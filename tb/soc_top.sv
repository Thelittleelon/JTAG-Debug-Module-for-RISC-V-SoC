import DM::*;

module soc_top #(
    parameter int unsigned INSTR_RDATA_WIDTH = 32,
    parameter int unsigned RAM_ADDR_WIDTH = 16,
    parameter logic [31:0] BOOT_ADDR = 32'h1A00_0180,
    parameter bit JTAG_BOOT = 1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic fetch_enable_i,
    output logic tests_passed_o,
    output logic tests_failed_o,

    // JTAG interface from board
    input  logic tck_i,
    input  logic tms_i,
    input  logic tdi_i,
    input  logic trst_ni,
    output logic tdo_o
);

    // Hart configuration
    localparam logic CLUSTER_ID = 1'b0;
    localparam logic CORE_ID = 1'b0;
    localparam logic [31:0] CORE_MHARTID = {21'b0, CLUSTER_ID, 1'b0, CORE_ID};
    localparam int NrHarts = 1;
    localparam logic [NrHarts-1:0] SELECTABLE_HARTS = 1 << CORE_MHARTID;
    localparam logic [31:0] HARTINFO = {8'h0, 4'h2, 3'b0, 1'b1, DataCount, DataAddr};

    // Core <-> RAM
    logic instr_req, instr_gnt, instr_rvalid;
    logic [31:0] instr_addr;
    logic [INSTR_RDATA_WIDTH-1:0] instr_rdata;
    logic data_req, data_gnt, data_rvalid;
    logic [31:0] data_addr, data_rdata, data_wdata;
    logic data_we;
    logic [3:0] data_be;

    // Debug module connections
    logic debug_req_ready, jtag_req_valid, jtag_resp_ready, jtag_resp_valid;
    dmi_req_t jtag_dmi_req;
    dmi_resp_t debug_resp;
    logic [NrHarts-1:0] dm_debug_req;
    logic ndmreset, ndmreset_n;

    // DM slave interface
    logic dm_req, dm_we, dm_rvalid, dm_grant;
    logic [31:0] dm_addr, dm_wdata, dm_rdata;
    logic [3:0] dm_be;

    // System bus (SBA)
    logic sb_req, sb_we, sb_gnt, sb_rvalid;
    logic [31:0] sb_addr, sb_wdata, sb_rdata;
    logic [3:0] sb_be;

    // Interrupts
    logic irq;
    logic [0:4] irq_id_in, irq_id_out;
    logic irq_ack;

    // Reset synchronizer (simple logic)
    assign ndmreset_n = rst_ni & ~ndmreset;

    // Core instantiation
    cv32e40p_core #(
        .PULP_XPULP(0), .PULP_CLUSTER(0), .FPU(0), .PULP_ZFINX(0), .NUM_MHPMCOUNTERS(1)
    ) riscv_core_i (
        .clk_i(clk_i),
        .rst_ni(ndmreset_n),
        .pulp_clock_en_i(1'b1),
        .scan_cg_en_i(1'b0),
        .boot_addr_i(BOOT_ADDR),
        .mtvec_addr_i(32'h00000000),
        .dm_halt_addr_i(32'h1A110800),
        .hart_id_i(CORE_MHARTID),
        .dm_exception_addr_i(32'h00000000),
        .instr_addr_o(instr_addr),
        .instr_req_o(instr_req),
        .instr_rdata_i(instr_rdata),
        .instr_gnt_i(instr_gnt),
        .instr_rvalid_i(instr_rvalid),
        .data_addr_o(data_addr),
        .data_wdata_o(data_wdata),
        .data_we_o(data_we),
        .data_req_o(data_req),
        .data_be_o(data_be),
        .data_rdata_i(data_rdata),
        .data_gnt_i(data_gnt),
        .data_rvalid_i(data_rvalid),
        .irq_i(32'b0),
        .irq_ack_o(irq_ack),
        .irq_id_o(irq_id_out),
        .debug_req_i(dm_debug_req[CORE_MHARTID]),
        .fetch_enable_i(fetch_enable_i),
        .core_sleep_o()
    );

    // RAM and peripherals
    mm_ram #(
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
        .INSTR_RDATA_WIDTH(INSTR_RDATA_WIDTH),
        .JTAG_BOOT(JTAG_BOOT)
    ) mm_ram_i (
        .clk_i(clk_i),
        .rst_ni(ndmreset_n),
        .instr_req_i(instr_req),
        .instr_addr_i(instr_addr),
        .instr_rdata_o(instr_rdata),
        .instr_rvalid_o(instr_rvalid),
        .instr_gnt_o(instr_gnt),
        .data_req_i(data_req),
        .data_addr_i(data_addr),
        .data_we_i(data_we),
        .data_be_i(data_be),
        .data_wdata_i(data_wdata),
        .data_rdata_o(data_rdata),
        .data_rvalid_o(data_rvalid),
        .data_gnt_o(data_gnt),
        .sb_req_i(sb_req),
        .sb_addr_i(sb_addr),
        .sb_we_i(sb_we),
        .sb_be_i(sb_be),
        .sb_wdata_i(sb_wdata),
        .sb_rdata_o(sb_rdata),
        .sb_rvalid_o(sb_rvalid),
        .sb_gnt_o(sb_gnt),
        .dm_req_o(dm_req),
        .dm_addr_o(dm_addr),
        .dm_we_o(dm_we),
        .dm_be_o(dm_be),
        .dm_wdata_o(dm_wdata),
        .dm_rdata_i(dm_rdata),
        .dm_rvalid_i(dm_rvalid),
        .dm_gnt_i(dm_grant),
        .irq_id_i(irq_id_out),
        .irq_ack_i(irq_ack),
        .irq_id_o(irq_id_in),
        .irq_o(irq),
        .tests_passed_o(tests_passed_o),
        .tests_failed_o(tests_failed_o)
    );

    // DMI from JTAG TAP
    DTM_top #(
        .IdcodeValue(32'h249511C3)
    ) i_dmi_jtag (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .testmode_i(1'b0),
        .dmi_req_o(jtag_dmi_req),
        .dmi_req_valid_o(jtag_req_valid),
        .dmi_req_ready_i(debug_req_ready),
        .dmi_resp_i(debug_resp),
        .dmi_resp_ready_o(jtag_resp_ready),
        .dmi_resp_valid_i(jtag_resp_valid),
        .dmi_rst_no(), // not used
        .tck_i(tck_i),
        .tms_i(tms_i),
        .trst_ni(trst_ni),
        .td_i(tdi_i),
        .td_o(tdo_o),
        .tdo_oe_o() // not used
    );

    // Debug Module
    DM_top #(
        .NrHarts(NrHarts),
        .BusWidth(32),
        .SelectableHarts(1'b1)
    ) dm (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .next_dm_addr_i(32'h0000_1000),
        .testmode_i(1'b0),
        .ndmreset_o(ndmreset),
        .ndmreset_ack_i(),
        .dmactive_o(),
        .debug_req_o(dm_debug_req),
        .unavailable_i(~SELECTABLE_HARTS),
        .hartinfo_i({HARTINFO}),
        .slave_req_i(dm_req),
        .slave_we_i(dm_we),
        .slave_addr_i(dm_addr),
        .slave_be_i(dm_be),
        .slave_wdata_i(dm_wdata),
        .slave_rdata_o(dm_rdata),
        .master_req_o(sb_req),
        .master_add_o(sb_addr),
        .master_we_o(sb_we),
        .master_wdata_o(sb_wdata),
        .master_be_o(sb_be),
        .master_gnt_i(sb_gnt),
        .master_r_valid_i(sb_rvalid),
        .master_r_err_i(1'b0),
        .master_r_other_err_i(1'b0),
        .master_r_rdata_i(sb_rdata),
        .dmi_rst_ni(rst_ni),
        .dmi_req_valid_i(jtag_req_valid),
        .dmi_req_ready_o(debug_req_ready),
        .dmi_req_i(jtag_dmi_req),
        .dmi_resp_valid_o(jtag_resp_valid),
        .dmi_resp_ready_i(jtag_resp_ready),
        .dmi_resp_o(debug_resp)
    );

    // Slave response logic
    assign dm_grant = dm_req;
    always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) dm_rvalid <= 1'b0;
        else dm_rvalid <= dm_grant;

endmodule
