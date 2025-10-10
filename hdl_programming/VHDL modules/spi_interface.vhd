library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;


entity spi_interface is

Port ( clk_in    :   in std_logic;                                -- SPI reference clock
       sys_reset :   in std_logic;                                -- system reset trigger
       tx_data   :   in std_logic_vector(15 downto 0);           -- data to transmit over SPI
       data_len  :   in std_logic_vector(15 downto 0);           -- data len
       tx_en 	 :   in std_logic_vector(15 downto 0);           -- enable clk paasthrough/ data output
       sel_in    :   in std_logic_vector(3 downto 0);
       freq_div  :   in std_logic_vector(15 downto 0);             -- frequency division value
       mclk      :   out std_logic;                               -- spi clk                   - PMOD1_4 (J24)
       mosi      :   out std_logic;                               -- spi data                  - PMOD1_5 (T23)
       strobe    :   out std_logic;                               -- strobe for control logic  - PMOD1_6 (R23)
       inhibit   :   out std_logic;                               -- inhibit for control logic - PMOD1_7 (R22)
       sel_out   :   out std_logic_vector(3 downto 0) );         -- select lines for device demux -  Sel3 - PMOD1_0 (P22)
                                                                   --                                  Sel2 - PMOD1_1 (N22)
                                                                   --                                  Sel1 - PMOD1_2 (J20)
                                                                   --                                  Sel0 - PMOD1_3 (K24)
end spi_interface; 

architecture Behavioral of spi_interface is

attribute mark_debug : string; 

signal spi_clk      : std_logic;


-- input/ output data buffers
signal tx_data_reg  : std_logic_vector(15 downto 0);
signal strobe_reg   : std_logic;
signal inhibit_reg  : std_logic;
signal sel_out_reg  : std_logic_vector(3 downto 0);
signal mosi_bit     : std_logic;

-- internal regs 
signal counter      : std_logic_vector(7 downto 0);
signal cntrl_cnt    : std_logic_vector(3 downto 0);
signal spi_start    : std_logic;
signal tx_go        : std_logic;


--attribute mark_debug of tx_data_reg : signal is "true";
--attribute mark_debug of strobe_reg : signal is "true";
--attribute mark_debug of inhibit_reg : signal is "true";
--attribute mark_debug of sel_out_reg : signal is "true";
--attribute mark_debug of mosi_bit : signal is "true";
--attribute mark_debug of counter : signal is "true";
--attribute mark_debug of cntrl_cnt : signal is "true";
--attribute mark_debug of tx_go : signal is "true";
--attribute mark_debug of spi_clk : signal is "true";


signal clk_cnt : std_logic_vector(15 downto 0);
signal div_clk : std_logic;

begin

mclk    <= clk_in when spi_start = '1' else '0';

mosi    <= mosi_bit;
strobe  <= strobe_reg;
inhibit <= inhibit_reg;
sel_out <= sel_out_reg;
spi_clk <= div_clk;

process(clk_in) begin
    if rising_edge(clk_in) then
		if sys_reset = '1' then -- system reset state
			clk_cnt  <= x"0000";
			div_clk  <= '0';
		else
		    if(counter = freq_div - 1) then
				clk_cnt <= x"0000";
				div_clk <= not div_clk;
			else
				clk_cnt <= clk_cnt + '1';
			end if;
		  end if;
    end if;
end process;

shift_out: process(div_clk)
begin                                   -- figure out timing of all of this

if falling_edge(div_clk) then
    if sys_reset = '1' then             -- system reset state
        counter      <= x"00";
        tx_data_reg  <= tx_data;
        mosi_bit     <= '0';
        spi_start    <= '0';
    else
        if(tx_go = '1') then
            if(counter < data_len - 1) then
                counter <= counter + '1';
                spi_start <= '1';
                mosi_bit <= tx_data_reg(7);
                tx_data_reg <= std_logic_vector(shift_left(unsigned(tx_data_reg),1));
                
            else
            -- reset data
                counter     <= x"00";
                tx_data_reg <= tx_data;
                
            -- disable shift until next stream is ready
                
            end if;
        else
          counter <= x"00";
          tx_data_reg <= tx_data;
          
        end if;
    end if;
end if;

end process;

cntrlr: process(div_clk)

begin

    if rising_edge(div_clk) then
        
		if sys_reset = '1' then -- system reset state

			cntrl_cnt   <= x"0";
			sel_out_reg <= x"0";
			inhibit_reg <= '1';
			strobe_reg  <= '0';
			tx_go       <= '0';

		else                       

			if(tx_en = x"0001" ) then

				if(cntrl_cnt = x"0") then
					inhibit_reg <= '1';
					strobe_reg  <= '0';
					sel_out_reg <= sel_in;
					cntrl_cnt   <= cntrl_cnt + '1';

				elsif(cntrl_cnt = x"1") then
				    strobe_reg <= '1';
					cntrl_cnt  <= cntrl_cnt + '1';

                elsif(cntrl_cnt = x"2") then
                    strobe_reg  <= '0';
                    inhibit_reg <= '0';
                    tx_go       <= '1';
                    cntrl_cnt   <= cntrl_cnt + '1';
                else
				    if(counter = data_len - 1) then
				        tx_go <= '0';
				        cntrl_cnt <= x"0";
				     end if;
					
				end if;
			else
                cntrl_cnt   <= x"0";
                sel_out_reg <= x"0";
                inhibit_reg <= '1';
                strobe_reg  <= '0';
			 end if;
		end if;     
    end if;

end process;

end Behavioral;
