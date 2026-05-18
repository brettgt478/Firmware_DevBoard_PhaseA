# dac_subsys.tcl
#
# qsys-script source-of-truth for ip/dac_subsys/dac_subsys.qsys.
# Hand-edit this file; the .qsys is regenerated from it by build.tcl
# (and on demand via:  qsys-script --quartus-project=agilex5_devkit.qpf
#                                  --script=../../ip/dac_subsys/dac_subsys.tcl).
#
# Stage 5 (merged): u_jesd_stub trimmed to terminate only the non-data JESD
# conduits of u_dac_controller_0 (status/refclk/csr/pio/tx_enbl); the two
# AVST data paths (jesd_link0_data, jesd_link1_data) now flow into two real
# Intel JESD204B GTS Subsystem instances (u_jesd_link0, u_jesd_link1), each
# carrying L=4 lanes (mode 4: M=4, F=2, S=1, NP=16, K=32, HD=1, SCR=1) at
# 12.5 Gbps lane rate. Refclk enters via u_xcvr_refclk (GBTCLK0, 312.5 MHz).
#
# Address map (Avalon-MM, 14-bit byte address, 16 KB total):
#   0x0000  u_dac_controller_0.lwhpm2fpga      1 KB   (Phase A RegBank)
#   0x1000  u_spi_master.spi_control_port      64 B   (AD9176 SPI master)
#   0x1100  u_tx_en_pio.s1                     16 B   (FMC TXEN[1:0])
#   0x1110  u_pe_ctrl_pio.s1                   16 B   (FMC PE_CTRL)
#   0x1120  u_dac_status_pio.s1                16 B   (FMC PRSNT/PG, GA, JESD status)
#   0x1130  u_spi_en_pio.s1                    16 B   (FMC SPI buffer enable)   [Stage 4]
#   0x1140  u_pg_c2m_pio.s1                    16 B   (FMC PG C2M to mezzanine) [Stage 4]
#   0x2000  u_jesd_link0.jesd204_tx_avs        4 KB   (GTS JESD204B link 0 CSR)
#   0x3000  u_jesd_link1.jesd204_tx_avs        4 KB   (GTS JESD204B link 1 CSR)
#
# External interfaces exported by this system:
#   axi_csr            Avalon-MM slave  (14-bit byte addr, 32-bit data)
#   clock_sink_clk     clock sink       (100 MHz, system_clock from shell)
#   jesd_tx_link_clk   clock sink       (312.5 MHz, JESD TX link clock from
#                                        top-SV loopback of GTS txphy_clk[0])
#   xcvr_refclk        clock sink       (312.5 MHz, FMC GBTCLK0_M2C buffered)
#   axi_reset          reset sink       (system reset, sync to clock_sink_clk;
#                                        active-high)
#   axi_reset_n        reset sink       (system reset, active-low, AVS rst_n)
#   jesd_reset         reset sink       (system reset, sync to jesd_tx_link_clk;
#                                        active-high)
#   jesd_reset_n       reset sink       (system reset, active-low, jesd_tx_rst_n)
#   spi                conduit          (SPI bus: sck, mosi, miso, ss_n[1:0])
#   tx_en              conduit          (2-bit output → FMC_TXEN_0/1)
#   pe_ctrl            conduit          (1-bit output → FMC_PE_CTRL)
#   spi_en             conduit          (1-bit output → FMC_SPI_EN)             [Stage 4]
#   pg_c2m             conduit          (1-bit output → FMC_PG_C2M)             [Stage 4]
#   dac_status         conduit          (32-bit input ← FMC + JESD status)
#   sysref_link0       conduit          (1-bit input, sync'd SYSREF → GTS link0) [Stage 5]
#   sysref_link1       conduit          (1-bit input, sync'd SYSREF → GTS link1) [Stage 5]
#   sync_n_link0       conduit          (1-bit input ← FMC SYNC0 from DAC)      [Stage 5]
#   sync_n_link1       conduit          (1-bit input ← FMC SYNC1 from DAC)      [Stage 5]
#   tx_serial_link0    conduit          (4-bit output → FMC_TX0..TX3 SERDIN)    [Stage 5]
#   tx_serial_link1    conduit          (4-bit output → FMC_TX4..TX7 SERDIN)    [Stage 5]
#   txphy_clk_out      conduit          (4-bit output ← GTS link0 PMA clk, [0]
#                                        loops back through top SV to
#                                        jesd_tx_link_clk sink)                  [Stage 5]

