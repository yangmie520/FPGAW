library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_edge_display is
  generic(
    H_RES   : integer := 800;
    H_FP    : integer := 56;
    H_SYNC  : integer := 120;
    H_BP    : integer := 64;
    H_POL   : std_logic := '1';
    V_RES   : integer := 600;
    V_FP    : integer := 37;
    V_SYNC  : integer := 6;
    V_BP    : integer := 23;
    V_POL   : std_logic := '1';
    IN_W    : integer := 100;
    IN_H    : integer := 100;
    SCALE_K : integer := 4           -- ??j???v
  );
  port (
    pixel_clk : in  std_logic;
    reset     : in  std_logic;
    ram_dout  : in  std_logic_vector(7 downto 0);
    ram_addr  : out unsigned(13 downto 0);  -- 100x100 => 14 bits
    o_h_sync  : out std_logic;
    o_v_sync  : out std_logic;
    o_red     : out std_logic_vector(3 downto 0);
    o_green   : out std_logic_vector(3 downto 0);
    o_blue    : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of vga_edge_display is
  constant H_TOTAL : integer := H_RES + H_FP + H_SYNC + H_BP;
  constant V_TOTAL : integer := V_RES + V_FP + V_SYNC + V_BP;

  signal h_count : integer range 0 to H_TOTAL-1 := 0;
  signal v_count : integer range 0 to V_TOTAL-1 := 0;
  signal active_video : std_logic;
  signal in_range     : std_logic;
  signal src_x, src_y : integer;
  signal edge_pix     : std_logic_vector(7 downto 0);
begin
  process(pixel_clk, reset)
  begin
    if reset='1' then
      h_count <= 0;
    elsif rising_edge(pixel_clk) then
      if h_count = H_TOTAL-1 then
        h_count <= 0;
      else
        h_count <= h_count + 1;
      end if;
    end if;
  end process;

  process(pixel_clk, reset)
  begin
    if reset='1' then
      v_count <= 0;
    elsif rising_edge(pixel_clk) then
      if h_count = H_TOTAL-1 then
        if v_count = V_TOTAL-1 then
          v_count <= 0;
        else
          v_count <= v_count + 1;
        end if;
      end if;
    end if;
  end process;

  process(pixel_clk, reset)
  begin
    if reset='1' then
      o_h_sync <= not H_POL;
      o_v_sync <= not V_POL;
    elsif rising_edge(pixel_clk) then
      if (h_count >= H_RES + H_FP) and (h_count < H_RES + H_FP + H_SYNC) then
        o_h_sync <= H_POL;
      else
        o_h_sync <= not H_POL;
      end if;
      if (v_count >= V_RES + V_FP) and (v_count < V_RES + V_FP + V_SYNC) then
        o_v_sync <= V_POL;
      else
        o_v_sync <= not V_POL;
      end if;
    end if;
  end process;

  active_video <= '1' when (h_count < H_RES and v_count < V_RES) else '0';

  src_x <= h_count / SCALE_K;
  src_y <= v_count / SCALE_K;
  in_range <= '1' when (src_x < IN_W and src_y < IN_H and h_count < IN_W*SCALE_K and v_count < IN_H*SCALE_K) else '0';

  edge_pix <= ram_dout;
  ram_addr <= to_unsigned(src_y*IN_W + src_x, 14);

  process(pixel_clk, reset)
    variable r,g,b : std_logic_vector(3 downto 0);
  begin
    if reset='1' then
      r := (others=>'0'); g := (others=>'0'); b := (others=>'0');
    elsif rising_edge(pixel_clk) then
      if active_video='1' and in_range='1' then
        if edge_pix = x"00" then
          r := "0000"; g := "0000"; b := "0000";
        elsif edge_pix = x"80" then
          r := "0111"; g := "0111"; b := "0111";
        elsif edge_pix = x"FF" then
          r := "1111"; g := "1111"; b := "1111";
        else
          r := "0000"; g := "0000"; b := "0000";
        end if;
      else
        r := "0000"; g := "0000"; b := "0000";
      end if;
    end if;
    o_red   <= r;
    o_green <= g;
    o_blue  <= b;
  end process;
end architecture;