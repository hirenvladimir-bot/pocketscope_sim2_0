`timescale 1ns / 1ps
//=============================================================================
// Waveform Analyzer — Enhanced Lab-Oscilloscope Measurements
//
// Measurements (GATE_MAX = 10000 sample gate, ~24.8ms at 403kSPS):
//   Frequency:   zero-crossing counter, freq_hz = zc × FREQ_CAL_X10 / 10
//   Period:      estimated from zero-crossing spacing (in 100µs units)
//   Vpp:         peak_max − peak_min over gate (raw ADC + calibrated mV)
//   Vmin:        valley (minimum) value in gate (raw + calibrated mV)
//   Vmax:        peak (maximum) value in gate (raw + calibrated mV)
//   RMS:         sqrt(Σ(wave−128)² / 8192) — AC RMS (raw + calibrated mV)
//   Average:     Σ(wave) / 8192 — DC level (raw + calibrated mV)
//   Duty Cycle:  time-above-midpoint / total-time × 100% (square waves)
//   Crest Factor: Vpeak / Vrms × 100 (sine≈141, square≈100, triangle≈173)
//   Rise Time:   estimated 10%→90% transition time (µs)
//
// Waveform Type Detection (histogram + shape analysis):
//   3'b000: Sine    3'b001: Square   3'b010: Triangle
//   3'b011: Sawtooth 3'b100: DC       3'b101: Noise/complex
//
// Calibration:
//   ADC LSB (8-bit) = 1V/256 = 3.90625mV at XADC input
//   CAL_MV_X1024 = 4000 → raw × 4000 / 1024 ≈ raw × 3.90625 mV/LSB
//=============================================================================

module wave_analyzer
#(
    // Frequency calibration: freq_hz = zc_count × FREQ_CAL_X10 / 10
    parameter [15:0] FREQ_CAL_X10  = 100,
    // Voltage calibration: mV = raw × CAL_MV_X1024 >> 10
    parameter [15:0] CAL_MV_X1024  = 4000,
    // Gate sizes
    parameter [13:0] GATE_MAX      = 10000,   // freq, Vpp, type, duty gate
    parameter [12:0] RMS_GATE      = 8192     // RMS, AVG, MAX gate (2^13)
)
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [7:0]    wave_data,
    input  wire          wave_valid,

    // ---- Frequency, Vpp, Type, Duty (GATE_MAX samples) ----
    output reg  [15:0]   frequency_hz,
    output reg  [15:0]   period_x100us,      // period in units of 100µs
    output reg  [7:0]    vpp,
    output reg  [7:0]    vmin_val,            // minimum (valley) raw
    output reg  [2:0]    wave_type_det,       // 3-bit: sine/square/tri/saw/dc/noise
    output reg  [6:0]    duty_cycle,          // 0-100%
    output reg  [7:0]    rise_time_us,        // estimated 10→90% rise time (µs)
    output reg  [10:0]   crest_factor_x100,   // Vpeak/Vrms × 100
    output reg           meas_valid,

    // ---- RMS, Average, Max (8192-sample gate) — raw ADC counts ----
    output reg  [7:0]    rms,
    output reg  [7:0]    avg_val,
    output reg  [7:0]    max_val,

    // ---- Calibrated outputs in millivolts ----
    output reg  [15:0]   vpp_mv,
    output reg  [15:0]   vmin_mv,
    output reg  [15:0]   rms_mv,
    output reg  [15:0]   avg_mv,
    output reg  [15:0]   max_mv
);

    //=========================================================================
    // Integer square root (combinational, 8-cycle unrolled)
    // Input: 0-16125, output: 0-127
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
    // Also track zero-crossing spacing for period estimation.
    //=========================================================================
    reg [13:0] gate_cnt;
    reg [15:0] zc_count;
    reg        prev_sign;
    wire       curr_sign = (wave_data >= 8'd128);

    // Period tracking: measure spacing between zero crossings
    reg [15:0] zc_spacing_sum;   // sum of spacing values (in samples)
    reg [15:0] zc_spacing_cnt;   // number of spacings measured
    reg [15:0] last_zc_sample;   // sample index of last zero crossing

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_cnt        <= 0;
            zc_count        <= 0;
            prev_sign       <= 1'b0;
            frequency_hz    <= 0;
            period_x100us   <= 0;
            zc_spacing_sum  <= 0;
            zc_spacing_cnt  <= 0;
            last_zc_sample  <= 0;
            meas_valid      <= 1'b0;
        end else begin
            meas_valid <= 1'b0;
            if (wave_valid) begin
                if (curr_sign && !prev_sign && gate_cnt > 0) begin
                    zc_count <= zc_count + 1'b1;
                    // Record spacing between zero crossings
                    if (last_zc_sample > 0 || zc_count == 0) begin
                        zc_spacing_sum <= zc_spacing_sum + (gate_cnt - last_zc_sample);
                        zc_spacing_cnt <= zc_spacing_cnt + 1'b1;
                    end
                    last_zc_sample <= gate_cnt;
                end
                prev_sign <= curr_sign;

                if (gate_cnt == GATE_MAX - 1) begin
                    // freq_hz = zc_count × FREQ_CAL_X10 / 10 (rounded)
                    frequency_hz <= (zc_count * FREQ_CAL_X10 + 16'd5) / 16'd10;

                    // Period: average spacing / sample_rate
                    // period_100us = (avg_spacing * 100000) / sample_rate (in 100µs)
                    // With sample_rate ≈ FREQ_CAL_X10*GATE_MAX/10,
                    // period_100us ≈ avg_spacing * 1e6 / sample_rate
                    // Simplified: period_100us ≈ avg_spacing * 10000 / FREQ_CAL_X10
                    if (zc_count > 1 && zc_spacing_cnt > 0) begin
                        // avg_spacing = zc_spacing_sum / zc_spacing_cnt
                        // period_x100us = avg_spacing * 10000 / FREQ_CAL_X10
                        // = zc_spacing_sum * 10000 / (zc_spacing_cnt * FREQ_CAL_X10)
                        period_x100us <= (zc_spacing_sum * 16'd10000) /
                                        ((zc_spacing_cnt * FREQ_CAL_X10 == 0) ? 16'd1 :
                                         (zc_spacing_cnt * FREQ_CAL_X10));
                    end else if (zc_count == 1) begin
                        // Single crossing: period ≈ gate time
                        period_x100us <= 16'd24800;  // ~24.8ms gate → period unknown
                    end else begin
                        period_x100us <= 0;  // no crossings
                    end

                    meas_valid   <= 1'b1;
                    gate_cnt     <= 0;
                    zc_count     <= 0;
                    zc_spacing_sum  <= 0;
                    zc_spacing_cnt  <= 0;
                    last_zc_sample  <= 0;
                end else begin
                    gate_cnt <= gate_cnt + 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // Peak-to-peak detector (GATE_MAX samples) + Vmin + calibrated mV outputs
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
            vmin_val <= 8'h80;
            vmin_mv  <= 0;
        end else if (wave_valid) begin
            if (wave_data > peak_max) peak_max <= wave_data;
            if (wave_data < peak_min) peak_min <= wave_data;
            if (peak_cnt == GATE_MAX - 1) begin
                vpp      <= peak_max - peak_min;
                vpp_mv   <= ((peak_max - peak_min) * CAL_MV_X1024) >> 10;
                vmin_val <= peak_min;
                vmin_mv  <= (peak_min * CAL_MV_X1024) >> 10;
                peak_max <= 8'h00;
                peak_min <= 8'hFF;
                peak_cnt <= 0;
            end else begin
                peak_cnt <= peak_cnt + 1'b1;
            end
        end
    end

    //=========================================================================
    // Duty Cycle measurement (GATE_MAX samples)
    // Counts samples above midpoint (128) vs total samples.
    //=========================================================================
    reg [13:0] high_count;
    reg [13:0] total_duty_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            high_count        <= 0;
            total_duty_count  <= 0;
            duty_cycle        <= 7'd50;  // default 50%
        end else if (wave_valid) begin
            if (wave_data > 8'd128)
                high_count <= high_count + 1'b1;
            total_duty_count <= total_duty_count + 1'b1;

            if (total_duty_count == GATE_MAX - 1) begin
                // duty_cycle = high_count * 100 / total = high_count * 100 / GATE_MAX
                // Use approximation: (high_count * 100 + GATE_MAX/2) / GATE_MAX
                duty_cycle <= ((high_count * 7'd100) + (GATE_MAX >> 1)) / GATE_MAX;
                high_count       <= 0;
                total_duty_count <= 0;
            end
        end
    end

    //=========================================================================
    // Rise Time estimation — track 10%→90% transition on rising edges
    // For each rising edge through midpoint, estimate samples from 10% to 90%
    //=========================================================================
    reg [7:0]  rt_vpp;           // cached Vpp for threshold calculation
    reg [7:0]  rt_vmin;          // cached Vmin
    reg        rt_in_rise;       // flag: currently tracking a rising edge
    reg [7:0]  rt_rise_start;    // sample when rise crossed 10%
    reg [7:0]  rt_rise_cnt;      // current rise duration counter
    reg [7:0]  rt_acc;           // accumulated rise times
    reg [3:0]  rt_count;         // number of rises measured
    reg        rt_prev_below_10;
    reg        rt_prev_below_90;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rt_vpp             <= 8'd128;
            rt_vmin            <= 8'd128;
            rt_in_rise         <= 1'b0;
            rt_rise_start      <= 0;
            rt_rise_cnt        <= 0;
            rt_acc             <= 0;
            rt_count           <= 0;
            rise_time_us       <= 0;
            rt_prev_below_10   <= 1'b1;
            rt_prev_below_90   <= 1'b1;
        end else if (wave_valid) begin
            // Update Vpp/Vmin tracking for thresholds
            if (wave_data > peak_max) rt_vpp <= peak_max;
            if (wave_data < peak_min) rt_vmin <= peak_min;

            // On gate completion, update rise_time
            if (gate_cnt == GATE_MAX - 1) begin
                if (rt_count > 0) begin
                    // Average rise time in samples → µs
                    // 1 sample ≈ 2.48µs at 403kSPS
                    // rise_time_us = avg_samples * 2.48 ≈ avg * 25 / 10
                    rise_time_us <= ((rt_acc / {4'b0, rt_count}) * 8'd25 + 8'd5) / 8'd10;
                end
                rt_acc   <= 0;
                rt_count <= 0;
            end

            // Rise time edge detection logic
            // 10% threshold = rt_vmin + Vpp/10
            // 90% threshold = rt_vmin + Vpp*9/10
            // Simplified: use fixed mid-scale thresholds
            // 10% ≈ 128 - Vpp*0.4, 90% ≈ 128 + Vpp*0.4 (for AC-coupled signals centered at 128)
            if (rt_vpp > 8'd20) begin
                // Compute dynamic thresholds based on current Vpp
                // 10%_level ≈ 128 - Vpp*2/5, 90%_level ≈ 128 + Vpp*2/5
                wire [7:0] low_10  = (rt_vmin > 8'd128 ? 8'd128 : rt_vmin) + (rt_vpp >> 3);  // ~12.5% of Vpp from min
                wire [7:0] high_90 = (peak_max < 8'd128 ? 8'd128 : peak_max) - (rt_vpp >> 3); // ~87.5% of Vpp
                // Simpler: use fixed 10/90 levels
                wire [7:0] thresh_10 = 8'd40;   // ~10% of 0-255 scale
                wire [7:0] thresh_90 = 8'd215;  // ~90% of 0-255 scale

                wire below_10 = (wave_data < thresh_10);
                wire above_90 = (wave_data > thresh_90);

                if (!rt_in_rise) begin
                    // Looking for start of rising edge: was below 10%, now above
                    if (!below_10) begin
                        rt_in_rise    <= 1'b1;
                        rt_rise_cnt   <= 0;
                        rt_rise_start <= 0;
                    end
                end else begin
                    rt_rise_cnt <= rt_rise_cnt + 1'b1;

                    // Mark 10% crossing point
                    if (rt_rise_start == 0 && !rt_prev_below_10 && wave_data >= thresh_10)
                        rt_rise_start <= rt_rise_cnt;

                    // 90% crossing → complete measurement
                    if (wave_data >= thresh_90 && rt_rise_start > 0) begin
                        rt_acc   <= rt_acc + (rt_rise_cnt - rt_rise_start);
                        rt_count <= rt_count + 1'b1;
                        rt_in_rise    <= 1'b0;
                        rt_rise_start <= 0;
                        rt_rise_cnt   <= 0;
                    end

                    // Timeout: if rise takes too long (>200 samples), abort
                    if (rt_rise_cnt == 8'd200) begin
                        rt_in_rise    <= 1'b0;
                        rt_rise_start <= 0;
                        rt_rise_cnt   <= 0;
                    end

                    // Signal went back down before reaching 90% → abort
                    if (wave_data < thresh_10 && rt_rise_cnt > 1) begin
                        rt_in_rise    <= 1'b0;
                        rt_rise_start <= 0;
                        rt_rise_cnt   <= 0;
                    end
                end

                rt_prev_below_10 <= below_10;
                rt_prev_below_90 <= (wave_data < thresh_90);
            end
        end
    end

    //=========================================================================
    // Waveform Type Detection (histogram + shape analysis, GATE_MAX samples)
    //
    // Bins: near_peak (>192, top 25%), near_valley (<64, bottom 25%),
    //       near_mid (112-144, center 12.5%), rising_edge samples (for sawtooth)
    //
    // Classification:
    //   Square:   many at extremes, few in middle
    //   Triangle: uniform spread, significant mid-count
    //   Sawtooth: asymmetric — many mid + moderate peak/valley, duty ≠ 50%
    //   DC:       Vpp < 5 (nearly flat)
    //   Noise:    high zero-crossing rate + small Vpp
    //   Sine:     default fallback
    //=========================================================================
    reg [9:0]  near_peak, near_valley, near_mid;
    reg [13:0] hist_cnt;
    reg [15:0] zc_rapid;       // rapid zero-crossings for noise detection
    reg        prev_sign2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            near_peak       <= 0;
            near_valley     <= 0;
            near_mid        <= 0;
            hist_cnt        <= 0;
            wave_type_det   <= 3'b000;
            zc_rapid        <= 0;
            prev_sign2      <= 1'b0;
            crest_factor_x100 <= 11'd141;  // default sine
        end else if (wave_valid) begin
            // Histogram bins
            if (wave_data > 8'd192)       near_peak   <= near_peak + 1'b1;
            if (wave_data < 8'd64)        near_valley <= near_valley + 1'b1;
            if (wave_data > 8'd112 && wave_data < 8'd144) near_mid <= near_mid + 1'b1;

            // Rapid zero-crossing detection for noise
            if (curr_sign != prev_sign2)
                zc_rapid <= zc_rapid + 1'b1;
            prev_sign2 <= curr_sign;

            if (hist_cnt == GATE_MAX - 1) begin
                // Compute crest factor (with safety divide-by-zero)
                // crest = Vpeak / Vrms, where Vpeak = max(|max-128|, |min-128|)
                // For now, use Vpp/2 as approximation of Vpeak
                if (vpp > 8'd10 && rms > 8'd0) begin
                    // crest × 100 = (Vpp/2) × 100 / rms
                    crest_factor_x100 <= (({3'b0, vpp[7:1]} * 11'd100) / {3'b0, rms});
                end else begin
                    crest_factor_x100 <= 11'd141;  // default: sine ≈ 1.414 × 100
                end

                // ---- Waveform Classification ----
                if (vpp < 8'd5) begin
                    // DC signal (flat)
                    wave_type_det <= 3'b100;  // DC
                end
                else if (vpp < 8'd15 && zc_rapid > 5000) begin
                    // Small amplitude + high zero-crossing rate → noise
                    wave_type_det <= 3'b101;  // Noise
                end
                // Square: concentrated at extremes, sparse in middle
                else if (near_peak > 3500 && near_valley > 3500 && near_mid < 800) begin
                    wave_type_det <= 3'b001;  // Square
                end
                // Triangle: uniform distribution, many mid-samples
                else if (near_peak < 3000 && near_valley < 3000 && near_mid > 1500 &&
                         duty_cycle > 7'd35 && duty_cycle < 7'd65) begin
                    wave_type_det <= 3'b010;  // Triangle
                end
                // Sawtooth: asymmetric distribution + unbalanced duty
                else if (duty_cycle < 7'd30 || duty_cycle > 7'd70) begin
                    // Sawtooth has skewed duty cycle + moderate mid count
                    if (near_mid > 800) begin
                        wave_type_det <= 3'b011;  // Sawtooth
                    end else begin
                        wave_type_det <= 3'b000;  // Sine (distorted)
                    end
                end
                // Default: Sine
                else begin
                    wave_type_det <= 3'b000;  // Sine
                end

                near_peak    <= 0;
                near_valley  <= 0;
                near_mid     <= 0;
                hist_cnt     <= 0;
                zc_rapid     <= 0;
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
