# dac_controller_0 Design Description

**Target Device:** Intel Agilex 5 E-Series FPGA `A5ED052AB32AI2E` (GTS Transceiver Architecture)
**Daughter Board:** Analog Devices AD9176-FMC-EBZ evaluation board
**Language:** VHDL-2008
**Synthesis Tool:** Intel Quartus

---

## 1. System Overview

`dac_controller_0` is a Platform Designer IP component that streams IQ sample data to an AD9176 dual-core DAC via two JESD204B links. It is the sole logic block connecting the Agilex 5 FPGA fabric to the AD9176-FMC-EBZ board's high-speed digital interfaces.

The ARM Hard Processor System (HPS) embedded in the Agilex 5 serves two roles:

1. **Control plane** — configures FPGA registers (NCO frequency, JESD sync mode, source selection) via the `lwhpm2fpga` lightweight AXI bridge mapped to `dac_controller_0`.
2. **AD9176 SPI configuration** — directly programs the AD9176 device registers via a software bit-banged SPI interface using HPS GPIO. No SPI master exists in the FPGA fabric.

The high-speed data path operates entirely within the FPGA fabric, from the internal NCO through the JESD204B transport layer to the Intel JESD GTS IP block.

---

## 2. Top-Level Interface

### Entity: `dac_controller_0`

| Port Group | Port Name Pattern | Direction | Description |
|---|---|---|---|
| AXI4 Control | `lwhpm2fpga_*` | In/Out | AXI4 slave — HPS lwhpm2fpga bridge |
| System | `clock_sink_clk` | In | AXI control clock (100–200 MHz) |
| System | `reset_sink_reset` | In | Active-high synchronous reset |
| JESD Reset | `jesd_gts_ss_tx_..._rst_n` | Out | Active-low JESD GTS subsystem reset |
| JESD Reset | `..._in_of_reset_export` | In | GTS reset active indicator |
| JESD Reset | `..._rst_ack_n_export` | In | GTS reset acknowledge |
| JESD Link Clk | `jesd204_tx_link_clk_clk` | In | JESD link clock ~250 MHz |
| JESD Link 0 | `jesd_gts_ss_TX_outtel_jesd_TX_*` | In/Out | Link 0 streaming — DAC core A |
| JESD Link 1 | `jesd_gts_ss_TX_outtel_jesd_TX_p1_*` | In/Out | Link 1 streaming — DAC core B |
| GTS Clk Mgmt | `jesd_gts_ss_TX_outst_src_*` | In/Out | Reference clock priority / status |
| PIO (stub) | `pio_control/status_*` | In/Out | Deferred — pass-through stubs |
| TX Enable (stub) | `tx_enbl` | In | Deferred |

### Generic

| Generic | Default | Description |
|---|---|---|
| `G_LUT_DEPTH` | 1024 | NCO quarter-wave LUT size. Testbenches should use 64–128 to reduce elaboration time. |

---

## 3. Module Hierarchy

```
dac_controller_0 (top-level)
├── AxiToAvmm            (u_axi_bridge)     — AXI4 slave → Avalon-MM master bridge
├── RegBank              (u_reg_bank)        — Avalon-MM CSR register file (1 KB)
├── SineWaveGen          (u_sine_wave_gen)   — 4-converter NCO, 8 samples/clk
├── DcFifo               (u_dc_fifo)         — Dual-clock async FIFO, CDC boundary
├── DataSrcMux           (u_data_src_mux)    — LMFC-aligned NCO/FIFO source MUX
├── JesdSyncController   (u_jesd_sync_ctrl)  — LMFC alignment & per-group sync FSM
├── JesdTxManager        (u_jesd_tx_mgr_0)   — Transport layer packing — Link 0
└── JesdTxManager        (u_jesd_tx_mgr_1)   — Transport layer packing — Link 1
```

**Note:** `AxiToAvmm`, `RegBank` run in `clock_sink_clk`. All remaining modules run in `txlink_clk` (`jesd204_tx_link_clk_clk`, ~250 MHz). Explicit CDC structures cross between the two domains.

---

## 4. Module Descriptions

### 4.1 AxiToAvmm

**File:** [src/axi_to_avmm.vhd](../src/axi_to_avmm.vhd)

Converts full AXI4 slave transactions from the Agilex 5 HPS `lwhpm2fpga` bridge into Avalon-MM waitrequest-mode transactions to `RegBank`. Only single-beat transfers are forwarded; burst support is accepted at the AXI level but only the first beat is issued (matches HPS bridge behavior for register-mapped peripherals).

