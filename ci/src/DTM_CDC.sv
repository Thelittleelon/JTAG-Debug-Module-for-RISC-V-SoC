module DTM_CDC (
  // JTAG domain (source)
  input  logic             tck_i,
  input  logic             trst_ni,
  input  DM::dmi_req_t jtag_dmi_req_i,
  output logic             jtag_dmi_ready_o,
  input  logic             jtag_dmi_valid_i,
  input  logic             jtag_dmi_cdc_clear_i, // Sync clear across CDC

  output DM::dmi_resp_t jtag_dmi_resp_o,
  output logic              jtag_dmi_valid_o,
  input  logic              jtag_dmi_ready_i,

  // Core domain (destination)
  input  logic             clk_i,
  input  logic             rst_ni,

  output logic             core_dmi_rst_no,
  output DM::dmi_req_t core_dmi_req_o,
  output logic             core_dmi_valid_o,
  input  logic             core_dmi_ready_i,

  input  DM::dmi_resp_t core_dmi_resp_i,
  output logic              core_dmi_ready_o,
  input  logic              core_dmi_valid_i
);

  logic core_clear_pending;

  // --------------------------------------------
  // CDC: DMI request from JTAG to Core domain
  // --------------------------------------------
  cdc_2phase_clearable #(.T(DM::dmi_req_t)) i_cdc_req (
    .src_rst_ni            ( trst_ni              ),
    .src_clear_i           ( jtag_dmi_cdc_clear_i ),
    .src_clk_i             ( tck_i                ),
    .src_clear_pending_o   ( /* unused */         ),
    .src_data_i            ( jtag_dmi_req_i       ),
    .src_valid_i           ( jtag_dmi_valid_i     ),
    .src_ready_o           ( jtag_dmi_ready_o     ),

    .dst_rst_ni            ( rst_ni               ),
    .dst_clear_i           ( 1'b0                 ),
    .dst_clear_pending_o   ( core_clear_pending   ),
    .dst_clk_i             ( clk_i                ),
    .dst_data_o            ( core_dmi_req_o       ),
    .dst_valid_o           ( core_dmi_valid_o     ),
    .dst_ready_i           ( core_dmi_ready_i     )
  );

  // --------------------------------------------
  // CDC: DMI response from Core to JTAG domain
  // --------------------------------------------
  cdc_2phase_clearable #(.T(DM::dmi_resp_t)) i_cdc_resp (
    .src_rst_ni            ( rst_ni               ),
    .src_clear_i           ( 1'b0                 ),
    .src_clear_pending_o   ( /* unused */         ),
    .src_clk_i             ( clk_i                ),
    .src_data_i            ( core_dmi_resp_i      ),
    .src_valid_i           ( core_dmi_valid_i     ),
    .src_ready_o           ( core_dmi_ready_o     ),

    .dst_rst_ni            ( trst_ni              ),
    .dst_clear_i           ( jtag_dmi_cdc_clear_i ),
    .dst_clear_pending_o   ( /* unused */         ),
    .dst_clk_i             ( tck_i                ),
    .dst_data_o            ( jtag_dmi_resp_o      ),
    .dst_valid_o           ( jtag_dmi_valid_o     ),
    .dst_ready_i           ( jtag_dmi_ready_i     )
  );

  // --------------------------------------------
  // Pulse generator: Clear signal for DM CSRs FIFO
  // --------------------------------------------
  logic core_clear_pending_q;
  logic core_dmi_rst_nq;
  logic clear_pending_rise_edge_detect;

  assign clear_pending_rise_edge_detect = !core_clear_pending_q && core_clear_pending;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      core_dmi_rst_nq       <= 1'b1;
      core_clear_pending_q  <= 1'b0;
    end else begin
      core_dmi_rst_nq       <= ~clear_pending_rise_edge_detect; // Active-low pulse
      core_clear_pending_q  <= core_clear_pending;
    end
  end

  assign core_dmi_rst_no = core_dmi_rst_nq;

endmodule
