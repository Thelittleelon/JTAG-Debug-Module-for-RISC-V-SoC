module AbstractCmd_Decoder #(
) (
    input   DM::command_t        cmd_i,
    
    output  DM::cmdtype_e        cmd_type_o,
    output  logic [2:0]          aarsize_o,
    output  logic                aarpostincrement_o,
    output  logic                postexec_o,
    output  logic                transfer_o,
    output  logic                write_o,
    output  logic [15:0]         regno_o,

    output  logic                unsupported_command_o
);
localparam int unsigned MaxAar         =  3;
DM::command_t cmd_t;
DM::cmdtype_e cmdtype_t;
logic [23:0]    control_t;

logic unsupported_command;

assign cmd_t = cmd_i;
assign control_t = cmd_i.control;

always_comb begin
  unsupported_command = 1'b0;

  unique case (cmd_type_o)
    DM::AccessRegister: begin
      if (32'(aarsize_o) < MaxAar && transfer_o && (regno_o[15:14] != '0)) begin
        unsupported_command = 1'b1;
      end
      // Dải regno reserved trong khi transfer
      else if (32'(aarsize_o) >= MaxAar || aarpostincrement_o == 1'b1) begin
        unsupported_command = 1'b1;
      end
    end
    default: unsupported_command = 1'b1;
  endcase
end

// output assignment
assign cmd_type_o = cmd_i.cmdtype;
assign aarsize_o = control_t [22:20];
assign aarpostincrement_o = control_t [19];
assign postexec_o = control_t [18];
assign transfer_o = control_t [17];
assign write_o = control_t [16];
assign regno_o = control_t [15:0];
assign unsupported_command_o = unsupported_command;
endmodule

