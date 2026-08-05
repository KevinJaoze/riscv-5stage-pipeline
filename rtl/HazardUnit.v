`timescale 1ns / 1ps

`include "defines.vh"

module HazardUnit (
    input  wire [ 4:0] id_rs1,
    input  wire [ 4:0] id_rs2,
    input  wire        id_rf1,
    input  wire        id_rf2,

    input  wire        id_ex_valid,
    input  wire [ 4:0] id_ex_rd,
    input  wire        id_ex_rf_we,
    input  wire [ 2:0] id_ex_ram_rop,
    input  wire        id_ex_is_mul,
    input  wire        id_ex_is_div,
    input  wire        mul_div_done,

    input  wire        ex_mem_valid,
    input  wire [ 4:0] ex_mem_rd,
    input  wire        ex_mem_rf_we,
    input  wire [ 2:0] ex_mem_ram_rop,
    input  wire [ 3:0] ex_mem_ram_wop,
    input  wire        ldst_done,

    input  wire        mem_wb_valid,
    input  wire [ 4:0] mem_wb_rd,
    input  wire        mem_wb_rf_we,

    output wire        raw_stall,
    output wire        ldst_stall,
    output wire        mul_div_stall,
    output wire        pipeline_stall,
    output wire [ 1:0] rd1_sel,
    output wire [ 1:0] rd2_sel
);

    localparam [1:0] RD_SEL_RF  = 2'b00;
    localparam [1:0] RD_SEL_EX  = 2'b01;
    localparam [1:0] RD_SEL_MEM = 2'b10;
    localparam [1:0] RD_SEL_WB  = 2'b11;

    wire rs1_id_ex_hazard;
    wire rs2_id_ex_hazard;
    wire rs1_id_mem_hazard;
    wire rs2_id_mem_hazard;
    wire rs1_id_wb_hazard;
    wire rs2_id_wb_hazard;
    wire raw_a_hazard;
    wire raw_b_hazard;
    wire raw_c_hazard;
    wire id_ex_load;
    wire id_ex_mul_div;
    wire mem_is_ld_st;
    wire ex_forward_valid;
    wire mem_forward_valid;
    wire wb_forward_valid;
    wire rs1_forward_ex;
    wire rs2_forward_ex;
    wire rs1_forward_mem;
    wire rs2_forward_mem;
    wire rs1_forward_wb;
    wire rs2_forward_wb;

    assign rs1_id_ex_hazard  = (id_ex_rd  == id_rs1) & id_ex_rf_we  & id_rf1 & (id_ex_rd  != 5'h0) & id_ex_valid;
    assign rs2_id_ex_hazard  = (id_ex_rd  == id_rs2) & id_ex_rf_we  & id_rf2 & (id_ex_rd  != 5'h0) & id_ex_valid;
    assign rs1_id_mem_hazard = (ex_mem_rd == id_rs1) & ex_mem_rf_we & id_rf1 & (ex_mem_rd != 5'h0) & ex_mem_valid;
    assign rs2_id_mem_hazard = (ex_mem_rd == id_rs2) & ex_mem_rf_we & id_rf2 & (ex_mem_rd != 5'h0) & ex_mem_valid;
    assign rs1_id_wb_hazard  = (mem_wb_rd == id_rs1) & mem_wb_rf_we & id_rf1 & (mem_wb_rd != 5'h0) & mem_wb_valid;
    assign rs2_id_wb_hazard  = (mem_wb_rd == id_rs2) & mem_wb_rf_we & id_rf2 & (mem_wb_rd != 5'h0) & mem_wb_valid;

    assign raw_a_hazard      = rs1_id_ex_hazard  | rs2_id_ex_hazard;
    assign raw_b_hazard      = rs1_id_mem_hazard | rs2_id_mem_hazard;
    assign raw_c_hazard      = rs1_id_wb_hazard  | rs2_id_wb_hazard;

    assign id_ex_load        = id_ex_valid & (id_ex_ram_rop != `RAM_EXT_N);
    assign id_ex_mul_div     = id_ex_valid & (id_ex_is_mul | id_ex_is_div);
    assign mem_is_ld_st      = ex_mem_valid & ((ex_mem_ram_rop != `RAM_EXT_N) | (ex_mem_ram_wop != `RAM_WE_N));

    assign raw_stall         = raw_a_hazard & id_ex_load;
    assign ldst_stall        = mem_is_ld_st & !ldst_done;
    assign mul_div_stall     = id_ex_mul_div & !mul_div_done;
    assign pipeline_stall    = raw_stall | ldst_stall | mul_div_stall;

    assign ex_forward_valid  = id_ex_rf_we & !id_ex_load & (!id_ex_mul_div | mul_div_done);
    assign mem_forward_valid = ex_mem_rf_we & ((ex_mem_ram_rop == `RAM_EXT_N) | ldst_done);
    assign wb_forward_valid  = mem_wb_rf_we;

    assign rs1_forward_ex    = rs1_id_ex_hazard  & ex_forward_valid;
    assign rs2_forward_ex    = rs2_id_ex_hazard  & ex_forward_valid;
    assign rs1_forward_mem   = rs1_id_mem_hazard & mem_forward_valid;
    assign rs2_forward_mem   = rs2_id_mem_hazard & mem_forward_valid;
    assign rs1_forward_wb    = rs1_id_wb_hazard  & wb_forward_valid;
    assign rs2_forward_wb    = rs2_id_wb_hazard  & wb_forward_valid;

    assign rd1_sel           = rs1_forward_ex  ? RD_SEL_EX  :
                               rs1_forward_mem ? RD_SEL_MEM :
                               rs1_forward_wb  ? RD_SEL_WB  : RD_SEL_RF;
    assign rd2_sel           = rs2_forward_ex  ? RD_SEL_EX  :
                               rs2_forward_mem ? RD_SEL_MEM :
                               rs2_forward_wb  ? RD_SEL_WB  : RD_SEL_RF;

endmodule
