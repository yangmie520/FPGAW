
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_TEST is
end entity;

architecture sim of tb_TEST is
    -- DUT 介面訊號
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal sw       : std_logic := '0';
    signal count1_o : std_logic_vector(7 downto 0);
    signal count2_o : std_logic_vector(7 downto 0);
begin
    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------
    uut : entity work.TEST
        port map(
            rst      => rst,
            clk      => clk,
            sw       => sw,
            count1_o => count1_o,
            count2_o => count2_o
        );

    --------------------------------------------------------------------
    -- Clock : 10 ns period
    --------------------------------------------------------------------
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for 5 ns;
            clk <= '1';
            wait for 5 ns;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------
    stim_proc : process
    begin
        -- 初始 reset
        rst <= '1';
        wait for 20 ns;
        rst <= '0';

        -- sw = 0 (每次加/減 1)
        wait for 300 ns;

        -- 切換 sw = 1 (每次加/減 2)
        sw <= '1';
        wait for 300 ns;

        -- 再切回 sw = 0
        sw <= '0';
        wait for 965 ns;

        -- 再次 reset
        sw <= '1';
        wait for 30 ns;
        sw <= '0';

       
        -- 結束模擬
        wait;
    end process;
end architecture;
