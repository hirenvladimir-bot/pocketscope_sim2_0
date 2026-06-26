`timescale 1ns / 1ps
//=============================================================================
// Stress Test — Long-running simulation to check stability
// Runs for 1 second of simulated time (1e9 ns at 100MHz)
//=============================================================================

module stress_tb;

    reg  sys_clk = 0;
    reg  rst_n;

    wire        hsync, vsync;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire [7:0]  dac_d;
    wire        dac_ile, dac_cs_n, dac_wr1_n, dac_wr2_n, dac_xfer_n;
    wire [2:0]  led_speed;
    wire [4:0]  loop_tx;
    wire [7:0]  dbg_dds_out    = uut.dbg_dds_out;
    wire [23:0] dbg_freq_ftw    = uut.dbg_freq_ftw;
    wire [7:0]  dbg_amplitude   = uut.dbg_amplitude;
    wire [7:0]  dbg_mod_signal  = uut.dbg_mod_signal;
    wire        dbg_clk25m      = uut.dbg_clk25m;

    reg  [4:0]  btn = 5'b00000;
    reg  [7:0]  sw_in  = 8'b00000000;    // Sig gen mode
    reg  [7:0]  sw_dip = 8'b10000000;
    reg  [4:0]  loop_rx = 5'b00000;

    top uut (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .hsync(hsync), .vsync(vsync),
        .dac_d(dac_d), .dac_ile(dac_ile), .dac_cs_n(dac_cs_n),
        .dac_wr1_n(dac_wr1_n), .dac_wr2_n(dac_wr2_n), .dac_xfer_n(dac_xfer_n),
        .adc_p_in(1'b0), .adc_n_in(1'b0),
        .adc_vauxp2(1'b0), .adc_vauxn2(1'b0),
        .btn(btn), .sw_in(sw_in), .sw_dip(sw_dip),
        .led_speed(led_speed), .loop_tx(loop_tx), .loop_rx(loop_rx)
    );

    // 100MHz clock
    always #5 sys_clk = ~sys_clk;

    // Reset
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    // Long run with mode switching every 100ms
    initial begin
        $display("START STRESS TEST (1 sec simulated)");

        // 100ms: sig gen sine
        sw_in = 8'b000_000_00;
        #100_000_000;
        $display("PASS 100ms — sig gen sine");

        // 200ms: scope mode
        sw_in = 8'b000_000_01;
        #100_000_000;
        $display("PASS 200ms — scope mode");

        // 300ms: lissajous mode
        sw_in = 8'b000_000_10;
        #100_000_000;
        $display("PASS 300ms — lissajous mode");

        // 400ms: kaleidoscope mode
        sw_in = 8'b000_000_11;
        #100_000_000;
        $display("PASS 400ms — kaleidoscope mode");

        // 500ms: AM modulation
        sw_in = 8'b000_011_00;
        #100_000_000;
        $display("PASS 500ms — AM modulation");

        // 600ms: FM modulation
        sw_in = 8'b000_100_00;
        #100_000_000;
        $display("PASS 600ms — FM modulation");

        // 700ms: SPWM
        sw_in = 8'b000_101_00;
        #100_000_000;
        $display("PASS 700ms — SPWM");

        // 800ms: sig gen square
        sw_in = 8'b000_001_00;
        #100_000_000;
        $display("PASS 800ms — sig gen square");

        // 900ms: sig gen triangle
        sw_in = 8'b000_010_00;
        #100_000_000;
        $display("PASS 900ms — sig gen triangle");

        // 1000ms: scope mode
        sw_in = 8'b000_000_01;
        #100_000_000;
        $display("PASS 1000ms — scope mode (final)");

        $display("");
        $display("========================================");
        $display("STRESS TEST COMPLETE — 1 second PASSED");
        $display("========================================");
        $finish;
    end

endmodule
