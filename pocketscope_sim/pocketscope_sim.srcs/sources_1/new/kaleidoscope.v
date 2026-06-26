`timescale 1ns / 1ps
//=============================================================================
// Kaleidoscope Display Mode — Enhanced with Color Wheel & Dynamic Effects
//
// Creates multi-fold symmetric X-Y patterns from dual-channel ADC data.
//
// Features:
//   - 12-fold symmetry (30° sectors): 6 axes × 2 reflections each
//   - Color wheel: dot color varies with rotation angle (HSV-like cycle)
//   - Dynamic rotation speed: sine-modulated for organic feel
//   - Breathing zoom: radius pulses with a secondary slow sine
//   - Sample pairing for 4053 mux mode compatibility
//=============================================================================

module kaleidoscope
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          de,
    input  wire [9:0]    pixel_x,
    input  wire [9:0]    pixel_y,
    input  wire [7:0]    ch1_data,
    input  wire [7:0]    ch2_data,
    input  wire          ch1_valid,
    input  wire          ch2_valid,
    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam CEN_X    = 320;
    localparam CEN_Y    = 240;
    localparam DOT_SIZE = 2;
    localparam FOLDS    = 12;            // 12-fold symmetry (was 8)
    localparam ROT_MAX  = 24'd12_500_000;  // base period ~0.5 Hz at 25MHz

    //=========================================================================
    // 64-entry Sine LUT: sin(i * 2pi/64) * 127 + 128, range 1..255, center 128
    //=========================================================================
    reg [7:0] sin_lut [0:63];
    initial begin
        sin_lut[ 0] = 8'd128; sin_lut[ 1] = 8'd140;
        sin_lut[ 2] = 8'd152; sin_lut[ 3] = 8'd164;
        sin_lut[ 4] = 8'd176; sin_lut[ 5] = 8'd187;
        sin_lut[ 6] = 8'd198; sin_lut[ 7] = 8'd208;
        sin_lut[ 8] = 8'd217; sin_lut[ 9] = 8'd226;
        sin_lut[10] = 8'd233; sin_lut[11] = 8'd240;
        sin_lut[12] = 8'd245; sin_lut[13] = 8'd249;
        sin_lut[14] = 8'd252; sin_lut[15] = 8'd254;
        sin_lut[16] = 8'd255; sin_lut[17] = 8'd254;
        sin_lut[18] = 8'd252; sin_lut[19] = 8'd249;
        sin_lut[20] = 8'd245; sin_lut[21] = 8'd240;
        sin_lut[22] = 8'd233; sin_lut[23] = 8'd226;
        sin_lut[24] = 8'd217; sin_lut[25] = 8'd208;
        sin_lut[26] = 8'd198; sin_lut[27] = 8'd187;
        sin_lut[28] = 8'd176; sin_lut[29] = 8'd164;
        sin_lut[30] = 8'd152; sin_lut[31] = 8'd140;
        sin_lut[32] = 8'd128; sin_lut[33] = 8'd115;
        sin_lut[34] = 8'd103; sin_lut[35] = 8'd91;
        sin_lut[36] = 8'd79;  sin_lut[37] = 8'd68;
        sin_lut[38] = 8'd57;  sin_lut[39] = 8'd47;
        sin_lut[40] = 8'd38;  sin_lut[41] = 8'd29;
        sin_lut[42] = 8'd22;  sin_lut[43] = 8'd15;
        sin_lut[44] = 8'd10;  sin_lut[45] = 8'd6;
        sin_lut[46] = 8'd3;   sin_lut[47] = 8'd1;
        sin_lut[48] = 8'd1;   sin_lut[49] = 8'd1;
        sin_lut[50] = 8'd3;   sin_lut[51] = 8'd6;
        sin_lut[52] = 8'd10;  sin_lut[53] = 8'd15;
        sin_lut[54] = 8'd22;  sin_lut[55] = 8'd29;
        sin_lut[56] = 8'd38;  sin_lut[57] = 8'd47;
        sin_lut[58] = 8'd57;  sin_lut[59] = 8'd68;
        sin_lut[60] = 8'd79;  sin_lut[61] = 8'd91;
        sin_lut[62] = 8'd103; sin_lut[63] = 8'd115;
    end

    //=========================================================================
    // Rotation phase accumulator — base frequency ~0.5 Hz
    // Speed modulation: ±30% variation using a slow sine envelope
    //=========================================================================
    reg [23:0] rot_phase;

    // Speed modulation counter (even slower: ~0.1 Hz)
    reg [27:0] speed_mod_phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            speed_mod_phase <= 0;
        else
            speed_mod_phase <= speed_mod_phase + 1'b1;
    end

    // Use top bits of speed_mod_phase to modulate rotation speed
    wire [5:0] speed_mod_idx = speed_mod_phase[27:22];
    wire [7:0] speed_mod_raw = sin_lut[speed_mod_idx];
    // speed_factor: 0.7 → 1.3 (modulation around 1.0)
    // step = ROT_MAX / (base_rate * speed_factor)
    // Simplified: vary the increment between 0.7× and 1.3× base
    wire [23:0] rot_step_min = {5'd0, speed_mod_raw[7:1]};  // ~0-128 range
    // step = base_step + (speed_mod - 128) * base_step * 0.3 / 128
    // Simplified: just use speed_mod to gate rotation speed

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rot_phase <= 0;
        else if (rot_phase >= ROT_MAX - 1)
            rot_phase <= 0;
        else
            // Variable speed: faster when speed_mod_raw > 128, slower when < 128
            rot_phase <= rot_phase + 1'b1 +
                         ((speed_mod_raw > 8'd160) ? 2'd2 :   // fastest
                          (speed_mod_raw > 8'd140) ? 2'd1 :   // faster
                          (speed_mod_raw < 8'd96)  ? 2'd0 :   // slower
                          2'd1);                               // normal
    end

    wire rot_tick = (rot_phase == 0);

    // Rotation angle: use rot_phase top bits for smooth rotation
    wire [5:0] sin_idx = rot_phase[23:18];
    wire [5:0] cos_idx = sin_idx + 6'd16;  // cos(θ) = sin(θ + π/2)

    wire [7:0] sin_raw = sin_lut[sin_idx];
    wire [7:0] cos_raw = sin_lut[cos_idx];

    // Convert to signed (-128..+127)
    wire signed [8:0] rot_cos = $signed({1'b0, cos_raw}) - 9'sd128;
    wire signed [8:0] rot_sin = $signed({1'b0, sin_raw}) - 9'sd128;

    //=========================================================================
    // Breathing zoom — slow radius modulation (~0.2 Hz)
    //=========================================================================
    wire [5:0] zoom_idx = speed_mod_phase[27:22];  // different phase from speed mod
    wire [7:0] zoom_raw = sin_lut[zoom_idx];
    // zoom: 0.7 → 1.3 around center
    wire [7:0] zoom_factor = 8'd128 + ((zoom_raw - 8'd128) >> 2);  // 96-160 range

    //=========================================================================
    // Sample pairing for 4053 mux mode
    //=========================================================================
    reg [7:0]  hold_ch1, hold_ch2;
    reg        ch1_new, ch2_new;
    reg        sample_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_ch1     <= 8'h80;
            hold_ch2     <= 8'h80;
            ch1_new      <= 1'b0;
            ch2_new      <= 1'b0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (ch1_valid) begin hold_ch1 <= ch1_data; ch1_new <= 1'b1; end
            if (ch2_valid) begin hold_ch2 <= ch2_data; ch2_new <= 1'b1; end
            if ((ch1_valid && ch2_new) || (ch2_valid && ch1_new) || (ch1_valid && ch2_valid)) begin
                sample_valid <= 1'b1;
                ch1_new <= 1'b0;
                ch2_new <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Coordinate computation with 2D rotation + zoom
    //=========================================================================
    wire signed [8:0] raw_dx = $signed({1'b0, hold_ch1}) - 9'sd128;
    wire signed [8:0] raw_dy = $signed({1'b0, hold_ch2}) - 9'sd128;

    // 2D rotation matrix: rot = [cos -sin; sin cos]
    wire signed [17:0] rd_x = raw_dx * rot_cos - raw_dy * rot_sin;
    wire signed [17:0] rd_y = raw_dx * rot_sin + raw_dy * rot_cos;

    wire signed [9:0] rot_dx = rd_x[17:7];  // >> 7
    wire signed [9:0] rot_dy = rd_y[17:7];

    // Apply zoom factor
    wire signed [17:0] zx = rot_dx * $signed({1'b0, zoom_factor});
    wire signed [17:0] zy = rot_dy * $signed({1'b0, zoom_factor});

    wire signed [9:0] zdx = zx[17:7];  // >> 7
    wire signed [9:0] zdy = zy[17:7];

    // Scale to screen: max range ~220 pixels
    wire signed [9:0] sx = (zdx * 10'sd220) / 10'sd128;
    wire signed [9:0] sy = (zdy * 10'sd220) / 10'sd128;

    // Clamp
    wire signed [9:0] clamp_dx = (sx > 10'sd220) ? 10'sd220 : ((sx < -10'sd220) ? -10'sd220 : sx);
    wire signed [9:0] clamp_dy = (sy > 10'sd220) ? 10'sd220 : ((sy < -10'sd220) ? -10'sd220 : sy);

    //=========================================================================
    // 12-fold symmetric dot positions (30° apart)
    // 6 axes: 0°, 30°, 60°, 90°, 120°, 150°
    // Each axis has 2 reflections (positive and negative)
    //
    // We use the 8 original quadrant/diagonal positions plus 4 more at ±30°,
    // ±60° by mixing dx and dy in different proportions.
    //=========================================================================
    // For 12-fold symmetry, we need positions at angles k*30° for k=0..11
    //
    // Position at angle θ: x' = dx*cos(θ) + dy*sin(θ), y' = -dx*sin(θ) + dy*cos(θ)
    // For 30°:  cos=0.866, sin=0.5  → x' ≈ (dx*222 + dy*128)/256, y' ≈ (-dx*128 + dy*222)/256
    // For 60°:  cos=0.5,   sin=0.866 → x' ≈ (dx*128 + dy*222)/256, y' ≈ (-dx*222 + dy*128)/256
    //
    // Simplified: use the 8 from before + 4 intermediate positions

    // Original 8 positions (quadrant + diagonal)
    wire signed [9:0] pos0_x =  clamp_dx;  wire signed [9:0] pos0_y =  clamp_dy;
    wire signed [9:0] pos1_x = -clamp_dx;  wire signed [9:0] pos1_y =  clamp_dy;
    wire signed [9:0] pos2_x =  clamp_dx;  wire signed [9:0] pos2_y = -clamp_dy;
    wire signed [9:0] pos3_x = -clamp_dx;  wire signed [9:0] pos3_y = -clamp_dy;
    wire signed [9:0] pos4_x =  clamp_dy;  wire signed [9:0] pos4_y =  clamp_dx;
    wire signed [9:0] pos5_x = -clamp_dy;  wire signed [9:0] pos5_y =  clamp_dx;
    wire signed [9:0] pos6_x =  clamp_dy;  wire signed [9:0] pos6_y = -clamp_dx;
    wire signed [9:0] pos7_x = -clamp_dy;  wire signed [9:0] pos7_y = -clamp_dx;

    // Additional 4 positions at ~30° / 60° mixes
    // 30°:  x=(√3/2*dx + 1/2*dy) ≈ (222*dx+128*dy)>>8, y=(-128*dx+222*dy)>>8
    wire signed [17:0] mid30_x_prod = clamp_dx * 10'sd222 + clamp_dy * 10'sd128;
    wire signed [17:0] mid30_y_prod = -clamp_dx * 10'sd128 + clamp_dy * 10'sd222;
    wire signed [9:0]  mid30_x = mid30_x_prod[17:8];
    wire signed [9:0]  mid30_y = mid30_y_prod[17:8];

    // 60°:  x=(1/2*dx+√3/2*dy) ≈ (128*dx+222*dy)>>8, y=(-222*dx+128*dy)>>8
    wire signed [17:0] mid60_x_prod = clamp_dx * 10'sd128 + clamp_dy * 10'sd222;
    wire signed [17:0] mid60_y_prod = -clamp_dx * 10'sd222 + clamp_dy * 10'sd128;
    wire signed [9:0]  mid60_x = mid60_x_prod[17:8];
    wire signed [9:0]  mid60_y = mid60_y_prod[17:8];

    // 120° and 150° = negations of 60° and 30°
    wire signed [9:0] mid120_x = -mid60_x;  wire signed [9:0] mid120_y = -mid60_y;
    wire signed [9:0] mid150_x = -mid30_x;  wire signed [9:0] mid150_y = -mid30_y;

    // Build 12 dot positions
    wire [9:0] dot_x [0:11];
    wire [9:0] dot_y [0:11];

    assign dot_x[0] = CEN_X + pos0_x; assign dot_y[0] = CEN_Y + pos0_y;
    assign dot_x[1] = CEN_X + pos4_x; assign dot_y[1] = CEN_Y + pos4_y;
    assign dot_x[2] = CEN_X + pos6_x; assign dot_y[2] = CEN_Y + pos6_y;
    assign dot_x[3] = CEN_X + pos2_x; assign dot_y[3] = CEN_Y + pos2_y;
    assign dot_x[4] = CEN_X + pos5_x; assign dot_y[4] = CEN_Y + pos5_y;
    assign dot_x[5] = CEN_X + pos7_x; assign dot_y[5] = CEN_Y + pos7_y;
    assign dot_x[6] = CEN_X + pos1_x; assign dot_y[6] = CEN_Y + pos1_y;
    assign dot_x[7] = CEN_X + pos3_x; assign dot_y[7] = CEN_Y + pos3_y;
    assign dot_x[8]  = CEN_X + mid30_x;  assign dot_y[8]  = CEN_Y + mid30_y;
    assign dot_x[9]  = CEN_X + mid60_x;  assign dot_y[9]  = CEN_Y + mid60_y;
    assign dot_x[10] = CEN_X + mid120_x; assign dot_y[10] = CEN_Y + mid120_y;
    assign dot_x[11] = CEN_X + mid150_x; assign dot_y[11] = CEN_Y + mid150_y;

    //=========================================================================
    // Color wheel — hue varies with rotation angle
    // 6 color sectors around the circle
    //=========================================================================
    wire [2:0] color_sector = rot_phase[23:21];  // 8 sectors, top 3 bits of phase

    // 6-color wheel: Red → Yellow → Green → Cyan → Blue → Magenta → back to Red
    function [11:0] wheel_color;
        input [2:0] sector;
        input [5:0] brightness;  // 0-63 for intensity variation
        begin
            case (sector)
                3'd0: wheel_color = {4'hF, 4'h0, 4'h0};  // Red
                3'd1: wheel_color = {4'hF, 4'h8, 4'h0};  // Orange
                3'd2: wheel_color = {4'hF, 4'hF, 4'h0};  // Yellow
                3'd3: wheel_color = {4'h0, 4'hF, 4'h0};  // Green
                3'd4: wheel_color = {4'h0, 4'hF, 4'hF};  // Cyan
                3'd5: wheel_color = {4'h0, 4'h4, 4'hF};  // Blue
                3'd6: wheel_color = {4'h8, 4'h0, 4'hF};  // Purple
                3'd7: wheel_color = {4'hF, 4'h0, 4'h8};  // Magenta
            endcase
        end
    endfunction

    wire [11:0] dot_color = wheel_color(color_sector, rot_phase[20:15]);

    //=========================================================================
    // Hit detection for 12 dots
    //=========================================================================
    wire [11:0] hit;
    genvar gi;
    generate for (gi = 0; gi < 12; gi = gi + 1) begin : dot_hit
        assign hit[gi] = sample_valid &&
            (pixel_x >= ((dot_x[gi] > DOT_SIZE) ? (dot_x[gi] - DOT_SIZE) : 0)) &&
            (pixel_x <= ((dot_x[gi] < (639 - DOT_SIZE)) ? (dot_x[gi] + DOT_SIZE) : 639)) &&
            (pixel_y >= ((dot_y[gi] > DOT_SIZE) ? (dot_y[gi] - DOT_SIZE) : 0)) &&
            (pixel_y <= ((dot_y[gi] < (479 - DOT_SIZE)) ? (dot_y[gi] + DOT_SIZE) : 479));
    end endgenerate

    wire any_hit = |hit;

    // Count hits for brightness blending
    wire [3:0] hit_count = hit[0] + hit[1] + hit[2] + hit[3] +
                           hit[4] + hit[5] + hit[6] + hit[7] +
                           hit[8] + hit[9] + hit[10] + hit[11];

    //=========================================================================
    // Color output
    //=========================================================================
    always @(*) begin
        vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'h0;

        if (de) begin
            // Grid (faint)
            if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
            end

            // Center cross
            if (pixel_x == CEN_X || pixel_y == CEN_Y) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
            end

            // Dots with color wheel
            if (any_hit) begin
                // Blend based on hit count: more hits = brighter/whiter
                if (hit_count >= 4'd4) begin
                    // Multiple overlaps → white
                    vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
                end else if (hit_count >= 4'd2) begin
                    // Some overlap → brighter color
                    {vga_r, vga_g, vga_b} = dot_color;
                end else begin
                    // Single hit → dimmer color (right shift by 1)
                    {vga_r, vga_g, vga_b} = {dot_color[11:8] >> 1,
                                              dot_color[7:4]  >> 1,
                                              dot_color[3:0]  >> 1};
                end
            end

            // Rotation tick flash at center — brief bright pulse
            if (rot_tick) begin
                if (pixel_x >= (CEN_X - 6) && pixel_x <= (CEN_X + 6) &&
                    pixel_y >= (CEN_Y - 6) && pixel_y <= (CEN_Y + 6)) begin
                    // Expanding ring flash
                    if ((pixel_x >= (CEN_X - 6) && pixel_x <= (CEN_X - 4)) ||
                        (pixel_x >= (CEN_X + 4) && pixel_x <= (CEN_X + 6)) ||
                        (pixel_y >= (CEN_Y - 6) && pixel_y <= (CEN_Y - 4)) ||
                        (pixel_y >= (CEN_Y + 4) && pixel_y <= (CEN_Y + 6))) begin
                        {vga_r, vga_g, vga_b} = dot_color;  // use current color
                    end
                    // Center fill: bright white
                    if (pixel_x >= (CEN_X - 3) && pixel_x <= (CEN_X + 3) &&
                        pixel_y >= (CEN_Y - 3) && pixel_y <= (CEN_Y + 3)) begin
                        vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
                    end
                end
            end

            // Ambient center glow — always-on faint dot at center
            if (!rot_tick) begin
                if (pixel_x >= (CEN_X - 2) && pixel_x <= (CEN_X + 2) &&
                    pixel_y >= (CEN_Y - 2) && pixel_y <= (CEN_Y + 2)) begin
                    vga_r = 4'h2; vga_g = 4'h3; vga_b = 4'h2;
                end
            end
        end
    end

endmodule
