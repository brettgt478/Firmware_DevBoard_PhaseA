# Phase B Design Review — `agilex5_devkit`

**Reviewer:** senior firmware engineer (implementation-design review)
**Date:** 2026-06-05
**Scope:** `dac_controller_0` RTL + `jesd_stub` + `dac_subsys.tcl` wiring + top-level
[agilex5_devkit.sv](../projects/agilex5_devkit/agilex5_devkit.sv) + SDC + the
`ad9176_config` user-space tool.

This review traces the JESD data path and the Stage-7 bring-up software end to end
against the source, confirms the already-tracked issues, and records previously
**untracked** deficiencies. New issues are filed in
[potential_issues.md](potential_issues.md) (ISSUE-020 … ISSUE-025, plus extensions to
ISSUE-007 / ISSUE-019). Fixes applied in the same change set are marked **[fixed]**;
items needing the build machine or vendor-IP internals are marked **[deferred]** with
the precise follow-up procedure, mirroring the ISSUE-019 precedent.

---

## Verdict

The control plane (CSR / SPI / PIO / FMC handshake) is coherent and well built. The
**JESD data path could not bring up or stream as originally wired** — and the blocking
cause was *not* the one the docs flagged (ISSUE-019, missing GTS reset sequencer). Two
independent, committed defects each prevented the end-to-end goal (a tone on the AD9176
RF output), plus a subclass-1 determinism concern. The two blockers are fixed in this
change set; the remaining items are tracked.

---

## CRITICAL-1 — JESD link-ready feedback was hardwired to `'0'` (ISSUE-020) **[fixed, with deferred follow-up]**

The Phase A controller gates all JESD payload on link readiness, but after the Stage-5
integration that readiness came from the **stub**, not the real GTS IP:

- [jesd_stub.vhd](../ip/jesd_stub/src/jesd_stub.vhd) drove
  `jesd_link0_status_frame_ready <= '0'` / `jesd_link1_status_frame_ready <= '0'`.
