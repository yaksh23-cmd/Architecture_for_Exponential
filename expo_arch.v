// Code your design here

module top_design(
  input [15:0] in,
  output [15:0] out ,
  output reg [15:0] final_int,
  output reg [15:0] result_mult
);
  
  wire sign_bit = in[15];
  
  //multiplication operation
    reg Exception;
    reg Overflow;
    reg Underflow;
 // reg [15:0] result_mult;
   
  wire [15:0] b;
  assign b = 16'b0011110111000011;  //approx
  multiplication_16 m1( .a_operand(in),
                       .b_operand(b),
                      .Exception(Exception),
                      .Overflow(Overflow),
                      .Underflow(Underflow),
                      .result(result_mult)
                     );
  
  //solving integer part
  
   reg [15:0] result_int;
  pow2_integer_part_only p(
                           .x_in(result_mult),
                           .result(result_int)
                          );
  
  //converting integer part answer into floating point half precision format
  
  //reg [15:0] final_int;
  int16_to_halfprecision converter(
                                   .int_in(result_int),
                                   .half_out(final_int)
                                  );
  
  //calculating fractional part 
  reg [15:0] final_float;
  reg [15:0] final_float_ans;
  
  fp16_subtractor cs(
    .a(result_mult),     // Operand A
    .b(final_int),     // Operand B
    .result(final_float) // A - B
);
    reg [15:0] CONST_9567_Q14 =16'b0011101110100111;
    
     half_precision_adder gp(
      .a(final_float),     // Operand A
      .b(CONST_9567_Q14),     // Operand B
      .result(final_float_ans) // A + B
);
    
    
  //multiplying the final answers 
  reg Exception1;
    reg Overflow1;
    reg Underflow1;
  multiplication_16 m2( .a_operand(final_int),
                       .b_operand(final_float_ans),
                       .Exception(Exception1),
                       .Overflow(Overflow1),
                       .Underflow(Underflow1),
                       .result(out)
                     );
  
