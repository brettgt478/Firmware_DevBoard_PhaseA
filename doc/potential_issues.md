# Potential Issues Log

Track design concerns that may surface during integration or hardware bring-up.

Open issues are listed first. Resolved issues are condensed in the
**Closed Issues (archived)** section at the bottom -- their `## ISSUE-NNN: ...`
headings are kept verbatim so existing `#issue-NNN-...` anchor links in CLAUDE.md,
PLAN.md, and the other docs keep resolving. Full detail is in git history
(`git log -- doc/potential_issues.md`).

---

## Open Issues

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

**Status note (2026-06-04 review):** the Stage 7 bring-up code already follows the
discipline — `dac_subsys_set_nco_tone()` in `software/ad9176_config/ad9176_init.c`
writes all freq/phase/amp registers before the `REG_SINE_CTRL` enable write. Remaining
work is just the explicit header comment below.

**Action items:**
- [ ] Document the write-before-enable requirement in the HPS driver header
- [ ] Consider adding a hardware interlock in a future revision if software discipline
      cannot be guaranteed (e.g., multi-threaded access)

---

## ISSUE-009: `lmfc_aligned` Always Reads '0' with Single AD9176

**Date:** 2026-04-07  Updated: 2026-06-04
**Module:** `dac_controller_0.vhd`, `jesd_sync_controller.vhd`,
`software/ad9176_config/ad9176_init.c`
**Status:** Open — latent software bug found 2026-06-04; **fix applied 2026-06-05**
in `ad9176_init.c`, but still requires hardware verification (Procedure 5.A) before
the new pass condition is trusted.

**Description:**
`JesdSyncController.lmfc_aligned` is only `'1'` when both `grp0_state = ST_RUNNING` AND
`grp1_state = ST_RUNNING`. With a single AD9176 (links 0 and 1 active, links 2 and 3
permanently tied to `'0'`), group 1 can never reach `ST_RUNNING`. As a result,
`lmfc_aligned` (bit 6 of `JESD_SYNC_STATUS`) will permanently read `'0'` regardless of
whether data is flowing correctly.

HPS software must use `group_synced[0]` (bit 4 of `JESD_SYNC_STATUS`) rather than
`lmfc_aligned` to determine whether the active JESD links are ready.

**Latent bug found 2026-06-04 (review):** `dac_subsys_wait_link_lock()` in
`software/ad9176_config/ad9176_init.c` gates success on
`txrdy == 0x0F && grp == 0x3 && lmfc` — i.e. all four internal links ready, BOTH
groups synced, AND `lmfc_aligned`. Per the analysis above, on the single-AD9176
target none of those three can ever be true (links 2/3 tied low → `txrdy` maxes at
`0x3`, `grp` maxes at `0x1`, `lmfc` is always `0`). The function therefore always
times out → JESD bring-up hangs at the link-lock gate. **Recommended fix:** gate on
the active links/group only, e.g. `(txrdy & 0x3) == 0x3 && (grp & 0x1)`, dropping the
`lmfc` requirement. **Applied 2026-06-05:** `dac_subsys_wait_link_lock()` now gates on
`(txrdy & 0x3) == 0x3 && (grp & 0x1)` and drops the `lmfc` requirement (`lmfc` stays in
the success log for diagnostics). This still carries a false-positive risk if a future
board populates links 2-3 (it would accept a partial lock), so the new pass condition
must be confirmed against the Phase A link mapping and verified on hardware during
Procedure 5.A; widen the masks to 0x0F / 0x03 and restore the `lmfc` check if links 2-3
are ever populated.

**Action items:**
- [x] Fix `dac_subsys_wait_link_lock()` to gate on active links/group, not
      `lmfc_aligned` (applied 2026-06-05; **still verify on hardware**, Procedure 5.A)
- [x] Document the active-links/group rationale at the gate (inline comment in
      `ad9176_init.c` referencing this issue)
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

Note: the documentation action below would edit Phase A RTL, which CLAUDE.md §5 keeps
unchanged at the source level. Treat as a deliberate exception if undertaken, or fold the
note into a Phase B wrapper comment instead.

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
- [x] Rebuild on 26.1 (2026-06-04): 0 errors; Fitter Successful, WNS
      +1.501 ns; assembler clean (time-limited SOF, ISSUE-016).
- [ ] First hardware bring-up: confirm PLL_LOCKED + LANE_READY come up
      stable on both links.

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

## ISSUE-019: JESD204B GTS IPs are missing a GTS Reset Sequencer driver

