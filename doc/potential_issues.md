# Potential Issues Log

Track design concerns that may surface during integration or hardware bring-up.

---

## ISSUE-001: RegBank Avalon-MM Read Path is Purely Combinational

**Date:** 2026-03-15
**Module:** `reg_bank.vhd`
**Status:** Open — monitor during integration

**Description:**
The `avmm_readdata` output is driven combinationally (no registered output stage). The read data mux (`p_read`) produces valid data in the same cycle that `avmm_read` is asserted. This is valid for Avalon-MM waitrequest-mode slaves with fixed 0-cycle read latency, but introduces two risks:

1. **HPS bridge compatibility:** If the `controller_subsystem_hps` Avalon-MM master expects a `readdatavalid` handshake (variable-latency read), the current design will not work. Need to confirm the HPS lightweight bridge is configured for waitrequest-mode with combinational readdata.

2. **Timing closure:** The combinational path from `avmm_address` through the read mux to `avmm_readdata` may become the critical path as more registers are added. At 200 MHz (`axi_lite_clk`), this is ~5 ns. The case statement fans out across all register blocks and the SPI mapped window mux adds another level. If timing fails, the fix is to register the read output and add 1 cycle of read latency (update `avmm_waitrequest` to hold for 1 cycle on reads).

**Action items:**
- [ ] Check Quartus Platform Designer settings for lwhps2fpga bridge read latency mode
- [ ] After synthesis (Step 8), check timing report for `avmm_readdata` path slack
- [ ] If registered read is needed: add `readdatavalid` port, register `read_data`, assert `readdatavalid` one cycle after `avmm_read` when `wait_req = '0'`

---

## ISSUE-002: SpiBridge Removed (FPGA SPI deprecated)

**Date:** 2026-04-07
**Module:** ~~`spi_bridge.vhd`~~ (removed)
**Status:** Closed — files deleted

**Description:**
`spi_bridge.vhd` and `spi_bridge_tb.vhd` have been removed from the project. AD9176 SPI
configuration is handled entirely by HPS software (`src/hps/ad9176_fmc_ebz.c`). The
previous issues (concurrent-access priority and lack of streaming mode) are moot.

---

## ISSUE-003: SpiBridge Removed — see ISSUE-002

**Date:** 2026-04-07
**Status:** Closed — see ISSUE-002

---

## ISSUE-004: JesdSyncController LMFC Boundary Coincidence Timing

**Date:** 2026-03-16
**Module:** `jesd_sync_controller.vhd`
**Status:** Documented — verified by TB-SYNC-004

**Description:**
When all required links in a sync group become ready on the exact same clock edge that the LMFC boundary counter fires, the FSM transitions `ST_WAIT_LOCK → ST_WAIT_LMFC` on that edge. Since the FSM does not check `lmfc_bound` in the `ST_WAIT_LOCK` state, it must wait until the following clock to evaluate `lmfc_bound` in `ST_WAIT_LMFC`.

Due to registered timing, `lmfc_bound = '1'` persists for exactly one clock. When the FSM enters `ST_WAIT_LMFC` on the same edge that `lmfc_bound` transitions to `'1'`, the `'1'` is still the current value on the next edge, so the FSM successfully transitions to `ST_RUNNING`. No LMFC period is lost in this true-coincidence case.

However, if links become ready **one clock after** the LMFC boundary (the `lmfc_bound = '1'` edge has already passed), the FSM enters `ST_WAIT_LMFC` when `lmfc_bound` has already returned to `'0'` and must wait a full LMFC period (`C_LMFC_PERIOD = 16` link clocks = 64 ns at 250 MHz) for the next boundary.

**Worst-case release latency:** `C_LMFC_PERIOD` link clocks after all links are ready. This is by design — LMFC-aligned release is a JESD204B requirement — but hardware bring-up teams should be aware that release timing varies by up to one full LMFC period depending on when links report ready relative to the LMFC counter.