package require -exact qsys 14.0

# -----------------------------------------------------------------------------
# Output path
# -----------------------------------------------------------------------------
# qsys-script's stock Tcl interpreter blocks [file normalize], so we use
# raw path joining. REPO_ROOT must be set by the caller (build.tcl does
# this from projects/agilex5_devkit/) or fall back to two-up from cwd.
if {[info exists ::env(REPO_ROOT)]} {
  set repo_root $::env(REPO_ROOT)
} else {
  set repo_root [file join [pwd] .. ..]
}
set output_qsys [file join $repo_root ip dac_subsys dac_subsys.qsys]

# -----------------------------------------------------------------------------
# Create a fresh system. If a stale .qsys exists, delete it so we never
# accidentally load + append to a previous version.
# -----------------------------------------------------------------------------
if {[file exists $output_qsys]} {
  file delete -force $output_qsys
}

create_system dac_subsys
set_project_property DEVICE_FAMILY {Agilex 5}
set_project_property DEVICE        {A5ED065BB32AE6SR0}

# =============================================================================
# Clock + reset bridges (boundary primitives)
# =============================================================================
add_instance u_clk_bridge_axi altera_clock_bridge
set_instance_parameter_value u_clk_bridge_axi EXPLICIT_CLOCK_RATE 100000000
set_instance_parameter_value u_clk_bridge_axi NUM_CLOCK_OUTPUTS   1

add_instance u_clk_bridge_jesd altera_clock_bridge
set_instance_parameter_value u_clk_bridge_jesd EXPLICIT_CLOCK_RATE 312500000
set_instance_parameter_value u_clk_bridge_jesd NUM_CLOCK_OUTPUTS   1

# Stage 5 (merged) added: transceiver reference clock bridges. One per
# transceiver tile -- the AD9176-FMC-EBZ uses GBTCLK0 (UX 4B, FPGA AP16/AP21)
# for link 0 (FMC_TX0..TX3 = lanes in UX 4B) and GBTCLK1 (UX 4C,
# FPGA AV16/AV21) for link 1 (FMC_TX4..TX7 = lanes in UX 4C). Cross-tile
# refclk routing is not supported on Agilex 5 GTS (see
# [doc/potential_issues.md ISSUE-015]) so each link needs its own refclk
# pad in the matching tile. Both clocks are 312.5 MHz (HMC7044 generates
# both from the same on-board reference; phase relationship is preserved).
add_instance u_xcvr_refclk altera_clock_bridge
set_instance_parameter_value u_xcvr_refclk EXPLICIT_CLOCK_RATE 312500000
set_instance_parameter_value u_xcvr_refclk NUM_CLOCK_OUTPUTS   1

add_instance u_xcvr_refclk_4c altera_clock_bridge
set_instance_parameter_value u_xcvr_refclk_4c EXPLICIT_CLOCK_RATE 312500000
set_instance_parameter_value u_xcvr_refclk_4c NUM_CLOCK_OUTPUTS   1

add_instance u_rst_bridge_axi altera_reset_bridge
set_instance_parameter_value u_rst_bridge_axi ACTIVE_LOW_RESET   0
set_instance_parameter_value u_rst_bridge_axi SYNCHRONOUS_EDGES  deassert
set_instance_parameter_value u_rst_bridge_axi NUM_RESET_OUTPUTS  1
set_instance_parameter_value u_rst_bridge_axi USE_RESET_REQUEST  0

add_instance u_rst_bridge_jesd altera_reset_bridge
set_instance_parameter_value u_rst_bridge_jesd ACTIVE_LOW_RESET   0
set_instance_parameter_value u_rst_bridge_jesd SYNCHRONOUS_EDGES  deassert
set_instance_parameter_value u_rst_bridge_jesd NUM_RESET_OUTPUTS  1
set_instance_parameter_value u_rst_bridge_jesd USE_RESET_REQUEST  0

