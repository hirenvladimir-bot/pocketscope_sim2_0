`timescale 1ns / 1ps
//=============================================================================
// Kaleidoscope Display Mode
// Creates 8-fold symmetric X-Y patterns from dual-channel ADC data.
// The symmetry + slow rotation creates mesmerizing geometric patterns.
//
// 8-fold symmetry = 4 quadrant reflections + 4 diagonal reflections:
//   (x+dx, y+dy), (x-dx, y+dy), (x+dx, y-dy), (x-dx, y-dy)
//   (x+dy, y+dx), (x-dy, y+dx), (x+dy, y-dx), (x-dy, y-dx)
//
// A low-frequency rotation slowly mixes dx/dy to make the pattern evolve.
//=============================================================================

module kaleidoscope
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          de,
    input  wire [9:0]    pixel_x,
    input  wire [9:0]    pixel_y,
    // ADC data inputs
    input  wire [7:0]    ch1_data,
    input  wire [7:0]    ch2_data,
    input  wire          ch1_valid,
    input  wire          ch2_valid,
    // VGA output
    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

//=============================================================================
// Parameters
//=============================================================================
localparam CEN_X    = 320;    // screen center X
localparam CEN_Y    = 240;    // screen center Y
localparam MAX_RAD  = 220;    // maximum radius from center
localparam DOT_SIZE = 2;      // half-size of drawn dot

// Rotation speed: slow (~0.5 Hz at 25MHz)
localparam ROT_MAX  = 24'd12_500_000;

//=============================================================================
// Rotation phase accumulator
//=============================================================================
reg [23:0] rot_phase;
reg [7:0]  rot_cos, rot_sin;     // approximated rotation trig values
wire       rot_tick;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rot_phase <= 0;
    end else begin
        if (rot_phase == ROT_MAX - 1)
            rot_phase <= 0;
        else
            rot_phase <= rot_phase + 1'b1;
    end
end

assign rot_tick = (rot_phase == 0);

// Simple rotation LUT: 64-step sine/cosine approximated (0..2pi)
// We only need a few values; use phase[23:18] as index
wire [5:0] rot_idx = rot_phase[23:18];

// Approximate cos/sin using triangle wave for rotating kaleidoscope effect
// This creates interesting geometric patterns as the "rotation angle" changes
// cos ~ triangle(rot_idx), sin ~ triangle(rot_idx + 16) (90° phase shift)
wire [5:0] sin_idx = rot_idx;
wire [5:0] cos_idx = rot_idx + 6'd16;

// Triangle function: 0→31 ramp up, 32→63 ramp down
function [7:0] tri_func;
    input [5:0] idx;
    begin
        if (idx[5] == 1'b0)
            tri_func = {2'b00, idx} << 1;     // 0→31, ramp up: 0→124
        else
            tri_func = {2'b00, ~idx} << 1;    // 32→63, ramp down: 124→0
    end
endfunction

always @(posedge clk) begin
    rot_cos <= tri_func(cos_idx);
    rot_sin <= tri_func(sin_idx);
end

//=============================================================================
// Sample capture: hold last valid CH1/CH2 pair
//=============================================================================
reg [7:0] hold_ch1, hold_ch2;
reg       sample_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hold_ch1     <= 8'h80;
        hold_ch2     <= 8'h80;
        sample_valid <= 1'b0;
    end else begin
        if (ch1_valid || ch2_valid) begin
            hold_ch1     <= ch1_data;
            hold_ch2     <= ch2_data;
            sample_valid <= 1'b1;
        end
    end
end

//=============================================================================
// Coordinate computation
//=============================================================================
// Map 8-bit (0-255) to signed offset (-128 to +127)
wire signed [8:0] raw_dx = $signed({1'b0, hold_ch1}) - $signed(9'd128);
wire signed [8:0] raw_dy = $signed({1'b0, hold_ch2}) - $signed(9'd128);

// Apply slow rotation: mix dx/dy based on rotation phase
// rot_dx = dx*cos - dy*sin  (simplified approximation)
// rot_dy = dx*sin + dy*cos
wire signed [8:0] rot_dx = (raw_dx * $signed({1'b0, rot_cos}) - raw_dy * $signed({1'b0, rot_sin})) >>> 7;
wire signed [8:0] rot_dy = (raw_dx * $signed({1'b0, rot_sin}) + raw_dy * $signed({1'b0, rot_cos})) >>> 7;

// Scale: max range ~128 * 220/128 ≈ 220 pixels
wire signed [9:0] sx = $signed(10'd0 + ((rot_dx * $signed(10'd220)) / $signed(9'd128)));
wire signed [9:0] sy = $signed(10'd0 + ((rot_dy * $signed(10'd220)) / $signed(9'd128)));

// Clamp scaled coordinates
wire signed [9:0] dx = (sx > 10'd220) ? 10'd220 : ((sx < -10'd220) ? -10'd220 : sx);
wire signed [9:0] dy = (sy > 10'd220) ? 10'd220 : ((sy < -10'd220) ? -10'd220 : sy);

// 8 symmetric dot positions (center + offset)
wire [9:0] dot_x [0:7];
wire [9:0] dot_y [0:7];

// Quadrant reflections
assign dot_x[0] = CEN_X + dx;   assign dot_y[0] = CEN_Y + dy;
assign dot_x[1] = CEN_X - dx;   assign dot_y[1] = CEN_Y + dy;
assign dot_x[2] = CEN_X + dx;   assign dot_y[2] = CEN_Y - dy;
assign dot_x[3] = CEN_X - dx;   assign dot_y[3] = CEN_Y - dy;

// Diagonal reflections
assign dot_x[4] = CEN_X + dy;   assign dot_y[4] = CEN_Y + dx;
assign dot_x[5] = CEN_X - dy;   assign dot_y[5] = CEN_Y + dx;
assign dot_x[6] = CEN_X + dy;   assign dot_y[6] = CEN_Y - dx;
assign dot_x[7] = CEN_X - dy;   assign dot_y[7] = CEN_Y - dx;

//=============================================================================
// Hit detection — check if current pixel hits any of the 8 dots
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

// Determine which quadrant/sector for coloring
wire is_quadrant = hit[0] | hit[1] | hit[2] | hit[3];
wire is_diagonal = hit[4] | hit[5] | hit[6] | hit[7];

//=============================================================================
// Color generation — each sector gets a different color
//=============================================================================
always @(*) begin
    vga_r = 4'h0;
    vga_g = 4'h0;
    vga_b = 4'h0;

    if (de) begin
        // Grid (faint)
        if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
            vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
        end

        // Center cross (slightly brighter)
        if (pixel_x == CEN_X || pixel_y == CEN_Y) begin
            vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
        end

        // Draw dots with color based on sector
        if (any_hit) begin
            if (is_quadrant && is_diagonal) begin
                // Overlap region — white
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
            end else if (is_quadrant) begin
                // Quadrant symmetry dots — cyan/blue tones
                if (hit[0] || hit[3]) begin
                    vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF;  // cyan
                end else begin
                    vga_r = 4'h0; vga_g = 4'h8; vga_b = 4'hF;  // blue
                end
            end else if (is_diagonal) begin
                // Diagonal symmetry dots — magenta/purple tones
                if (hit[4] || hit[7]) begin
                    vga_r = 4'hF; vga_g = 4'h0; vga_b = 4'hF;  // magenta
                end else begin
                    vga_r = 4'hF; vga_g = 4'h4; vga_b = 4'h8;  // pink-purple
                end
            end
        end

        // Rotation phase indicator ring (faint circle at radius ~180)
        // Simple distance check: if pixel is near radius, draw indicator dot
        if (rot_tick && any_hit) begin
            // flash center on rotation tick
            if (pixel_x >= (CEN_X - 4) && pixel_x <= (CEN_X + 4) &&
                pixel_y >= (CEN_Y - 4) && pixel_y <= (CEN_Y + 4)) begin
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;  // yellow flash
            end
        end
    end
end

endmodule
