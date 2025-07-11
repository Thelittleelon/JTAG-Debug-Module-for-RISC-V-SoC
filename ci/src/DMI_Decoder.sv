module DMI_Decoder (
  input   DM::dmi_req_t                          dmi_req_i,
  output  logic [6:0]                        dmi_req_addr_o,
  output  logic [1:0]                        dmi_req_op_o,
  output  logic [31:0]                       dmi_req_data_o
    
);
  assign dmi_req_addr_o = dmi_req_i.addr;
  assign dmi_req_data_o = dmi_req_i.data;
  assign dmi_req_op_o   = dmi_req_i.op;
endmodule