**Verified in simulation:** TB-SYNC-004 tests the "1 clock after LMFC" case and confirms the FSM correctly waits for the next boundary rather than releasing early.

---

## ISSUE-005: JesdSyncController — Transient Link Glitch Recovery (Fixed)

**Date:** 2026-03-16
**Module:** `jesd_sync_controller.vhd`
**Status:** Fixed

**Description:**
The original `ST_ERROR` state had a conditional exit: it only transitioned back to `ST_WAIT_LOCK` when `grp_all_ready = '0'`. If a link dropped for only one clock and immediately recovered, the FSM would enter `ST_ERROR` but find `grp_all_ready = '1'` on the very next edge, permanently deadlocking in `ST_ERROR` with no exit path.

**Fix applied:** Changed `ST_ERROR` to unconditionally transition to `ST_WAIT_LOCK` (single-clock transient state). The error flag is still set by the sticky error logic in `p_err`, preserving observability. The FSM then follows the normal `ST_WAIT_LOCK → ST_WAIT_LMFC → ST_RUNNING` recovery path.

**Trade-off:** A single-clock glitch now causes a brief data release drop (~16 clocks worst case for LMFC re-alignment) rather than a permanent hang. This is preferable — transient glitches on `txlink_ready` could occur during JESD link training or due to brief signal integrity events on the serial lanes.

**Verified in simulation:** TB-SYNC-005 tests a 1-clock glitch on link 0 and confirms error flag assertion, automatic recovery, and successful re-sync on the next LMFC boundary.

---

## ISSUE-006: Platform Designer Component Ports for `dac_controller_0`

**Date:** 2026-04-07
**Module:** `dac_controller_0.vhd` (replaces deleted `iq_router.vhd`)
**Status:** Open — required before synthesis

**Description:**
`dac_controller_0` is the new top-level entity replacing `iq_router`. The Platform Designer
component definition must be updated to export the full port list of `dac_controller_0`,
including both JESD links and the lwhpm2fpga AXI4 bus. SPI ports have been removed (HPS
software handles SPI directly).

**Action items:**
- [ ] Update Platform Designer component to match `dac_controller_0` port list
- [ ] Connect `jesd204_tx_link_clk_clk` to JESD204B GTS IP link clock output
- [ ] Connect both JESD TX streaming ports (`_jesd204_tx_link_*` and `_p1_jesd204_tx_link_*`)
- [ ] Verify `lwhpm2fpga_*` AXI4 port widths match the HPS bridge configuration
- [ ] Regenerate the component and confirm port names match RTL exactly

---

## ISSUE-007: AXI4 Full vs. AXI4-Lite Bridge

**Date:** 2026-04-07
**Module:** `axi_to_avmm.vhd`, `dac_controller_0.vhd`
**Status:** Open — monitor during integration

**Description:**
The HPS `lwhpm2fpga` bridge exports AXI4 (with burst, ID, and lock fields). `AxiToAvmm`
accepts AXI4 but only forwards the first beat of any burst; burst length is acknowledged
but remaining beats are dropped. This matches expected lwhpm2fpga behavior (single-beat
register access), but should be confirmed.

**Risks:**
1. **Write channel timing:** Bridge waits for simultaneous `awvalid` + `wvalid`. If the HPS
   issues them on separate cycles the bridge still works (waits in IDLE), with 1 extra cycle
   latency per write.
2. **No byte-enable passthrough:** `wstrb` is accepted but not forwarded to RegBank. All
   writes are full 32-bit. Correct for register access.
3. **Always-OKAY response:** `bresp` and `rresp` are hardwired to `"00"`. If the HPS expects
   error responses for unmapped addresses, this will not be provided.

**Action items:**
- [ ] Confirm lwhpm2fpga always issues single-beat transactions for register access
- [ ] Confirm HPS AXI master does not require error responses for unmapped addresses

---

