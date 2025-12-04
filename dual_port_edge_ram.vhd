library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dual_port_edge_ram is
  generic (
    DATA_BITS : integer := 8;
    ADDR_BITS : integer := 14  -- 100x100 => 10000 < 2^14
  );
  port (
    clk_a   : in  std_logic;
    we_a    : in  std_logic;
    addr_a  : in  unsigned(ADDR_BITS-1 downto 0);
    din_a   : in  std_logic_vector(DATA_BITS-1 downto 0);

    clk_b   : in  std_logic;
    addr_b  : in  unsigned(ADDR_BITS-1 downto 0);
    dout_b  : out std_logic_vector(DATA_BITS-1 downto 0)
  );
end entity;

architecture rtl of dual_port_edge_ram is
  type ram_t is array (0 to (2**ADDR_BITS)-1) of std_logic_vector(DATA_BITS-1 downto 0);
  signal ram : ram_t := (others => (others => '0'));
  signal dout_b_reg : std_logic_vector(DATA_BITS-1 downto 0);
begin
  process(clk_a)
  begin
    if rising_edge(clk_a) then
      if we_a='1' then
        ram(to_integer(addr_a)) <= din_a;
      end if;
    end if;
  end process;

  process(clk_b)
  begin
    if rising_edge(clk_b) then
      dout_b_reg <= ram(to_integer(addr_b));
    end if;
  end process;

  dout_b <= dout_b_reg;
end architecture;