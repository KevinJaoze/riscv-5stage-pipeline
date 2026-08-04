`timescale 1ns / 1ps

`include "defines.vh"

module cpu_core(
    input  wire         cpu_rst,
    input  wire         cpu_clk,

    // Instruction Fetch Interface
    output wire         ifetch_req   /* verilator public */ ,
    output wire [31:0]  ifetch_addr  /* verilator public */ ,
    input  wire         ifetch_valid /* verilator public */ ,
    input  wire [31:0]  ifetch_inst,

    // Data Access Interface
    output reg  [ 3:0]  daccess_ren,
    output reg  [31:0]  daccess_addr,
    input  wire         daccess_rvalid,
    input  wire [31:0]  daccess_rdata,
    output reg  [ 3:0]  daccess_wen,
    output reg  [31:0]  daccess_wdata,
    input  wire         daccess_wresp
);

    localparam [31:0] NOP_INST = 32'h0000_0013; // addi x0, x0, 0

    // IF stage.
    wire [31:0] pc;
    wire [31:0] npc;
    wire [31:0] pc_npc;
    wire [31:0] pc4;
    wire [31:0] fetch_pc4;
    wire        ex_bj_f;
    wire [31:0] ex_bj_target;
    wire        flush_pipeline;
    wire        pipeline_stop;
    wire        pause_ifetch;
    wire        refetch_if;
    reg         rst_r;
    reg  [31:0] if_pc;
    reg  [31:0] if_pc4;
    reg         refetch_valid;
    reg  [31:0] refetch_pc;

    wire first_req = rst_r & !cpu_rst;

    always @(posedge cpu_clk) begin
        rst_r <= cpu_rst;
    end

    assign pause_ifetch  = pipeline_stop;
    assign refetch_if    = refetch_valid & !pause_ifetch;
    assign ifetch_req    = ex_bj_f | (!pause_ifetch & (first_req | ifetch_valid | refetch_if));
    assign ifetch_addr   = ex_bj_f ? ex_bj_target :
                           refetch_if ? refetch_pc : pc;
    assign pc4         = pc + 32'h4;
    assign fetch_pc4   = ifetch_addr + 32'h4;
    assign pc_npc      = (ex_bj_f | refetch_if) ? fetch_pc4 : npc;

    PC U_PC (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .npc        (pc_npc),
        .fetch      (ifetch_req),
        .pc         (pc)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            if_pc  <= 32'h0;
            if_pc4 <= 32'h0;
        end else if (ifetch_req) begin
            if_pc  <= ifetch_addr;
            if_pc4 <= fetch_pc4;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            refetch_valid <= 1'b0;
            refetch_pc    <= 32'h0;
        end else if (flush_pipeline) begin
            refetch_valid <= 1'b0;
            refetch_pc    <= 32'h0;
        end else if (pipeline_stop & ifetch_valid) begin
            refetch_valid <= 1'b1;
            refetch_pc    <= if_pc;
        end else if (refetch_if & ifetch_req) begin
            refetch_valid <= 1'b0;
        end
    end

    // IF/ID pipeline register.
    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_pc4;
    reg [31:0] if_id_inst;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_pc4   <= 32'h0;
            if_id_inst  <= NOP_INST;
        end else if (flush_pipeline) begin
            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_pc4   <= 32'h0;
            if_id_inst  <= NOP_INST;
        end else if (pipeline_stop) begin
            if_id_valid <= if_id_valid;
            if_id_pc    <= if_id_pc;
            if_id_pc4   <= if_id_pc4;
            if_id_inst  <= if_id_inst;
        end else begin
            if_id_valid <= ifetch_valid;
            if_id_pc    <= if_pc;
            if_id_pc4   <= if_pc4;
            if_id_inst  <= ifetch_valid ? ifetch_inst : NOP_INST;
        end
    end

    // ID stage.
    wire [ 1:0] id_npc_op;
    wire [ 1:0] id_rf_wsel;
    wire [ 2:0] id_sext_op;
    wire [ 4:0] id_alu_op;
    wire        id_alua_sel;
    wire        id_alub_sel;
    wire [ 2:0] id_ram_rop;
    wire [ 3:0] id_ram_wop;
    wire        id_is_mul;
    wire        id_is_div;
    wire        id_rf_we;
    wire [31:0] id_rf_rd1;
    wire [31:0] id_rf_rd2;
    wire [31:0] id_ext;
    wire [ 4:0] id_rs1;
    wire [ 4:0] id_rs2;
    wire [ 4:0] id_rd;
    wire        id_rf1;
    wire        id_rf2;
    wire        rs1_id_ex_hazard;
    wire        rs2_id_ex_hazard;
    wire        rs1_id_mem_hazard;
    wire        rs2_id_mem_hazard;
    wire        rs1_id_wb_hazard;
    wire        rs2_id_wb_hazard;
    wire        raw_a_hazard;
    wire        raw_b_hazard;
    wire        raw_c_hazard;

    assign id_rs1 = if_id_inst[19:15];
    assign id_rs2 = if_id_inst[24:20];
    assign id_rd  = if_id_inst[11:7];
    assign id_rf1 = (if_id_inst[6:0] == 7'b0110011) |
                    (if_id_inst[6:0] == 7'b0010011) |
                    (if_id_inst[6:0] == 7'b0000011) |
                    (if_id_inst[6:0] == 7'b0100011) |
                    (if_id_inst[6:0] == 7'b1100011) |
                    (if_id_inst[6:0] == 7'b1100111);
    assign id_rf2 = (if_id_inst[6:0] == 7'b0110011) |
                    (if_id_inst[6:0] == 7'b0100011) |
                    (if_id_inst[6:0] == 7'b1100011);

    // WB-stage signals feed the register file write port.
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_pc4;
    reg [31:0] mem_wb_alu_c;
    reg [31:0] mem_wb_ram_ext;
    reg [31:0] mem_wb_lui_imm;
    reg [ 4:0] mem_wb_rd;
    reg [ 1:0] mem_wb_rf_wsel;
    reg        mem_wb_rf_we;
    reg        mem_wb_valid;
    reg [31:0] rf_wdata;

    Controller U_CU (
        .opcode         (if_id_inst[6:0]),
        .funct3         (if_id_inst[14:12]),
        .funct7         (if_id_inst[31:25]),
        .npc_op         (id_npc_op),
        .sext_op        (id_sext_op),
        .alu_op         (id_alu_op),
        .alua_sel       (id_alua_sel),
        .alub_sel       (id_alub_sel),
        .is_mul         (id_is_mul),
        .is_div         (id_is_div),
        .ram_r_op       (id_ram_rop),
        .ram_w_op       (id_ram_wop),
        .rf_we          (id_rf_we),
        .rf_wsel        (id_rf_wsel)
    );

    RF U_RF (
        .clk        (cpu_clk),
        .rR1        (if_id_inst[19:15]),
        .rR2        (if_id_inst[24:20]),
        .rD1        (id_rf_rd1),
        .rD2        (id_rf_rd2),
        .we         (mem_wb_rf_we & mem_wb_valid),
        .wR         (mem_wb_rd),
        .wD         (rf_wdata)
    );

    SEXT U_SEXT (
        .op         (id_sext_op),
        .imm        (if_id_inst[31:7]),
        .ext        (id_ext)
    );

    // ID/EX pipeline register.
    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_pc4;
    reg [31:0] id_ex_rs1;
    reg [31:0] id_ex_rs2;
    reg [31:0] id_ex_ext;
    reg [31:0] id_ex_lui_imm;
    reg [ 4:0] id_ex_rd;
    reg [ 1:0] id_ex_npc_op;
    reg [ 1:0] id_ex_rf_wsel;
    reg [ 4:0] id_ex_alu_op;
    reg        id_ex_alua_sel;
    reg        id_ex_alub_sel;
    reg [ 2:0] id_ex_ram_rop;
    reg [ 3:0] id_ex_ram_wop;
    reg        id_ex_rf_we;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            id_ex_valid    <= 1'b0;
            id_ex_pc       <= 32'h0;
            id_ex_pc4      <= 32'h0;
            id_ex_rs1      <= 32'h0;
            id_ex_rs2      <= 32'h0;
            id_ex_ext      <= 32'h0;
            id_ex_lui_imm  <= 32'h0;
            id_ex_rd       <= 5'h0;
            id_ex_npc_op   <= `NPC_PC4;
            id_ex_rf_wsel  <= `WB_ALU;
            id_ex_alu_op   <= `ALU_ADD;
            id_ex_alua_sel <= `ALU_A_RS1;
            id_ex_alub_sel <= `ALU_B_RS2;
            id_ex_ram_rop  <= `RAM_EXT_N;
            id_ex_ram_wop  <= `RAM_WE_N;
            id_ex_rf_we    <= 1'b0;
        end else if (flush_pipeline) begin
            id_ex_valid    <= 1'b0;
            id_ex_pc       <= 32'h0;
            id_ex_pc4      <= 32'h0;
            id_ex_rs1      <= 32'h0;
            id_ex_rs2      <= 32'h0;
            id_ex_ext      <= 32'h0;
            id_ex_lui_imm  <= 32'h0;
            id_ex_rd       <= 5'h0;
            id_ex_npc_op   <= `NPC_PC4;
            id_ex_rf_wsel  <= `WB_ALU;
            id_ex_alu_op   <= `ALU_ADD;
            id_ex_alua_sel <= `ALU_A_RS1;
            id_ex_alub_sel <= `ALU_B_RS2;
            id_ex_ram_rop  <= `RAM_EXT_N;
            id_ex_ram_wop  <= `RAM_WE_N;
            id_ex_rf_we    <= 1'b0;
        end else if (pipeline_stop) begin
            id_ex_valid    <= 1'b0;
            id_ex_pc       <= 32'h0;
            id_ex_pc4      <= 32'h0;
            id_ex_rs1      <= 32'h0;
            id_ex_rs2      <= 32'h0;
            id_ex_ext      <= 32'h0;
            id_ex_lui_imm  <= 32'h0;
            id_ex_rd       <= 5'h0;
            id_ex_npc_op   <= `NPC_PC4;
            id_ex_rf_wsel  <= `WB_ALU;
            id_ex_alu_op   <= `ALU_ADD;
            id_ex_alua_sel <= `ALU_A_RS1;
            id_ex_alub_sel <= `ALU_B_RS2;
            id_ex_ram_rop  <= `RAM_EXT_N;
            id_ex_ram_wop  <= `RAM_WE_N;
            id_ex_rf_we    <= 1'b0;
        end else begin
            id_ex_valid    <= if_id_valid;
            id_ex_pc       <= if_id_pc;
            id_ex_pc4      <= if_id_pc4;
            id_ex_rs1      <= id_rf_rd1;
            id_ex_rs2      <= id_rf_rd2;
            id_ex_ext      <= id_ext;
            id_ex_lui_imm  <= id_ext;
            id_ex_rd       <= if_id_inst[11:7];
            id_ex_npc_op   <= id_npc_op;
            id_ex_rf_wsel  <= id_rf_wsel;
            id_ex_alu_op   <= id_alu_op;
            id_ex_alua_sel <= id_alua_sel;
            id_ex_alub_sel <= id_alub_sel;
            id_ex_ram_rop  <= id_ram_rop;
            id_ex_ram_wop  <= id_ram_wop;
            id_ex_rf_we    <= id_rf_we;
        end
    end

    // EX stage.
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_c;
    wire        br;
    wire        mul_div_busy;
    wire [31:0] bj_target;
    wire [31:0] jalr_target;

    assign alu_a       = id_ex_alua_sel ? id_ex_pc  : id_ex_rs1;
    assign alu_b       = id_ex_alub_sel ? id_ex_ext : id_ex_rs2;
    assign bj_target   = id_ex_pc + id_ex_ext;
    assign jalr_target = alu_c & ~32'h1;
    assign ex_bj_f     = id_ex_valid & (((id_ex_npc_op == `NPC_BRA) & br) |
                                         (id_ex_npc_op == `NPC_JMP) |
                                         (id_ex_npc_op == `NPC_JALR));
    assign ex_bj_target = (id_ex_npc_op == `NPC_JALR) ? jalr_target : bj_target;
    assign flush_pipeline = ex_bj_f;

    ALU U_ALU (
        .rst        (cpu_rst),
        .clk        (cpu_clk),
        .op         (id_ex_alu_op),
        .a          (alu_a),
        .b          (alu_b),
        .br         (br),
        .c          (alu_c),
        .busy       (mul_div_busy)
    );

    NPC U_NPC (
        .op         (id_ex_npc_op),
        .pc4        (pc4),
        .bj_target  (bj_target),
        .jalr_target(jalr_target),
        .br         (br),
        .npc        (npc)
    );

    // EX/MEM pipeline register.
    reg        ex_mem_valid;
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_pc4;
    reg [31:0] ex_mem_alu_c;
    reg [31:0] ex_mem_rs2;
    reg [31:0] ex_mem_lui_imm;
    reg [ 4:0] ex_mem_rd;
    reg [ 1:0] ex_mem_rf_wsel;
    reg [ 2:0] ex_mem_ram_rop;
    reg [ 3:0] ex_mem_ram_wop;
    reg        ex_mem_rf_we;

    assign rs1_id_ex_hazard  = (id_ex_rd  == id_rs1) & id_ex_rf_we  & id_rf1 & (id_ex_rd  != 5'h0) & id_ex_valid;
    assign rs2_id_ex_hazard  = (id_ex_rd  == id_rs2) & id_ex_rf_we  & id_rf2 & (id_ex_rd  != 5'h0) & id_ex_valid;
    assign rs1_id_mem_hazard = (ex_mem_rd == id_rs1) & ex_mem_rf_we & id_rf1 & (ex_mem_rd != 5'h0) & ex_mem_valid;
    assign rs2_id_mem_hazard = (ex_mem_rd == id_rs2) & ex_mem_rf_we & id_rf2 & (ex_mem_rd != 5'h0) & ex_mem_valid;
    assign rs1_id_wb_hazard  = (mem_wb_rd == id_rs1) & mem_wb_rf_we & id_rf1 & (mem_wb_rd != 5'h0) & mem_wb_valid;
    assign rs2_id_wb_hazard  = (mem_wb_rd == id_rs2) & mem_wb_rf_we & id_rf2 & (mem_wb_rd != 5'h0) & mem_wb_valid;
    assign raw_a_hazard      = rs1_id_ex_hazard  | rs2_id_ex_hazard;
    assign raw_b_hazard      = rs1_id_mem_hazard | rs2_id_mem_hazard;
    assign raw_c_hazard      = rs1_id_wb_hazard  | rs2_id_wb_hazard;
    assign pipeline_stop     = raw_a_hazard | raw_b_hazard | raw_c_hazard;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            ex_mem_valid   <= 1'b0;
            ex_mem_pc      <= 32'h0;
            ex_mem_pc4     <= 32'h0;
            ex_mem_alu_c   <= 32'h0;
            ex_mem_rs2     <= 32'h0;
            ex_mem_lui_imm <= 32'h0;
            ex_mem_rd      <= 5'h0;
            ex_mem_rf_wsel <= `WB_ALU;
            ex_mem_ram_rop <= `RAM_EXT_N;
            ex_mem_ram_wop <= `RAM_WE_N;
            ex_mem_rf_we   <= 1'b0;
        end else begin
            ex_mem_valid   <= id_ex_valid;
            ex_mem_pc      <= id_ex_pc;
            ex_mem_pc4     <= id_ex_pc4;
            ex_mem_alu_c   <= alu_c;
            ex_mem_rs2     <= id_ex_rs2;
            ex_mem_lui_imm <= id_ex_lui_imm;
            ex_mem_rd      <= id_ex_rd;
            ex_mem_rf_wsel <= id_ex_rf_wsel;
            ex_mem_ram_rop <= id_ex_ram_rop;
            ex_mem_ram_wop <= id_ex_ram_wop;
            ex_mem_rf_we   <= id_ex_rf_we;
        end
    end

    // MEM stage.
    wire [ 3:0] da_ren;
    wire [31:0] da_addr;
    wire [ 3:0] da_wen;
    wire [31:0] da_wdata;
    wire [31:0] ram_ext;

    MREQ U_MEM_REQ (
        .ram_addr   (ex_mem_alu_c),

        .ram_rop    (ex_mem_ram_rop),
        .da_ren     (da_ren),
        .da_addr    (da_addr),

        .ram_wop    (ex_mem_ram_wop),
        .ram_wdata  (ex_mem_rs2),
        .da_wen     (da_wen),
        .da_wdata   (da_wdata)
    );

    MEXT U_MEM_EXT (
        .op             (ex_mem_ram_rop),
        .din            (daccess_rdata),
        .byte_offs      (ex_mem_alu_c[1:0]),
        .ext            (ram_ext)
    );

    // Registered external data interface.
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            daccess_ren   <= 4'h0;
            daccess_addr  <= 32'h0;
            daccess_wen   <= 4'h0;
            daccess_wdata <= 32'h0;
        end else begin
            daccess_ren   <= da_ren;
            daccess_addr  <= da_addr;
            daccess_wen   <= da_wen;
            daccess_wdata <= da_wdata;
        end
    end

    // MEM/WB pipeline register.
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            mem_wb_valid   <= 1'b0;
            mem_wb_pc      <= 32'h0;
            mem_wb_pc4     <= 32'h0;
            mem_wb_alu_c   <= 32'h0;
            mem_wb_ram_ext <= 32'h0;
            mem_wb_lui_imm <= 32'h0;
            mem_wb_rd      <= 5'h0;
            mem_wb_rf_wsel <= `WB_ALU;
            mem_wb_rf_we   <= 1'b0;
        end else begin
            mem_wb_valid   <= ex_mem_valid;
            mem_wb_pc      <= ex_mem_pc;
            mem_wb_pc4     <= ex_mem_pc4;
            mem_wb_alu_c   <= ex_mem_alu_c;
            mem_wb_ram_ext <= ram_ext;
            mem_wb_lui_imm <= ex_mem_lui_imm;
            mem_wb_rd      <= ex_mem_rd;
            mem_wb_rf_wsel <= ex_mem_rf_wsel;
            mem_wb_rf_we   <= ex_mem_rf_we;
        end
    end

    // WB stage.
    always @(*) begin
        case (mem_wb_rf_wsel)
            `WB_ALU : rf_wdata = mem_wb_alu_c;
            `WB_RAM : rf_wdata = mem_wb_ram_ext;
            `WB_PC4 : rf_wdata = mem_wb_pc4;
            `WB_EXT : rf_wdata = mem_wb_lui_imm;
            default : rf_wdata = 32'h0;
        endcase
    end

    // Trace signals for the external test harness.

`ifdef RUN_TRACE
    wire [31:0] debug_wb_pc    /* verilator public */ ;
    wire        debug_wb_rf_we /* verilator public */ ;
    wire [ 4:0] debug_wb_rf_wR /* verilator public */ ;
    wire [31:0] debug_wb_rf_wD /* verilator public */ ;

    wire [31:0] debug_mem_pc    /* verilator public */ ;
    wire [ 3:0] debug_mem_we    /* verilator public */ ;
    wire [31:0] debug_mem_waddr /* verilator public */ ;
    wire [31:0] debug_mem_wdata /* verilator public */ ;

    assign debug_wb_pc    = mem_wb_pc;
    assign debug_wb_rf_we = mem_wb_rf_we & mem_wb_valid;
    assign debug_wb_rf_wR = mem_wb_rd;
    assign debug_wb_rf_wD = rf_wdata;

    assign debug_mem_pc    = ex_mem_pc;
    assign debug_mem_we    = daccess_wen;
    assign debug_mem_waddr = daccess_addr;
    assign debug_mem_wdata = daccess_wdata;
`endif

endmodule
