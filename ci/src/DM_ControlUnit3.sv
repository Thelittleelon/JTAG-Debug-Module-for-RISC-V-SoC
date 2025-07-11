module DM_ControlUnit3 #(
  parameter int unsigned DbgAddressBits = 12,
  parameter int unsigned BusWidth       = 32
)(
  input  logic                        req_i,
  input  logic                        we_i,
  input  logic [BusWidth-1:0]         addr_i,

  output logic                        wr_halted_en,
  output logic                        wr_going_en,
  output logic                        wr_resuming_en,
  output logic                        wr_exception_en,
  output logic                        wr_data_en,
  output logic [BusWidth-1:0]         wr_data_addr_o,

  output logic                        rd_where_en,
  output logic                        rd_data_en,
  output logic                        rd_prog_en,
  output logic                        rd_abs_cmd_en,
  output logic                        rd_flags_en,
  output logic [BusWidth-1:0]         rd_addr_o,

  output logic req_o
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

  always_comb begin
    // Default all outputs to zero
    wr_halted_en       = 1'b0;
    wr_going_en        = 1'b0;
    wr_resuming_en     = 1'b0;
    wr_exception_en    = 1'b0;
    wr_data_en         = 1'b0;
    wr_data_addr_o     = '0;

    rd_where_en        = 1'b0;
    rd_data_en         = 1'b0;
    rd_prog_en         = 1'b0;
    rd_abs_cmd_en      = 1'b0;
    rd_flags_en        = 1'b0;
    rd_addr_o          = addr_i;

    if (req_i) begin
      if (we_i) begin
        unique case (addr_i[DbgAddressBits-1:0])
          HaltedAddr:       wr_halted_en    = 1'b1;
          GoingAddr:        wr_going_en     = 1'b1;
          ResumingAddr:     wr_resuming_en  = 1'b1;
          ExceptionAddr:    wr_exception_en = 1'b1;
          default: begin
            if (addr_i[DbgAddressBits-1:0] >= DataBaseAddr && addr_i[DbgAddressBits-1:0] <= DataEndAddr) begin
              wr_data_en     = 1'b1;
              wr_data_addr_o = addr_i;
            end
          end
        endcase
      end else begin
        unique case (addr_i[DbgAddressBits-1:0])
          WhereToAddr:      rd_where_en     = 1'b1;
          default: begin
            if (addr_i[DbgAddressBits-1:0] >= DataBaseAddr && addr_i[DbgAddressBits-1:0] <= DataEndAddr)
              rd_data_en = 1'b1;
            else if (addr_i[DbgAddressBits-1:0] >= ProgBufBaseAddr && addr_i[DbgAddressBits-1:0] <= ProgBufEndAddr)
              rd_prog_en = 1'b1;
            else if (addr_i[DbgAddressBits-1:0] >= AbstractCmdBaseAddr && addr_i[DbgAddressBits-1:0] <= AbstractCmdEndAddr)
              rd_abs_cmd_en = 1'b1;
            else if (addr_i[DbgAddressBits-1:0] >= FlagsBaseAddr && addr_i[DbgAddressBits-1:0] <= FlagsEndAddr)
              rd_flags_en = 1'b1;
          end 
        endcase
      end
    end
  end

  assign req_o = req_i;

endmodule: DM_ControlUnit3


