----------------------------------------------------------------------------------
-- Create Date: 12/10/2020 09:04:54 AM
-- Module Name: sd card interface
-- Dependencies:
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity sd_card_interface is
port(
  sys_reset      : in  std_logic;                      -- system/ AXI reset
  clk_in         : in  std_logic;                      -- 100 MHz system/ AXI clk
  read_addr_base : in  std_logic_vector(15 downto 0);  -- split address in two due to size of AXI_REG registers
  read_addr_top  : in  std_logic_vector(15 downto 0);
  block_size     : in  std_logic_vector(15 downto 0);  -- size of block to read from SD device
  block_count    : in  std_logic_vector(15 downto 0);  -- number of blocks to read from memory   - 2 GiB = 2^30. 2^30/ 512 Bytes = 0x400000 (max number of blocks)
  tx_en          : in  std_logic_vector(15 downto 0);
  write_prot     : in  std_logic;                      -- misc SD signal - not currently used    - PMOD0_7 (BC16)
  card_detect    : in  std_logic;                      -- misc SD signal - not currently used    - PMOD0_6 (AW12)
  DATA1          : in  std_logic;                      -- SD mode data line - not currently used - PMOD0_4 (BC13)
  DATA2          : in  std_logic;                      -- SD mode data line - not currently used - PMOD0_5 (BF7 )
  MISO           : in  std_logic;                      -- spi master in / slave out (DATA 0)     - PMOD0_2 (AW16)
  MOSI           : out std_logic;                      -- spi master out/ slave in  (Command)    - PMOD0_1 (BA10)
  MCLK           : out std_logic;                      -- spi master clk                         - PMOD0_3 (BB16)
  aCS            : out std_logic;                      -- CS - active low                        - PMOD0_0 (BC14)
  sample_out     : out std_logic_vector(31 downto 0)); -- current sample

end sd_card_interface;

architecture Behavioral of sd_card_interface is

component clkdivmuxsmall
port(
  clkin  : in  std_logic;
  rst    : in  std_logic;
  div1   : in  std_logic_vector(31 downto 0);
  div2   : in  std_logic_vector(31 downto 0);
  sel    : in  std_logic; -- level selects between clock dividers, switching at the next output falling edge after this toggles
  re     : out std_logic; -- gives a 1-clock cycle warning of clk div's rising edge
  fe     : out std_logic; -- gives a 1-clock cycle warning of clk div's falling edge
  clkout : out std_logic
);
end component;

-- State machine/ output clk
constant base_div      : std_logic_vector(7 downto 0) := x"FA"; -- low speed clk - 400 kbps, clk_div = 250
constant high_div      : std_logic_vector(7 downto 0) := x"04"; -- high speed clk - 25 MHz
signal high_trigger    : std_logic := '0';
signal spi_clk         : std_logic;
signal spi_clk_rising  : std_logic;
signal spi_clk_falling : std_logic;
--signal spi_clk_cnt  : std_logic_vector(7 downto 0);

-- SPI State Machine output buffer/ internal regs
signal mosi_sig         : std_logic;                     -- for debugging
signal mosi_reg         : std_logic;                     -- trigger mosi
signal main_mosi_reg    : std_logic;
signal miso_reg         : std_logic;                     -- track miso
signal miso_sig         : std_logic;                     -- for debugging
signal miso_reg_rd      : std_logic;
signal acs_sig          : std_logic;                     -- trigger aCS
signal spi_trigger      : std_logic;                     -- enable/disable SPI clk for slave
signal spi_state        : std_logic_vector(7 downto 0);  -- cnt spi states
signal init_cnt         : std_logic_vector(7 downto 0);
signal block_read_count : std_logic_vector(31 downto 0); -- Current count of number of blocks read
signal fault            : std_logic;                     -- SM entered fault state, check most recent command/ response
signal cmd8_scss        : std_logic;                     -- Did CMD8 run/ return properly? Track validity of HCS
signal spi_hcs          : std_logic;                     -- High capacity support..

-- TX State Machine internal regs
signal tx_trigger : std_logic;                     -- Main SM starts TX SM
signal tx_done    : std_logic;
signal tx_cnt     : std_logic_vector( 7 downto 0);
signal tx_data    : std_logic_vector(47 downto 0); -- Command to send

