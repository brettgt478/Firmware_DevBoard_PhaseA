# run_dac_subsys_tb.do -- Stage 8b integration TB driver.
#
# Mirrors the baseline runquesta.sh flow so we get the same compile
# order + library bindings the GHRD baseline TB relies on, then swaps
# in dac_subsys_tb as the top-level module.
#
# Run from projects/agilex5_devkit/sim/:
#   vsim -c -do run_dac_subsys_tb.do

file delete -force work
vlib work

# Force VHDL-2008 for Phase A RTL (msim_setup defaults to -93).
set USER_DEFINED_VHDL_COMPILE_OPTIONS "-2008"

# Pull in all baseline_top IP compile aliases (dev_com, com, elab).
set QSYS_SIMDIR ../baseline_top/sim
source $QSYS_SIMDIR/mentor/msim_setup.tcl

puts "== dev_com (Intel sim libs) =="
if {[catch { dev_com } err]} { puts "FAIL: dev_com -- $err"; quit -code 1 }
puts "== com (IP-generated) =="
if {[catch { com } err]} { puts "FAIL: com -- $err"; quit -code 2 }

# Top-level RTL not produced by qsys (mirrors runquesta.sh:75-77).
puts "== vlog top-level RTL =="
vlog -sv -work work ../src/debounce.sv
vlog -sv -work work ../src/clocks_and_resets.sv
vlog -sv -work work ../src/fmc_handshake.sv
vcom -2008 -work work ../src/sysref_capture.vhd
vlog -sv -work work ../agilex5_devkit.sv

# Local sim packages required by both baseline TB and dac_subsys_tb
# (runquesta.sh:78-79). Compile -work work so they land in the same
# library the TB scopes into.
puts "== vlog sim packages =="
vlog -sv -work work hps_h2f_pkg.sv
vlog -sv -work work hps_h2f_lw_pkg.sv

# The HPS AXI BFM packages (altera_axi_bfm_pkg, host_memory_class_pkg)
# live in the altera_lnsim_ver library that dev_com just populated.
# -L altera_lnsim_ver lets vlog resolve those package imports.
puts "== vlog dac_subsys_tb =="
if {[catch {
    vlog -sv -timescale 1ps/1ps -work work \
        -L altera_lnsim_ver \
        dac_subsys_tb.sv
} err]} {
    puts "FAIL: vlog dac_subsys_tb -- $err"; quit -code 3
}

# Shell-subsys IP files runquesta.sh compiles explicitly (the dev_com
# pass doesn't include user-PLL/user-rst-clkgate because they're outside
# the baseline_top.qsys sim manifest).
puts "== vlog shell_subsys leftovers =="
vlog -work work ../ip/shell_subsys/sys_pll/sim/sys_pll.v
vlog -work work ../ip/shell_subsys/user_rst_clkgate/sim/user_rst_clkgate.v
vlog -sv -work work \
    ../ip/shell_subsys/user_rst_clkgate/altera_s10_user_rst_clkgate_1949/sim/altera_s10_user_rst_clkgate.sv
foreach f [glob -nocomplain ../ip/shell_subsys/sys_pll/altera_iopll_*/synth/sys_pll_altera_iopll_*.v] {
    vlog -work work $f
}

# Elaborate via the msim_setup-emitted alias. USER_DEFINED_ELAB_OPTIONS
# suppress vsim warnings the baseline runquesta also suppresses
# (14408 = duplicate VPI macro, 16154 = unused signal).
set TOP_LEVEL_NAME dac_subsys_tb
set USER_DEFINED_ELAB_OPTIONS "-suppress 14408,16154 -voptargs=-svext=+adta"

puts "== elab =="
if {[catch { elab } err]} { puts "FAIL: elab -- $err"; quit -code 4 }

puts "== run -all =="
set NumericStdNoWarnings 1
if {[catch { run -all } err]} { puts "FAIL: run -- $err"; quit -code 5 }

quit -code 0
