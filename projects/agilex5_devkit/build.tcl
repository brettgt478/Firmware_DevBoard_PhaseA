# build.tcl  Phase B Quartus entry script for agilex5_devkit
#
# Modes:
#   quartus_sh -t build.tcl                  -> IP gen + full compile + asm (.sof)
#   quartus_sh -t build.tcl --project-only   -> IP gen only (no synthesis)
#
# Always cleans previous outputs first per CLAUDE.md SS3:
#   "Every build TCL script must clean its previous outputs ... before starting.
#    Never accumulate stale builds."
#
# Project + revision are both 'agilex5_devkit' (qpf basename + revision name in qpf).

set project_only 0
foreach arg $::argv {
    if {$arg eq "--project-only"} { set project_only 1 }
}

set proj agilex5_devkit
set rev  agilex5_devkit

# Hard clean  prevent stale artifact builds.
# Paths are relative to projects/agilex5_devkit/ (cwd when this script runs).
set clean_dirs [list \
    output_files \
    db \
    incremental_db \
    qdb \
    tmp-clearbox \
    dni \
    sim_setup_$rev \
    ../../ip/dac_subsys/dac_subsys \
    ../../ip/dac_controller_0/dac_controller_0 \
]
foreach d $clean_dirs {
    if {[file exists $d]} {
        puts "build.tcl: cleaning $d"
        file delete -force $d
    }
}

# --- IP / Platform Designer generation ------------------------------------
# Generates synthesis IP for the qsys systems referenced in the qsf
# (hps_subsys, fabric_subsys, shell_subsys, baseline_top, niosv_subsys; and
# in later stages also dac_subsys). Simulation outputs land in sim_setup_<rev>/.
puts "build.tcl: running quartus_ipgenerate $proj -c $rev"
if {[catch {exec >@stdout 2>@stderr quartus_ipgenerate $proj -c $rev \
                --synthesis=verilog \
                --simulation=verilog \
                --simulator=modelsim \
                --clear_ip_generation_dirs} result]} {
    puts stderr "build.tcl: quartus_ipgenerate FAILED:"
    puts stderr $result
    exit 1
}

if {$project_only} {
    puts "build.tcl: --project-only requested, stopping after IP generation"
    exit 0
}

# --- Full compile flow ----------------------------------------------------
# quartus_sh --flow compile runs: ipgenerate -> syn -> fit -> sta -> pow
# Assembler is gated by FLOW_DISABLE_ASSEMBLER ON in the qsf, so run it
# explicitly to produce the .sof.
puts "build.tcl: running quartus_sh --flow compile $proj -c $rev"
if {[catch {exec >@stdout 2>@stderr quartus_sh --flow compile $proj -c $rev} result]} {
    puts stderr "build.tcl: quartus_sh --flow compile FAILED:"
    puts stderr $result
    exit 1
}

puts "build.tcl: running quartus_asm $proj -c $rev"
if {[catch {exec >@stdout 2>@stderr quartus_asm $proj -c $rev} result]} {
    puts stderr "build.tcl: quartus_asm FAILED:"
    puts stderr $result
    exit 1
}

set sof output_files/$rev.sof
if {[file exists $sof]} {
    puts "build.tcl: complete. SOF at $sof"
    exit 0
} else {
    puts stderr "build.tcl: expected SOF $sof not produced"
    exit 1
}