-- RX State Machine internal regs
signal rx_trigger    : std_logic;                     -- Main SM starts TX SM
signal rx_done       : std_logic;
signal rx_cont       : std_logic;
signal rx_cnt        : std_logic_vector( 7 downto 0);
signal rx_detect_cnt : std_logic_vector( 7 downto 0); -- Detect no response from Slave
signal rx_data       : std_logic_vector(39 downto 0);
signal rsp_len       : std_logic_vector( 7 downto 0);

-- RX Read SM  - allows for continuous reading of 512 byte blocks, separated into 32 bit I/ Q samples
-- Most signals are copies of RX state machine, simplify logic
-- The 32 bit I/Q samples will be updated each time a new 4 bytes comes in
constant read_length       : std_logic_vector(15 downto 0) := x"1020";
constant read_idle_error   : std_logic_vector( 2 downto 0) := "001";
constant read_status_error : std_logic_vector( 2 downto 0) := "010";
constant read_data_error   : std_logic_vector( 2 downto 0) := "011";
constant read_CRC_error    : std_logic_vector( 2 downto 0) := "100";
signal read_cont        : std_logic;
signal read_done        : std_logic;
signal read_trigger     : std_logic;
signal block_done       : std_logic;
signal read_data        : std_logic_vector(4127 downto 0); -- Block Read of 512 bytes + 'response' + 'status' + 'CRC' = 516 bytes
signal read_cnt         : std_logic_vector(  15 downto 0);
signal read_detect_cnt  : std_logic_vector(  15 downto 0); -- Detect no response from Slave
signal sample_cnt       : std_logic_vector(  15 downto 0);
signal status_error     : std_logic_vector(   7 downto 0);
signal read_error       : std_logic_vector(   2 downto 0);
signal read_block_count : std_logic_vector(  15 downto 0);

-- command structure stuff
signal   cmd      : std_logic_vector(47 downto 0);          -- Full command is built from:   start & CMD & Argument & CRC
signal   argument : std_logic_vector(31 downto 0);
constant start    : std_logic_vector( 1 downto 0) := "01";
signal   CRC      : std_logic_vector( 7 downto 0) := x"95"; -- Includes stop bit = 1, leaves MOSI high at end of TX

-- command constants
constant cmd_len    : std_logic_vector(7 downto 0) := x"30";
constant rsp_1_len  : std_logic_vector(7 downto 0) := x"08";
constant rsp_3_len  : std_logic_vector(7 downto 0) := x"28";
constant rsp_7_len  : std_logic_vector(7 downto 0) := x"28";
constant resp_idle  : std_logic_vector(7 downto 0) := x"01";
constant resp_illeg : std_logic_vector(7 downto 0) := x"04";

-- Card information
signal card_version    : std_logic_vector(1 downto 0);
signal voltage_support : std_logic_vector(3 downto 0); -- 0001 (2.7-3.6), 0010 (low voltage 1.8v)

----- command arguments -----
-- CMD0 - Initialize
-- 31:0  - zeros...
-- Response - 8 bits (resp_idle)
constant cmd_0_arg : std_logic_vector(31 downto 0) := x"00000000";

-- CMD8 - IF_COND - check if applied voltage is allowed
-- 31:12    reserved
-- 11:8     Voltage Range Check (0x1)
-- 7:0      Check Pattern  (0xAA )
-- Response - 40 bits - expects idle state & original argument, including voltage support and check pattern
-- Note - correct receipt of CMD8 opens up functionality for CMD41/ 58 - allows HCS to be specified/ Read
constant cmd_8_arg  : std_logic_vector(31 downto 0) := x"000001AA";     -- voltage supplied = 2.7-3.6V, Check pattern = "AA" ?
constant cmd_8_resp : std_logic_vector(39 downto 0) := resp_idle & cmd_8_arg;

-- CMD 55 - Specifies that the next command is App. Specific
-- Sends all zeros
-- Response - 8 bits (resp_idle)
constant cmd_55_arg  : std_logic_vector(31 downto 0) := x"00000000";
constant cmd_55_resp : std_logic_vector( 7 downto 0) := resp_idle;

