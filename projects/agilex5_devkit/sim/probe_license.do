# probe_license.do -- compile-only smoke test for Questa licensing.
#
# Sources the generated baseline_top msim_setup.tcl, then runs dev_com
# (compile vendor libs) and com (compile generated IP). Does NOT elab
# or simulate -- the goal is to find out whether Questa FSE / Pro can
# even *read* the JESD204B GTS IP simulation models before we invest
# in writing TBs.
#
# Run from projects/agilex5_devkit/sim/:
#   vsim -c -do probe_license.do

# Clean previous library so we don't get false PASS from cached compile
file delete -force work
vlib work

# Phase A RTL (vendored into dac_controller_0's sim/) uses VHDL-2008
# constructs (process(all), unconstrained subtype-indication on records).
# msim_setup.tcl defaults to VHDL-93; force -2008 BEFORE source so the
# alias is built with the right options. This is the same pattern the
# Phase A tb/ uses (vcom -2008 ...).
set USER_DEFINED_VHDL_COMPILE_OPTIONS "-2008"

# Quartus-generated IP simulation setup. Sets QSYS_SIMDIR + compiles
# every Intel sim lib + every IP under baseline_top.
set QSYS_SIMDIR ../baseline_top/sim
source $QSYS_SIMDIR/mentor/msim_setup.tcl

# dev_com: compile Intel simulation libraries (sim_lib + altera_*_partial)
puts "== probe_license.do: dev_com (Intel libs) =="
if {[catch { dev_com } err]} {
    puts "PROBE_FAIL: dev_com -- $err"
    quit -code 1
}

# com: compile all generated IP -- this is where JESD204B GTS would
# either pass or trip the FSE encryption / size wall.
puts "== probe_license.do: com (project IP) =="
if {[catch { com } err]} {
    puts "PROBE_FAIL: com -- $err"
    quit -code 2
}

puts "== probe_license.do: PROBE_PASS (all libs + IP compiled) =="
quit -code 0