Write priority over read is enforced in the IDLE state.

**FSM States:**

| State | Description |
|---|---|
| `S_IDLE` | Wait for write (`AW+W` valid) or read (`AR` valid) |
| `S_WRITE` | Assert `avmm_write`, hold until `avmm_waitrequest` deasserts |
| `S_WRITE_RESP` | Assert `bvalid`, wait for AXI `bready` |
| `S_READ` | Assert `avmm_read`, hold until `avmm_waitrequest` deasserts, latch `rdata` |
| `S_READ_RESP` | Assert `rvalid`, wait for AXI `rready` |

**Generics:** `G_ADDR_WIDTH=10`, `G_DATA_WIDTH=32`, `G_ID_WIDTH=4`

---

### 4.2 RegBank

**File:** [src/reg_bank.vhd](../src/reg_bank.vhd)

Avalon-MM slave register file occupying a 10-bit (1 KB) byte-addressed space. Zero wait-state read response. All writes are registered. Contains the complete CSR for the NCO, JESD sync controller, and PIO stubs.

Outputs `t_sine_csr` and `t_jesd_sync_csr` record types directly to the top level for CDC dispatch into `txlink_clk`. Receives synchronized status back for HPS readback.

**Register Map Summary:**

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x000–0x00C` | `SCRATCH0–3` | RW | Bridge connectivity test registers |
| `0x020` | `JESD_SYNC_CTRL` | RW | bit[0]: sync_mode (0=per-DAC 2-link, 1=all-four) |
| `0x024` | `JESD_SYNC_STATUS` | R | [3:0]=txlink_ready, [5:4]=group_synced, [6]=lmfc_aligned |
| `0x028` | `JESD_SYNC_ERR` | R/W1C | [3:0]: per-link sticky error flags (write-1-to-clear) |
| `0x030` | `JESD_TX_SRC_SEL` | RW | bit[0]: 0=NCO, 1=FIFO |
| `0x034` | `JESD_TX_SRC_STAT` | R | bit[0]=switch_pending, bit[1]=src_active |
| `0x040` | `SINE_CTRL` | RW | bit[0]=enable, bits[4:1]=conv_enable[3:0] |
| `0x050` | `SINE_FREQ_CH1_I` | RW | Converter M0 (DAC core A, I) frequency word |
| `0x054` | `SINE_FREQ_CH1_Q` | RW | Converter M1 (DAC core A, Q) frequency word |
| `0x058` | `SINE_FREQ_CH2_I` | RW | Converter M2 (DAC core B, I) frequency word |
| `0x05C` | `SINE_FREQ_CH2_Q` | RW | Converter M3 (DAC core B, Q) frequency word |
| `0x060–0x06C` | `SINE_PHASE_M0–M3` | RW | Per-converter 32-bit phase offset |
| `0x070–0x07C` | `SINE_AMP_M0–M3` | RW | Per-converter 16-bit amplitude (default 0x7FFF) |
| `0x080` | `PIO_CTRL` | RW | PIO output register (stub) |
| `0x084` | `PIO_STATUS` | R | PIO input register (stub) |

**NCO Frequency Calculation:**
```
freq_word = round(f_tone_Hz × 2^32 / f_sample_Hz)
f_sample_Hz = 2 × f_link_clk_Hz
Example: 10 MHz @ 500 MSPS → 0x051EB852
```

---

### 4.3 SineWaveGen

**File:** [src/sine_wave_gen.vhd](../src/sine_wave_gen.vhd)

Four-converter NCO producing 8 samples per link clock cycle (2 samples per converter per clock). Each converter maintains an independent 32-bit phase accumulator. A quarter-wave sine LUT (default 1024 entries, 16-bit signed values, full scale = 32767) is shared across all converters via block RAM inference.

**Pipeline (2 registered stages + combinational):**

```
Stage 0 (combinational):  phase_acc + offset → S0/S1 full phase
                          phase → LUT address (quadrant fold)

Stage 1 (registered):     LUT read → s0_raw, s1_raw
                          quadrant bits delayed for sign correction

Stage 2 (registered):     apply_quadrant_sign(raw) × amplitude → scaled output
                          sign correct: quadrant[1]=1 → negate
                          amplitude scale: 16-bit × 17-bit, extract [30:15]