# Stage 5 (merged) added: active-low reset bridges for the GTS IPs which
# expect rst_n inputs (jesd204_tx_avs_rst_n, jesd204_tx_rst_n). Each pair is
# wired externally to the same physical reset as its high-active counterpart.
add_instance u_rst_bridge_axi_n altera_reset_bridge
set_instance_parameter_value u_rst_bridge_axi_n ACTIVE_LOW_RESET   1
set_instance_parameter_value u_rst_bridge_axi_n SYNCHRONOUS_EDGES  deassert
set_instance_parameter_value u_rst_bridge_axi_n NUM_RESET_OUTPUTS  1
set_instance_parameter_value u_rst_bridge_axi_n USE_RESET_REQUEST  0

add_instance u_rst_bridge_jesd_n altera_reset_bridge
set_instance_parameter_value u_rst_bridge_jesd_n ACTIVE_LOW_RESET   1
set_instance_parameter_value u_rst_bridge_jesd_n SYNCHRONOUS_EDGES  deassert
set_instance_parameter_value u_rst_bridge_jesd_n NUM_RESET_OUTPUTS  1
set_instance_parameter_value u_rst_bridge_jesd_n USE_RESET_REQUEST  0

# Reset bridges need their own clk input wired
add_connection u_clk_bridge_axi.out_clk    u_rst_bridge_axi.clk
add_connection u_clk_bridge_jesd.out_clk   u_rst_bridge_jesd.clk
add_connection u_clk_bridge_axi.out_clk    u_rst_bridge_axi_n.clk
add_connection u_clk_bridge_jesd.out_clk   u_rst_bridge_jesd_n.clk

# =============================================================================
# External CSR entry point  Avalon-MM bridge ('axi_csr' for continuity
# with PLAN.md Appendix B; the actual protocol on the external face is
# Avalon-MM, and Qsys auto-inserts an AXI-Lite/AXI4 adapter in Stage 4
# when this slave is connected to the LWH2F AXI4 master in baseline_top.)
# 14-bit byte address  16 KB span (0x0000-0x3FFF).
# =============================================================================
add_instance u_csr_bridge altera_avalon_mm_bridge
set_instance_parameter_value u_csr_bridge DATA_WIDTH             32
set_instance_parameter_value u_csr_bridge SYMBOL_WIDTH           8
set_instance_parameter_value u_csr_bridge ADDRESS_WIDTH          14
set_instance_parameter_value u_csr_bridge ADDRESS_UNITS          SYMBOLS
set_instance_parameter_value u_csr_bridge USE_AUTO_ADDRESS_WIDTH 0
set_instance_parameter_value u_csr_bridge MAX_BURST_SIZE         1
set_instance_parameter_value u_csr_bridge BURSTCOUNT_WIDTH       1
set_instance_parameter_value u_csr_bridge PIPELINE_COMMAND       1
set_instance_parameter_value u_csr_bridge PIPELINE_RESPONSE      1
set_instance_parameter_value u_csr_bridge USE_RESPONSE           0
set_instance_parameter_value u_csr_bridge SYNC_RESET             0
set_instance_parameter_value u_csr_bridge USE_WRITERESPONSE      0
add_connection u_clk_bridge_axi.out_clk     u_csr_bridge.clk
add_connection u_rst_bridge_axi.out_reset   u_csr_bridge.reset

# =============================================================================
# u_dac_controller_0  Phase A IP (Stage 2 component)
# =============================================================================
add_instance u_dac_controller_0 dac_controller_0
set_instance_parameter_value u_dac_controller_0 G_LUT_DEPTH 1024
add_connection u_clk_bridge_axi.out_clk    u_dac_controller_0.clock_sink
add_connection u_clk_bridge_jesd.out_clk   u_dac_controller_0.jesd_tx_link_clk
add_connection u_rst_bridge_axi.out_reset  u_dac_controller_0.reset_sink
add_connection u_csr_bridge.m0             u_dac_controller_0.lwhpm2fpga
set_connection_parameter_value \
    u_csr_bridge.m0/u_dac_controller_0.lwhpm2fpga baseAddress 0x0000

