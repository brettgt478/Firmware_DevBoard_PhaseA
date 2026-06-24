# Phase B `agilex5_devkit` Architecture

Reference document for the firmware in this repository. Cross-links into
[CLAUDE.md](../CLAUDE.md) and [PLAN.md](../PLAN.md) but is self-contained
for someone walking into the project cold.

---

## 1. Big picture

The deployable build (`projects/agilex5_devkit/agilex5_devkit.qpf`) targets
the **DK-A5E065BB32AES1 Agilex 5 E-Series 065B Premium Development Kit**
(production 065B silicon, part `A5ED065BB32AE4S`) with an **Analog Devices
AD9176-FMC-EBZ** mezzanine on the on-board FMC connector (J34).

> **Design approach: fabric-only on the production GHRD.** Phase B keeps the HPS
> (pin-mux, clocks, EMIF, peripherals) byte-stable against the production
> baseline so the prebuilt bootloader boots unchanged; only the FPGA fabric
> (`ghrd.core.rbf`) is regenerated and shipped inside `kernel.itb`. The Stage 1
> ES retarget (`A5ED065BB32AE6SR0`, DDR4-1600) was reverted — see
> [CLAUDE.md §6 #10–#12](../CLAUDE.md#6-critical-constraints),
> [DESIGN_DECISION.md](../DESIGN_DECISION.md), and ISSUE-011.

The bitstream provides:

- Baseline Altera GSRD (HPS, EMIF DDR4-3200, USB3.1 PHY, NiosV debug
  fabric, JTAG-to-Avalon master) -- inherited as-is from the upstream
  **production** `a5ed065b-premium-devkit-oobe/baseline-a55` reference.
- Phase A `dac_controller_0` IP wrapped as a Platform Designer
  component, providing NCO + JESD transport + sync + DcFifo + reg_bank.
- Two `intel_jesd204b_gts` subsystem instances (one per AD9176 DAC
  core), each L=4 / M=4 / 12.5 Gbps / mode 4 / subclass 1.
- A fabric **Avalon-MM SPI Master** (24-bit) driving the AD9176 SPI
  control plane via the FMC `LA03/LA04/LA05` HSIO 3B 1.2-V pins.
- Five PIOs for FMC-side discrete control / status: `TXEN[1:0]`,
  `PE_CTRL`, `SPI_EN`, `PG_C2M` (loopback only -- see ISSUE-012),
  `dac_status_pio` (FMC presence + power-good + JESD status).
- An FMC presence-and-power-good handshake module
  ([projects/agilex5_devkit/src/fmc_handshake.sv](../projects/agilex5_devkit/src/fmc_handshake.sv))
  gating JESD GTS reset deassertion.
- A SYSREF receiver
  ([projects/agilex5_devkit/src/sysref_capture.vhd](../projects/agilex5_devkit/src/sysref_capture.vhd))
  re-synchronizing the AD9176 source-synchronous SYSREF to the JESD
  link clock for subclass-1 deterministic latency.

User-space integration is the Linux tool at
[software/ad9176_config/](../software/ad9176_config/), described in
Section 7 below.

---

## 2. Subsystem hierarchy

```
agilex5_devkit (top, projects/agilex5_devkit/agilex5_devkit.sv)
|
+-- baseline_top (projects/agilex5_devkit/baseline_top.qsys)
    |
    +-- u_shell_subsys (shell_subsys.qsys, unchanged)
    |   +-- u_sys_pll        system PLL: 100 MHz refclk -> 100 MHz fabric clock
    |   +-- u_clks_and_rsts  clocks_and_resets.sv: synchronous async-deassert
    |   |                    resets per clock domain
    |   +-- usb31_phy        USB 3.1 PHY (untouched)
    |
    +-- u_hps_subsys (hps_subsys.qsys, unchanged baseline)
    |   +-- u_agilex_hps     A76 + A55 cluster, peripherals on IO48
    |   +-- u_emif_hps       EMIF I/O 96B HPS DDR4-3200 (production baseline;
    |                        DBI exported/bonded -- ES retarget reverted, see
    |                        ISSUE-011)
    |
    +-- u_fabric_subsys (fabric_subsys.qsys, unchanged baseline)
    |   +-- u_jtag_avalon    NiosV JTAG-to-Avalon master (debug)
    |   +-- u_ocram          on-chip RAM
    |   +-- u_user_pio       LEDs/switches/buttons
    |   +-- u_h2f_bridge     HPS H2F (full) -> fabric
    |   +-- u_lwh2f_bridge   HPS LWH2F (lightweight) -> fabric
    |   +-- u_f2sdram        F2SDRAM adapter
    |   +-- u_ace5l_xlate    ACE5-lite coherency translator
    |
    +-- u_niosv_subsys (niosv_subsys.qsys, unchanged baseline)
    |
    +-- u_dac_subsys (dac_subsys.qsys, Phase B addition)
        |
        +-- u_csr_bridge          Avalon-MM CSR bridge from LWH2F
        +-- u_dac_controller_0    Phase A IP (10 VHDL files)
        +-- u_jesd_link0          intel_jesd204b_gts (L=4, M=4, link 0)
        +-- u_jesd_link1          intel_jesd204b_gts (L=4, M=4, link 1)
        +-- u_xcvr_refclk         GBTCLK0 PMA refclk (UX 4B)
        +-- u_xcvr_refclk_4c      GBTCLK1 PMA refclk (UX 4C)
        +-- u_clk_bridge_jesd     312.5 MHz link clock bridge
        +-- u_spi_master          Avalon-MM SPI Master (24-bit, 2 CS, 25 MHz)
        +-- u_tx_en_pio           2-bit output PIO  -> FMC_TXEN[1:0]
        +-- u_pe_ctrl_pio         1-bit output PIO  -> FMC_PE_CTRL
        +-- u_spi_en_pio          1-bit output PIO  -> FMC_SPI_EN
        +-- u_pg_c2m_pio          1-bit output PIO  -> internal loopback only
        +-- u_dac_status_pio      32-bit input PIO  <- presence/PG/JESD status
        +-- u_reset_bridge_*      one per clock domain that crosses LWH2F
```

The `u_dac_subsys` instance is built by the Tcl program at
[ip/dac_subsys/dac_subsys.tcl](../ip/dac_subsys/dac_subsys.tcl). The Phase
A IP is wrapped at
[ip/dac_controller_0/dac_controller_0_hw.tcl](../ip/dac_controller_0/dac_controller_0_hw.tcl).

### Known structural gaps (ISSUE-019, ISSUE-020)

`u_jesd_link0` and `u_jesd_link1` are missing a `intel_gts_reset_sequencer`
driver for their Control Unit Clock + request/grant ports. The fitter
completes regardless, but the Agilex 5 GTS Reset Sequencer User Guide
mandates this IP for every shoreline-tile transceiver instance.
Procedure 5.A will probably fail without it; the fix is small and
contained (see [potential_issues.md ISSUE-019](potential_issues.md)).

Separately, the controller's `frame_ready` link-status feedback was wired to
`u_jesd_stub` (constant `'0'`), not to the real GTS IPs — so the transport
never released data and the FPGA sync status was dead, independent of the
reset sequencer. An interim fix (stub `frame_ready <= '1'`, so the transport
free-runs and the GTS link layer gates the wire) is applied; the permanent fix
wires real GTS link status back to the controller. See
[potential_issues.md ISSUE-020](potential_issues.md) and the full
[design_review_phaseB.md](design_review_phaseB.md).

---

## 3. Clocking

| Net | Frequency | Source | Consumers |
|-----|-----------|--------|-----------|
| `pll_refclk_100` | 100 MHz | dev-kit oscillator on `PIN_BK109` | `u_shell_subsys.u_sys_pll` only |
| `system_clock` | 100 MHz | `u_sys_pll.outclk[0]` | Fabric / Avalon-MM control plane; drives `dac_controller_0.clock_sink_clk`, all CSRs, all PIOs, `u_spi_master`. |
| `fmc_gbtclk0` | 312.5 MHz | FMC `D4/D5` -> `AP16/AP21` (UX 4B) | `u_jesd_link0` PMA refclk via `u_xcvr_refclk`. ×40 PLL = 12.5 Gbps lane rate. |
| `fmc_gbtclk1` | 312.5 MHz | FMC `B20/B21` -> `AV16/AV21` (UX 4C) | `u_jesd_link1` PMA refclk via `u_xcvr_refclk_4c`. Required because Agilex 5 GTS cannot route a refclk across transceiver tiles (ISSUE-015). |
| `jesd_link_clk` | 312.5 MHz | `u_jesd_link0.txphy_clk[0]` looped at top SV (see line 270 of `agilex5_devkit.sv`) | Drives both `u_jesd_link0.txlink_clk` and `u_jesd_link1.txlink_clk`; drives `u_clk_bridge_jesd`; clocks `u_sysref_capture` 2-stage synchronizer. |
| `fmc_sysref` | low-rate, divides DEV_CLK | FMC `G6/G7 (LA00_CC)` -> `A45/B42` | Sampled to `jesd_link_clk` in `u_sysref_capture`, fed to both `u_jesd_link*.sysref` inputs as `sysref_captured`. |
| HPS EMIF clocks | 1066.667 MHz (DDR4-3200, production baseline) | EMIF refclk pad | HPS only; not visible to fabric clock tree. |
| `altera_int_osc_clk` | ~125 MHz | internal oscillator | Reset sequencer + SLD JTAG hub fabric. |

### Asynchronous clock groups

[projects/agilex5_devkit/sdc/jesd_cdc.sdc](../projects/agilex5_devkit/sdc/jesd_cdc.sdc)
declares `jesd_link_clk` as a separate clock group from `system_clock`,
so the Quartus STA does not chase setup paths across the CDC boundary.
All multi-bit transfers between the two domains route through Phase A's
`DcFifo` or through 2-stage synchronizers (single-bit) per Phase A's
CDC rules (preserved in [phase_a_design_description.md](phase_a_design_description.md)).

---

## 4. Reset architecture

Two cascaded gates:

1. **System reset (`fpga_reset_n`)** -- inherited from baseline GSRD;
   `u_shell_subsys.u_clks_and_rsts` produces synchronous, async-deasserted
   per-domain resets.

2. **FMC presence / power-good gate (`fmc_ready`)** -- produced by
   [src/fmc_handshake.sv](../projects/agilex5_devkit/src/fmc_handshake.sv).
   Inputs: synchronized `fmc_prsnt_n` (from the FMC connector's
   `H2 PRSNT_M2C_L` pin via FPGA `K8`) and `fmc_pg_m2c` (currently tied to
   `1'b1` in the top because the on-board MAX10 handles the PG handshake
   autonomously -- see CLAUDE.md s2 and ISSUE-012). Output asserts after
   `~prsnt_n` is stable for >= 32 cycles. Reads back to HPS as bit 5 of
   `u_dac_status_pio` (verified in `dac_subsys_tb.sv` T1).

The JESD GTS reset is the AND of the two:

```systemverilog
wire jesd_reset_n_gated  = fpga_reset_n & fmc_ready_internal;
wire jesd_reset_active_h = ~jesd_reset_n_gated;
```

Both are exported into `u_dac_subsys` -- `dac_jesd_reset_n_reset_n`
(active-low) and `dac_jesd_reset_reset` (active-high companion for the
reset bridge crossing into the `u_clk_bridge_jesd` domain).

The HPS warm-reset case is handled by a reset bridge on the LWH2F slave
inside `u_dac_subsys` (CLAUDE.md s6 #7); in-flight AXI bursts terminate
cleanly when the HPS resets.

---

## 5. Address map (HPS view, LWS2F window at 0x0200_0000)

| Slave | Base | Size | Contents |
|-------|------|------|----------|
| `u_dac_controller_0.lwhpm2fpga` | `0x0200_0000` | 1 KB | Phase A reg_bank: NCO ctrl, JESD sync ctrl, sine_wave_gen, status |
| `u_spi_master.s1` | `0x0200_1000` | 64 B | Altera Avalon SPI Master CSR (byte offsets: rxdata 0x00, txdata 0x04, status 0x08, control 0x0C, slaveselect 0x14) |
| `u_tx_en_pio.s1` | `0x0200_1100` | 16 B | TXEN[1:0] output |
| `u_pe_ctrl_pio.s1` | `0x0200_1110` | 16 B | PE_CTRL output |
| `u_dac_status_pio.s1` | `0x0200_1120` | 16 B | 32-bit input: `[0]=~prsnt_n`, `[2]=pg_c2m loopback`, `[5]=fmc_ready`, `[31:6]=JESD status (future)` |
| `u_spi_en_pio.s1` | `0x0200_1130` | 16 B | FMC SPI level-shifter enable |
| `u_pg_c2m_pio.s1` | `0x0200_1140` | 16 B | Internal-only PG_C2M (dangling externally; see ISSUE-012) |
| `u_jesd_link0.csr` | `0x0200_2000` | 4 KB | JESD204B GTS link 0 CSR window |
| `u_jesd_link1.csr` | `0x0200_3000` | 4 KB | JESD204B GTS link 1 CSR window |
| _(reserved)_ | `0x0200_4000`+ | | Future use, e.g. GTS Reset Sequencer (ISSUE-019 fix) |

Source of truth for software is
[software/ad9176_config/dac_subsys_regs.h](../software/ad9176_config/dac_subsys_regs.h).
The Phase A `iq_router_regs.h` is stale and **must not be used** -- see
ISSUE-017.

---

## 6. JESD204B mode-4 parameters (one entry, two links)

| Parameter | Value | Defined in |
|-----------|-------|-----------|
| Mode | 4 | AD9176 datasheet (mode table) |
| Subclass | 1 (with subclass-0 fallback via runtime CSR) | Source-sync SYSREF on the AD9176-FMC-EBZ |
| L (lanes per link) | 4 | `dac_controller_pkg.vhd`, GTS IP `L`/`L_2` |
| M (converters per link) | 4 | `dac_controller_pkg.vhd` |
| F (octets per frame) | 2 | same |
| S (samples per converter per frame) | 1 | same |
| N (resolution) | 16 | same |
| NP (word size) | 16 | same |
| K (frames per multiframe) | 32 | same |
| HD (high density) | 1 | same |
| SCR (scrambling) | 1 | same |
| CF (control words / frame) | 0 | same |
| CS (control bits) | 0 | same |
| Lane rate | 12.5 Gbps | GTS IP `lane_rate` / `lane_rate_2` |
| Refclk (per tile) | 312.5 MHz | x40 PMA PLL on 12.5 Gbps |
| Link clock | 312.5 MHz | `txphy_clk[0]` from `u_jesd_link0` |
| Per-converter sample rate Fs | 625 MSPS | (lane_rate x L) / (M x NP) -> 12.5e9 * 4 / (4 * 16) = 781.25 MHz transport, derated by 8b/10b = 625 MSPS |
| Post-interp DAC rate | 2.5 GSPS | 625 MSPS x 4 (AD9176 4x interp on this datapath) |
| Number of links | 2 | one per AD9176 DAC core |
| Total lanes wired | 8 | UX 4B (links 0..3) + UX 4C (links 4..7) |
| LMFC period | 16 link clocks | K x F / (L x 4 / M) = 32 x 2 / (4 x 4 / 4) |

The 12.5 Gbps lane rate at M=4 / L=4 / NP=16 gives Fs = 625 MSPS per
converter, well within the AD9176's 12.6 GSPS max DAC rate; this is the
Stage 5 (merged) configuration the GTS IP is parameterized for.

---

## 7. Linux user-space integration

[software/ad9176_config/](../software/ad9176_config/) provides the
deployable bring-up tool. Architecture:

```
ad9176_config (main, software/ad9176_config/ad9176_config.c)
|
+-- subcommands: status | bringup | tone | peek | poke
|
+-- ad9176_fmc_ebz.[ch]        /dev/mem mmap + 24-bit fabric SPI driver
|   |                          (drives u_spi_master at 0x0200_1000)
|   +-- spi_write24(addr, data)
|   +-- spi_read24(addr) -> data
|   +-- pio_status_read()      -> dac_subsys_regs.h DAC_STATUS_*
|   +-- pio_txen / pio_pe_ctrl / pio_spi_en  writers
|
+-- ad9176_init.[ch]            AD9176 register sequence (Table 50)
|   +-- ad9176_wait_fmc_ready() polls DAC_STATUS_FMC_READY_BIT (=5)
|   +-- ad9176_bringup()         clock chain + PLL + JESD link param
|                                writes per AD9176 datasheet
|
+-- dac_subsys_regs.h          single source of truth: LWS2F register
                                map authored against
                                dac_controller_pkg.vhd
```

The Yocto recipe scaffolding is at
[software/yocto_linux/meta-custom/recipes-apps/ad9176-config/](../software/yocto_linux/meta-custom/recipes-apps/ad9176-config/);
the recipe is not invoked from the firmware workstation, see
[deferred_hw_gates.md](deferred_hw_gates.md) Stage 7 entry.

---

## 8. Dataflow at run-time

Once `ad9176-config bringup` succeeds:

```
                 +-----------+    +-----------------+    +-----+
HPS user-space --|LWS2F /    |--->|u_dac_controller |--->|     |
ad9176-config    |LWH2F      |    |  _0.reg_bank    |    |     |
                 |(0x0200_0..|<---|                 |<---|     |
                 |  0x0203_F)|    +-------+---------+    |     |
                 |           |            |              |     |
                 |           |            v (axi_csr)    |     |
                 |           |    +-------+---------+    |     |
                 |           |--->| u_spi_master    |--->| FMC | -> AD9176 SPI
                 |           |    | (24-bit Avalon) |    | Mez-|
                 |           |    +-----------------+    |zanin|
                 |           |                           | e   |
                 |           |--->| u_*_pio (PIOs)  |--->|     | -> TXEN/PE/EN
                 |           |    +-----------------+    |     |
                 |           |    +-----------------+    |     |
                 |           |<---| u_dac_status_pio|<---|     | <- PRSNT_N
                 +-----------+    +-----------------+    +-----+
                                                          ^   |
                                                          |   | 312.5 MHz
                          NCO output samples (M=4, NP=16) |   | GBTCLK0/1
                                                          |   v
                 +-----------+    +-----------------+    +-----+
                 |dac_       |--->|u_dac_controller |--->|u_je-|
                 |controller_|    | _0.sine_wave_gen|    |sd_  |--> SERDIN0..7
                 |0 NCO loop |    | + jesd transport|    |link0|    @ 12.5 Gbps
                 |@ 100 MHz  |    | + DcFifo CDC    |    |/1   |
                 |sys_clk    |    | @ 312.5 MHz     |    +-----+
                 +-----------+    | jesd_link_clk   |       ^
                                  +-----------------+       |
                                                            +-- SYSREF (LA00_CC)
                                                                via u_sysref_capture
```

The control plane is at 100 MHz; the JESD transport is at 312.5 MHz;
the DcFifo at the boundary is the only multi-bit CDC. Single-bit
control signals between the two domains use 2-stage synchronizers per
the Phase A CDC rules (e.g. `jesd_sync_controller` toggle synchronizer
for the sync release pulse).

---

## 9. Verification entry points

| Scope | Entry-point | Status |
|-------|-------------|--------|
| Phase A block testbenches (VHDL) | `tb/run_block_tbs.tcl` -> 8 TBs under Questa | Stage 8a PASS (Procedure 8.A) |
| dac_subsys integration TB (SV) | [projects/agilex5_devkit/sim/dac_subsys_tb.sv](../projects/agilex5_devkit/sim/dac_subsys_tb.sv) via `run_dac_subsys_tb.do` | Stage 8b PASS (Procedure 8.C); 6/6 sub-tests |
| JESD link-layer simulation | hand-rolled JESD RX BFM (TBD) | Stage 8c deferred (covered by hardware) |
| Synthesis / elaborate | `quartus_syn --analysis_and_elaboration agilex5_devkit` | Stage 9 PASS (0 errors; 1 IP-eval warning -> ISSUE-016; 3 DRC criticals -> ISSUE-019) |
| Fit + STA | `quartus_sh -t projects/agilex5_devkit/build.tcl` | Stage 5 PASS (8% ALM, 17% M20K, 33% GTS, WNS = 1.806 ns on system PLL) |
| System Console JESD bring-up | TCL via NiosV JTAG-Avalon master | Procedure 5.A (hardware) |
| Linux end-to-end | `ad9176-config bringup` on Yocto SD card | Procedure 7.A (hardware) |

---

## 10. Cross-references

- [CLAUDE.md](../CLAUDE.md) -- project rules, critical constraints, build commands
- [PLAN.md](../PLAN.md) -- stage-by-stage implementation script
- [doc/jesd_bringup_sequence.md](jesd_bringup_sequence.md) -- AD9176 SPI sequence + Linux flow
- [doc/fmc_pinout_crossref.md](fmc_pinout_crossref.md) -- FMC <-> AD9176 <-> FPGA pin map
- [doc/integration.md](integration.md) -- hardware-deferred procedures
- [doc/deferred_hw_gates.md](deferred_hw_gates.md) -- ledger of deferred verifies
- [doc/potential_issues.md](potential_issues.md) -- open + closed issues
- [doc/phase_a_design_description.md](phase_a_design_description.md) -- inherited Phase A CLAUDE.md + design notes
