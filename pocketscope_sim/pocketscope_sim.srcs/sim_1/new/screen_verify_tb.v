`timescale 1ns / 1ps
//=============================================================================
// Screen Content Verification Testbench
// Verifies VGA output pixels across all 4 display modes
//=============================================================================

module screen_verify_tb;

    //==================================================
    // Clock (100MHz) and Reset
    //==================================================
    reg  sys_clk;
    reg  rst_n;

    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    //==================================================
    // DUT
    //==================================================
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
        .btn(btn), .sw_in(sw_in), .sw_dip(sw_dip),
        .led_speed(led_speed), .loop_tx(loop_tx), .loop_rx(loop_rx)
    );

    //==================================================
    // Pixel counters
    //==================================================
    integer green_cnt;    // sig gen waveform (r=0,g=F,b=0)
    integer yellow_cnt;   // CH1 (r=F,g=F,b=0)
    integer blue_cnt;     // CH2 (r=0,g=0,b=F)
    integer white_cnt;    // overlap (r=F,g=F,b=F)
    integer grid_cnt;     // grid pixels (r=1,g=1,b=1) or (r=2,g=2,b=2)
    integer magenta_cnt;  // kaleidoscope diagonal
    integer cyan_cnt;     // kaleidoscope quadrant
    integer total_cnt;

    task reset_counters;
        begin
            green_cnt   = 0;
            yellow_cnt  = 0;
            blue_cnt    = 0;
            white_cnt   = 0;
            grid_cnt    = 0;
            magenta_cnt = 0;
            cyan_cnt    = 0;
            total_cnt   = 0;
        end
    endtask

    always @(posedge sys_clk) begin
        total_cnt <= total_cnt + 1;

        // Sig gen: green trace
        if ((vga_r == 4'h0) && (vga_g == 4'hF) && (vga_b == 4'h0))
            green_cnt <= green_cnt + 1;

        // CH1: yellow
        if ((vga_r == 4'hF) && (vga_g == 4'hF) && (vga_b == 4'h0))
            yellow_cnt <= yellow_cnt + 1;

        // CH2: blue
        if ((vga_r == 4'h0) && (vga_g == 4'h0) && (vga_b == 4'hF))
            blue_cnt <= blue_cnt + 1;

        // Overlap: white
        if ((vga_r == 4'hF) && (vga_g == 4'hF) && (vga_b == 4'hF))
            white_cnt <= white_cnt + 1;

        // Grid: dim gray
        if ((vga_r == 4'h1) && (vga_g == 4'h1) && (vga_b == 4'h1))
            grid_cnt <= grid_cnt + 1;

        // Kaleidoscope: magenta (diagonal)
        if ((vga_r == 4'hF) && (vga_g == 4'h0) && (vga_b == 4'hF))
            magenta_cnt <= magenta_cnt + 1;

        // Kaleidoscope: cyan (quadrant)
        if ((vga_r == 4'h0) && (vga_g == 4'hF) && (vga_b == 4'hF))
            cyan_cnt <= cyan_cnt + 1;
    end

    //==================================================
    // Test sequence: check each mode
    //==================================================
    initial begin
        reset_counters();

        //-------------------------------------------------
        // Phase 1: Signal Generator mode (~2 frames)
        //-------------------------------------------------
        sw_in = 8'b000_000_00;
        #35_000_000;

        $display("========================================");
        $display("PHASE 1: SIGNAL GENERATOR MODE");
        $display("========================================");
        $display("GREEN pixels  = %d", green_cnt);
        $display("GRID pixels   = %d", grid_cnt);
        $display("TOTAL pixels  = %d", total_cnt);
        $display("========================================");

        if (green_cnt > 500)
            $display("Sig Gen trace: PASS");
        else
            $display("Sig Gen trace: FAIL");

        if (grid_cnt > 1000)
            $display("Grid display: PASS");
        else
            $display("Grid display: FAIL");

        //-------------------------------------------------
        // Phase 2: Oscilloscope mode
        //-------------------------------------------------
        reset_counters();
        sw_in = 8'b000_000_01;
        #35_000_000;

        $display("");
        $display("========================================");
        $display("PHASE 2: OSCILLOSCOPE MODE");
        $display("========================================");
        $display("YELLOW pixels = %d", yellow_cnt);
        $display("BLUE pixels   = %d", blue_cnt);
        $display("WHITE pixels  = %d", white_cnt);
        $display("GRID pixels   = %d", grid_cnt);
        $display("TOTAL pixels  = %d", total_cnt);
        $display("========================================");

        if (yellow_cnt > 500)
            $display("CH1 (yellow): PASS");
        else
            $display("CH1 (yellow): FAIL");

        if (blue_cnt > 500)
            $display("CH2 (blue): PASS");
        else
            $display("CH2 (blue): FAIL");

        //-------------------------------------------------
        // Phase 3: Lissajous mode
        //-------------------------------------------------
        reset_counters();
        sw_in = 8'b000_000_10;
        #35_000_000;

        $display("");
        $display("========================================");
        $display("PHASE 3: LISSAJOUS MODE");
        $display("========================================");
        $display("GREEN pixels  = %d", green_cnt);
        $display("GRID pixels   = %d", grid_cnt);
        $display("TOTAL pixels  = %d", total_cnt);
        $display("========================================");

        if (green_cnt > 5)
            $display("Lissajous dot: PASS");
        else
            $display("Lissajous dot: FAIL");

        //-------------------------------------------------
        // Phase 4: Kaleidoscope mode
        //-------------------------------------------------
        reset_counters();
        sw_in = 8'b000_000_11;
        #35_000_000;

        $display("");
        $display("========================================");
        $display("PHASE 4: KALEIDOSCOPE MODE");
        $display("========================================");
        $display("CYAN pixels    = %d", cyan_cnt);
        $display("MAGENTA pixels = %d", magenta_cnt);
        $display("GRID pixels    = %d", grid_cnt);
        $display("TOTAL pixels   = %d", total_cnt);
        $display("========================================");

        if ((cyan_cnt + magenta_cnt) > 5)
            $display("Kaleidoscope dots: PASS");
        else
            $display("Kaleidoscope dots: FAIL");

        $display("");
        $display("========================================");
        $display("SCREEN VERIFICATION COMPLETE");
        $display("========================================");

        $stop;
    end

endmodule
