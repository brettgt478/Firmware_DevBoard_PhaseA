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

# SYNC_N inputs from the AD9176 (RX side) are quasi-static during JESD link
# bring-up; treat as asynchronous to the fabric domain. The signals are
# resampled into the JESD link clock by the GTS IP.
set_false_path -from [get_ports fmc_sync0] -to *
set_false_path -from [get_ports fmc_sync1] -to *

# SYSREF capture is asynchronous at the port; sysref_capture.vhd's 2-stage
# synchronizer handles metastability into the JESD link clock domain.
# Subclass-1 deterministic latency relies on the AD9176-FMC-EBZ source-sync
# SYSREF<->GBTCLK0 phasing on the AD9176 side, not on FPGA capture timing.
set_false_path -from [get_ports fmc_sysref] -to *