## ISSUE-008: Quasi-Static CDC for Sine Wave Gen Configuration

**Date:** 2026-03-18  Updated: 2026-04-07
**Module:** `dac_controller_0.vhd` (`p_cdc_sine` process)
**Status:** Open — software-enforced constraint (hardware interlock deferred)

**Description:**
The `t_sine_csr` record crosses from `clock_sink_clk` (~100–200 MHz) to `txlink_clk`
(~250 MHz) using a quasi-static CDC pattern. Multi-bit values (frequency words, phase
offsets, amplitudes) are sampled in the `txlink_clk` domain only while the 2-stage
synchronized `enable` is `'0'`.

**Safety assumption:** HPS software must write all configuration registers **before**
asserting `SINE_CTRL[0]`. The `enable` synchronizer adds ≥2 `txlink_clk` cycles of delay,
during which the multi-bit values must be stable. This is the standard "quasi-static with
synchronized qualifier" CDC pattern.

**Violation conditions:**
- Modifying frequency/phase/amplitude registers while `enable = '1'` is unsafe; values
  may be corrupted on the `txlink_clk` side.
- The HPS driver must enforce the write-before-enable discipline. A hardware interlock
  (RegBank ignoring config writes while enable is set) has been evaluated and deferred to
  software policy.

**Action items:**
- [ ] Document the write-before-enable requirement in the HPS driver header
- [ ] Consider adding a hardware interlock in a future revision if software discipline
      cannot be guaranteed (e.g., multi-threaded access)

---

## ISSUE-009: `lmfc_aligned` Always Reads '0' with Single AD9176

**Date:** 2026-04-07
**Module:** `dac_controller_0.vhd`, `jesd_sync_controller.vhd`
**Status:** Open — by design, document for HPS software

**Description:**
`JesdSyncController.lmfc_aligned` is only `'1'` when both `grp0_state = ST_RUNNING` AND
`grp1_state = ST_RUNNING`. With a single AD9176 (links 0 and 1 active, links 2 and 3
permanently tied to `'0'`), group 1 can never reach `ST_RUNNING`. As a result,
`lmfc_aligned` (bit 6 of `JESD_SYNC_STATUS`) will permanently read `'0'` regardless of
whether data is flowing correctly.

HPS software must use `group_synced[0]` (bit 4 of `JESD_SYNC_STATUS`) rather than
`lmfc_aligned` to determine whether the active JESD links are ready.

**Action items:**
- [ ] Document in HPS driver: poll `group_synced[0]` for single-AD9176 bring-up, not
      `lmfc_aligned`
- [ ] Consider adding a `C_NUM_ACTIVE_GROUPS` generic to `JesdSyncController` in a future
      revision to suppress the inactive group from the `lmfc_aligned` computation

---

## ISSUE-010: `sync_err` Clear/Set Race in Same Clock Cycle

**Date:** 2026-04-07
**Module:** `jesd_sync_controller.vhd` (`p_err` process)
**Status:** Open — document only, no RTL change needed

**Description:**
In `p_err`, the clear assignment (`sync_err_r(i) <= '0'`) occurs before the set assignment
(`sync_err_r(i) <= '1'`) in the same process. In VHDL, the last assignment to a signal
variable wins. If `err_clr(i)` and an active link fault are both true in the same clock
cycle, the error set takes priority and the clear is silently discarded.

This means software cannot clear a `sync_err` bit while the underlying link fault is still
active — which is the correct behavior. The interaction is not a bug, but it is not
documented in the source and is not covered by any testbench.

**Action items:**
- [ ] Add a comment to `p_err` explaining the last-assignment priority
- [ ] Add a TB-SYNC test case: assert `err_clr` while the corresponding link is still down,
      verify the flag remains set

---

## ISSUE-011: ES-silicon HPS EMIF retargeted to DDR4-1600 @ 800 MHz; DBI removed