-- CMD 58 - Read OCR Register - CCS Bit = Reg[30]
-- send all zeros?
-- Response - 8 bits (resp_idle) & 32 bits (OCR register)
-- [20], [21] should be '1' 3.2-3.3 OR 3.3-3.4 V is supported,
-- [30] = 1 gives High capacity support, 0 gives low capacity support
-- Bit [30] only valid if CMD8 accepted returned properly
constant cmd_58_arg  : std_logic_vector(31 downto 0) := x"00000000";
constant cmd_58_resp : std_logic_vector(39 downto 0) :=resp_idle & "11000000001100000000000000000000";

-- ACMD41 - Sends host capacity support; starts initialization
-- 31   - reserved (set to 0)
-- 30   - High capacity support? (1 = yes)
-- 29:0 - reserved (set to 0)
-- Note: HCS only accepted on first run, should just be ignored by SD card
-- Response - 8 bits - CMD41 expects idle state OR all zeros
constant acmd_41_arg     : std_logic_vector(31 downto 0) := x"40000000";
constant cmd_41_resp     : std_logic_vector( 7 downto 0) := resp_idle;
constant cmd_41_resp_alt : std_logic_vector( 7 downto 0) := x"00";

-- CMD12 - SD card stop TX - End Read command
-- 31:0 - Stuff (set to 0?)
-- Response - R1 + Busy Bytes
-- When Busy Byte is all 0's, continue pulling bytes until non zero.
constant cmd_12_arg       : std_logic_vector(31 downto 0) := x"00000000";
constant cmd_12_resp      : std_logic_vector( 7 downto 0) := resp_idle;
constant cmd_12_resp_busy : std_logic_vector( 7 downto 0) := x"00";

-- CMD16 - Program Block Length
-- 31:0 - Block Len
-- Response - R1
constant cmd_16_arg  : std_logic_vector(31 downto 0) := x"0000" & block_size;
constant cmd_16_resp : std_logic_vector( 7 downto 0) := resp_idle;

-- CMD17 -  Read Single Block
-- 31:0 - Start Address
-- Response - R1
constant cmd_17_arg  : std_logic_vector(31 downto 0) := read_addr_top & read_addr_base;
constant cmd_17_resp : std_logic_vector( 7 downto 0) := resp_idle;

-- CMD18 - Read Multiple Blocks
-- 31:0 - Start Address
-- Response - R1
-- Response - Read response
--  start block - "11111110" (status)
--  data bytes  - byte 2 - 513
--  CRC         - x^16 + x^12 + x^5 + 1
--  start block will have different error responses given below
constant cmd_18_arg              : std_logic_vector(31 downto 0) := read_addr_top & read_addr_base;
constant cmd_18_resp             : std_logic_vector( 7 downto 0) := resp_idle;
constant read_status_ok          : std_logic_vector( 7 downto 0) := "11111110";
constant read_status_range_error : std_logic_vector( 7 downto 0) := "00001001";
constant read_status_ECC_error   : std_logic_vector( 7 downto 0) := "00000101";
constant read_status_CC_error    : std_logic_vector( 7 downto 0) := "00000011";

-- OCR Register
-- 0:14   reserved
-- 15:23  Voltage Level Support
-- 24-29  Reserved
-- 30 CCS - card capacity status - valid IF R[31] = 1
-- 31 CPS - card power-up status
----------------------------------

---- Debugging ----
signal tx_en_reg : std_logic_vector(15 downto 0);


attribute mark_debug : string;

--attribute mark_debug of mosi_reg    : signal is "true";
attribute mark_debug of mosi_sig    : signal is "true";
--attribute mark_debug of miso_reg    : signal is "true";
attribute mark_debug of miso_sig    : signal is "true";
attribute mark_debug of acs_sig     : signal is "true";
attribute mark_debug of spi_trigger : signal is "true";
attribute mark_debug of spi_state   : signal is "true";
attribute mark_debug of spi_clk     : signal is "true";
attribute mark_debug of init_cnt    : signal is "true";

--attribute mark_debug of tx_cnt      : signal is "true";
--attribute mark_debug of tx_trigger  : signal is "true";
--attribute mark_debug of tx_data     : signal is "true";
--attribute mark_debug of tx_done     : signal is "true";

--attribute mark_debug of rx_cnt      : signal is "true";
--attribute mark_debug of rx_trigger  : signal is "true";
--attribute mark_debug of rx_cont     : signal is "true";
--attribute mark_debug of rx_data     : signal is "true";
--attribute mark_debug of rx_done     : signal is "true";
--attribute mark_debug of rx_detect_cnt  : signal is "true";

