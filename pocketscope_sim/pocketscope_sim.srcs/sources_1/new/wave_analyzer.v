`timescale 1ns / 1ps
// Waveform Analyzer: frequency, Vpp, RMS, Average, Max, waveform type detection
//
// Calibration parameters based on EGO1_Oscilloscope_Gen extension board:
//   Front-end: BNC→10kΩ+100kΩ trimmer→MCP6002(G=1.1×)→74HC4053→XADC VAUXP2
//   VBIAS = 3.3V×(10k/(56k+10k)) ≈ 0.5V, op-amp DC out ≈ 0.55V
//   XADC 12-bit 0-1V → code uses adc[11:4] (8-bit, 0-255)
//   ADC LSB (8-bit) = 1V/256 = 3.90625mV at XADC input
//   Front-end gain at max trimmer: 100k/(10k+100k)×1.1 ≈ 1.0
//   → ~3.91mV/LSB at BNC input
//
// Frequency: zero-crossing counter over GATE_MAX samples
//   freq_hz = zc_count × FREQ_CAL_X10 / 10
//   Default FREQ_CAL_X10=100 gives 10Hz/count (correct for 100kSPS gate)
//   For ~403kSPS (4053 mode): FREQ_CAL_X10=403 → 40.3Hz/count
// Vpp:        peak_max - peak_min over 10000-sample gate, raw ADC counts
// RMS:        sqrt(sum((wave-128)^2) / 8192) — AC RMS (0-127), raw counts
// Average:    sum(wave) / 8192 — DC level (0-255), raw counts
// Max:        peak_max over 8192-sample gate, raw counts
// Type:       histogram-based classification (square/triangle/sine)
//
// Calibrated outputs (mV): raw_value × CAL_MV_X1024 >> 10
//   CAL_MV_X1024 = round(3906.25 × 1024 / 1000) = 4000 (default)
//   Result: raw × 4000 / 1024 ≈ raw × 3.90625 mV/LSB
//
// RMS/AVG/MAX use a separate 8192-sample gate (= 2^13) for clean shift-division.

module wave_analyzer
#(
    // Frequency calibration: freq_hz = zc_count × FREQ_CAL_X10 / 10
    // FREQ_CAL_X10 = sample_rate_hz × 10 / GATE_MAX
    // Default: 100 (for 100kSPS), for 403kSPS use 403
    parameter [15:0] FREQ_CAL_X10  = 100,
    // Voltage calibration: mV = raw × CAL_MV_X1024 >> 10
    // Default: 4000 → 3.90625 mV/LSB (max trimmer, front-end gain≈1.0)
    // For calibrated trimmer settings:
    //   CAL_MV_X1024 = round(3906.25 × 1024 / frontend_gain)
    parameter [15:0] CAL_MV_X1024  = 4000,
    // Gate sizes
    parameter [13:0] GATE_MAX      = 10000,   // freq, Vpp, type gate
    parameter [12:0] RMS_GATE      = 8192     // RMS, AVG, MAX gate (2^13)
)
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [7:0]    wave_data,
    input  wire          wave_valid,
    // Frequency & Vpp & Type (GATE_MAX samples)
    output reg  [15:0]   frequency_hz,
    output reg  [7:0]    vpp,
    output reg  [1:0]    wave_type_det,
    output reg           meas_valid,
    // RMS, Average, Max (8192-sample gate) — raw ADC counts
    output reg  [7:0]    rms,
    output reg  [7:0]    avg_val,
    output reg  [7:0]    max_val,
    // Calibrated outputs in millivolts (valid same cycle as raw outputs)
    output reg  [15:0]   vpp_mv,
    output reg  [15:0]   rms_mv,
    output reg  [15:0]   avg_mv,
    output reg  [15:0]   max_mv
);

    //=========================================================================
    // Integer square root (combinational, 8-cycle unrolled)
    // Input: 0-16125 (after >> 13), output: 0-127
    //=========================================================================
    function [7:0] sqrt_int;
        input [15:0] x;
        reg [15:0] r;
        reg [7:0] q;
        reg [9:0] t;
        integer i;
        begin
            r = 0;
            q = 0;
            for (i = 7; i >= 0; i = i - 1) begin
                r = {r[13:0], x[2*i+1], x[2*i]};
                t = {q, 2'b01};
                if (r >= t) begin
                    r = r - t;
                    q = {q[6:0], 1'b1};
                end else begin
                    q = {q[6:0], 1'b0};
                end
            end
            sqrt_int = q;
        end
    endfunction

    //=========================================================================
    // Frequency measurement (zero-crossing, GATE_MAX samples)
    // freq_hz = zc_count * FREQ_CAL_X10 / 10
    //=========================================================================
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
                    // freq_hz = zc_count × FREQ_CAL_X10 / 10
                    // Multiply 16×16→32, then divide by 10 (approximate)
                    frequency_hz <= (zc_count * FREQ_CAL_X10 + 16'd5) / 16'd10;
                    meas_valid   <= 1'b1;
                    gate_cnt     <= 0;
                    zc_count     <= 0;
                end else begin
                    gate_cnt <= gate_cnt + 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // Peak-to-peak detector (GATE_MAX samples) + calibrated mV output
    //=========================================================================
    reg [7:0]  peak_max, peak_min;
    reg [13:0] peak_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            peak_max <= 8'h00;
            peak_min <= 8'hFF;
            peak_cnt <= 0;
            vpp      <= 0;
            vpp_mv   <= 0;
        end else if (wave_valid) begin
            if (wave_data > peak_max) peak_max <= wave_data;
            if (wave_data < peak_min) peak_min <= wave_data;
            if (peak_cnt == GATE_MAX - 1) begin
                vpp      <= peak_max - peak_min;
                // vpp_mv = (vpp_raw × CAL_MV_X1024) >> 10
                // 8×16→24, keep upper 14 bits for 0-1000mV range
                vpp_mv   <= ((peak_max - peak_min) * CAL_MV_X1024) >> 10;
                peak_max <= 8'h00;
                peak_min <= 8'hFF;
                peak_cnt <= 0;
            end else begin
                peak_cnt <= peak_cnt + 1'b1;
            end
        end
    end

    //=========================================================================
    // Waveform type detection (histogram, GATE_MAX samples)
    // Adaptive classification using peak_max/peak_min from Vpp detector.
    // Bins: near_peak = top 25% (>192), near_valley = bottom 25% (<64),
    //       near_mid = center 12.5% (112-144), all on 0-255 scale.
    //=========================================================================
    reg [9:0]  near_peak, near_valley, near_mid;
    reg [13:0] hist_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            near_peak     <= 0;
            near_valley   <= 0;
            near_mid      <= 0;
            hist_cnt      <= 0;
            wave_type_det <= 2'b00;
        end else if (wave_valid) begin
            // Fixed bins (wider than before for better small-signal coverage):
            if (wave_data > 8'd192) near_peak <= near_peak + 1'b1;
            if (wave_data < 8'd64)  near_valley <= near_valley + 1'b1;
            if (wave_data > 8'd112 && wave_data < 8'd144) near_mid <= near_mid + 1'b1;

            if (hist_cnt == GATE_MAX - 1) begin
                // Adaptive classification: use Vpp from peak detector as guard
                if ((peak_max - peak_min) < 8'd20) begin
                    wave_type_det <= wave_type_det;  // too small, hold previous
                end
                // Square: most samples at extremes, very few in middle
                else if (near_peak > 3500 && near_valley > 3500 && near_mid < 800)
                    wave_type_det <= 2'b01;  // square
                // Triangle: uniform spread, significant mid-count
                else if (near_peak < 3000 && near_valley < 3000 && near_mid > 1200)
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

    //=========================================================================
    // RMS, Average, Max accumulators (RMS_GATE = 8192 samples) + calibrated mV
    //=========================================================================
    reg [27:0] sum_sq_acc;    // sum of (wave_data - 128)^2
    reg [20:0] sum_acc;       // sum of wave_data
    reg [7:0]  rms_peak;      // max value during RMS gate
    reg [12:0] rms_cnt;       // 0..8191

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_sq_acc <= 0;
            sum_acc    <= 0;
            rms_peak   <= 0;
            rms_cnt    <= 0;
            rms        <= 0;
            avg_val    <= 0;
            max_val    <= 0;
            rms_mv     <= 0;
            avg_mv     <= 0;
            max_mv     <= 0;
        end else if (wave_valid) begin
            // Accumulate: (wave-128)^2 and wave
            sum_sq_acc <= sum_sq_acc + ((wave_data >= 8'd128)
                          ? (wave_data - 8'd128) * (wave_data - 8'd128)
                          : (8'd128 - wave_data) * (8'd128 - wave_data));
            sum_acc    <= sum_acc + {13'b0, wave_data};
            if (wave_data > rms_peak) rms_peak <= wave_data;

            if (rms_cnt == RMS_GATE - 1) begin
                // avg = sum / 8192 = sum[20:13]
                avg_val <= sum_acc[20:13];

                // rms = sqrt(sum_sq / 8192) = sqrt(sum_sq[27:13])
                // sum_sq[27:13] is 15-bit (0..16129)
                rms <= sqrt_int({1'b0, sum_sq_acc[27:13]});

                // max = peak
                max_val <= rms_peak;

                // Calibrated mV outputs: mV = raw × CAL_MV_X1024 >> 10
                avg_mv  <= (sum_acc[20:13] * CAL_MV_X1024) >> 10;
                rms_mv  <= (sqrt_int({1'b0, sum_sq_acc[27:13]}) * CAL_MV_X1024) >> 10;
                max_mv  <= (rms_peak * CAL_MV_X1024) >> 10;

                // Reset accumulators
                sum_sq_acc <= 0;
                sum_acc    <= 0;
                rms_peak   <= 0;
                rms_cnt    <= 0;
            end else begin
                rms_cnt <= rms_cnt + 1'b1;
            end
        end
    end

endmodule
