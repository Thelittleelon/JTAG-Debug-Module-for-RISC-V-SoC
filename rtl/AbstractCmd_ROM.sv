module AbstractCmd_ROM #(
  parameter int unsigned        NrHarts          =  1,
  parameter int unsigned        BusWidth         = 32,
  parameter logic [NrHarts-1:0] SelectableHarts  = {NrHarts{1'b1}},
  parameter int unsigned        DmBaseAddress    = 'h1000
) ( 
  // Abstract Cmd Decoded inputs
  input  DM::cmdtype_e        cmd_type_i,
  input  logic [2:0]          aarsize_i,
  input  logic                aarpostincrement_i,
  input  logic                postexec_i,
  input  logic                transfer_i,
  input  logic                write_i,
  input  logic [15:0]         regno_i,
  input  logic                unsupported_command_i,

  output [7:0][63:0]          abstract_cmd_o
);
localparam bit          HasSndScratch  = (DmBaseAddress != 0);
localparam int unsigned MaxAar         = (BusWidth == 64) ? 4 : 3;
//localparam int unsigned MaxAar         = 3;
 localparam logic [4:0]  LoadBaseAddr   = (DmBaseAddress == 0) ? 5'd0 : 5'd10;

logic [7:0][63:0]   abstract_cmd;

// Read/Write logic
logic abstract_cmd_to_read;
logic abstract_cmd_to_write;
assign abstract_cmd_to_write = 32'(aarsize_i) < MaxAar && transfer_i && write_i;
assign abstract_cmd_to_read = 32'(aarsize_i) < MaxAar && transfer_i && (!write_i);
// Output
assign abstract_cmd_o = abstract_cmd;
always_comb begin : p_abstract_cmd_rom
    // default memory
    abstract_cmd[0][31:0]  = DM::illegal();
    abstract_cmd[0][63:32] = HasSndScratch ? DM::auipc(5'd10, '0) : DM::nop();
    // clr lowest 12b -> DM base offset
    abstract_cmd[1][31:0]  = HasSndScratch ? DM::srli(5'd10, 5'd10, 6'd12) : DM::nop();
    abstract_cmd[1][63:32] = HasSndScratch ? DM::slli(5'd10, 5'd10, 6'd12) : DM::nop();
    abstract_cmd[2][31:0]  = DM::nop();
    abstract_cmd[2][63:32] = DM::nop();
    abstract_cmd[3][31:0]  = DM::nop();
    abstract_cmd[3][63:32] = DM::nop();
    abstract_cmd[4][31:0]  = HasSndScratch ? DM::csrr(DM::CSR_DSCRATCH1, 5'd10) : DM::nop();
    abstract_cmd[4][63:32] = DM::ebreak();
    abstract_cmd[7:5]      = '0;

    // Only support AccessRegister Abstract Cmd
    if(cmd_type_i == DM::AccessRegister ) begin
      // AbstractCmd to Write to Memory
        if (abstract_cmd_to_write) begin
          // store a0 in dscratch1
          abstract_cmd[0][31:0] = HasSndScratch ? DM::csrw(DM::CSR_DSCRATCH1, 5'd10) : DM::nop();
          // this range is reserved
          if (regno_i[15:14] != '0) begin
            abstract_cmd[0][31:0] = DM::ebreak(); 
          // A0 access needs to be handled separately, as we use A0 to load
          // the DM address offset need to access DSCRATCH1 in this case
          end else if (HasSndScratch && regno_i[12] && (!regno_i[5]) &&
                      (regno_i[4:0] == 5'd10)) begin
            // store s0 in dscratch
            abstract_cmd[2][31:0]  = DM::csrw(DM::CSR_DSCRATCH0, 5'd8);
            // load from data register
            abstract_cmd[2][63:32] = DM::load(aarsize_i, 5'd8, LoadBaseAddr, DM::DataAddr);
            // and store it in the corresponding CSR
            abstract_cmd[3][31:0]  = DM::csrw(DM::CSR_DSCRATCH1, 5'd8);
            // restore s0 again from dscratch
            abstract_cmd[3][63:32] = DM::csrr(DM::CSR_DSCRATCH0, 5'd8);
          // GPR/FPR access
          end else if (regno_i[12]) begin
            // determine whether we want to access the floating point register or not
            if (regno_i[5]) begin
              abstract_cmd[2][31:0] = DM::float_load(aarsize_i, regno_i[4:0], LoadBaseAddr, DM::DataAddr);
            end else begin
              abstract_cmd[2][31:0] = DM::load(aarsize_i, regno_i[4:0], LoadBaseAddr, DM::DataAddr);
            end
          // CSR access
          end else begin
            // data register to CSR
            // store s0 in dscratch
            abstract_cmd[2][31:0]  = DM::csrw(DM::CSR_DSCRATCH0, 5'd8);
            // load from data register
            abstract_cmd[2][63:32] = DM::load(aarsize_i, 5'd8, LoadBaseAddr, DM::DataAddr);
            // and store it in the corresponding CSR
            abstract_cmd[3][31:0]  = DM::csrw(DM::csr_reg_t'(regno_i[11:0]), 5'd8);
            // restore s0 again from dscratch
            abstract_cmd[3][63:32] = DM::csrr(DM::CSR_DSCRATCH0, 5'd8);
          end
        end else if (abstract_cmd_to_read) begin
          // store a0 in dscratch1
          abstract_cmd[0][31:0]  = HasSndScratch ?
                                   DM::csrw(DM::CSR_DSCRATCH1, LoadBaseAddr) :
                                   DM::nop();
          // this range is reserved
          if (regno_i[15:14] != '0) begin
              abstract_cmd[0][31:0] = DM::ebreak(); // we leave asap
          // A0 access needs to be handled separately, as we use A0 to load
          // the DM address offset need to access DSCRATCH1 in this case
          end else if (HasSndScratch && regno_i[12] && (!regno_i[5]) &&
                      (regno_i[4:0] == 5'd10)) begin
            // store s0 in dscratch
            abstract_cmd[2][31:0]  = DM::csrw(DM::CSR_DSCRATCH0, 5'd8);
            // read value from CSR into s0
            abstract_cmd[2][63:32] = DM::csrr(DM::CSR_DSCRATCH1, 5'd8);
            // and store s0 into data section
            abstract_cmd[3][31:0]  = DM::store(aarsize_i, 5'd8, LoadBaseAddr, DM::DataAddr);
            // restore s0 again from dscratch
            abstract_cmd[3][63:32] = DM::csrr(DM::CSR_DSCRATCH0, 5'd8);
          // GPR/FPR access
          end else if (regno_i[12]) begin
            // determine whether we want to access the floating point register or not
            if (regno_i[5]) begin
              abstract_cmd[2][31:0] = DM::float_store(aarsize_i, regno_i[4:0], LoadBaseAddr, DM::DataAddr);
            end else begin
              abstract_cmd[2][31:0] = DM::store(aarsize_i, regno_i[4:0], LoadBaseAddr, DM::DataAddr);
            end
          // CSR access
          end else begin
            // CSR register to data
            // store s0 in dscratch
            abstract_cmd[2][31:0]  = DM::csrw(DM::CSR_DSCRATCH0, 5'd8);
            // read value from CSR into s0
            abstract_cmd[2][63:32] = DM::csrr(DM::csr_reg_t'(regno_i[11:0]), 5'd8);
            // and store s0 into data section
            abstract_cmd[3][31:0]  = DM::store(aarsize_i, 5'd8, LoadBaseAddr, DM::DataAddr);
            // restore s0 again from dscratch
            abstract_cmd[3][63:32] = DM::csrr(DM::CSR_DSCRATCH0, 5'd8);
          end
        end else if (32'(aarsize_i) >= MaxAar || aarpostincrement_i == 1'b1) begin
          abstract_cmd[0][31:0] = DM::ebreak(); // we leave asap
        end
        if (postexec_i && !unsupported_command_i) begin
          // issue a nop, we will automatically run into the program buffer
          abstract_cmd[4][63:32] = DM::nop();
        end
      end
      else begin
        abstract_cmd[0][31:0] = DM::ebreak();
      end
  end

endmodule: AbstractCmd_ROM