--attribute mark_debug of tx_en_reg   : signal is "true";

--attribute mark_debug of cmd8_scss   : signal is "true";
--attribute mark_debug of spi_hcs     : signal is "true";

--attribute mark_debug of read_data          : signal is "true";
--attribute mark_debug of read_trigger       : signal is "true";
--attribute mark_debug of read_cnt            : signal is "true";
--attribute mark_debug of read_detect_cnt     : signal is "true";
--attribute mark_debug of read_cont       : signal is "true";
--attribute mark_debug of read_done       : signal is "true";
--attribute mark_debug of sample_cnt       : signal is "true";
--attribute mark_debug of read_length       : constant is "true";
--attribute mark_debug of read_idle_error     : constant is "true";
--attribute mark_debug of read_status_error   : constant is "true";
--attribute mark_debug of read_data_error     : constant is "true";
--attribute mark_debug of read_CRC_error     : constant is "true";
--attribute mark_debug of status_error       : signal is "true";
--attribute mark_debug of read_error       : signal is "true";
--attribute mark_debug of block_done       : signal is "true";
--attribute mark_debug of read_block_count     : signal is "true";

---- End Debug ----

begin

-- outputs
MCLK <= spi_clk when spi_trigger  = '1' else '0';
mosi_sig <= mosi_reg or main_mosi_reg;
mosi <= mosi_sig;
miso_sig <= miso;
acs <= acs_sig;

-- clock divider for SPI
-- 'div1' and 'div2' must be a multiple of 2.
-- sel=0 : use div1, sel=1 : use div2
-- re : preemptive indicator of rising edge on output clock  (clocked at clkin rate)
-- fe : preemptive indicator of falling edge on output clock (clocked at clkin rate)
clk_div_mux_inst : clkdivmuxsmall
port map(
  clkin  => clk_in,
  rst    => sys_reset,
  div1   => x"000000fa", -- 0xfa = div by 250 : 100M/250 = 400k
  div2   => x"00000004", -- 0x04 = div by   4 : 100M/4   =  25M
  sel    => '0',
  re     => spi_clk_rising,  -- preemptive indicator of rising edge on output clock (clocked at clkin rate)
  fe     => spi_clk_falling, -- preemptive indicator of falling edge on output clock (clocked at clkin rate)
  clkout => spi_clk
);

-- internal
-- Must divide sys_clk down to SD standard
-- Maximum clk for initialization: 400kHz
-- Maximum clk for further spi action post initialization: 25 MHz
--spi_clk_gen : process(clk_in)
--begin
--  if rising_edge(clk_in) then
--    if sys_reset = '1' then
--      spi_clk_cnt <= x"00";
--      spi_clk <= '0';
--    elsif high_trigger = '1' then
--            if spi_clk_cnt < high_div - 1 then
--                spi_clk_cnt <= spi_clk_cnt + 1;
--            else
--                spi_clk_cnt <= x"00";
--                spi_clk <= not spi_clk;
--            end if;
--    else -- high_trigger = '0'
--        if spi_clk_cnt < base_div - 1 then
--        spi_clk_cnt <= spi_clk_cnt + 1;
--      else
--        spi_clk_cnt <= x"00";
--        spi_clk <= not spi_clk;
--      end if;
--    end if;
--    end if;
--end process;
--- End CLK Division --


