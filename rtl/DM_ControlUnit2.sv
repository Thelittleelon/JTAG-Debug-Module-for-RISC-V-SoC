module DM_ControlUnit2 (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        cmd_valid_i,
  input  logic        halted_i,
  input  logic        unsupported_cmd_i,
  input  logic        resumereq_i,
  input  logic        resuming_i,
  input  logic        haltreq_i,
  input  logic        going_i,
  input  logic        exception_i,
  input  logic        ndmreset_i,

  input  logic        halted_int_i,

  output logic        go_o,
  output logic        resume_o,
  output logic        cmdbusy_o,
  output logic        cmderror_valid_o,
  output DM::cmderr_e     cmderror_o,
  output logic        debug_req_o 
);

assign debug_req_o = haltreq_i;
  typedef enum logic [1:0] {
    ST_IDLE  = 2'd0,        // Idle
    ST_GO    = 2'd1,        // Resume or ProgBuf or Abtract Cmd
    ST_RES   = 2'd2,        // Resume
    ST_EXEC  = 2'd3         // Executing Cmd
  } state_t;

  state_t state_d, state_q;

  always_comb begin

    cmdbusy_o        = 1'b1;
    cmderror_valid_o = 1'b0;
    cmderror_o       = DM::None;
    go_o             = 1'b0;
    resume_o         = 1'b0;
    state_d          = state_q;

    case (state_q)
      ST_IDLE: begin
        cmdbusy_o = 1'b0;
        if (cmd_valid_i) begin
          if (halted_i) begin
            if (!unsupported_cmd_i) begin
              state_d = ST_GO;
            end else begin
              cmderror_valid_o = 1'b1;
              cmderror_o  = unsupported_cmd_i ? DM::NotSupported : DM::HaltResume;
            end
          end 
        end         
        // Resume request coming from dmcontrol
        if (resumereq_i && !resuming_i && !haltreq_i && halted_i)
          state_d = ST_RES;
      end

      ST_GO: begin
        cmdbusy_o = 1'b1;
        go_o      = 1'b1;
        if (going_i) state_d = ST_EXEC;
      end
      ST_RES: begin
        cmdbusy_o = 1'b1;
        resume_o  = 1'b1;
        if (resuming_i) state_d = ST_IDLE;
      end
      ST_EXEC: begin
        cmdbusy_o = 1'b1;
        go_o = 1'b0;
        if (halted_int_i) state_d = ST_IDLE;
      end

      default: state_d = ST_IDLE;
    endcase

    // Exception has top priority
    if (exception_i) begin
      cmderror_valid_o = 1'b1;
      cmderror_o       = DM::Exception;
    end

    // Async reset of hart via ndmreset
    if (ndmreset_i) begin
      state_d = ST_IDLE;
      go_o    = 1'b0;
      resume_o= 1'b0;
    end
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

endmodule : DM_ControlUnit2