# =============================================================================
# u_spi_master  Avalon-MM SPI Master to AD9176 (2 CS, mode 0, 25 MHz, 24 bit)
# 24-bit transfers cover AD9176 (16-bit addr + 8-bit data) in one frame.
# 25 MHz = 100 MHz / 4  (well below AD9176's 50 MHz SCK ceiling).
# =============================================================================
add_instance u_spi_master altera_avalon_spi
set_instance_parameter_value u_spi_master masterSPI                            true
set_instance_parameter_value u_spi_master numberOfSlaves                       2
set_instance_parameter_value u_spi_master dataWidth                            24
set_instance_parameter_value u_spi_master targetClockRate                      25000000
set_instance_parameter_value u_spi_master clockPolarity                        0
set_instance_parameter_value u_spi_master clockPhase                           0
set_instance_parameter_value u_spi_master lsbOrderedFirst                      false
set_instance_parameter_value u_spi_master disableAvalonFlowControl             false
set_instance_parameter_value u_spi_master insertSync                           false
set_instance_parameter_value u_spi_master insertDelayBetweenSlaveSelectAndSClk false
add_connection u_clk_bridge_axi.out_clk   u_spi_master.clk
add_connection u_rst_bridge_axi.out_reset u_spi_master.reset
add_connection u_csr_bridge.m0            u_spi_master.spi_control_port
set_connection_parameter_value \
    u_csr_bridge.m0/u_spi_master.spi_control_port baseAddress 0x1000

# =============================================================================
# u_tx_en_pio  2-bit output PIO  drives FMC_TXEN_0/1
# =============================================================================
add_instance u_tx_en_pio altera_avalon_pio
set_instance_parameter_value u_tx_en_pio direction   Output
set_instance_parameter_value u_tx_en_pio width       2
set_instance_parameter_value u_tx_en_pio captureEdge false
set_instance_parameter_value u_tx_en_pio generateIRQ false
set_instance_parameter_value u_tx_en_pio resetValue  0
add_connection u_clk_bridge_axi.out_clk   u_tx_en_pio.clk
add_connection u_rst_bridge_axi.out_reset u_tx_en_pio.reset
add_connection u_csr_bridge.m0            u_tx_en_pio.s1
set_connection_parameter_value \
    u_csr_bridge.m0/u_tx_en_pio.s1 baseAddress 0x1100

# =============================================================================
# u_pe_ctrl_pio  1-bit output PIO  drives FMC_PE_CTRL
# =============================================================================
add_instance u_pe_ctrl_pio altera_avalon_pio
set_instance_parameter_value u_pe_ctrl_pio direction   Output
set_instance_parameter_value u_pe_ctrl_pio width       1
set_instance_parameter_value u_pe_ctrl_pio captureEdge false
set_instance_parameter_value u_pe_ctrl_pio generateIRQ false
set_instance_parameter_value u_pe_ctrl_pio resetValue  0
add_connection u_clk_bridge_axi.out_clk   u_pe_ctrl_pio.clk
add_connection u_rst_bridge_axi.out_reset u_pe_ctrl_pio.reset
add_connection u_csr_bridge.m0            u_pe_ctrl_pio.s1
set_connection_parameter_value \
    u_csr_bridge.m0/u_pe_ctrl_pio.s1 baseAddress 0x1110

# =============================================================================
# u_dac_status_pio  32-bit input PIO with edge capture
# Captures transient transitions on FMC presence/power-good + JESD status
# bits so HPS software can clear interrupts without missing edges.
# =============================================================================
add_instance u_dac_status_pio altera_avalon_pio
set_instance_parameter_value u_dac_status_pio direction   Input
set_instance_parameter_value u_dac_status_pio width       32
set_instance_parameter_value u_dac_status_pio captureEdge true
set_instance_parameter_value u_dac_status_pio edgeType    ANY
set_instance_parameter_value u_dac_status_pio generateIRQ false
add_connection u_clk_bridge_axi.out_clk   u_dac_status_pio.clk
add_connection u_rst_bridge_axi.out_reset u_dac_status_pio.reset
add_connection u_csr_bridge.m0            u_dac_status_pio.s1
set_connection_parameter_value \
    u_csr_bridge.m0/u_dac_status_pio.s1 baseAddress 0x1120

