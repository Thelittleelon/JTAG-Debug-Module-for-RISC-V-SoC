module DTM_JTAG_TAP #(
  parameter int unsigned IrLength = 5,
  parameter logic [31:0] IdcodeValue = 32'h00000001
) (
  input  logic        tck_i,      // JTAG clock
  input  logic        tms_i,      // JTAG mode select
  input  logic        trst_ni,    // JTAG reset (active low)
  input  logic        td_i,       // JTAG data input
  output logic        td_o,       // JTAG data output
  output logic        tdo_oe_o,   // TDO output enable
  input  logic        testmode_i, // Test mode enable

  output logic        tck_o,         // Forwarded TCK
  output logic        dmi_clear_o,   // Reset for DMI triggered by TAP reset
  output logic        update_o,      // TAP update phase
  output logic        capture_o,     // TAP capture phase
  output logic        shift_o,       // TAP shift phase
  output logic        tdi_o,         // Forwarded TDI

  output logic        dtmcs_select_o,// Select DTMCS register
  input  logic        dtmcs_tdo_i,   // TDO from DTMCS

  output logic        dmi_select_o,  // Select DMI register
  input  logic        dmi_tdo_i      // TDO from DMI
);

  typedef enum logic [3:0] {
    TestLogicReset, RunTestIdle, SelectDrScan,
    CaptureDr, ShiftDr, Exit1Dr, PauseDr, Exit2Dr,
    UpdateDr, SelectIrScan, CaptureIr, ShiftIr,
    Exit1Ir, PauseIr, Exit2Ir, UpdateIr
  } tap_state_e;

  tap_state_e tap_state_q, tap_state_d;
  logic update_dr, shift_dr, capture_dr;

  typedef enum logic [IrLength-1:0] {
    BYPASS0   = 'h0,
    IDCODE    = 'h1,
    DTMCSR    = 'h10,
    DMIACCESS = 'h11,
    BYPASS1   = 'h1f
  } ir_reg_e;

  // ----------------
  // IR (Instruction Register)
  // ----------------
  logic [IrLength-1:0]  jtag_ir_shift_d, jtag_ir_shift_q;
  ir_reg_e              jtag_ir_d, jtag_ir_q;
  logic capture_ir, shift_ir, update_ir, test_logic_reset;

  always_comb begin : p_jtag
    jtag_ir_shift_d = jtag_ir_shift_q;
    jtag_ir_d       = jtag_ir_q;

    if (shift_ir)
      jtag_ir_shift_d = {td_i, jtag_ir_shift_q[IrLength-1:1]};

    if (capture_ir)
      jtag_ir_shift_d = IrLength'(4'b0101);

    if (update_ir)
      jtag_ir_d = ir_reg_e'(jtag_ir_shift_q);

    if (test_logic_reset) begin
      jtag_ir_shift_d = '0;
      jtag_ir_d       = IDCODE;
    end
  end

  always_ff @(posedge tck_i or negedge trst_ni) begin : p_jtag_ir_reg
    if (!trst_ni) begin
      jtag_ir_shift_q <= '0;
      jtag_ir_q       <= IDCODE;
    end else begin
      jtag_ir_shift_q <= jtag_ir_shift_d;
      jtag_ir_q       <= jtag_ir_d;
    end
  end

  // ----------------
  // DR (Data Register): BYPASS, IDCODE, DTMCSR
  // ----------------
  logic [31:0] idcode_d, idcode_q;
  logic        idcode_select;
  logic        bypass_select;

  logic        bypass_d, bypass_q;

  always_comb begin
    idcode_d = idcode_q;
    bypass_d = bypass_q;

    if (capture_dr) begin
      if (idcode_select)  idcode_d = IdcodeValue;
      if (bypass_select)  bypass_d = 1'b0;
    end

    if (shift_dr) begin
      if (idcode_select)  idcode_d = {td_i, 31'(idcode_q >> 1)};
      if (bypass_select)  bypass_d = td_i;
    end

    if (test_logic_reset) begin
      idcode_d = IdcodeValue;
      bypass_d = 1'b0;
    end
  end

  // ----------------
  // Register selection based on IR
  // ----------------
  always_comb begin : p_data_reg_sel
    dmi_select_o   = 1'b0;
    dtmcs_select_o = 1'b0;
    idcode_select  = 1'b0;
    bypass_select  = 1'b0;

    unique case (jtag_ir_q)
      BYPASS0:                  bypass_select  = 1'b1;
      BYPASS1:                  bypass_select  = 1'b1;
      IDCODE:                   idcode_select  = 1'b1;
      DTMCSR:                   dtmcs_select_o = 1'b1;
      DMIACCESS:                dmi_select_o   = 1'b1;
      default:                  bypass_select  = 1'b1;      
    endcase
  end

  // ----------------
  // TDO output mux
  // ----------------
  logic tdo_mux;

  always_comb begin : p_out_sel
    if (shift_ir)
      tdo_mux = jtag_ir_shift_q[0];
    else begin
      unique case (jtag_ir_q)
        IDCODE:    tdo_mux = idcode_q[0];
        DTMCSR:    tdo_mux = dtmcs_tdo_i;
        DMIACCESS: tdo_mux = dmi_tdo_i;
        default:   tdo_mux = bypass_q;
      endcase
    end
  end

  // ----------------
  // DFT logic (test clock inversion)
  // ----------------
  logic tck_n, tck_ni;

  tc_clk_inverter i_tck_inv (
    .clk_i ( tck_i  ),
    .clk_o ( tck_ni )
  );

  tc_clk_mux2 i_dft_tck_mux (
    .clk0_i    ( tck_ni     ),
    .clk1_i    ( tck_i      ),
    .clk_sel_i ( testmode_i ),
    .clk_o     ( tck_n      )
  );

  // ----------------
  // Output TDO on negedge TCK
  // ----------------
  always_ff @(posedge tck_n or negedge trst_ni) begin : p_tdo_regs
    if (!trst_ni) begin
      td_o     <= 1'b0;
      tdo_oe_o <= 1'b0;
    end else begin
      td_o     <= tdo_mux;
      tdo_oe_o <= (shift_ir | shift_dr);
    end
  end

  // ----------------
  // TAP FSM (state transitions)
  // ----------------
  always_comb begin : p_tap_fsm
    test_logic_reset = 1'b0;

    capture_dr = 1'b0;
    shift_dr   = 1'b0;
    update_dr  = 1'b0;

    capture_ir = 1'b0;
    shift_ir   = 1'b0;
    update_ir  = 1'b0;

    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = tms_i ? TestLogicReset : RunTestIdle;
        test_logic_reset = 1'b1;
      end
      RunTestIdle: tap_state_d = tms_i ? SelectDrScan : RunTestIdle;

      // DR Path
      SelectDrScan: tap_state_d = tms_i ? SelectIrScan : CaptureDr;
      CaptureDr: begin
        capture_dr = 1'b1;
        tap_state_d = tms_i ? Exit1Dr : ShiftDr;
      end
      ShiftDr: begin
        shift_dr = 1'b1;
        tap_state_d = tms_i ? Exit1Dr : ShiftDr;
      end
      Exit1Dr: tap_state_d = tms_i ? UpdateDr : PauseDr;
      PauseDr: tap_state_d = tms_i ? Exit2Dr : PauseDr;
      Exit2Dr: tap_state_d = tms_i ? UpdateDr : ShiftDr;
      UpdateDr: begin
        update_dr = 1'b1;
        tap_state_d = tms_i ? SelectDrScan : RunTestIdle;
      end

      // IR Path
      SelectIrScan: tap_state_d = tms_i ? TestLogicReset : CaptureIr;
      CaptureIr: begin
        capture_ir = 1'b1;
        tap_state_d = tms_i ? Exit1Ir : ShiftIr;
      end
      ShiftIr: begin
        shift_ir = 1'b1;
        tap_state_d = tms_i ? Exit1Ir : ShiftIr;
      end
      Exit1Ir: tap_state_d = tms_i ? UpdateIr : PauseIr;
      PauseIr: tap_state_d = tms_i ? Exit2Ir : PauseIr;
      Exit2Ir: tap_state_d = tms_i ? UpdateIr : ShiftIr;
      UpdateIr: begin
        update_ir = 1'b1;
        tap_state_d = tms_i ? SelectDrScan : RunTestIdle;
      end
    endcase
  end

  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= TestLogicReset;
      idcode_q    <= IdcodeValue;
      bypass_q    <= 1'b0;
    end else begin
      tap_state_q <= tap_state_d;
      idcode_q    <= idcode_d;
      bypass_q    <= bypass_d;
    end
  end

  // ----------------
  // Signal passthrough to DTM core
  // ----------------
  assign tck_o        = tck_i;
  assign tdi_o        = td_i;
  assign update_o     = update_dr;
  assign shift_o      = shift_dr;
  assign capture_o    = capture_dr;
  assign dmi_clear_o  = test_logic_reset;

endmodule