**Date:** 2026-05-15
**Module:** `projects/agilex5_devkit/ip/hps_subsys/emif_io96b_hps.ip` and
parent qsys plumbing (`hps_subsys.qsys`, `baseline_top.qsys`, `agilex5_devkit.sv`,
`agilex5_devkit.qsf`)
**Status:** Open — Phase B Stage 1 workaround, requires re-evaluation when ES
silicon supports DDR4-3200

**Description:**
The upstream 065B baseline-a55 GHRD targets the production part
`A5ED065BB32AE4S` (speed grade 4) with HPS DDR4 configured at
**1066.667 MHz** (DDR4-3200AA). Retargeting to the dev kit's ES silicon
`A5ED065BB32AE6SR0` (speed grade 6, SR0 stepping) triggers
`Error: emif_io96b_hps.emif_io96b_hps_inst: emif_0_ddr4comp:
"Memory Operating Frequency" (MEM_OPERATING_FREQ_MHZ) "1066.667" is out of
range: "666.667" "800"` during ipgenerate. ES silicon HPS EMIF supports a
maximum of 800 MHz (DDR4-1600).

**Resolution applied (2026-05-15):**
Replaced the production-stepping IP with the ES-silicon variant from
`agilex5e-ed-gsrd-main/a5ed065es-premium-devkit-debug2/legacy-baseline/ip/hps_subsys/emif_io96b_hps.ip`:

| Parameter                | Production 065B (was) | ES SR0 (now) |
| ------------------------ | --------------------- | ------------ |
| `MEM_OPERATING_FREQ_MHZ` | 1066.667              | 800          |
| DDR4 speed grade         | 3200AA                | 1600L        |
| `MEM_TCK_NS`             | 0.937                 | 1.25         |
| `MEM_TWR_NS`             | 15.0                  | 12.0         |
| `mem_dbi_n` (DBI port)   | exported, 5-bit Bidir | not exported |
| `MAIN_SM7_REVA/B`        | REVB                  | REVA         |

The DBI port removal cascaded into edits to:
- `hps_subsys.qsys` — two `<port name="mem_0_dbi_n">` blocks removed
- `baseline_top.qsys` — one `<port name="emif_hps_emif_mem_0_mem_dbi_n">` block removed
- `agilex5_devkit.sv` — `inout wire [4:0] emif_hps_emif_mem_0_mem_dbi_n`
  port + instantiation `.emif_hps_emif_mem_0_mem_dbi_n(...)` connection removed
- `agilex5_devkit.qsf` — 5 PIN_ + 5 IO_STANDARD assignments for
  `emif_hps_emif_mem_0_mem_dbi_n[0..4]` removed (PIN_B119, AC90, V87, H87, B97
  now unbonded)

**Impact:**
- HPS DDR4 bandwidth drops from ~25.6 GB/s (DDR4-3200, 40-bit data) to
  ~12.8 GB/s (DDR4-1600, 40-bit data). Per CLAUDE.md §2 the
  DAC pipeline is fed via H2F (samples streamed from HPS DRAM) — at
  Phase B's 500 MSPS × 16-bit × 8 lanes = 8 GB/s peak, the lower
  bandwidth still leaves headroom but with less margin than the production
  stepping would.
- DBI is disabled. Slightly higher DDR4 power consumption due to
  worst-case data patterns not inverted. Negligible at 800 MHz.
- 5 FPGA bank-3D pins (PIN_B119, AC90, V87, H87, B97) are now free for
  future use. They are NOT in the FMC area so don't conflict with
  Phase B's DAC subsystem.

**Action items:**
- [ ] When hardware is connected, validate Linux boots cleanly with the
      retargeted DDR4-1600 EMIF.
- [ ] If a future ES silicon stepping (SR1, SR2, ...) raises the EMIF cap,
      reconsider re-promoting to DDR4-3200 and re-enabling DBI.
- [ ] If production silicon ever lands on the dev kit, restore the original
      `emif_io96b_hps.ip` and DBI plumbing.