# =============================================================================
# u_spi_en_pio  1-bit output PIO  drives FMC_SPI_EN (level-shifter enable)
# Reset value 0 = SPI buffer disabled at FPGA reset; HPS asserts after VADJ
# verified. Stage 4 addition.
# =============================================================================
add_instance u_spi_en_pio altera_avalon_pio
set_instance_parameter_value u_spi_en_pio direction   Output
set_instance_parameter_value u_spi_en_pio width       1
set_instance_parameter_value u_spi_en_pio captureEdge false
set_instance_parameter_value u_spi_en_pio generateIRQ false
set_instance_parameter_value u_spi_en_pio resetValue  0
add_connection u_clk_bridge_axi.out_clk   u_spi_en_pio.clk
add_connection u_rst_bridge_axi.out_reset u_spi_en_pio.reset
add_connection u_csr_bridge.m0            u_spi_en_pio.s1
set_connection_parameter_value \
    u_csr_bridge.m0/u_spi_en_pio.s1 baseAddress 0x1130

# =============================================================================
# u_pg_c2m_pio  1-bit output PIO  drives FMC_PG_C2M (FPGA card power-good
# back to the AD9176 mezzanine). Reset value 0 so we don't lie about power
# until HPS has confirmed pg_m2c is high. Stage 4 addition.
# =============================================================================
add_instance u_pg_c2m_pio altera_avalon_pio
set_instance_parameter_value u_pg_c2m_pio direction   Output
set_instance_parameter_value u_pg_c2m_pio width       1
set_instance_parameter_value u_pg_c2m_pio captureEdge false
set_instance_parameter_value u_pg_c2m_pio generateIRQ false
set_instance_parameter_value u_pg_c2m_pio resetValue  0
add_connection u_clk_bridge_axi.out_clk   u_pg_c2m_pio.clk
add_connection u_rst_bridge_axi.out_reset u_pg_c2m_pio.reset
add_connection u_csr_bridge.m0            u_pg_c2m_pio.s1
set_connection_parameter_value \
    u_csr_bridge.m0/u_pg_c2m_pio.s1 baseAddress 0x1140

# =============================================================================
# u_jesd_stub  -- non-data JESD conduit terminator (Stage 5 (merged) shrink)
# Terminates the status/refclk/csr/pio/tx_enbl conduits of u_dac_controller_0
# that have no native counterpart on the Intel GTS JESD204B IP. The two AVST
# data paths (jesd_link0_data, jesd_link1_data) flow to u_jesd_link0 and
# u_jesd_link1 below, not here.
# =============================================================================
add_instance u_jesd_stub jesd_stub
add_connection u_clk_bridge_jesd.out_clk   u_jesd_stub.jesd_tx_link_clk
add_connection u_rst_bridge_jesd.out_reset u_jesd_stub.reset_sink

add_connection u_dac_controller_0.jesd_link0_status u_jesd_stub.jesd_link0_status
add_connection u_dac_controller_0.jesd_link1_status u_jesd_stub.jesd_link1_status
add_connection u_dac_controller_0.jesd_reset_seq    u_jesd_stub.jesd_reset_seq
add_connection u_dac_controller_0.jesd_refclk_ctrl  u_jesd_stub.jesd_refclk_ctrl
add_connection u_dac_controller_0.jesd_csr_readback u_jesd_stub.jesd_csr_readback
add_connection u_dac_controller_0.pio_control       u_jesd_stub.pio_control
add_connection u_dac_controller_0.pio_status        u_jesd_stub.pio_status
add_connection u_dac_controller_0.tx_enbl           u_jesd_stub.tx_enbl

