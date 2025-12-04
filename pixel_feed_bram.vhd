library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pixel_feed_rom is
  generic (
    IMG_W     : integer := 100;
    IMG_H     : integer := 100;
    ADDR_BITS : integer := 14;
    PIX_BITS  : integer := 8;
    RUN_ONCE  : boolean := true   -- ?s?W?Gtrue=?]???@?V?N??
  );
  port (
    clk        : in  std_logic;
    reset      : in  std_logic;
    start      : in  std_logic;   -- ???£^s??? RUN_ONCE
    rom_addr   : out std_logic_vector(ADDR_BITS-1 downto 0);
    rom_dout   : in  std_logic_vector(PIX_BITS-1 downto 0);
    pixelIn    : out std_logic_vector(8 downto 0);
    pixelValid : out std_logic;
    sof        : out std_logic;
    frame_done : out std_logic
  );
end entity;

architecture rtl of pixel_feed_rom is
  type state_t is (IDLE, RUN);
  signal state          : state_t := IDLE;
  signal addr_reg       : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
  signal dout_reg       : std_logic_vector(PIX_BITS-1 downto 0) := (others=>'0');
  signal pixelValid_i   : std_logic := '0';
  signal sof_i          : std_logic := '0';
  signal frame_done_i   : std_logic := '0';
  signal prev_addr_valid: std_logic := '0';
  signal cnt            : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
begin
  rom_addr <= std_logic_vector(addr_reg);

  -- ???A???Gstart ??? ?? RUN?F?]???@?V ?? ??? RUN_ONCE ?M?w?????~??
  process(clk, reset)
  begin
    if reset='1' then
      state        <= IDLE;
      addr_reg     <= (others=>'0');
      cnt          <= (others=>'0');
      prev_addr_valid <= '0';
      frame_done_i <= '0';
    elsif rising_edge(clk) then
      frame_done_i <= '0';

      case state is
        when IDLE =>
          prev_addr_valid <= '0';
          if start='1' then
            state    <= RUN;
            addr_reg <= (others=>'0');
            cnt      <= (others=>'0');
            prev_addr_valid <= '1';  -- ?U?@??N?|????@?????
          end if;

        when RUN =>
          -- ?o?a?}?A?C??+1?F????@??o?X frame_done
          if pixelValid_i='1' then
            if cnt = to_unsigned(IMG_W*IMG_H-1, ADDR_BITS) then
              frame_done_i <= '1';
              if RUN_ONCE then
                state    <= IDLE;      -- ????
                prev_addr_valid <= '0';
              else
                -- ?s?????G?^???@???~??
                addr_reg <= (others=>'0');
                cnt      <= (others=>'0');
                prev_addr_valid <= '1';
              end if;
            else
              cnt      <= cnt + 1;
              addr_reg <= addr_reg + 1;
              prev_addr_valid <= '1';
            end if;
          else
            -- ??@??????????]ROM 1-cycle latency?^
            prev_addr_valid <= '1';
          end if;
      end case;
    end if;
  end process;

  -- 1-cycle ??? ROM ??X
  process(clk, reset)
  begin
    if reset='1' then
      dout_reg     <= (others=>'0');
      pixelValid_i <= '0';
      sof_i        <= '0';
    elsif rising_edge(clk) then
      if prev_addr_valid='1' and state=RUN then
        dout_reg     <= rom_dout;
        pixelValid_i <= '1';
        if cnt=to_unsigned(0, ADDR_BITS) then
          sof_i <= '1';
        else
          sof_i <= '0';
        end if;
      else
        pixelValid_i <= '0';
        sof_i        <= '0';
      end if;
    end if;
  end process;

  pixelIn    <= '0' & dout_reg;
  pixelValid <= pixelValid_i;
  sof        <= sof_i;
  frame_done <= frame_done_i;
end architecture;