---

## ISSUE-012: AD9176-FMC-EBZ board-mgmt signals routed to MAX10, not main FPGA

**Date:** 2026-05-17
**Module:** `projects/agilex5_devkit/agilex5_devkit.sv`, `agilex5_devkit.qsf`,
`ip/dac_subsys/dac_subsys.tcl` (u_pg_c2m_pio instance)
**Status:** Closed (Stage 4) — documented in
[memory/project_fmc_max10_handoff.md](../../.claude/projects/d--Firmware-DevBoard-PhaseA/memory/project_fmc_max10_handoff.md)

**Description:**
On the DK-A5E065BB32AES1 dev kit, several FMC management signals defined by
VITA 57.1 are routed to an on-board MAX10 board-management FPGA, **not** to
the main Agilex 5 FPGA. Initial CLAUDE.md §2 architecture (Stage 4 plan)
incorrectly assumed the main FPGA owned these. Confirmed routing:

| Signal      | Main FPGA pin   | Owned by              |
|-------------|-----------------|-----------------------|
| `PRSNT_M2C_L` | PIN_K8        | **main FPGA** (input) |
| `PG_M2C`      | n/a           | board-mgmt MAX10      |
| `PG_C2M`      | n/a           | board-mgmt MAX10      |
| `GA[1:0]`     | n/a           | board pull-ups only   |

**Resolution applied (2026-05-17):**
- Stage 4 SV top exports only `fmc_prsnt_n` (no `fmc_pg_m2c`, `fmc_pg_c2m`,
  `fmc_ga`); qsf carries only `set_location_assignment PIN_K8 -to fmc_prsnt_n`
  for housekeeping.
- `dac_subsys` keeps the `u_pg_c2m_pio` instance internally so HPS can write
  and read back the bit (dac_status_word[2] loopback); the conduit dangles
  inside baseline_top because the FPGA package pin does not exist.
- `dac_status_word[1]` (PG_M2C) and `dac_status_word[4:3]` (GA) are tied
  to 0 in agilex5_devkit.sv with explanatory comments.

**Impact:** None on Stage 4 verification — `PRSNT_N` is sufficient for the
"AD9176 mezzanine present" indication used by the Stage 6 JESD bring-up
handshake. The MAX10 likely handles PG_M2C/PG_C2M autonomously per the FMC
spec; if Stage 5 or later finds firmware needs runtime visibility, the
path is via the MAX10's own interface (SDM or board-mgmt path), not the
FMC connector.

---

## ISSUE-013: Stage 1 baseline retargeting dropped 48 HPS IO48 pin locations

**Date:** 2026-05-17
**Module:** `projects/agilex5_devkit/agilex5_devkit.qsf` (HPS Peripherals block)
**Status:** Closed (Stage 4) — pin locations restored from upstream
`legacy_baseline.qsf`

**Description:**
The upstream Stage 0 GHRD `baseline_a55.qsf` ships with IO_STANDARD,
CURRENT_STRENGTH_NEW, and WEAK_PULL_UP_DN_SEL assignments for the 48 HPS
IO48 peripheral pins (`hps_jtag_*`, `hps_sdmmc_*`, `hps_emac0_*`,
`hps_spim0_*`, `hps_uart0_*`, `hps_i3c1_*`, `hps_trace_*`, `hps_gpio1_*`,
`hps_osc_clk`) but **no** `set_location_assignment` lines for any of them.
Stage 0 retargeting carried this gap into the Phase B repo's
`agilex5_devkit.qsf` unchanged.

Stages 1, 2, and 3 all used `quartus_sh -t build.tcl --project-only`
(IP generation only) as their verify gate, so the fitter never ran on this
project until Stage 4. The first full compile in Stage 4 surfaced the gap
as `Error (171016): Can't place node ... -- illegal location assignment`
and `Error (12677): No exact pin location assignment(s) for 48 pins of
154 total pins` (PROMOTE_WARNING_TO_ERROR 12677 promotes the warning).

