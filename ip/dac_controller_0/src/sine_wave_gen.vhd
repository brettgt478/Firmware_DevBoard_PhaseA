-- =============================================================================
-- Module:      SineWaveGen
-- Description: 4-converter NCO with quarter-wave LUT, 8 samples/clk output.
--              Each converter independently generates sin(phase_acc + offset).
--              I/Q relationship is configured via per-converter phase offsets,
--              not hardwired — all 8 sample outputs are produced simultaneously.
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.DacControllerPkg.all;

entity SineWaveGen is
  generic (
    G_PHASE_BITS  : positive := 32;
    G_SAMPLE_BITS : positive := 16;
    G_LUT_DEPTH   : positive := 1024
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    -- CSR inputs
    csr           : in  t_sine_csr;
    -- Output samples (all 8 valid simultaneously each clock)
    samples_out   : out t_sample_bus;
    samples_valid : out std_logic
  );
end entity SineWaveGen;

architecture rtl of SineWaveGen is

  -- LUT address bits = clog2(G_LUT_DEPTH), derived from generic
  function clog2(val : positive) return positive is
    variable result : natural := 0;
    variable v      : natural := val - 1;
  begin
    while v > 0 loop
      result := result + 1;
      v := v / 2;
    end loop;
    return result;
  end function;

  constant C_LUT_ADDR_BITS : positive := clog2(G_LUT_DEPTH);

  -- Quarter-wave LUT type
  type t_lut_mem is array (0 to G_LUT_DEPTH - 1) of
    signed(G_SAMPLE_BITS - 1 downto 0);

  -- =========================================================================
  -- Quarter-wave sine table initialization
  -- Stores sin(0) to sin(pi/2) as signed 16-bit values, full scale = 32767
  -- =========================================================================
  function init_quarter_wave return t_lut_mem is
    variable lut : t_lut_mem;
    variable angle : real;
  begin
    for i in 0 to G_LUT_DEPTH - 1 loop
      angle := (real(i) + 0.5) * MATH_PI / (2.0 * real(G_LUT_DEPTH));
      lut(i) := to_signed(integer(sin(angle) * 32767.0), G_SAMPLE_BITS);
    end loop;
    return lut;
  end function;

  -- Evaluate the quarter-wave table once as a constant, then replicate
  -- to 4 block RAMs (one per converter, true dual-port).
  -- Port A: S0 lookup, Port B: S1 lookup -- both read every clock.
  constant C_LUT_DATA : t_lut_mem := init_quarter_wave;

  type t_lut_array is array (0 to 3) of t_lut_mem;
  signal lut : t_lut_array := (others => C_LUT_DATA);

  -- Helper arrays mapped from CSR named fields
  type t_phase_arr is array (0 to 3) of unsigned(G_PHASE_BITS - 1 downto 0);
  type t_amp_arr   is array (0 to 3) of unsigned(G_SAMPLE_BITS - 1 downto 0);

  signal freq      : t_phase_arr;
  signal phase_ofs : t_phase_arr;
  signal amp       : t_amp_arr;

  -- Phase accumulators (one per converter)
  signal phase_acc : t_phase_arr;

  -- Computed phases for S0 and S1 (combinational)
  signal phase_s0 : t_phase_arr;
  signal phase_s1 : t_phase_arr;

  -- Pipeline stage 1: LUT addresses and quadrant info (combinational)
  type t_addr_arr is array (0 to 3) of
    unsigned(C_LUT_ADDR_BITS - 1 downto 0);
  type t_quad_arr is array (0 to 3) of unsigned(1 downto 0);

  signal s0_addr : t_addr_arr;
  signal s1_addr : t_addr_arr;
  signal s0_quad : t_quad_arr;
  signal s1_quad : t_quad_arr;

  -- Pipeline stage 2: raw LUT values + delayed quadrants (registered)
  type t_sample_arr is array (0 to 3) of
    signed(G_SAMPLE_BITS - 1 downto 0);

  signal s0_raw    : t_sample_arr;
  signal s1_raw    : t_sample_arr;
  signal s0_quad_d : t_quad_arr;
  signal s1_quad_d : t_quad_arr;

  -- Pipeline stage 3: sign-corrected + amplitude-scaled outputs (registered)
  signal s0_out : t_sample_arr;
  signal s1_out : t_sample_arr;

  -- Pipeline valid (2 registered stages: LUT read + output)
  signal pipe_valid : std_logic_vector(1 downto 0);

  -- =========================================================================
  -- Quarter-wave address from full phase
  -- Phase bits: [31:30] = quadrant, [29:20] = LUT address (for 1024 depth)
  -- Quadrant 0 (00): sin increasing,  addr = phase[29:20]
  -- Quadrant 1 (01): sin decreasing,  addr = ~phase[29:20] (mirror)
  -- Quadrant 2 (10): sin neg rising,  addr = phase[29:20], negate output
  -- Quadrant 3 (11): sin neg falling, addr = ~phase[29:20], negate output
  -- =========================================================================
  function get_lut_addr(
    phase : unsigned(G_PHASE_BITS - 1 downto 0)
  ) return unsigned is
    variable addr : unsigned(C_LUT_ADDR_BITS - 1 downto 0);
  begin
    addr := phase(G_PHASE_BITS - 3 downto
                  G_PHASE_BITS - 2 - C_LUT_ADDR_BITS);
    if phase(G_PHASE_BITS - 2) = '1' then
      return not addr;
    else
      return addr;
    end if;
  end function;

  function get_quadrant(
    phase : unsigned(G_PHASE_BITS - 1 downto 0)
  ) return unsigned is
  begin
    return phase(G_PHASE_BITS - 1 downto G_PHASE_BITS - 2);
  end function;

  function apply_quadrant_sign(
    raw_val : signed(G_SAMPLE_BITS - 1 downto 0);
    quad    : unsigned(1 downto 0)
  ) return signed is
  begin
    if quad(1) = '1' then
      return -raw_val;
    else
      return raw_val;
    end if;
  end function;

