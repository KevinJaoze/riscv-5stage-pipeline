`timescale 1ns / 1ps

`include "defines.vh"

module NPC (
    input  wire [ 1:0]  op,
    input  wire [31:0]  pc,
    input  wire [31:0]  offset,
    input  wire [31:0]  jalr_target,    // Exclusive input for jalr next-PC target.
    input  wire         br,
    
    output reg  [31:0]  npc,
    output wire [31:0]  pc4
);

    assign pc4 = pc + 32'h4;

    always @(*) begin
        case (op)
            `NPC_PC4: npc = pc4;
            `NPC_JALR: npc = jalr_target & ~32'h1;
            `NPC_BRA: npc = br ? pc + offset : pc4;
            `NPC_JMP: npc = pc + offset;
            default:  npc = pc4;
        endcase
    end
    
endmodule