```

**Phase accumulator advance:** Each clock cycle the accumulator advances by `2 × freq_word` because two consecutive samples (S0, S1) are produced simultaneously.

**Sample output mapping (AD9176 Mode 4 typical usage):**

| Sample Bus Field | Converter | Signal |
|---|---|---|
| `m0_s0 / m0_s1` | M0 | DAC core A — I channel |
| `m1_s0 / m1_s1` | M1 | DAC core A — Q channel |
| `m2_s0 / m2_s1` | M2 | DAC core B — I channel |
| `m3_s0 / m3_s1` | M3 | DAC core B — Q channel |

I/Q channel pairing is configured via software by setting 90° phase offsets on Q converters (not hardwired in RTL).

---

### 4.4 DcFifo

**File:** [src/dc_fifo.vhd](../src/dc_fifo.vhd)

Parameterized dual-clock asynchronous FIFO using gray-coded pointers for safe CDC. Standard implementation: write and read pointers maintained in binary per their respective clock domains; converted to Gray code before crossing via 2-stage synchronizers. Empty/full detection uses the gray-coded synchronized pointers.

**Fill level** is reported in the read clock domain by converting the synchronized write pointer back to binary and subtracting the read pointer. Used by `DataSrcMux` for the pre-fill threshold check before switching to FIFO source.

In Phase A the FIFO write port is tied off (no external data source connected). The FIFO is instantiated with `G_DATA_WIDTH=128`, `G_DEPTH=512`.

**Generics:** `G_DATA_WIDTH`, `G_DEPTH` (must be power of 2)

---

### 4.5 DataSrcMux

**File:** [src/data_src_mux.vhd](../src/data_src_mux.vhd)

LMFC-aligned source multiplexer with double-buffered switching. Prevents sample glitches at the transport layer by only switching between NCO and FIFO sources on LMFC boundaries, guaranteeing frame-aligned transitions.

**Source switching protocol:**

1. HPS writes `JESD_TX_SRC_SEL[0]` → reflected to `src_sel` in `txlink_clk` domain via 2-stage sync.
2. If `src_sel ≠ active_src`, `pending` is asserted.
3. On the next `lmfc_boundary` pulse:
   - Switch to NCO: unconditional.
   - Switch to FIFO: only if `fill_level ≥ G_FILL_THRESHOLD` (default 256 of 512 entries).
4. If FIFO below threshold: `pending` stays set; switch is retried on the next LMFC boundary.

**Status outputs:** `src_switch_pending` and `src_active` are synchronized into `clock_sink_clk` for HPS readback via `JESD_TX_SRC_STAT`.

**Generics:** `G_FIFO_DEPTH=512`, `G_FILL_THRESHOLD=256`

---

### 4.6 JesdSyncController

**File:** [src/jesd_sync_controller.vhd](../src/jesd_sync_controller.vhd)

Manages LMFC-aligned deterministic latency for two independent link groups. Runs entirely in `txlink_clk` domain.

**LMFC counter:** Free-running 4-bit counter wrapping at `C_LMFC_PERIOD=16` link clocks. Derived from JESD204B parameters: K=32, F=2, effective frames-per-clock=2, so LMFC period = 32/2 = 16 link clocks.

**Groups:**

| Group | Links | Condition (`sync_mode=0`, per-DAC) |
|---|---|---|
| Group 0 | 0, 1 | Both links ready (one AD9176, two cores) |
| Group 1 | 2, 3 | Both links ready (stub — always unready in Phase A) |

When `sync_mode=1` (all-four), both groups require all four links to be ready simultaneously.

**Per-group FSM:**

| State | Entry Condition | Exit Condition |
|---|---|---|
| `ST_WAIT_LOCK` | Reset or error recovery | `grp_all_ready = '1'` → `ST_WAIT_LMFC` |
| `ST_WAIT_LMFC` | All links ready | `lmfc_bound = '1'` → `ST_RUNNING`; link drop → `ST_WAIT_LOCK` |
| `ST_RUNNING` | LMFC boundary reached | Link drop → `ST_ERROR` |
| `ST_ERROR` | Link dropout during run | Unconditional → `ST_WAIT_LOCK` (auto-retry) |

`data_release[1:0]` follows `grp0_release`; `data_release[3:2]` follows `grp1_release`. In Phase A only `data_release[0]` and `[1]` become active.

**Sticky error flags** (`sync_err[3:0]`) latch on link dropout during `ST_RUNNING`. Cleared by write-1-to-clear from HPS via `JESD_SYNC_ERR`. A toggle synchronizer propagates the clear pulse from `clock_sink_clk` to `txlink_clk`.

---

### 4.7 JesdTxManager

**File:** [src/jesd_tx_manager.vhd](../src/jesd_tx_manager.vhd)

JESD204B Mode 4 transport layer. Packs the `t_sample_bus` (8 × 16-bit samples) into the 4-lane × 32-bit (`t_lane_data`) format required by the Intel JESD204B GTS IP streaming interface.

**Lane packing (JESD204B Table 18, MSB-first, HD=1, F=2, S=1):**

| Lane | Content (32 bits) |
|---|---|
| Lane 0 | M0_S0[15:8] & M0_S0[7:0] & M0_S1[15:8] & M0_S1[7:0] |
| Lane 1 | M1_S0[15:8] & M1_S0[7:0] & M1_S1[15:8] & M1_S1[7:0] |
| Lane 2 | M2_S0[15:8] & M2_S0[7:0] & M2_S1[15:8] & M2_S1[7:0] |
| Lane 3 | M3_S0[15:8] & M3_S0[7:0] & M3_S1[15:8] & M3_S1[7:0] |

One converter per lane; each lane carries 2 samples per clock (2 frames × F=2 octets/frame).

The Intel JESD204B IP requires **continuous valid** once `tx_ready` is asserted — there is no back-pressure. When `samples_valid = '0'`, all lane outputs are zeroed (mid-scale / silence). This is a safety fallback; it should not occur during active transmission.

Two instances are instantiated: `u_jesd_tx_mgr_0` (Link 0, DAC core A) and `u_jesd_tx_mgr_1` (Link 1, DAC core B). Both receive the same `mux_samples` / `mux_valid` bus and `data_release` gating.

The 4-lane `t_lane_data` record is flattened to a 128-bit `std_logic_vector` at the top level for connection to the JESD GTS IP. Bit mapping: `[31:0]=lane0, [63:32]=lane1, [95:64]=lane2, [127:96]=lane3`.

---

## 5. Data Flow

### 5.1 Control Path (HPS → FPGA registers)

```
ARM HPS
  → lwhpm2fpga AXI bridge (Agilex 5 HPS-to-FPGA bridge)
  → dac_controller_0 AXI4 ports
  → AxiToAvmm (FSM: IDLE → WRITE/READ → RESP)
  → Avalon-MM bus (10-bit address, 32-bit data)
  → RegBank (address-decoded register file)
  → t_sine_csr / t_jesd_sync_csr records (clock_sink_clk domain)
  → CDC structures
  → txlink_clk domain logic
