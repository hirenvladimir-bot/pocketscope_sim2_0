`timescale 1ns / 1ps
//=============================================================================
// PocketScope Top-Level Testbench
//=============================================================================

module top_tb;

    //==================================================
    // Clock (100MHz) and Reset
    //==================================================
    reg  sys_clk;
    reg  rst_n;

    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;   // 100MHz
    end

    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    //==================================================
    // DUT connections
    //==================================================
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        hsync, vsync;
    wire [7:0]  dac_d;
    wire        dac_ile, dac_cs_n, dac_wr1_n, dac_wr2_n, dac_xfer_n;
    wire [2:0]  led_speed;
    wire [4:0]  loop_tx;
    // Debug — accessed hierarchically from DUT
    wire [7:0]  dbg_dds_out    = uut.dbg_dds_out;
    wire [23:0] dbg_freq_ftw    = uut.dbg_freq_ftw;
    wire [7:0]  dbg_amplitude   = uut.dbg_amplitude;
    wire [7:0]  dbg_mod_signal  = uut.dbg_mod_signal;
    wire        dbg_clk25m      = uut.dbg_clk25m;

    reg  [4:0]  btn = 5'b00000;
    reg  [7:0]  sw_in  = 8'b00000000;    // sig gen mode, sine wave
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

    //==================================================
    // Test sequence
    //==================================================
    integer i;

    initial begin
        // Wait for reset
        #5000;

        // Test 1: Sig Gen - Sine wave
        sw_in  = 8'b000_000_00;
        sw_dip = 8'b00110010;  // ~1000Hz
        #100000;

        // Test 2: Switch to square wave
        sw_in = 8'b000_001_00;
        #100000;

        // Test 3: Switch to triangle wave
        sw_in = 8'b000_010_00;
        #100000;

        // Test 4: AM Modulation
        sw_in = 8'b000_011_00;
        #100000;

        // Test 5: FM Modulation
        sw_in = 8'b000_100_00;
        #100000;

        // Test 6: SPWM
        sw_in = 8'b000_101_00;
        #100000;

        // Test 7: Oscilloscope mode
        sw_in = 8'b000_000_01;
        #100000;

        // Test 8: Lissajous mode
        sw_in = 8'b000_000_10;
        #100000;

        // Test 9: Kaleidoscope mode
        sw_in = 8'b000_000_11;
        #100000;

        // Test 10: Back to sig gen, test buttons
        sw_in = 8'b000_000_00;
        #50000;
        // Press amp up
        btn[0] = 1;
        #500000;
        btn[0] = 0;
        #50000;

        // Test 11: DIP frequency change
        sw_dip = 8'b11111111;  // max fine
        #50000;
        sw_dip = 8'b00000001;  // min fine
        #50000;

        // Test 12: Loopback
        loop_rx = 5'b10101;
        #50000;

        // End simulation
        #100000;
        $display("========================================");
        $display("Top-level simulation complete.");
        $display("========================================");
        $stop;
    end

endmodule
