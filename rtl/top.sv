module top #(
  parameter logic [31:0] IdcodeValue     = 32'h00000DB3,
  parameter int unsigned NrHarts         = 1,
  parameter int unsigned BusWidth        = 32,
  parameter int unsigned DmBaseAddress   = 'h1000,
  parameter logic [NrHarts-1:0] SelectableHarts = {NrHarts{1'b1}},
  parameter bit ReadByteEnable           = 1
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  testmode_i,

  // System Bus side
  input  logic                  slave_req_i,
  input  logic                  slave_we_i,
  input  logic [BusWidth-1:0]   slave_addr_i,
  input  logic [BusWidth/8-1:0] slave_be_i,
  input  logic [BusWidth-1:0]   slave_wdata_i,
  output logic [BusWidth-1:0]   slave_rdata_o,

  output logic                  master_req_o,
  output logic [BusWidth-1:0]   master_add_o,
  output logic                  master_we_o,
  output logic [BusWidth-1:0]   master_wdata_o,
  output logic [BusWidth/8-1:0] master_be_o,
  input  logic                  master_gnt_i,
  input  logic                  master_r_valid_i,
  input  logic                  master_r_err_i,
  input  logic                  master_r_other_err_i,
  input  logic [BusWidth-1:0]   master_r_rdata_i,

  // DMI JTAG physical interface
  input  logic tck_i,
  input  logic tms_i,
  input  logic trst_ni,
  input  logic td_i,
  output logic td_o,
  output logic tdo_oe_o,

  // Hart side
  output logic [NrHarts-1:0] debug_req_o,
  input  logic [NrHarts-1:0] unavailable_i,
  input  DM::hartinfo_t [NrHarts-1:0] hartinfo_i,
  input  logic ndmreset_ack_i
);

  // DMI connections
  logic dmi_rst_no;
  logic dmi_req_valid;
  logic dmi_req_ready;
  DM::dmi_req_t dmi_req;
  logic dmi_resp_valid;
  logic dmi_resp_ready;
  DM::dmi_resp_t dmi_resp;

  // dmactive and ndmreset outputs
  logic dmactive;
  logic ndmreset;

  // Instantiate DMI JTAG interface
DTM_top #(
    .IdcodeValue(IdcodeValue)
  ) i_dmi_jtag (
    .clk_i           ( clk_i             ),
    .rst_ni          ( rst_ni            ),
    .testmode_i      ( testmode_i        ),
    .dmi_rst_no      ( dmi_rst_no        ),
    .dmi_req_o       ( dmi_req           ),
    .dmi_req_valid_o ( dmi_req_valid     ),
    .dmi_req_ready_i ( dmi_req_ready     ),
    .dmi_resp_i      ( dmi_resp          ),
    .dmi_resp_ready_o( dmi_resp_ready    ),
    .dmi_resp_valid_i( dmi_resp_valid    ),
    .tck_i           ( tck_i             ),
    .tms_i           ( tms_i             ),
    .trst_ni         ( trst_ni           ),
    .td_i            ( td_i              ),
    .td_o            ( td_o              ),
    .tdo_oe_o        ( tdo_oe_o          )
  );

  // Instantiate Debug Module Top
  DM_top #(
    .NrHarts(NrHarts),
    .BusWidth(BusWidth),
    .DmBaseAddress(DmBaseAddress),
    .SelectableHarts(SelectableHarts),
    .ReadByteEnable(ReadByteEnable)
  ) i_dm_top (
    .clk_i             ( clk_i               ),
    .rst_ni            ( rst_ni              ),
    .next_dm_addr_i    ( 32'h0               ),
    .testmode_i        ( testmode_i          ),
    .ndmreset_o        ( ndmreset            ),
    .ndmreset_ack_i    ( ndmreset_ack_i      ),
    .dmactive_o        ( dmactive            ),
    .debug_req_o       ( debug_req_o         ),
    .unavailable_i     ( unavailable_i       ),
    .hartinfo_i        ( hartinfo_i          ),
    .slave_req_i       ( slave_req_i         ),
    .slave_we_i        ( slave_we_i          ),
    .slave_addr_i      ( slave_addr_i        ),
    .slave_be_i        ( slave_be_i          ),
    .slave_wdata_i     ( slave_wdata_i       ),
    .slave_rdata_o     ( slave_rdata_o       ),
    .master_req_o      ( master_req_o        ),
    .master_add_o      ( master_add_o        ),
    .master_we_o       ( master_we_o         ),
    .master_wdata_o    ( master_wdata_o      ),
    .master_be_o       ( master_be_o         ),
    .master_gnt_i      ( master_gnt_i        ),
    .master_r_valid_i  ( master_r_valid_i    ),
    .master_r_err_i    ( master_r_err_i      ),
    .master_r_other_err_i(master_r_other_err_i),
    .master_r_rdata_i  ( master_r_rdata_i    ),
    .dmi_rst_ni        ( dmi_rst_no          ),
    .dmi_req_valid_i   ( dmi_req_valid       ),
    .dmi_req_ready_o   ( dmi_req_ready       ),
    .dmi_req_i         ( dmi_req             ),
    .dmi_resp_valid_o  ( dmi_resp_valid      ),
    .dmi_resp_ready_i  ( dmi_resp_ready      ),
    .dmi_resp_o        ( dmi_resp            )
  );

endmodule

