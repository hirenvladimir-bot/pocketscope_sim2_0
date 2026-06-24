`timescale 1ns / 1ps
// Waveform Analyzer: frequency, Vpp, waveform type detection

module wave_analyzer
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [7:0]    wave_data,
    input  wire          wave_valid,
    output reg  [15:0]   frequency_hz,
    output reg  [7:0]    vpp,
    output reg  [1:0]    wave_type_det,
    output reg           meas_valid
);

    // Gate: ~10000 samples, at ~100kSPS = ~0.1s
    localparam GATE_MAX = 10000;

    // Zero-crossing frequency counter
    reg [13:0] gate_cnt;
    reg [15:0] zc_count;
    reg        prev_sign;
    wire       curr_sign = (wave_data >= 8'd128);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_cnt     <= 0;
            zc_count     <= 0;
            prev_sign    <= 1'b0;
            frequency_hz <= 0;
            meas_valid   <= 1'b0;
        end else begin
            meas_valid <= 1'b0;
            if (wave_valid) begin
                if (curr_sign && !prev_sign && gate_cnt > 0)
                    zc_count <= zc_count + 1'b1;
                prev_sign <= curr_sign;

                if (gate_cnt == GATE_MAX - 1) begin
                    frequency_hz <= zc_count * 16'd10;
                    meas_valid   <= 1'b1;
                    gate_cnt     <= 0;
                    zc_count     <= 0;
                end else begin
                    gate_cnt <= gate_cnt + 1'b1;
                end
            end
        end
    end

    // Peak-to-peak detector
    reg [7:0] peak_max, peak_min;
    reg [13:0] peak_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            peak_max <= 8'h00;
            peak_min <= 8'hFF;
            peak_cnt <= 0;
            vpp      <= 0;
        end else if (wave_valid) begin
            if (wave_data > peak_max) peak_max <= wave_data;
            if (wave_data < peak_min) peak_min <= wave_data;
            if (peak_cnt == GATE_MAX - 1) begin
                vpp      <= peak_max - peak_min;
                peak_max <= 8'h00;
                peak_min <= 8'hFF;
                peak_cnt <= 0;
            end else begin
                peak_cnt <= peak_cnt + 1'b1;
            end
        end
    end

    // Waveform type detection (histogram method)
    reg [9:0] near_peak, near_valley, near_mid;
    reg [13:0] hist_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            near_peak    <= 0;
            near_valley  <= 0;
            near_mid     <= 0;
            hist_cnt     <= 0;
            wave_type_det <= 2'b00;
        end else if (wave_valid) begin
            if (wave_data > 8'd220) near_peak <= near_peak + 1'b1;
            if (wave_data < 8'd35)  near_valley <= near_valley + 1'b1;
            if (wave_data > 8'd108 && wave_data < 8'd148) near_mid <= near_mid + 1'b1;

            if (hist_cnt == GATE_MAX - 1) begin
                if (near_peak > 3000 && near_valley > 3000 && near_mid < 500)
                    wave_type_det <= 2'b01;  // square
                else if (near_peak < 500 && near_valley < 500)
                    wave_type_det <= 2'b10;  // triangle
                else
                    wave_type_det <= 2'b00;  // sine

                near_peak    <= 0;
                near_valley  <= 0;
                near_mid     <= 0;
                hist_cnt     <= 0;
            end else begin
                hist_cnt <= hist_cnt + 1'b1;
            end
        end
    end

endmodule