endmodule
  
  module fp16_subtractor (
    input  [15:0] a,     // Operand A
    input  [15:0] b,     // Operand B
    output [15:0] result // A - B
);

    // Internal fields
    wire sign_a = a[15];
    wire sign_b = b[15];
    wire [4:0] exp_a = a[14:10];
    wire [4:0] exp_b = b[14:10];
    wire [10:0] frac_a = {1'b1, a[9:0]}; // Implicit 1 for normalized
    wire [10:0] frac_b = {1'b1, b[9:0]};

    wire [4:0] exp_diff;
    wire [10:0] frac_b_shifted;
    wire [11:0] frac_diff;
    reg [4:0] exp_result;
    reg [10:0] frac_result;
    reg sign_result;

    // Step 1: Align exponents
    assign exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);
    assign frac_b_shifted = (exp_a > exp_b) ? (frac_b >> exp_diff) : frac_b;
    wire [10:0] aligned_frac_a = (exp_a > exp_b) ? frac_a : (frac_a >> exp_diff);

    // Step 2: Perform subtraction
    assign frac_diff = aligned_frac_a - frac_b_shifted;

    always @(*) begin
        if (exp_a > exp_b) begin
            exp_result = exp_a;
        end else begin
            exp_result = exp_b;
        end

        // Determine signa
        if (a == b) begin
            frac_result = 0;
            exp_result = 0;
            sign_result = 0;
        end else if (frac_a >= frac_b_shifted) begin
            frac_result = frac_diff[10:0];
            sign_result = sign_a;
        end else begin
            frac_result = -frac_diff[10:0];
            sign_result = ~sign_a; // Flip sign
        end

        // Normalize result (basic leading zero detection)
        while (frac_result[10] == 0 && exp_result > 0) begin
            frac_result = frac_result << 1;
            exp_result = exp_result - 1;
        end
    end

    // Pack the result
    assign result = {sign_result, exp_result, frac_result[9:0]};

endmodule


// Code your design here
module half_precision_adder (
    input  [15:0] a,       // Half-precision input 1
    input  [15:0] b,       // Half-precision input 2
    output [15:0] result   // Half-precision output
);

    // Internal fields
    reg sign_a, sign_b, sign_r;
    reg [4:0] exp_a, exp_b, exp_r;
    reg [10:0] mant_a, mant_b;
    reg [11:0] mant_sum;
    reg [9:0] mant_r;

    reg [15:0] res;

    always @(*) begin
        // Step 1: Extract sign, exponent, mantissa
        sign_a = a[15];
        sign_b = b[15];
        exp_a  = a[14:10];
        exp_b  = b[14:10];
        mant_a = {1'b1, a[9:0]}; // Prepend implicit 1
        mant_b = {1'b1, b[9:0]};

        // Step 2: Align exponents
        if (exp_a > exp_b) begin
            mant_b = mant_b >> (exp_a - exp_b);
            exp_r = exp_a;
        end else begin
            mant_a = mant_a >> (exp_b - exp_a);
            exp_r = exp_b;
        end

        // Step 3: Perform addition (assuming same sign for simplicity)
        mant_sum = mant_a + mant_b;

        // Step 4: Normalize result
        if (mant_sum[11] == 1) begin
            mant_sum = mant_sum >> 1;
            exp_r = exp_r + 1;
        end

        mant_r = mant_sum[9:0];
        sign_r = 0; // Assuming both inputs are positive

        // Step 5: Assemble result
        res = {sign_r, exp_r, mant_r};
    end

    assign result = res;

endmodule




// Code your design here
module int16_to_halfprecision (
    input  wire signed [15:0] int_in,
    output reg  [15:0] half_out
);

    reg [15:0] abs_val;
    reg [4:0]  msb_pos;
    reg [9:0]  mantissa;
    reg [4:0]  biased_exp;
    integer    i;

    always @(*) begin
        if (int_in == 16'd0) begin
            half_out = 16'd0;
        end else begin
            // Step 1: Get sign and absolute value
            half_out[15] = int_in[15];               // Sign bit
            abs_val = int_in[15] ? -int_in : int_in;

            // Step 2: Find MSB position
            msb_pos = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                if (abs_val[i] == 1'b1 && msb_pos == 0)
                    msb_pos = i[4:0];
            end

            // Step 3: Biased exponent
            biased_exp = msb_pos + 5'd15;
            half_out[14:10] = biased_exp;

            // Step 4: Mantissa extraction
            if (msb_pos > 10)
                mantissa = (abs_val >> (msb_pos - 10)) & 10'h3FF;
            else
                mantissa = (abs_val << (10 - msb_pos)) & 10'h3FF;

            half_out[9:0] = mantissa;
        end
    end

endmodule


// Code your design here
module pow2_integer_part_only (
    input  wire [15:0] x_in,      // 16-bit half-precision float
    output reg  [15:0] result     // 16-bit output = 2^floor(x)
);

    wire sign;
    wire [4:0] exponent;
    wire [9:0] mantissa;
    reg  [15:0] int_part;
    real value;

    assign sign     = x_in[15];
    assign exponent = x_in[14:10];
    assign mantissa = x_in[9:0];

    always @(*) begin
        result = 16'd0;

        if (sign == 1'b1 || exponent == 5'd0) begin
            // Negative or subnormal/zero
            result = 16'd1;
        end else begin
            // Normalized: 1.mantissa × 2^(exp - 15)
            // Convert to real value
            value = (1.0 + mantissa / 1024.0) * (2.0 ** (exponent - 15));
            int_part = $floor(value);

            if (int_part > 15)
                result = 16'd0; // Avoid overflow
            else
                result = 16'd1 << int_part;
        end
    end

endmodule


module multiplication_16(
    input [15:0] a_operand,
    input [15:0] b_operand,
    output Exception,
    output Overflow,
    output Underflow,
    output [15:0] result
);
    localparam EXP_BIAS = 15;

    wire sign, normalised, zero, round_bit;
    wire [10:0] operand_a, operand_b;
    wire [21:0] product, product_shifted;
    wire [9:0] guard_bits;
    wire [5:0] sum_exponent;
    wire [4:0] exponent;
    wire [9:0] mantissa;

    wire a_is_nan = (a_operand[14:10] == 5'b11111) && (a_operand[9:0] != 0);
    wire b_is_nan = (b_operand[14:10] == 5'b11111) && (b_operand[9:0] != 0);
    wire a_is_inf = (a_operand[14:10] == 5'b11111) && (a_operand[9:0] == 0);
    wire b_is_inf = (b_operand[14:10] == 5'b11111) && (b_operand[9:0] == 0);
    wire a_is_zero = (a_operand[14:0] == 15'd0);
    wire b_is_zero = (b_operand[14:0] == 15'd0);

    assign sign = a_operand[15] ^ b_operand[15];
    assign Exception = a_is_nan | b_is_nan | (a_is_inf & b_is_zero) | (a_is_zero & b_is_inf);

    assign operand_a = (a_operand[14:10] == 0) ? {1'b0, a_operand[9:0]} : {1'b1, a_operand[9:0]};
    assign operand_b = (b_operand[14:10] == 0) ? {1'b0, b_operand[9:0]} : {1'b1, b_operand[9:0]};

    assign product = operand_a * operand_b;

    assign normalised = product[21];
    assign product_shifted = normalised ? product : product << 1;

    assign guard_bits = product_shifted[10:1];
    assign round_bit = |guard_bits;

    wire [9:0] mantissa_unrounded = product_shifted[20:11];
    wire [10:0] mantissa_rounded = mantissa_unrounded + (product_shifted[10] & round_bit);

    wire mantissa_carry = mantissa_rounded[10];
    assign mantissa = mantissa_carry ? 10'd0 : mantissa_rounded[9:0];

    wire [5:0] base_exponent = a_operand[14:10] + b_operand[14:10] - EXP_BIAS + normalised + mantissa_carry;
    assign exponent = base_exponent[4:0];

    assign zero = (mantissa == 0 && exponent == 0);

    // ✅ Only assert these if no Exception
    assign Overflow = ~Exception & (base_exponent[5] & ~base_exponent[4]) & ~zero;
    assign Underflow = ~Exception & (base_exponent[5] & base_exponent[4]) & ~zero;

    assign result = Exception ? 16'h7E00 :
                    a_is_inf | b_is_inf ? {sign, 5'b11111, 10'd0} :
                    a_is_zero | b_is_zero ? {sign, 15'd0} :
                    Overflow ? {sign, 5'b11111, 10'd0} :
                    Underflow ? {sign, 15'd0} :
                    {sign, exponent, mantissa};

endmodule
