module DM_Datapath #(
  parameter int unsigned NrHarts = 1,
  parameter int unsigned BusWidth = 32,
  parameter logic [NrHarts-1:0] SelectableHarts  = {NrHarts{1'b1}},
  parameter  int unsigned DbgAddressBits = 12
) (
  input  logic                              clk_i,       
  input  logic                              rst_ni,

  input  logic [31:0]                       next_dm_addr_i,
  input  logic                              testmode_i,
  input  logic                              unavailable_i,
  input  logic                              dmi_rst_ni,
  output logic                              dmactive_o,  // debug module is active

  input  DM::hartinfo_t [NrHarts-1:0]           hartinfo_i,      // static hartinfo

  output logic                              ndmreset_o,  
  input  logic                              ndmreset_ack_i, 

  output logic [NrHarts-1:0]                haltreq_o,       // request to halt a hart
  output logic [NrHarts-1:0]                resumereq_o,  

 
  output DM::dmi_resp_t                         dmi_resp_o,

  // DMI Decoder Interfaces
  // input  logic [6:0]                        dmi_req_addr_i,
  // input  logic [1:0]                        dmi_req_op_i,
  input  logic [31:0]                       dmi_req_data_i,
  // Abstract Command Interfaces
  output DM::command_t                          cmd_o,    
  output logic [19:0]                       hartsel_o,          


  // ControlUnit 1 Interfaces
  output  logic                             resp_queue_full_o,  
  output  logic                             resp_queue_empty_o,
  input logic                               resp_queue_pop_i,
  input logic                               resp_queue_push_i,

  input DM::dm_csr_e                            dm_csr_sel_i,
  input logic                               set_cmdbusy_i,
  input DM::cmderr_e                            set_cmderror_i,
  input logic                               dm_csrs_we_i,
  input logic                               dm_csrs_re_i,

  // ControlUnit 2 Interfaces
  input logic                               cmdbusy_i,

  // 
  input  logic                              wr_halted_en,
  input  logic                              wr_resuming_en,
  input  logic                              wr_going_en,
  input  logic                              wr_exception_en,
  input  logic                              wr_data_en,
  input  logic [BusWidth-1:0]               wr_data_addr_i,

  input  logic                              rd_where_en,
  input  logic                              rd_data_en,
  input  logic                              rd_prog_en,
  input  logic                              rd_abs_cmd_en,
  input  logic                              rd_flags_en,
  input  logic [BusWidth-1:0]               rd_addr_i,

  input logic req_i,

  input  logic [31:0]                       wdata_i,
  input  logic [3:0]                        be_i,
  input  logic                              resume_i,
  input  logic                              go_i,
  output logic                              halted_int_o,

  output  logic                             resuming_o,
  output  logic                             halted_o, 
  output  logic                             going_o, 
  output  logic                             exception_o,
  output  logic [11:0]                      autoexecdata_o,
  output  logic [15:0]                      autoexecprogbuf_o,

  // AbstractCmd Interface
  input  DM::cmdtype_e        cmd_type_i,
  input  logic [2:0]      aarsize_i,
  input  logic            aarpostincrement_i,
  input  logic            postexec_i,
  input  logic            transfer_i,
  input  logic            write_i,
  input  logic [15:0]     regno_i,

  input logic             unsupported_command_i,

  // SBA Interface
  output logic                  master_req_o,
  output logic [BusWidth-1:0]   master_add_o,
  output logic                  master_we_o,
  output logic [BusWidth-1:0]   master_wdata_o,
  output logic [BusWidth/8-1:0] master_be_o,
  input  logic                  master_gnt_i,
  input  logic                  master_r_valid_i,
  input  logic                  master_r_err_i,
  input  logic                  master_r_other_err_i, 
  input  logic [BusWidth-1:0]   master_r_rdata_i,

  output logic [BusWidth-1:0]              rdata_o 
);

// Instance of the dmi_resp_FIFO module
DM::dmi_resp_t resp_queue_inp;
logic [31:0] resp_data;
logic [1:0]  resp_resp;
assign resp_queue_inp.data = resp_data;
assign resp_queue_inp.resp = resp_resp;

// System Bus Access Module
logic [BusWidth-1:0]              sbaddress_csrs_sba;
logic [BusWidth-1:0]              sbaddress_sba_csrs;
logic                             sbaddress_write_valid;
logic                             sbreadonaddr;
logic                             sbautoincrement;
logic [2:0]                       sbaccess;
logic                             sbreadondata;
logic [BusWidth-1:0]              sbdata_write;
logic                             sbdata_read_valid;
logic                             sbdata_write_valid;
logic [BusWidth-1:0]              sbdata_read;
logic                             sbdata_valid;
logic                             sbbusy;
logic                             sberror_valid;
logic [2:0]                       sberror;

// Wires
logic                             clear_resumeack;

logic [DM::ProgBufSize-1:0][31:0]     progbuf;
logic [DM::DataCount-1:0][31:0]       data_csrs_mem;
logic [DM::DataCount-1:0][31:0]       data_mem_csrs; 
logic                             data_valid;
logic [7:0][63:0]                 abstract_cmd_rom;

// DMI_Resp_FIFO #(                                // DONE
// // Add any parameter overrides here if needed
// ) u_dmi_resp_fifo (
//     .clk_i              (clk_i),
//     .rst_ni             (rst_ni), 
//     .testmode_i         (testmode_i),
//     .dmi_rst_ni         (dmi_rst_ni),

//     .resp_queue_inp_i   (resp_queue_inp),           

//     .resp_queue_push_i  (resp_queue_push_i),
//     .resp_queue_pop_i   (resp_queue_pop_i),

//     .dmi_resp_o         (dmi_resp_o),               

//     .resp_queue_full_o  (resp_queue_full_o),
//     .resp_queue_empty_o (resp_queue_empty_o)
// );

fifo_v2 #(
  .dtype            ( logic [$bits(dmi_resp_o)-1:0] ),
  .DEPTH            ( 2                             )
) i_fifo (
  .clk_i,
  .rst_ni,
  .flush_i          ( ~dmi_rst_ni          ), // Flush the queue if the DTM is
                                              // reset
  .testmode_i       ( testmode_i           ),
  .full_o           ( resp_queue_full_o      ),
  .empty_o          ( resp_queue_empty_o     ),
  .alm_full_o       (                      ),
  .alm_empty_o      (                      ),
  .data_i           ( resp_queue_inp       ),
  .push_i           ( resp_queue_push_i      ),
  .data_o           ( dmi_resp_o           ),
  .pop_i            ( resp_queue_pop_i       )
);