# =============================================================================
# u_jesd_link0, u_jesd_link1  -- Intel JESD204B GTS Subsystem IPs (Stage 5)
#
# Each instance carries L=4 lanes at 12.5 Gbps lane rate (mode-4 spec:
# M=4 converters, F=2 octets/frame, S=1 sample/converter/frame, NP=16,
# K=32, HD=1, SCR=1, CF=0, CS=0, Subclass 1). The two instances together
# implement the AD9176's dual-link mode (4 converters per link, 2 links =
# 8 total converters externally). LIDs are 0..3 for link 0, 4..7 for link 1.
#
# Lane rate derivation: per-lane bit rate = (M * NP * fs * 10) / (L * 8)
# For M=4, L=4, NP=16, fs=625 MSPS per-converter: lane rate = 20*fs = 12.5 Gbps.
# DAC sample rate post 4x interpolation = 4 * 625 = 2.5 GSPS (well within
# AD9176 12.6 GSPS max).
#
# Clocking (clocking_mode=PMA, default):
#   pll_refclk  <- u_xcvr_refclk.out_clk (FMC GBTCLK0_M2C, 312.5 MHz HSST
#                  refclk pad). GTS PMA PLL multiplies x40 -> 12.5 Gbps.
#   txlink_clk  <- u_clk_bridge_jesd.out_clk (312.5 MHz, looped back at top
#                  SV from u_jesd_link0.txphy_clk[0] via the txphy_clk_out
#                  conduit). Both IPs share the same link clock so the AVST
#                  link sinks are isomorphic to each other.
#   jesd204_tx_avs_clk <- u_clk_bridge_axi.out_clk (100 MHz fabric).
#
# Resets:
#   jesd204_tx_avs_rst_n <- u_rst_bridge_axi_n.out_reset (active-low AXI rst)
#   jesd204_tx_rst_n     <- u_rst_bridge_jesd_n.out_reset (active-low JESD rst)
#
# Self-loop: each IP's jesd204_tx_dev_sync_n output feeds its own
# jesd204_tx_mdev_sync_n input. This is the standard pattern when there is
# no multi-device sync requirement above this subsystem (the AD9176 acts as
# the single converter device per JESD link).
# =============================================================================
add_instance u_jesd_link0 intel_jesd204b_gts
set_instance_parameter_value u_jesd_link0 DATA_PATH            TX
set_instance_parameter_value u_jesd_link0 wrapper_opt          base_phy
set_instance_parameter_value u_jesd_link0 clocking_mode        PMA
set_instance_parameter_value u_jesd_link0 JESDV                1
set_instance_parameter_value u_jesd_link0 SUBCLASSV            1
set_instance_parameter_value u_jesd_link0 lane_rate            12500.0
set_instance_parameter_value u_jesd_link0 d_refclk_freq        312.5
# PMA AVMM reconfig interface OFF: Stage 5 (merged) does not need runtime
# PMA register access (Stage 7 brings up AD9176 + JESD via SPI/CSR only).
# Setting this true requires reconfig_xcvr_clk + reconfig_xcvr_reset
# connections, which aren't useful at this stage.
set_instance_parameter_value u_jesd_link0 pll_reconfig_enable  false
set_instance_parameter_value u_jesd_link0 rcfg_jtag_enable     false
set_instance_parameter_value u_jesd_link0 L                    4
set_instance_parameter_value u_jesd_link0 M                    4
set_instance_parameter_value u_jesd_link0 F                    2
set_instance_parameter_value u_jesd_link0 N                    16
set_instance_parameter_value u_jesd_link0 N_PRIME              16
set_instance_parameter_value u_jesd_link0 S                    1
set_instance_parameter_value u_jesd_link0 K                    32
set_instance_parameter_value u_jesd_link0 SCR                  1
set_instance_parameter_value u_jesd_link0 CS                   0
set_instance_parameter_value u_jesd_link0 CF                   0
set_instance_parameter_value u_jesd_link0 HD                   1
set_instance_parameter_value u_jesd_link0 DID                  0
set_instance_parameter_value u_jesd_link0 BID                  0
set_instance_parameter_value u_jesd_link0 LID0                 0
set_instance_parameter_value u_jesd_link0 LID1                 1
set_instance_parameter_value u_jesd_link0 LID2                 2
set_instance_parameter_value u_jesd_link0 LID3                 3

