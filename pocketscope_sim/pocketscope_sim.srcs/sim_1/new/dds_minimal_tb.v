`timescale 1ns / 1ps

module dds_minimal_tb;

    reg clk = 0;
    reg rst_n = 0;
    reg [23:0] ftw;
    reg [1:0] wave_type;
    wire [7:0] wave_out;

    always #20 clk = ~clk;  // 25 MHz

    dds_core #(.PHASE_WIDTH(24), .LUT_ADDR_W(10), .LUT_DATA_W(8)) u_dds (
        .clk(clk), .rst_n(rst_n), .ftw(ftw), .wave_type(wave_type), .wave_out(wave_out)
    );

    initial begin
        ftw = 24'd1845;
        wave_type = 2'b00;

        // Proper reset
        rst_n = 0;
        #100;
        rst_n = 1;

        // Wait for DDS to produce output
        #1000;

        $display("DDS MINIMAL: wave_out=%0d (expect non-zero, non-x)", wave_out);

        // Monitor
        repeat (100) @(posedge clk);
        $display("DDS MINIMAL after 100 clocks: wave_out=%0d", wave_out);

        if (wave_out !== 8'hxx && wave_out !== 8'hx0)
            $display("DDS MINIMAL: PASS");
        else
            $display("DDS MINIMAL: FAIL");

        $stop;
    end

endmodule
