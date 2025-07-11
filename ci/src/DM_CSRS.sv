module DM_CSRS #(
  parameter int unsigned        NrHarts          = 1,
  parameter int unsigned        BusWidth         = 32,
  parameter logic [NrHarts-1:0] SelectableHarts  = {NrHarts{1'b1}}
) (

  input  logic                                 clk_i,           // Clock
  input  logic                                 rst_ni,          // Asynchronous reset active low
  input  logic [31:0]                          next_dm_addr_i,  // Static next_dm word address.
  // // Global Control Signals                  //ok
  output logic                                 ndmreset_o,      // non-debug module reset active-high
  input  logic                                 ndmreset_ack_i,  // non-debug module reset ack pulse   //havereset
  output logic                                 dmactive_o,      // 1 -> debug-module is active,       // dmi.dmiactive
  //                                           //ok                 // 0 -> synchronous re-set
  output logic                                 clear_resumeack_o, // clear the resumeack bit in dmcontrol
  // Static input
  input  DM::hartinfo_t [NrHarts-1:0]              hartinfo_i,

  // DMI Decoder Interface    
  input  logic [31:0]                          dmi_data_i,      // DMI Request Data in
  output logic [31:0]                          dmi_data_o,      // DMI Response Data out
  output logic [1:0]                           dmi_resp_o,      // DMI Respomse Status out

  // DM_MEM Interface 
  output DM::command_t                             cmd_o,           // abstract command 
  output logic [DM::ProgBufSize-1:0][31:0]         progbuf_o,       // to system bus
  output logic [DM::DataCount-1:0][31:0]           data_o,

  input  logic [DM::DataCount-1:0][31:0]           data_i,
  input  logic                                 data_valid_i,

  // Control signal in 
  input DM::dm_csr_e                               dm_csr_sel_i,
  input logic                                  set_cmdbusy_i,
  input DM::cmderr_e                               set_cmderror_i,
  input logic                                  dm_csrs_we_i,
  input logic                                  dm_csrs_re_i,
  
  input logic                                  unavailable_i,
  input  logic [NrHarts-1:0]                   resumeack_i,

  input logic  [NrHarts-1:0]                   halted_i,

  output logic  [11:0]                         autoexecdata_o,
  output logic  [15:0]                         autoexecprogbuf_o,

    // hart control
  output logic [19:0]                          hartsel_o,       // hartselect to ctrl module
  output logic [NrHarts-1:0]                   haltreq_o,       // request to halt a hart
  output logic [NrHarts-1:0]                   resumereq_o,  

  // SBA Related
  output logic [BusWidth-1:0]                  sbaddress_o,
  input  logic [BusWidth-1:0]                  sbaddress_i,
  output logic                                 sbaddress_write_valid_o,
  // control signals in
  output logic                                 sbreadonaddr_o,
  output logic                                 sbautoincrement_o,
  output logic [2:0]                           sbaccess_o,
  // data out
  output logic                                 sbreadondata_o,
  output logic [BusWidth-1:0]                  sbdata_o,
  output logic                                 sbdata_read_valid_o,
  output logic                                 sbdata_write_valid_o,
  // read data in
  input  logic [BusWidth-1:0]                  sbdata_i,
  input  logic                                 sbdata_valid_i,
  // control signals
  input  logic                                 sbbusy_i,
  input  logic                                 sberror_valid_i, // bus error occurred
  input  logic [2:0]                           sberror_i // bus error occurred

  
);
  localparam DM::dm_csr_e DataEnd = DM::dm_csr_e'(DM::Data0 + {4'h0, DM::DataCount} - 8'h1);
  localparam DM::dm_csr_e ProgBufEnd = DM::dm_csr_e'(DM::ProgBuf0 + {4'h0, DM::ProgBufSize} - 8'h1);

  // DM Registers
  // Control & Status Registers
  DM::dmcontrol_t                                  dmcontrol_d, dmcontrol_q;
  DM::dmstatus_t                                   dmstatus; // Read Only
  DM::hartinfo_t                                   hartinfo; // Static
  // AbstractCmd Register
  DM::abstractcs_t                                 abstractcs; // Read Only
  DM::command_t                                    command_d, command_q;
  DM::abstractauto_t                               abstractauto_d, abstractauto_q;
  logic [DM::DataCount-1:0][31:0]                  data_d, data_q;
  // ProBuff Registers
  logic [DM::ProgBufSize-1:0][31:0]                progbuf_d, progbuf_q;
  // SBA Registers
  DM::sbcs_t                                       sbcs_d, sbcs_q;
  logic [63:0]                                 sbaddr_d, sbaddr_q;
  logic [63:0]                                 sbdata_d, sbdata_q;
  logic [NrHarts-1:0]                          havereset_d, havereset_q;
  // Haltsume registers
  logic [31:0] haltsum0, haltsum1, haltsum2, haltsum3;
  logic [((NrHarts-1)/2**5 + 1) * 32 - 1 : 0] halted;
  logic [(NrHarts-1)/2**5:0][31:0] halted_reshaped0;
  logic [(NrHarts-1)/2**10:0][31:0] halted_reshaped1;
  logic [(NrHarts-1)/2**15:0][31:0] halted_reshaped2;
  logic [((NrHarts-1)/2**10+1)*32-1:0] halted_flat1;
  logic [((NrHarts-1)/2**15+1)*32-1:0] halted_flat2;
  logic [31:0] halted_flat3;

  // haltsum0
  logic [14:0] hartsel_idx0;
  always_comb begin : p_haltsum0
    halted              = '0;
    haltsum0            = '0;
    hartsel_idx0        = hartsel_o[19:5];
    halted[NrHarts-1:0] = halted_i;
    halted_reshaped0    = halted;
    if (hartsel_idx0 < 15'((NrHarts-1)/2**5+1)) begin
      haltsum0 = halted_reshaped0[hartsel_idx0];
    end
  end
  // haltsum1
  logic [9:0] hartsel_idx1;
  always_comb begin : p_reduction1
    halted_flat1 = '0;
    haltsum1     = '0;
    hartsel_idx1 = hartsel_o[19:10];

    for (int unsigned k = 0; k < (NrHarts-1)/2**5+1; k++) begin
      halted_flat1[k] = |halted_reshaped0[k];
    end
    halted_reshaped1 = halted_flat1;

    if (hartsel_idx1 < 10'(((NrHarts-1)/2**10+1))) begin
      haltsum1 = halted_reshaped1[hartsel_idx1];
    end
  end
  // haltsum2
  logic [4:0] hartsel_idx2;
  always_comb begin : p_reduction2
    halted_flat2 = '0;
    haltsum2     = '0;
    hartsel_idx2 = hartsel_o[19:15];

    for (int unsigned k = 0; k < (NrHarts-1)/2**10+1; k++) begin
      halted_flat2[k] = |halted_reshaped1[k];
    end
    halted_reshaped2 = halted_flat2;

    if (hartsel_idx2 < 5'(((NrHarts-1)/2**15+1))) begin
      haltsum2         = halted_reshaped2[hartsel_idx2];
    end
  end
  // haltsum3
  always_comb begin : p_reduction3
    halted_flat3 = '0;
    for (int unsigned k = 0; k < NrHarts/2**15+1; k++) begin
      halted_flat3[k] = |halted_reshaped2[k];
    end
    haltsum3 = halted_flat3;
  end

  assign hartsel_o         = {dmcontrol_q.hartselhi, dmcontrol_q.hartsello};

  // helper variables
  DM::abstractcs_t a_abstractcs;
  DM::sbcs_t sbcs;
  logic [3:0] autoexecdata_idx; // 0 == Data0 ... 11 == Data11
  assign autoexecdata_idx = 4'({dm_csr_sel_i} - {DM::Data0});



always_comb (*xprop_off *) begin : csr_read_write
    // --------------------
    // Static Values (R/O)
    // --------------------
    // dmstatus
    dmstatus    = '0;
    dmstatus.version = DM::DbgVersion013;
    // no authentication implemented
    dmstatus.authenticated = 1'b1;
    // we do not support halt-on-reset sequence
    dmstatus.hasresethaltreq = 1'b0;
    dmstatus.allhavereset = havereset_q;
    dmstatus.anyhavereset = havereset_q;

    dmstatus.allresumeack = resumeack_i;
    dmstatus.anyresumeack = resumeack_i;

    dmstatus.allunavail   = unavailable_i;
    dmstatus.anyunavail   = unavailable_i;

    // as soon as we are out of the legal Hart region tell the debugger
    // that there are only non-existent harts
    dmstatus.allnonexistent = logic'(32'(hartsel_o) > (NrHarts - 1));
    dmstatus.anynonexistent = logic'(32'(hartsel_o) > (NrHarts - 1));

    // We are not allowed to be in multiple states at once. This is a to
    // make the running/halted and unavailable states exclusive.
    dmstatus.allhalted    = halted_i & ~unavailable_i;
    dmstatus.anyhalted    = halted_i & ~unavailable_i;

    dmstatus.allrunning   = ~halted_i & ~unavailable_i;
    dmstatus.anyrunning   = ~halted_i & ~unavailable_i;

    // abstractcs
    abstractcs = '0;
    abstractcs.datacount = DM::DataCount;
    abstractcs.progbufsize = DM::ProgBufSize;
    abstractcs.cmderr = set_cmderror_i;

    // abstractautoexec
    abstractauto_d = abstractauto_q;
    abstractauto_d.zero0 = '0;

    // default assignments
    havereset_d             = havereset_q;
    dmcontrol_d             = dmcontrol_q;
    command_d               = command_q;
    progbuf_d               = progbuf_q;
    data_d                  = data_q;
    sbcs_d                  = sbcs_q;
    sbaddr_d                = 64'(sbaddress_i);
    sbdata_d                = sbdata_q;

    dmi_data_o              = 32'h0;
    dmi_resp_o              = DM::DTM_SUCCESS;
    sbaddress_write_valid_o = 1'b0;
    sbdata_read_valid_o     = 1'b0;
    sbdata_write_valid_o    = 1'b0;
    clear_resumeack_o       = 1'b0;

    // helper variables
    sbcs         = '0;
    a_abstractcs = '0;

    // READ OPERATION
    if(dm_csrs_re_i) begin
      unique case(dm_csr_sel_i) inside
      DM::DMControl:    dmi_data_o = dmcontrol_q;
      DM::DMStatus:     dmi_data_o = dmstatus;
      DM::Hartinfo:     dmi_data_o = hartinfo_i;
      DM::AbstractCS:   dmi_data_o = abstractcs;
      DM::AbstractAuto: dmi_data_o = abstractauto_q;
      DM::Command:      dmi_data_o = '0;
      DM::NextDM:       dmi_data_o = next_dm_addr_i;
      DM::HaltSum0:     dmi_data_o = haltsum0;
      DM::HaltSum1:     dmi_data_o = haltsum1;
      DM::HaltSum2:     dmi_data_o = haltsum2;
      DM::HaltSum3:     dmi_data_o = haltsum3;

      [DM::Data0:DataEnd]: begin
        dmi_data_o = data_q[$clog2(DM::DataCount)'(autoexecdata_idx)];                                 
        if(set_cmdbusy_i) begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end
      [DM::ProgBuf0:ProgBufEnd]: begin
        dmi_data_o = progbuf_q[dm_csr_sel_i[$clog2(DM::ProgBufSize)-1:0]];                               
        if(set_cmdbusy_i) begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end

      // SBA Related
      DM::SBCS: begin
        dmi_data_o = sbcs_q;
      end
      DM::SBAddress0: begin
        dmi_data_o = sbaddr_q[31:0];
      end
      DM::SBAddress1: begin
        dmi_data_o = sbaddr_q[63:32];
      end
      DM::SBData0: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbdata_read_valid_o = (sbcs_q.sberror == '0);
          dmi_data_o = sbdata_q[31:0];
        end
      end
      DM::SBData1: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          dmi_data_o = sbdata_q[63:32];
        end
      end
    endcase
    end

    // WRITE OPERATION
    if(dm_csrs_we_i) begin
      unique case(dm_csr_sel_i) inside
      DM::DMControl: begin                              
        dmcontrol_d = dmi_data_i;
        if (dmcontrol_d.ackhavereset) begin
          havereset_d = 1'b0;
        end
      end
      DM::AbstractCS: begin
        if(set_cmdbusy_i) begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end
      DM::Command: begin 
        if(!set_cmdbusy_i) begin
          command_d = DM::command_t'(dmi_data_i);                             
        end else begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end
      DM::AbstractAuto: begin
        // this field can only be written legally when there is no command executing
        if (!set_cmdbusy_i) begin
          abstractauto_d                 = 32'h0;
          abstractauto_d.autoexecdata    = 12'(dmi_data_i[(DM::DataCount)-1:0]);
          abstractauto_d.autoexecprogbuf = 16'(dmi_data_i[(DM::ProgBufSize)-1+16:16]);
        end else begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end
      [DM::Data0:DataEnd]: begin
        if(DM::DataCount > 0 ) begin
          if(!set_cmdbusy_i) begin
            data_d[dm_csr_sel_i[$clog2(DM::DataCount)-1:0]] = dmi_data_i;
          end else begin
            dmi_resp_o = DM::DTM_BUSY;
        end
        end
      end

      [DM::ProgBuf0:ProgBufEnd]: begin
        if(!set_cmdbusy_i)begin
          progbuf_d[dm_csr_sel_i[$clog2(DM::ProgBufSize)-1:0]] = dmi_data_i;
        end else begin
          dmi_resp_o = DM::DTM_BUSY;
        end
      end

      // SBA related 
      DM::SBCS: begin
        // access while the SBA was busy
        if (sbbusy_i) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbcs = DM::sbcs_t'(dmi_data_i);
          sbcs_d = sbcs;
          // R/W1C
          sbcs_d.sbbusyerror = sbcs_q.sbbusyerror & (~sbcs.sbbusyerror);
          sbcs_d.sberror     = (|sbcs.sberror) ? 3'b0 : sbcs_q.sberror;
        end
      end
     DM::SBAddress0: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbaddr_d[31:0] = dmi_data_i;
          sbaddress_write_valid_o = (sbcs_q.sberror == '0);
        end
      end
      DM::SBAddress1: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbaddr_d[63:32] = dmi_data_i;
        end
      end
      DM::SBData0: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbdata_d[31:0] = dmi_data_i;
          sbdata_write_valid_o = (sbcs_q.sberror == '0);
        end
      end
      DM::SBData1: begin
        // access while the SBA was busy
        if (sbbusy_i || sbcs_q.sbbusyerror) begin
          sbcs_d.sbbusyerror = 1'b1;
          dmi_resp_o = DM::DTM_BUSY;
        end else begin
          sbdata_d[63:32] = dmi_data_i;
        end
      end
      endcase
    end

    // update data registers
    if (data_valid_i) begin
      data_d = data_i;
    end

    // set the havereset flag when the ndmreset completed
    if (ndmreset_ack_i) begin
      havereset_d = '1;
    end
    // -------------
    // System Bus
    // -------------
    // set bus error
    if (sberror_valid_i) begin
      sbcs_d.sberror = sberror_i;
    end
    // update read data
    if (sbdata_valid_i) begin
      sbdata_d = 64'(sbdata_i);
    end

    // dmcontrol
    dmcontrol_d.hasel           = 1'b0;
    dmcontrol_d.hartreset       = 1'b0;
    dmcontrol_d.setresethaltreq = 1'b0;
    dmcontrol_d.clrresethaltreq = 1'b0;
    dmcontrol_d.zero1           = '0;
    dmcontrol_d.zero0           = '0;
    dmcontrol_d.ackhavereset    = 1'b0;
    if (!dmcontrol_q.resumereq && dmcontrol_d.resumereq) begin
      clear_resumeack_o = 1'b1;
    end
    if (dmcontrol_q.resumereq && resumeack_i) begin
      dmcontrol_d.resumereq = 1'b0;
    end
    // WARL behavior of hartsel, depending on NrHarts.
    // If NrHarts = 1 this is just masked to all-zeros.
    {dmcontrol_d.hartselhi, dmcontrol_d.hartsello} &= (2**$clog2(NrHarts))-1;

    // static values for dcsr
    sbcs_d.sbversion            = 3'd1;
    sbcs_d.sbbusy               = sbbusy_i;
    sbcs_d.sbasize              = $bits(sbcs_d.sbasize)'(BusWidth);
    sbcs_d.sbaccess128          = logic'(BusWidth >= 32'd128);
    sbcs_d.sbaccess64           = logic'(BusWidth >= 32'd64);
    sbcs_d.sbaccess32           = logic'(BusWidth >= 32'd32);
    sbcs_d.sbaccess16           = logic'(BusWidth >= 32'd16);
    sbcs_d.sbaccess8            = logic'(BusWidth >= 32'd8);
