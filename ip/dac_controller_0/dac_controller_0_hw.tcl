# dac_controller_0_hw.tcl
#
# Platform Designer descriptor for Phase A's dac_controller_0 IP.
# Wraps the unchanged Phase A VHDL-2008 RTL (10 modules under src/) so it
# can be instantiated inside dac_subsys.qsys (Stage 3 onward) without
# modifying the RTL.
#
# Interface groups (per PLAN.md Stage 2):
#   clock_sink            clock end                  (system clock, AXI + reg_bank)
#   jesd_tx_link_clk      clock end                  (~250 MHz, drives JESD framers)
#   reset_sink            reset end                  (active-high sync reset)
#   lwhpm2fpga            axi4 end                   (4-bit ID, 10-bit addr, 32-bit data)
#   jesd_link0_data       avalon_streaming start     (128-bit, ready+valid)
#   jesd_link1_data       avalon_streaming start     (128-bit, ready+valid)
#   jesd_link0_status     conduit                    (somf in, frame_error out, frame_ready in)
#   jesd_link1_status     conduit                    (frame_error out, frame_ready in)
#   jesd_reset_seq        conduit                    (in_of_reset in, rst_n out, rst_ack_n in)
#   jesd_refclk_ctrl      conduit                    (txphy_clk, rs_priority, refclk_fail,
#                                                     refclk_on_ack, refclk_on, core_pll_locked)
#   jesd_csr_readback     conduit                    (HD CS L K N NP S CF F M DLB_DATA
#                                                     DLB_KCHAR TESTMODE TESTPATTERN_A..D)
#   pio_control           conduit                    (32-bit in,  stubbed in Phase A)
#   pio_status            conduit                    (32-bit out, stubbed in Phase A)
#   tx_enbl               conduit                    (1-bit in,   stubbed in Phase A)

package require -exact qsys 14.0

# =============================================================================
# Module
# =============================================================================
set_module_property NAME             dac_controller_0
set_module_property DISPLAY_NAME     "DAC Controller (AD9176-FMC-EBZ, Phase A)"
set_module_property VERSION          1.0
set_module_property GROUP            "Phase B DAC"
set_module_property AUTHOR           "Brett Taylor"
set_module_property DESCRIPTION      "Phase A DAC controller wrapped for Platform Designer.\
 Drives AD9176 over JESD204B mode 4 (2 links x 4 lanes). NCO, JESD transport,\
 sync FSM, FIFO, register bank."
set_module_property ELABORATION_CALLBACK elaborate

# =============================================================================
# File sets (synthesis + simulation share the same VHDL-2008 sources)
# =============================================================================
add_fileset synth_fileset QUARTUS_SYNTH set_top_level
set_fileset_property synth_fileset TOP_LEVEL dac_controller_0
add_fileset_file dac_controller_pkg.vhd    VHDL PATH src/dac_controller_pkg.vhd
add_fileset_file axi_lite_to_avmm.vhd      VHDL PATH src/axi_lite_to_avmm.vhd
add_fileset_file axi_to_avmm.vhd           VHDL PATH src/axi_to_avmm.vhd
add_fileset_file dc_fifo.vhd               VHDL PATH src/dc_fifo.vhd
add_fileset_file data_src_mux.vhd          VHDL PATH src/data_src_mux.vhd
add_fileset_file reg_bank.vhd              VHDL PATH src/reg_bank.vhd
add_fileset_file sine_wave_gen.vhd         VHDL PATH src/sine_wave_gen.vhd
add_fileset_file jesd_sync_controller.vhd  VHDL PATH src/jesd_sync_controller.vhd
add_fileset_file jesd_tx_manager.vhd       VHDL PATH src/jesd_tx_manager.vhd
add_fileset_file dac_controller_0.vhd      VHDL PATH src/dac_controller_0.vhd TOP_LEVEL_FILE