// Instance of DM_CSRS              //not done yet
DM_CSRS #(
  .NrHarts         (NrHarts),
  .BusWidth        (BusWidth),
  .SelectableHarts ({NrHarts{1'b1}})       // cho phép debug tất cả các hart
) i_dm_csrs (
  .clk_i                        (clk_i),
  .rst_ni                       (rst_ni),
  .next_dm_addr_i               (next_dm_addr_i),

  .ndmreset_o                   (ndmreset_o),  
  .ndmreset_ack_i               (ndmreset_ack_i),      
  .dmactive_o                   (dmactive_o), 

  .clear_resumeack_o            (clear_resumeack ), 

  .hartinfo_i                   (hartinfo_i),

  .unavailable_i                (unavailable_i),
  .resumeack_i                  (resuming_o), // resumeack from hart

  // Global control outputs / input

  // DMI interfaces
  .dmi_data_i                   (dmi_req_data_i),       
  .dmi_data_o                   (resp_data),       
  .dmi_resp_o                   (resp_resp),      
  //
  .halted_i                     (halted_o),                 
  .hartsel_o                    (hartsel_o), // DM_CSR_SEL  
  .haltreq_o                    (haltreq_o),                // DM_HALTREQ
  .resumereq_o                  (resumereq_o),              // DM_RESUMEREQ
  .autoexecdata_o               (autoexecdata_o),             // DM_AUTOEXECDATA 
  .autoexecprogbuf_o            (autoexecprogbuf_o),          // DM_AUTOEXECPROGBUF  

  // --------- Interface tới DM-MEM (datapath) --------------------------------
  .cmd_o                        (cmd_o),         
  .progbuf_o                    (progbuf),      
  .data_o                       (data_csrs_mem),           
  .data_i                       (data_mem_csrs),              
  .data_valid_i                 (data_valid),             

  // --------- CSR control -----------------------------------------------------  DONE
  .dm_csr_sel_i                 (dm_csr_sel_i),
  .set_cmdbusy_i                (set_cmdbusy_i),
  .set_cmderror_i               (set_cmderror_i),
  .dm_csrs_we_i                 (dm_csrs_we_i),
  .dm_csrs_re_i                 (dm_csrs_re_i),

  // --------- System Bus Access (SBA) ------------------------ // DONE
  .sbaddress_o                  (sbaddress_csrs_sba),
  .sbaddress_i                  (sbaddress_sba_csrs),
  .sbaddress_write_valid_o      (sbaddress_write_valid),

  .sbreadonaddr_o               (sbreadonaddr),
  .sbautoincrement_o            (sbautoincrement),
  .sbaccess_o                   (sbaccess),

  .sbreadondata_o               (sbreadondata),
  .sbdata_o                     (sbdata_write),
  .sbdata_read_valid_o          (sbdata_read_valid),
  .sbdata_write_valid_o         (sbdata_write_valid),

  .sbdata_i                     (sbdata_read),
  .sbdata_valid_i               (sbdata_valid),   

  .sbbusy_i                     (sbbusy),
  .sberror_valid_i              (sberror_valid),
  .sberror_i                    (sberror)
);
DM_SBA i_dm_sba_control (       // DONE
  .clk_i                  (clk_i), 
  .rst_ni                 (rst_ni),
  .dmactive_i             (dmactive_o),
  // OKE
  .master_req_o           (master_req_o),
  .master_add_o           (master_add_o),
  .master_we_o            (master_we_o),
  .master_wdata_o         (master_wdata_o),
  .master_be_o            (master_be_o),
  .master_gnt_i           (master_gnt_i),
  .master_r_valid_i       (master_r_valid_i),
  .master_r_err_i         (master_r_err_i),
  .master_r_other_err_i   (master_r_other_err_i),
  .master_r_rdata_i       (master_r_rdata_i),

  .sbaddress_i            (sbaddress_csrs_sba),
  .sbaddress_write_valid_i(sbaddress_write_valid),
  .sbreadonaddr_i         (sbreadonaddr),
  .sbaddress_o            (sbaddress_sba_csrs),
  .sbautoincrement_i      (sbautoincrement),
  .sbaccess_i             (sbaccess),

  .sbreadondata_i         (sbreadondata),
  .sbdata_i               (sbdata_write),
  .sbdata_read_valid_i    (sbdata_read_valid),
  .sbdata_write_valid_i   (sbdata_write_valid),

  .sbdata_o               (sbdata_read),
  .sbdata_valid_o         (sbdata_valid),

  .sbbusy_o               (sbbusy),
  .sberror_valid_o        (sberror_valid),
  .sberror_o              (sberror)
);

// Instance of AbstractCmd_ROM          // DONE
AbstractCmd_ROM #(
    .NrHarts         (1),
    .BusWidth        (32),
    .SelectableHarts (1'b1),      
    .DmBaseAddress   ('h1000)
) u_abstract_cmd_rom (
    // input from AbstractCmd Decoder
    .cmd_type_i             (cmd_type_i),
    .aarsize_i              (aarsize_i),
    .aarpostincrement_i     (aarpostincrement_i),
    .postexec_i             (postexec_i),
    .transfer_i             (transfer_i),
    .write_i                (write_i),
    .regno_i                (regno_i),
    .unsupported_command_i  (unsupported_command_i),  

    .abstract_cmd_o         (abstract_cmd_rom)                                               
);

DM_Mem #(
    .DbgAddressBits (DbgAddressBits),
    .BusWidth       (BusWidth)
) i_dm_mem (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),

    .wr_halted_en    (wr_halted_en),
    .wr_resuming_en  (wr_resuming_en),
    .wr_going_en     (wr_going_en),
    .wr_exception_en (wr_exception_en),
    .wr_data_en      (wr_data_en),
    .wr_data_addr_i  (wr_data_addr_i),

    .rd_where_en     (rd_where_en),
    .rd_data_en      (rd_data_en),
    .rd_prog_en      (rd_prog_en),
    .rd_abs_cmd_en   (rd_abs_cmd_en),
    .rd_flags_en     (rd_flags_en),
    .rd_addr_i       (rd_addr_i),

    .req_i(req_i),

    .wdata_i         (wdata_i),
    .be_i            (be_i),

    .resume_i        (resume_i),
    .go_i            (go_i),
    .halted_int_o    (halted_int_o),

    .clear_resumeack_i (clear_resumeack),
    .ndmreset_i        (ndmreset_o),
    .resumereq_i       (resumereq_o),

    // --- Abstract-Command Decoder side ---
    .cmdbusy_i       (cmdbusy_i),
    .abstract_cmd_i  (abstract_cmd_rom),
    .cmd_type_i      (cmd_type_i),
    .postexec_i      (postexec_i),
    .transfer_i      (transfer_i),

    .progbuf_i       (progbuf),
    .data_i          (data_csrs_mem),

    // --- Outputs ---
    .data_o          (data_mem_csrs),
    .data_valid_o    (data_valid),

    .halted_o        (halted_o),
    .resuming_o      (resuming_o),
    .going_o         (going_o),
    .exception_o     (exception_o),

    .rdata_o         (rdata_o)
);   


endmodule

