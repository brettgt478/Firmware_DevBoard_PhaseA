# fmc_io.sdc -- Stage 5 (merged) FMC I/O timing constraints
#
# AD9176 device clocks come back to the FPGA via FMC GBTCLK0/1_M2C.
# 312.5 MHz (3.200 ns) each = Agilex 5 GTS PMA PLL refclk for 12.5 Gbps
# lane rate (refclk x40 = lane rate). The AD9176-FMC-EBZ HMC7044 derives
# both from its on-board reference oscillator (PLL2; both refclks are
# phase-locked to a common reference). GBTCLK0 drives u_jesd_link0 (UX 4B
# transceiver tile), GBTCLK1 drives u_jesd_link1 (UX 4C); see ISSUE-015.
create_clock -name fmc_gbtclk0 -period 3.200 [get_ports fmc_gbtclk0_p]
create_clock -name fmc_gbtclk1 -period 3.200 [get_ports fmc_gbtclk1_p]

# fmc_prsnt_n is an asynchronous, debounced housekeeping input (FMC card
# presence). It is sampled by fmc_handshake.sv in the fabric clock domain
# behind a synchronizer, so it has no timing relationship to any launch
# clock -- cut it. Clears Design Assistant TMC-20011 (Missing Input Delay,
# High) reported in agilex5_devkit.tq.drc.signoff.rpt.
set_false_path -from [get_ports fmc_prsnt_n] -to *

# SYNC_N inputs from the AD9176 (RX side) are quasi-static during JESD link
# bring-up; treat as asynchronous to the fabric domain. The signals are
# resampled into the JESD link clock by the GTS IP.
#
# NOTE: until the GTS Reset Sequencer lands (ISSUE-019), the txphy_clk
# loopback is stuck at 0, sysref_capture.vhd is swept, and these three FMC
# inputs are pruned as non-driving -- so these exceptions currently target
# empty collections (TMC-20025/20026). They self-heal once ISSUE-019 makes
# the JESD datapath real; do NOT delete them.
set_false_path -from [get_ports fmc_sync0] -to *
set_false_path -from [get_ports fmc_sync1] -to *

# SYSREF capture is asynchronous at the port; sysref_capture.vhd's 2-stage
# synchronizer handles metastability into the JESD link clock domain.
# Subclass-1 deterministic latency relies on the AD9176-FMC-EBZ source-sync
# SYSREF<->GBTCLK0 phasing on the AD9176 side, not on FPGA capture timing.
set_false_path -from [get_ports fmc_sysref] -to *
