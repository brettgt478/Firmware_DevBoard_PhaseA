# baseline_top_phaseb_patches.tcl
#
# Phase B patch script for projects/agilex5_devkit/baseline_top.qsys.
#
# Pattern (mirrors ip/dac_subsys/dac_subsys.tcl source-of-truth pattern):
#   baseline_top.upstream.qsys  -- frozen GHRD baseline snapshot (immutable)
#   baseline_top_phaseb_patches.tcl  -- this file (Phase B mutations as Tcl)
#   baseline_top.qsys           -- generated artifact = upstream + this patch
#
# build.tcl regenerates baseline_top.qsys whenever either of:
#   - baseline_top.upstream.qsys
#   - baseline_top_phaseb_patches.tcl
# is newer than the working baseline_top.qsys.
#
# Invocation (build.tcl already wires this up; only run manually for testing):
#   cd projects/agilex5_devkit
#   set env(REPO_ROOT) [pwd]/../..
#   qsys-script --new-quartus-project=scratch/baseline_top_patch_gen \
#               --search-path="../../ip/dac_controller_0/**/*,../../ip/jesd_stub/**/*,../../ip/dac_subsys/**/*,custom_ip/**/*,ip/fabric_subsys/**/*,ip/shell_subsys/**/*,$" \
#               --script=baseline_top_phaseb_patches.tcl
#
# -----------------------------------------------------------------------------
# Stage 4 patches:
#   - add_instance      u_dac_subsys (ip/dac_subsys/dac_subsys.qsys)
#   - add_connection    u_shell_subsys.lwhps2fpga -> u_dac_subsys.axi_csr @ 0x02000000
#   - add_connection    u_shell_subsys.system_clock -> u_dac_subsys.clock_sink_clk
#   - add_connection    u_shell_subsys.system_reset_n -> u_dac_subsys.axi_reset
#   - export conduits:  dac_spi, dac_tx_en, dac_pe_ctrl, dac_spi_en, dac_pg_c2m, dac_status
#
# Stage 5 (merged) patches (this run):
#   - Drop the system_clock -> jesd_tx_link_clk placeholder (Stage 4 stub);
#     jesd_tx_link_clk is now driven externally from the top-SV loopback of
#     u_jesd_link0.txphy_clk[0] via the exported dac_jesd_tx_link_clk sink.
#   - Drop the system_reset_n -> jesd_reset placeholder; jesd_reset and
#     jesd_reset_n are now exported as sinks so the top SV drives both from
#     the system reset (active-high + active-low halves).
#   - Add reset wiring: system_reset_n -> u_dac_subsys.axi_reset_n (active-low).
#   - Export sinks:  dac_xcvr_refclk (clock), dac_jesd_tx_link_clk (clock),
#                    dac_axi_reset_n (reset), dac_jesd_reset (reset),
#                    dac_jesd_reset_n (reset).
#   - Export conduits (JESD physical-layer pads + status):
#                    dac_sysref_link0, dac_sysref_link1,
#                    dac_sync_n_link0, dac_sync_n_link1,
#                    dac_tx_serial_link0, dac_tx_serial_link0_n,
#                    dac_tx_serial_link1, dac_tx_serial_link1_n,
#                    dac_txphy_clk_out.
# -----------------------------------------------------------------------------

package require -exact qsys 14.0

# Resolve paths. REPO_ROOT must be set by the caller (build.tcl does this).
if {[info exists ::env(REPO_ROOT)]} {
  set repo_root $::env(REPO_ROOT)
} else {
  set repo_root [file join [pwd] .. ..]
}
set proj_dir   [file join $repo_root projects agilex5_devkit]
set upstream   [file join $proj_dir baseline_top.upstream.qsys]
set working    [file join $proj_dir baseline_top.qsys]

# Always reset the working file from the frozen upstream snapshot so this
# script is fully idempotent (no chance of stacking duplicate connections).
if {![file exists $upstream]} {
  error "baseline_top.upstream.qsys missing at $upstream"
}
puts "patches: copying upstream -> working baseline_top.qsys"
file copy -force $upstream $working

# -----------------------------------------------------------------------------
# Load the working system and apply Stage 4 mutations.
# -----------------------------------------------------------------------------
load_system $working

# u_dac_subsys instance (Stage 3 .qsys; library name = "dac_subsys").
add_instance u_dac_subsys dac_subsys

