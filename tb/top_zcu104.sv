module top_zcu104 (
    // Clock 200MHz differential input
    input  logic clk_p,
    input  logic clk_n,

    // Reset từ nút nhấn (active high)
    input  logic reset_button,

    // JTAG interface từ header
    input  logic tck,
    input  logic tms,
    input  logic tdi,
    input  logic trst_n,
    output logic tdo,

    // LED status
    output logic led_pass,
    output logic led_fail
);

    // Clock buffer
    logic clk_ibuf;
    logic clk;

    // Xilinx differential clock buffer (cho clock chính)
    IBUFGDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("DEFAULT")
    ) clk_ibufgds_inst (
        .I (clk_p),
        .IB(clk_n),
        .O (clk_ibuf)
    );

    // Global buffer cho clock hệ thống
    BUFG clk_bufg_inst (
        .I(clk_ibuf),
        .O(clk)
    );

    // Reset (active low)
    logic rst_ni;
    assign rst_ni = ~reset_button;

    // SoC test signals
    logic tests_passed, tests_failed;

    // SoC instance - không có BUFG cho TCK
    soc_top #(
        .INSTR_RDATA_WIDTH(32),
        .RAM_ADDR_WIDTH(10),
        .BOOT_ADDR(32'h1A00_0180),
        .JTAG_BOOT(1)
    ) soc_top_inst (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .fetch_enable_i(1'b1),
        .tests_passed_o(tests_passed),
        .tests_failed_o(tests_failed),
        .tck_i(tck),         // dùng trực tiếp tck (không qua BUFG)
        .tms_i(tms),
        .tdi_i(tdi),
        .trst_ni(trst_n),
        .tdo_o(tdo)
    );

    // LED indicators
    assign led_pass = tests_passed;
    assign led_fail = tests_failed;

endmodule
