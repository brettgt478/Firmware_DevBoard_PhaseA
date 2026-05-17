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
# Stage 4 patches (this run):
#   - add_instance      u_dac_subsys (ip/dac_subsys/dac_subsys.qsys)
#   - add_connection    u_shell_subsys.lwhps2fpga -> u_dac_subsys.axi_csr @ 0x02000000
#   - add_connection    u_shell_subsys.system_clock -> u_dac_subsys.clock_sink_clk
#   - add_connection    u_shell_subsys.system_clock -> u_dac_subsys.jesd_tx_link_clk  [Stage 6 rewires]
#   - add_connection    u_shell_subsys.system_reset_n -> u_dac_subsys.axi_reset
#   - add_connection    u_shell_subsys.system_reset_n -> u_dac_subsys.jesd_reset      [Stage 6 rewires]
#   - export conduits:  dac_spi, dac_tx_en, dac_pe_ctrl, dac_spi_en, dac_pg_c2m, dac_status
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

# Clock + reset wiring (Stage 4).
# system_clock (100 MHz) feeds both the AXI control path and the JESD-side
# clock_sink as a Stage 4 placeholder; Stage 6 reroutes jesd_tx_link_clk to
# the ~250 MHz JESD GTS link-layer clock.
add_connection u_shell_subsys.system_clock u_dac_subsys.clock_sink_clk
add_connection u_shell_subsys.system_clock u_dac_subsys.jesd_tx_link_clk
add_connection u_shell_subsys.system_reset_n u_dac_subsys.axi_reset
add_connection u_shell_subsys.system_reset_n u_dac_subsys.jesd_reset

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

# -----------------------------------------------------------------------------
# Save the patched system.
# -----------------------------------------------------------------------------
save_system $working
puts "patches: wrote $working (upstream + Phase B Stage 4)"
