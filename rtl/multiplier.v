`timescale 1ns / 1ps

module multiplier #(
    parameter WIDTH = 32,
    parameter O_WID = 2*WIDTH
)(
    input  wire        clk,
	input  wire        rst,
	input  wire [WIDTH-1:0] x,
	input  wire [WIDTH-1:0] y,
	input  wire        start,
	output reg  [O_WID-1:0] z,
	output wire        busy 
);

    reg [O_WID  :0] product;
    reg [O_WID  :0] multiplicand;
    reg [WIDTH    :0] multiplier;
    reg [WIDTH-1  :0] cnt;
    reg               busy_r;
    wire [O_WID :0] product_add;
    wire [O_WID :0] product_sub;

    assign busy = busy_r;
    assign product_add = product + multiplicand;
    assign product_sub = product - multiplicand;

    always @(posedge clk) begin
        if (rst) begin
            z            <= {O_WID{1'b0}};
            product      <= {(O_WID+1){1'b0}};
            multiplicand <= {(O_WID+1){1'b0}};
            multiplier   <= {(WIDTH+1){1'b0}};
            cnt          <= {WIDTH{1'b0}};
            busy_r       <= 1'b0;
        end else if (start) begin
            product      <= {(O_WID+1){1'b0}};
            multiplicand <= {{WIDTH{x[WIDTH-1]}}, x, 1'b0};
            multiplier   <= {y, 1'b0};
            cnt          <= {WIDTH{1'b0}};
            busy_r       <= 1'b1;
        end else if (busy_r) begin
            case (multiplier[1:0])
                2'b01  : product <= product_add;
                2'b10  : product <= product_sub;
                default: product <= product;
            endcase

            multiplicand <= multiplicand << 1;
            multiplier   <= {multiplier[WIDTH], multiplier[WIDTH:1]};

            if (cnt == WIDTH - 1) begin
                case (multiplier[1:0])
                    2'b01  : z <= product_add[O_WID:1];
                    2'b10  : z <= product_sub[O_WID:1];
                    default: z <= product[O_WID:1];
                endcase
                busy_r <= 1'b0;
            end

            cnt <= cnt + 1'b1;
        end
    end
    
endmodule
