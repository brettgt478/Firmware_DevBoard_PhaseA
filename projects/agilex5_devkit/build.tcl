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
# NOTE on ip/dac_subsys/ip/ : NOT cleaned between builds.
# That tree holds per-instance .ip backing files written by qsys-script's
# save_system (with --quartus-project=agilex5_devkit.qpf). They are source
# artifacts on par with fabric_subsys's projects/agilex5_devkit/ip/fabric_subsys/*.ip.
# The regen step below rewrites them when dac_subsys.tcl is newer than the .qsys
# OR when the backing dir is missing. Cleaning them here without forcing regen
# would leave the .qsys referencing files that no longer exist (13 "undefined
# entity" synthesis errors).
foreach d $clean_dirs {
    if {[file exists $d]} {
        puts "build.tcl: cleaning $d"
        file delete -force $d
    }
}

# --- Regenerate dac_subsys.qsys from dac_subsys.tcl when stale ------------
# qsys-script wins source-of-truth status; the committed .qsys is the
# build-time artifact, regenerated whenever its .tcl source is newer (or
# the .qsys is missing). Regen happens BEFORE quartus_ipgenerate because
# ipgenerate parses the .qsys file referenced by the qsf.
set env(REPO_ROOT) [pwd]/../..

set dac_subsys_tcl  ../../ip/dac_subsys/dac_subsys.tcl
set dac_subsys_qsys ../../ip/dac_subsys/dac_subsys.qsys
set dac_subsys_ipdir ../../ip/dac_subsys/ip/dac_subsys
set regen 0
if {![file exists $dac_subsys_qsys]} {
    set regen 1
    puts "build.tcl: dac_subsys.qsys missing  regenerating"
} elseif {![file isdirectory $dac_subsys_ipdir]} {
    set regen 1
    puts "build.tcl: per-instance .ip backing dir $dac_subsys_ipdir missing  regenerating"
} elseif {[file mtime $dac_subsys_tcl] > [file mtime $dac_subsys_qsys]} {
    set regen 1
    puts "build.tcl: dac_subsys.tcl newer than dac_subsys.qsys  regenerating"
}
if {$regen} {
    # --quartus-project=agilex5_devkit.qpf is REQUIRED (not --new-quartus-project).
    # qsys-script's save_system needs the project's IP catalog to write the
    # per-instance backing .ip files at ip/dac_subsys/ip/dac_subsys/dac_subsys_u_*.ip
    # (logicalView path embedded in the .qsys's Generic Component definitions).
    # Without those .ip files synthesis fails with 13 "instantiates undefined
    # entity" errors. --search-path additionally ensures jesd_stub and
    # dac_controller_0 are discoverable even if Quartus's IP catalog cache
    # hasn't picked them up yet (build.tcl already cleans qdb/dni so the
    # catalog is rescanned each run).
    set qsys_search [list \
        "../../ip/dac_controller_0/**/*" \
        "../../ip/jesd_stub/**/*" \
        "\$"]
    set qsys_search_arg [join $qsys_search ","]
    puts "build.tcl: regenerating dac_subsys.qsys via qsys-script"
    if {[catch {exec >@stdout 2>@stderr qsys-script \
                    --quartus-project=agilex5_devkit.qpf \
                    --search-path=$qsys_search_arg \
                    --script=$dac_subsys_tcl} result]} {
        puts stderr "build.tcl: qsys-script regen FAILED:"
        puts stderr $result
        exit 1
    }
}

# --- Regenerate baseline_top.qsys = upstream + Phase B patches ------------
# baseline_top.upstream.qsys is the frozen GHRD baseline snapshot (never
# edited). baseline_top_phaseb_patches.tcl is the Phase B mutation source;
# it copies upstream into the working .qsys then applies Stage 4+ edits via
# load_system / add_instance / add_connection / EXPORT_OF.
# Regen rule: working .qsys missing OR (upstream OR patch script) newer.
set bt_upstream ./baseline_top.upstream.qsys
set bt_patches  ./baseline_top_phaseb_patches.tcl
set bt_working  ./baseline_top.qsys
set bt_regen 0
if {![file exists $bt_working]} {
    set bt_regen 1
    puts "build.tcl: baseline_top.qsys missing  regenerating"
} elseif {[file mtime $bt_patches] > [file mtime $bt_working]} {
    set bt_regen 1
    puts "build.tcl: baseline_top_phaseb_patches.tcl newer than baseline_top.qsys  regenerating"
} elseif {[file mtime $bt_upstream] > [file mtime $bt_working]} {
    set bt_regen 1
    puts "build.tcl: baseline_top.upstream.qsys newer than baseline_top.qsys  regenerating"
}
if {$bt_regen} {
    # --quartus-project=agilex5_devkit.qpf (see dac_subsys regen rationale above).
    # baseline_top.qsys instantiates u_dac_subsys; its .ip backing files at
    # ip/dac_subsys/ip/dac_subsys/ must exist BEFORE this step runs (the
    # dac_subsys regen above takes care of that). --search-path lets
    # qsys-script find dac_subsys.qsys and the new jesd_stub component.
    set bt_search [list \
        "../../ip/dac_controller_0/**/*" \
        "../../ip/jesd_stub/**/*" \
        "../../ip/dac_subsys/**/*" \
        "custom_ip/**/*" \
        "ip/fabric_subsys/**/*" \
        "ip/shell_subsys/**/*" \
        "\$"]
    set bt_search_arg [join $bt_search ","]
    puts "build.tcl: regenerating baseline_top.qsys via qsys-script patch"
    if {[catch {exec >@stdout 2>@stderr qsys-script \
                    --quartus-project=agilex5_devkit.qpf \
                    --search-path=$bt_search_arg \
                    --script=$bt_patches} result]} {
        puts stderr "build.tcl: baseline_top patch regen FAILED:"
        puts stderr $result
        exit 1
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

# Accept either the fully-licensed SOF or the OpenCore-Plus time-limited
# variant. The JESD204B GTS IP is OpenCore Plus on this workstation per
# doc/potential_issues.md ISSUE-016 -- the assembler then emits
# <rev>_time_limited.sof instead of <rev>.sof. Both are valid bitstreams
# for bring-up; only the deployable image requires the full license.
set sof_full    output_files/$rev.sof
set sof_limited output_files/${rev}_time_limited.sof
if {[file exists $sof_full]} {
    puts "build.tcl: complete. SOF at $sof_full (full license)"
    exit 0
} elseif {[file exists $sof_limited]} {
    puts "build.tcl: complete. SOF at $sof_limited (OpenCore Plus -- see ISSUE-016)"
    exit 0
} else {
    puts stderr "build.tcl: neither $sof_full nor $sof_limited was produced"
    exit 1
}
