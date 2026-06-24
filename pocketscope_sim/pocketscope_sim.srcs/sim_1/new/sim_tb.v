`timescale 1ns / 1ps
//=============================================================================
// Quick Simulation Testbench — validates key internal signals
//=============================================================================

module sim_tb;

    // 100MHz clock
    reg  sys_clk = 0;
    always #5 sys_clk = ~sys_clk;
    reg  rst_n;

    wire [3:0]  vga_r, vga_g, vga_b;
    wire        hsync, vsync;
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
    reg  [7:0]  sw_in  = 8'b00000000;
    reg  [7:0]  sw_dip = 8'b00110010;
    reg  [4:0]  loop_rx = 5'b00000;

    top uut (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .hsync(hsync), .vsync(vsync),
        .dac_d(dac_d), .dac_ile(dac_ile), .dac_cs_n(dac_cs_n),
        .dac_wr1_n(dac_wr1_n), .dac_wr2_n(dac_wr2_n), .dac_xfer_n(dac_xfer_n),
        .adc_p_in(1'b0), .adc_n_in(1'b0),
        .adc_vauxp2(1'b0), .adc_vauxn2(1'b0),
        .adc_vauxp3(1'b0), .adc_vauxn3(1'b0),
        .btn(btn), .sw_in(sw_in), .sw_dip(sw_dip),
        .led_speed(led_speed), .loop_tx(loop_tx), .loop_rx(loop_rx)
    );

    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    initial begin
        // Wait for reset + clock stabilization
        #10000;

        $display("========================================");
        $display("Quick Simulation Results");
        $display("========================================");
        $display("25MHz clock active: %b", dbg_clk25m);
        $display("DDS output:         %h", dbg_dds_out);
        $display("Amplitude:          %h", dbg_amplitude);
        $display("Freq FTW:           %h", dbg_freq_ftw);
        $display("Mod signal:         %h", dbg_mod_signal);
        $display("Mode LED:           %b", led_speed);
        $display("========================================");

        // Quick mode switch tests
        sw_in = 8'b000_001_00;  #5000;  // square
        sw_in = 8'b000_010_00;  #5000;  // triangle
        sw_in = 8'b000_011_00;  #5000;  // AM
        sw_in = 8'b000_100_00;  #5000;  // FM
        sw_in = 8'b000_000_01;  #5000;  // scope mode
        sw_in = 8'b000_000_10;  #5000;  // lissajous
        sw_in = 8'b000_000_11;  #5000;  // kaleidoscope
        sw_in = 8'b000_000_00;  #5000;  // back to sig gen

        $display("All mode switches complete.");
        $stop;
    end

endmodule
