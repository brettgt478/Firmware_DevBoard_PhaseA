# tb/run_block_tbs.tcl  Phase A block-testbench regression for Stage 1 gate.
#
# Compiles all 10 Phase A VHDL files from ip/dac_controller_0/src/ plus the
# 8 block testbenches in tb/, then runs each testbench in -c (console) mode.
#
# Invocation (from repo root):
#   vsim -c -do "do tb/run_block_tbs.tcl; quit -f"
#
# Pass criterion: every TB completes with "SIMULATION PASSED" in its
# transcript and zero severity-failure assertions. Stage 1 gate per
# PLAN.md SS S1.

# --- Clean ---
if {[file exists work]} { vdel -all }
vlib work

if {[info exists ::env(REPO_ROOT)]} {
    set repo_root $::env(REPO_ROOT)
} else {
    set repo_root [file normalize [file join [file dirname [info script]] ..]]
}
set src_dir [file normalize [file join $repo_root ip dac_controller_0 src]]
set tb_dir  [file normalize [file join $repo_root tb]]

puts "run_block_tbs: src_dir = $src_dir"
puts "run_block_tbs: tb_dir  = $tb_dir"

# --- Compile RTL in dependency order ---
# Phase A uses direct entity instantiation (no component declarations),
# so leaf entities must be compiled before their parents. Order:
#   1. Package (always first)
#   2. Leaf modules with no inter-RTL deps
#   3. RegBank (uses package only)
#   4. Higher-level wrappers (axi_to_avmm wraps axi_lite_to_avmm)
#   5. dac_controller_0 (top, instantiates everything above)
set rtl_order [list \
    dac_controller_pkg.vhd \
    axi_lite_to_avmm.vhd \
    axi_to_avmm.vhd \
    dc_fifo.vhd \
    data_src_mux.vhd \
    reg_bank.vhd \
    sine_wave_gen.vhd \
    jesd_sync_controller.vhd \
    jesd_tx_manager.vhd \
    dac_controller_0.vhd \
]
foreach f $rtl_order {
    puts "run_block_tbs: compiling $f"
    vcom -2008 -quiet [file join $src_dir $f]
}

# --- Compile block testbenches ---
foreach f [lsort [glob -directory $tb_dir *_tb.vhd]] {
    puts "run_block_tbs: compiling [file tail $f]"
    vcom -2008 -quiet $f
}

# --- Run each testbench (entity name lookup by file) ---
set tb_list [list \
    SineWaveGen_tb \
    DataSrcMux_tb \
    DcFifo_tb \
    RegBank_tb \
    AxiLiteToAvmm_tb \
    JesdSyncController_tb \
    JesdTxManager_tb \
    DacController_tb \
]

set failures [list]
foreach tb $tb_list {
    puts ""
    puts "============================================================"
    puts "run_block_tbs: vsim work.$tb"
    puts "============================================================"
    set rc [catch {
        vsim -c -voptargs="+acc" -t ps work.$tb \
             -do "set NumericStdNoWarnings 1; run -all; quit -sim"
    } err]
    if {$rc != 0} {
        puts stderr "run_block_tbs: $tb: vsim returned error: $err"
        lappend failures $tb
    }
}

puts ""
puts "============================================================"
puts "run_block_tbs: summary"
puts "============================================================"
puts "TBs run    : [llength $tb_list]"
puts "TBs failed : [llength $failures]"
if {[llength $failures] > 0} {
    puts "Failed list: $failures"
    quit -code 1
}
puts "Stage 1 block-tb gate: PASS"
quit -code 0
