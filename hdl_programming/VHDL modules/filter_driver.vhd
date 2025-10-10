library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity filter_driver is
generic(
	AXI_WIDTH	    	: integer	:= 32		-- address, data, register width 
);
Port (
	sys_reset :   in std_logic;			-- system reset trigger	 
	mclk      :   out std_logic;											-- spi clk					PMOD1_6	- 	R23
	mosi      :   out std_logic;    									-- spi data					PMOD1_5 - 	T23
	strobe    :   out std_logic;											-- spi sel-load			PMOD1_4	-		J24
	inhibit   :   out std_logic;											-- spi inhibit			PMOD1_7	-		R22
	sel_out   :   out std_logic_vector(3 downto 0);		-- spi sel-device		PMOD1_0(3)	-	P22
																										--									PMOD1_1(2)	-	N22
																										--									PMOD1_2(1)	-	J20
																										--									PMOD1_3(0)	-	K24
	-- AXI interface ports
	S_AXI_ACLK		: in std_logic; 
	S_AXI_ARESETN	: in std_logic;  
	S_AXI_AWADDR	: in std_logic_vector(AXI_WIDTH-1 downto 0);			
	S_AXI_AWVALID	: in std_logic;                             
	S_AXI_WDATA   : in std_logic_vector(AXI_WIDTH-1 downto 0); 
	S_AXI_WVALID	: in std_logic;                         
	S_AXI_BREADY	: in std_logic;
	S_AXI_WSTRB	  : in std_logic_vector((AXI_WIDTH/8)-1 downto 0);  
  S_AXI_AWREADY	: out std_logic;                                     
	S_AXI_WREADY	: out std_logic;   	                                   
  S_AXI_BRESP	  : out std_logic_vector(1 downto 0);   	               
	S_AXI_BVALID	: out std_logic;																			
	S_AXI_AWPROT	: in std_logic_vector(2 downto 0);                     
	S_AXI_ARADDR	: in std_logic_vector(AXI_WIDTH-1 downto 0);		  
	S_AXI_ARVALID	: in std_logic;		                                    
	S_AXI_RREADY	: in std_logic;		                                    
	S_AXI_ARREADY	: out std_logic;                                      	
	S_AXI_RDATA	  : out std_logic_vector(AXI_WIDTH-1 downto 0);  	 
	S_AXI_RRESP	  : out std_logic_vector(1 downto 0);		                 
	S_AXI_RVALID	: out std_logic;   	                                   
	S_AXI_ARPROT	: in std_logic_vector(2 downto 0)
);
end filter_driver;

architecture Behavioral of filter_driver is

component axi_interface
port(
	REG_ADDR_00	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_04	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_08	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_0C	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_10	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_14	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_18	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_1C	: out std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_20	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_24	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_28	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_2C	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_30	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_34	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_38	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	REG_ADDR_3C	: in std_logic_vector(AXI_WIDTH-1 downto 0);
	s_axi_aclk		: in std_logic; 
	s_axi_aresetn	: in std_logic;  
	s_axI_awaddr	: in std_logic_vector(AXI_WIDTH-1 downto 0);	
	s_axi_awvalid	: in std_logic;           
	s_axi_wdata   : in std_logic_vector(AXI_WIDTH-1 downto 0); 
	s_axi_wvalid	: in std_logic;   
	s_axi_bready	: in std_logic;
	s_axi_wstrb	  : in std_logic_vector((AXI_WIDTH/8)-1 downto 0);  
	s_axi_awready	: out std_logic;
	s_axi_wready	: out std_logic;     
	s_axi_bresp	  : out std_logic_vector(1 downto 0);    	
	s_axi_bvalid	: out std_logic;	
	s_axi_awprot	: in std_logic_vector(2 downto 0);   
	s_axi_araddr	: in std_logic_vector(AXI_WIDTH-1 downto 0);	
	s_axi_arvalid	: in std_logic;		 
	s_axi_rready	: in std_logic;		 
	s_axi_arready	: out std_logic;   
	s_axi_rdata		: out std_logic_vector(AXI_WIDTH-1 downto 0);  
	s_axi_rresp	  : out std_logic_vector(1 downto 0);		
	s_axi_rvalid	: out std_logic; 
	s_axi_arprot	: in std_logic_vector(2 downto 0)
);
end component;

-- input/ output data buffers
signal reg_data			: std_logic_vector(31 downto 0);	-- register to shift out on go command
signal reg_strobe   : std_logic;
signal reg_inhibit  : std_logic;
signal reg_mclk			: std_logic;
signal reg_mosi			: std_logic; 

-- internal regs
signal cntrl_state  : std_logic_vector(1 downto 0);
signal shift_count	: std_logic_vector(31 downto 0);
signal clk_div_cnt	: integer;
signal trig					: std_logic;
signal spi_rdy_dr_0	: std_logic; 
signal spi_rdy_dr_1	: std_logic; 
signal spi_en       : std_logic;
signal shift_en			: std_logic;

