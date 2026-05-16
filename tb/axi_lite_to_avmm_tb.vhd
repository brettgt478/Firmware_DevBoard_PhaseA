-- =============================================================================
-- Testbench:   AxiLiteToAvmm_tb
-- Description: Self-checking testbench for AXI4-Lite to Avalon-MM bridge.
-- Author:      Brett Taylor
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AxiLiteToAvmm_tb is
end entity AxiLiteToAvmm_tb;

architecture sim of AxiLiteToAvmm_tb is

  constant CLK_PERIOD : time := 10 ns;

  -- DUT signals
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- AXI-Lite side
  signal axi_awaddr  : std_logic_vector(19 downto 0) := (others => '0');
  signal axi_awvalid : std_logic := '0';
  signal axi_awready : std_logic;
  signal axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal axi_wstrb   : std_logic_vector(3 downto 0)  := (others => '1');
  signal axi_wvalid  : std_logic := '0';
  signal axi_wready  : std_logic;
  signal axi_bvalid  : std_logic;
  signal axi_bready  : std_logic := '0';
  signal axi_bresp   : std_logic_vector(1 downto 0);
  signal axi_araddr  : std_logic_vector(19 downto 0) := (others => '0');
  signal axi_arvalid : std_logic := '0';
  signal axi_arready : std_logic;
  signal axi_rdata   : std_logic_vector(31 downto 0);
  signal axi_rvalid  : std_logic;
  signal axi_rready  : std_logic := '0';

  -- Avalon-MM side (connects to slave BFM)
  signal avmm_address     : std_logic_vector(19 downto 0);
  signal avmm_read        : std_logic;
  signal avmm_write       : std_logic;
  signal avmm_writedata   : std_logic_vector(31 downto 0);
  signal avmm_readdata    : std_logic_vector(31 downto 0);
  signal avmm_waitrequest : std_logic;

  -- Slave BFM: 4-register file, combinational read, 0 wait states
  type t_reg_array is array (0 to 3) of std_logic_vector(31 downto 0);
  signal slave_regs : t_reg_array := (others => (others => '0'));

  -- =========================================================================
  -- AXI-Lite BFM Procedures
  -- =========================================================================

  procedure axi_write(
    constant addr    : in  std_logic_vector(19 downto 0);
    constant data    : in  std_logic_vector(31 downto 0);
    signal   aclk    : in  std_logic;
    signal   awaddr  : out std_logic_vector(19 downto 0);
    signal   awvalid : out std_logic;
    signal   awready : in  std_logic;
    signal   wdata   : out std_logic_vector(31 downto 0);
    signal   wvalid  : out std_logic;
    signal   wready  : in  std_logic;
    signal   bvalid  : in  std_logic;
    signal   bready  : out std_logic
  ) is
  begin
    wait until rising_edge(aclk);
    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wvalid  <= '1';
    loop
      wait until rising_edge(aclk);
      exit when awready = '1' and wready = '1';
    end loop;
    awvalid <= '0';
    wvalid  <= '0';
    bready  <= '1';
    loop
      wait until rising_edge(aclk);
      exit when bvalid = '1';
    end loop;
    bready <= '0';
  end procedure axi_write;

  procedure axi_read(
    constant addr    : in  std_logic_vector(19 downto 0);
    variable data    : out std_logic_vector(31 downto 0);
    signal   aclk    : in  std_logic;
    signal   araddr  : out std_logic_vector(19 downto 0);
    signal   arvalid : out std_logic;
    signal   arready : in  std_logic;
    signal   rdata   : in  std_logic_vector(31 downto 0);
    signal   rvalid  : in  std_logic;
    signal   rready  : out std_logic
  ) is
  begin
    wait until rising_edge(aclk);
    araddr  <= addr;
    arvalid <= '1';
    loop
      wait until rising_edge(aclk);
      exit when arready = '1';
    end loop;
    arvalid <= '0';
    rready  <= '1';
    loop
      wait until rising_edge(aclk);
      if rvalid = '1' then
        data := rdata;
        exit;
      end if;
    end loop;
    rready <= '0';
  end procedure axi_read;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD / 2;

  -- =========================================================================
  -- DUT
  -- =========================================================================
  u_dut : entity work.AxiLiteToAvmm
    generic map (
      G_ADDR_WIDTH => 20,
      G_DATA_WIDTH => 32
    )
    port map (
      clk              => clk,
      rst              => rst,
      s_axi_awaddr     => axi_awaddr,
      s_axi_awvalid    => axi_awvalid,
      s_axi_awready    => axi_awready,
      s_axi_wdata      => axi_wdata,
      s_axi_wstrb      => axi_wstrb,
      s_axi_wvalid     => axi_wvalid,
      s_axi_wready     => axi_wready,
      s_axi_bvalid     => axi_bvalid,
      s_axi_bready     => axi_bready,
      s_axi_bresp      => axi_bresp,
      s_axi_araddr     => axi_araddr,
      s_axi_arvalid    => axi_arvalid,
      s_axi_arready    => axi_arready,
      s_axi_rdata      => axi_rdata,
      s_axi_rvalid     => axi_rvalid,
      s_axi_rready     => axi_rready,
      avmm_address     => avmm_address,
      avmm_read        => avmm_read,
      avmm_write       => avmm_write,
      avmm_writedata   => avmm_writedata,
      avmm_readdata    => avmm_readdata,
      avmm_waitrequest => avmm_waitrequest
    );

  -- =========================================================================
  -- Avalon-MM Slave BFM: 4 registers, combinational read, 0 wait states
  -- =========================================================================
  avmm_waitrequest <= '0';
  avmm_readdata    <= slave_regs(to_integer(unsigned(avmm_address(3 downto 2))))
                        when avmm_read = '1' else (others => '0');

  p_slave : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        slave_regs <= (others => (others => '0'));
      elsif avmm_write = '1' then
        slave_regs(to_integer(unsigned(avmm_address(3 downto 2))))
          <= avmm_writedata;
      end if;
    end if;
  end process p_slave;

  -- =========================================================================
  -- Stimulus
  -- =========================================================================
  p_stim : process
    variable rd_data : std_logic_vector(31 downto 0);
  begin
    -- Hold reset
    wait for CLK_PERIOD * 5;
    rst <= '0';
    wait for CLK_PERIOD * 2;

    -- ==================================================================
    -- TB-BRG-001: Single write — verify slave captures data
    -- ==================================================================
    report "TB-BRG-001: Single write test" severity error;
    axi_write(x"00000", x"DEADBEEF",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);
    wait until rising_edge(clk);
    assert slave_regs(0) = x"DEADBEEF"
      report "TB-BRG-001 FAILED: slave reg(0) = " &
             to_hstring(slave_regs(0)) & ", expected DEADBEEF"
      severity failure;
    assert axi_bresp = "00"
      report "TB-BRG-001 FAILED: bresp /= OKAY" severity failure;
    report "TB-BRG-001 PASSED" severity error;

    -- ==================================================================
    -- TB-BRG-002: Single read — verify AXI returns correct data
    -- ==================================================================
    report "TB-BRG-002: Single read test" severity error;
    axi_read(x"00000", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"DEADBEEF"
      report "TB-BRG-002 FAILED: read = " & to_hstring(rd_data) &
             ", expected DEADBEEF"
      severity failure;
    report "TB-BRG-002 PASSED" severity error;

    -- ==================================================================
    -- TB-BRG-003: Write 4 registers, read all back
    -- ==================================================================
    report "TB-BRG-003: Multi-register round-trip" severity error;
    axi_write(x"00000", x"11111111",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);
    axi_write(x"00004", x"22222222",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);
    axi_write(x"00008", x"33333333",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);
    axi_write(x"0000C", x"44444444",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);

    axi_read(x"00000", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"11111111"
      report "TB-BRG-003 FAILED: reg0" severity failure;
    axi_read(x"00004", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"22222222"
      report "TB-BRG-003 FAILED: reg1" severity failure;
    axi_read(x"00008", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"33333333"
      report "TB-BRG-003 FAILED: reg2" severity failure;
    axi_read(x"0000C", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"44444444"
      report "TB-BRG-003 FAILED: reg3" severity failure;
    report "TB-BRG-003 PASSED" severity error;

    -- ==================================================================
    -- TB-BRG-004: Reset clears FSM — write works after re-reset
    -- ==================================================================
    report "TB-BRG-004: Reset behavior" severity error;
    rst <= '1';
    wait for CLK_PERIOD * 3;
    rst <= '0';
    wait for CLK_PERIOD * 2;
    -- Verify slave regs were cleared
    assert slave_regs(0) = x"00000000"
      report "TB-BRG-004 FAILED: regs not cleared" severity failure;
    -- Verify bridge still works after reset
    axi_write(x"00000", x"CAFEBABE",
      clk, axi_awaddr, axi_awvalid, axi_awready,
      axi_wdata, axi_wvalid, axi_wready, axi_bvalid, axi_bready);
    axi_read(x"00000", rd_data,
      clk, axi_araddr, axi_arvalid, axi_arready,
      axi_rdata, axi_rvalid, axi_rready);
    assert rd_data = x"CAFEBABE"
      report "TB-BRG-004 FAILED: post-reset round-trip" severity failure;
    report "TB-BRG-004 PASSED" severity error;

    -- ==================================================================
    report "SIMULATION PASSED" severity error;
    std.env.stop;
  end process p_stim;

end architecture sim;