**Resolution applied (2026-05-17):**
Recovered all 48 HPS pin locations from
`D:/agilex5e-ed-gsrd-main/a5ed065es-premium-devkit-debug2/legacy-baseline/legacy_baseline.qsf`
(same DK-A5E065BB32AES1 dev kit family, ES SR0 silicon) and inserted them
into `agilex5_devkit.qsf` immediately before the existing `IO_STANDARD`
block under `# HPS IO48 Peripherals`. Full Stage 4 fit then completed
cleanly (WNS +1.731 ns, 0 errors).

**Action items:**
- [x] Restore HPS pin locations (Stage 4 close-out).
- [ ] PLAN.md Stage 1 retro-fix: the verify gate should have included at
      least one full `quartus_sh -t build.tcl` (not just `--project-only`)
      to catch this class of gap before later stages compound it.
- [ ] Confirm upstream `legacy_baseline.qsf` pin locations match the
      `oobe/baseline_a55.qsf` ones on first hardware bring-up — both target
      the same dev kit but if Altera's pinout was ever revised between
      revisions, the legacy snapshot could diverge.


---

## ISSUE-014: GTS JESD204B IP on Agilex 5 ES SR0 silicon (Stage 5 merged)

**Date:** 2026-05-17
**Module:** `ip/dac_subsys/dac_subsys.qsys` (u_jesd_link0, u_jesd_link1)
**Status:** Open — track warnings from first full compile + first hardware
bring-up

**Description:**
Stage 5 (merged) added two `intel_jesd204b_gts` IP instances to
`dac_subsys.qsys` for the AD9176 dual-link JESD204B transport. The IP is
listed in Quartus 26.1 with `SUPPORTED_DEVICE_FAMILIES {{Agilex 5}
{Agilex 3}}` and `SUPPORTED_DIE_TYPES {"MAIN_SM7*" "MAIN_SM5*" "MAIN_SM4*"
"MAIN_FMM3*" "MAIN_FMM2*"}` per
`D:/altera_pro/26.1/ip/altera/jesd204b_gts/src/top/j204b_gts_hw.tcl`
line 35-36. Our target device `A5ED065BB32AE6SR0` falls within the
supported family but ES SR0 stepping support is not explicitly enumerated
in the IP descriptor.

**Watch for:**
- `IP_NOT_PRODUCTION_READY` warnings during quartus_ipgenerate or
  quartus_syn (capture verbatim if seen).
- PMA PLL lock-time anomalies during hardware bring-up.
- Timing closure issues on the 312.5 MHz PMA datapath if ES SR0 has
  slower speed binning than the IP wizard's nominal Fmax assumptions.

**Resolution path:**
- If warnings are benign at fit time, document them here and proceed.
- If hardware lock fails, escalate to Altera support with the dev kit
  ES SR0 stepping reference and a verbose quartus_sta log.

**Action items:**
- [x] First full compile (2026-05-18): 0 errors, 41 warnings; none flag
      `IP_NOT_PRODUCTION_READY` for the GTS JESD204B IP. Timing met with
      WNS = +1.806 ns. 222 synchronizer chains, worst-case MTBF 1e+09 yr.
- [ ] First hardware bring-up: confirm PLL_LOCKED + LANE_READY come up
      stable on both links.

---

## ISSUE-015: Cross-tile transceiver refclk routing (UX 4B GBTCLK0 -> UX 4C SERDIN lanes)