add_fileset sim_vhdl_fileset SIM_VHDL set_top_level
set_fileset_property sim_vhdl_fileset TOP_LEVEL dac_controller_0
add_fileset_file dac_controller_pkg.vhd    VHDL PATH src/dac_controller_pkg.vhd
add_fileset_file axi_lite_to_avmm.vhd      VHDL PATH src/axi_lite_to_avmm.vhd
add_fileset_file axi_to_avmm.vhd           VHDL PATH src/axi_to_avmm.vhd
add_fileset_file dc_fifo.vhd               VHDL PATH src/dc_fifo.vhd
add_fileset_file data_src_mux.vhd          VHDL PATH src/data_src_mux.vhd
add_fileset_file reg_bank.vhd              VHDL PATH src/reg_bank.vhd
add_fileset_file sine_wave_gen.vhd         VHDL PATH src/sine_wave_gen.vhd
add_fileset_file jesd_sync_controller.vhd  VHDL PATH src/jesd_sync_controller.vhd
add_fileset_file jesd_tx_manager.vhd       VHDL PATH src/jesd_tx_manager.vhd
add_fileset_file dac_controller_0.vhd      VHDL PATH src/dac_controller_0.vhd TOP_LEVEL_FILE

# =============================================================================
# Parameters
# =============================================================================
add_parameter G_LUT_DEPTH POSITIVE 1024
set_parameter_property G_LUT_DEPTH DISPLAY_NAME        "Sine LUT depth"
set_parameter_property G_LUT_DEPTH DESCRIPTION         "Sine wave LUT depth (entries). 1024 for synthesis; testbenches may override to 64 for faster elaboration."
set_parameter_property G_LUT_DEPTH UNITS               none
set_parameter_property G_LUT_DEPTH HDL_PARAMETER       true
set_parameter_property G_LUT_DEPTH AFFECTS_ELABORATION true
set_parameter_property G_LUT_DEPTH AFFECTS_GENERATION  true
set_parameter_property G_LUT_DEPTH ALLOWED_RANGES      "16:65536"

# Elaboration callback is a no-op; included so the interface model can read
# parameter values if needed in future revisions.
proc elaborate {} {}

# =============================================================================
# Clock interfaces
# =============================================================================
add_interface clock_sink clock end
add_interface_port clock_sink clock_sink_clk clk Input 1

add_interface jesd_tx_link_clk clock end
add_interface_port jesd_tx_link_clk jesd204_tx_link_clk_clk clk Input 1

# =============================================================================
# Reset interface (associated with the AXI control clock)
# =============================================================================
add_interface reset_sink reset end
set_interface_property reset_sink associatedClock  clock_sink
set_interface_property reset_sink synchronousEdges DEASSERT
add_interface_port reset_sink reset_sink_reset reset Input 1

# =============================================================================
# AXI4 control slave  HPS lwhpm2fpga bridge (4-bit ID, 10-bit address)
# =============================================================================
add_interface lwhpm2fpga axi4 end
set_interface_property lwhpm2fpga associatedClock                clock_sink
set_interface_property lwhpm2fpga associatedReset                reset_sink
set_interface_property lwhpm2fpga readAcceptanceCapability       1
set_interface_property lwhpm2fpga writeAcceptanceCapability      1
set_interface_property lwhpm2fpga combinedAcceptanceCapability   1
set_interface_property lwhpm2fpga readDataReorderingDepth        1
set_interface_property lwhpm2fpga bridgesToMaster                ""

