# jesd_stub_hw.tcl
#
# -- JESD STUB - REMOVE IN STAGE 6 --
#
# Platform Designer descriptor for the JESD-side terminator used by
# ip/dac_subsys/dac_subsys.qsys in Stages 3-5. Its interface set is the
# conjugate of dac_controller_0's JESD interfaces, so that an explicit
# wiring of jesd_stub <-> dac_controller_0 in the qsys system produces a
# clean (warning-free) generate.
#
# Stage 6 deletes this component (and its parent ip/dac_subsys/jesd_stub/
# directory) and replaces the wiring with the Intel JESD204B GTS
# Subsystem IP. The deletion is intentionally one large hunk to make the
# stub-to-real transition reviewable in a single diff.

package require -exact qsys 14.0

# =============================================================================
# Module
# =============================================================================
set_module_property NAME                jesd_stub
set_module_property DISPLAY_NAME        "JESD-side stub (Stage 3 placeholder)"
set_module_property VERSION             1.0
set_module_property GROUP               "Phase B DAC"
set_module_property AUTHOR              "Brett Taylor"
set_module_property DESCRIPTION         "Synthesis-only terminator for the\
 JESD-side ports of dac_controller_0. Terminates 2x Avalon-ST link sources,\
 drives JESD CSR readback fields with mode-4 spec-encoded nominals, and ties\
 off the reset/refclk control conduits. Replaced in Stage 6 by the real\
 JESD204B GTS Subsystem IP."
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
# Avalon-ST sinks for JESD link data (conjugate of dac_controller_0's sources)
# =============================================================================
add_interface jesd_link0_data avalon_streaming end
set_interface_property jesd_link0_data associatedClock   jesd_tx_link_clk
set_interface_property jesd_link0_data associatedReset   reset_sink
set_interface_property jesd_link0_data dataBitsPerSymbol 128
set_interface_property jesd_link0_data readyLatency      0
add_interface_port jesd_link0_data jesd_link0_data_data  data  Input  128
add_interface_port jesd_link0_data jesd_link0_data_valid valid Input  1
add_interface_port jesd_link0_data jesd_link0_data_ready ready Output 1

add_interface jesd_link1_data avalon_streaming end
set_interface_property jesd_link1_data associatedClock   jesd_tx_link_clk
set_interface_property jesd_link1_data associatedReset   reset_sink
set_interface_property jesd_link1_data dataBitsPerSymbol 128
set_interface_property jesd_link1_data readyLatency      0
add_interface_port jesd_link1_data jesd_link1_data_data  data  Input  128
add_interface_port jesd_link1_data jesd_link1_data_valid valid Input  1
add_interface_port jesd_link1_data jesd_link1_data_ready ready Output 1

# =============================================================================
# Conduits (direction flipped relative to dac_controller_0)
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
