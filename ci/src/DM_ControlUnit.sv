module DM_ControlUnit #(
    parameter int unsigned DbgAddressBits = 12,
    parameter int unsigned BusWidth         = 32
) (

    input  logic                              clk_i,       // Clock
    input  logic                              rst_ni,      // debug module reset

    input  logic                              ndmreset_i,
    input  logic [19:0]                       hartsel_i,
    input  logic                              dmactive_i,  // DM is active

// DMI_Decoder Interface
    input  DM::dmi_req_t                          dmi_req_i,
    output  logic [6:0]                       dmi_req_addr_o,
    output  logic [1:0]                       dmi_req_op_o,
    output  logic [31:0]                      dmi_req_data_o,

// AbstractCmd_Decoder Interface
    input  DM::command_t                          cmd_i,
    output DM::cmdtype_e                          cmd_type_o,
    output logic [2:0]                        aarsize_o,
    output logic                              aarpostincrement_o,
    output logic                              postexec_o,
    output logic                              transfer_o,
    output logic                              write_o,
    output logic [15:0]                       regno_o,
    output logic                              unsupported_command_o,

// ControlUnit1 Interface
    input  logic                              resp_queue_full_i,  
    input  logic                              resp_queue_empty_i,
    output logic                              resp_queue_pop_o,
    output logic                              resp_queue_push_o,
 
    input  logic                              dmi_req_valid_i,
    output logic                              dmi_req_ready_o,

    output logic                              dmi_resp_valid_o,
    input  logic                              dmi_resp_ready_i,
                  
    input  logic [11:0]                       autoexecdata_i,    
    input logic [15:0]                        autoexecprogbuf_i, 

    output DM::dm_csr_e                           dm_csr_sel_o,
    output logic                              set_cmdbusy_o,
    output DM::cmderr_e                           set_cmderror_o,
    output logic                              dm_csrs_we_o,
    output logic                              dm_csrs_re_o,


// ControlUnit2 Interface 
    input  logic                              halted_i,
    input  logic                              resumereq_i,
    input  logic                              resuming_i,
    input  logic                              haltreq_i,
    input  logic                              going_i,
    input  logic                              exception_i,
    input  logic                              halted_int_i,

    output logic                              go_o,
    output logic                              resume_o,

    output logic                              cmdbusy_o,
    // output logic                              cmderror_valid_o,
    // output cmderr_e                           cmderror_o,
    output logic                              debug_req_o,

// ControlUnit3 Interface 
    output logic                              wr_halted_en,
    output logic                              wr_going_en,
    output logic                              wr_resuming_en,
    output logic                              wr_exception_en,
    output logic                              wr_data_en,
    output logic [BusWidth-1:0]               wr_data_addr_o,

    output logic                              rd_where_en,
    output logic                              rd_data_en,
    output logic                              rd_prog_en,
    output logic                              rd_abs_cmd_en,
    output logic                              rd_flags_en,
    output logic [BusWidth-1:0]               rd_addr_o,  

    output logic req_o,

// SRAM interface
    input  logic                              req_i,
    input  logic                              we_i,
    input  logic [BusWidth-1:0]               addr_i
);
logic                                         cmderr_valid;
DM::cmderr_e                                      cmderr;                        
// Instance of DMI_Decoder
DMI_Decoder u_dmi_decoder (
    .dmi_req_i        (dmi_req_i),
    .dmi_req_addr_o   (dmi_req_addr_o),
    .dmi_req_op_o     (dmi_req_op_o),
    .dmi_req_data_o   (dmi_req_data_o)
);
logic cmd_valid;
// Instance of ControlUnit1
DM_ControlUnit1 #(
    // Parameter overrides here if needed
) u_control_unit1 (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .dmactive_i         (dmactive_i),

    .resp_queue_full_i  (resp_queue_full_i),
    .resp_queue_empty_i (resp_queue_empty_i),
    .resp_queue_pop_o   (resp_queue_pop_o),
    .resp_queue_push_o  (resp_queue_push_o),

    .dmi_req_valid_i    (dmi_req_valid_i),
    .dmi_req_addr_i     (dmi_req_addr_o),
    .dmi_req_op_i       (dmi_req_op_o),
    .dmi_req_data_i     (dmi_req_data_o),
    .dmi_req_ready_o    (dmi_req_ready_o),

    // DMI Response
    .dmi_resp_valid_o   (dmi_resp_valid_o),
    .dmi_resp_ready_i   (dmi_resp_ready_i),

    // Cmd Error
    .cmderror_valid_i   (cmderr_valid),
    .cmderror_i         (cmderr),
    .cmdbusy_i          (cmdbusy_o),

    .cmd_valid_o        (cmd_valid),        //OK
    .autoexecdata_i     (autoexecdata_i),
    .autoexecprogbuf_i  (autoexecprogbuf_i),

    // Control Signal Output
    .dm_csr_sel_o       (dm_csr_sel_o),
    .set_cmdbusy_o      (set_cmdbusy_o),
    .set_cmderror_o     (set_cmderror_o),
    .dm_csrs_we_o       (dm_csrs_we_o),
    .dm_csrs_re_o       (dm_csrs_re_o)
);  
// Instance of ControlUnit2  
DM_ControlUnit2 i_control_unit2 (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),

    .cmd_valid_i        (cmd_valid),            //OK
    .halted_i           (halted_i),
    .unsupported_cmd_i  (unsupported_command_o), //OK
    .resumereq_i        (resumereq_i),
    .resuming_i         (resuming_i),
    .haltreq_i          (haltreq_i),
    .going_i            (going_i),
    .exception_i        (exception_i),
    .ndmreset_i         (ndmreset_i),
    .halted_int_i       (halted_int_i),

    .go_o               (go_o),
    .resume_o           (resume_o),
    .cmdbusy_o          (cmdbusy_o),
    .cmderror_valid_o   (cmderr_valid),
    .cmderror_o         (cmderr),
    .debug_req_o         (debug_req_o)
  );

// Instance of ControlUnit3                 // DONE
DM_ControlUnit3 #(
    .DbgAddressBits (DbgAddressBits),
    .BusWidth       (BusWidth)
  ) i_control_unit3 (
    // ---- Inputs từ DMI decoder ----
    .req_i              (req_i),   
    .we_i               (we_i),          // 1 = write, 0 = read
    .addr_i             (addr_i),

    // ---- Outputs (ghi-đọc CSR/data trong DM_Mem) ----
    .wr_halted_en       (wr_halted_en),
    .wr_going_en        (wr_going_en),
    .wr_resuming_en     (wr_resuming_en),
    .wr_exception_en    (wr_exception_en),
    .wr_data_en         (wr_data_en),
    .wr_data_addr_o     (wr_data_addr_o),

    .rd_where_en        (rd_where_en),
    .rd_data_en         (rd_data_en),
    .rd_prog_en         (rd_prog_en),
    .rd_abs_cmd_en      (rd_abs_cmd_en),
    .rd_flags_en        (rd_flags_en),
    .rd_addr_o,
    .req_o (req_o)        
  );

// Instance of AbstractCmd_Decoder          // DONE
AbstractCmd_Decoder u_abstract_cmd_decoder (
    .cmd_i               (cmd_i),
    .cmd_type_o          (cmd_type_o),
    .aarsize_o           (aarsize_o),
    .aarpostincrement_o  (aarpostincrement_o),
    .postexec_o          (postexec_o),
    .transfer_o          (transfer_o),
    .write_o             (write_o),
    .regno_o             (regno_o),
    .unsupported_command_o (unsupported_command_o)
);

endmodule: DM_ControlUnit