-- spi_clk domain
-- double register
signal spi_en_dr_0	: std_logic;
signal spi_en_dr_1	: std_logic;
signal spi_ready		: std_logic; 

-- clk divider
signal clk_cnt : std_logic_vector(15 downto 0);
signal spi_clk : std_logic;

-- AXI Slave Registers  - internal to SPI device
signal tx_data  : std_logic_vector(31 downto 0);		-- addr 00					, data to transmit
signal data_len	: std_logic_vector(31 downto 0);		-- addr 04					, length of data string
signal freq_div	: std_logic_vector(31 downto 0);		-- addr 08					, divider for spi_clk relative to 100 MHz
signal sel_bits	: std_logic_vector(31 downto 0);		-- addr 0C					, select device to program
signal spi_strb	: std_logic_vector(31 downto 0);		-- addr 10					, start the spi-transaction process
signal spi_status : std_logic_vector(31 downto 0);	-- addr 14 (read)		, CPU checks status of transmission - read only  

---
signal spi_strb_prev : std_logic;

---- Internal 
constant addr_len       : integer := 8;
signal axi_reset        : std_logic; 
signal read_data        : std_logic_vector(AXI_WIDTH-1 downto 0); 
signal int_read_addr    : std_logic_vector(addr_len-1 downto 0);
signal int_write_addr   : std_logic_vector(addr_len-1 downto 0);

--attribute mark_debug : string; 

---- AXI slave registers
--attribute mark_debug of tx_data			: signal is "true";
--attribute mark_debug of data_len		: signal is "true";
--attribute mark_debug of freq_div		: signal is "true";
--attribute mark_debug of sel_bits		: signal is "true";
--attribute mark_debug of spi_strb		: signal is "true";
--attribute mark_debug of spi_status	: signal is "true";

------ SPI signals 
--attribute mark_debug of reg_data 		: signal is "true";
--attribute mark_debug of reg_strobe 	: signal is "true";
--attribute mark_debug of reg_inhibit : signal is "true";
--attribute mark_debug of reg_mosi : signal is "true";
--attribute mark_debug of reg_mclk : signal is "true";
--attribute mark_debug of spi_clk : signal is "true";
--attribute mark_debug of shift_en : signal is "true";
--attribute mark_debug of shift_count : signal is "true";

------ Satate machine
--attribute mark_debug of spi_en			: signal is "true";
--attribute mark_debug of spi_en_dr_0	: signal is "true";
--attribute mark_debug of spi_en_dr_1	: signal is "true";
--attribute mark_debug of spi_ready		: signal is "true";
--attribute mark_debug of spi_rdy_dr_0	: signal is "true";
--attribute mark_debug of spi_rdy_dr_1	: signal is "true";
--attribute mark_debug of spi_strb_prev	: signal is "true";
--attribute mark_debug of cntrl_state	: signal is "true";

begin		-- Asynchronous connections

---- connect AXI interface to our spi device 
axi_interface_inst : axi_interface
port map(
	REG_ADDR_00	=>	tx_data,
	REG_ADDR_04	=>	data_len,
	REG_ADDR_08	=>	freq_div,
	REG_ADDR_0C	=>	sel_bits,
	REG_ADDR_10	=> 	spi_strb,
	REG_ADDR_14	=>  open, 
	REG_ADDR_18	=> 	open,
	REG_ADDR_1C	=> 	open,
	REG_ADDR_20	=> 	spi_status,
	REG_ADDR_24	=> 	(others => '0'),
	REG_ADDR_28	=> 	(others => '0'),
	REG_ADDR_2C	=> 	(others => '0'),
	REG_ADDR_30	=> 	(others => '0'),
	REG_ADDR_34	=> 	(others => '0'),
	REG_ADDR_38	=> 	(others => '0'),
	REG_ADDR_3C	=> 	(others => '0'),
	s_axi_aclk		=>	S_AXI_ACLK,
	s_axi_aresetn	=>	S_AXI_ARESETN,
	s_axI_awaddr	=>	S_AXI_AWADDR,
	s_axi_awvalid =>  S_AXI_AWVALID,
	s_axi_wdata		=>	S_AXI_WDATA,
	s_axi_wvalid	=>	S_AXI_WVALID,
	s_axi_bready	=>	S_AXI_BREADY,
	s_axi_wstrb		=>	S_AXI_WSTRB,
	s_axi_awready	=>	S_AXI_AWREADY,
	s_axi_wready	=>	S_AXI_WREADY,
	s_axi_bresp 	=>	S_AXI_BRESP,
	s_axi_bvalid	=>	S_AXI_BVALID,
	s_axi_awprot	=>	S_AXI_AWPROT,
	s_axi_araddr	=>	S_AXI_ARADDR,
	s_axi_arvalid	=>	S_AXI_ARVALID,
	s_axi_rready	=>	S_AXI_RREADY,
	s_axi_arready	=>	S_AXI_ARREADY,
	s_axi_rdata		=>	S_AXI_RDATA,
	s_axi_rresp	  =>	S_AXI_RRESP,
	s_axi_rvalid	=>	S_AXI_RVALID,
	s_axi_arprot	=>	S_AXI_ARPROT
);