**Date:** 2026-05-21
**Module:** `ip/dac_subsys/dac_subsys.qsys` (`u_jesd_link0`, `u_jesd_link1`)
**Status:** Open -- hardware-blocker for JESD link bring-up (Procedure
5.A); not a fitter blocker, but the Design Assistant DRC flags it as
Critical and the link almost certainly will not come up without it.
Scope corrected 2026-06-03 after analysing the full target-machine DRC
set (elaborated + synthesized + signoff) -- this is a clock/reset cluster,
not a single IP; see "Corrected scope" below. Two independent SDC
side-findings surfaced by the same DRC set are fixed (see end of entry).

**Description:**
Stage 9 elaborate (`quartus_syn --analysis_and_elaboration`) emits
Critical Warning (21619) from the partitioned-snapshot Design Assistant,
referencing `output_files/agilex5_devkit.drc.partitioned.rpt`. Three
GTS-specific rules fire:

| Rule | Hits | Meaning |
|------|------|---------|
| IPC-40030 | 16 | `src_sss_req[*]` / `src_sss_grant[*]` ports on both `u_jesd_linkN` instances are UNCONNECTED |
| IPC-40028 | 2  | The Control Unit Clock port of each JESD link IP is not driven by a GTS Reset Sequencer |
| IPC-40036 | 1  | There is no single Reset Sequencer covering every protocol IP on the shoreline (UX 4B + UX 4C) |

The fitter still completes (the JESD IP elaborates with its CU clock /
request / grant left floating), the bitstream produces, and timing
closes -- so the gate that catches this is the Design Assistant, not
the fitter. On hardware, without a GTS Reset Sequencer driving these
shoreline-wide control signals, the GTS PMA reset / power-up sequence
is undefined; PLL_LOCKED and LANE_READY behaviour is not guaranteed.

**Root cause:** Stage 5 (merged) added the two `intel_jesd204b_gts`
instances and a refclk PMA but did not add the
`intel_gts_reset_sequencer` IP that the Agilex 5 GTS Reset Sequencer
User Guide mandates for every shoreline-tile transceiver IP. The
[ip/dac_subsys/dac_subsys.tcl](../ip/dac_subsys/dac_subsys.tcl) build
script for Stage 5 wired the JESD IPs' refclk + Avalon-MM CSR ports
directly to the rest of the system, leaving the reset request/grant
ports floating.

**Detection:** Stage 9 elaborate-only run on 2026-05-21 (no source
changes since commit `804b6f1`); the DRC report was already produced
by the Stage 5 fit but was not surfaced until Stage 9 hygiene swept
the reports. Reproduced on Quartus 26.1 on 2026-06-04 (IPC-40028/30/36
= 2/16/1 in the partitioned DRC; FLP-10500 = 3 in the synthesized DRC).

**Workaround in simulation:** none required. Stage 8b
`dac_subsys_tb.sv` does not exercise the JESD link layer, so the
missing reset-sequencer connectivity is invisible to the CSR-plane
regression. Stage 8c (link-layer BFM) would be the simulation gate;
that stage is deferred (see [deferred_hw_gates.md](deferred_hw_gates.md)).

**Downstream cascade (2026-06-03 analysis of the target-machine DRC set):**
the missing sequencer is not just a Critical elaborated-snapshot flag --
it silently corrupts the synthesized and signoff snapshots too. With
`pma_cu_clk` tied to GROUND, the GTS PMA never produces a TX clock:
`phy_tx_clkout2[0]` is reported `stuck at 0` in
`output_files/agilex5_devkit.syn.rpt` (23,663 objects swept). That dead
net is the `txphy_clk[0]` loopback that the top SV feeds back as
`jesd_link_clk`. With its clock constant, `sysref_capture` is optimized
away entirely (syn.rpt "Hierarchies Optimized Away During Sweep"), which
strands `fmc_sysref`/`fmc_sync0`/`fmc_sync1` as non-driving inputs
(synthesized DRC **FLP-10500**), and their `fmc_io.sdc` false-path
exceptions then target empty collections (signoff DRC **TMC-20025 x3 /
TMC-20026 x3**). All of these self-heal once the sequencer makes the
JESD datapath real -- they are symptoms, not independent bugs.

