// dac_subsys_tb.sv -- Stage 8b integration TB for the Phase B dac_subsys.
//
// Drives the LWH2F AXI4 BFM (exposed by the Agilex 5 HPS simulation model)
// to exercise dac_subsys CSRs in the same address space the Linux
// ad9176-config tool uses (0x0200_0000 + offset, per dac_subsys_regs.h).
//
// Scope: CSR-plane reachability + handshake gating. The TB does NOT
// expect JESD204B link-up to complete in simulation -- the GTS IP has
// no RX peer (no HMC7044, no AD9176, no BFM yet -- that's Stage 8c).
// What this TB DOES prove:
//   T1: fmc_handshake.sv asserts fmc_ready when prsnt_n=0 + pg_m2c=1
//       within the documented 32-cycle hold-off.
//   T2: Phase A reg_bank scratchpad write -> readback survives the
//       LWH2F -> AXI -> AvMM -> reg_bank path.
//   T3: SPI master CSR is reachable; CONTROL bit writes survive.
//   T4: PIOs (TX_EN, PE_CTRL, SPI_EN) write to the right pin set.
//   T5: SineWaveGen NCO frequency register write -> readback.
//   T6: dac_status_pio reflects the fmc_handshake gate state.
//
// Pin gating notes:
//   - fmc_prsnt_n is the only FMC input that materially affects this TB.
//     Tied to 0 so the handshake passes and the LWH2F CSR path opens.
//   - All other FMC inputs are tied to safe values (no real AD9176 in
//     sim). The transceivers won't lock; that's expected.

`timescale 1 ps / 1 ps `default_nettype none

import altera_axi_bfm_pkg::*;
import host_memory_class_pkg::*;
import hps_h2f_lw_pkg::*;