spi_state_machine : process(clk_in)        -- state machine driven by currently selected SPI clk
begin
  if(spi_clk_rising = '1') then

      -- debugging
        tx_en_reg <= tx_en;

    if(tx_en = x"0000") then
        high_trigger    <= '0';
        main_mosi_reg   <= '1';
      acs_sig        <= '1';      -- disable chip select - active low
      spi_trigger    <= '0';      -- disable spi clk at output
      spi_hcs         <= '0';         -- track high capacity support
      cmd8_scss       <= '0';         -- track cmd8 success -> determines SD card type!
      spi_state      <= x"00";    -- start at state 0
      init_cnt     <= x"00";    -- cnt to configure device into SPI mode
      read_block_count <= x"0000";    -- count number of blocks received (assuming 512 bytes here for block size)

      -- TX/ RX state machine
      tx_trigger      <= '0';         -- keep tx state machine off
      rx_trigger      <= '0';         -- keep rx state machine off
      read_trigger    <= '0';         -- keep rx_read state machine off
      rsp_len         <= rsp_1_len;   -- response length RX should look for

    else
      -- start of state machine sequence, sys_reset may drop to '0' before rising edge of our divided 'spi_clk'
      if(spi_state = x"00") then
        -- configure mosi/ aCS defaults
        main_mosi_reg   <= '1';
                acs_sig        <= '1';                                  -- disable chip select - active low
                spi_trigger    <= '0';                                  -- disable spi clk at output
                init_cnt     <= x"00";                                -- cnt to configure device into SPI mode

                -- TX/ RX state machine
                tx_trigger      <= '0';                                     -- keep tx state machine off
                rx_trigger      <= '0';                                     -- keep rx state machine off
                rsp_len         <= rsp_1_len;                             -- response length RX should look for

        spi_state <= spi_state + 1;

      elsif(spi_state = x"01") then                             -- count 74 cycles with MOSI/ aCS = high, setting up reset command
        -- stay in state '1' until 74 clks counted
        init_cnt <= init_cnt + 1;
        if( init_cnt = x"4A" - 1) then
          spi_state       <= spi_state + 1;
          init_cnt      <= x"00";
          acs_sig           <= '0';
              main_mosi_reg <= '0';
        end if;

      elsif(spi_state = x"02") then     ---- CMD0 ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd        <= start & "000000" & argument & CRC;           -- Build cmd
                    rsp_len    <= rsp_1_len;                                     -- Configure response length for RX state machine
                    tx_trigger <= '1';                             -- Trigger transmit state machine
                    spi_trigger    <= '1';

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
          rx_trigger <= '0';                                         -- Reset RX state machine for next CMD

          -------- Handle response for particular command ----
          if rx_data(7 downto 0) = resp_idle then                -- handle Response from RX for CMD0 (idle)
            spi_state <= spi_state + 1;                                -- go to next command if response is valid
          else
            spi_state <= x"02";                                    -- otherwise restart CMD0 from beginning
          -------- End Response Handling ----
          end if;
        end if;

      elsif(spi_state = x"03") then      ---- CMD8 ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd         <= start & "001000" & cmd_8_arg & CRC;            -- Build cmd
                    rsp_len     <= rsp_7_len;                                     -- Configure response length for particular command
                    tx_trigger   <= '1';                              -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    rx_trigger <= '1';

        elsif rx_done = '1' then
          rx_trigger <= '0';                                             -- Reset RX state machine for next CMD

          -------- Handle response for particular command ----
          if rx_data = cmd_8_resp then                            -- handle Response from RX for CMD8
            spi_state <= spi_state + 1;                                    -- go to next command if response is valid
            cmd8_scss <= '1';
          elsif rx_data(39 downto 32) = resp_illeg then                  -- Illegal command - SD must be 'version 1.0'
            spi_state <= spi_state + 1;                                    -- Jump to CMD58 to check allowed voltage
          elsif rx_data(15 downto 8) /= cmd_8_arg(15 downto 8) then
            spi_state <= x"03";                                        -- Voltage check pattern incorrect , Go to fault state, record state/ response
          else
            spi_state <= x"02";                                        -- otherwise restart CMD0 from beginning
          end if;
        end if;
                    -------- End Response Handling ----

            elsif(spi_state = x"04") then     ---- CMD58 Voltage ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd       <= start & "111010" & cmd_58_arg & CRC;              -- Build cmd
                    rsp_len   <= rsp_3_len;                                         -- Configure response length for particular command
                    tx_trigger   <= '1';                                -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
          rx_trigger <= '0';                                            -- Reset RX state machine for next CMD

          -------- Handle response for particular command ----
          if rx_data = cmd_58_resp then                           -- handle Response from RX for CMD58
            spi_state <= spi_state + 1;                                   -- go to next command if response is valid
          elsif rx_data(20) = '1' or rx_data(21) = '1' then             -- 3.2-3.3V  OR 3.3-3.4V mode supported, move on to next command
            spi_state <= spi_state + 1;
          else
            spi_state <= x"99";                                       -- fault
          end if;
          -------- End Response Handling ----
                end if;

            elsif(spi_state = x"05") then     ---- CMD55 ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd        <= start & "110111" & cmd_55_arg & CRC;              -- Build cmd
                    rsp_len    <= rsp_1_len;                                        -- Configure response length for particular command
                    tx_trigger <= '1';                                -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
                    rx_trigger <= '0';                                            -- Reset TX state machine, Enable RX

          -------- Handle response for particular command ----
          if rx_data(7 downto 0) = resp_idle then                   -- handle Response from RX for CMD55
            spi_state <= spi_state + 1;                                     -- go to next command if response is valid
          else
            spi_state <= x"99";                                         -- otherwise go to fault state
          end if;
          -------- End Response Handling ----
                end if;

            elsif(spi_state = x"06") then     ---- ACMD41 ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd        <= start & "101001" & acmd_41_arg & CRC;              -- Build cmd
                    rsp_len    <= rsp_1_len;                                        -- Configure response length for particular command
                    tx_trigger <= '1';                                -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then                                  -- as tx_done signal comes in, turn off state machine
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
          rx_trigger <= '0';

           -------- Handle response for particular command ----
           if rx_data(7 downto 0) = resp_idle then                   -- handle Response from RX for ACMD41
            spi_state <= x"05";                                       -- Repeat CMD55/ ACMD41 until x"0000" is returned
           elsif rx_data(7 downto 0) = x"00" then
            spi_state <= spi_state + '1';                                 -- Go to next command, Initialization is finished
           else
            spi_state <= x"99";                                       -- otherwise restart CMD0 from beginning
           end if;
           -------- End Response Handling ----
                end if;

            elsif(spi_state = x"07") then     ---- CMD58 Mode ----
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd        <= start & "111010" & cmd_58_arg & CRC;              -- Build cmd
                    rsp_len    <= rsp_3_len;                                        -- Configure response length for particular command
                    tx_trigger <= '1';                                -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then                                  -- as tx_done signal comes in, turn off state machine
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
          rx_trigger <= '0';

          -------- Handle response for particular command ----
          if rx_data = cmd_58_resp then                               -- handle Response from RX for CMD58
            if(cmd8_scss = '1') then
              spi_hcs <= '1';
            end if;
            spi_state <= spi_state + '1';
          elsif rx_data(31 downto 30) = "11" then
            if(cmd8_scss = '1') then
              spi_hcs <= '1';
            end if;
            spi_state <= spi_state + '1';                                 -- Go to next command, Initialization is finished
          else
            spi_state <= x"99";                                       -- fault
          end if;
          -------- End Response Handling ----
                end if;

            elsif(spi_state = x"08") then      ---- Block Read ----
                if tx_trigger = '0' and read_trigger = '0' then
                    high_trigger    <= '1';
                    cmd        <= start & "010010" & cmd_18_arg & CRC;               -- Build cmd
                    tx_trigger <= '1';                                 -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    read_trigger <= '1';

                elsif read_done = '1' then
                    -------- Handle response for particular command ----
          read_trigger <= '0';
          -- error handle --
          if read_error = read_idle_error then
            spi_state <= x"08";
          elsif read_error = read_status_error then
            spi_state <= x"99";
          end if;
          ------------------
        elsif block_done = '1' then
          if read_block_count = block_count then
            read_trigger <= '0';
            spi_state <= spi_state + '1';
          else
            read_block_count <= read_block_count + '1';
          end if;
          -------- End Response Handling ----
                end if;

            elsif spi_state = x"09" then
                if tx_trigger = '0' and rx_trigger = '0' then
                    cmd        <= start & "001100" & cmd_12_arg & CRC;               -- Build cmd
                    rsp_len    <= rsp_1_len;                                         -- Configure response length for particular command
                    tx_trigger <= '1';                                 -- Trigger transmit state machine

                -- Runs in parallel with TX/ RX state machines to keep tabs
                elsif tx_done = '1' then
                    tx_trigger <= '0';
                    rx_trigger <= '1';

                elsif rx_done = '1' then
          rx_trigger <= '0';

          -------- Handle response for particular command ----
          if rx_data(7 downto 0) = resp_idle then                      -- handle Response from RX for CMD (idle)
            spi_state <= x"99";                                          -- go to next command if response is valid
          else
            spi_state <= x"02";                                          -- otherwise restart CMD0 from beginning
          -------- End Response Handling ----
           end if;
                end if;

            elsif(spi_state = x"99") then     ---- Fault/ Idle  ----
                fault <= '1';
      else

      end if;
    end if;
  end if;
