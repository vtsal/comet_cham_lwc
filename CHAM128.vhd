----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/04/2019 05:25:12 PM
-- Design Name: 
-- Module Name: CHAM128 - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- Entity
----------------------------------------------------------------------------------
entity CHAM128 is
    Port (
        clk         : in std_logic;
        rst         : in std_logic;
        start       : in std_logic;
        Key         : in std_logic_vector (127 downto 0);
        CHAM_in     : in std_logic_vector (127 downto 0);
        CHAM_out    : out std_logic_vector (127 downto 0);
        done        : out std_logic
    );

end CHAM128;

-- Architecture
----------------------------------------------------------------------------------
architecture Behavioral of CHAM128 is

    type RK_vector is array (0 to 7) of std_logic_vector(31 downto 0);
    -- Signals -------------------------------------------------------------------
    signal S0, S1, S2, S3                           : std_logic_vector(31 downto 0); -- Four 32-bit words of current state
    signal S0_Up, S1_Up, S2_Up, S3_Up               : std_logic_vector(31 downto 0); -- Four 32-bit words of updated state
    signal S3_temp                                  : std_logic_vector(31 downto 0);
    signal RK                                       : RK_vector; -- Eight 32-bit words of round key
    signal K0, K1, K2, K3                           : std_logic_vector(31 downto 0);
    signal round_Num                                : natural range 0 to 80; -- Round number

----------------------------------------------------------------------------------
begin

    -- Load 128-bit plaintext or updated state
    S0 <= CHAM_in(127 downto 96) when (round_Num = 0) else S0_Up;
    S1 <= CHAM_in(95 downto 64) when (round_Num = 0) else S1_Up;
    S2 <= CHAM_in(63 downto 32) when (round_Num = 0) else S2_Up;
    S3 <= CHAM_in(31 downto 0) when (round_Num = 0) else S3_Up;

    -- Key schedule
    K0      <= Key(127 downto 96);
    K1      <= Key(95 downto 64);
    K2      <= Key(63 downto 32);
    K3      <= Key(31 downto 0);
    RK(0)   <= K0 xor (K0(30 downto 0) & K0(31)) xor (K0(23 downto 0) & K0(31 downto 24)); -- R = K xor (K <<< 1) xor (K <<< 8)
    RK(1)   <= K1 xor (K1(30 downto 0) & K1(31)) xor (K1(23 downto 0) & K1(31 downto 24));
    RK(2)   <= K2 xor (K2(30 downto 0) & K2(31)) xor (K2(23 downto 0) & K2(31 downto 24)); 
    RK(3)   <= K3 xor (K3(30 downto 0) & K3(31)) xor (K3(23 downto 0) & K3(31 downto 24));
    RK(5)   <= K0 xor (K0(30 downto 0) & K0(31)) xor (K0(20 downto 0) & K0(31 downto 21)); -- R = K xor (K <<< 1) xor (K <<< 11)
    RK(4)   <= K1 xor (K1(30 downto 0) & K1(31)) xor (K1(20 downto 0) & K1(31 downto 21));
    RK(7)   <= K2 xor (K2(30 downto 0) & K2(31)) xor (K2(20 downto 0) & K2(31 downto 21));
    RK(6)   <= K3 xor (K3(30 downto 0) & K3(31)) xor (K3(20 downto 0) & K3(31 downto 21));
    
    -- ARX
    S3_temp <= (S0 xor conv_std_logic_vector(round_Num,32)) + ((S1(30 downto 0) & S1(31)) xor RK(round_Num mod 8)) when (round_Num mod 2 = 0) else
               (S0 xor conv_std_logic_vector(round_Num,32)) + ((S1(23 downto 0) & S1(31 downto 24)) xor RK(round_Num mod 8));
    
    -- Clock process
    RF: process(clk)
    begin
        if rising_edge(clk) then
            if (rst = '1' or start = '0') then
                round_Num   <= 0;
                done        <= '0';
                
            elsif (rst = '0' and start = '1') then
                round_Num   <= round_Num + 1;
            
                -- Update state
                if (round_Num mod 2 = 0) then
                    S3_Up   <= S3_temp(23 downto 0) & S3_temp(31 downto 24); 
                else
                    S3_Up   <= S3_temp(30 downto 0) & S3_temp(31);
                end if;
                S0_Up   <= S1;
                S1_Up   <= S2;
                S2_Up   <= S3;
                
                case round_Num is
                    when 80 => 
                        round_Num   <= 0;
                        done        <= '1';
                        CHAM_out    <= S3_Up & S2_Up & S1_Up & S0_Up;
                    when others =>
                        done        <= '0';
                end case;
            end if;
        end if;
    end process RF;

end Behavioral;
 