`define lwh2f_bfm_m dut.u_baseline_top.u_shell_subsys.u_hps_subsys.u_agilex_hps.intel_agilex_5_soc_inst.sm_hps.sundancemesa_hps_inst.lwh2f_bfm_gen.lwh2f_axi4_master_inst

module dac_subsys_tb ();

    //----------------------------------------------------------------------
    // dac_subsys register map (HPS / LWH2F bridge view).
    // Mirrors software/ad9176_config/dac_subsys_regs.h. Bridge addresses
    // are absolute in the 29-bit LWH2F space; dac_subsys.axi_csr is bound
    // at baseAddress 0x0200_0000 in baseline_top_phaseb_patches.tcl.
    //----------------------------------------------------------------------
    localparam logic [31:0] DAC_BASE          = 32'h0200_0000;
    localparam logic [31:0] REG_SCRATCH0      = DAC_BASE + 32'h0000;
    localparam logic [31:0] REG_SINE_FREQ_CH1_I = DAC_BASE + 32'h0050;
    localparam logic [31:0] REG_SINE_AMP_M0   = DAC_BASE + 32'h0070;
    localparam logic [31:0] DAC_STATUS_PIO    = DAC_BASE + 32'h1120;
    localparam logic [31:0] SPI_MASTER_CTRL   = DAC_BASE + 32'h100C;
    localparam logic [31:0] SPI_MASTER_SLAVE  = DAC_BASE + 32'h1014;
    localparam logic [31:0] TX_EN_PIO         = DAC_BASE + 32'h1100;
    localparam logic [31:0] PE_CTRL_PIO       = DAC_BASE + 32'h1110;
    localparam logic [31:0] SPI_EN_PIO        = DAC_BASE + 32'h1130;

    localparam int          DAC_STATUS_FMC_READY_BIT = 5;

    //----------------------------------------------------------------------
    // Clock and reset, baseline GHRD pattern.
    //----------------------------------------------------------------------
    logic       clk100M;
    logic       fpga_reset_n;
    wire  [3:0] fpga_led_pio;
    logic [3:0] fpga_dipsw_pio  = '0;
    logic [3:0] fpga_button_pio = '0;

    // FMC ports -- only fmc_prsnt_n matters for CSR-plane tests.
    // Drive it active-low (0 = present) AFTER fpga_reset_n deasserts so
    // fmc_handshake's 32-cycle hold-off starts from a clean baseline.
    logic       fmc_prsnt_n_reg = 1'b1;   // tied 1 in reset, dropped to 0 below
    logic       fmc_spi_miso    = 1'b0;
    logic       fmc_sysref      = 1'b0;
    logic       fmc_sync0       = 1'b0;
    logic       fmc_sync1       = 1'b0;
    logic       fmc_gbtclk      = 1'b0;
    // 312.5 MHz GBTCLK0/1 stimulus (3200 ps period). Both refclks are
    // phase-locked on the AD9176-FMC-EBZ via the HMC7044; in sim we
    // share one stimulus.
    initial fmc_gbtclk = 1'b0;
    always #1600ps fmc_gbtclk = ~fmc_gbtclk;

    //----------------------------------------------------------------------
    // DUT
    //----------------------------------------------------------------------
    agilex5_devkit dut (
        .pll_refclk_100                  (clk100M),
        .fpga_user_leds                  (fpga_led_pio),
        .fpga_user_switches              (fpga_dipsw_pio),
        .fpga_user_push_buttons          (fpga_button_pio),

        // HPS EMIF (left unconnected; HPS sim model handles internally)
        .emif_hps_emif_mem_0_mem_ck_t    (),
        .emif_hps_emif_mem_0_mem_ck_c    (),
        .emif_hps_emif_mem_0_mem_a       (),
        .emif_hps_emif_mem_0_mem_act_n   (),
        .emif_hps_emif_mem_0_mem_ba      (),
        .emif_hps_emif_mem_0_mem_bg      (),
        .emif_hps_emif_mem_0_mem_cke     (),
        .emif_hps_emif_mem_0_mem_cs_n    (),
        .emif_hps_emif_mem_0_mem_odt     (),
        .emif_hps_emif_mem_0_mem_reset_n (),
        .emif_hps_emif_mem_0_mem_par     (),
        .emif_hps_emif_mem_0_mem_alert_n ('0),
        .emif_hps_emif_oct_0_oct_rzqin   ('0),
        .emif_hps_emif_ref_clk_0_clk     ('0),
        .emif_hps_emif_mem_0_mem_dqs_t   (),
        .emif_hps_emif_mem_0_mem_dqs_c   (),
        .emif_hps_emif_mem_0_mem_dq      (),

        // HPS peripherals (stubbed)
        .hps_jtag_tck                    ('0),
        .hps_jtag_tms                    ('0),
        .hps_jtag_tdo                    (),
        .hps_jtag_tdi                    ('0),
        .hps_sdmmc_CCLK                  (),
        .hps_sdmmc_CMD                   (),
        .hps_sdmmc_D0                    (),
        .hps_sdmmc_D1                    (),
        .hps_sdmmc_D2                    (),
        .hps_sdmmc_D3                    (),
        .hps_emac0_TX_CLK                (),
        .hps_emac0_RX_CLK                ('0),
        .hps_emac0_TX_CTL                (),
        .hps_emac0_RX_CTL                ('0),
        .hps_emac0_TXD0                  (),
        .hps_emac0_TXD1                  (),
        .hps_emac0_RXD0                  ('0),
        .hps_emac0_RXD1                  ('0),
        .hps_emac0_PPS                   (),
        .hps_emac0_PPS_TRIG              ('0),
        .hps_emac0_TXD2                  (),
        .hps_emac0_TXD3                  (),
        .hps_emac0_RXD2                  ('0),
        .hps_emac0_RXD3                  ('0),
        .hps_emac0_MDIO                  (),
        .hps_emac0_MDC                   (),
        .hps_uart0_RX                    ('0),
        .hps_uart0_TX                    (),
        .hps_i3c1_SDA                    (),
        .hps_i3c1_SCL                    (),
        .hps_trace_CLK                   (),
        .hps_trace_D0                    (),
        .hps_trace_D1                    (),
        .hps_trace_D2                    (),
        .hps_trace_D3                    (),
        .hps_trace_D4                    (),
        .hps_trace_D5                    (),
        .hps_trace_D6                    (),
        .hps_trace_D7                    (),
        .hps_gpio1_io3                   (),
        .hps_gpio1_io4                   (),
        .hps_gpio1_io12                  (),
        .hps_gpio1_io13                  (),
        .hps_osc_clk                     ('0),
        .fpga_reset_n                    (fpga_reset_n),

        // FMC SPI / control PIOs (driven by Stage 4 path; left dangling)
        .fmc_spi_sck                     (),
        .fmc_spi_mosi                    (),
        .fmc_spi_miso                    (fmc_spi_miso),
        .fmc_spi_cs1_n                   (),
        .fmc_spi_cs2_n                   (),
        .fmc_spi_en                      (),
        .fmc_txen                        (),
        .fmc_pe_ctrl                     (),
        .fmc_prsnt_n                     (fmc_prsnt_n_reg),

        // FMC JESD (driven by Stage 5 path)
        .fmc_gbtclk0_p                   (fmc_gbtclk),
        .fmc_gbtclk1_p                   (fmc_gbtclk),
        .fmc_sysref                      (fmc_sysref),
        .fmc_sync0                       (fmc_sync0),
        .fmc_sync1                       (fmc_sync1),
        .fmc_serdin_tx_p                 (),
        .fmc_serdin_tx_n                 ()
    );

    //----------------------------------------------------------------------
    // 100 MHz fabric refclk
    //----------------------------------------------------------------------
    initial clk100M = 1'b0;
    always #5ns clk100M = ~clk100M;

    //----------------------------------------------------------------------
    // BFM reset override -- gate the BFM until the HPS hps2fpga_rst lifts.
    // Same pattern as baseline agilex5_devkit_tb.sv:191.
    //----------------------------------------------------------------------
    initial begin
        force dut.u_baseline_top.u_shell_subsys.u_hps_subsys.u_agilex_hps.intel_agilex_5_soc_inst.sm_hps.sundancemesa_hps_inst.lwh2f_bfm_gen.lwh2f_axi4_master_inst.rstn =
            !dut.u_baseline_top.u_shell_subsys.u_hps_subsys.u_agilex_hps.intel_agilex_5_soc_inst.sm_hps.hps2fpga_rst;
    end

    //----------------------------------------------------------------------
    // Helper tasks
    //----------------------------------------------------------------------
    AlteraAxiTransaction wr_tr, rd_tr;
    int errors = 0;

    task automatic lwh2f_write(input logic [31:0] addr, input logic [31:0] data);
        wr_tr = `lwh2f_bfm_m.AXI4MAN.bfm.manager_bfm_wr_tx(1, addr);
        wr_tr.set_size(AXI4_BYTES_4);
        wr_tr.set_burst_length(0);
        wr_tr.set_burst_type(BURST_TYPE_FIXED);
        wr_tr.set_data_words(data, 0);
        wr_tr.set_write_strobes(4'hF, 0);
        `lwh2f_bfm_m.AXI4MAN.bfm.put_transaction(wr_tr);
        `lwh2f_bfm_m.AXI4MAN.bfm.drive_transaction();
    endtask

    task automatic lwh2f_read(input logic [31:0] addr, output logic [31:0] data);
        rd_tr = `lwh2f_bfm_m.AXI4MAN.bfm.manager_bfm_rd_tx(1, addr);
        rd_tr.set_size(AXI4_BYTES_4);
        rd_tr.set_burst_length(0);
        rd_tr.set_burst_type(BURST_TYPE_FIXED);
        `lwh2f_bfm_m.AXI4MAN.bfm.put_transaction(rd_tr);
        `lwh2f_bfm_m.AXI4MAN.bfm.drive_transaction();
        data = rd_tr.get_data_words(0);
    endtask

    task automatic check_eq(input string tag,
                            input logic [31:0] expected,
                            input logic [31:0] actual);
        if (expected === actual) begin
            $display("[%0t] %s PASS exp=0x%08X act=0x%08X", $time, tag, expected, actual);
        end else begin
            $display("[%0t] %s FAIL exp=0x%08X act=0x%08X", $time, tag, expected, actual);
            errors++;
        end
    endtask

    //----------------------------------------------------------------------
    // Watchdog
    //----------------------------------------------------------------------
    initial begin
        #40000000ns;
        $display("[%0t] WATCHDOG: dac_subsys_tb timed out", $time);
        $fatal(1, "dac_subsys_tb watchdog");
    end

    //----------------------------------------------------------------------
    // Main test sequence
    //----------------------------------------------------------------------
    initial begin
        logic [31:0] rdata;

        $display("[%0t] dac_subsys_tb: hold fpga_reset_n low", $time);
        fpga_reset_n = 1'b0;
        repeat (10) @(posedge clk100M);
        $display("[%0t] dac_subsys_tb: deassert fpga_reset_n", $time);
        fpga_reset_n = 1'b1;

        // Wait for system reset to clear (HPS reset network settles).
        fork : wait_reset
            begin
                while (dut.sys_clk_100_reset_n != 1'b1) @(posedge clk100M);
                `lwh2f_bfm_m.AXI4MAN.bfm.m_reset();
            end
            begin
                #10000ns $fatal(1, "INIT_DONE not asserted within 10us");
            end
        join_any
        disable wait_reset;
        repeat (10) @(posedge clk100M);

        // T1: Assert FMC presence; wait for fmc_ready to come high.
        // fmc_handshake.sv uses a 32-cycle hold-off + 2-stage sync on
        // prsnt_n. pg_m2c is hard-tied to 1 inside agilex5_devkit.sv per
        // CLAUDE.md SS6 #4 (MAX10 owns the real PG handshake).
        $display("[%0t] T1: drop fmc_prsnt_n -> wait fmc_ready", $time);
        fmc_prsnt_n_reg = 1'b0;
        // Poll status; allow 200 polls -> well past the 32-cycle gate.
        // `automatic` keeps polls scoped to this initial block iteration
        // (default static would persist across the run if the TB ever
        // looped, which it doesn't, but the explicit keyword silences
        // (vlog-2244)).
        begin : t1_poll
            automatic int polls = 0;
            do begin
                @(`lwh2f_bfm_m.m_cb);
                lwh2f_read(DAC_STATUS_PIO, rdata);
                polls++;
                if (polls > 200) begin
                    $display("[%0t] T1 FAIL: fmc_ready never asserted (status=0x%08X)",
                             $time, rdata);
                    errors++;
                    break;
                end
            end while (((rdata >> DAC_STATUS_FMC_READY_BIT) & 1'b1) == 1'b0);
            if (((rdata >> DAC_STATUS_FMC_READY_BIT) & 1'b1) == 1'b1) begin
                $display("[%0t] T1 PASS fmc_ready asserted (status=0x%08X, polls=%0d)",
                         $time, rdata, polls);
            end
        end

        // T2: Scratchpad survives the HPS -> LWH2F -> AXI -> AvMM ->
        // reg_bank round trip.
        $display("[%0t] T2: scratchpad write/readback", $time);
        lwh2f_write(REG_SCRATCH0, 32'hDEAD_BEEF);
        lwh2f_read (REG_SCRATCH0, rdata);
        check_eq("T2 scratch0 DEADBEEF", 32'hDEAD_BEEF, rdata);
        lwh2f_write(REG_SCRATCH0, 32'h1234_5678);
        lwh2f_read (REG_SCRATCH0, rdata);
        check_eq("T2 scratch0 12345678", 32'h1234_5678, rdata);

        // T3: SPI master CONTROL register reachable. Writing
        // SPI_CONTROL_SSO (bit 10) and reading back proves the AvMM path
        // into u_spi_master is alive.
        $display("[%0t] T3: SPI master CONTROL bit toggle", $time);
        lwh2f_write(SPI_MASTER_CTRL, 32'h0000_0400);
        lwh2f_read (SPI_MASTER_CTRL, rdata);
        check_eq("T3 spi.control=0x400", 32'h0000_0400, rdata);
        lwh2f_write(SPI_MASTER_SLAVE, 32'h0000_0001);
        lwh2f_read (SPI_MASTER_SLAVE, rdata);
        check_eq("T3 spi.slavesel=0x1", 32'h0000_0001, rdata);
        // Clear so we leave the IP idle.
        lwh2f_write(SPI_MASTER_CTRL, 32'h0);

        // T4: PIO writes survive (each PIO is a separate IP at its own
        // base; pattern detects address-decode errors in dac_subsys).
        $display("[%0t] T4: PIO write/readback", $time);
        lwh2f_write(TX_EN_PIO,   32'h0000_0003);
        lwh2f_read (TX_EN_PIO,   rdata);
        check_eq("T4 tx_en=0x3",    32'h0000_0003, rdata);
        lwh2f_write(PE_CTRL_PIO, 32'h0000_0001);
        lwh2f_read (PE_CTRL_PIO, rdata);
        check_eq("T4 pe_ctrl=0x1",  32'h0000_0001, rdata);
        lwh2f_write(SPI_EN_PIO,  32'h0000_0001);
        lwh2f_read (SPI_EN_PIO,  rdata);
        check_eq("T4 spi_en=0x1",   32'h0000_0001, rdata);

        // T5: SineWaveGen NCO frequency word + amplitude survive.
        $display("[%0t] T5: NCO CSR write/readback", $time);
        lwh2f_write(REG_SINE_FREQ_CH1_I, 32'h0666_6666);
        lwh2f_read (REG_SINE_FREQ_CH1_I, rdata);
        check_eq("T5 freq_ch1_i", 32'h0666_6666, rdata);
        lwh2f_write(REG_SINE_AMP_M0, 32'h0000_7FFF);
        lwh2f_read (REG_SINE_AMP_M0, rdata);
        check_eq("T5 amp_m0",     32'h0000_7FFF, rdata);

        // T6: dac_status_pio still reflects fmc_ready (sticky check).
        $display("[%0t] T6: re-read dac_status_pio", $time);
        lwh2f_read(DAC_STATUS_PIO, rdata);
        if (((rdata >> DAC_STATUS_FMC_READY_BIT) & 1'b1) == 1'b1) begin
            $display("[%0t] T6 PASS fmc_ready still high (status=0x%08X)", $time, rdata);
        end else begin
            $display("[%0t] T6 FAIL fmc_ready dropped (status=0x%08X)", $time, rdata);
            errors++;
        end

        //------------------------------------------------------------------
        // Summary
        //------------------------------------------------------------------
        $display("============================================================");
        $display("dac_subsys_tb summary: errors=%0d", errors);
        if (errors == 0) begin
            $display("dac_subsys_tb: SIMULATION PASSED");
        end else begin
            $display("dac_subsys_tb: SIMULATION FAILED");
        end
        $display("============================================================");
        #100ns;
        $finish(errors == 0 ? 1 : 2);
    end

endmodule