```

### 5.2 Sample Data Path (NCO source)

```
RegBank (clock_sink_clk)
  → t_sine_csr record
  → CDC: quasi-static capture on txlink_clk while enable=0
  → sine_csr_txclk (txlink_clk domain)

SineWaveGen (txlink_clk)
  Phase Accumulators (×4, advance by 2×freq_word/clk)
  → Combinational: phase+offset → LUT address + quadrant
  → Stage 1 register: LUT read (4×BRAM dual-port)
  → Stage 2 register: quadrant sign correction + amplitude scaling
  → nco_samples (t_sample_bus: 8×16-bit) + nco_valid

DataSrcMux (txlink_clk)
  → active_src=0 (NCO): passes nco_samples / nco_valid
  → mux_samples (t_sample_bus) + mux_valid

JesdSyncController (txlink_clk)
  → data_release[1:0] gating
  → lmfc_boundary signal

JesdTxManager ×2 (txlink_clk)
  mux_samples & (mux_valid AND data_release[n])
  → lane packing: t_lane_data (4×32-bit)
  → flatten_lanes() → 128-bit std_logic_vector

Intel JESD204B GTS IP
  → 8B/10B encoding, scrambling, lane serialization
  → GTS transceivers → FMC connector

AD9176 (on FMC-EBZ)
  → deserializes JESD lanes → DAC digital datapath
  → 6× interpolation → 12 GSPS DAC output
```

### 5.3 AD9176 Configuration Path (SPI)

```
ARM HPS software (ad9176_fmc_ebz.c)
  → HPS GPIO bit-bang SPI (24-bit frames: R/W | A[14:0] | D[7:0])
  → AD9176 register interface (via FMC connector)
  → DAC PLL config, JESD204B parameters (M, L, F, K, S, N, HD, SCR)
  → JESD link enable
