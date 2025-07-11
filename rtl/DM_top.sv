module DM_top #(
  parameter int unsigned        NrHarts          = 1,
  parameter int unsigned        BusWidth         = 32,
  parameter logic [NrHarts-1:0] SelectableHarts  = {NrHarts{1'b1}},
  parameter bit                 ReadByteEnable   = 1,
   parameter int unsigned       DmBaseAddress    = 'h1000, // default to non-zero page
  parameter int unsigned DbgAddressBits = 12
) (
  input  logic                  clk_i,       // clock
  input  logic                  rst_ni,

  input  logic [31:0]           next_dm_addr_i,
  input  logic                  testmode_i,
  output logic                  ndmreset_o,  
  input  logic                  ndmreset_ack_i, 
  output logic                  dmactive_o,  
  output logic [NrHarts-1:0]    debug_req_o, 
 
  input  logic [NrHarts-1:0]    unavailable_i,
  input  DM::hartinfo_t [NrHarts-1:0] hartinfo_i,

  input  logic                  slave_req_i,
  input  logic                  slave_we_i,
  input  logic [BusWidth-1:0]   slave_addr_i,
  input  logic [BusWidth/8-1:0] slave_be_i,
  input  logic [BusWidth-1:0]   slave_wdata_i,
  output logic [BusWidth-1:0]   slave_rdata_o,

  output logic                  master_req_o,
  output logic [BusWidth-1:0]   master_add_o,
  output logic                  master_we_o,
  output logic [BusWidth-1:0]   master_wdata_o,
  output logic [BusWidth/8-1:0] master_be_o,
  input  logic                  master_gnt_i,
  input  logic                  master_r_valid_i,
  input  logic [BusWidth-1:0]   master_r_rdata_i,

  input  logic                  master_r_err_i,
  input  logic                  master_r_other_err_i, 


  // Connection to DTM - compatible to RocketChip Debug Module
  input  logic                  dmi_rst_ni,  // not assigned
  input  logic                  dmi_req_valid_i,
  output logic                  dmi_req_ready_o,
  input  DM::dmi_req_t              dmi_req_i,

  output logic                  dmi_resp_valid_o,
  input  logic                  dmi_resp_ready_i,
  output DM::dmi_resp_t             dmi_resp_o
);

  logic [11:0]                  autoexecdata;
  logic [15:0]                  autoexecprogbuf;
  logic [19:0]                  hartsel;  

  logic                         haltreq, resumereq;                
  DM::command_t                     abstract_cmd;
  logic                         resp_queue_full, resp_queue_empty;
  logic                         resp_queue_pop,  resp_queue_push;

  DM::dm_csr_e                      dm_csr_sel;         
  logic                         set_cmdbusy; 
  DM::cmderr_e                      set_cmderr;
  logic                         dm_csrs_we, dm_csrs_re;             

  logic                         cmdbusy;

  logic                         wr_halted_en, wr_resuming_en, wr_going_en, wr_exception_en;
  logic                         wr_data_en;
  logic [BusWidth-1:0]          wr_data_addr;

  logic                         rd_where_en, rd_data_en, rd_prog_en, rd_abs_cmd_en, rd_flags_en;
  logic [BusWidth-1:0]          rd_addr;

  logic                         resume, go;
  logic                         halted_int;

  logic                         resuming, halted, going, exception;

  DM::cmdtype_e                     cmd_type;                    
  logic [2:0]                   aarsize;
  logic                         aarpostincrement;
  logic                         postexec, transfer, write;
  logic [15:0]                  regno;
  logic                         unsupported_command;

  logic [6:0]                   dmi_req_addr;                
  logic [1:0]                   dmi_req_op;
  logic [31:0]                  dmi_req_data;

  logic req;
// logic cmderr_valid;//??
//   logic [2:0] cmderr;                       // dm::cmderr_t               
  // --------------------------------------------------------------------------
  // Instance DM_datapath
  // --------------------------------------------------------------------------
  DM_Datapath #(
    .NrHarts        (NrHarts),
    .BusWidth       (BusWidth),
    .DbgAddressBits (DbgAddressBits),
    .SelectableHarts(SelectableHarts)
  ) u_dm_datapath (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),

    .next_dm_addr_i      (next_dm_addr_i),   // ví dụ addr kế tiếp
    .testmode_i          (testmode_i),
    .unavailable_i       (unavailable_i),
    .dmi_rst_ni          (dmi_rst_ni),
    .dmactive_o          (dmactive_o),                // quan sát ở waveform

    .hartinfo_i          (hartinfo_i),
    .ndmreset_o          (ndmreset_o),
    .ndmreset_ack_i      (ndmreset_ack_i),

    .haltreq_o           (haltreq),
    .resumereq_o         (resumereq),
    .hartsel_o           (hartsel),                 // hart nào đang được chọn 

    // ------------------ DMI ------------------       
    .dmi_resp_o          (dmi_resp_o),

    // .dmi_req_addr_i      (dmi_req_addr),
    // .dmi_req_op_i        (dmi_req_op),
    .dmi_req_data_i      (dmi_req_data),
    .cmd_o               (abstract_cmd),                // abstract command đi ra

    // ---------- FIFO phản hồi ----------
    .resp_queue_full_o   (resp_queue_full),
    .resp_queue_empty_o  (resp_queue_empty),
    .resp_queue_pop_i    (resp_queue_pop),
    .resp_queue_push_i   (resp_queue_push),

    .dm_csr_sel_i        (dm_csr_sel),
    .set_cmdbusy_i       (set_cmdbusy),
    .set_cmderror_i      (set_cmderr),
    .dm_csrs_we_i        (dm_csrs_we),
    .dm_csrs_re_i        (dm_csrs_re),

    // ---------- ControlUnit 2 ----------
    .cmdbusy_i           (cmdbusy),

    // ---------- Write-side signals ----------
    .wr_halted_en        (wr_halted_en),
    .wr_resuming_en      (wr_resuming_en),
    .wr_going_en         (wr_going_en),
    .wr_exception_en     (wr_exception_en),
    .wr_data_en          (wr_data_en),
    .wr_data_addr_i      (wr_data_addr),

    // ---------- Read-side signals ----------
    .rd_where_en         (rd_where_en),
    .rd_data_en          (rd_data_en),
    .rd_prog_en          (rd_prog_en),
    .rd_abs_cmd_en       (rd_abs_cmd_en),
    .rd_flags_en         (rd_flags_en),
    .rd_addr_i           (rd_addr),

    .req_i (req),

    .wdata_i             (slave_wdata_i),
    .be_i                (slave_be_i),
    .resume_i            (resume),
    .go_i                (go),
    .halted_int_o        (halted_int),

    .resuming_o          (resuming),
    .halted_o            (halted),
    .going_o             (going),
    .exception_o         (exception),
    .autoexecdata_o      (autoexecdata),                    
    .autoexecprogbuf_o   (autoexecprogbuf),                     

    // ---------- AbstractCmd inputs ----------
    .cmd_type_i          (cmd_type),
    .aarsize_i           (aarsize),
    .aarpostincrement_i  (aarpostincrement),
    .postexec_i          (postexec),
    .transfer_i          (transfer),
    .write_i             (write),
    .regno_i             (regno),
    .unsupported_command_i (unsupported_command),

    // ---------- SBA ----------
    .master_req_o        (master_req_o),
    .master_add_o        (master_add_o),
    .master_we_o         (master_we_o),
    .master_wdata_o      (master_wdata_o),
    .master_be_o         (master_be_o),
    .master_gnt_i        (master_gnt_i),
    .master_r_valid_i    (master_r_valid_i),
    .master_r_err_i      (master_r_err_i),
    .master_r_other_err_i(master_r_other_err_i),
    .master_r_rdata_i    (master_r_rdata_i),

    .rdata_o             (slave_rdata_o)              // đọc DM-mem
  );

  DM_ControlUnit #(
    .DbgAddressBits(DbgAddressBits),
    .BusWidth(BusWidth)
  ) u_dm_cu (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),

    .ndmreset_i          (ndmreset_o),                 
    .hartsel_i           (hartsel),                
    .dmactive_i          (dmactive_o),

    //-------------- DMI Decoder ----------------
    .dmi_req_i           (dmi_req_i),
    .dmi_req_addr_o      (dmi_req_addr),                    // quan sát nếu cần
    .dmi_req_op_o        (dmi_req_op),
    .dmi_req_data_o      (dmi_req_data),

    //-------------- Abstract Cmd ---------------
    .cmd_i               (abstract_cmd),
    .cmd_type_o          (cmd_type), .aarsize_o(aarsize), .aarpostincrement_o(aarpostincrement),
    .postexec_o          (postexec), .transfer_o(transfer), .write_o(write),
    .regno_o             (regno), .unsupported_command_o(unsupported_command),

    //-------------- ControlUnit1 ---------------
    .resp_queue_full_i   (resp_queue_full),
    .resp_queue_empty_i  (resp_queue_empty),
    .resp_queue_pop_o    (resp_queue_pop),
    .resp_queue_push_o   (resp_queue_push),

    .dmi_req_valid_i     (dmi_req_valid_i),
    .dmi_req_ready_o     (dmi_req_ready_o),                    // handshake trả về

    .dmi_resp_valid_o    (dmi_resp_valid_o),
    .dmi_resp_ready_i    (dmi_resp_ready_i),

    .autoexecdata_i      (autoexecdata),                    
    .autoexecprogbuf_i   (autoexecprogbuf),                      

    .dm_csr_sel_o        (dm_csr_sel),
    .set_cmdbusy_o       (set_cmdbusy),
    .set_cmderror_o      (set_cmderr),
    .dm_csrs_we_o        (dm_csrs_we),
    .dm_csrs_re_o        (dm_csrs_re),

    //---------------- ControlUnit2 -------------
    .halted_i            (halted),
    .resumereq_i         (resumereq),
    .resuming_i          (resuming),
    .haltreq_i           (haltreq),
    .going_i             (going),
    .exception_i         (exception),
    .halted_int_i        (halted_int),

    .go_o                (go),
    .resume_o            (resume),
    .cmdbusy_o           (cmdbusy),
    // .cmderror_valid_o    (cmderr_valid),
    // .cmderror_o          (cmderr),
    .debug_req_o         (debug_req_o),

    //---------------- ControlUnit3 -------------
    .wr_halted_en        (wr_halted_en),
    .wr_going_en         (wr_going_en),
    .wr_resuming_en      (wr_resuming_en),
    .wr_exception_en     (wr_exception_en),
    .wr_data_en          (wr_data_en),
    .wr_data_addr_o      (wr_data_addr),

    .rd_where_en         (rd_where_en),
    .rd_data_en          (rd_data_en),
    .rd_prog_en          (rd_prog_en),
    .rd_abs_cmd_en       (rd_abs_cmd_en),
    .rd_flags_en         (rd_flags_en),
    .rd_addr_o           (rd_addr),

    .req_o (req),

    //---------------- SRAM Port ----------------
    .req_i               (slave_req_i),
    .we_i                (slave_we_i),
    .addr_i              (slave_addr_i)
  );
endmodule

