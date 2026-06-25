`timescale 1ns / 1ps
//=============================================================================
// Kaleidoscope Display Mode with Smooth Rotation
// Creates 8-fold symmetric X-Y patterns from dual-channel ADC data.
// The symmetry + smooth sine/cosine rotation creates geometric patterns.
//
// 8-fold symmetry = 4 quadrant + 4 diagonal reflections
//
// Uses a 64-entry sine LUT for proper 2D rotation (replaces triangle-wave
// approximation which caused severe geometric distortion).
//
// Samples are paired (CH1+CH2) to avoid mismatched data in 4053 mux mode.
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

//=============================================================================
// Parameters
//=============================================================================
localparam CEN_X    = 320;
localparam CEN_Y    = 240;
localparam DOT_SIZE = 2;
localparam ROT_MAX  = 24'd12_500_000;  // ~0.5 Hz at 25MHz

//=============================================================================
// 64-entry Sine LUT: sin(i * 2pi/64) * 127 + 128, range 1..255, center 128
// Pre-computed for synthesis compatibility.
//=============================================================================
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

//=============================================================================
// Rotation phase accumulator
//=============================================================================
reg [23:0] rot_phase;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rot_phase <= 0;
    else if (rot_phase == ROT_MAX - 1)
        rot_phase <= 0;
    else
        rot_phase <= rot_phase + 1'b1;
end

wire rot_tick = (rot_phase == 0);

// Rotation angle index and sin/cos lookup
wire [5:0] sin_idx = rot_phase[23:18];
wire [5:0] cos_idx = sin_idx + 6'd16;  // cos(θ) = sin(θ + π/2)

wire [7:0] sin_raw = sin_lut[sin_idx];
wire [7:0] cos_raw = sin_lut[cos_idx];

// Convert to signed (-128..+127)
wire signed [8:0] rot_cos = $signed({1'b0, cos_raw}) - 9'sd128;
wire signed [8:0] rot_sin = $signed({1'b0, sin_raw}) - 9'sd128;

//=============================================================================
// Sample pairing for 4053 mux mode compatibility
//=============================================================================
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

//=============================================================================
// Coordinate computation with proper 2D rotation
//=============================================================================
wire signed [8:0] raw_dx = $signed({1'b0, hold_ch1}) - 9'sd128;
wire signed [8:0] raw_dy = $signed({1'b0, hold_ch2}) - 9'sd128;

// 2D rotation matrix: rot = [cos -sin; sin cos]
// rot_dx = (dx*cos - dy*sin) / 128
// rot_dy = (dx*sin + dy*cos) / 128
wire signed [17:0] rd_x = raw_dx * rot_cos - raw_dy * rot_sin;
wire signed [17:0] rd_y = raw_dx * rot_sin + raw_dy * rot_cos;

wire signed [9:0] rot_dx = rd_x[17:7];  // >> 7
wire signed [9:0] rot_dy = rd_y[17:7];

// Scale to screen: max range ~220 pixels
wire signed [9:0] sx = (rot_dx * 10'sd220) / 10'sd128;
wire signed [9:0] sy = (rot_dy * 10'sd220) / 10'sd128;

// Clamp (FIXED: was self-referencing 'dy' in else branch)
wire signed [9:0] clamp_dx = (sx > 10'sd220) ? 10'sd220 : ((sx < -10'sd220) ? -10'sd220 : sx);
wire signed [9:0] clamp_dy = (sy > 10'sd220) ? 10'sd220 : ((sy < -10'sd220) ? -10'sd220 : sy);

// 8 symmetric dot positions
wire [9:0] dot_x [0:7];
wire [9:0] dot_y [0:7];

// Quadrant reflections
assign dot_x[0] = CEN_X + clamp_dx; assign dot_y[0] = CEN_Y + clamp_dy;
assign dot_x[1] = CEN_X - clamp_dx; assign dot_y[1] = CEN_Y + clamp_dy;
assign dot_x[2] = CEN_X + clamp_dx; assign dot_y[2] = CEN_Y - clamp_dy;
assign dot_x[3] = CEN_X - clamp_dx; assign dot_y[3] = CEN_Y - clamp_dy;
// Diagonal reflections (swap dx/dy)
assign dot_x[4] = CEN_X + clamp_dy; assign dot_y[4] = CEN_Y + clamp_dx;
assign dot_x[5] = CEN_X - clamp_dy; assign dot_y[5] = CEN_Y + clamp_dx;
assign dot_x[6] = CEN_X + clamp_dy; assign dot_y[6] = CEN_Y - clamp_dx;
assign dot_x[7] = CEN_X - clamp_dy; assign dot_y[7] = CEN_Y - clamp_dx;

//=============================================================================
// Hit detection
//=============================================================================
wire [7:0] hit;
genvar gi;
generate for (gi = 0; gi < 8; gi = gi + 1) begin : dot_hit
    assign hit[gi] = sample_valid &&
        (pixel_x >= ((dot_x[gi] > DOT_SIZE) ? (dot_x[gi] - DOT_SIZE) : 0)) &&
        (pixel_x <= ((dot_x[gi] < (639 - DOT_SIZE)) ? (dot_x[gi] + DOT_SIZE) : 639)) &&
        (pixel_y >= ((dot_y[gi] > DOT_SIZE) ? (dot_y[gi] - DOT_SIZE) : 0)) &&
        (pixel_y <= ((dot_y[gi] < (479 - DOT_SIZE)) ? (dot_y[gi] + DOT_SIZE) : 479));
end endgenerate

wire any_hit = |hit;
wire is_quadrant = hit[0] | hit[1] | hit[2] | hit[3];
wire is_diagonal = hit[4] | hit[5] | hit[6] | hit[7];

//=============================================================================
// Color output
//=============================================================================
always @(*) begin
    vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'h0;

    if (de) begin
        // Grid
        if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
            vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
        end
        // Center cross
        if (pixel_x == CEN_X || pixel_y == CEN_Y) begin
            vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
        end
        // Dots
        if (any_hit) begin
            if (is_quadrant && is_diagonal) begin
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;  // white overlap
            end else if (is_quadrant) begin
                vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF;  // cyan
            end else if (is_diagonal) begin
                vga_r = 4'hF; vga_g = 4'h0; vga_b = 4'hF;  // magenta
            end
        end
        // Rotation tick flash
        if (rot_tick) begin
            if (pixel_x >= (CEN_X - 4) && pixel_x <= (CEN_X + 4) &&
                pixel_y >= (CEN_Y - 4) && pixel_y <= (CEN_Y + 4)) begin
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
            end
        end
    end
end

endmodule