```

### 5.4 Status Path (FPGA → HPS)

```
JesdSyncController (txlink_clk)
  → txlink_ready[3:0], group_synced[1:0], lmfc_aligned, sync_err[3:0]
  → 2-stage synchronizers → clock_sink_clk domain
  → jesd_sync_status record → RegBank → JESD_SYNC_STATUS / JESD_SYNC_ERR

DataSrcMux (txlink_clk)
  → src_switch_pending, src_active
  → 2-stage synchronizers → clock_sink_clk
  → jesd_sync_status → RegBank → JESD_TX_SRC_STAT

HPS reads FPGA registers via lwhpm2fpga AXI bridge
```

---

## 6. Clock Domains

| Clock Signal | Internal Alias | Typical Frequency | Domain Contents |
|---|---|---|---|
| `clock_sink_clk` | — | 100–200 MHz | AXI bridge, RegBank, JESD GTS reset sequencer |
| `jesd204_tx_link_clk_clk` | `txlink_clk` | ~250 MHz | NCO, FIFO read, DataSrcMux, JesdSyncController, JesdTxManager ×2 |

### 6.1 CDC Structures

**`clock_sink_clk` → `txlink_clk`:**

| Signal(s) | Technique | Notes |
|---|---|---|
| `sine_csr.enable` (1-bit) | 2-stage synchronizer | Enable bit only |
| `sine_csr` config fields | Quasi-static capture | Captured while `sine_enable_sync=0`; SW must write config before asserting enable |
| `sync_mode`, `src_sel` | 2-stage synchronizer | Single-bit quasi-static CSR fields |
| `jesd_sync_err_clr[3:0]` | Toggle synchronizer (pulse) | RegBank writes a pulse; top level converts to toggle; toggles are synchronized and edge-detected in `txlink_clk` |

**`txlink_clk` → `clock_sink_clk`:**

| Signal(s) | Technique | Notes |
|---|---|---|
| `txlink_ready[3:0]` | 2-stage synchronizer | Frame-ready from JESD GTS IP |
| `group_synced[1:0]` | 2-stage synchronizer | JesdSyncController FSM output |
| `lmfc_aligned` | 2-stage synchronizer | Combined group sync status |
| `sync_err[3:0]` | 2-stage synchronizer | Sticky error flags |
| `src_switch_pending`, `src_active` | 2-stage synchronizer | DataSrcMux status |

**Reset synchronization:**
- `reset_sink_reset` is active-high in `clock_sink_clk` domain.
- Synchronized into `txlink_clk` with a 2-stage flip-flop chain (`txlink_rst_meta → txlink_rst`).
- All `txlink_clk` domain logic uses `txlink_rst` as the synchronous reset.

**JESD GTS reset sequencer:**
- `reset_sink_reset` triggers a 64-cycle hold counter in `clock_sink_clk`.
- Drives `jesd_gts_ss_tx_..._rst_n_reset_n` active-low to the GTS subsystem.
- `rst_ack_n` is monitored (for future use; not gating logic in Phase A).

---

## 7. JESD204B Configuration

| Parameter | Value | Description |
|---|---|---|
| Mode | 4 | AD9176 datasheet JESD mode |
| M | 4 | Converters per link |
| L | 4 | Lanes per link |
| F | 2 | Octets per frame per lane |
| S | 1 | Samples per converter per frame |
| N / NP | 16 | Converter resolution / JESD word size |
| K | 32 | Frames per multiframe (LMFC period) |
| HD | 1 | High density mode |
| SCR | 1 | Scrambling enabled |
| Links | 2 | One per AD9176 DAC core (A and B) |

**LMFC period derivation:**
```
frames_per_link_clk = L × 4 / (M × F) = 4×4 / (4×2) = 2 frames/clock
LMFC period         = K / frames_per_clock = 32 / 2   = 16 link clocks
→ C_LMFC_PERIOD = 16
```

---

## 8. Agilex 5 Integration Path

### 8.1 Platform Designer Setup

1. Add the Intel JESD204B GTS IP to the Platform Designer (PD) project.
   - Configure for Tx-only, 2 links, 4 lanes each, Mode 4 parameters as above.
   - Set the link clock output to drive `jesd204_tx_link_clk_clk` of `dac_controller_0`.

2. Add `dac_controller_0` as a Platform Designer component.
   - Connect `lwhpm2fpga` AXI4 slave to the HPS `lwhps2fpga` lightweight bridge.
   - Note the base address assigned by PD; update `DAC_CTRL_BASE` in `ad9176_fmc_ebz.h`.

3. Connect the JESD GTS IP exported streaming ports to `dac_controller_0`:
   - Link 0: `jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_*`
   - Link 1: `jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_*`
   - Reset sequencing: `in_of_reset_export`, `rst_n_reset_n`, `rst_ack_n_export`
   - Reference clock management: `txphy_clk_export`, `rs_priority`, `refclk_on`, `refclk_fail_status`, `refclk_on_ack`

4. Connect `clock_sink_clk` to the HPS bridge clock, `reset_sink_reset` to the system reset.

5. Tie off stub ports:
   - `pio_control_external_connection_export` → external GPIO or tie to `'0'`
   - `pio_status_external_connection_export` → leave unconnected or tie to `(others => '0')`
   - `tx_enbl` → tie to `'1'` (or future control logic)

### 8.2 Constraints

- Add `set_false_path` for all CDC paths listed in Section 6.1.
- Gray-coded FIFO pointer paths should use `set_max_delay -datapath_only` constraints.
- Target: WNS ≥ 0.5 ns, ALM/M20K/DSP utilization < 80%.

### 8.3 HPS Software Integration Sequence

1. Call `ad9176_fpga_bridge_test()` — verifies scratchpad registers via lwhpm2fpga bridge.
2. Call `ad9176_init()` — configures AD9176 over SPI (PLL, JESD params, link enable).
3. Call `ad9176_jesd_wait_lock(timeout_ms)` — polls `JESD_SYNC_STATUS` for:
   - `txlink_ready[1:0] = 0x3` (both active links locked at JESD IP level)
   - `group_synced[0] = 1` (Group 0 FSM in `ST_RUNNING` — LMFC boundary released)
4. Call `ad9176_nco_enable(freq_hz, f_sample_hz)` — programs NCO and asserts `SINE_CTRL.enable`.
5. Verify DAC output on spectrum analyzer; NCO produces a pure tone at the configured frequency.

**Important:** HPS software must write all NCO configuration registers **before** asserting `SINE_CTRL[0]` (enable). The RTL only samples configuration into `txlink_clk` domain while `enable=0`. Enabling first then configuring causes indeterminate output frequencies.

---

## 9. Package Types (`DacControllerPkg`)

**File:** [src/dac_controller_pkg.vhd](../src/dac_controller_pkg.vhd)

| Type | Fields | Used By |
|---|---|---|
| `t_sample_bus` | `m0_s0..m3_s1` (8 × `signed(15:0)`) | SineWaveGen out, DcFifo payload, DataSrcMux, JesdTxManager in |
| `t_lane_data` | `lane0..lane3` (4 × `slv(31:0)`) | JesdTxManager out → JESD IP stream |
| `t_sine_csr` | enable, conv_enable[3:0], freq_m0–m3, phase_ofs_m0–m3, amplitude_m0–m3 | RegBank out → SineWaveGen in |
| `t_jesd_sync_csr` | sync_mode, src_sel | RegBank out → JesdSyncController + DataSrcMux |
| `t_jesd_sync_status` | txlink_ready[3:0], group_synced[1:0], lmfc_aligned, sync_err[3:0], src_switch_pending, src_active | JesdSyncController/DataSrcMux out → RegBank in |

---

## 10. Known Constraints and Deferred Items

| Item | Status | Notes |
|---|---|---|
| Group 1 (links 2, 3) | Stub — tied to `'0'` | No second AD9176 in Phase A. `lmfc_aligned` will always read 0; use `group_synced[0]` instead. |
| FIFO write port | Tied off | No external data source in Phase A. `DcFifo` write-side inputs are all `'0'`/open. |
| `pio_control/status` | Pass-through stub | Registers exist; functionality deferred. |
| `tx_enbl` | Tied off | No logic uses this port in Phase A. |
| JESD `rst_ack_n` | Monitored, not gating | RST ACK readback is present; hardware validation will confirm sequencing. |
| `lwhpm2fpga` base address | Placeholder (`0xFF200000`) | Must be confirmed against PD memory map assignment. |
| SPI GPIO pin assignments | Placeholder | `SPI_CLK_GPIO_BASE` and pin numbers in `ad9176_fmc_ebz.h` must be confirmed for the Agilex 5 dev board FMC connector. |
