`timescale 1ns / 1ps
//=============================================================================
// Waveform Visual Verification Testbench
// Monitors VGA output and checks scroll/shift in scope mode
//=============================================================================

module waveform_visual_tb;

    reg  sys_clk = 0;
    reg  rst_n = 0;

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
    reg  [7:0]  sw_in  = 8'b00000001;   // Scope mode
    reg  [7:0]  sw_dip = 8'b0;
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

    // 100MHz clock
    always #5 sys_clk = ~sys_clk;

    // Reset
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    //====================================================
    // Color statistics
    //====================================================
    integer yellow_pixels = 0;
    integer blue_pixels   = 0;
    integer white_pixels  = 0;
    integer grid_pixels   = 0;
    integer center_pixels = 0;

    always @(posedge dbg_clk25m) begin
        // Yellow (CH1)
        if (vga_r == 4'hF && vga_g == 4'hF && vga_b == 4'h0)
            yellow_pixels <= yellow_pixels + 1;

        // Blue (CH2)
        if (vga_r == 4'h0 && vga_g == 4'h0 && vga_b == 4'hF)
            blue_pixels <= blue_pixels + 1;

        // White (overlap)
        if (vga_r == 4'hF && vga_g == 4'hF && vga_b == 4'hF)
            white_pixels <= white_pixels + 1;

        // Grid
        if (vga_r == 4'h2 && vga_g == 4'h2 && vga_b == 4'h2)
            grid_pixels <= grid_pixels + 1;

        // Center line
        if (vga_r == 4'h4 && vga_g == 4'h4 && vga_b == 4'h4)
            center_pixels <= center_pixels + 1;
    end

    //====================================================
    // Simulation timeline
    //====================================================
    initial begin
        // Wait ~2 VGA frames
        #35000000;

        $display("");
        $display("================================");
        $display(" PocketScope Visual Verify");
        $display("================================");
        $display("YELLOW PIXELS = %d", yellow_pixels);
        $display("BLUE PIXELS   = %d", blue_pixels);
        $display("WHITE PIXELS  = %d", white_pixels);
        $display("GRID PIXELS   = %d", grid_pixels);
        $display("CENTER PIXELS = %d", center_pixels);
        $display("");

        if (yellow_pixels > 1000)
            $display("CH1 DRAW PASS");
        else
            $display("CH1 DRAW FAIL");

        if (blue_pixels > 1000)
            $display("CH2 DRAW PASS");
        else
            $display("CH2 DRAW FAIL");

        if (grid_pixels > 10000)
            $display("GRID PASS");
        else
            $display("GRID FAIL");

        if (center_pixels > 500)
            $display("CENTER LINE PASS");
        else
            $display("CENTER LINE FAIL");

        $display("");
        $display("DBG_CLK25M = %b", dbg_clk25m);
        $display("================================");

        $stop;
    end

endmodule
