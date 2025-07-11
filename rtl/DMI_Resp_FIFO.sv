module DMI_Resp_FIFO (
    input logic             clk_i,
    input logic             rst_ni,

    input logic             testmode_i,
    input logic             dmi_rst_ni,
    input DM::dmi_resp_t        resp_queue_inp_i,
    // control unit1 input
    input logic             resp_queue_push_i,
    input logic             resp_queue_pop_i,
    // output
    output DM::dmi_resp_t       dmi_resp_o,
    output logic            resp_queue_full_o,
    output logic            resp_queue_empty_o
);
  fifo_v2 #(
    .dtype            ( logic [$bits(dmi_resp_o)-1:0] ),
    .DEPTH            ( 2                             )
  ) i_fifo (
    .clk_i,
    .rst_ni,
    .flush_i          ( ~dmi_rst_ni          ), // Flush the queue if the DTM is
                                                // reset
    .testmode_i       ( testmode_i           ),
    .full_o           ( resp_queue_full      ),
    .empty_o          ( resp_queue_empty     ),
    .alm_full_o       (                      ),
    .alm_empty_o      (                      ),
    .data_i           ( resp_queue_inp       ),
    .push_i           ( resp_queue_push      ),
    .data_o           ( dmi_resp_o           ),
    .pop_i            ( resp_queue_pop       )
  );
endmodule : DMI_Resp_FIFO