end process;


spi_tx : process(clk_in)
begin
  if(spi_clk_falling = '1') then
    if tx_trigger = '1' then
      if tx_cnt < cmd_len then
        tx_cnt      <= tx_cnt + 1;
        mosi_reg    <= tx_data(natural(to_integer(unsigned(cmd_len - 1))));          -- grab the MSB of tx_data
        tx_data     <= std_logic_vector(shift_left(unsigned(tx_data),1));          -- shift tx_data left for MSB-first transmission
      else
        tx_done     <= '1';                                    -- reset tx state machine
      end if;
    else
      mosi_reg <= '1';                                                                  -- default - hold mosi high so slave can detect start of transmission
      tx_data  <= cmd;
      tx_cnt   <= x"00";
      tx_done  <= '0';
    end if;
  end if;
end process;

spi_rx : process(clk_in)
begin
  if(spi_clk_rising = '1') then

    miso_reg <= MISO;

    if rx_trigger = '1' then
      if(rx_cont = '0') then
        if MISO = '0' and miso_reg = '1' then                   -- miso transitioned, sending first bit of response sequence
          rx_cont     <= '1';
        else
          rx_detect_cnt <= rx_detect_cnt + '1';                     -- Track state of response, if no response in 16 cycles, must reset to CMD0
        end if;
      end if;

      if rx_detect_cnt  = x"0F" then                                  -- count up to 16 (15 plus cycle delay)
        rx_detect_cnt <= x"00";                                     -- Reset response timeout
        rx_done       <= '1';                                         -- tell top level SM to disable Reception of data
      end if;

      if rx_cont = '1' then
        if rx_cnt < rsp_len then
          rx_data(0)           <= miso_reg;
          rx_data(39 downto 1) <= rx_data(38 downto 0);
          rx_cnt               <= rx_cnt + 1;
        else
          rx_cnt  <= x"00";
          rx_done <= '1';
          rx_cont <= '0';
        end if;
      end if;
      else
            rx_data       <= x"0000000000";
            rx_detect_cnt <= x"00";
            rx_cnt        <= x"00";
            rx_cont       <= '0';
            rx_done       <= '0';
      end if;
  end if;