- [dac_subsys.tcl:290-291](../ip/dac_subsys/dac_subsys.tcl#L290-L291) connects
  `u_dac_controller_0.jesd_link0/1_status` to that stub; the real GTS IPs are wired only
  for `jesd204_tx_link` data + CSR + sync_n — **no link-status output is fed back**.
- [dac_controller_0.vhd:347-348](../ip/dac_controller_0/src/dac_controller_0.vhd#L347-L348)
  ties `txlink_ready(0/1)` to those stubbed `frame_ready` ports.
- `txlink_ready` drives `JesdSyncController`; `grp0_release` only asserts in `ST_RUNNING`,
  which needs `txlink_ready(0) and txlink_ready(1)`
  ([jesd_sync_controller.vhd:89](../ip/dac_controller_0/src/jesd_sync_controller.vhd#L89)).
  With both stubbed to `0` it never runs.
- Link `valid` is `lane_valid and data_release`
  ([dac_controller_0.vhd:675](../ip/dac_controller_0/src/dac_controller_0.vhd#L675),
  [:680](../ip/dac_controller_0/src/dac_controller_0.vhd#L680)) → **`tx_link_valid` was
  permanently 0; no samples were ever streamed**, even on perfect hardware.

The same stubbed path feeds software: `dac_subsys_wait_link_lock()` polls
`REG_JESD_SYNC_STATUS`
([ad9176_init.c](../software/ad9176_config/ad9176_init.c)), whose `txrdy`/`grp` fields
originate from the stubbed signals — so the poll could never pass.

**Why this is not ISSUE-019.** ISSUE-019 / [architecture.md §2](architecture.md)
attributed the all-zero sync status to the missing reset sequencer and claimed it would
"self-heal once the sequencer makes the JESD datapath real." That is **wrong for this
path**: `frame_ready` was tied to a constant `'0'` in fabric, independent of the
PMA/reset-sequencer state. Adding the reset sequencer would not have released data.

**Fix applied.** With the real Intel GTS IP, the transport must supply continuous data;
the link layer (GTS IP) gates the wire via SYNC_N/ILAS. The Phase A `data_release`
interlock predates the GTS IP and is redundant. The stub now drives `frame_ready <= '1'`
so the transport free-runs (continuous `valid`), and the software gate is meaningful
again (after CRITICAL-2 the active group reaches `ST_RUNNING`).

**Deferred follow-up (build machine).** The architecturally clean fix is to wire each GTS
IP's real link-status output back into `u_dac_controller_0.jesd_link*_status` and delete
the stub's frame-ready/somf drivers — this requires the GTS IP status port names and a
`qsys-generate` + fit + DRC pass. Until then, the FPGA `REG_JESD_SYNC_STATUS` gate proves
the **FPGA transport is releasing data**, not that the AD9176 achieved code-group sync;
the software now also reads the AD9176's own `LINK_STATUS` (0x301) and prints it so the
bring-up engineer can confirm the physical link during Procedure 5.A / 7.A. Residual: the
GTS multiframe boundary (`somf`) is not fed back to the Phase A LMFC counter; confirm
lane/frame alignment on hardware.

## CRITICAL-2 — `dac_subsys_release_sync()` selected all-four sync mode (ISSUE-021) **[fixed]**

[ad9176_init.c](../software/ad9176_config/ad9176_init.c) wrote `REG_JESD_SYNC_CTRL = 0x1`
with a comment claiming it "starts the sync controller state machine." It is **not** a
start bit. Bit 0 maps to `sync_mode`
([reg_bank.vhd:251](../ip/dac_controller_0/src/reg_bank.vhd#L251)), and `sync_mode = 1`
selects **all-four mode**, which requires `txlink_ready(0..3)` all high
([jesd_sync_controller.vhd:91-97](../ip/dac_controller_0/src/jesd_sync_controller.vhd#L91-L97)).
Links 2/3 are permanently tied low on this single-AD9176 board, so this *guaranteed* the
active group never reached `ST_RUNNING` — even if CRITICAL-1 were fixed. The FSM
auto-starts from reset; no "release" write is needed. The function comment also claimed it
"deasserts the SYNC_N output to the AD9176," but the FPGA does **not** drive SYNC_N here —
it is an *input* from the AD9176 into the GTS IP
([agilex5_devkit.sv:131-132](../projects/agilex5_devkit/agilex5_devkit.sv#L131-L132)).

**Fix applied.** Write `0x0` (per-DAC mode, group 0 = links 0+1) and rewrite the comments.

## HIGH-3 — SYSREF re-synchronizer undermines subclass-1 determinism (ISSUE-022) **[deferred]**

[sysref_capture.vhd:33-44](../projects/agilex5_devkit/src/sysref_capture.vhd#L33-L44)
passes SYSREF through a 2-stage metastability synchronizer and feeds the result to **both**
GTS IP `sysref` inputs
([agilex5_devkit.sv:392-393](../projects/agilex5_devkit/agilex5_devkit.sv#L392-L393)).
Subclass-1 deterministic latency depends on SYSREF being captured with a known, repeatable
phase relative to the link clock so the LMFC counter resets deterministically. A 2-FF
synchronizer deliberately allows ±1 cycle of non-deterministic resolution, defeating
deterministic LMFC alignment on the FPGA side. Either bring SYSREF into the GTS IP's own
dedicated capture path (recommended), or formally drop to subclass-0 (already a documented
fallback). Needs build + STA validation; deferred.

## HIGH-4 — Missing GTS Reset Sequencer (ISSUE-019, confirmed) **[deferred]**

ISSUE-019 is real and is a hard hardware blocker. Added caveat: the JESD-domain reset
bridges (`u_rst_bridge_jesd`, `u_rst_bridge_jesd_n`) are clocked by the **GTS-sourced
`txphy_clk[0]` loopback** ([dac_subsys.tcl:137-139](../ip/dac_subsys/dac_subsys.tcl#L137-L139),
[agilex5_devkit.sv:270](../projects/agilex5_devkit/agilex5_devkit.sv#L270)) — i.e. the
resets that release the GTS depend on a clock the GTS only produces once released. Usual
transceiver pattern (txphy_clk is PMA-sourced), but validate explicitly when the sequencer
lands.

## MEDIUM-5 — Real GTS AVST backpressure is ignored (ISSUE-024) **[deferred]**

`jesd204_tx_link_ready` from the GTS IP is now a live backpressure signal, but the
controller's `..._link_ready` input is unused and
[jesd_tx_manager.vhd:62](../ip/dac_controller_0/src/jesd_tx_manager.vhd#L62) drives
`lane_valid <= samples_valid` unconditionally. If the GTS link layer ever deasserts ready,
samples are dropped → frame slip. Phase A RTL is frozen (CLAUDE.md §1/§5), so confirm the
IP holds ready continuously in this mode, or add a transport-side elastic stage in Phase B
glue.

## MEDIUM-6 — AD9176 silicon-ID read before 4-wire SPI enable (ISSUE-023) **[fixed]**

`ad9176_verify_id()` reads `CHIPTYPE/PRODID` over the separate-MISO (4-wire) fabric SPI
master immediately after reset, but the bring-up never configured the AD9176 SPI interface
(`SPI_INTFCONFA`, reg 0x000) for SDO-active. The AD9176 powers up in 3-wire SDIO mode;
unless the board straps 4-wire, the first read returns garbage and bring-up aborts at
`verify_id`.

**Fix applied.** `ad9176_reset()` now writes `0x18` (SDOACTIVE + mirror) to reg 0x000
after the soft-reset deassert, enabling 4-wire before the first read.

## MEDIUM-7 — `AxiToAvmm` write handshake / burst handling unguarded (ISSUE-007 extended) **[deferred]**

[axi_to_avmm.vhd:141](../ip/dac_controller_0/src/axi_to_avmm.vhd#L141) accepts a write only
when `AWVALID` **and** `WVALID` are asserted in the same cycle, which deadlocks against any
AXI master that waits for `AWREADY` before driving `WVALID` (legal AXI). `awlen`/`arlen`
are ignored entirely; a burst would hang the master. Practically safe with the LWH2F
bridge (issues AW+W together, single beat), but unverified. Phase A RTL frozen; tracked
under ISSUE-007.

## MEDIUM-8 — One link clock shared across two PMA tiles (ISSUE-025) **[deferred]**

`u_jesd_link1` (UX 4C) takes its `txlink_clk` from `u_jesd_link0`'s (UX 4B)
`txphy_clk[0]` ([dac_subsys.tcl:397-398](../ip/dac_subsys/dac_subsys.tcl#L397-L398)). The
two links have independent PMAs/PLLs/refclk pads, so this relies on each IP's TX
phase-compensation FIFO. Confirm phase-comp is enabled on both, or link 1 risks periodic
slips. Needs build/IP validation.

---

## LOW / documentation & hygiene

- **ISSUE-009 "fix" was ineffective as committed.** The 2026-06-05 edit dropped the `lmfc`
  condition, but the gate still could not pass because of CRITICAL-1 (stubbed `txrdy`/`grp`)
  and CRITICAL-2 (wrong `sync_mode`). Re-scoped: see ISSUE-020 / ISSUE-021.
- **Legacy IQ register naming.** `REG_SINE_FREQ_CH1_I/Q`, `CH2_I/Q` actually map to
  per-converter `freq_m0..m3`
  ([reg_bank.vhd:237-240](../ip/dac_controller_0/src/reg_bank.vhd#L237-L240)). Consistent,
  but the CH/IQ-vs-`m0..m3` vocabulary clash invites exactly the audit error ISSUE-017
  warns about. Phase A RTL frozen — documentation-only.
- **Muddled LMFC arithmetic comment** in
  [dac_controller_pkg.vhd:40-42](../ip/dac_controller_0/src/dac_controller_pkg.vhd#L40-L42)
  ("4 frames/clk" then ÷2 → 16). The constant `C_LMFC_PERIOD = 16` is correct; the comment
  is not. Phase A RTL frozen — left as-is, noted here.
- **Vestigial Phase A JESD control surface.** The controller's internal reset sequencer,
  refclk-ctrl tie-offs, `csr_readback`, `pio`, and `tx_enbl` all dead-end into the stub;
  prune per the stub's own TODO once the GTS status rewire (ISSUE-020) lands.
- **No license-clean deployable bitstream yet (ISSUE-016).** Only a time-limited
  OpenCore-Plus SOF has been produced; Stage 9 reused Stage 5/8b reports. The "deployable
  firmware" milestone is not actually met.

---

## What's solid

- Stage-8b bit-shift fix is correct: `fmc_ready` at bit 5
  ([agilex5_devkit.sv:220](../projects/agilex5_devkit/agilex5_devkit.sv#L220) ↔
  [dac_subsys_regs.h:123](../software/ad9176_config/dac_subsys_regs.h#L123)).
- AD9176 SPI 24-bit framing (R/W, 15-bit addr, 8-bit data) correct for read and write.
- Control/status CDC (quasi-static sine CSR, toggle error-clear, 2-stage status readback)
  is disciplined and matches the documented Phase A rules.
- Address maps are consistent across `reg_bank.vhd`, `dac_subsys.tcl`,
  `dac_subsys_regs.h`, CLAUDE.md, and architecture.md.

---

## Suggested priority order to unblock bring-up

1. **[done]** CRITICAL-2 — `REG_JESD_SYNC_CTRL = 0x0`.
2. **[done]** CRITICAL-1 interim — stub `frame_ready` high + AD9176 link-status readback.
3. CRITICAL-1 permanent — wire real GTS link status back to the controller (build machine).
4. ISSUE-019 — add the GTS reset sequencer (build machine).
5. HIGH-3 — resolve SYSREF capture or commit to subclass-0.
6. Re-run a full, license-clean build and re-validate the deferred hardware procedures.
