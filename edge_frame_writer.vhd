library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 修正版 V3：連續對齊寫入器
-- 1. 等待第一筆資料出現 (對齊開頭)
-- 2. 之後連續寫入，遇到無效資料補 0 (保持幾何形狀，解決破碎問題)
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
  
  -- 狀態機
  type state_t is (IDLE, WAIT_FIRST, WRITING, DONE);
  signal state : state_t := IDLE;
  
  -- 總像素量
  constant TOTAL_PIXELS : integer := IN_W * IN_H;

begin

  process(clk, reset)
  begin
    if reset='1' then
      waddr      <= (others=>'0');
      state      <= IDLE;
      ram_we     <= '0';
      ram_din    <= (others=>'0');
      write_done <= '0';
      
    elsif rising_edge(clk) then
      -- 預設值
      ram_we     <= '0';
      ram_din    <= (others=>'0');
      write_done <= '0';

      case state is
        -- 1. 閒置狀態：等待 Start 指令
        when IDLE =>
          if start='1' then
            waddr <= (others=>'0');
            state <= WAIT_FIRST;
          end if;

        -- 2. 等待第一筆有效資料 (解決上下位移/黑畫面)
        -- 濾掉 Canny 核心剛啟動時的 Latency
        when WAIT_FIRST =>
          if edgeValid='1' then
            -- 抓到第一筆！開始寫入 Address 0
            ram_we  <= '1';
            ram_din <= edgePix(7 downto 0);
            waddr   <= waddr + 1;
            state   <= WRITING;
          end if;

        -- 3. 連續寫入狀態 (解決破碎/折行問題)
        -- 一旦開始，每個 Clock 都必須計數，保持 100x100 的結構
        when WRITING =>
          ram_we <= '1'; -- 強制寫入
          
          if edgeValid='1' then
            ram_din <= edgePix(7 downto 0); -- 有效則寫入邊緣
          else
            ram_din <= (others=>'0');       -- 無效則寫入黑色 (邊框/Padding)
          end if;
          
          -- 地址計數
          if waddr = to_unsigned(TOTAL_PIXELS-1, ADDR_BITS) then
            state <= DONE;
            -- 寫完最後一個點，也要正確輸出
            -- 上面的 ram_we/ram_din 已經處理了
          else
            waddr <= waddr + 1;
          end if;

        -- 4. 完成狀態
        when DONE =>
          write_done <= '1';
          ram_we     <= '0'; -- 停止寫入
          
          -- 允許重新 Start
          if start='1' then
            state <= WAIT_FIRST;
            waddr <= (others=>'0');
          end if;
          
      end case;
    end if;
  end process;

  ram_addr <= waddr;

end architecture;