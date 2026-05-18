# jesd_stub_hw.tcl
#
# Platform Designer descriptor for the **non-data** JESD-side terminator used
# by ip/dac_subsys/dac_subsys.qsys.
#
# Stage 5 (merged) added the real Intel JESD204B GTS Subsystem IP for the
# two AVST data paths (jesd_link0_data, jesd_link1_data); those interfaces
# have been removed from this stub. The remaining conduits (jesd_*_status,
# jesd_reset_seq, jesd_refclk_ctrl, jesd_csr_readback, pio_*, tx_enbl) have
# no native counterpart on the GTS IP and are still terminated here so
# dac_controller_0 sees a complete set of conduit connections.
#
# A future stage can delete this stub entirely once dac_controller_0_hw.tcl
# is redesigned to drop those now-unused conduits.

package require -exact qsys 14.0

# =============================================================================
# Module
# =============================================================================
set_module_property NAME                jesd_stub
set_module_property DISPLAY_NAME        "JESD non-data conduit terminator"
set_module_property VERSION             1.1
set_module_property GROUP               "Phase B DAC"
set_module_property AUTHOR              "Brett Taylor"
set_module_property DESCRIPTION         "Terminates the JESD non-data\
 status/refclk/CSR/pio/tx_enbl conduits of dac_controller_0. The two AVST\
 data paths now flow to the real Intel JESD204B GTS Subsystem IP; this stub\
 retains the JESD CSR readback (mode-4 spec-encoded nominals) and ties off\
 the reset/refclk/pio/tx_enbl conduits."
set_module_property ELABORATION_CALLBACK elaborate

# =============================================================================
# Filesets
# =============================================================================
add_fileset synth_fileset QUARTUS_SYNTH set_top_level
set_fileset_property synth_fileset TOP_LEVEL jesd_stub
add_fileset_file jesd_stub.vhd VHDL PATH src/jesd_stub.vhd TOP_LEVEL_FILE

add_fileset sim_vhdl_fileset SIM_VHDL set_top_level
set_fileset_property sim_vhdl_fileset TOP_LEVEL jesd_stub
add_fileset_file jesd_stub.vhd VHDL PATH src/jesd_stub.vhd TOP_LEVEL_FILE

proc elaborate {} {}

# Fileset-callback no-op. qsys invokes the proc named in the 3rd arg of
# add_fileset during SPD generation; the actual add_fileset_file calls above
# already populated the filesets at top-level, so this proc has nothing to
# do beyond existing. Missing this proc only manifests during full ipgenerate
# (not during module-scan / elaborate), which is why Stage 3 --project-only
# didn't catch it.
proc set_top_level {top} {}

# =============================================================================
# Clock + reset
# =============================================================================
add_interface jesd_tx_link_clk clock end
add_interface_port jesd_tx_link_clk jesd204_tx_link_clk_clk clk Input 1

add_interface reset_sink reset end
set_interface_property reset_sink associatedClock  jesd_tx_link_clk
set_interface_property reset_sink synchronousEdges DEASSERT
add_interface_port reset_sink reset_sink_reset reset Input 1

# =============================================================================
# Conduits (direction flipped relative to dac_controller_0)
# Note: jesd_link0_data and jesd_link1_data AVST sinks were removed in
# Stage 5 (merged); those data paths now flow to the real Intel
# JESD204B GTS Subsystem IPs.
# =============================================================================

# jesd_link0_status: somf OUT (was IN to dac_controller_0), frame_error IN,
#                    frame_ready OUT
add_interface jesd_link0_status conduit end
add_interface_port jesd_link0_status jesd_link0_status_somf        somf        Output 4
add_interface_port jesd_link0_status jesd_link0_status_frame_error frame_error Input  1
add_interface_port jesd_link0_status jesd_link0_status_frame_ready frame_ready Output 1

# jesd_link1_status: no somf, frame_error IN, frame_ready OUT
add_interface jesd_link1_status conduit end
add_interface_port jesd_link1_status jesd_link1_status_frame_error frame_error Input  1
add_interface_port jesd_link1_status jesd_link1_status_frame_ready frame_ready Output 1

# jesd_reset_seq: in_of_reset OUT, rst_n IN, rst_ack_n OUT
add_interface jesd_reset_seq conduit end
add_interface_port jesd_reset_seq jesd_reset_seq_in_of_reset in_of_reset Output 1
add_interface_port jesd_reset_seq jesd_reset_seq_rst_n       rst_n       Input  1
add_interface_port jesd_reset_seq jesd_reset_seq_rst_ack_n   rst_ack_n   Output 1

# jesd_refclk_ctrl: txphy_clk OUT, rs_priority IN, refclk_fail_status OUT,
#                   refclk_on_ack OUT, refclk_on IN, core_pll_locked OUT
add_interface jesd_refclk_ctrl conduit end
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_txphy_clk          txphy_clk          Output 4
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_rs_priority        rs_priority        Input  4
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_refclk_fail_status refclk_fail_status Output 8
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_refclk_on_ack      refclk_on_ack      Output 1
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_refclk_on          refclk_on          Input  10
add_interface_port jesd_refclk_ctrl jesd_refclk_ctrl_core_pll_locked    core_pll_locked    Output 1

# jesd_csr_readback: all OUT from stub (driven), all IN to dac_controller_0
add_interface jesd_csr_readback conduit end
add_interface_port jesd_csr_readback jesd_csr_readback_csr_hd        csr_hd        Output 1
add_interface_port jesd_csr_readback jesd_csr_readback_csr_cs        csr_cs        Output 2
add_interface_port jesd_csr_readback jesd_csr_readback_csr_l         csr_l         Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_k         csr_k         Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_n         csr_n         Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_np        csr_np        Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_s         csr_s         Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_cf        csr_cf        Output 5
add_interface_port jesd_csr_readback jesd_csr_readback_csr_f         csr_f         Output 8
add_interface_port jesd_csr_readback jesd_csr_readback_csr_m         csr_m         Output 8
add_interface_port jesd_csr_readback jesd_csr_readback_dlb_data      dlb_data      Output 128
add_interface_port jesd_csr_readback jesd_csr_readback_dlb_kchar     dlb_kchar_data     Output 16
add_interface_port jesd_csr_readback jesd_csr_readback_testmode      testmode      Output 4
add_interface_port jesd_csr_readback jesd_csr_readback_testpattern_a testpattern_a Output 32
add_interface_port jesd_csr_readback jesd_csr_readback_testpattern_b testpattern_b Output 32
add_interface_port jesd_csr_readback jesd_csr_readback_testpattern_c testpattern_c Output 32
add_interface_port jesd_csr_readback jesd_csr_readback_testpattern_d testpattern_d Output 32

# pio_control: OUT from stub (32-bit, driven to 0) -> IN to dac_controller_0
add_interface pio_control conduit end
add_interface_port pio_control pio_control_pio_control pio_control Output 32

# pio_status: IN to stub (32-bit, consumed) <- OUT from dac_controller_0
add_interface pio_status conduit end
add_interface_port pio_status pio_status_pio_status pio_status Input 32

# tx_enbl: OUT from stub (1-bit, driven to '0') -> IN to dac_controller_0
add_interface tx_enbl conduit end
add_interface_port tx_enbl tx_enbl_tx_enbl tx_enbl Output 1
