


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TEST is
    port (
        rst       : in  std_logic;                 
        clk       : in  std_logic;
        sw        : in  std_logic;                 
        count1_o  : out std_logic_vector(7 downto 0);
        count2_o  : out std_logic_vector(7 downto 0)
    );
end entity;

architecture Behavioral of TEST is
    signal count1 : unsigned(7 downto 0);
    signal count2 : unsigned(7 downto 0);

    type fsm_type is (s0, s1, s2, s3);
    signal state : fsm_type;
begin
    count1_o <= std_logic_vector(count1);
    count2_o <= std_logic_vector(count2);


    fsm : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= s0;
            else
                case state is
                    when s0 =>
                        if count1 = "00001000" then  
                            state <= s2;
                        end if;
                    when s1 =>
                        if count2 = "01010000" then 
                            state <= s3;
                        end if;
                    when s2 =>
                        state <= s1;
                    when s3 =>
                        state <= s0;
                    when others =>
                        state <= s0;
                end case;
            end if;
        end if;
    end process;



    counter1 : process(clk)
        variable step_val : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count1 <= (others => '0');
            else
               
                if sw = '1' then
                    step_val := to_unsigned(2, 8);
                else
                    step_val := to_unsigned(1, 8);
                end if;

                case state is
                    when s0 =>
                        count1 <= count1 + step_val;
                    when s2 =>
                        count1 <= (others => '0');
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;



    counter2 : process(clk)
        variable step_val : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count2 <= "11111101";  
            else
                -- sw=1 ¡÷ -2 ; sw=0 ¡÷ -1
                if sw = '1' then
                    step_val := to_unsigned(2, 8);
                else
                    step_val := to_unsigned(1, 8);
                end if;

                case state is
                    when s1 =>
                        count2 <= count2 - step_val;
                    when s3 =>
                        count2 <= "11111101";
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;
end architecture;