# Write address channel
add_interface_port lwhpm2fpga lwhpm2fpga_awid    awid    Input  4
add_interface_port lwhpm2fpga lwhpm2fpga_awaddr  awaddr  Input  10
add_interface_port lwhpm2fpga lwhpm2fpga_awlen   awlen   Input  8
add_interface_port lwhpm2fpga lwhpm2fpga_awsize  awsize  Input  3
add_interface_port lwhpm2fpga lwhpm2fpga_awburst awburst Input  2
add_interface_port lwhpm2fpga lwhpm2fpga_awlock  awlock  Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_awcache awcache Input  4
add_interface_port lwhpm2fpga lwhpm2fpga_awprot  awprot  Input  3
add_interface_port lwhpm2fpga lwhpm2fpga_awvalid awvalid Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_awready awready Output 1
# Write data channel
add_interface_port lwhpm2fpga lwhpm2fpga_wdata   wdata   Input  32
add_interface_port lwhpm2fpga lwhpm2fpga_wstrb   wstrb   Input  4
add_interface_port lwhpm2fpga lwhpm2fpga_wlast   wlast   Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_wvalid  wvalid  Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_wready  wready  Output 1
# Write response channel
add_interface_port lwhpm2fpga lwhpm2fpga_bid     bid     Output 4
add_interface_port lwhpm2fpga lwhpm2fpga_bresp   bresp   Output 2
add_interface_port lwhpm2fpga lwhpm2fpga_bvalid  bvalid  Output 1
add_interface_port lwhpm2fpga lwhpm2fpga_bready  bready  Input  1
# Read address channel
add_interface_port lwhpm2fpga lwhpm2fpga_arid    arid    Input  4
add_interface_port lwhpm2fpga lwhpm2fpga_araddr  araddr  Input  10
add_interface_port lwhpm2fpga lwhpm2fpga_arlen   arlen   Input  8
add_interface_port lwhpm2fpga lwhpm2fpga_arsize  arsize  Input  3
add_interface_port lwhpm2fpga lwhpm2fpga_arburst arburst Input  2
add_interface_port lwhpm2fpga lwhpm2fpga_arlock  arlock  Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_arcache arcache Input  4
add_interface_port lwhpm2fpga lwhpm2fpga_arprot  arprot  Input  3
add_interface_port lwhpm2fpga lwhpm2fpga_arvalid arvalid Input  1
add_interface_port lwhpm2fpga lwhpm2fpga_arready arready Output 1
# Read data channel
add_interface_port lwhpm2fpga lwhpm2fpga_rid     rid     Output 4
add_interface_port lwhpm2fpga lwhpm2fpga_rdata   rdata   Output 32
add_interface_port lwhpm2fpga lwhpm2fpga_rresp   rresp   Output 2
add_interface_port lwhpm2fpga lwhpm2fpga_rlast   rlast   Output 1
add_interface_port lwhpm2fpga lwhpm2fpga_rvalid  rvalid  Output 1
add_interface_port lwhpm2fpga lwhpm2fpga_rready  rready  Input  1

# =============================================================================
# Avalon-ST source  JESD link 0 data (128-bit)
# =============================================================================
add_interface jesd_link0_data avalon_streaming start
set_interface_property jesd_link0_data associatedClock     jesd_tx_link_clk
set_interface_property jesd_link0_data dataBitsPerSymbol   128
set_interface_property jesd_link0_data readyLatency        0
add_interface_port jesd_link0_data \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_data  data  Output 128
add_interface_port jesd_link0_data \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_valid valid Output 1
add_interface_port jesd_link0_data \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_ready ready Input  1

# =============================================================================
# Avalon-ST source  JESD link 1 data (128-bit)
# =============================================================================
add_interface jesd_link1_data avalon_streaming start
set_interface_property jesd_link1_data associatedClock     jesd_tx_link_clk
set_interface_property jesd_link1_data dataBitsPerSymbol   128
set_interface_property jesd_link1_data readyLatency        0
add_interface_port jesd_link1_data \
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_data  data  Output 128
add_interface_port jesd_link1_data \
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_valid valid Output 1
add_interface_port jesd_link1_data \
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_ready ready Input  1