-- General Process
-- 5 devices are being written to. Each one is sharing the same SPI bus (MOSI/MCLK)
-- A Demux is used to select which device is being spoken to. The process is:
-- 		choose select bits
--		strobe -> latching in select bits
--		drop inhibit line
-- Then, we start the SPI BUS, transferring data into that device
--

-- Setup Clk divider max count 
clk_div_cnt	<= to_integer(shift_right(unsigned(freq_div),1));		-- divide freq_div value by two to get correct clk division 

-- track status of transaction for Master 
spi_status(0)	<= spi_en_dr_1;	-- grab spi_en as seen from the low speed domain. Keeps CPU in sync with SPI_CLK domain...

-- Setup SPI ports from internal regs
reg_mclk  <=	spi_clk when shift_en = '1' else '0';
reg_mosi  <=	reg_data(to_integer(unsigned(data_len))-1);		-- select MSB of tx_data for transmission



-- Filter Board signals
mosi		<= reg_mosi;
mclk		<= reg_mclk;
strobe  <=	reg_strobe;							-- latch data into DEMUX/ 8 bit-shift register
--inhibit <=	reg_inhibit;						-- disable outputs of DEMUX (all '1') / 8-bit Shift Register (all 'Z')
-- debugging
inhibit		<= spi_clk;
--
sel_out <= 	sel_bits(3 downto 0);

clocking: process(S_AXI_ACLK)	begin
	if rising_edge(S_AXI_ACLK) then
		if sys_reset = '1' then				 		-- system reset state
			clk_cnt  <= x"0000";
			spi_clk  <= '0';
		else
			if(clk_cnt < clk_div_cnt - 1) then
				clk_cnt	<= clk_cnt + '1'; 
			else
				spi_clk	<= not spi_clk;
				clk_cnt	<= x"0000";
			end if; 
		end if;
	end if;
end process;

-- allow SW strobe to enable system
-- SPI cntrlr will turn itself off after its completed transmitting
spi_enable : process(S_AXI_ACLK) begin
	if rising_edge(S_AXI_ACLK) then
		if sys_reset = '1' then
			spi_en <= '0';
		else
			-- rising edge check
			spi_strb_prev	<= spi_strb(0);
			
			-- double register spi_ready
			spi_rdy_dr_0	<= spi_ready;
			spi_rdy_dr_1	<= spi_rdy_dr_0;
			 
			-- rising edge of spi-strobe (from CPU) + spi_ready (from spi_clk domain)
			if spi_rdy_dr_1 = '1' then 
				if spi_strb(0) = '1' and spi_strb_prev = '0' then spi_en <= '1'; end if; 
			else
				spi_en	<= '0';
			end if;
			 
		end if;
	end if; 
end process;

spi_cntrlr: process(spi_clk)	begin
if rising_edge(spi_clk) then	
	if sys_reset = '1' then 
		cntrl_state	<= (others => '0');		-- controller signals 
		shift_en		<= '0';
		shift_count	<= (others => '0');
		reg_data		<= tx_data;
		spi_ready		<= '1';
		--
		reg_inhibit		<= '0';				-- selected output is enabled by 'inhibit = 0'
		reg_strobe		<= '0';				-- output follows changes in input when 'strobe = '1'
	else        
		-- double register the spi_en signal into our spi_clk domain               
		spi_en_dr_0	<= spi_en;
		spi_en_dr_1	<= spi_en_dr_0;
		
		if spi_en_dr_1 = '1' then
			case cntrl_state is
				when "00" =>
					reg_strobe		<= '1';
					cntrl_state		<= "01";
				when "01" =>
					reg_strobe    <= '0';
					shift_en			<= '1';
					cntrl_state		<= "10";
				when "10" =>
					if shift_count = x"00000000" then 
						shift_en		<= '0';
						cntrl_state	<= "11";
						if data_len = x"00000004" then
							reg_strobe <= '1';				-- strobe the shift register to enable the outputs
						end if;
					end if;
        when others =>
        	reg_strobe		<= '0';
      		-- "shift" will reset the "cntrlr" when done
      end case;
		else
			cntrl_state   <= (others => '0');
			reg_strobe  <= '0';
			shift_en		<= '0'; 
		end if;
	end if;    
end if;
-----------------------------------			-- shift data on falling edge per SPI spec
if falling_edge(spi_clk) then 
	if shift_en = '1' then
		if shift_count < data_len - 1 then
			shift_count <= shift_count + '1';
			reg_data		<= std_logic_vector(shift_left(unsigned(reg_data),1));
		else
			shift_count	<= (others => '0');		-- reset data, reset "cntrlr" machine
			reg_data		<= tx_data;
			spi_ready		<= '0';								-- disable communication
		end if;
	else
		shift_count		<= (others => '0');
		reg_data			<= tx_data;
		spi_ready			<= '1';									-- prepare for next user trigger
	end if;
end if;
------------------------------------

end process;



end Behavioral; 