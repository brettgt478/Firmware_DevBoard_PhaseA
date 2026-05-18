`timescale 1 ps / 1 ps
//
`default_nettype none

module agilex5_devkit (
    // Board PLL reference clock
    input  wire         pll_refclk_100,
    //
    // User switches and LEDs
    output wire [4-1:0] fpga_user_leds,
    input  wire [4-1:0] fpga_user_switches,
    input  wire [4-1:0] fpga_user_push_buttons,
    //
    //HPS
    //
    // HPS EMIF
    output wire         emif_hps_emif_mem_0_mem_ck_t,
    output wire         emif_hps_emif_mem_0_mem_ck_c,
    output wire [ 16:0] emif_hps_emif_mem_0_mem_a,
    output wire         emif_hps_emif_mem_0_mem_act_n,
    output wire [  1:0] emif_hps_emif_mem_0_mem_ba,
    output wire [  1:0] emif_hps_emif_mem_0_mem_bg,
    output wire         emif_hps_emif_mem_0_mem_cke,
    output wire         emif_hps_emif_mem_0_mem_cs_n,
    output wire         emif_hps_emif_mem_0_mem_odt,
    output wire         emif_hps_emif_mem_0_mem_reset_n,
    output wire         emif_hps_emif_mem_0_mem_par,
    input  wire         emif_hps_emif_mem_0_mem_alert_n,
    input  wire         emif_hps_emif_oct_0_oct_rzqin,
    input  wire         emif_hps_emif_ref_clk_0_clk,
    inout  wire [  4:0] emif_hps_emif_mem_0_mem_dqs_t,
    inout  wire [  4:0] emif_hps_emif_mem_0_mem_dqs_c,
    inout  wire [ 39:0] emif_hps_emif_mem_0_mem_dq,
    //
    // HPS IO48 Peripherals
    input  wire         hps_jtag_tck,
    input  wire         hps_jtag_tms,
    output wire         hps_jtag_tdo,
    input  wire         hps_jtag_tdi,
    output wire         hps_sdmmc_CCLK,
    inout  wire         hps_sdmmc_CMD,
    inout  wire         hps_sdmmc_D0,
    inout  wire         hps_sdmmc_D1,
    inout  wire         hps_sdmmc_D2,
    inout  wire         hps_sdmmc_D3,
    output wire         hps_emac0_TX_CLK,
    input  wire         hps_emac0_RX_CLK,
    output wire         hps_emac0_TX_CTL,
    input  wire         hps_emac0_RX_CTL,
    output wire         hps_emac0_TXD0,
    output wire         hps_emac0_TXD1,
    input  wire         hps_emac0_RXD0,
    input  wire         hps_emac0_RXD1,
    output wire         hps_emac0_PPS,
    input  wire         hps_emac0_PPS_TRIG,
    output wire         hps_emac0_TXD2,
    output wire         hps_emac0_TXD3,
    input  wire         hps_emac0_RXD2,
    input  wire         hps_emac0_RXD3,
    inout  wire         hps_emac0_MDIO,
    output wire         hps_emac0_MDC,
    output wire         hps_spim0_CLK,
    output wire         hps_spim0_MOSI,
    input  wire         hps_spim0_MISO,
    output wire         hps_spim0_SS0_N,
    input  wire         hps_uart0_RX,
    output wire         hps_uart0_TX,
    inout  wire         hps_i3c1_SDA,
    inout  wire         hps_i3c1_SCL,
    output wire         hps_trace_CLK,
    output wire         hps_trace_D0,
    output wire         hps_trace_D1,
    output wire         hps_trace_D2,
    output wire         hps_trace_D3,
    output wire         hps_trace_D4,
    output wire         hps_trace_D5,
    output wire         hps_trace_D6,
    output wire         hps_trace_D7,
    inout  wire         hps_gpio1_io3,
    inout  wire         hps_gpio1_io4,
    inout  wire         hps_gpio1_io12,
    inout  wire         hps_gpio1_io13,
    //
    // HPS External Oscillator
    input  wire         hps_osc_clk,
    //
    // External FPGA Reset
    input  wire         fpga_reset_n,
    //
    // FMC SPI bus to AD9176-FMC-EBZ (HSIO 3B, 1.2-V LVCMOS, Stage 4)
    output wire         fmc_spi_sck,
    output wire         fmc_spi_mosi,
    input  wire         fmc_spi_miso,
    output wire         fmc_spi_cs1_n,
    output wire         fmc_spi_cs2_n,
    output wire         fmc_spi_en,
    //
    // FMC control GPIOs (HSIO 3B, 1.2-V LVCMOS, Stage 4)
    output wire [1:0]   fmc_txen,
    output wire         fmc_pe_ctrl,
    //
    // FMC housekeeping (3.3-V LVCMOS, Stage 4)
    // - GA[1:0] are board pull-ups on this dev kit, not routed to the FPGA.
    // - PG_M2C / PG_C2M are routed to the on-board MAX10 board-mgmt FPGA on
    //   this dev kit, not to the main FPGA. The MAX10 handles the power-good
    //   handshake autonomously.
    input  wire         fmc_prsnt_n,
    //
    // JESD204B GTS reference clocks - FMC GBTCLK0/1_M2C (HSST refclk pads)
    // Both 312.5 MHz from the AD9176-FMC-EBZ HMC7044 (PLL2; common reference
    // via the same HMC7044, phase-locked). Agilex 5 GTS does not route a
    // refclk across transceiver tiles, so each link needs its own refclk
    // in the matching tile (CLAUDE.md ISSUE-015):
    //   GBTCLK0 (FMC D4/D5 -> AP16/AP21, UX 4B) drives u_jesd_link0 (TX0..TX3)
    //   GBTCLK1 (FMC B20/B21 -> AV16/AV21, UX 4C) drives u_jesd_link1 (TX4..TX7)
    // Only _p side named in RTL; _n complement handled implicitly by Quartus
    // via the "CURRENT MODE LOGIC (CML)" IO_STANDARD.
    input  wire         fmc_gbtclk0_p,
    input  wire         fmc_gbtclk1_p,
    //
    // JESD204B SYSREF (LVDS 1.2-V, HSIO 3B LA00_CC, source-sync subclass-1)
    // Quartus infers the LVDS_RX buffer from the IO_STANDARD assignment in
    // the qsf; only the _p pad is named in RTL, the _n location is set via
    // the "(n)" notation in the qsf.
    input  wire         fmc_sysref,
    //
    // JESD204B SYNC_N (LVDS 1.2-V, HSIO 3B LA01_CC / LA02)
    // AD9176 (RX side) drives SYNC_N to request alignment; FPGA TX samples.
    // (Confirmed from D:/altera_pro/26.1/.../j204b_gts_ports.csv line 21:
    //  jesd204_tx_sync_n is an INPUT to the TX IP.)
    input  wire         fmc_sync0,
    input  wire         fmc_sync1,
    //
    // JESD204B TX serial lanes - FMC TX0..TX7 (UX 4B / UX 4C HSST)
    // Routed externally to the AD9176-FMC-EBZ SERDIN0..SERDIN7 in a
    // scrambled order; the logical->physical lane map is captured in the
    // GTS IP wizard config inside ip/dac_subsys/dac_subsys.tcl.
    output wire [7:0]   fmc_serdin_tx_p,
    output wire [7:0]   fmc_serdin_tx_n
);
    // Constants
    localparam LED_PIO_WIDTH = 32;
    localparam DIPSW_PIO_WIDTH = 32;
    localparam BUTTONS_PIO_WIDTH = 32;

    // Clock and Reset
    wire sys_clk_100;
    wire sys_clk_100_reset_n;

    // Debounce logic to clean out push button glitches within 1ms
    wire [BUTTONS_PIO_WIDTH-1:0] fpga_debounced_buttons;
    wire [BUTTONS_PIO_WIDTH-1:0] fpga_push_buttons;
    assign fpga_push_buttons = {
        {BUTTONS_PIO_WIDTH - $size(fpga_user_push_buttons) {1'b0}}, fpga_user_push_buttons
    };

    debounce #(
        .WIDTH        (32),
        .POLARITY     ("LOW"),
        .TIMEOUT      (10000),  // at 100MHz this is a debounce time of 1ms
        .TIMEOUT_WIDTH(32)      // ceil(log2(TIMEOUT))
    ) debounce_inst (
        .clk     (sys_clk_100),
        .reset_n (sys_clk_100_reset_n),
        .data_in (fpga_push_buttons),
        .data_out(fpga_debounced_buttons)
    );

    // Assign DIPSW I/O
    wire [DIPSW_PIO_WIDTH-1:0] fpga_switches;
    assign fpga_switches = {
        {DIPSW_PIO_WIDTH - $size(fpga_user_switches) {1'b0}}, fpga_user_switches
    };

    // Create a heartbeat counter
    reg [22:0] heartbeat_count;
    always @(posedge sys_clk_100) begin
        if (!sys_clk_100_reset_n) begin
            heartbeat_count <= '0;
        end else begin
            heartbeat_count <= heartbeat_count + 23'd1;
        end
    end

    // Create a heartbeat LED
    wire heartbeat_led;
    assign heartbeat_led = heartbeat_count[22];

    // LED PIO
    wire [LED_PIO_WIDTH-1:0] fpga_leds;

    // Drive the USER PIN LEDs to be the HPS LED outputs
    // in addition to the heartbeat LED
    assign fpga_user_leds = {heartbeat_led, fpga_leds[2:0]};

    // Tie off all fabric to HPS interrupts
    wire [31:0] fpga2hps_interrupts;
    assign fpga2hps_interrupts = '0;

    // Directly loop reset request signal to the reset acknowledge signals.
    logic h2f_warm_reset_handshake_reset_ack;
    logic h2f_warm_reset_handshake_reset_req;

    assign h2f_warm_reset_handshake_reset_ack = h2f_warm_reset_handshake_reset_req;

    // FMC housekeeping pack into dac_status PIO (Stage 4).
    //   [0]    = ~prsnt_n (active-high presence)
    //   [1]    = reserved (PG_M2C is routed to board-mgmt MAX10, not main FPGA)
    //   [2]    = pg_c2m_loopback (what u_pg_c2m_pio is driving; physical pin
    //                              dangles -- routed to MAX10 board-mgmt FPGA)
    //   [4:3]  = reserved (GA[1:0] not routed to FPGA on this dev kit)
    //   [5]    = fmc_ready (Stage 5 (merged): gates JESD GTS reset deassertion)
    //   [31:6] = '0       (reserved; JESD link status added in later stage)
    wire fmc_pg_c2m_drive;          // PIO output bit (dangling externally)
    wire fmc_ready_internal;
    wire [31:0] dac_status_word;
    assign dac_status_word = {26'd0, fmc_ready_internal, 1'b0, fmc_pg_c2m_drive, 1'b0, ~fmc_prsnt_n};

    // Stage 5 (merged): FMC presence + power-good gate. PG_M2C is owned by
    // the on-board MAX10 board-mgmt FPGA (CLAUDE.md ISSUE-012); the MAX10
    // gates FMC VADJ and reports power-good back to the AD9176-FMC-EBZ
    // autonomously. From the main Agilex's perspective we tie pg_m2c high
    // and let the prsnt_n debounce drive the FPGA-side handshake.
    fmc_handshake u_fmc_handshake (
        .clk         (sys_clk_100),
        .rst         (~sys_clk_100_reset_n),
        .fmc_prsnt_n (fmc_prsnt_n),
        .fmc_pg_m2c  (1'b1),
        .fmc_ready   (fmc_ready_internal)
    );

    // Stage 5 (merged): JESD reset gates on fmc_ready per CLAUDE.md s6 #4.
    // jesd_reset_n: active-low; deasserted only when both system reset is
    // deasserted AND fmc_ready is asserted. jesd_reset is the active-high
    // companion that goes to the u_clk_bridge_jesd-domain reset bridge.
    wire jesd_reset_n_gated  = fpga_reset_n & fmc_ready_internal;
    wire jesd_reset_active_h = ~jesd_reset_n_gated;

    // Stage 5 (merged): JESD SYSREF capture. Differential LVDS_RX is inferred
    // by Quartus from the "1.2-V TRUE DIFFERENTIAL SIGNALING" IO_STANDARD in
    // the qsf; only the _p pad appears in RTL. 2-stage synchronizer captures
    // the SYSREF edge into the JESD link clock domain (subclass-1).
    wire sysref_captured;
    wire jesd_link_clk;          // loopback from u_jesd_link0.txphy_clk[0]
    sysref_capture u_sysref_capture (
        .sysref_in  (fmc_sysref),
        .link_clk   (jesd_link_clk),
        .rst_n      (jesd_reset_n_gated),
        .sysref_out (sysref_captured)
    );

    // Stage 5 (merged): GBTCLK0/1 refclk pads (HSST transceiver refclk pads on
    // UX 4B / UX 4C). Only _p in RTL; CML IO_STANDARD in qsf tells Quartus
    // these are differential refclks (the _n complement is auto-placed).
    wire fmc_gbtclk0_buf;
    wire fmc_gbtclk1_buf;
    assign fmc_gbtclk0_buf = fmc_gbtclk0_p;
    assign fmc_gbtclk1_buf = fmc_gbtclk1_p;

    // Stage 5 (merged): txphy_clk loopback. u_jesd_link0 drives
    // dac_txphy_clk_out (4-bit, one per lane); the [0] lane feeds back into
    // u_clk_bridge_jesd as the jesd_tx_link_clk source. The loop is closed
    // here in fabric (the actual cycle break is the txphy_clk output buffer
    // inside the GTS PMA). Both GTS IPs share txlink_clk so the data path
    // is isomorphic across links.
    wire [3:0] dac_txphy_clk_bus;
    assign jesd_link_clk = dac_txphy_clk_bus[0];

    // Baseline-A55 system top module
    baseline_top u_baseline_top (
        // Board PLL reference clock
        .pll_refclk_100_clk                   (pll_refclk_100),
        // External FPGA reset
        .fpga_reset_n_reset_n                 (fpga_reset_n),
        // System clock and reset to FPGA
        .system_clk_clk                       (sys_clk_100),
        .system_reset_n_reset_n               (sys_clk_100_reset_n),
        //
        //HPS
        // HPS Clock
        .hps_io_hps_osc_clk                   (hps_osc_clk),
        // HPS reset to the fabric
        .h2f_warm_reset_handshake_reset_req   (h2f_warm_reset_handshake_reset_req),
        .h2f_warm_reset_handshake_reset_ack   (h2f_warm_reset_handshake_reset_ack),
        // HPS EMIF interface
        .emif_hps_emif_mem_ck_0_mem_ck_t      (emif_hps_emif_mem_0_mem_ck_t),
        .emif_hps_emif_mem_ck_0_mem_ck_c      (emif_hps_emif_mem_0_mem_ck_c),
        .emif_hps_emif_mem_0_mem_a            (emif_hps_emif_mem_0_mem_a),
        .emif_hps_emif_mem_0_mem_act_n        (emif_hps_emif_mem_0_mem_act_n),
        .emif_hps_emif_mem_0_mem_ba           (emif_hps_emif_mem_0_mem_ba),
        .emif_hps_emif_mem_0_mem_bg           (emif_hps_emif_mem_0_mem_bg),
        .emif_hps_emif_mem_0_mem_cke          (emif_hps_emif_mem_0_mem_cke),
        .emif_hps_emif_mem_0_mem_cs_n         (emif_hps_emif_mem_0_mem_cs_n),
        .emif_hps_emif_mem_0_mem_odt          (emif_hps_emif_mem_0_mem_odt),
        .emif_hps_emif_mem_reset_n_mem_reset_n(emif_hps_emif_mem_0_mem_reset_n),
        .emif_hps_emif_mem_0_mem_par          (emif_hps_emif_mem_0_mem_par),
        .emif_hps_emif_mem_0_mem_alert_n      (emif_hps_emif_mem_0_mem_alert_n),
        .emif_hps_emif_mem_0_mem_dqs_t        (emif_hps_emif_mem_0_mem_dqs_t),
        .emif_hps_emif_mem_0_mem_dqs_c        (emif_hps_emif_mem_0_mem_dqs_c),
        .emif_hps_emif_mem_0_mem_dq           (emif_hps_emif_mem_0_mem_dq),
        .emif_hps_emif_oct_0_oct_rzqin        (emif_hps_emif_oct_0_oct_rzqin),
        .emif_hps_emif_ref_clk_0_clk          (emif_hps_emif_ref_clk_0_clk),
        // HPS Peripherals
        .hps_io_jtag_tck                      (hps_jtag_tck),
        .hps_io_jtag_tms                      (hps_jtag_tms),
        .hps_io_jtag_tdo                      (hps_jtag_tdo),
        .hps_io_jtag_tdi                      (hps_jtag_tdi),
        .hps_io_emac0_tx_clk                  (hps_emac0_TX_CLK),
        .hps_io_emac0_rx_clk                  (hps_emac0_RX_CLK),
        .hps_io_emac0_tx_ctl                  (hps_emac0_TX_CTL),
        .hps_io_emac0_rx_ctl                  (hps_emac0_RX_CTL),
        .hps_io_emac0_txd0                    (hps_emac0_TXD0),
        .hps_io_emac0_txd1                    (hps_emac0_TXD1),
        .hps_io_emac0_rxd0                    (hps_emac0_RXD0),
        .hps_io_emac0_rxd1                    (hps_emac0_RXD1),
        .hps_io_emac0_pps                     (hps_emac0_PPS),
        .hps_io_emac0_pps_trig                (hps_emac0_PPS_TRIG),
        .hps_io_emac0_txd2                    (hps_emac0_TXD2),
        .hps_io_emac0_txd3                    (hps_emac0_TXD3),
        .hps_io_emac0_rxd2                    (hps_emac0_RXD2),
        .hps_io_emac0_rxd3                    (hps_emac0_RXD3),
        .hps_io_mdio0_mdio                    (hps_emac0_MDIO),
        .hps_io_mdio0_mdc                     (hps_emac0_MDC),
        .hps_io_sdmmc_cclk                    (hps_sdmmc_CCLK),
        .hps_io_sdmmc_cmd                     (hps_sdmmc_CMD),
        .hps_io_sdmmc_data0                   (hps_sdmmc_D0),
        .hps_io_sdmmc_data1                   (hps_sdmmc_D1),
        .hps_io_sdmmc_data2                   (hps_sdmmc_D2),
        .hps_io_sdmmc_data3                   (hps_sdmmc_D3),
        .hps_io_i3c1_sda                      (hps_i3c1_SDA),
        .hps_io_i3c1_scl                      (hps_i3c1_SCL),
        .hps_io_uart0_rx                      (hps_uart0_RX),
        .hps_io_uart0_tx                      (hps_uart0_TX),
        .hps_io_spim0_clk                     (hps_spim0_CLK),
        .hps_io_spim0_mosi                    (hps_spim0_MOSI),
        .hps_io_spim0_miso                    (hps_spim0_MISO),
        .hps_io_spim0_ss0_n                   (hps_spim0_SS0_N),
        .hps_io_trace_clk                     (hps_trace_CLK),
        .hps_io_trace_data0                   (hps_trace_D0),
        .hps_io_trace_data1                   (hps_trace_D1),
        .hps_io_trace_data2                   (hps_trace_D2),
        .hps_io_trace_data3                   (hps_trace_D3),
        .hps_io_trace_data4                   (hps_trace_D4),
        .hps_io_trace_data5                   (hps_trace_D5),
        .hps_io_trace_data6                   (hps_trace_D6),
        .hps_io_trace_data7                   (hps_trace_D7),
        .hps_io_gpio27                        (hps_gpio1_io3),
        .hps_io_gpio28                        (hps_gpio1_io4),
        .hps_io_gpio36                        (hps_gpio1_io12),
        .hps_io_gpio37                        (hps_gpio1_io13),
        //
        // Interrupts
        .f2h_interrupts_irq                   (fpga2hps_interrupts),
        //
        // LEDs, Push Buttons and DIP Switches IOs
        .user_leds_export                     (fpga_leds),
        .user_switches_export                 (fpga_switches),
        .user_push_buttons_export             (fpga_debounced_buttons),
        //
        // NiosV subsys PIO
        .niosv_pio_in_export                  ('0),
        .niosv_pio_out_export                 (),
        //
        // dac_subsys conduits (Stage 4) -- FMC SPI + TXEN + PE_CTRL + SPI_EN + PG_C2M
        .dac_spi_MOSI                         (fmc_spi_mosi),
        .dac_spi_MISO                         (fmc_spi_miso),
        .dac_spi_SCLK                         (fmc_spi_sck),
        .dac_spi_SS_n                         ({fmc_spi_cs2_n, fmc_spi_cs1_n}),
        .dac_tx_en_export                     (fmc_txen),
        .dac_pe_ctrl_export                   (fmc_pe_ctrl),
        .dac_spi_en_export                    (fmc_spi_en),
        // dac_pg_c2m_export: still bound to the local fmc_pg_c2m_drive net so
        // dac_status_word can read back what HPS wrote. The external FMC pin
        // for PG_C2M (FMC D1) is owned by the board-mgmt MAX10, not the main
        // FPGA, so this net never reaches a package pin.
        .dac_pg_c2m_export                    (fmc_pg_c2m_drive),
        .dac_status_export                    (dac_status_word),
        //
        // Stage 5 (merged) JESD external interfaces.
        // Clock sinks (driven from top SV).
        .dac_xcvr_refclk_clk                  (fmc_gbtclk0_buf),
        .dac_xcvr_refclk_4c_clk               (fmc_gbtclk1_buf),
        .dac_jesd_tx_link_clk_clk             (jesd_link_clk),
        // Reset sinks (active-high jesd_reset + active-low jesd_reset_n,
        // both gated on fmc_ready).
        .dac_jesd_reset_reset                 (jesd_reset_active_h),
        .dac_jesd_reset_n_reset_n             (jesd_reset_n_gated),
        // SYSREF: same captured single-bit drives both link IPs.
        .dac_sysref_link0_export              (sysref_captured),
        .dac_sysref_link1_export              (sysref_captured),
        // SYNC_N from AD9176 (FPGA TX samples).
        .dac_sync_n_link0_export              (fmc_sync0),
        .dac_sync_n_link1_export              (fmc_sync1),
        // TX serial lanes (4 per link, 8 total → FMC TX0..TX7 via scrambled
        // logical-to-physical map; physical pin order set by qsf).
        .dac_tx_serial_link0_export           (fmc_serdin_tx_p[3:0]),
        .dac_tx_serial_link0_n_export         (fmc_serdin_tx_n[3:0]),
        .dac_tx_serial_link1_export           (fmc_serdin_tx_p[7:4]),
        .dac_tx_serial_link1_n_export         (fmc_serdin_tx_n[7:4]),
        // txphy_clk loopback (link0 drives link clock for both IPs).
        .dac_txphy_clk_out_export             (dac_txphy_clk_bus)
    );

endmodule