# Clock + reset wiring (Stage 4 + 5 merged).
#   AXI control plane: system_clock (100 MHz) + system_reset_n (driven through
#   both the active-high axi_reset and active-low axi_reset_n bridges inside
#   dac_subsys).
#   JESD link clock and JESD reset are now external: jesd_tx_link_clk is
#   sourced from the top-SV loopback of u_jesd_link0.txphy_clk[0]; jesd_reset
#   and jesd_reset_n are driven from the system reset at the top SV.
#   GBTCLK0 transceiver refclk is also external (xcvr_refclk sink).
add_connection u_shell_subsys.system_clock   u_dac_subsys.clock_sink_clk
add_connection u_shell_subsys.system_reset_n u_dac_subsys.axi_reset
add_connection u_shell_subsys.system_reset_n u_dac_subsys.axi_reset_n

# LWH2F AXI4 master from HPS reaches the dac_subsys AXI CSR window at
# 0x0200_0000 (16 KB span). Qsys auto-inserts an AXI4-to-Avalon-MM adapter
# at the dac_subsys boundary (axi_csr is exported as Avalon-MM in
# ip/dac_subsys/dac_subsys.tcl).
add_connection u_shell_subsys.lwhps2fpga u_dac_subsys.axi_csr
set_connection_parameter_value \
    u_shell_subsys.lwhps2fpga/u_dac_subsys.axi_csr baseAddress 0x02000000

# -----------------------------------------------------------------------------
# Exported interfaces (propagate dac_subsys conduits to baseline_top boundary).
# -----------------------------------------------------------------------------
add_interface dac_spi conduit end
set_interface_property dac_spi EXPORT_OF u_dac_subsys.spi

add_interface dac_tx_en conduit end
set_interface_property dac_tx_en EXPORT_OF u_dac_subsys.tx_en

add_interface dac_pe_ctrl conduit end
set_interface_property dac_pe_ctrl EXPORT_OF u_dac_subsys.pe_ctrl

add_interface dac_spi_en conduit end
set_interface_property dac_spi_en EXPORT_OF u_dac_subsys.spi_en

add_interface dac_pg_c2m conduit end
set_interface_property dac_pg_c2m EXPORT_OF u_dac_subsys.pg_c2m

add_interface dac_status conduit end
set_interface_property dac_status EXPORT_OF u_dac_subsys.dac_status

# Stage 5 (merged) JESD external interfaces.
# Clock sinks for top-SV loopback / external refclk.
add_interface dac_xcvr_refclk clock sink
set_interface_property dac_xcvr_refclk EXPORT_OF u_dac_subsys.xcvr_refclk

add_interface dac_xcvr_refclk_4c clock sink
set_interface_property dac_xcvr_refclk_4c EXPORT_OF u_dac_subsys.xcvr_refclk_4c

add_interface dac_jesd_tx_link_clk clock sink
set_interface_property dac_jesd_tx_link_clk EXPORT_OF u_dac_subsys.jesd_tx_link_clk

# Reset sinks (active-low jesd_reset_n pair + active-high jesd_reset; the
# axi_reset_n pair is already driven internally by add_connection above).
add_interface dac_jesd_reset reset sink
set_interface_property dac_jesd_reset EXPORT_OF u_dac_subsys.jesd_reset

add_interface dac_jesd_reset_n reset sink
set_interface_property dac_jesd_reset_n EXPORT_OF u_dac_subsys.jesd_reset_n

# JESD physical-layer conduits (SYSREF, SYNC_N, TX serial pairs, txphy_clk).
add_interface dac_sysref_link0 conduit end
set_interface_property dac_sysref_link0 EXPORT_OF u_dac_subsys.sysref_link0

add_interface dac_sysref_link1 conduit end
set_interface_property dac_sysref_link1 EXPORT_OF u_dac_subsys.sysref_link1

add_interface dac_sync_n_link0 conduit end
set_interface_property dac_sync_n_link0 EXPORT_OF u_dac_subsys.sync_n_link0

add_interface dac_sync_n_link1 conduit end
set_interface_property dac_sync_n_link1 EXPORT_OF u_dac_subsys.sync_n_link1

add_interface dac_tx_serial_link0 conduit end
set_interface_property dac_tx_serial_link0 EXPORT_OF u_dac_subsys.tx_serial_link0

add_interface dac_tx_serial_link0_n conduit end
set_interface_property dac_tx_serial_link0_n EXPORT_OF u_dac_subsys.tx_serial_link0_n

add_interface dac_tx_serial_link1 conduit end
set_interface_property dac_tx_serial_link1 EXPORT_OF u_dac_subsys.tx_serial_link1

add_interface dac_tx_serial_link1_n conduit end
set_interface_property dac_tx_serial_link1_n EXPORT_OF u_dac_subsys.tx_serial_link1_n

add_interface dac_txphy_clk_out conduit end
set_interface_property dac_txphy_clk_out EXPORT_OF u_dac_subsys.txphy_clk_out

# -----------------------------------------------------------------------------
# Save the patched system.
# -----------------------------------------------------------------------------
save_system $working
puts "patches: wrote $working (upstream + Phase B Stage 4)"