add_instance u_jesd_link1 intel_jesd204b_gts
set_instance_parameter_value u_jesd_link1 DATA_PATH            TX
set_instance_parameter_value u_jesd_link1 wrapper_opt          base_phy
set_instance_parameter_value u_jesd_link1 clocking_mode        PMA
set_instance_parameter_value u_jesd_link1 JESDV                1
set_instance_parameter_value u_jesd_link1 SUBCLASSV            1
set_instance_parameter_value u_jesd_link1 lane_rate            12500.0
set_instance_parameter_value u_jesd_link1 d_refclk_freq        312.5
set_instance_parameter_value u_jesd_link1 pll_reconfig_enable  false
set_instance_parameter_value u_jesd_link1 rcfg_jtag_enable     false
set_instance_parameter_value u_jesd_link1 L                    4
set_instance_parameter_value u_jesd_link1 M                    4
set_instance_parameter_value u_jesd_link1 F                    2
set_instance_parameter_value u_jesd_link1 N                    16
set_instance_parameter_value u_jesd_link1 N_PRIME              16
set_instance_parameter_value u_jesd_link1 S                    1
set_instance_parameter_value u_jesd_link1 K                    32
set_instance_parameter_value u_jesd_link1 SCR                  1
set_instance_parameter_value u_jesd_link1 CS                   0
set_instance_parameter_value u_jesd_link1 CF                   0
set_instance_parameter_value u_jesd_link1 HD                   1
set_instance_parameter_value u_jesd_link1 DID                  1
set_instance_parameter_value u_jesd_link1 BID                  0
set_instance_parameter_value u_jesd_link1 LID0                 4
set_instance_parameter_value u_jesd_link1 LID1                 5
set_instance_parameter_value u_jesd_link1 LID2                 6
set_instance_parameter_value u_jesd_link1 LID3                 7

# Clock connections (per-tile refclks to avoid Agilex 5 GTS cross-tile
# refclk routing limitation; ISSUE-015).
add_connection u_xcvr_refclk.out_clk         u_jesd_link0.pll_refclk
add_connection u_xcvr_refclk_4c.out_clk      u_jesd_link1.pll_refclk
add_connection u_clk_bridge_axi.out_clk      u_jesd_link0.jesd204_tx_avs_clk
add_connection u_clk_bridge_axi.out_clk      u_jesd_link1.jesd204_tx_avs_clk
add_connection u_clk_bridge_jesd.out_clk     u_jesd_link0.txlink_clk
add_connection u_clk_bridge_jesd.out_clk     u_jesd_link1.txlink_clk

# Reset connections (active-low for the GTS IP, sourced from u_rst_bridge_*_n)
add_connection u_rst_bridge_axi_n.out_reset  u_jesd_link0.jesd204_tx_avs_rst_n
add_connection u_rst_bridge_axi_n.out_reset  u_jesd_link1.jesd204_tx_avs_rst_n
add_connection u_rst_bridge_jesd_n.out_reset u_jesd_link0.jesd204_tx_rst_n
add_connection u_rst_bridge_jesd_n.out_reset u_jesd_link1.jesd204_tx_rst_n

# CSR slave: link 0 at 0x2000 (4 KB), link 1 at 0x3000 (4 KB).
add_connection u_csr_bridge.m0               u_jesd_link0.jesd204_tx_avs
set_connection_parameter_value \
    u_csr_bridge.m0/u_jesd_link0.jesd204_tx_avs baseAddress 0x2000
add_connection u_csr_bridge.m0               u_jesd_link1.jesd204_tx_avs
set_connection_parameter_value \
    u_csr_bridge.m0/u_jesd_link1.jesd204_tx_avs baseAddress 0x3000

# AVST data: dac_controller_0 sources -> GTS IPs sinks.
add_connection u_dac_controller_0.jesd_link0_data u_jesd_link0.jesd204_tx_link
add_connection u_dac_controller_0.jesd_link1_data u_jesd_link1.jesd204_tx_link

# dev_sync_n self-loop (no multi-device sync above this subsystem).
add_connection u_jesd_link0.jesd204_tx_dev_sync_n  u_jesd_link0.jesd204_tx_mdev_sync_n
add_connection u_jesd_link1.jesd204_tx_dev_sync_n  u_jesd_link1.jesd204_tx_mdev_sync_n

# =============================================================================
# Exported interfaces
# =============================================================================
add_interface clock_sink_clk clock sink
set_interface_property clock_sink_clk EXPORT_OF u_clk_bridge_axi.in_clk

add_interface jesd_tx_link_clk clock sink
set_interface_property jesd_tx_link_clk EXPORT_OF u_clk_bridge_jesd.in_clk

