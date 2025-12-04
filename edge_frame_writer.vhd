library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 修改版：具備自動對齊功能的 Writer
-- 功能：收到 start 後進入待命，直到 edgeValid='1' 才開始連續寫入 100x100 個像素
entity edge_frame_writer is
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
end entity;

architecture rtl of edge_frame_writer is
  -- 內部計數器
  signal waddr        : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
  
  -- writing: 表示「正在連續寫入中」的狀態
  signal writing      : std_logic := '0';
  
  -- wait_first: 表示「已收到 Start，正在等第一筆有效資料」的狀態 (新增旗標)
  signal wait_first   : std_logic := '0';
  
  signal write_done_i : std_logic := '0';
  signal pix8         : std_logic_vector(7 downto 0);
  
  -- 總像素量
  constant TOTAL_PIXELS : integer := IN_W * IN_H;

begin
  -- 資料接線
  pix8 <= edgePix(7 downto 0);

  -- 主邏輯 Process
  process(clk, reset)
  begin
    if reset='1' then
      waddr        <= (others=>'0');
      writing      <= '0';
      wait_first   <= '0';
      write_done_i <= '0';
    elsif rising_edge(clk) then
      write_done_i <= '0';

      -- 1. 收到 Start 脈衝：重置計數，進入「等待第一筆資料」狀態
      -- 這裡只負責重置，不負責啟動寫入
      if start='1' then
        wait_first <= '1';
        writing    <= '0';
        waddr      <= (others=>'0');
      end if;

      -- 2. 判斷是否應該寫入 (核心修改處)
      -- 條件：正在寫入模式 (writing='1') 或 (正在等待 wait_first='1' 且有效資料 edgeValid='1' 來了)
      if (writing='1') or (wait_first='1' and edgeValid='1') then
        
        -- 檢查是否寫滿整張圖 (0 ~ 9999)
        if waddr = to_unsigned(TOTAL_PIXELS-1, ADDR_BITS) then
          -- 寫滿了，停止一切
          writing      <= '0';
          wait_first   <= '0';
          write_done_i <= '1';
          waddr        <= (others=>'0'); -- 歸零保險
        else
          -- 還沒寫滿，計數器 +1
          waddr <= waddr + 1;
          
          -- 狀態維護：如果原本是 wait_first，現在正式切換成 writing 鎖定狀態
          if wait_first='1' then
            wait_first <= '0';
            writing    <= '1';
          end if;
        end if;
        
      end if;
    end if;
  end process;

  -- 輸出邏輯 (Combinatorial)
  
  -- ram_addr 直接對應內部計數器
  ram_addr <= waddr;
  
  -- ram_we (寫入致能)：
  -- 必須在 (writing='1') 或者 (剛抓到第一筆 wait_first='1' and edgeValid='1') 的當下皆為 High
  -- 這樣可以確保第一筆資料 (Address 0) 被正確寫入
  ram_we <= '1' when (writing='1' or (wait_first='1' and edgeValid='1')) else '0';
  
  -- ram_din 資料：
  -- 當 edgeValid 有效時寫入像素值，無效時補 0
  ram_din <= pix8 when edgeValid='1' else (others=>'0');
  
  write_done <= write_done_i;

end architecture;