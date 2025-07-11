module DM_SBA(
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic         dmactive_i,

    output logic         master_req_o,
    output logic [31:0]  master_add_o,
    output logic         master_we_o,
    output logic [31:0]  master_wdata_o,
    output logic [3:0]   master_be_o,
    input  logic         master_gnt_i,
    input  logic         master_r_valid_i,
    input  logic         master_r_err_i,
    input  logic         master_r_other_err_i,
    input  logic [31:0]  master_r_rdata_i,

    input  logic [31:0]  sbaddress_i,
    input  logic         sbaddress_write_valid_i,
    input  logic         sbreadonaddr_i,
    output logic [31:0]  sbaddress_o,
    input  logic         sbautoincrement_i,
    input  logic [2:0]   sbaccess_i,

    input  logic         sbreadondata_i,
    input  logic [31:0]  sbdata_i,
    input  logic         sbdata_read_valid_i,
    input  logic         sbdata_write_valid_i,

    output logic [31:0]  sbdata_o,
    output logic         sbdata_valid_o,

    output logic         sbbusy_o,
    output logic         sberror_valid_o,
    output logic [2:0]   sberror_o
);

localparam int BeIdxWidth = 2;
DM::sba_state_e state_d, state_q;

logic [31:0] address;
logic        req, gnt, we;
logic [3:0]  be, be_mask;
logic [1:0]  be_idx;

assign sbbusy_o = (state_q != DM::Idle);

always_comb begin : p_be_mask
    be_mask = '0;
    unique case (sbaccess_i)
        3'b000: be_mask[be_idx] = 1'b1;
        
        3'b001: begin
            if (be_idx[1] == 1'b1) begin
                be_mask[3:2] = 2'b11;
            end else begin
                be_mask[1:0] = 2'b11;
            end
        end

        3'b010: be_mask = 4'b1111;
        default: ;
    endcase
end

logic [31:0] sbaccess_mask;
assign sbaccess_mask = 32'hFFFFFFFF << sbaccess_i;

logic addr_incr_en;
logic [31:0] addr_incr;
assign addr_incr   = (addr_incr_en) ? (32'(1) << sbaccess_i) : 32'b0;
assign sbaddress_o = sbaddress_i + addr_incr;

always_comb begin : p_fsm
    req     = 1'b0;
    address = sbaddress_i;
    we      = 1'b0;
    be      = 4'b0000;
    be_idx  = sbaddress_i[BeIdxWidth-1:0];

    sberror_o       = 3'b000;
    sberror_valid_o = 1'b0;
    addr_incr_en    = 1'b0;
    state_d         = state_q;

    unique case (state_q)
        DM::Idle: begin
            if (sbaddress_write_valid_i && sbreadonaddr_i)
                state_d = DM::Read;
            else if (sbdata_write_valid_i)
                state_d = DM::Write;
            else if (sbdata_read_valid_i && sbreadondata_i)
            //else if (sbdata_read_valid_i)
                state_d = DM::Read;
        end

        DM::Read: begin
            req = 1'b1;
            be  = be_mask;
            if (gnt) state_d = DM::WaitRead;
        end

        DM::Write: begin
            req = 1'b1;
            we  = 1'b1;
            be  = be_mask;
            if (gnt) state_d = DM::WaitWrite;
        end

        DM::WaitRead: begin
            if (master_r_valid_i) begin
                state_d = DM::Idle;
                addr_incr_en = sbautoincrement_i;
                if (master_r_other_err_i) begin
                    sberror_valid_o = 1'b1;
                    sberror_o = 3'd7;
                end else if (master_r_err_i) begin
                    sberror_valid_o = 1'b1;
                    sberror_o = 3'd2;
                end
            end
        end

        DM::WaitWrite: begin
            if (master_r_valid_i) begin
                state_d = DM::Idle;
                addr_incr_en = sbautoincrement_i;
                if (master_r_other_err_i) begin
                    sberror_valid_o = 1'b1;
                    sberror_o = 3'd7;
                end else if (master_r_err_i) begin
                    sberror_valid_o = 1'b1;
                    sberror_o = 3'd2;
                end
            end
        end

        default: state_d = DM::Idle;
    endcase

    if ((sbaccess_i > BeIdxWidth) && (state_q != DM::Idle)) begin
        req             = 1'b0;
        state_d         = DM::Idle;
        sberror_valid_o = 1'b1;
        sberror_o       = 3'd4;
    end

    if ((|(sbaddress_i & ~sbaccess_mask)) && (state_q != DM::Idle)) begin
        req             = 1'b0;
        state_d         = DM::Idle;
        sberror_valid_o = 1'b1;
        sberror_o       = 3'd3;
    end
end

always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (!rst_ni)
        state_q <= DM::Idle;
    else
        state_q <= state_d;
end

logic [1:0] be_idx_masked;
assign be_idx_masked   = be_idx & sbaccess_mask[1:0];
assign master_req_o    = req;
assign master_add_o    = address;
assign master_we_o     = we;
assign master_wdata_o  = sbdata_i << (8 * be_idx_masked);
assign master_be_o     = be;
assign gnt             = master_gnt_i;
assign sbdata_valid_o  = master_r_valid_i;
assign sbdata_o        = master_r_rdata_i >> (8 * be_idx_masked);



endmodule: DM_SBA