end process;


read_rx : process(clk_in)
begin
  if(spi_clk_rising = '1') then

    miso_reg_rd <= MISO;

    if read_trigger = '1' then
      if read_cont = '0' then
        if MISO = '0' and miso_reg_rd = '1' then                -- miso transitioned, sending first bit of response sequence
          read_cont       <= '1';
        else
          read_detect_cnt <= read_detect_cnt + '1';                   -- Track state of response, if no response in 16 cycles, must reset to CMD0
        end if;
      else
        if read_cnt < read_length then
          read_data(0)             <= miso_reg_rd;
          read_data(4127 downto 1) <= read_data(4126 downto 0);
          read_cnt                 <= read_cnt + '1';
          sample_cnt               <= sample_cnt + '1';
          block_done               <= '0';

          if read_cnt = x"0008" and block_done = '0' then                 -- check for first response - idle state
            if read_data(7 downto 0) /= resp_idle then
              read_error      <= read_idle_error;
              read_done       <= '1';
              read_cont       <= '0';
            end if;
          elsif read_cnt = x"0010" then                  -- check for status response
            if read_data(7 downto 0) /= read_status_ok then
              read_error      <= read_status_error;
              status_error    <= read_data(7 downto 0);
              read_done       <= '1';
              read_cont       <= '0';
            end if;
          elsif sample_cnt = x"0030" then                               -- count number of samples that come in - multiples of 32
            sample_out <= read_data(31 downto 0);
            sample_cnt <= x"0000";
          end if;
        else
          read_cnt  <= x"0008";                                        -- set count to 16, starting at the data_block read
          sample_cnt <= x"0008";
          read_data <= (others => '0');
          block_done <= '1';
        end if;
      end if;

      if read_detect_cnt  = x"0010" then                                -- count up to 16
        read_detect_cnt <= x"0000";                                     -- Reset response timeout
        read_done       <= '1';                                         -- tell top level SM to disable Reception of data
      end if;

      else
         read_data <= (others => '0');
         read_detect_cnt <= x"0000";
         read_cnt        <= x"0000";
         sample_cnt      <= x"0000";
         read_error      <= "000";
           read_cont       <= '0';
           read_done       <= '0';
      end if;
  end if;
end process;

end Behavioral;