**Corrected scope (the earlier "one IP + 3 connections" estimate was
wrong).** The authoritative reference is Altera's own example-design
generator for this exact IP:
`<quartus>/ip/altera/jesd204b_gts/ed/ds/ds_jesd_subsystem_qsys.tcl.terp`.
A GTS JESD shoreline needs a clock/reset *cluster*, not a single IP:

  - `intel_srcss_gts` (the GTS source clock/reset sequencer) -- provides
    `pma_cu_clk` and the `src_rs_req`/`src_rs_grant` handshake to each
    `intel_jesd204b_gts`. Parameters `NUM_LANES_SHORELINE` and
    `NUM_BANKS_SHORELINE` must match the *physical* TX lane/bank
    placement (8 lanes across UX 4B + UX 4C; confirm bank count from the
    fitter). This clears IPC-40028 + IPC-40030.
  - `altera_reset_sequencer` x1+ (`ENABLE_CSR=1`) -- the Avalon-MM reset
    sequencer that clears IPC-40036. Its `*_dsrt_qual` qualification
    inputs must be wired to the JESD IP status (`pll_locked`,
    `tx_rst_ack_n`, `out_of_reset`) -- which in the example design is done
    with a small amount of top-level SV glue (registers
    `core_pll_locked_reg`, `tx_rst_ack`, `tx_out_of_reset`).
  - PMA clocking mode is in use (`clocking_mode=PMA`), so the
    `intel_systemclk_gts` / `altera_iopll` instances that the example adds
    only under `clocking_mode=syspll` are NOT required here -- verify.

  Confirmed JESD IP signal names available for the wiring (from the
  generated `ip/dac_subsys/dac_subsys.qsys`): `pma_cu_clk`, `src_rs_req`,
  `src_rs_grant`, `i_src_rs_priority`, `tx_rst_ack_n`, `pll_locked`,
  `out_of_reset`. The Platform Designer *interface* names (e.g.
  `src_o_pma_cu_clk`, `src_i_src_rs_req`, `src_o_src_rs_grant`) are as
  emitted by the ds_group wrapper in the reference script above.

**Implementation procedure (must run on the build machine -- needs
`qsys-generate` + fit + DRC to validate; cannot be done blind):**

1. Mirror the `inst_src` / `reset_seq*` instantiation + connection block
   from `ds_jesd_subsystem_qsys.tcl.terp` into
   [ip/dac_subsys/dac_subsys.tcl](../ip/dac_subsys/dac_subsys.tcl),
   adapted for TX-only, dual-link, shared txlink_clk, PMA clocking.
2. Add the reset-qualification glue to
   [projects/agilex5_devkit/agilex5_devkit.sv](../projects/agilex5_devkit/agilex5_devkit.sv)
   (or a small VHDL helper) per the example top.
3. Give the reset-sequencer CSR a base at `0x0200_4000` (adjacent to the
   JESD CSR windows); update
   [software/ad9176_config/dac_subsys_regs.h](../software/ad9176_config/dac_subsys_regs.h)
   and the CLAUDE.md address map in the same commit. (Do NOT add the
   address-map entry before the IP exists -- a CSR window pointing at no
   slave is its own DRC hit.)
4. After it elaborates: re-confirm the `jesd_cdc.sdc` clock-group names
   (the txphy_clk loopback only becomes a real clock at this point) with
   `report_clocks` / `report_clock_groups`.
5. Re-run `quartus_sh -t build.tcl` and verify in
   `agilex5_devkit.drc.partitioned.rpt`: IPC-40028/30/36 = 0; and in the
   synthesized/signoff DRC: FLP-10500 = 0 and the sysref/sync TMC-20025/
   20026 entries are gone.

**Hardware-blocker assessment:** the link will not come up during
Procedure 5.A without this fix. The exact behaviour is PLL/PCS-stack
dependent; the AD9176 side will not see ILAS, SYNC stays asserted from
the FPGA side, and `jesd_sync_status` reads all zeros.

**Related fixes already applied (2026-06-03, committed `f8d7aa5`,
independent of the sequencer; validated on the 26.1 build 2026-06-04):**

- [projects/agilex5_devkit/sdc/fmc_io.sdc](../projects/agilex5_devkit/sdc/fmc_io.sdc):
  added `set_false_path -from [get_ports fmc_prsnt_n]` -- clears the only
  **High** signoff finding, TMC-20011 (Missing Input Delay): confirmed 0
  on the 26.1 build. Independent of ISSUE-019.
