//=============================================================================
// ILA ADC Debug Wrapper — Integrated Logic Analyzer for XADC signal chain
//=============================================================================
// Monitors the complete ADC data path from XADC raw output through CDC to
// 25MHz scope domain. Clocked by sys_clk (100MHz) for full XADC visibility.
//
// Signal bit mapping (probe[63:0]):
//   [63:62]  device_mode          — current UI mode
//   [61]     mux_sel              — 4053 mux channel select (0=CH1, 1=CH2)
//   [60]     ch1_vld_raw          — CH1 valid raw (single-cycle from XADC DRDY)
//   [59]     ch2_vld_raw          — CH2 valid raw (single-cycle from XADC DRDY)
//   [58]     drp_drdy             — XADC DRP data-ready (monitor for stuck-high)
//   [57]     drp_den              — XADC DRP enable (DEN pulse to XADC)
//   [56]     settling             — 4053 settle wait state (1=waiting for mux to settle)
//   [55]     den_pending          — DEN pending flag (1=waiting to issue next DEN)
//   [54]     startup_done         — XADC post-reset calibration complete
//   [53]     trigger_fired_25m    — scope trigger fired (25MHz domain, resync'd)
//   [52:43]  sample_wr_addr       — scope sample write address (25MHz, resync'd)
//   [42:31]  adc_ch1_raw          — CH1 12-bit raw XADC data
//   [30:19]  adc_ch2_raw          — CH2 12-bit raw XADC data
//   [18:11]  adc_ch1_8b           — CH1 8-bit scope-domain data
//   [10:3]   adc_ch2_8b           — CH2 8-bit scope-domain data
//   [2]      dbg_clk_25m          — 25MHz clock sampled for reference
//   [1:0]    reserved
//=============================================================================

module ila_adc_debug
(
    input  wire         clk,            // sys_clk (100MHz)
    input  wire [63:0]  probe           // debug probe bus
);

    // ILA IP core — single 64-bit probe clocked at 100MHz
    ila_adc u_ila (
        .clk    (clk),
        .probe0 (probe)
    );

endmodule
