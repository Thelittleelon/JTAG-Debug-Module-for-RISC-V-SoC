module DM_ControlUnit1(
  input  logic                              clk_i,
  input  logic                              rst_ni,
  input  logic                              dmactive_i,
  // FIFO Signal  
  input  logic                              resp_queue_full_i,  
  input  logic                              resp_queue_empty_i,
  output logic                              resp_queue_pop_o,
  output logic                              resp_queue_push_o,
  // DMI Request  
  input  logic                              dmi_req_valid_i,
  input  logic [6:0]                        dmi_req_addr_i,
  input  logic [1:0]                        dmi_req_op_i,
  input  logic [31:0]                       dmi_req_data_i,
  output logic                              dmi_req_ready_o,
  // DMI Response
  output logic                              dmi_resp_valid_o,
  input  logic                              dmi_resp_ready_i,
  // Cmd Error Control 
  input  logic                              cmderror_valid_i,  
  input  DM::cmderr_e                           cmderror_i,        
  input  logic                              cmdbusy_i,         
  output logic                              cmd_valid_o,      
  
  input  logic [11:0]                       autoexecdata_i,    
  input logic [15:0]                        autoexecprogbuf_i, 
  // Control Signal
  output DM::dm_csr_e                           dm_csr_sel_o,
  output logic                              set_cmdbusy_o,
  output DM::cmderr_e                           set_cmderror_o,
  output logic                              dm_csrs_we_o,
  output logic                              dm_csrs_re_o
);
  localparam DM::dm_csr_e DataEnd = DM::dm_csr_e'(DM::Data0 + {4'h0, DM::DataCount} - 8'h1);
  localparam DM::dm_csr_e ProgBufEnd = DM::dm_csr_e'(DM::ProgBuf0 + {4'h0, DM::ProgBufSize} - 8'h1);

  DM::dtm_op_e dtm_op;
  assign dtm_op = DM::dtm_op_e'(dmi_req_op_i);
  DM::dm_csr_e    dm_csr_addr;
  assign dm_csr_addr = DM::dm_csr_e'({1'b0, dmi_req_addr_i});

  // Read/ Write enable
  logic dm_csrs_we;     // write = 1
  logic dm_csrs_re;     // read = 1
  logic illegal_write;  // write into read-only  Register
  assign illegal_write = (dtm_op == DM::DTM_WRITE) &&     // Must not write in to R/O registers
                          ((dm_csr_addr == DM::DMStatus) || 
                          (dm_csr_addr == DM::Hartinfo)  || 
                          (dm_csr_addr == DM::NextDM));
  assign dm_csrs_we = (!illegal_write) && (dtm_op == DM::DTM_WRITE) && dmi_req_valid_i && dmi_req_ready_o;
  assign dm_csrs_re = (dtm_op == DM::DTM_READ) && dmi_req_valid_i && dmi_req_ready_o;

  // Get the Data Index
  logic [3:0] autoexecdata_idx; // 0 == Data0 ... 11 == Data11

  assign autoexecdata_idx = 4'({dm_csr_addr} - {DM::Data0});
  // Helper
  DM::abstractcs_t a_abstractcs;
  
  // Cmd Error & Valid control
  DM::cmderr_e        cmderr_d, cmderr_q;
  logic           cmd_valid_d, cmd_valid_q;
  (* xprop_off *) always_comb begin
    // Default assignment
    cmderr_d = cmderr_q;
    cmd_valid_d = 1'b0;

    a_abstractcs = '0;


    if (cmderror_valid_i) begin
      cmderr_d = cmderror_i;
    end

    //READ
    if(dm_csrs_re) begin  
    unique case (dm_csr_addr) inside
    [(DM::Data0): DataEnd]: begin              // Read Data0-Data11
      if (!cmdbusy_i) begin
        // check whether we need to re-execute the command by just giving a cmd_valid
          cmd_valid_d = autoexecdata_i[autoexecdata_idx];
        // An abstract command was executing while one of the data registers was read
      end else begin
            if (cmderr_q == DM::None) begin
              cmderr_d = DM::Busy;
            end
      end
    end

    [(DM::ProgBuf0):ProgBufEnd]: begin                                             
    if (!cmdbusy_i) begin
            cmd_valid_d = autoexecprogbuf_i[{1'b1, dmi_req_addr_i[3:0]}]; // not done yet
          // An abstract command was executing while one of the progbuf registers was read
          end else begin
            if (cmderr_q == DM::None) begin
              cmderr_d = DM::Busy;
            end
          end
    end
    endcase
    end else if (dm_csrs_we) begin
      unique case(dm_csr_addr) inside
      [(DM::Data0):DataEnd]: begin
        if (!cmdbusy_i) begin
          // check whether we need to re-execute the command (just give a cmd_valid)
          cmd_valid_d = autoexecdata_i[autoexecdata_idx];   // not done yet
          //An abstract command was executing while one of the data registers was written
        end else begin
          if (cmderr_q == DM::None) begin
            cmderr_d = DM::Busy;
            end
          end
      end
      // Only cmderr is write able
      DM::AbstractCS: begin
        a_abstractcs = DM::abstractcs_t'(dmi_req_data_i);
        if (!cmdbusy_i) begin
          cmderr_d = DM::cmderr_e'(~a_abstractcs.cmderr & cmderr_q);    // Write 1 to clear
        end else begin
          if (cmderr_q == DM::None) begin
            cmderr_d = DM::Busy;
          end
        end       
      end

      DM::Command: begin
        // writes are ignored if a command is already busy
        if (!cmdbusy_i) begin
          cmd_valid_d = 1'b1;
          // if there was an attempted to write during a busy execution
          // and the cmderror field is zero set the busy error
        end else begin
          if (cmderr_q == DM::None) begin
            cmderr_d = DM::Busy;
          end
        end
      end

      DM::AbstractAuto: begin 
        if(cmdbusy_i) begin
          if (cmderr_q == DM::None) begin
            cmderr_d = DM::Busy;
          end
        end
      end

      [(DM::ProgBuf0):ProgBufEnd]: begin
        if (!cmdbusy_i) begin
            cmd_valid_d = autoexecprogbuf_i[{1'b1, dmi_req_addr_i[3:0]}];    
          //An abstract command was executing while one of the progbuf registers was written
          end else begin
            if (cmderr_q == DM::None) begin
              cmderr_d = DM::Busy;
            end
          end
      end

      endcase
    end
  end

  always_ff@(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      cmderr_q       <= DM::None;
      cmd_valid_q    <= '0;
    end else begin
      // if(dmactive_i) begin 
      // cmderr_q       <= DM::None;
      // cmd_valid_q    <= '0;  
      //end else begin 
      cmderr_q       <= cmderr_d;
      cmd_valid_q    <= cmd_valid_d;
      //end
    end
  end

  // Output assignment
  assign  dm_csr_sel_o = dm_csr_addr;
  assign  set_cmdbusy_o = cmdbusy_i;
  assign  set_cmderror_o = cmderr_q;
  assign  cmd_valid_o = cmd_valid_q;
  assign  dm_csrs_we_o = dm_csrs_we;
  assign  dm_csrs_re_o = dm_csrs_re;
  
  assign dmi_resp_valid_o     = ~resp_queue_empty_i;
  assign dmi_req_ready_o      = ~resp_queue_full_i;

  assign resp_queue_pop_o     = dmi_resp_ready_i & ~resp_queue_empty_i;
  assign resp_queue_push_o    = dmi_req_valid_i & dmi_req_ready_o;

endmodule : DM_ControlUnit1

