-- =============================================================================
-- Module:      RegBank
-- Description: Avalon-MM slave register bank for dac_controller_0.
--              10-bit address decode (1 KB), no SPI registers.
--              SPI configuration is now handled entirely in HPS software.
--              PIO control/status registers are stubbed pending implementation.
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- Updated:     2026-04-06  Adapted for AD9176-FMC-EBZ: 10-bit address space,
--                          SPI registers removed, PIO stubs added.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity RegBank is
  port (
    clk              : in  std_logic;
    rst              : in  std_logic;
    -- Avalon-MM slave interface
    avmm_address     : in  std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0);
    avmm_read        : in  std_logic;
    avmm_write       : in  std_logic;
    avmm_writedata   : in  std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
    avmm_readdata    : out std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
    avmm_waitrequest : out std_logic;
    -- Sine wave gen CSR outputs
    sine_csr         : out t_sine_csr;
    -- JESD sync CSR outputs / status inputs
    jesd_sync_csr     : out t_jesd_sync_csr;
    jesd_sync_status  : in  t_jesd_sync_status;
    jesd_sync_err_clr : out std_logic_vector(3 downto 0);
    -- PIO passthrough (stubbed — defer to later implementation)
    pio_ctrl_reg  : out std_logic_vector(31 downto 0);
    pio_stat_in   : in  std_logic_vector(31 downto 0)
  );
end entity RegBank;

architecture rtl of RegBank is

  signal addr : unsigned(C_AVMM_ADDR_WIDTH - 1 downto 0);

  -- Scratchpad registers
  type t_scratch_array is array (0 to 3) of
    std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
  signal scratch_regs : t_scratch_array;

  -- JESD TX CSR registers
  signal reg_jesd_sync_ctrl  : std_logic_vector(31 downto 0);
  signal reg_jesd_tx_src_sel : std_logic_vector(31 downto 0);

  -- Sine wave gen CSR registers
  signal reg_sine_ctrl       : std_logic_vector(31 downto 0);
  signal reg_sine_freq_ch1_i : std_logic_vector(31 downto 0);
  signal reg_sine_freq_ch1_q : std_logic_vector(31 downto 0);
  signal reg_sine_freq_ch2_i : std_logic_vector(31 downto 0);
  signal reg_sine_freq_ch2_q : std_logic_vector(31 downto 0);
  signal reg_sine_phase_m0   : std_logic_vector(31 downto 0);
  signal reg_sine_phase_m1   : std_logic_vector(31 downto 0);
  signal reg_sine_phase_m2   : std_logic_vector(31 downto 0);
  signal reg_sine_phase_m3   : std_logic_vector(31 downto 0);
  signal reg_sine_amp_m0     : std_logic_vector(31 downto 0);
  signal reg_sine_amp_m1     : std_logic_vector(31 downto 0);
  signal reg_sine_amp_m2     : std_logic_vector(31 downto 0);
  signal reg_sine_amp_m3     : std_logic_vector(31 downto 0);

  -- PIO stub register
  signal reg_pio_ctrl : std_logic_vector(31 downto 0);

  -- Read data combinational
  signal read_data : std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);