# =============================================================================
# Conduit  JESD link 0 status (somf, frame_error, frame_ready)
# =============================================================================
add_interface jesd_link0_status conduit end
add_interface_port jesd_link0_status \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_somf_export        somf        Input  4
add_interface_port jesd_link0_status \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_error_export frame_error Output 1
add_interface_port jesd_link0_status \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_ready_export frame_ready Input  1

# =============================================================================
# Conduit  JESD link 1 status (frame_error, frame_ready; link 1 has no somf)
# =============================================================================
add_interface jesd_link1_status conduit end
add_interface_port jesd_link1_status \
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_error_export frame_error Output 1
add_interface_port jesd_link1_status \
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_ready_export frame_ready Input  1

# =============================================================================
# Conduit  JESD GTS reset sequencing (shared)
# =============================================================================
add_interface jesd_reset_seq conduit end
add_interface_port jesd_reset_seq \
    jesd_gts_ss_TX_intel_jesd_TX_jesd204_tx_in_of_reset_export   in_of_reset Input  1
add_interface_port jesd_reset_seq \
    jesd_gts_ss_tx_outtel_jesd_tx_jesd204_tx_rst_n_reset_n       rst_n       Output 1
add_interface_port jesd_reset_seq \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_rst_ack_n_export    rst_ack_n   Input  1

# =============================================================================
# Conduit  JESD reference-clock / PLL management
# =============================================================================
add_interface jesd_refclk_ctrl conduit end
add_interface_port jesd_refclk_ctrl \
    jesd_gts_ss_TX_outtel_jesd_TX_txphy_clk_export                   txphy_clk           Input  4
add_interface_port jesd_refclk_ctrl \
    jesd_gts_ss_TX_outst_src_i_src_rs_priority_src_rs_priority       rs_priority         Output 4
add_interface_port jesd_refclk_ctrl \
    jesd_gts_ss_tx_outst_src_o_refclk_fail_status_refclk_fail_status refclk_fail_status  Input  8
add_interface_port jesd_refclk_ctrl \
    jesd_gts_ss_tx_outst_src_o_refclk_on_ack_refclk_on_ack           refclk_on_ack       Input  1
add_interface_port jesd_refclk_ctrl \
    jesd_gts_ss_tx_outst_src_i_refclk_on_refclk_on                   refclk_on           Output 10
add_interface_port jesd_refclk_ctrl \
    core_pll_locked_export                                           core_pll_locked     Input  1

# =============================================================================
# Conduit  JESD CSR readback (HD, CS, L, K, N, NP, S, CF, F, M + DLB + test)
# =============================================================================
add_interface jesd_csr_readback conduit end
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_hd_export   csr_hd  Input 1
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cs_export   csr_cs  Input 2
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_l_export    csr_l   Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_k_export    csr_k   Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_n_export    csr_n   Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_np_export   csr_np  Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_s_export    csr_s   Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cf_export   csr_cf  Input 5
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_f_export    csr_f   Input 8
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_m_export    csr_m   Input 8
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_data_export       dlb_data       Input 128
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_kchar_data_export dlb_kchar_data Input 16
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testmode_export           testmode       Input 4
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_a_export      testpattern_a  Input 32
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_b_export      testpattern_b  Input 32
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_c_export      testpattern_c  Input 32
add_interface_port jesd_csr_readback \
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_d_export      testpattern_d  Input 32

# =============================================================================
# Conduit  PIO control (32-bit in, Phase A stub)
# =============================================================================
add_interface pio_control conduit end
add_interface_port pio_control pio_control_external_connection_export pio_control Input 32

# =============================================================================
# Conduit  PIO status (32-bit out, Phase A stub)
# =============================================================================
add_interface pio_status conduit end
add_interface_port pio_status pio_status_external_connection_export pio_status Output 32

# =============================================================================
# Conduit  TX enable (1-bit in, Phase A stub)
# =============================================================================
add_interface tx_enbl conduit end
add_interface_port tx_enbl tx_enbl tx_enbl Input 1