begin

  -- Map CSR named fields to arrays for loop iteration
  freq(0)      <= csr.freq_m0;
  freq(1)      <= csr.freq_m1;
  freq(2)      <= csr.freq_m2;
  freq(3)      <= csr.freq_m3;
  phase_ofs(0) <= csr.phase_ofs_m0;
  phase_ofs(1) <= csr.phase_ofs_m1;
  phase_ofs(2) <= csr.phase_ofs_m2;
  phase_ofs(3) <= csr.phase_ofs_m3;
  amp(0)       <= csr.amplitude_m0;
  amp(1)       <= csr.amplitude_m1;
  amp(2)       <= csr.amplitude_m2;
  amp(3)       <= csr.amplitude_m3;

  -- =========================================================================
  -- Phase Accumulators
  -- Advance by 2 * freq_word each clock because each clock produces two
  -- consecutive samples (S0 and S1).
  -- =========================================================================
  p_phase_acc : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or csr.enable = '0' then
        for i in 0 to 3 loop
          phase_acc(i) <= (others => '0');
        end loop;
        pipe_valid <= (others => '0');
      else
        for i in 0 to 3 loop
          phase_acc(i) <= phase_acc(i) + shift_left(freq(i), 1);
        end loop;
        pipe_valid <= pipe_valid(0) & '1';
      end if;
    end if;
  end process p_phase_acc;

  -- =========================================================================
  -- Phase + Address Computation (combinational — no latches)
  -- S0 = accumulator + phase_offset
  -- S1 = accumulator + phase_offset + freq_word  (next consecutive sample)
  -- =========================================================================
  p_phase_addr : process(all)
  begin
    for i in 0 to 3 loop
      phase_s0(i) <= phase_acc(i) + phase_ofs(i);
      phase_s1(i) <= phase_acc(i) + phase_ofs(i) + freq(i);
      s0_addr(i)  <= get_lut_addr(phase_s0(i));
      s1_addr(i)  <= get_lut_addr(phase_s1(i));
      s0_quad(i)  <= get_quadrant(phase_s0(i));
      s1_quad(i)  <= get_quadrant(phase_s1(i));
    end loop;
  end process p_phase_addr;

  -- =========================================================================
  -- Block RAM Read (synchronous, true dual-port per converter)
  -- Port A: S0 address, Port B: S1 address — all converters every clock
  -- =========================================================================
  p_lut_read : process(clk)
  begin
    if rising_edge(clk) then
      for i in 0 to 3 loop
        s0_raw(i)    <= lut(i)(to_integer(s0_addr(i)));
        s1_raw(i)    <= lut(i)(to_integer(s1_addr(i)));
        s0_quad_d(i) <= s0_quad(i);
        s1_quad_d(i) <= s1_quad(i);
      end loop;
    end if;
  end process p_lut_read;

  -- =========================================================================
  -- Sign Correction + Amplitude Scaling
  -- Product is 16-bit signed × 17-bit signed = 33-bit result.
  -- Extract bits [30:15] for Q0.15 output (divide by 32768).
  -- =========================================================================
  p_output : process(clk)
    variable scaled : signed(2 * G_SAMPLE_BITS downto 0);  -- 33 bits
  begin
    if rising_edge(clk) then
      if rst = '1' then
        for i in 0 to 3 loop
          s0_out(i) <= (others => '0');
          s1_out(i) <= (others => '0');
        end loop;
      else
        for i in 0 to 3 loop
          if csr.conv_enable(i) = '1' then
            scaled := apply_quadrant_sign(s0_raw(i), s0_quad_d(i)) *
                      signed('0' & amp(i));
            s0_out(i) <= scaled(2 * G_SAMPLE_BITS - 2 downto
                                G_SAMPLE_BITS - 1);

            scaled := apply_quadrant_sign(s1_raw(i), s1_quad_d(i)) *
                      signed('0' & amp(i));
            s1_out(i) <= scaled(2 * G_SAMPLE_BITS - 2 downto
                                G_SAMPLE_BITS - 1);
          else
            s0_out(i) <= (others => '0');
            s1_out(i) <= (others => '0');
          end if;
        end loop;
      end if;
    end if;
  end process p_output;

  -- =========================================================================
  -- Output Assignment
  -- Each converter maps directly to its sample bus slot.
  -- I/Q pairing is a software concern (phase offsets), not hardwired here.
  -- Typical AD9176 Mode 4 usage:
  --   M0 = DAC0 I, M1 = DAC0 Q, M2 = DAC1 I, M3 = DAC1 Q
  -- =========================================================================
  samples_out.m0_s0 <= s0_out(0);
  samples_out.m0_s1 <= s1_out(0);
  samples_out.m1_s0 <= s0_out(1);
  samples_out.m1_s1 <= s1_out(1);
  samples_out.m2_s0 <= s0_out(2);
  samples_out.m2_s1 <= s1_out(2);
  samples_out.m3_s0 <= s0_out(3);
  samples_out.m3_s1 <= s1_out(3);

  samples_valid <= pipe_valid(1) and csr.enable;

end architecture rtl;