**Date:** 2026-05-17
**Module:** Agilex 5 GTS PMA, FMC SERDIN[4..7] (UX 4C bank) sourced from
GBTCLK0 (UX 4B refclk pad)
**Status:** Closed (Stage 5 merged, 2026-05-18) — resolved by adding GBTCLK1
(UX 4C refclk pad, FPGA AV16/AV21) as a second refclk wired to
u_jesd_link1. The Fitter rejected the single-refclk topology with
`Error (175001): The Fitter cannot place 1 IPFLUXTOP_UXTOP_WRAP, which is
within Generic Component dac_subsys_u_jesd_link1` + `Error (175006): There
is no routing connectivity between the IPFLUXTOP_UXTOP_WRAP and
destination pin` — confirming cross-tile refclk routing is NOT supported
on Agilex 5 GTS. After adding GBTCLK1 the periphery placement succeeded.

**Description:**
The AD9176-FMC-EBZ feeds GBTCLK0 to FMC pin BR40 (FPGA pad AP16/AP21),
which is on the Agilex 5 UX 4B HSST refclk pad. The 8 SERDIN lanes split
across UX 4B (lanes 0..3 + lane 4 on BE7/BE10) and UX 4C (lanes 5..7 on
BC/BA/AW). Whether the Agilex 5 GTS supports cross-tile PMA refclk
routing (UX 4B refclk feeding UX 4C transceiver PLL) is undocumented in
the Quartus 26.1 IP wizard text; in some Intel/Altera transceiver
families this requires a dedicated refclk per tile.

**Watch for:**
- Fitter error: "transceiver reference clock cannot reach instance X" or
  similar at first full compile.
- Quartus 26.1 GTS IP user guide section on multi-tile refclk topology
  (consult before debugging in fitter).

**Resolution path:**
- If cross-tile refclk works: close this issue with a one-line note.
- If it doesn't: add a second refclk input on UX 4C. The FMC also exposes
  `GBTCLK1_M2C` (pins B20/B21); FPGA pad assignment TBD from
  AD9176_Dev_Pinout.txt. Add `fmc_gbtclk1_p/n` SV port + qsf pin
  assignment + a second `u_xcvr_refclk_4c` clock_bridge inside dac_subsys
  + route to `u_jesd_link1.pll_refclk`.

**Action items:**
- [x] First full compile: confirmed cross-tile refclk is NOT supported
      (Error 175001/175006 on u_jesd_link1).
- [x] Dual-refclk path implemented: GBTCLK1 -> FPGA AV16/AV21 (UX 4C),
      `u_xcvr_refclk_4c` clock_bridge added in dac_subsys, fed to
      `u_jesd_link1.pll_refclk`. Periphery placement passes on the second
      full compile (2026-05-18).

---

## ISSUE-016: JESD204B FPGA IP for F-Tile is OpenCore Plus on this workstation

**Date:** 2026-05-18
**Module:** `ip/dac_subsys/dac_subsys.qsys` (u_jesd_link0, u_jesd_link1)
**Status:** Open — license-server issue, not a design issue

**Description:**
First successful full Quartus build (Stage 5 merged) reported the IP
license as `OpenCore Plus` in `output_files/agilex5_devkit.asm.rpt`:

    ; Altera ; JESD204B FPGA IP for F-Tile (6AF7 018D) ; OpenCore Plus ;

Consequence: the Assembler produced `agilex5_devkit_time_limited.sof`
(4.35 MB) instead of `agilex5_devkit.sof`. The time-limited bitstream is
fully functional on hardware but halts after the OpenCore Plus tether
timer expires (~1 hour). Useful for first power-on and bring-up; not
suitable for the eventual deployable artifact.

The mapping "JESD204B FPGA IP for F-Tile (6AF7 018D)" is the license
Quartus 26.1 checks for the **Agilex 5 GTS** flavour of the IP. The
license name `JESD204B FPGA IP for F-Tile` is misleading — it covers
both F-Tile (Agilex 7) and GTS (Agilex 5) variants under one feature
code per the 26.1 license model.

**Watch for:**
- Time-limited bitstream behaviour on hardware: AD9176 SYNC and DAC
  output will stop after ~1 hour. Re-flash to recover.
