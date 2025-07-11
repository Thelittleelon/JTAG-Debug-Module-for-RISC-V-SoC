module DM_ROM (
    input logic     clk_i,
    input logic     rst_ni,
    input logic     req_i,
    input logic [31:0]              addr_i,

    output logic[63:0]      rom_rdata_o
);
localparam bit          HasSndScratch  = 1;
logic [63:0] rom_addr;
logic [63:0] rom_rdata;
assign rom_addr = 64'(addr_i);
assign rom_rdata_o = rom_rdata;

if (HasSndScratch) begin : gen_rom_snd_scratch
  debug_rom i_debug_rom (
    .clk_i,
    .rst_ni,
    .req_i,
    .addr_i  ( rom_addr  ),
    .rdata_o ( rom_rdata )
  );
  end else begin : gen_rom_one_scratch
  debug_rom_one_scratch i_debug_rom (
      .clk_i,
      .rst_ni,
      .req_i,
      .addr_i  ( rom_addr  ),
      .rdata_o ( rom_rdata )
    );
  end 
endmodule