end

// Outputs Assignment
assign data_o      = data_q;
assign dmactive_o  = dmcontrol_q.dmactive;
assign cmd_o       = command_q;
assign progbuf_o   = progbuf_q;
assign ndmreset_o = dmcontrol_q.ndmreset;

assign haltreq_o  = dmcontrol_q.haltreq;
assign resumereq_o= dmcontrol_q.resumereq;
assign autoexecdata_o = abstractauto_q.autoexecdata;
assign autoexecprogbuf_o = abstractauto_q.autoexecprogbuf;

  // SBA
assign sbautoincrement_o = sbcs_q.sbautoincrement;
assign sbreadonaddr_o    = sbcs_q.sbreadonaddr;
assign sbreadondata_o    = sbcs_q.sbreadondata;
assign sbaccess_o        = sbcs_q.sbaccess;
assign sbdata_o          = sbdata_q[BusWidth-1:0];
assign sbaddress_o       = sbaddr_q[BusWidth-1:0];


always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    // PoR
    if (!rst_ni) begin
      dmcontrol_q    <= '0;
      // this is the only write-able bit during reset
      command_q      <= '0;
      abstractauto_q <= '0;
      progbuf_q      <= '0;
      data_q         <= '0;
      sbcs_q         <= '{default: '0,  sbaccess: 3'd2};
      sbaddr_q       <= '0;
      sbdata_q       <= '0;
      havereset_q    <= '1;
    end else begin
      havereset_q    <= SelectableHarts & havereset_d;
      // synchronous re-set of debug module, active-low, except for dmactive
      if (!dmcontrol_q.dmactive) begin
        dmcontrol_q.haltreq          <= '0;
        dmcontrol_q.resumereq        <= '0;
        dmcontrol_q.hartreset        <= '0;
        dmcontrol_q.ackhavereset     <= '0;
        dmcontrol_q.zero1            <= '0;
        dmcontrol_q.hasel            <= '0;
        dmcontrol_q.hartsello        <= '0;
        dmcontrol_q.hartselhi        <= '0;
        dmcontrol_q.zero0            <= '0;
        dmcontrol_q.setresethaltreq  <= '0;
        dmcontrol_q.clrresethaltreq  <= '0;
        dmcontrol_q.ndmreset         <= '0;
        // this is the only write-able bit during reset
        dmcontrol_q.dmactive         <= dmcontrol_d.dmactive;
        command_q                    <= '0;
        abstractauto_q               <= '0;
        progbuf_q                    <= '0;
        data_q                       <= '0;
        sbcs_q                       <= '{default: '0,  sbaccess: 3'd2};
        sbaddr_q                     <= '0;
        sbdata_q                     <= '0;
      end else begin
        dmcontrol_q                  <= dmcontrol_d;
        command_q                    <= command_d;
        abstractauto_q               <= abstractauto_d;
        progbuf_q                    <= progbuf_d;
        data_q                       <= data_d;
        sbcs_q                       <= sbcs_d;
        sbaddr_q                     <= sbaddr_d;
        sbdata_q                     <= sbdata_d;
      end
    end
  end

endmodule: DM_CSRS

