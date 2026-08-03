`timescale 1ns / 1ps

`include "defines.vh"

module NPC (
    input  wire [ 1:0]  op,
    input  wire [31:0]  pc4,
    input  wire [31:0]  bj_target,
    input  wire [31:0]  jalr_target,
    input  wire         br,
    
    output reg  [31:0]  npc
);

    always @(*) begin
        case (op)
            `NPC_PC4 : npc = pc4;
            `NPC_JALR: npc = jalr_target;
            `NPC_BRA : npc = br ? bj_target : pc4;
            `NPC_JMP : npc = bj_target;
            default  : npc = pc4;
        endcase
    end
    
endmodule