begin

  addr <= unsigned(avmm_address);

  -- =========================================================================
  -- Write Process
  -- =========================================================================
  p_write : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        scratch_regs       <= (others => (others => '0'));
        reg_jesd_sync_ctrl  <= (others => '0');
        reg_jesd_tx_src_sel <= (others => '0');
        reg_sine_ctrl       <= (others => '0');
        reg_sine_freq_ch1_i <= (others => '0');
        reg_sine_freq_ch1_q <= (others => '0');
        reg_sine_freq_ch2_i <= (others => '0');
        reg_sine_freq_ch2_q <= (others => '0');
        reg_sine_phase_m0   <= (others => '0');
        reg_sine_phase_m1   <= (others => '0');
        reg_sine_phase_m2   <= (others => '0');
        reg_sine_phase_m3   <= (others => '0');
        reg_sine_amp_m0     <= x"00007FFF";
        reg_sine_amp_m1     <= x"00007FFF";
        reg_sine_amp_m2     <= x"00007FFF";
        reg_sine_amp_m3     <= x"00007FFF";
        reg_pio_ctrl        <= (others => '0');
        jesd_sync_err_clr   <= (others => '0');
      else
        jesd_sync_err_clr <= (others => '0');

        if avmm_write = '1' then
          case addr is
            when C_REG_SCRATCH0 =>
              scratch_regs(0) <= avmm_writedata;
            when C_REG_SCRATCH1 =>
              scratch_regs(1) <= avmm_writedata;
            when C_REG_SCRATCH2 =>
              scratch_regs(2) <= avmm_writedata;
            when C_REG_SCRATCH3 =>
              scratch_regs(3) <= avmm_writedata;
            when C_REG_JESD_SYNC_CTRL =>
              reg_jesd_sync_ctrl <= avmm_writedata;
            when C_REG_JESD_SYNC_ERR =>
              jesd_sync_err_clr <= avmm_writedata(3 downto 0);  -- W1C
            when C_REG_JESD_TX_SRC_SEL =>
              reg_jesd_tx_src_sel <= avmm_writedata;
            when C_REG_SINE_CTRL =>
              reg_sine_ctrl <= avmm_writedata;
            when C_REG_SINE_FREQ_CH1_I =>
              reg_sine_freq_ch1_i <= avmm_writedata;
            when C_REG_SINE_FREQ_CH1_Q =>
              reg_sine_freq_ch1_q <= avmm_writedata;
            when C_REG_SINE_FREQ_CH2_I =>
              reg_sine_freq_ch2_i <= avmm_writedata;
            when C_REG_SINE_FREQ_CH2_Q =>
              reg_sine_freq_ch2_q <= avmm_writedata;
            when C_REG_SINE_PHASE_M0 =>
              reg_sine_phase_m0 <= avmm_writedata;
            when C_REG_SINE_PHASE_M1 =>
              reg_sine_phase_m1 <= avmm_writedata;
            when C_REG_SINE_PHASE_M2 =>
              reg_sine_phase_m2 <= avmm_writedata;
            when C_REG_SINE_PHASE_M3 =>
              reg_sine_phase_m3 <= avmm_writedata;
            when C_REG_SINE_AMP_M0 =>
              reg_sine_amp_m0 <= avmm_writedata;
            when C_REG_SINE_AMP_M1 =>
              reg_sine_amp_m1 <= avmm_writedata;
            when C_REG_SINE_AMP_M2 =>
              reg_sine_amp_m2 <= avmm_writedata;
            when C_REG_SINE_AMP_M3 =>
              reg_sine_amp_m3 <= avmm_writedata;
            when C_REG_PIO_CTRL =>
              reg_pio_ctrl <= avmm_writedata;  -- stub
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process p_write;

  -- =========================================================================
  -- Read Process (combinational, zero-wait-state)
  -- =========================================================================
  p_read : process(all)
  begin
    read_data <= (others => '0');

    if avmm_read = '1' then
      case addr is
        when C_REG_SCRATCH0 =>
          read_data <= scratch_regs(0);
        when C_REG_SCRATCH1 =>
          read_data <= scratch_regs(1);
        when C_REG_SCRATCH2 =>
          read_data <= scratch_regs(2);
        when C_REG_SCRATCH3 =>
          read_data <= scratch_regs(3);
        when C_REG_JESD_SYNC_CTRL =>
          read_data <= reg_jesd_sync_ctrl;
        when C_REG_JESD_SYNC_STATUS =>
          read_data(3 downto 0) <= jesd_sync_status.txlink_ready;
          read_data(5 downto 4) <= jesd_sync_status.group_synced;
          read_data(6)          <= jesd_sync_status.lmfc_aligned;
        when C_REG_JESD_SYNC_ERR =>
          read_data(3 downto 0) <= jesd_sync_status.sync_err;
        when C_REG_JESD_TX_SRC_SEL =>
          read_data <= reg_jesd_tx_src_sel;
        when C_REG_JESD_TX_SRC_STAT =>
          read_data(0) <= jesd_sync_status.src_switch_pending;
          read_data(1) <= jesd_sync_status.src_active;
        when C_REG_SINE_CTRL =>
          read_data <= reg_sine_ctrl;
        when C_REG_SINE_FREQ_CH1_I =>
          read_data <= reg_sine_freq_ch1_i;
        when C_REG_SINE_FREQ_CH1_Q =>
          read_data <= reg_sine_freq_ch1_q;
        when C_REG_SINE_FREQ_CH2_I =>
          read_data <= reg_sine_freq_ch2_i;
        when C_REG_SINE_FREQ_CH2_Q =>
          read_data <= reg_sine_freq_ch2_q;
        when C_REG_SINE_PHASE_M0 =>
          read_data <= reg_sine_phase_m0;
        when C_REG_SINE_PHASE_M1 =>
          read_data <= reg_sine_phase_m1;
        when C_REG_SINE_PHASE_M2 =>
          read_data <= reg_sine_phase_m2;
        when C_REG_SINE_PHASE_M3 =>
          read_data <= reg_sine_phase_m3;
        when C_REG_SINE_AMP_M0 =>
          read_data <= reg_sine_amp_m0;
        when C_REG_SINE_AMP_M1 =>
          read_data <= reg_sine_amp_m1;
        when C_REG_SINE_AMP_M2 =>
          read_data <= reg_sine_amp_m2;
        when C_REG_SINE_AMP_M3 =>
          read_data <= reg_sine_amp_m3;
        when C_REG_PIO_CTRL =>
          read_data <= reg_pio_ctrl;
        when C_REG_PIO_STATUS =>
          read_data <= pio_stat_in;  -- stub: pass through external PIO status
        when others =>
          read_data <= (others => '0');
      end case;
    end if;
  end process p_read;

  -- No wait states needed — all registers respond in 0 cycles.
  avmm_waitrequest <= '0';
  avmm_readdata    <= read_data;

  -- =========================================================================
  -- CSR Output Mapping
  -- =========================================================================

  -- Sine Wave Gen CSR
  sine_csr.enable       <= reg_sine_ctrl(0);
  sine_csr.conv_enable  <= reg_sine_ctrl(4 downto 1);
  sine_csr.freq_m0      <= unsigned(reg_sine_freq_ch1_i);
  sine_csr.freq_m1      <= unsigned(reg_sine_freq_ch1_q);
  sine_csr.freq_m2      <= unsigned(reg_sine_freq_ch2_i);
  sine_csr.freq_m3      <= unsigned(reg_sine_freq_ch2_q);
  sine_csr.phase_ofs_m0 <= unsigned(reg_sine_phase_m0);
  sine_csr.phase_ofs_m1 <= unsigned(reg_sine_phase_m1);
  sine_csr.phase_ofs_m2 <= unsigned(reg_sine_phase_m2);
  sine_csr.phase_ofs_m3 <= unsigned(reg_sine_phase_m3);
  sine_csr.amplitude_m0 <= unsigned(reg_sine_amp_m0(15 downto 0));
  sine_csr.amplitude_m1 <= unsigned(reg_sine_amp_m1(15 downto 0));
  sine_csr.amplitude_m2 <= unsigned(reg_sine_amp_m2(15 downto 0));
  sine_csr.amplitude_m3 <= unsigned(reg_sine_amp_m3(15 downto 0));

  -- JESD Sync CSR
  jesd_sync_csr.sync_mode <= reg_jesd_sync_ctrl(0);
  jesd_sync_csr.src_sel   <= reg_jesd_tx_src_sel(0);

  -- PIO stub
  pio_ctrl_reg <= reg_pio_ctrl;

end architecture rtl;
