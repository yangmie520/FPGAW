library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- 引用 Xilinx 原語庫 (為了解決時鐘錯誤)
library UNISIM;
use UNISIM.vcomponents.all;

entity top_canny_vga_comp is
  port (
    sys_clk   : in  std_logic;            -- 100 MHz
    reset     : in  std_logic;
    start     : in  std_logic;

    -- VGA 輸出
    o_h_sync  : out std_logic;
    o_v_sync  : out std_logic;
    o_red     : out std_logic_vector(3 downto 0);
    o_green   : out std_logic_vector(3 downto 0);
    o_blue    : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_canny_vga_comp is
  -- 影像尺寸
  constant IN_W : integer := 100;
  constant IN_H : integer := 100;

  -- Canny 閾值
  constant LOW_T  : std_logic_vector(6 downto 0) := "0101101";    -- 45
  constant HIGH_T : std_logic_vector(8 downto 0) := "010000111";  -- 135

  -- 時鐘訊號
  signal div_reg       : std_logic := '0'; -- 分頻用暫存器
  signal pixel_clk_raw : std_logic := '0'; -- 分頻後的原始訊號
  signal pixel_clk     : std_logic;        -- 經過 BUFG 的全域時鐘

  -- start 同步與單次脈衝
  signal start_sync1, start_sync2 : std_logic := '0';
  signal start_prev               : std_logic := '0';
  signal start_pulse              : std_logic := '0';

  -- 混合重置訊號 (只給 Canny 用)
  signal canny_reset : std_logic := '0';

  -- 內部連接信號
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

  signal vga_addr    : unsigned(13 downto 0);
  signal vga_dout    : std_logic_vector(7 downto 0);

  -- 元件宣告
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
      IMG_W     : integer;
      IMG_H     : integer;
      ADDR_BITS : integer;
      PIX_BITS  : integer;
      RUN_ONCE  : boolean
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
      IN_W      : integer;
      IN_H      : integer;
      ADDR_BITS : integer
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
      DATA_BITS : integer;
      ADDR_BITS : integer
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

  component vga_edge_display
    generic(
      H_RES   : integer;
      H_FP    : integer;
      H_SYNC  : integer;
      H_BP    : integer;
      H_POL   : std_logic;
      V_RES   : integer;
      V_FP    : integer;
      V_SYNC  : integer;
      V_BP    : integer;
      V_POL   : std_logic;
      IN_W    : integer;
      IN_H    : integer;
      SCALE_K : integer
    );
    port (
      pixel_clk : in  std_logic;
      reset     : in  std_logic;
      ram_dout  : in  std_logic_vector(7 downto 0);
      ram_addr  : out unsigned(13 downto 0);
      o_h_sync  : out std_logic;
      o_v_sync  : out std_logic;
      o_red     : out std_logic_vector(3 downto 0);
      o_green   : out std_logic_vector(3 downto 0);
      o_blue    : out std_logic_vector(3 downto 0)
    );
  end component;

begin
  --------------------------------------------------
  -- 時鐘生成：100MHz -> 50MHz (加入 BUFG 解決 Implementation Error)
  --------------------------------------------------
  process(sys_clk, reset)
  begin
    if reset='1' then
      div_reg       <= '0';
      pixel_clk_raw <= '0';
    elsif rising_edge(sys_clk) then
      div_reg       <= not div_reg;
      pixel_clk_raw <= div_reg; 
    end if;
  end process;

  -- 這是關鍵：將一般邏輯產生的時鐘放入全域時鐘樹
  u_bufg : BUFG
    port map (
      I => pixel_clk_raw,
      O => pixel_clk
    );

  --------------------------------------------------
  -- 按鍵去彈跳/同步
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

  -- 修正後的重置訊號：只給 Canny 用
  canny_reset <= reset or start_pulse;

  --------------------------------------------------
  -- 1. 影像輸入源 (ROM)
  --------------------------------------------------
  u_feed : pixel_feed_rom
    generic map (IMG_W=>IN_W, IMG_H=>IN_H, ADDR_BITS=>14, PIX_BITS=>8, RUN_ONCE=>true)
    port map (
      clk        => sys_clk,
      reset      => reset,        -- Feed 不需要 soft reset
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
  -- 2. Canny 演算法核心 (使用 canny_reset)
  --------------------------------------------------
  u_canny : canny_dut_step_modular_fixpt
    port map (
      clk          => sys_clk,
      reset        => canny_reset,  -- **這裡維持強制重置，清空 Buffer**
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
  -- 3. 寫入器 (修正：使用一般 reset)
  --------------------------------------------------
  -- 原因：Writer 內部是 Async Reset，如果接 start_pulse 會導致它在 start 當下被重置而忽略啟動指令
  u_writer : edge_frame_writer
    generic map (IN_W=>IN_W, IN_H=>IN_H, ADDR_BITS=>14)
    port map (
      clk        => sys_clk,
      reset      => reset,      -- **改回一般 reset，不要接 start_pulse**
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
  -- 4. 雙埠 RAM
  --------------------------------------------------
  u_edge_ram : dual_port_edge_ram
    generic map (DATA_BITS=>8, ADDR_BITS=>14)
    port map (
      clk_a  => sys_clk,
      we_a   => w_we,
      addr_a => w_addr,
      din_a  => w_din,
      
      clk_b  => pixel_clk,  -- 使用 BUFG 後的穩定的 50MHz
      addr_b => vga_addr,
      dout_b => vga_dout
    );

  --------------------------------------------------
  -- 5. VGA 顯示控制器
  --------------------------------------------------
  u_vga : vga_edge_display
    generic map (
      H_RES   => 800,
      H_FP    => 56,
      H_SYNC  => 120,
      H_BP    => 64,
      H_POL   => '1',
      V_RES   => 600,
      V_FP    => 37,
      V_SYNC  => 6,
      V_BP    => 23,
      V_POL   => '1',
      IN_W    => IN_W,
      IN_H    => IN_H,
      SCALE_K => 4 
    )
    port map (
      pixel_clk => pixel_clk, -- 使用 BUFG 後的穩定的 50MHz
      reset     => reset,
      ram_dout  => vga_dout,
      ram_addr  => vga_addr,
      o_h_sync  => o_h_sync,
      o_v_sync  => o_v_sync,
      o_red     => o_red,
      o_green   => o_green,
      o_blue    => o_blue
    );

end architecture;