- [projects/agilex5_devkit/sdc/jesd_cdc.sdc](../projects/agilex5_devkit/sdc/jesd_cdc.sdc):
  replaced the `*u_clk_bridge_axi*` / `*u_clk_bridge_jesd*` clock-group
  filters (which matched zero clocks -- a clock bridge does not create a
  named clock) with the real clock names: fabric `...|u_sys_pll|
  iopll_0_outclk0`, `fmc_gbtclk0/1`, and `*u_dac_subsys|u_jesd_link0/1*`.
  This applies the JESD<->AXI async grouping required by CLAUDE.md s6 #8
  and cleared the STA 332174/332049 clock-bridge warnings + the matching
  TMC-20025/20026 lines (TMC-20026 went 5->3, TMC-20025 6->5). On the
  26.1 build the new grouping is currently flagged "fully overridden"
  (the GTS IP's own SDC already covers those paths) -- benign; re-confirm
  the group members are non-empty after step 4 above, once the txphy_clk
  loopback is a real clock.

---

## Closed Issues (archived)

Resolved issues are condensed here; the `## ISSUE-NNN: ...` headings are kept
verbatim so existing `#issue-NNN-...` anchor links in CLAUDE.md, PLAN.md, and
the other docs still resolve. Full detail is in git history
(`git log -- doc/potential_issues.md`). (ISSUE-002, ISSUE-003, and ISSUE-018
were closed and unreferenced, so they were dropped entirely; see git history.)

## ISSUE-005: JesdSyncController — Transient Link Glitch Recovery (Fixed)

**Closed (Fixed, 2026-03-16).** `ST_ERROR` was changed to an unconditional
single-clock transition to `ST_WAIT_LOCK`, so a 1-clock glitch on `txlink_ready`
can no longer deadlock the FSM; the sticky error flag (`p_err`) is preserved for
observability. Verified by TB-SYNC-005.

## ISSUE-006: Platform Designer Component Ports for `dac_controller_0`

**Closed (2026-06-04).** `ip/dac_controller_0/dac_controller_0_hw.tcl` exports the
full `dac_controller_0` port list (JESD `jesd_link0/1_data` streaming, `lwhpm2fpga`
AXI4, `jesd_tx_link_clk`, and all status/conduit ports). Confirmed by a clean
synth/fit/asm of the full design on Quartus 26.1.

## ISSUE-012: AD9176-FMC-EBZ board-mgmt signals routed to MAX10, not main FPGA

**Closed (Stage 4, 2026-05-17).** On the DK-A5E065BB32AES1, PG_M2C / PG_C2M / GA are
owned by the on-board MAX10 board-management FPGA, not the main Agilex; only
`PRSNT_M2C_L` (PIN_K8) reaches the main FPGA. The SV top exports just `fmc_prsnt_n`;
`u_pg_c2m_pio` is kept internally as an HPS-readable loopback (`dac_status_word[2]`),
and PG_M2C / GA bits are tied to 0. See also
[memory/project_fmc_max10_handoff.md](../../.claude/projects/d--Firmware-DevBoard-PhaseA/memory/project_fmc_max10_handoff.md).

## ISSUE-013: Stage 1 baseline retargeting dropped 48 HPS IO48 pin locations

**Closed (Stage 4, 2026-05-17).** The upstream `baseline_a55.qsf` shipped IO_STANDARD /
drive / pull-up assignments for the 48 HPS IO48 peripheral pins but no
`set_location_assignment` lines; Stages 1–3 (project-only verify) never ran the fitter,
so the gap surfaced as Error 12677 in the first Stage 4 full compile. All 48 pin
locations were recovered from the upstream `legacy_baseline.qsf` and inserted into
`agilex5_devkit.qsf`; Stage 4 fit then passed (WNS +1.731 ns).

## ISSUE-015: Cross-tile transceiver refclk routing (UX 4B GBTCLK0 -> UX 4C SERDIN lanes)

**Closed (Stage 5 merged, 2026-05-18).** The single-refclk topology (GBTCLK0 on UX 4B
feeding both tiles) was rejected by the Fitter (Error 175001/175006), confirming Agilex 5
GTS cannot route a refclk across transceiver tiles. Resolved by adding GBTCLK1 (UX 4C
pad AV16/AV21) → `u_xcvr_refclk_4c` clock bridge → `u_jesd_link1.pll_refclk`; periphery
placement then passed.

## ISSUE-017: Phase A `iq_router_regs.h` is stale; new `dac_subsys_regs.h` is the source of truth

**Closed (2026-05-20).** New header `software/ad9176_config/dac_subsys_regs.h` was authored
against `reg_bank.vhd` (10-bit / 1 KB map, with the SPI master as a separate IP at
LWS2F+0x1000), replacing Phase A's `iq_router_regs.h` (wider map, merged SPI). The Phase A
header is retained at `software/ad9176_config/reference/iq_router_regs.h` for traceability
only and is not in the Stage 7 build paths. Re-audit `dac_subsys_regs.h` on any future
`reg_bank.vhd` edit.
