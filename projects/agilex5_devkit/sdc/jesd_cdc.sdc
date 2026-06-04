# jesd_cdc.sdc -- Stage 5 (merged) JESD CDC constraints  [clock names corrected]
#
# The JESD transceiver domain (GTS PMA / link clocks generated inside
# u_jesd_link0/1, plus the GBTCLK0/1 refclks and the txphy_clk[0] loopback)
# is asynchronous to the fabric AXI/control clock. All CSR cross-domain
# reads use Phase A's documented 2-stage synchronizers and DcFifo
# (CLAUDE.md s6 #8).
#
# WHY THE NAMES CHANGED: an altera_clock_bridge does NOT create a named
# clock -- it passes its source clock straight through -- so the previous
# `*u_clk_bridge_axi*` / `*u_clk_bridge_jesd*` filters matched ZERO clock
# objects. STA logged Warning 332174/332049 and the Design Assistant logged
# TMC-20025/20026, and the JESD<->AXI false-paths were never actually
# applied. The groups below use the real clock names reported by
# `report_clocks` (see output_files/agilex5_devkit.sta.rpt clock table):
#   fabric AXI clock : u_baseline_top|...|u_sys_pll|iopll_0_outclk0
#   refclks          : fmc_gbtclk0, fmc_gbtclk1
#   JESD xcvr clocks : every generated clock under u_dac_subsys|u_jesd_link0/1
#                      (o_tx_clkout, tx_user_clk1, divided_osc_clk, and the
#                       txphy_clk[0] loopback that re-enters as the link clk)
#
# All groups below are MUTUALLY asynchronous (each clock in its own -group),
# which is the safe direction for CDC exceptions: set_clock_groups only
# REMOVES timing analysis between groups, so this can never create a new
# failing path (PROMOTE_WARNING 332148 stays safe). It preserves the
# original intent (gbtclk0 async gbtclk1) and adds the fabric<->JESD/refclk
# async grouping that was previously a no-op. The two JESD link IPs share
# the txlink_clk loopback, so their clocks stay in one group (not cut from
# each other). Intra-transceiver CDC is governed by the GTS IP's own SDC.
#
# RE-CONFIRM AFTER ISSUE-019: the txphy_clk loopback clock only toggles once
# the GTS Reset Sequencer is added; re-run `report_clocks` /
# `report_clock_groups` then and verify every -group collection is non-empty
# and that no intended path was left uncut.
set_clock_groups -asynchronous \
  -group [get_clocks { u_baseline_top|u_shell_subsys|u_clks_and_rsts|clks_and_rsts|u_sys_pll|iopll_0_outclk0 }] \
  -group [get_clocks { fmc_gbtclk0 }] \
  -group [get_clocks { fmc_gbtclk1 }] \
  -group [get_clocks { *u_dac_subsys|u_jesd_link0* *u_dac_subsys|u_jesd_link1* }]

# Internal GTS CDC paths between PMA and link layer are emitted by the
# JESD204B GTS IP into ip/dac_subsys/jesd204b_gts_ss/synthesis/*.sdc;
# this file only carries project-scope additions.
