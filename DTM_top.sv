module DTM_top #(
  parameter logic [31:0] IdcodeValue = 32'h00000DB3
) (
  input  logic         clk_i,        // DMI clock
  input  logic         rst_ni,       // Active-low async reset
  input  logic         testmode_i,   // Test mode enable

  output logic         dmi_rst_no,   // Reset for DM core side
  output DM::dmi_req_t dmi_req_o,
  output logic         dmi_req_valid_o,
  input  logic         dmi_req_ready_i,

  input DM::dmi_resp_t dmi_resp_i,
  output logic         dmi_resp_ready_o,
  input  logic         dmi_resp_valid_i,

  input  logic         tck_i,        // JTAG clock
  input  logic         tms_i,        // JTAG TMS
  input  logic         trst_ni,      // JTAG reset (active low)
  input  logic         td_i,         // JTAG data in
  output logic         td_o,         // JTAG data out
  output logic         tdo_oe_o      // JTAG data out enable
);

  typedef enum logic [1:0] {
    DMINoError       = 2'h0,
    DMIReservedError = 2'h1,
    DMIOPFailed      = 2'h2,
    DMIBusy          = 2'h3
  } dmi_error_e;

  dmi_error_e error_d, error_q;

  logic tck;
  logic jtag_dmi_clear; // Reset from JTAG TAP FSM
  logic dmi_clear;       // Combined reset for DMI logic
  logic update, capture, shift, tdi;
  logic dtmcs_select;

  assign dmi_clear = jtag_dmi_clear || (dtmcs_select && update && dtmcs_q.dmihardreset);

  // -------------------------------
  // DTMCS (Debug Transport Module Control & Status)
  // -------------------------------

  DM::dtmcs_t dtmcs_d, dtmcs_q;

  always_comb begin
    dtmcs_d = dtmcs_q;
    if (capture && dtmcs_select) begin
      dtmcs_d = '{
        zero1        : '0,
        dmihardreset : 1'b0,
        dmireset     : 1'b0,
        zero0        : '0,
        idle         : 3'd1,
        dmistat      : error_q,
        abits        : 6'd7,
        version      : 4'd1
      };
    end
    if (shift && dtmcs_select)
      dtmcs_d = {tdi, 31'(dtmcs_q >> 1)};
  end

  always_ff @(posedge tck or negedge trst_ni) begin
    if (!trst_ni)
      dtmcs_q <= '0;
    else
      dtmcs_q <= dtmcs_d;
  end

  // ----------------------------
  // DMI (Debug Module Interface)
  // ----------------------------

  logic        dmi_select;
  logic        dmi_tdo;

  DM::dmi_req_t  dmi_req;
  logic              dmi_req_ready, dmi_req_valid;
  DM::dmi_resp_t dmi_resp;
  logic              dmi_resp_valid, dmi_resp_ready;

  typedef struct packed {
    logic [6:0]  address;
    logic [31:0] data;
    logic [1:0]  op;
  } dmi_t;

  typedef enum logic [2:0] {
    Idle, Read, WaitReadValid, Write, WaitWriteValid
  } state_e;

  state_e state_d, state_q;
  logic [$bits(dmi_t)-1:0] dr_d, dr_q;
  logic [6:0] address_d, address_q;
  logic [31:0] data_d, data_q;

  dmi_t dmi = dmi_t'(dr_q);

  assign dmi_req.addr     = address_q;
  assign dmi_req.data     = data_q;
  assign dmi_req.op       = (state_q == Write) ? DM::DTM_WRITE : DM::DTM_READ;
  assign dmi_resp_ready   = 1'b1;

  logic error_dmi_busy, error_dmi_op_failed;

  always_comb begin : p_fsm
    error_dmi_busy      = 1'b0;
    error_dmi_op_failed = 1'b0;
    state_d             = state_q;
    address_d           = address_q;
    data_d              = data_q;
    error_d             = error_q;
    dmi_req_valid       = 1'b0;

    if (dmi_clear) begin
      state_d   = Idle;
      address_d = '0;
      data_d    = '0;
      error_d   = DMINoError;
    end else begin
      unique case (state_q)
        Idle: begin
          if (dmi_select && update && error_q == DMINoError) begin
            address_d = dmi.address;
            data_d    = dmi.data;
            case (DM::dtm_op_e'(dmi.op))
              DM::DTM_READ:  state_d = Read;
              DM::DTM_WRITE: state_d = Write;
              default: ; // NOP
            endcase
          end
        end
        Read: begin
          dmi_req_valid = 1'b1;
          if (dmi_req_ready)
            state_d = WaitReadValid;
        end
        WaitReadValid: begin
          if (dmi_resp_valid) begin
            case (dmi_resp.resp)
              DM::DTM_SUCCESS: data_d = dmi_resp.data;
              DM::DTM_ERR:     data_d = 32'hDEAD_BEEF;
              DM::DTM_BUSY:    data_d = 32'hB051_B051;
              default:             data_d = 32'hBAAD_C0DE;
            endcase
            error_dmi_op_failed = (dmi_resp.resp == DM::DTM_ERR);
            error_dmi_busy      = (dmi_resp.resp == DM::DTM_BUSY);
            state_d = Idle;
          end
        end
        Write: begin
          dmi_req_valid = 1'b1;
          if (dmi_req_ready)
            state_d = WaitWriteValid;
        end
        WaitWriteValid: begin
          if (dmi_resp_valid) begin
            error_dmi_op_failed = (dmi_resp.resp == DM::DTM_ERR);
            error_dmi_busy      = (dmi_resp.resp == DM::DTM_BUSY);
            state_d = Idle;
          end
        end
        default: begin
          if (dmi_resp_valid)
            state_d = Idle;
        end
      endcase

      if (update && state_q != Idle)
        error_dmi_busy = 1'b1;

      if (capture && state_q inside {Read, WaitReadValid})
        error_dmi_busy = 1'b1;

      if (error_dmi_busy && error_q == DMINoError)
        error_d = DMIBusy;

      if (error_dmi_op_failed && error_q == DMINoError)
        error_d = DMIOPFailed;

      if (update && dtmcs_q.dmireset && dtmcs_select)
        error_d = DMINoError;
    end
  end

  assign dmi_tdo = dr_q[0];

  // always_comb begin : p_shift
  //   dr_d = dr_q;
  //   if (dmi_clear)
  //     dr_d = '0;
  //   else begin
  //     if (capture && dmi_select) begin
  //       case (error_q)
  //         DMINoError: dr_d = {address_q, data_q, DMINoError};
  //         DMIBusy:    dr_d = {address_q, data_q, DMIBusy};
  //         default:    dr_d = dr_q;
  //       endcase
  //     end
  //     if (shift && dmi_select)
  //       dr_d = {tdi, dr_q[$bits(dr_q)-1:1]};
  //   end
  // end

  always_comb begin : p_shift
  dr_d    = dr_q;
  if (dmi_clear) begin
    dr_d = '0;
  end else begin
    if (capture) begin
      if (dmi_select) begin
        if (error_q == DMINoError && !error_dmi_busy) begin
          dr_d = {address_q, data_q, DMINoError};
          // DMI was busy, report an error
        end else if (error_q == DMIBusy || error_dmi_busy) begin
          dr_d = {address_q, data_q, DMIBusy};
        end
      end
    end

    if (shift) begin
      if (dmi_select) begin
        dr_d = {tdi, dr_q[$bits(dr_q)-1:1]};
      end
    end
  end
end

  always_ff @(posedge tck or negedge trst_ni) begin
    if (!trst_ni) begin
      dr_q      <= '0;
      state_q   <= Idle;
      address_q <= '0;
      data_q    <= '0;
      error_q   <= DMINoError;
    end else begin
      dr_q      <= dr_d;
      state_q   <= state_d;
      address_q <= address_d;
      data_q    <= data_d;
      error_q   <= error_d;
    end
  end

  // -------------------------------
  // TAP controller instance
  // -------------------------------
  DTM_JTAG_TAP #(
    .IrLength     (5),
    .IdcodeValue  (IdcodeValue)
  ) i_dmi_jtag_tap (
    .tck_i,
    .tms_i,
    .trst_ni,
    .td_i,
    .td_o,
    .tdo_oe_o,
    .testmode_i,
    .tck_o          ( tck            ),
    .dmi_clear_o    ( jtag_dmi_clear ),
    .update_o       ( update         ),
    .capture_o      ( capture        ),
    .shift_o        ( shift          ),
    .tdi_o          ( tdi            ),
    .dtmcs_select_o ( dtmcs_select   ),
    .dtmcs_tdo_i    ( dtmcs_q[0]     ),
    .dmi_select_o   ( dmi_select     ),
    .dmi_tdo_i      ( dmi_tdo        )
  );

  // -------------------------------
  // Clock domain crossing
  // -------------------------------
  DTM_CDC i_dmi_cdc (
    // JTAG (master side)
    .tck_i                ( tck            ),
    .trst_ni              ( trst_ni        ),
    .jtag_dmi_cdc_clear_i ( dmi_clear      ),
    .jtag_dmi_req_i       ( dmi_req        ),
    .jtag_dmi_ready_o     ( dmi_req_ready  ),
    .jtag_dmi_valid_i     ( dmi_req_valid  ),
    .jtag_dmi_resp_o      ( dmi_resp       ),
    .jtag_dmi_valid_o     ( dmi_resp_valid ),
    .jtag_dmi_ready_i     ( dmi_resp_ready ),

    // Core side
    .clk_i,
    .rst_ni,
    .core_dmi_rst_no      ( dmi_rst_no       ),
    .core_dmi_req_o       ( dmi_req_o        ),
    .core_dmi_valid_o     ( dmi_req_valid_o  ),
    .core_dmi_ready_i     ( dmi_req_ready_i  ),
    .core_dmi_resp_i      ( dmi_resp_i       ),
    .core_dmi_ready_o     ( dmi_resp_ready_o ),
    .core_dmi_valid_i     ( dmi_resp_valid_i )
  );

endmodule : DTM_top
