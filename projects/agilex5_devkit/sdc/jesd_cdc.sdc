# jesd_cdc.sdc -- Stage 5 (merged) JESD CDC constraints
#
# JESD link clock (312.5 MHz, sourced from u_jesd_link0.txphy_clk[0]
# loopback) is asynchronous to the AXI/fabric control clock (100 MHz from
# u_shell_subsys.system_clock). All CSR cross-domain reads use Phase A's
# documented 2-stage synchronizers and DcFifo (CLAUDE.md s6 #8).
#
# The clock name patterns are conservative -- they catch any clock node
# whose name contains the bridge instance name, which works for both
# top-level and per-instance clock objects emitted by the qsys flatten.
set_clock_groups -asynchronous \
  -group [get_clocks {*u_clk_bridge_jesd*}] \
  -group [get_clocks {*u_clk_bridge_axi*}]

# The transceiver reference clocks (GBTCLK0/1, both 312.5 MHz) are the
# sources for the txlink_clk loopback (via txphy_clk[0]) and the PMA PLLs;
# they must be asynchronous to the AXI clock domain. Group both with the
# AXI clock for false-path coverage. The two refclks are phase-locked to a
# common HMC7044 reference but the FPGA sees them as separate clock trees.
set_clock_groups -asynchronous \
  -group [get_clocks fmc_gbtclk0] \
  -group [get_clocks fmc_gbtclk1] \
  -group [get_clocks {*u_clk_bridge_axi*}]

# Internal GTS CDC paths between PMA and link layer are emitted by the
# JESD204B GTS IP into ip/dac_subsys/jesd204b_gts_ss/synthesis/*.sdc;
# this file only carries project-scope additions.
