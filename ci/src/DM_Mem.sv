module DM_Mem #(
  parameter int unsigned DbgAddressBits = 12,
  parameter int unsigned BusWidth       = 32            
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  // ===== ControlUnit3 Interface ======================
  input  logic                         wr_halted_en,
  input  logic                         wr_resuming_en,
  input  logic                         wr_going_en,
  input  logic                         wr_exception_en,
  input  logic                         wr_data_en,
  input  logic [BusWidth-1:0]          wr_data_addr_i,

  input  logic                         rd_where_en,
  input  logic                         rd_data_en,
  input  logic                         rd_prog_en,
  input  logic                         rd_abs_cmd_en,
  input  logic                         rd_flags_en,
  input  logic [BusWidth-1:0]          rd_addr_i,

  input  logic [31:0]                  wdata_i,
  input  logic [3:0]                   be_i,

  input logic req_i,
  // ===== ControlUnit2 Interface ======================
  input  logic                         resume_i,
  input  logic                         go_i,
  output logic                         halted_int_o,


  input  logic                         clear_resumeack_i,
  input  logic                         ndmreset_i,
  input  logic                         resumereq_i,   // duy nhất 1 hart

  // Abstract Command Decoder Interface
  input  logic                         cmdbusy_i,
  input  logic [7:0][63:0]             abstract_cmd_i,       // Input from Abstract Command ROM
  input  DM::cmdtype_e                     cmd_type_i,
  input  logic                         postexec_i,
  input  logic                         transfer_i,

  input  logic [DM::ProgBufSize-1:0][31:0] progbuf_i,
  input  logic [DM::DataCount-1:0][31:0]   data_i,

  // ===== Outputs ============================================================
  output logic [DM::DataCount-1:0][31:0]     data_o,
  output logic                           data_valid_o,

  output logic                           halted_o,
  output logic                           resuming_o,
  output logic                           going_o,
  output logic                           exception_o,

  output logic [BusWidth-1:0]            rdata_o
);
   // Constants (same as original spec)
  localparam logic [DbgAddressBits-1:0] HaltedAddr         = 'h100;
  localparam logic [DbgAddressBits-1:0] GoingAddr          = 'h108;
  localparam logic [DbgAddressBits-1:0] ResumingAddr       = 'h110;
  localparam logic [DbgAddressBits-1:0] ExceptionAddr      = 'h118;

  localparam logic [DbgAddressBits-1:0] WhereToAddr        = 'h300;

  localparam logic [DbgAddressBits-1:0] DataBaseAddr        = (DM::DataAddr);
  localparam logic [DbgAddressBits-1:0] DataEndAddr         = (DM::DataAddr + 4*(DM::DataCount) - 1);

  localparam logic [DbgAddressBits-1:0] ProgBufBaseAddr     = (DM::DataAddr - 4*(DM::ProgBufSize));
  localparam logic [DbgAddressBits-1:0] ProgBufEndAddr     =  (DM::DataAddr - 1);

  localparam logic [DbgAddressBits-1:0] AbstractCmdBaseAddr = (ProgBufBaseAddr - 4*10);
  localparam logic [DbgAddressBits-1:0] AbstractCmdEndAddr  = (ProgBufBaseAddr - 1);

  localparam logic [DbgAddressBits-1:0] FlagsBaseAddr      = 'h400;
  localparam logic [DbgAddressBits-1:0] FlagsEndAddr       = 'h7FF;
  // -------------------------------------------------------------------------
  logic [DM::DataCount-1:0][31:0]     data_bits;
  logic [63:0]                    rdata_d, rdata_q;
  logic [63:0]                    rom_rdata;
  logic [7:0][7:0] flag_data;

  logic halted_d, resuming_d;
  logic halted_q, resuming_q;

  logic          fwd_rom_d, fwd_rom_q;
  logic          word_enable32_q;
  logic [63:0]   word_mux;

  logic data_valid_int, exception_int, going_int, halted_int;

  always_comb begin : p_rw_logic
    halted_d      = halted_q;
    resuming_d   = resuming_q;
    flag_data          = '0;

    data_bits        = data_i;
    rdata_d          = rdata_q;

    data_valid_int   = 1'b0;
    exception_int    = 1'b0;
    going_int        = 1'b0;
    halted_int       = 1'b0;  
    // Write
    if (wr_halted_en) begin 
      halted_d = 1'b1; 
      halted_int = 1'b1;
    end
    if (wr_going_en)    going_int   = 1'b1; 
    if (wr_resuming_en) begin
      halted_d = 1'b0;
      resuming_d= 1'b1;
    end
    if (wr_exception_en) exception_int = 1'b1;

    if (wr_data_en) begin
      data_valid_int = 1'b1;
      // int dc_sel = (wr_data_addr_i[DbgAddressBits-1:2] - DataBaseAddr[DbgAddressBits-1:2]);
      // for (int i = 0; i < 4; i++) begin
      //   if (be_i[i]) begin
      //     if (BusWidth == 64 && i > 3) begin
      //       if (dc_sel + 1 < DataCount)
      //         data_bits[dc_sel+1][(i-4)*8 +:8] = wdata_i[i*8 +:8];
      //     end else begin
      //       data_bits[dc_sel][i*8 +:8] = wdata_i[i*8 +:8];
      //     end
      //   end
      // end
      for (int dc = 0; dc < (DM::DataCount); dc++) begin
              if ((wr_data_addr_i[DbgAddressBits-1:2] - DataBaseAddr[DbgAddressBits-1:2]) == dc) begin
                for (int i = 0; i < $bits(be_i); i++) begin
                  if (be_i[i]) begin
                    if (i>3) begin // for upper 32bit data write (only used for BusWidth ==  64)
                      if ((dc+1) < DM::DataCount) begin // ensure we write to an implemented data register
                        data_bits[dc+1][(i-4)*8+:8] = wdata_i[i*8+:8];
                      end
                    end else begin // for lower 32bit data write
                      data_bits[dc][i*8+:8] = wdata_i[i*8+:8];
                    end
                  end
                end
              end
      end
    end
    // Read
    if (rd_where_en) begin
      rdata_d = 64'h0;
      if (resumereq_i)
        rdata_d = {32'h0, DM::jal('0, 21'(DM::ResumeAddress[11:0]) - 21'(WhereToAddr))};
      if (cmdbusy_i) begin
        if (cmd_type_i == DM::AccessRegister && !transfer_i && postexec_i)   
          rdata_d = {32'h0, DM::jal('0, 21'(ProgBufBaseAddr) - 21'(WhereToAddr))};
        else
          rdata_d = {32'h0, DM::jal('0, 21'(AbstractCmdBaseAddr) - 21'(WhereToAddr))};
      end
    end else if (rd_data_en) begin
          rdata_d = { data_i[$clog2(DM::DataCount)'(((rd_addr_i[DbgAddressBits-1:3] - DataBaseAddr[DbgAddressBits-1:3]) << 1) + 1'b1)],
                      data_i[$clog2(DM::DataCount)'(((rd_addr_i[DbgAddressBits-1:3] - DataBaseAddr[DbgAddressBits-1:3]) << 1))]};
    end else if (rd_prog_en) begin
          rdata_d = progbuf_i[$clog2(DM::ProgBufSize)'(rd_addr_i[DbgAddressBits-1:3] - ProgBufBaseAddr[DbgAddressBits-1:3])];
    end else if (rd_abs_cmd_en) begin
          rdata_d = abstract_cmd_i[3'(rd_addr_i[DbgAddressBits-1:3] - AbstractCmdBaseAddr[DbgAddressBits-1:3])];
    end else if (rd_flags_en) begin
          if (({rd_addr_i[DbgAddressBits-1:3], 3'b0} - FlagsBaseAddr[DbgAddressBits-1:0]) ==
            (DbgAddressBits'(0) & {{(DbgAddressBits-3){1'b1}}, 3'b0})) begin
              flag_data[DbgAddressBits'(0) & DbgAddressBits'(3'b111)] = {6'b0, resume_i, go_i};
          end
          rdata_d = flag_data;
    end

    if (ndmreset_i) begin
      // When harts are reset, they are neither halted nor resuming.
      halted_d   = '0;
      resuming_d = '0;
    end
    // clear resumeack
    if (clear_resumeack_i) begin 
      resuming_d = 1'b0; 
    end
  end
  // 2)  ROM instance
  // -------------------------------------------------------------------------
  DM_ROM u_rom (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    // .req_i       (rd_where_en | rd_data_en | rd_prog_en | rd_abs_cmd_en | rd_flags_en),
    .req_i (req_i),
    .addr_i      (rd_addr_i),
    .rom_rdata_o (rom_rdata)
  );
  // -------------------------------------------------------------------------
  // 4)  forward‑to‑ROM & word‑mux
  // -------------------------------------------------------------------------
  assign fwd_rom_d     = (rd_addr_i[DbgAddressBits-1:0] >= DM::HaltAddress[DbgAddressBits-1:0]);
  assign word_mux      = fwd_rom_q ? rom_rdata : rdata_q;


  assign rdata_o = word_enable32_q ? {32'h0, word_mux[63:32]} : {32'h0, word_mux[31:0]};

  // -------------------------------------------------------------------------
  // 5)  Sequential registers
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      halted_q        <= 1'b0;
      resuming_q      <= 1'b0;

      rdata_q         <= '0;
      fwd_rom_q       <= 1'b0;
      word_enable32_q <= 1'b0;
    end else begin
      halted_q        <= halted_d;
      resuming_q      <= resuming_d;

      rdata_q         <= rdata_d;
      fwd_rom_q       <= fwd_rom_d;
      word_enable32_q <= rd_addr_i[2];
    end
  end

  // -------------------------------------------------------------------------
  // 6)  Outputs
  // -------------------------------------------------------------------------
  assign data_o        = data_bits;
  assign data_valid_o  = data_valid_int;
  
  assign resuming_o    = resuming_q;
  assign halted_o      = halted_q;
  
  assign exception_o   = exception_int;
  assign going_o       = going_int;
  assign halted_int_o  = halted_int;

endmodule : DM_Mem