add_interface xcvr_refclk clock sink
set_interface_property xcvr_refclk EXPORT_OF u_xcvr_refclk.in_clk

add_interface xcvr_refclk_4c clock sink
set_interface_property xcvr_refclk_4c EXPORT_OF u_xcvr_refclk_4c.in_clk

add_interface axi_reset reset sink
set_interface_property axi_reset EXPORT_OF u_rst_bridge_axi.in_reset

add_interface jesd_reset reset sink
set_interface_property jesd_reset EXPORT_OF u_rst_bridge_jesd.in_reset

add_interface axi_reset_n reset sink
set_interface_property axi_reset_n EXPORT_OF u_rst_bridge_axi_n.in_reset

add_interface jesd_reset_n reset sink
set_interface_property jesd_reset_n EXPORT_OF u_rst_bridge_jesd_n.in_reset

add_interface axi_csr avalon slave
set_interface_property axi_csr EXPORT_OF u_csr_bridge.s0

add_interface spi conduit end
set_interface_property spi EXPORT_OF u_spi_master.external

add_interface tx_en conduit end
set_interface_property tx_en EXPORT_OF u_tx_en_pio.external_connection

add_interface pe_ctrl conduit end
set_interface_property pe_ctrl EXPORT_OF u_pe_ctrl_pio.external_connection

add_interface spi_en conduit end
set_interface_property spi_en EXPORT_OF u_spi_en_pio.external_connection

add_interface pg_c2m conduit end
set_interface_property pg_c2m EXPORT_OF u_pg_c2m_pio.external_connection

add_interface dac_status conduit end
set_interface_property dac_status EXPORT_OF u_dac_status_pio.external_connection

# =============================================================================
# Stage 5 (merged) added JESD GTS external interfaces
# =============================================================================
# SYSREF: one 1-bit conduit per IP (sourced from sysref_capture.vhd at top SV
# and tied to the same captured signal). Each IP's sysref conduit is the
# IP's `sysref` interface (declared in j204b_gts_ports.csv as 1-bit input).
add_interface sysref_link0 conduit end
set_interface_property sysref_link0 EXPORT_OF u_jesd_link0.jesd204_tx_sysref

add_interface sysref_link1 conduit end
set_interface_property sysref_link1 EXPORT_OF u_jesd_link1.jesd204_tx_sysref

# SYNC_N: from FMC, driven by AD9176 (RX side) -> sampled by FPGA TX.
# j204b_gts_ports.csv line 21: jesd204_tx_sync_n is an INPUT to the TX IP.
add_interface sync_n_link0 conduit end
set_interface_property sync_n_link0 EXPORT_OF u_jesd_link0.jesd204_tx_sync_n

add_interface sync_n_link1 conduit end
set_interface_property sync_n_link1 EXPORT_OF u_jesd_link1.jesd204_tx_sync_n

# TX serial data: 4 lanes per IP, exported as conduit (the GTS IP's
# tx_serial_data and tx_serial_data_n are common_conduit outputs, width $L).
add_interface tx_serial_link0 conduit end
set_interface_property tx_serial_link0 EXPORT_OF u_jesd_link0.tx_serial_data

add_interface tx_serial_link0_n conduit end
set_interface_property tx_serial_link0_n EXPORT_OF u_jesd_link0.tx_serial_data_n

add_interface tx_serial_link1 conduit end
set_interface_property tx_serial_link1 EXPORT_OF u_jesd_link1.tx_serial_data

add_interface tx_serial_link1_n conduit end
set_interface_property tx_serial_link1_n EXPORT_OF u_jesd_link1.tx_serial_data_n

# txphy_clk loopback: u_jesd_link0.txphy_clk[0] feeds back to top SV which
# drives jesd_tx_link_clk back into this subsystem (and into u_jesd_link1's
# txlink_clk indirectly via u_clk_bridge_jesd.out_clk).
add_interface txphy_clk_out conduit end
set_interface_property txphy_clk_out EXPORT_OF u_jesd_link0.txphy_clk

# =============================================================================
# Save
# =============================================================================
save_system $output_qsys
puts "Wrote $output_qsys"
