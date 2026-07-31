`timescale 1ns / 1ps

`include "defines.vh"

module ALU (
    input  wire         rst,
    input  wire         clk,
    input  wire [ 4:0]  op,
    input  wire [31:0]  a,
    input  wire [31:0]  b,
    
    output reg  [31:0]  c,
    output reg          br,
    output wire         busy
);

    wire        mul_flag, mulu_flag;
    wire [63:0] mul_res;
    wire [65:0] mulu_res;
    wire        mul_busy, mulu_busy;
    wire        div_flag, divu_flag;
    wire [31:0] div_quo , divu_quo ;    // quotient
    wire [31:0] div_rem , divu_rem ;    // remainder
    wire        div_busy, divu_busy;
    reg  [ 4:0] op_r;
    reg         div_sign_r;
    reg         rem_sign_r;
    reg         div_by_zero_r;
    reg  [31:0] div_src_r;
    wire [31:0] div_x_abs;
    wire [31:0] div_y_abs;
    wire [31:0] div_quo_fix;
    wire [31:0] div_rem_fix;

    always @(*) begin
        case (op_r != 5'h0 ? op_r : op)
            `ALU_ADD  : c = a + b;
            `ALU_SUB  : c = a - b;
            `ALU_XOR  : c = a ^ b;
            `ALU_OR   : c = a | b;
            `ALU_AND  : c = a & b;
            `ALU_SLL  : c = a << b[4:0];
            `ALU_SRL  : c = a >> b[4:0];
            `ALU_SRA  : c = $signed(a) >>> b[4:0];
            `ALU_SLT  : c = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0;
            `ALU_SLTU : c = (a < b) ? 32'h1 : 32'h0;
            `ALU_MUL  : c = mul_res[31:0];
            `ALU_MULH : c = mul_res[63:32];
            `ALU_MULHU: c = mulu_res[63:32];
            `ALU_DIV  : c = div_by_zero_r ? 32'hffff_ffff : div_quo_fix;
            `ALU_DIVU : c = divu_quo;
            `ALU_REM  : c = div_by_zero_r ? div_src_r : div_rem_fix;
            `ALU_REMU : c = divu_rem;
            default   : c = 32'h0;
        endcase
    end

    always @(*) begin
        case (op)
            `ALU_EQ : br = a == b;
            `ALU_NE : br = a != b;
            `ALU_SLT : br = $signed(a) < $signed(b);   // Reused by blt.
            `ALU_SLTU: br = a < b;                     // Reused by bltu.
            `ALU_BGE : br = $signed(a) >= $signed(b);
            `ALU_BGEU: br = a >= b;
            default : br = 1'b0;
        endcase
    end

    assign mul_flag  = (op == `ALU_MUL) | (op == `ALU_MULH);
    assign mulu_flag = (op == `ALU_MULHU);
    assign div_flag  = (op == `ALU_DIV) | (op == `ALU_REM);
    assign divu_flag = (op == `ALU_DIVU) | (op == `ALU_REMU);
    assign busy      = mul_busy | mulu_busy | div_busy | divu_busy;
    assign div_x_abs = a[31] ? (~a + 1'b1) : a;
    assign div_y_abs = b[31] ? (~b + 1'b1) : b;
    assign div_quo_fix = div_sign_r ? (~div_quo + 1'b1) : div_quo;
    assign div_rem_fix = rem_sign_r ? (~div_rem + 1'b1) : div_rem;

    always @(posedge clk) begin
        if (rst) begin
            op_r <= 5'h0;
            div_sign_r    <= 1'b0;
            rem_sign_r    <= 1'b0;
            div_by_zero_r <= 1'b0;
            div_src_r     <= 32'h0;
        end else if (mul_flag | mulu_flag | div_flag | divu_flag) begin
            op_r <= op;
            div_sign_r    <= a[31] ^ b[31];
            rem_sign_r    <= a[31];
            div_by_zero_r <= (b == 32'h0);
            div_src_r     <= a;
        end else if (!busy) begin
            op_r <= 5'h0;
        end
    end

    multiplier #(32) U_mul (
        .clk    (clk),
        .rst    (rst),
        .x      (a),
        .y      (b),
        .start  (mul_flag),
        .z      (mul_res),
        .busy   (mul_busy)
    );

    multiplier #(33) U_mulu (
        .clk    (clk),
        .rst    (rst),
        .x      ({1'b0, a}),
        .y      ({1'b0, b}),
        .start  (mulu_flag),
        .z      (mulu_res),
        .busy   (mulu_busy)
    );

    divider #(32) U_div (
        .clk    (clk),
        .rst    (rst),
        .x      (div_x_abs),
        .y      (div_y_abs),
        .start  (div_flag),
        .z      (div_quo),
        .r      (div_rem),
        .busy   (div_busy)
    );

    divider #(32) U_divu (
        .clk    (clk),
        .rst    (rst),
        .x      (a),
        .y      (b),
        .start  (divu_flag),
        .z      (divu_quo),
        .r      (divu_rem),
        .busy   (divu_busy)
    );

endmodule
