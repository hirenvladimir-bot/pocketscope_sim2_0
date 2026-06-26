`timescale 1ns / 1ps
//=============================================================================
// Multi-Frame Screen Capture Testbench
// Captures VGA frames as CSV for offline visualization
//=============================================================================

module screen_capture_multi_tb;

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

    // 100MHz clock
    always #5 sys_clk = ~sys_clk;

    // Reset
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;
    end

    // Frame capture
    integer fp;
    integer x, y;
    integer r8, g8, b8;
    integer frame_idx;
    parameter TOTAL_FRAMES = 5;   // 5 frames for faster sim

    initial begin
        #5000000;  // Wait for stabilization

        for (frame_idx = 0; frame_idx < TOTAL_FRAMES; frame_idx = frame_idx + 1) begin
            fp = $fopen($sformatf("frame%0d.csv", frame_idx), "w");
            $display("Capture Start: frame %0d", frame_idx);
            $fwrite(fp, "x,y,r,g,b\n");

            // Capture one frame
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    // Wait for pixel position (hierarchical access to internal wires)
                    @(posedge dbg_clk25m);
                    if (uut.pixel_x == x && uut.pixel_y == y) begin
                        r8 = {vga_r, 4'b0};
                        g8 = {vga_g, 4'b0};
                        b8 = {vga_b, 4'b0};
                        $fwrite(fp, "%0d,%0d,%0d,%0d,%0d\n", x, y, r8, g8, b8);
                    end else if (uut.pixel_x > x) begin
                        // skip missed pixels
                    end
                end
            end

            $fclose(fp);
            $display("Frame %0d saved: frame%0d.csv", frame_idx, frame_idx);
            repeat(480*800) @(posedge dbg_clk25m);
        end

        $display("======================");
        $display("All frames saved");
        $display("======================");
        $stop;
    end

endmodule
