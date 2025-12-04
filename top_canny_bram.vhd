library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_canny_vga_comp is
  port (
    sys_clk   : in  std_logic;
    reset     : in  std_logic;
    start     : in  std_logic;

    -- 原 VGA 輸出端口保留（模擬中全部拉低）
    o_h_sync  : out std_logic;
    o_v_sync  : out std_logic;
    o_red     : out std_logic_vector(3 downto 0);
    o_green   : out std_logic_vector(3 downto 0);
    o_blue    : out std_logic_vector(3 downto 0);

    -- 新增：幀輸入完成、邊緣寫入完成、edgeValid 計數
    frame_done_o        : out std_logic;
    write_done_o        : out std_logic;
    edge_valid_count_o  : out unsigned(15 downto 0);

    -- 新增：RAM B 讀取介面（僅模擬使用）
    dbg_clk_b  : in  std_logic;
    dbg_addr_b : in  unsigned(13 downto 0);
    dbg_dout_b : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of top_canny_vga_comp is
  constant IN_W : integer := 100;
  constant IN_H : integer := 100;
  constant LOW_T  : std_logic_vector(6 downto 0) := "0101101";    -- 45
  constant HIGH_T : std_logic_vector(8 downto 0) := "010000111";  -- 135

  -- 按鍵同步 + 單次脈衝
  signal start_sync1, start_sync2 : std_logic := '0';
  signal start_prev               : std_logic := '0';
  signal start_pulse              : std_logic := '0';

  component img_bram
    port (
      clka  : in  std_logic;
      addra : in  std_logic_vector(13 downto 0);
      douta : out std_logic_vector(7 downto 0)
    );
  end component;

  component canny_dut_step_modular_fixpt
    port (
      clk          : in  std_logic;
      reset        : in  std_logic;
      clk_enable   : in  std_logic;
      pixelIn      : in  std_logic_vector(8 downto 0);
      pixelValid   : in  std_logic;
      lowT         : in  std_logic_vector(6 downto 0);
      highT        : in  std_logic_vector(8 downto 0);
      imageWidth   : in  std_logic_vector(9 downto 0);
      imageHeight  : in  std_logic_vector(10 downto 0);
      sof          : in  std_logic;
      ce_out       : out std_logic;
      edgePix      : out std_logic_vector(8 downto 0);
      edgeValid    : out std_logic
    );
  end component;

  component pixel_feed_rom
    generic (
      IMG_W     : integer := 100;
      IMG_H     : integer := 100;
      ADDR_BITS : integer := 14;
      PIX_BITS  : integer := 8;
      RUN_ONCE  : boolean := true
    );
    port (
      clk        : in  std_logic;
      reset      : in  std_logic;
      start      : in  std_logic;
      rom_addr   : out std_logic_vector(ADDR_BITS-1 downto 0);
      rom_dout   : in  std_logic_vector(PIX_BITS-1 downto 0);
      pixelIn    : out std_logic_vector(8 downto 0);
      pixelValid : out std_logic;
      sof        : out std_logic;
      frame_done : out std_logic
    );
  end component;

  component edge_frame_writer
    generic (
      IN_W      : integer := 100;
      IN_H      : integer := 100;
      ADDR_BITS : integer := 14
    );
    port (
      clk        : in  std_logic;
      reset      : in  std_logic;
      edgePix    : in  std_logic_vector(8 downto 0);
      edgeValid  : in  std_logic;
      start      : in  std_logic;
      done_in    : in  std_logic;
      ram_we     : out std_logic;
      ram_addr   : out unsigned(ADDR_BITS-1 downto 0);
      ram_din    : out std_logic_vector(7 downto 0);
      write_done : out std_logic
    );
  end component;

  component dual_port_edge_ram
    generic (
      DATA_BITS : integer := 8;
      ADDR_BITS : integer := 14
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
  end component;

  -- 信號
  signal pixelIn     : std_logic_vector(8 downto 0);
  signal pixelValid  : std_logic;
  signal sof         : std_logic;
  signal edgePix     : std_logic_vector(8 downto 0);
  signal edgeValid   : std_logic;
  signal frame_done  : std_logic;

  signal feed_addr   : std_logic_vector(13 downto 0);
  signal feed_dout   : std_logic_vector(7 downto 0);

  signal w_we        : std_logic;
  signal w_addr      : unsigned(13 downto 0);
  signal w_din       : std_logic_vector(7 downto 0);
  signal w_done      : std_logic;

  signal edge_valid_count : unsigned(15 downto 0) := (others=>'0');
begin
  --------------------------------------------------
  -- start 同步 + 上升沿
  --------------------------------------------------
  process(sys_clk, reset)
  begin
    if reset='1' then
      start_sync1 <= '0';
      start_sync2 <= '0';
      start_prev  <= '0';
      start_pulse <= '0';
    elsif rising_edge(sys_clk) then
      start_sync1 <= start;
      start_sync2 <= start_sync1;
      start_pulse <= '0';
      if start_sync2='1' and start_prev='0' then
        start_pulse <= '1';
      end if;
      start_prev <= start_sync2;
    end if;
  end process;

  --------------------------------------------------
  -- Pixel 來源
  --------------------------------------------------
  u_feed : pixel_feed_rom
    generic map (IMG_W=>IN_W, IMG_H=>IN_H, ADDR_BITS=>14, PIX_BITS=>8, RUN_ONCE=>true)
    port map (
      clk        => sys_clk,
      reset      => reset,
      start      => start_pulse,
      rom_addr   => feed_addr,
      rom_dout   => feed_dout,
      pixelIn    => pixelIn,
      pixelValid => pixelValid,
      sof        => sof,
      frame_done => frame_done
    );

  u_img_bram : img_bram
    port map (
      clka  => sys_clk,
      addra => feed_addr,
      douta => feed_dout
    );

  --------------------------------------------------
  -- Canny
  --------------------------------------------------
  u_canny : canny_dut_step_modular_fixpt
    port map (
      clk          => sys_clk,
      reset        => reset,
      clk_enable   => '1',
      pixelIn      => pixelIn,
      pixelValid   => pixelValid,
      lowT         => LOW_T,
      highT        => HIGH_T,
      imageWidth   => std_logic_vector(to_unsigned(IN_W,10)),
      imageHeight  => std_logic_vector(to_unsigned(IN_H,11)),
      sof          => sof,
      ce_out       => open,
      edgePix      => edgePix,
      edgeValid    => edgeValid
    );

  --------------------------------------------------
  -- Writer：完整 raster
  --------------------------------------------------
  u_writer : edge_frame_writer
    generic map (IN_W=>IN_W, IN_H=>IN_H, ADDR_BITS=>14)
    port map (
      clk        => sys_clk,
      reset      => reset,
      edgePix    => edgePix,
      edgeValid  => edgeValid,
      start      => start_pulse,
      done_in    => frame_done,
      ram_we     => w_we,
      ram_addr   => w_addr,
      ram_din    => w_din,
      write_done => w_done
    );

  --------------------------------------------------
  -- RAM：Port A 寫（sys_clk），Port B 讀（dbg_clk_b）
  --------------------------------------------------
  u_edge_ram : dual_port_edge_ram
    generic map (DATA_BITS=>8, ADDR_BITS=>14)
    port map (
      clk_a  => sys_clk,
      we_a   => w_we,
      addr_a => w_addr,
      din_a  => w_din,
      clk_b  => dbg_clk_b,
      addr_b => dbg_addr_b,
      dout_b => dbg_dout_b
    );

  --------------------------------------------------
  -- edgeValid 計數（寫期間統計）
  --------------------------------------------------
  process(sys_clk, reset)
  begin
    if reset='1' then
      edge_valid_count <= (others=>'0');
    elsif rising_edge(sys_clk) then
      if start_pulse='1' then
        edge_valid_count <= (others=>'0');
      elsif w_we='1' and edgeValid='1' then
        edge_valid_count <= edge_valid_count + 1;
      end if;
    end if;
  end process;

  frame_done_o       <= frame_done;
  write_done_o       <= w_done;
  edge_valid_count_o <= edge_valid_count;

  -- VGA 端口全部拉低（不使用）
  o_h_sync <= '0';
  o_v_sync <= '0';
  o_red    <= (others=>'0');
  o_green  <= (others=>'0');
  o_blue   <= (others=>'0');
end architecture;