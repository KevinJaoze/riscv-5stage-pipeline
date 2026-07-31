`timescale 1ns / 1ps

module divider #(
    parameter WIDTH = 32
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [WIDTH-1:0] x,
    input  wire [WIDTH-1:0] y,
    input  wire       start,
    output wire [WIDTH-1:0] z,
    output reg  [WIDTH-1:0] r,
    output reg        busy     
);

    reg  [WIDTH-1:0] dividend;
    reg  [WIDTH-1:0] divisor;
    reg  [WIDTH-1:0] quotient;
    reg  [WIDTH-1:0] cnt;
    reg  [WIDTH  :0] remainder;
    wire [WIDTH  :0] remainder_shift;
    wire [WIDTH  :0] remainder_sub;

    assign z = quotient;
    assign remainder_shift = {remainder[WIDTH-1:0], dividend[WIDTH-1]};
    assign remainder_sub   = remainder_shift - {1'b0, divisor};

    // DONE: Implement unsigned restoring division with start/busy handshake.
    always @(posedge clk) begin
        if (rst) begin
            dividend  <= {WIDTH{1'b0}};
            divisor   <= {WIDTH{1'b0}};
            quotient  <= {WIDTH{1'b0}};
            r         <= {WIDTH{1'b0}};
            cnt       <= {WIDTH{1'b0}};
            remainder <= {(WIDTH+1){1'b0}};
            busy      <= 1'b0;
        end else if (start) begin
            dividend  <= x;
            divisor   <= y;
            quotient  <= {WIDTH{1'b0}};
            r         <= {WIDTH{1'b0}};
            cnt       <= WIDTH;
            remainder <= {(WIDTH+1){1'b0}};
            busy      <= 1'b1;

            if (y == {WIDTH{1'b0}}) begin
                quotient <= {WIDTH{1'b1}};
                r        <= x;
                busy     <= 1'b0;
            end
        end else if (busy) begin
            dividend <= {dividend[WIDTH-2:0], 1'b0};
            cnt      <= cnt - 1'b1;

            if (remainder_sub[WIDTH] == 1'b0) begin
                remainder <= remainder_sub;
                quotient  <= {quotient[WIDTH-2:0], 1'b1};
            end else begin
                remainder <= remainder_shift;
                quotient  <= {quotient[WIDTH-2:0], 1'b0};
            end

            if (cnt == {{(WIDTH-1){1'b0}}, 1'b1}) begin
                if (remainder_sub[WIDTH] == 1'b0)
                    r <= remainder_sub[WIDTH-1:0];
                else
                    r <= remainder_shift[WIDTH-1:0];
                busy <= 1'b0;
            end
        end
    end
	
endmodule
