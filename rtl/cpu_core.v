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

    // IF and next-PC signals.
    wire [31:0] pc;
    wire [31:0] npc;
    wire [31:0] pc4;
    wire [31:0] bj_target;
    wire [31:0] jalr_target;
    wire [31:0] inst;

    // Decode control outputs. Later commits will pipeline only the fields
    // used by following stages.
    wire [ 1:0] npc_op;
    wire [ 1:0] rf_wsel;
    wire [ 2:0] sext_op;
    wire [ 4:0] alu_op;
    wire        alua_sel;
    wire        alub_sel;
    wire [ 2:0] ram_rop;
    reg  [ 2:0] ram_rop_hold;
    wire [ 3:0] ram_wop;
    wire        is_mul;
    wire        is_div;
    wire        is_mul_div;
    reg         mul_div_active;

    // Register file and writeback signals.
    wire [31:0] rf_rd1;
    wire [31:0] rf_rd2;
    wire        rf_we;
    wire        rf_we_wb;
    reg  [ 4:0] rd_addr_hold;
    wire [ 4:0] rf_waddr;
    reg  [31:0] rf_wdata;

    // Immediate value generated in decode.
    wire [31:0] ext;

    // Execute-stage datapath signals.
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_c;
    reg  [31:0] load_addr_hold;
    wire        br;
    wire        mul_div_busy;
    
    // Memory-stage request and load extension signals.
    wire [ 3:0] da_ren;
    wire [31:0] da_addr;
    wire [ 3:0] da_wen;
    wire [31:0] da_wdata;
    wire [31:0] ram_ext;
    wire        is_ld_st;
    reg         ld_st_active;
    wire        ld_st_done;

    // Single-cycle wait helpers. Pipeline control will replace these later.
    wire        inst_finished;
    reg         inst_finished_r;

    // IF stage.
    reg rst_r;
    wire first_req = rst_r & !cpu_rst;
    always @(posedge cpu_clk) rst_r <= cpu_rst;

    // Fetch once after reset and after each completed instruction.
    assign ifetch_req  = first_req | inst_finished_r;
    assign ifetch_addr = pc;
    assign pc4         = pc + 32'h4;
    assign bj_target   = pc + ext;
    assign jalr_target = alu_c & ~32'h1;

    NPC U_NPC (
        .op         (npc_op),
        .pc4        (pc4),
        .bj_target  (bj_target),
        .jalr_target(jalr_target),
        .br         (br),
        .npc        (npc)
    );

    PC U_PC (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .npc        (npc),
        .fetch      (inst_finished),
        .pc         (pc)
    );
    
    // ID stage. The instruction bus is valid for one cycle only.
    assign inst = ifetch_valid ? ifetch_inst : 32'h13 /* NOP */ ;

    Controller U_CU (
        .opcode         (inst[6:0]),
        .funct3         (inst[14:12]),
        .funct7         (inst[31:25]),
        .npc_op         (npc_op),
        .sext_op        (sext_op),
        .alu_op         (alu_op),
        .alua_sel       (alua_sel),
        .alub_sel       (alub_sel),
        .is_mul         (is_mul),
        .is_div         (is_div),
        .ram_r_op       (ram_rop),
        .ram_w_op       (ram_wop),
        .rf_we          (rf_we),
        .rf_wsel        (rf_wsel)
    );

    RF U_RF (
        .clk        (cpu_clk),
        .rR1        (inst[19:15]),
        .rR2        (inst[24:20]),
        .rD1        (rf_rd1),
        .rD2        (rf_rd2),
        .we         (rf_we_wb),
        .wR         (rf_waddr),
        .wD         (rf_wdata)
    );

    SEXT U_SEXT (
        .op         (sext_op),
        .imm        (inst[31:7]),
        .ext        (ext)
    );
    
    // Loads and stores wait for the external data response.
    assign is_ld_st = (ram_rop != `RAM_EXT_N) | (ram_wop != `RAM_WE_N);
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if      (cpu_rst)    ld_st_active <= 1'b0;
        else if (is_ld_st)   ld_st_active <= 1'b1;
        else if (ld_st_done) ld_st_active <= 1'b0;
    end

    // Mul/div operations wait for the iterative unit to become idle.
    assign is_mul_div = is_mul | is_div;
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if      (cpu_rst)       mul_div_active <= 1'b0;
        else if (is_mul_div)    mul_div_active <= 1'b1;
        else if (!mul_div_busy) mul_div_active <= 1'b0;
    end

    // Multi-cycle paths hold the destination register until writeback.
    always @(posedge cpu_clk) begin
        if (is_ld_st | is_mul_div) rd_addr_hold <= inst[11:7];
    end

    // EX stage.
    assign alu_a = alua_sel ? pc  : rf_rd1;
    assign alu_b = alub_sel ? ext : rf_rd2;

    ALU U_ALU (
        .rst        (cpu_rst),
        .clk        (cpu_clk),
        .op         (alu_op),
        .a          (alu_a),
        .b          (alu_b),
        .br         (br),
        .c          (alu_c),
        .busy       (mul_div_busy)
    );

    // MEM stage.
    MREQ U_MEM_REQ (
        .ram_addr   (alu_c),

        .ram_rop    (ram_rop),
        .da_ren     (da_ren),
        .da_addr    (da_addr),

        .ram_wop    (ram_wop),
        .ram_wdata  (rf_rd2),   // Store data comes from rs2.
        .da_wen     (da_wen),
        .da_wdata   (da_wdata)
    );

    MEXT U_MEM_EXT (
        .op             (ram_rop_hold),
        .din            (daccess_rdata),
        .byte_offs      (load_addr_hold[1:0]),
        .ext            (ram_ext)
    );

    always @(posedge cpu_clk) if (is_ld_st) load_addr_hold <= alu_c;
    always @(posedge cpu_clk) if (is_ld_st) ram_rop_hold   <= ram_rop;

    // Registered external data interface.
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            daccess_ren   <= 4'h0;
            daccess_wen   <= 4'h0;
        end else begin
            daccess_ren   <= da_ren;
            daccess_addr  <= da_addr;
            daccess_wen   <= da_wen;
            daccess_wdata <= da_wdata;
        end
    end

    assign ld_st_done = daccess_rvalid | daccess_wresp;

    // WB stage.
    assign rf_we_wb = ld_st_active   & daccess_rvalid |
                      mul_div_active & !mul_div_busy  |
                      ifetch_valid & rf_we & !is_ld_st & !is_mul_div;

    assign rf_waddr = ld_st_active | mul_div_active ? rd_addr_hold : inst[11:7];

    always @(*) begin
        casex ({ld_st_active, rf_wsel})
            {1'b0, `WB_ALU}: rf_wdata = alu_c;
            {1'b0, `WB_PC4}: rf_wdata = pc4;
            {1'b0, `WB_EXT}: rf_wdata = ext;
            {1'b1, 2'b??  }: rf_wdata = ram_ext;
            default        : rf_wdata = 32'h0;
        endcase
    end

    assign inst_finished = ld_st_active   & ld_st_done    |
                           mul_div_active & !mul_div_busy |
                           ifetch_valid & !is_ld_st & !is_mul_div;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        inst_finished_r <= cpu_rst ? 1'b0 : inst_finished;
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

    assign debug_wb_pc    = pc;
    assign debug_wb_rf_we = rf_we_wb;
    assign debug_wb_rf_wR = rf_waddr;
    assign debug_wb_rf_wD = rf_wdata;

    assign debug_mem_pc    = pc;
    assign debug_mem_we    = daccess_wen;
    assign debug_mem_waddr = daccess_addr;
    assign debug_mem_wdata = daccess_wdata;
`endif

endmodule