- Any further IP additions that pull additional unlicensed features
  (Signal Tap is `Licensed`; Nios V/m is `Licensed`).

**Resolution path:**
- Procure a full JESD204B FPGA IP for F-Tile license on the workstation's
  Altera license server (FlexLM feature code per Altera licensing).
- After licensing, the next `quartus_sh -t build.tcl` will produce
  `agilex5_devkit.sof` directly and `build.tcl`'s SOF check will pass
  the strict-name branch (see below).

**Build.tcl accommodation:**
`build.tcl` was updated (2026-05-18) to accept either
`agilex5_devkit.sof` (full license) or `agilex5_devkit_time_limited.sof`
(OpenCore Plus) and report which one was produced. Without this change
the exit code was 1 even on otherwise-clean builds.

**Action items:**
- [ ] License-admin: add JESD204B FPGA IP for F-Tile feature to the
      Altera license server.
- [ ] After license refresh: re-run `quartus_sh -t build.tcl` and
      confirm `agilex5_devkit.sof` is produced and reported.
- [ ] First hardware bring-up: schedule for less than 1 hour of
      continuous-bitstream time, or re-flash periodically.

---

## ISSUE-017: Phase A `iq_router_regs.h` is stale; new `dac_subsys_regs.h` is the source of truth

**Date:** 2026-05-20
**Module:** `software/ad9176_config/` (PLAN.md Stage 7 reg-audit task)
**Status:** Closed -- new header `software/ad9176_config/dac_subsys_regs.h`
authored against `dac_controller_pkg.vhd` constants. The Phase A
reference at `software/ad9176_config/reference/iq_router_regs.h` is
retained for traceability but is NOT used by Phase B code.

**Audit findings (2026-05-20):**

Phase A's `iq_router_regs.h` was authored against the older `IqRouterPkg`
register map, which used a wider address space and merged the SPI master
into the same IP. Phase B's `reg_bank.vhd` uses a 10-bit address space
(1 KB) and the SPI master is a separate IP at LWS2F+0x1000. Concrete
drift:

| Symbol | Phase A iq_router_regs.h | Phase B reg_bank.vhd | Resolution |
|--------|--------------------------|----------------------|------------|
| `REG_JESD_SYNC_CTRL`    | `0x0320` | `0x020` | new header |
| `REG_JESD_SYNC_STATUS`  | `0x0324` | `0x024` | new header |
| `REG_JESD_SYNC_ERR`     | `0x0328` | `0x028` | new header |
| `REG_JESD_TX_SRC_SEL`   | `0x0330` | `0x030` | new header |
| `REG_JESD_TX_SRC_STAT`  | `0x0334` | `0x034` | new header |
| `REG_SINE_CTRL`         | `0x0400` | `0x040` | new header |
| `REG_SINE_FREQ_CH1_I`   | `0x0410` | `0x050` | new header |
| ... (all SINE_*)        | `0x041x`..`0x043x` | `0x05x`..`0x07x` | new header |
| `REG_SPI_CTRL`/`STATUS` | inside iq_router 0x0500 | separate IP at LWS2F+0x1000 | new SPI driver |
| `SPI_MAP_BASE`          | `0x2000`..`0x3FFF` | n/a (Altera Avalon-MM SPI Master used instead) | rewritten |

**Resolution path:**
- New header `software/ad9176_config/dac_subsys_regs.h` matches
  `reg_bank.vhd` exactly (manual cross-check 2026-05-20).
- Phase A `iq_router_regs.h` left in `reference/` directory; not in
  Stage 7 build paths.
- `software/ad9176_config/ad9176_fmc_ebz.c` provides a new SPI
  transport on top of the Altera Avalon-MM SPI Master CSR (24-bit
  full-duplex single-frame transactions).

**Action items:**
- [x] Audit complete; ISSUE closed.
- [ ] On any future `reg_bank.vhd` edit: re-audit `dac_subsys_regs.h`
      against the updated case statement before the next firmware build.

