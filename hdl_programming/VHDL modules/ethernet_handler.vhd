--------------------------------------------------------
-- Create Date: 04/09/2021 04:05:37 PM
-- Module Name: axi_axis_ethernet_handler - Behavioral
--------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity axi_axis_ethernet_handler is

	generic(		
  -- setup for UDP/IP header	[MAC][IP][UDP][ADDR+FLUFF]	[14][20][8][4][2]	- 48 Bytes Total
  -- fluff bytes added to Address to allow Endian-Conversion to group data properly

  MAX_PKTLEN_BYTE : std_logic_vector(15 downto 0) := x"03EC";   -- Using payload of 956 bytes + 42 byte header + 6 byte addr+fluff = 1004 total pkt length -> FIFO is built on 1024
	PKT_FIFO_SIZE		: integer := (2);															-- how many packets of 'MAX_PKTLEN_BYTE' can fit in our fifo?
	DDR_FRD_PORT		: integer := (50000);													-- packets with Destination port: 50,000 are to have their contents stored in DDR
	FRD_HDR_LEN			: integer := (46);														-- [MAC][IP][UDP][DDR_ADDR]
	FRD_HDR_BIT			: integer := (46)*8;
	FRD_ADDR_IDX		: integer := (42)*8														-- start of DDR4 starting address from TOP of packet 
	);
	
  Port ( 
  -- sys Reset for 300M Master Out
  sys_rst					    : in std_logic; 
  dma_sys_rstn				: out std_logic; 
  --- Axi Stream Interface -- Slave Receive
  axi_str_aresetn			: in std_logic; 
  axi_str_aclk				: in std_logic;
  -- Receive Data 
  axi_str_rxd_aresetn	: in std_logic;
  axi_str_rxd_tvalid	: in std_logic;
  axi_str_rxd_tready	: out std_logic;
  axi_str_rxd_tlast		: in std_logic;
  axi_str_rxd_tkeep		: in std_logic_vector(3 downto 0);
  axi_str_rxd_tdata		: in std_logic_vector(31 downto 0);
  -- Receive status 
  axi_str_rxs_tvalid	: in std_logic; 
  axi_str_rxs_tready	: out std_logic;
  axi_str_rxs_tlast		: in std_logic;
  axi_str_rxs_tkeep		: in std_logic_vector(3 downto 0);
  axi_str_rxs_tdata		: in std_logic_vector(31 downto 0);
  -- Receive Forward ---------------------------------------
  axi_str_frd_rxd_aresetn	: in std_logic; 
  axi_str_frd_rxd_tvalid	: out std_logic;
  axi_str_frd_rxd_tready	: in std_logic;
  axi_str_frd_rxd_tlast		: out std_logic;
  axi_str_frd_rxd_tkeep		: out std_logic_vector(3 downto 0);
  axi_str_frd_rxd_tdata		: out std_logic_vector(31 downto 0);
  ----------------------------------------------------------
  
  --- Axi Stream Interface -- Master Transmit
  -- Transmit Data
  axi_str_txd_tvalid	    : out std_logic;
  axi_str_txd_tready	    : in std_logic;
  axi_str_txd_tlast		    : out std_logic;
  axi_str_txd_tkeep		    : out std_logic_vector(3 downto 0);
  axi_str_txd_tdata		    : out std_logic_vector(31 downto 0);
  -- Transmit Control 
  axi_str_txc_tvalid	    : out std_logic; 
  axi_str_txc_tready	    : in std_logic;
  axi_str_txc_tlast		    : out std_logic;
  axi_str_txc_tkeep		    : out std_logic_vector(3 downto 0);
  axi_str_txc_tdata		    : out std_logic_vector(31 downto 0);
  -- Transmit Forward ---------------------------------------
  axi_str_frd_txd_aresetn	: in std_logic;
  axi_str_frd_txd_tvalid	: in std_logic;
  axi_str_frd_txd_tready	: out std_logic;
  axi_str_frd_txd_tlast		: in std_logic;
  axi_str_frd_txd_tkeep		: in std_logic_vector(3 downto 0);
  axi_str_frd_txd_tdata		: in std_logic_vector(31 downto 0);
  -----------------------------------------------------------
  
  -- AXI MASTER
  M_AXI_ACLK_d			: out std_logic;
  M_AXI_ARESETN_d		: out std_logic; 
  -- M --> S
  M_AXI_AWADDR_d		: out std_logic_vector(31 downto 0);    
  M_AXI_AWVALID_d		: out std_logic;                          
  M_AXI_WDATA_d     : out std_logic_vector(31 downto 0);   	 
  M_AXI_WVALID_d		: out std_logic;                         
  M_AXI_BREADY_d		: out std_logic;
  M_AXI_WSTRB_d	    : out std_logic_vector(3 downto 0);      
  M_AXI_AWPROT_d		: out std_logic_vector(2 downto 0);
  -- S --> M
  M_AXI_AWREADY_d		: in std_logic;                                     
  M_AXI_WREADY_d		: in std_logic;   	                                
  M_AXI_BRESP_d	    : in std_logic_vector(1 downto 0);   	             
  M_AXI_BVALID_d		: in std_logic
  );
end axi_axis_ethernet_handler;

architecture Behavioral of axi_axis_ethernet_handler is  

-- Intermediate axi_reg for internal use with FIFO Control
signal s_axi_arready_t    : std_logic;
-- Receive Internal Signals 
signal rx_data						    : std_logic_vector(31 downto 0);
signal rx_data_state			    : std_logic_vector(1 downto 0);
signal rx_wrd_cnt					    : std_logic_vector(15 downto 0);	
signal rx_byte_cnt       	    : std_logic_vector(15 downto 0);
signal rx_bit_cnt					    : std_logic_vector(31 downto 0);
signal axi_rxd_reorder		    : std_logic_vector(31 downto 0);
signal frd_header					    : std_logic_vector(FRD_HDR_BIT - 1 downto 0);	-- Receive packet organization
signal rx_bit_cnt_idx			    : integer;
signal rxd_tready					    : std_logic;  -- intermediate signal for axi_str_rxd_tready
signal rxd_storing				    : std_logic;
signal rxd_storing_prev		    : std_logic;
signal axis_rx_tready			    : std_logic;	-- Internally controlled AXIS

-- Receive FIFO + Tracker FIFO's
type fifo_track is array (0 to PKT_FIFO_SIZE-1) of std_logic_vector(31 downto 0); -- Used for RX and TX fifo tracking 
type pkt_frd    is array (0 to PKT_FIFO_SIZE-1) of std_logic_vector(48 downto 0); -- contains Dest Port | DDR Start Address | CRC-pass/fail 
signal rxfifo_pkt_track 			: fifo_track; 
signal rxfifo_pkt_frd     		: pkt_frd; 
signal rx_fifo_dout           : std_logic_vector(31 downto 0);
signal rx_fifo_din            : std_logic_vector(31 downto 0);	
signal rx_fifo_full           : std_logic;
signal rx_fifo_empty          : std_logic;
signal rx_fifo_wr_en          : std_logic;
signal rx_fifo_rd_en          : std_logic;			
signal rx_fifo_busy       		: std_logic; 
signal rx_fifo_busy_store     : std_logic;
signal rx_fifo_busy_forward   : std_logic;
signal rxfifo_rxfrd_tvalid_en : std_logic;
signal rxfifo_rx_tready_en	  : std_logic; 	
signal rx_wren_prev       		: std_logic; 
signal rx_frd_cnt      				: integer; 
signal rxfrd_pkt_idx      		: integer; 
signal rx_pkt_idx         		: integer; 
	
-- Receive Forward Signals
signal rx_frd_byte_cnt		    : std_logic_vector(31 downto 0); 
signal rx_frd_byte_limit	    : std_logic_vector(31 downto 0);
signal rx_frd_state				    : std_logic_vector(1 downto 0);
signal rx_frd_tvalid			    : std_logic;
signal rx_frd_bit_cnt			    : integer;
signal rx_frd_en					    : std_logic; 
signal rx_frd_en_prev			    : std_logic; 
signal rx_frd_ready				    : std_logic; 
signal rx_frd_start				    : std_logic; 
signal rx_frd_rd_en 			    : std_logic; 
-- Receive control signals 
type cntrl_data is array (0 to 5) of std_logic_vector(31 downto 0); -- Extra bit for tagging as DDR4 OR DMA 
signal rx_cntrl_word 			    : cntrl_data; 
signal rx_cntrl_data			    : std_logic_vector(31 downto 0);
signal rx_cntrl_state			    : std_logic_vector(1 downto 0);
signal rx_cntrl_word_cnt 	    : std_logic_vector(3 downto 0);
signal crc_ip_udp_pass        : std_logic;
-- Status Words
-- W0:  [31:28] - Flag = 0x5 (Receive Status Frame)
--			[27:0]	- Reserved
-- W1:	[31:16]	- Reserved
--			[15:0]	- Multicast_Addr_Upper (47:32)
-- W2:	[31:0]	- Multicast Addr_Lower (31:0)
-- W3:	[31] MII Align Err, [30] Len Field Err, [29] Bad OP Code, [28] Pause Frame, [27] VLAN Frame
--			[26] Max Len Error, [25] Cntrl Frame, [24:11]	- Length Bytes
--			[10] Multicast Frame, [9] Broadcast Frame, [8] FCS Error, [7] Bad Frame, [6] Good Frame
--			[5:3] RX Checksum Status, [2] Broadcast Frame Flag, [1] IP Multicast Frame Flag, [0] MAC Multicast Frame Flag
-- W4:	[31:16] - Type/Length		
-- 			[15:0]	- Receive Raw Checksum	(FCS is included if FCS stripping is not enabled)
-- W5:	[31:16] - First Two Data bytes
--			[15:0]	- Receive Frame Byte Length		
--------------------------------------------------------------------

-- Transmit axi-s Signals 
signal tlast          		    : std_logic;
signal tvalid         		    : std_logic;	
signal tkeep          		    : std_logic_vector(3 downto 0);	
signal tdata          		    : std_logic_vector(31 downto 0);	
signal tx_byte_cnt				    : std_logic_vector(31 downto 0);  -- track where we are in the Frame
signal tx_byte_limit			    : std_logic_vector(31 downto 0);
-- TX Data State Machine
signal axis_tx_state			    : std_logic_vector(1 downto 0);
signal tx_en						      : std_logic;
signal tx_en_prev					    : std_logic; 
signal tx_ready					      : std_logic;
-- TX Forward
signal tx_frd_state			      : std_logic_vector(1 downto 0);
signal tx_frd_byte_cnt		    : std_logic_vector(15 downto 0);
signal tx_frd_tready		      : std_logic;
signal tx_frd_storing 	      : std_logic; 
signal tx_storing_prev 	      : std_logic; 
signal txfrd_txfifo_din       : std_logic_vector(31 downto 0);
signal tx_frd_wren            : std_logic; 
signal frd_txd_tready			    : std_logic;  -- Track axi_str_frd_txd_tready
-- TX FIFO signals 
signal tx_fifo_full           : std_logic;
signal tx_fifo_din            : std_logic_vector(31 downto 0);
signal tx_fifo_dout           : std_logic_vector(31 downto 0);
signal tx_fifo_wr_en          : std_logic;
signal tx_fifo_empty          : std_logic;
signal tx_fifo_rd_en          : std_logic;
signal tx_fifo_busy			      : std_logic;
signal tx_fifo_busy_forward	  : std_logic;
signal tx_fifo_busy_store		  : std_logic;
-- TX FIFO Management
signal txfifo_pkt_track 		  : fifo_track; 
signal tx_fifo_storing        : std_logic;
signal tx_pkt_cnt             : integer; 
signal txfrd_pkt_idx          : integer; 
signal tx_pkt_idx             : integer;
signal tx_reading             : std_logic; 
signal tx_reading_prev				: std_logic;
signal txfifo_txfrd_tready_en : std_logic; 
-- TX Control Signals
signal tckeep							    : std_logic_vector(3 downto 0);
signal tclast							    : std_logic;
signal tcdata							    : std_logic_vector(31 downto 0);
signal tcvalid						    : std_logic;
signal tx_cntrl_state 		    : std_logic_vector(1 downto 0);
signal tx_cntrl_ready			    : std_logic; 
signal tx_cntrl_word_cnt	    : std_logic_vector(15 downto 0); 
signal tx_cntrl_buf 			    : std_logic_vector(31 downto 0); 
signal tx_cntrl_en				    : std_logic;
constant cw0							    : std_logic_vector(31 downto 0) := b"1010" & x"0000000";  -- Normal TX Frame
constant cw1							    : std_logic_vector(31 downto 0) := x"00000000";						-- No TX Checksum Offloading
-- All control words are transmitted on TX_CNTRL Bus every frame (cw2,cw3,cw4,cw5 are equal to cw1)
-- TX Control Words 
-- cw2 -> TxCsBegin | TxCsInsert
-- cw3 -> Reserved | TxCsInit
-- cw4 -> Reserved..
-- cw5 -> Reserved..

-- AXI MASTER for DDR4 Streaming
-- Master to Slave
signal m_axi_awaddr				: std_logic_vector(31 downto 0);
signal m_axi_awvalid			: std_logic;
signal m_axi_wdata				: std_logic_vector(31 downto 0);
signal m_axi_wvalid				: std_logic;
signal m_axi_bready 			: std_logic;
signal m_axi_wstrb				: std_logic_vector(3 downto 0);
-- Slave to Master 
signal m_axi_awready 			: std_logic;
signal m_axi_wready 			: std_logic;
signal m_axi_bresp 				: std_logic_vector(1 downto 0);
signal m_axi_bvalid 			: std_logic;
signal m_axi_state 				: std_logic_vector(1 downto 0);
signal m_addr_count				: std_logic_vector(30 downto 0);
-- Signals for starting AXI_Master-write sequence
signal ms_en				: std_logic;
signal ms_ready				: std_logic;
signal sample_out     		: std_logic_vector(31 downto 0);
signal load_word_cnt  		: std_logic_vector(31 downto 0);  -- Number of words to transmit 
signal addr_to_write		: std_logic_vector(31 downto 0);	
signal ddr_frd_state        : std_logic_vector(2 downto 0);
signal ddr_frd_en			: std_logic;
signal ddr_frd_en_prev		: std_logic; 
signal ddr_frd_start		: std_logic; 
signal ddr_frd_rd_en        : std_logic;
signal ddr_empty_rd_en		: std_logic; 
signal ddr_empty_start		: std_logic;
signal ddr_frd_count		: std_logic_vector(3 downto 0);
-- response from handler -> remote client 
signal ddr_txfifo_din     : std_logic_vector(31 downto 0);
signal ddr_resp_start     : std_logic;
signal ddr_frd_wren       : std_logic; 
signal resp_ip_crc        : std_logic_vector(19 downto 0);  -- ip_header CRC: 16 bits crc + 4 bits for carry 
signal resp_udp_crc       : std_logic_vector(19 downto 0);
signal resp_pkt           : std_logic_vector(383 downto 0); -- includes space for UDP header + resp_pass/fail
constant resp_pass        : std_logic_vector(47 downto 0) := x"000000000001";
constant resp_fail        : std_logic_vector(47 downto 0) := x"000000000000";

---- Define FIFO's 
component ethernet_handler_fifo is 
port(
clk   : in  std_logic; 
srst  : in  std_logic; 
full  : out std_logic; 
din   : in  std_logic_vector(31 downto 0);
wr_en : in  std_logic; 
empty : out std_logic; 
dout  : out std_logic_vector(31 downto 0);
rd_en : in  std_logic; 
wr_rst_busy : out std_logic; 
rd_rst_busy : out std_logic 
);
end component;

-------- Debug -------------------------------------------------
attribute mark_debug		: string; 
-- Transmit Control --------------------------------------------
--attribute mark_debug of axi_str_txc_tready  : signal is "true";
--attribute mark_debug of axi_str_txc_tlast  	: signal is "true";
--attribute mark_debug of axi_str_txc_tkeep  	: signal is "true";
--attribute mark_debug of axi_str_txc_tdata  	: signal is "true";
--attribute mark_debug of axi_str_txc_tvalid 	: signal is "true";
--attribute mark_debug of tx_cntrl_en 				: signal is "true";
-- Transmit Data ---------------------------------------------
--attribute mark_debug of axi_str_txd_tready  : signal is "true";
--attribute mark_debug of axi_str_txd_tlast  	: signal is "true";
--attribute mark_debug of axi_str_txd_tkeep  	: signal is "true";
--attribute mark_debug of axi_str_txd_tdata  	: signal is "true";
--attribute mark_debug of axi_str_txd_tvalid 	: signal is "true";
--attribute mark_debug of axis_tx_state				: signal is "true";
--attribute mark_debug of tx_byte_limit				: signal is "true";
--attribute mark_debug of tx_byte_cnt					: signal is "true";
--attribute mark_debug of tx_en								: signal is "true";
--attribute mark_debug of tx_ready  					: signal is "true";
--attribute mark_debug of tx_fifo_rd_en  			: signal is "true";

-- Transmit Forward ------------------------------------------
--attribute mark_debug of tx_frd_state  			: signal is "true";
--attribute mark_debug of tx_frd_byte_cnt  		: signal is "true";
--attribute mark_debug of tx_frd_storing  		: signal is "true";
--attribute mark_debug of tx_storing_prev  		:	signal is "true";
--attribute mark_debug of txfrd_txfifo_din  	:	signal is "true";
--attribute mark_debug of tx_frd_wren  				: signal is "true";
--attribute mark_debug of tx_fifo_din  						: signal is "true";
--attribute mark_debug of tx_fifo_dout  					: signal is "true";
--attribute mark_debug of tx_frd_tready						: signal is "true";
--attribute mark_debug of axi_str_frd_txd_tvalid	: signal is "true";
--attribute mark_debug of axi_str_frd_txd_tlast		: signal is "true";
--attribute mark_debug of axi_str_frd_txd_tkeep		: signal is "true";
--attribute mark_debug of axi_str_frd_txd_tdata		: signal is "true";
-- TX Fifo Manager -----------------------------------------------
--attribute mark_debug of tx_fifo_empty  			  	: signal is "true";
--attribute mark_debug of tx_fifo_full		  	  	: signal is "true";
--attribute mark_debug of txfifo_pkt_track  			: signal is "true";
--attribute mark_debug of tx_fifo_storing  		  	: signal is "true";
--attribute mark_debug of txfrd_pkt_idx  					: signal is "true";
--attribute mark_debug of tx_pkt_idx  						: signal is "true";
--attribute mark_debug of tx_pkt_cnt  				  	: signal is "true";
--attribute mark_debug of tx_fifo_wr_en  					: signal is "true";
--attribute mark_debug of txfifo_txfrd_tready_en  : signal is "true";
--attribute mark_debug of tx_fifo_busy  	        : signal is "true";
--attribute mark_debug of tx_fifo_busy_forward  	: signal is "true";
--attribute mark_debug of tx_fifo_busy_store  	  : signal is "true";
-- Receive Data -----------------------------------------------
--attribute mark_debug of frd_header					: signal is "true";
--attribute mark_debug of rx_data_state  			: signal is "true";
--attribute mark_debug of rx_data							: signal is "true";
--attribute mark_debug of rxd_storing_prev		: signal is "true";
--attribute mark_debug of rxd_storing					: signal is "true";
--attribute mark_debug of rx_bit_cnt					: signal is "true";
--attribute mark_debug of rx_byte_cnt					: signal is "true";
--attribute mark_debug of rx_wrd_cnt					: signal is "true";
--attribute mark_debug of rxd_tready					: signal is "true";
--attribute mark_debug of axi_str_rxd_tvalid  : signal is "true";
--attribute mark_debug of axi_str_rxd_tready 	: signal is "true";
--attribute mark_debug of axi_str_rxd_tlast  	: signal is "true";
--attribute mark_debug of axi_str_rxd_tkeep  	: signal is "true";
--attribute mark_debug of axi_str_rxd_tdata  	: signal is "true";
-- Receive Status -----------------------------------------------
--attribute mark_debug of axi_str_rxs_tvalid   : signal is "true";
--attribute mark_debug of axi_str_rxs_tready   : signal is "true";
--attribute mark_debug of axi_str_rxs_tlast    : signal is "true";
--attribute mark_debug of axi_str_rxs_tkeep    : signal is "true";
--attribute mark_debug of axi_str_rxs_tdata  	 : signal is "true";
--attribute mark_debug of rx_cntrl_data        : signal is "true";
--attribute mark_debug of rx_cntrl_word_cnt    : signal is "true";
--attribute mark_debug of rx_cntrl_word        : signal is "true";
-- Receive Forward -----------------------------------------------
--attribute mark_debug of rx_frd_tvalid  					: signal is "true";
--attribute mark_debug of axi_str_frd_rxd_tready 	: signal is "true";
--attribute mark_debug of rx_frd_byte_cnt					: signal is "true";
--attribute mark_debug of rx_frd_byte_limit				: signal is "true";
--attribute mark_debug of rx_frd_state  					: signal is "true";
--attribute mark_debug of rx_frd_en  							: signal is "true";
--attribute mark_debug of rx_frd_ready  					: signal is "true";
--attribute mark_debug of axis_rx_tready					: signal is "true";
--attribute mark_debug of rx_frd_start			  		: signal is "true";
-- Receive FIFO Manager ----------------------------------------
--attribute mark_debug of rxfifo_pkt_track  		: signal is "true";
--attribute mark_debug of rxfifo_pkt_frd  			: signal is "true";
--attribute mark_debug of rxfifo_rx_tready_en  	: signal is "true";
--attribute mark_debug of rxfrd_pkt_idx  			  : signal is "true";
--attribute mark_debug of rx_frd_cnt  		    	: signal is "true";
--attribute mark_debug of rx_fifo_busy  			  : signal is "true";
--attribute mark_debug of rx_fifo_busy_store  	: signal is "true";
--attribute mark_debug of rx_fifo_busy_forward  : signal is "true";
--attribute mark_debug of rx_pkt_idx	  			  : signal is "true";
-- Receive FIFO -------------------------------------------------
--attribute mark_debug of rx_fifo_full  	  		: signal is "true";
--attribute mark_debug of rx_fifo_din  					: signal is "true";
--attribute mark_debug of rx_fifo_wr_en  				: signal is "true";
--attribute mark_debug of rx_fifo_empty  	  		: signal is "true";
--attribute mark_debug of rx_fifo_dout  	  		: signal is "true";
--attribute mark_debug of rx_fifo_rd_en     		:	signal is "true";
-- DDR_FORWARD --------------------------------------------------
--attribute mark_debug of load_word_cnt   			: signal is "true";
--attribute mark_debug of sample_out						: signal is "true";
--attribute mark_debug of m_addr_count					: signal is "true";
--attribute mark_debug of addr_to_write					: signal is "true";
--attribute mark_debug of ms_en				    			: signal is "true";
--attribute mark_debug of ms_ready		    			: signal is "true";
--attribute mark_debug of ddr_frd_en		  			: signal is "true";
--attribute mark_debug of ddr_frd_start					: signal is "true";
--attribute mark_debug of ddr_empty_rd_en				: signal is "true";
--attribute mark_debug of ddr_frd_count					: signal is "true";
--attribute mark_debug of ddr_txfifo_din				: signal is "true";
--attribute mark_debug of ddr_resp_start				: signal is "true";
--attribute mark_debug of ddr_frd_wren	  			: signal is "true";
--attribute mark_debug of ddr_frd_state	  			: signal is "true";
--attribute mark_debug of resp_ip_crc	    			: signal is "true";
--attribute mark_debug of resp_udp_crc	  			: signal is "true";
--attribute mark_debug of resp_pkt      			  : signal is "true";
-- AXI_MASTER Debug ---------------------------------------------
--attribute mark_debug of m_axi_state	: signal is "true";
-- Write --------------------------------------------------
--attribute mark_debug of m_axi_awaddr		: signal is "true";
--attribute mark_debug of m_axi_awvalid		: signal is "true";
--attribute mark_debug of m_axi_wdata			: signal is "true";
--attribute mark_debug of m_axi_bready		: signal is "true";
--attribute mark_debug of m_axi_wvalid		: signal is "true";
--attribute mark_debug of m_axi_wstrb			: signal is "true";
--attribute mark_debug of m_axi_awready		: signal is "true";
--attribute mark_debug of m_axi_wready		: signal is "true";
--attribute mark_debug of m_axi_bresp			: signal is "true";
--attribute mark_debug of m_axi_bvalid		: signal is "true";
--------------------------------------------------------------

begin	-- Asynch 

-- negative reset for DMA-accessible RAM 
dma_sys_rstn	<= not sys_rst;

-- Instantiate FIFO's 
-- FIFO's have First word fall through 
-- Valid data exists on output before issuing read (FWFT)
-- Each holds 4 packets of MAX_PKTLEN_BYTE + some extra space 
TX_SIDE_FIFO : ethernet_handler_fifo
port map(
clk     => axi_str_aclk,
srst    => sys_rst,
full    => tx_fifo_full,
din     => tx_fifo_din,
wr_en   => tx_fifo_wr_en,
empty   => tx_fifo_empty,
dout    => tx_fifo_dout,
rd_en   => tx_fifo_rd_en,
wr_rst_busy => open,
rd_rst_busy => open
);

RX_SIDE_FIFO : ethernet_handler_fifo
port map(
clk     => axi_str_aclk,
srst    => sys_rst,
full    => rx_fifo_full,
din     => rx_fifo_din,
wr_en   => rx_fifo_wr_en,
empty   => rx_fifo_empty,
dout    => rx_fifo_dout,
rd_en   => rx_fifo_rd_en,
wr_rst_busy => open,
rd_rst_busy => open
);

-- Tracks the current state of the TX_SIDE_FIFO
-- keeps track of number of network packets inside and their length in bytes 
-- Enables and disables 'axi_str_frd_txd_tready' to keep FIFO from overflowing
tx_fifo_busy <= tx_fifo_busy_forward or tx_fifo_busy_store;
TX_FIFO_MANAGER : process(axi_str_aclk) begin 
if rising_edge(axi_str_aclk) then 
  if axi_str_aresetn = '0' then 
    txfifo_pkt_track        <= (others => "00000000");
    txfrd_pkt_idx           <= PKT_FIFO_SIZE;
    tx_pkt_idx              <= PKT_FIFO_SIZE;
    tx_pkt_cnt              <= 0;
    txfifo_txfrd_tready_en  <= '1';
    tx_fifo_busy_store      <= '0';
    tx_fifo_busy_forward    <= '0';
    -- Edge detectors
    tx_en_prev							<= '0';
    tx_reading_prev					<= '0';
    tx_storing_prev				  <= '0';
  else 
    tx_en_prev				<= tx_en;
    tx_storing_prev 	<= tx_fifo_storing;
    tx_reading_prev		<= tx_reading; 
    
    -- When tx_fifo_wr_en = 1, count packets stored in txfifo_pkt_track(txfrd_pkt_idx)
    if tx_fifo_wr_en = '1' then txfifo_pkt_track(txfrd_pkt_idx-1)  <= txfifo_pkt_track(txfrd_pkt_idx-1) + x"4"; end if;
    -- turn off tx_frd storing data 
    if txfrd_pkt_idx = 0 then txfifo_txfrd_tready_en <= '0'; else txfifo_txfrd_tready_en <= '1'; end if; 

    -- TRANSMITTING TO MAC
    if tx_en = '1' and tx_en_prev = '0' then   -- RE
      tx_fifo_busy_forward  <= '1';
    end if;      
    if tx_en = '0' and tx_en_prev = '1' then   -- FE
      tx_pkt_cnt            <= tx_pkt_cnt + 1;  
      tx_pkt_idx         		<= tx_pkt_idx - 1;
      tx_fifo_busy_forward  <= '0';
    end if; 
    -- STORING FROM MAC
    if tx_fifo_storing = '1' and tx_storing_prev = '0'  then   -- RE 
      tx_fifo_busy_store  	<= '1';
    end if; 
    if tx_fifo_storing = '0' and tx_storing_prev = '1'  then   -- FE
      txfrd_pkt_idx         <= txfrd_pkt_idx - 1;  
      tx_fifo_busy_store  	<= '0';        
    end if; 
     -- FIFO Tracker Shift 
    if tx_fifo_busy = '0' and tx_pkt_idx < PKT_FIFO_SIZE then 
      -- update fifo pointers
      tx_pkt_cnt      <= 0;
      tx_pkt_idx     	<= PKT_FIFO_SIZE;
      txfrd_pkt_idx   <= txfrd_pkt_idx + tx_pkt_cnt;
    	
--    	-- this allows us to change the length of the FIFO in the future. May be useless 
--    	for i in PKT_FIFO_SIZE downto 0 loop
--				if tx_pkt_cnt < i then
--					txfifo_pkt_track(i-1) <= txfifo_pkt_track(i-1-tx_pkt_cnt);
--				else
--					if i = PKT_FIFO_SIZE then txfifo_pkt_track(i-1)	<= txfifo_pkt_track(0); else txfifo_pkt_track(i-1) <= (others => '0'); end if;
--				end if;
--			end loop;
--			txfifo_pkt_track(0)   <= (others => '0'); 
    
--    	-- goal of loop is to replicate this code here for PKT_FIFO_SIZE = 4
--      if tx_pkt_cnt < 4 then txfifo_pkt_track(3) <= txfifo_pkt_track(3-tx_pkt_cnt); else txfifo_pkt_track(3) <= txfifo_pkt_track(0); end if;
--      if tx_pkt_cnt < 3 then txfifo_pkt_track(2) <= txfifo_pkt_track(2-tx_pkt_cnt); else txfifo_pkt_track(2) <= (others => '0'); end if;
      if tx_pkt_cnt < 2 then txfifo_pkt_track(1) <= txfifo_pkt_track(1-tx_pkt_cnt); else txfifo_pkt_track(1) <= (others => '0'); end if;
      txfifo_pkt_track(0)   <= (others => '0'); 
      
    end if; 
    
  end if; 
end if; 
end process;

-- Receives data from DMA Engine and Forwards to TRANSMIT_DATA through TX_SIDE_FIFO
-- frd_txd_tready is gated by 'ddr_resp_start' to allow ddr_forwarding to remote client 
-- TRANSMIT_FORWARD is prioritized by watching status of 'axi_str_frd_txd_tvalid'
frd_txd_tready					<= tx_frd_tready and txfifo_txfrd_tready_en and not ddr_resp_start;
axi_str_frd_txd_tready	<= frd_txd_tready;
-- TX_FIFO muxing - mux is controlled by ddr_frd_wren
tx_fifo_wr_en           <= tx_frd_wren xor ddr_frd_wren;  -- only one of these should be active, otherwise disable 
tx_fifo_din             <= ddr_txfifo_din when ddr_frd_wren = '1' else txfrd_txfifo_din;
tx_fifo_storing         <= ddr_frd_wren   when ddr_frd_wren = '1' else tx_frd_storing;
TRANSMIT_FORWARD : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
  if axi_str_frd_txd_aresetn = '0' then
    tx_frd_state			<= (others => '0');
    tx_frd_byte_cnt		<= (others => '0');
    txfrd_txfifo_din  <= (others => '0');
    tx_frd_storing    <= '0';
    tx_frd_tready     <= '0';
    tx_frd_wren       <= '0'; 
  else
    case tx_frd_state is
      when "00" =>
        tx_frd_tready	    <= '1';
        tx_frd_wren       <= '0'; 
        tx_frd_storing    <= '0';
        tx_frd_byte_cnt		<= (others => '0');
        tx_frd_state			<= "01";
            
      when "01" =>
        if axi_str_frd_txd_tvalid = '1' and frd_txd_tready = '1' then 
          tx_frd_byte_cnt	    <= tx_frd_byte_cnt + x"4";  -- count number of received bytes
          if tx_frd_byte_cnt <= MAX_PKTLEN_BYTE - x"4" then
            tx_frd_wren       <= '1';
            tx_frd_storing    <= '1';
            txfrd_txfifo_din  <= axi_str_frd_txd_tdata; 							
          else 
            tx_frd_wren   <= '0';
          end if; 
        else
          tx_frd_wren		  <= '0';
        end if; 
       
        if axi_str_frd_txd_tlast = '1' then
          tx_frd_tready   <= '0';
          tx_frd_state    <= "10";
        end if; 
        
      when "10" =>			-- **** Can we remove this state????
        tx_frd_state		<= "00";
        tx_frd_wren		  <= '0';
        tx_frd_storing  <= '0';
      when others =>
    end case;
  end if;
end if; 
end process; 

-- Transmit Data over AXIS to MAC 
-- TX Data Asynch
axi_str_txd_tvalid	<= tvalid;
axi_str_txd_tlast		<= tlast;
axi_str_txd_tkeep		<= tkeep; 
axi_str_txd_tdata   <= tx_fifo_dout when tvalid = '1' else (others => '0');
tx_fifo_rd_en			  <= tvalid and axi_str_txd_tready;
TRANSMIT_DATA : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
  if axi_str_aresetn = '0' then
    -- internal Reg configuration
    tx_byte_cnt			<= (others => '0');
    tx_byte_limit		<= (others => '0');
    tx_cntrl_en			<= '0'; -- start up the tx_control machine and allow it to finish full transmission
    -- State Machine Setup 
    tx_ready 			  <= '0';
    axis_tx_state	  <= "00";
    -- AXIS line default
    tkeep			      <= (others => '0');
    tvalid		      <= '0';
    tlast			      <= '0';
  else
  
    -- determine number of bytes to send and start state machine 
    if tx_ready = '1' and (tx_pkt_idx > txfrd_pkt_idx) and tx_fifo_busy_forward = '0' then
      tx_byte_limit		<= txfifo_pkt_track(tx_pkt_idx-1);
      tx_en	      		<= '1';
    end if; 
  
    if tx_en = '1' then 
      case axis_tx_state is
      
        -- Setup for Beginning of TX w/ DEST_ADDR
        when "00" =>			
          -- Read out first word before starting state machine 
          tx_byte_cnt			  <= (others => '0');
          tx_cntrl_en			  <= '1'; 
          tx_ready				  <= '0';
          axis_tx_state		  <= axis_tx_state + '1';
          tkeep							<= "1111";
          tvalid						<= '1';
        when "01" =>						

          if axi_str_txd_tready = '1' and tvalid = '1' then -- Hold off on transitioning through Frame until RX is ready
            -- When we finish the frame, reset system by jumping to state "10"
            if tx_byte_cnt = tx_byte_limit - 4 then 				-- Transmit last word
              tlast						<= '0'; 
              tvalid					<= '0';
              axis_tx_state		<= axis_tx_state + '1';
            elsif tx_byte_cnt = tx_byte_limit - 8 then			-- Setup for Last Word  
              tlast						  <= '1'; 
              tx_byte_cnt 		  <= tx_byte_cnt + x"0004";
            elsif tx_byte_cnt = tx_byte_limit - 6 then			-- Setup for Last Word (when tx_wrd_num is even but not divisible by 4)
              tlast						  <= '1'; 
              tx_byte_cnt 		  <= tx_byte_cnt + x"0002";
            else
              tx_byte_cnt 		  <= tx_byte_cnt + x"0004";
            end if; 	
          else 
          end if;
          
        when "10" =>			-- Handle Next Frame Setup/ state machine reset 
          tx_cntrl_en			<= '0'; 
          tx_en           <= '0';
          tx_ready				<= '1';
          axis_tx_state	 	<= "00";
        when others => 
      end case;
      
    else 	-- Default tx_ready to '1' to allow system startup
      tx_ready		<= '1';
    end if;
  end if; 
end if;
end process;

-- Transmit control over AXIS to MAC
-- Control Info used to keep MAC in sync with Frame Data
axi_str_txc_tvalid	<= tcvalid;
axi_str_txc_tlast		<= tclast;
axi_str_txc_tkeep		<= tckeep;
axi_str_txc_tdata		<= tcdata;
TRANSMIT_CONTROL : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_aresetn = '0' then
		-- internal Reg configuration
		tx_cntrl_word_cnt	<= (others => '0');
		tx_cntrl_buf			<= (others => '0');
		-- State Machine Setup 
		tx_cntrl_state	<= "00";
		-- AXIS line default
		tckeep			<= (others => '0');
		tcdata			<= (others => '0');
		tcvalid			<= '0';
		tclast			<= '0';
	else
		if tx_cntrl_en = '1' then 
		
			case tx_cntrl_state is
			
			-- Setup for Beginning of TX w/ DEST_ADDR
			when "00" =>			            
				tx_cntrl_buf				<= cw0; 												-- Reset Control Word
				tx_cntrl_word_cnt		<= (others => '0');							-- Reset Counter
				tx_cntrl_state			<= tx_cntrl_state + '1';				-- Go to next State
				
			-- Start loop, counting bytes until finished		
			when "01" =>
				-- On Second Cycle of State "01", Data is valid for first transfer
				tckeep				<= "1111";
				tcvalid				<= '1';
				-- Grab data from data buffer
				tcdata				<= tx_cntrl_buf;	
				if axi_str_txc_tready = '1' and tcvalid = '1' then	-- Hold off on transitioning through Frame until RX is ready
					tx_cntrl_word_cnt 	<= tx_cntrl_word_cnt + x"1"; 
				
					-- When we finish the frame, reset system by jumping to state "10"
					if tx_cntrl_word_cnt = x"0005" then	-- send tcvalid = '0'; End Transmission
						tclast						<= '0';
						tcvalid						<= '0'; 
						tx_cntrl_state		<= "10";				-- Sit in Limbo until next packet comes
					elsif tx_cntrl_word_cnt = x"0004" then	-- Send Last Word
						tclast						<= '1'; 
					elsif tx_cntrl_word_cnt = x"0000" then	-- Switch over to CW1
						tx_cntrl_buf			<= cw1;
					end if; 
				end if;
				
			when others =>
			end case;
		else
			tx_cntrl_state <= "00";		-- Get ready for next Transmission
		end if;
	end if; 
end if;
end process;

rx_fifo_busy <= rx_fifo_busy_forward or rx_fifo_busy_store;
RX_FIFO_MANAGER : process(axi_str_aclk) begin 
if rising_edge(axi_str_aclk) then 
  if axi_str_aresetn = '0' then 
    rxfifo_pkt_track        <= (others => "00000000");
    rxfifo_pkt_frd          <= (others => "0000000000");
    rxfrd_pkt_idx           <= PKT_FIFO_SIZE;
    rx_pkt_idx              <= PKT_FIFO_SIZE;
    rx_frd_cnt              <= 0;
    rx_fifo_busy_store      <= '0';
    rx_fifo_busy_forward    <= '0';
    rxfifo_rx_tready_en     <= '1';
    rx_frd_en_prev					<= '0';
    ddr_frd_en_prev					<= '0';
    rxd_storing_prev				<= '0';
  else 
    -- edge tracking 
    rxd_storing_prev	<= rxd_storing;
    ddr_frd_en_prev	  <= ddr_frd_en;
    rx_frd_en_prev	  <= rx_frd_en;
    
    -- When rx_fifo_wr_en = 1, count packets stored in rxfifo_pkt_track(rx_pkt_idx)
    if rx_fifo_wr_en = '1' then rxfifo_pkt_track(rx_pkt_idx-1)	<= rxfifo_pkt_track(rx_pkt_idx-1) + x"4"; end if; 
    -- disable rx packet storage
    if rx_pkt_idx = 0 then rxfifo_rx_tready_en <= '0'; else rxfifo_rx_tready_en <= '1'; end if; 

    -- Rising/ Falling Edge checks
    -- FORWARD TO CPU/ DDR
    if(rx_frd_en = '1' and rx_frd_en_prev = '0')  or
      (ddr_frd_en = '1' and ddr_frd_en_prev = '0')  then    -- RE
      rx_fifo_busy_forward 	<= '1';
    end if; 
    if(rx_frd_en = '0' and rx_frd_en_prev = '1')  or 
      (ddr_frd_en = '0' and ddr_frd_en_prev = '1')  then	  -- FE
      rxfrd_pkt_idx         <= rxfrd_pkt_idx - 1;
      rx_frd_cnt	          <= rx_frd_cnt + 1;
      rx_fifo_busy_forward	<= '0';
    end if;
    -- STORE FROM MAC
    if(rxd_storing = '1' and rxd_storing_prev = '0') then   -- RE
      rx_fifo_busy_store    <= '1';
    end if;  
    if(rxd_storing = '0' and rxd_storing_prev = '1') then   -- FE
    	rxfifo_pkt_frd(rx_pkt_idx-1)	<= frd_header(79 downto 64) & frd_header(31 downto 0) & crc_ip_udp_pass;
      rx_pkt_idx            				<= rx_pkt_idx - 1;
      rx_fifo_busy_store    				<= '0';
    end if;        

    -- FIFO Tracker Shift 
    if rx_fifo_busy = '0' and rxfrd_pkt_idx < PKT_FIFO_SIZE then 
      -- update fifo pointers
      rx_frd_cnt        <= 0;
      rxfrd_pkt_idx     <= PKT_FIFO_SIZE;
      rx_pkt_idx        <= rx_pkt_idx + rx_frd_cnt;
      
      -- update rxfifo_pkt_track -> left shift by 'rx_frd_cnt'
      --      if rx_frd_cnt < 4 then rxfifo_pkt_track(3) <= rxfifo_pkt_track(3-rx_frd_cnt); else rxfifo_pkt_track(3) <= rxfifo_pkt_track(0); end if;
      --      if rx_frd_cnt < 3 then rxfifo_pkt_track(2) <= rxfifo_pkt_track(2-rx_frd_cnt); else rxfifo_pkt_track(2) <= (others => '0'); end if;
      if rx_frd_cnt < 2 then rxfifo_pkt_track(1) <= rxfifo_pkt_track(1-rx_frd_cnt); else rxfifo_pkt_track(1) <= (others => '0'); end if;
      rxfifo_pkt_track(0)   <= (others => '0');
    
      -- update rxfifo_pkt_frd -> left shift by 'rx_frd_cnt'
      --      if rx_frd_cnt < 4 then rxfifo_pkt_frd(3) <= rxfifo_pkt_frd(3-rx_frd_cnt); else rxfifo_pkt_frd(3) <= rxfifo_pkt_frd(0); end if;
      --      if rx_frd_cnt < 3 then rxfifo_pkt_frd(2) <= rxfifo_pkt_frd(2-rx_frd_cnt); else rxfifo_pkt_frd(2) <= (others => '0'); end if;
      if rx_frd_cnt < 2 then rxfifo_pkt_frd(1) <= rxfifo_pkt_frd(1-rx_frd_cnt); else rxfifo_pkt_frd(1) <= (others => '0'); end if;
      rxfifo_pkt_frd(0)   <= (others => '0');
    end if;
    
  end if; 
end if; 
end process;

-- Need to receive status-data in order for receive-data to be passed to our SM
-- Must Capture all 6 words before Data comes through on 'axis_rxd_'
-- rx_cntrl_word is accurate after RX_CNTRL finishes, but before a new transmission starts 
crc_ip_udp_pass <= '1' when rx_cntrl_word(3)(5 downto 3) = "011" else '0';
RECEIVE_CONTROL : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_aresetn = '0' then
		rx_cntrl_word				<= (others => "00000000");
		rx_cntrl_word_cnt		<= (others => '0');
		rx_cntrl_data				<= (others => '0');
		rx_cntrl_state			<= (others => '0');
	else

		case rx_cntrl_state is
			when "00" =>
				-- Setup 
				axi_str_rxs_tready	<= '1';
				rx_cntrl_word_cnt		<= (others => '0');
				rx_cntrl_state			<= "01";
						
			when "01" =>
				if axi_str_rxs_tvalid = '1' then 
					if axi_str_rxs_tlast = '1' then
						-- Handle end of transmission
						axi_str_rxs_tready	<= '0';
						rx_cntrl_state		  <= "00";
					end if; 
					
					-- Store word into array, make sure we dont run out of bounds
					if rx_cntrl_word_cnt < "0110" then
						rx_cntrl_word(to_integer(unsigned(rx_cntrl_word_cnt))) <= axi_str_rxs_tdata; 
					end if; 
					
					rx_cntrl_word_cnt <= rx_cntrl_word_cnt + '1';		-- count number of received words
					rx_cntrl_data			<= axi_str_rxs_tdata; 	-- Capture data, incase its outside of array bounds
				end if; 
			when others =>
		end case;
			
	end if;
end if; 
end process; 

-- reorder the data before pushing it into the rxfifo_pkt_frd() FIFO
-- only forwarding info gets re-ordered, as forwarded FIFO data naturally gets re-ordered on DDR writes
axi_rxd_reorder			<= axi_str_rxd_tdata(7 downto 0) 		& axi_str_rxd_tdata(15 downto 8)	&
											 axi_str_rxd_tdata(23 downto 16)	&	axi_str_rxd_tdata(31 downto 24);
-- pkt indexing 
rx_bit_cnt_idx 			<= to_integer(unsigned(rx_bit_cnt));
-- RXD AXIS connections
rxd_tready					<= axis_rx_tready and rxfifo_rx_tready_en;
axi_str_rxd_tready	<= rxd_tready;
RECEIVE_DATA : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_aresetn = '0' then
		-- Reset buffers 
		frd_header			<= (others => '0');
		-- State Tracking
		rx_data_state   <= (others => '0');
		rx_byte_cnt			<= (others => '0');
		rx_bit_cnt			<= (others => '0');
		-- AXIS line defaults
		axis_rx_tready  <= '0';
		-- RX Fifo
		rx_fifo_wr_en		<= '0';
    rxd_storing			<= '0';
	else

		case rx_data_state is
			when "00" =>
				frd_header			<= (others => '0');
				rx_byte_cnt			<= (others => '0');
				rx_bit_cnt			<= (others => '0');
				axis_rx_tready	<= '1';
				rx_data_state		<= "01";
						
			when "01" =>
				
				-- Collect data off stream line
				-- Assuming All Data on Bus is Valid tvalid = "1111"
				if axi_str_rxd_tvalid = '1' and rxd_tready = '1' then
					rx_byte_cnt  <= rx_byte_cnt + x"4";
					rx_bit_cnt   <= rx_bit_cnt + x"20";

					-- stop writing to fifo if we reach our predetermined maximum length
					if rx_byte_cnt <= MAX_PKTLEN_BYTE - x"4" then
          	rxd_storing		<= '1';										-- let FIFO manager know we're still receiving/ writing data
						rx_fifo_wr_en <= '1';
						rx_fifo_din   <= axi_str_rxd_tdata;
					else
						rx_fifo_wr_en <= '0';
					end if;

					-- Pack data into tcp/ udp header
					if rx_byte_cnt < FRD_HDR_LEN-2 then	-- rx_byte_cnt < 44 (up to 40), capture full word
						frd_header(31 downto 0)							<= axi_rxd_reorder;
						frd_header(FRD_HDR_BIT-1 downto 32) <= frd_header(FRD_HDR_BIT-1-32 downto 0);
					elsif rx_byte_cnt = FRD_HDR_LEN-2 then -- rx_byte_cnt = 40, capture last two 
						frd_header(15 downto 0)							<= axi_rxd_reorder(31 downto 16);
						frd_header(FRD_HDR_BIT-1 downto 16) <= frd_header(FRD_HDR_BIT-1-16 downto 0);
					end if; 

				else 
					rx_fifo_wr_en	<= '0';
				end if; 
				
				-- Watch for tlast
				if axi_str_rxd_tlast = '1' then
					axis_rx_tready	<= '0';										-- Drop tready line, handshake
					rx_data_state		<= "10";
				end if; 
			
			when "10" =>
				rx_data_state		<= "00";								-- delay one cycle before resetting
				rx_fifo_wr_en		<= '0';
				rxd_storing			<= '0';
			when others =>
		end case;
	end if; 
end if;
end process;

-- Takes data from Receive side of this block; Forwards it (transmits) to the DMA-S2MM
rx_frd_start <= '1' when rx_frd_ready = '1' 
										and rx_fifo_busy_forward = '0'
										and (rxfrd_pkt_idx > rx_pkt_idx) 
										and rxfifo_pkt_frd(rxfrd_pkt_idx-1)(48 downto 33) /= DDR_FRD_PORT
										else '0';
										
rx_frd_rd_en						<= '1' when rx_frd_tvalid = '1' and axi_str_frd_rxd_tready = '1' else '0';
rx_fifo_rd_en						<= rx_frd_rd_en or ddr_frd_rd_en or ddr_empty_rd_en;		-- only one process will access FIFO at a time
axi_str_frd_rxd_tvalid	<= rx_frd_tvalid;
axi_str_frd_rxd_tdata   <= rx_fifo_dout when rx_frd_tvalid = '1' else (others => '0');
RECEIVE_FORWARD : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_frd_rxd_aresetn = '0' then
		-- State Tracking
		rx_frd_state				  <= (others => '0');
		rx_frd_byte_limit			<= (others => '0');
		rx_frd_byte_cnt		    <= (others => '0');
		rx_frd_en					    <= '0';
		rx_frd_ready			    <= '0';
		-- AXIS line defaults
		axi_str_frd_rxd_tkeep	<= (others => '0');
		rx_frd_tvalid					<= '0';
		axi_str_frd_rxd_tlast	<= '0';
		
	else
	
		if rx_frd_start = '1' then
			rx_frd_byte_limit	<= rxfifo_pkt_track(rxfrd_pkt_idx-1);
			rx_frd_en					<= '1';
		end if; 
		
		if rx_frd_en = '1' then
		
			case rx_frd_state is
			-- Setup Forwarding
			when "00" =>			
				rx_frd_ready 						<= '0';
				rx_frd_byte_cnt					<= (others => '0');          
				axi_str_frd_rxd_tkeep		<= "1111";  
				rx_frd_tvalid		        <= '1';             
				rx_frd_state						<= rx_frd_state + '1';
				
			when "01" =>						
				
				if rx_frd_tvalid = '1' and axi_str_frd_rxd_tready = '1' then
					
					if rx_frd_byte_cnt	= rx_frd_byte_limit - 4 then        -- transfer last word
						rx_frd_tvalid						<= '0';
						axi_str_frd_rxd_tlast		<= '0';
						axi_str_frd_rxd_tkeep		<= "0000";                
						rx_frd_state						<= rx_frd_state + '1';
					elsif rx_frd_byte_cnt = rx_frd_byte_limit - 8 then
						axi_str_frd_rxd_tlast 	<= '1'; 
						rx_frd_byte_cnt					<= rx_frd_byte_cnt + x"4";
					elsif rx_frd_byte_cnt = rx_frd_byte_limit - 6 then			-- For word_count thats not an even multiple of 4
						axi_str_frd_rxd_tkeep		<= "1100";
						axi_str_frd_rxd_tlast		<= '1';
						rx_frd_byte_cnt 				<= rx_frd_byte_cnt + x"2";
					else
						rx_frd_byte_cnt         <= rx_frd_byte_cnt + x"4"; 
					end if; 
				else 
				end if; 
	
			when "10" =>			-- Handle Next Frame Setup
				rx_frd_ready	  <= '1';
				rx_frd_en			  <= '0';
				rx_frd_state		<= "00";
			when others =>
			end case;
			
		else -- Default rx_frd_ready to '1' to allow system to startup properly
			rx_frd_ready		<= '1';
		end if; 
		
	end if; 
end if; 
end process; 

-- This process will handle pulling data into the Master Write block
ddr_frd_start  <= '1' when rx_fifo_busy_forward = '0'                                   -- FIFO not being read from by RECEIVE_FORWARD
											and (rxfrd_pkt_idx > rx_pkt_idx)                             			-- RECEIVE_DATA working/ waiting on next entry 
											and rxfifo_pkt_frd(rxfrd_pkt_idx-1)(48 downto 33) = DDR_FRD_PORT  -- PORT # = 50,000
											else '0';
										
DDR_FORWARD : process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_aresetn = '0' then
	 -- start indexing into top of FIFO
    sample_out        <= (others => '0');
    addr_to_write     <= (others => '0');			-- starting address for the current transfer 
    load_word_cnt     <= (others => '0');
    ddr_empty_rd_en   <= '0';									-- Used to remove header data from the FIFO we want to dump into DDR4
    ddr_empty_start	  <= '0';
    ddr_frd_state     <= "000";
    ddr_frd_en        <= '0';
    ddr_resp_start    <= '0';
    ddr_frd_count	    <= (others => '0');
    ddr_txfifo_din    <= (others => '0');
    resp_ip_crc       <= (others => '0');
    resp_udp_crc      <= (others => '0');
    ms_en             <= '0';
	else 
    case ddr_frd_state is
    
    -- (0) store packet length locally and setup load_word_cnt to enable DDR state machine 
    when "000" =>    
      if load_word_cnt = x"0000" then 
        ddr_frd_en          <= '0';             -- Tell FIFO_MANAGER we are done transferring ddr data 
        if ddr_frd_start = '1' and ddr_empty_start = '0' then
          addr_to_write     <= rxfifo_pkt_frd(rxfrd_pkt_idx-1)(32 downto 1);
          ddr_empty_start   <= '1';
          ddr_frd_state     <= "001";
          ddr_frd_count		  <= x"C";	-- 12 words
          ddr_empty_rd_en   <= '1';
        end if;
      end if; 
		
	-- (1) Remove the header + addr/fluff from packet (48 bytes) [MAC][IP][UDP][DDR_ADDR][FLUFF]
    --     Put them into a response packet by flipping the source and destination IP, MAC, Port  
    --     Finally, Append the UDP-Receive CRC status bit and calculate the new outgoing IP/ UDP Checksums
    when "001" =>
      if ddr_frd_count > x"0" then
        ddr_frd_count <= ddr_frd_count - '1';
        
        -- place into our return-pkt + re-order data from little-endian to big-endian
        resp_pkt(31 downto 0)   <= rx_fifo_dout(7 downto 0) & rx_fifo_dout(15 downto 8) & 
        						rx_fifo_dout(23 downto 16) & rx_fifo_dout(31 downto 24);   
        resp_pkt(383 downto 32) <= resp_pkt(351 downto 0);  -- shift pkt
        
        if ddr_frd_count = x"1" then
          ddr_empty_rd_en	<= '0';   -- terminate fifo read one cycle early
        end if;
        
      else
        ddr_empty_start <= '0';
        ddr_frd_state   <= "010";
        
        -- update CRC check status 
        if rxfifo_pkt_frd(rxfrd_pkt_idx-1)(0) = '1' then 
          resp_pkt(47 downto 0) <= resp_pass; 
        else 
          resp_pkt(47 downto 0) <= resp_fail; 
        end if; 
        -- swap MAC addresses 
        resp_pkt(48*8-1 downto 42*8)  <= resp_pkt(42*8-1 downto 36*8);
        resp_pkt(42*8-1 downto 36*8)  <= resp_pkt(48*8-1 downto 42*8);
        -- swap IP addresses 
        resp_pkt(22*8-1 downto 18*8)  <= resp_pkt(18*8-1 downto 14*8);
        resp_pkt(18*8-1 downto 14*8)  <= resp_pkt(22*8-1 downto 18*8);
        -- swap UDP Ports  
        resp_pkt(14*8-1 downto 12*8)  <= resp_pkt(12*8-1 downto 10*8);
        resp_pkt(12*8-1 downto 10*8)  <= resp_pkt(14*8-1 downto 12*8);     
        -- Update IP Total length (20 + 8 + 6) = 34 (0x22)
        resp_pkt(32*8-1 downto 30*8)  <= x"0022";
        -- Update UDP Total Length (8 + 6) = 14 (0xE)
        resp_pkt(10*8-1 downto 8*8)   <= x"000E";
      end if; 
        -- (2) calculate CRC for IP/ UDP headers
	when "010" =>
        ddr_frd_state <= "011";
        resp_ip_crc	<= x"00000" + resp_pkt(34*8-1 downto 32*8) + resp_pkt(32*8-1 downto 30*8) + 
                                  resp_pkt(30*8-1 downto 28*8) + resp_pkt(28*8-1 downto 26*8) + 
                                  resp_pkt(26*8-1 downto 24*8) + resp_pkt(22*8-1 downto 20*8) + 
                                  resp_pkt(20*8-1 downto 18*8) + resp_pkt(18*8-1 downto 16*8) +
                                  resp_pkt(16*8-1 downto 14*8);	-- entire IP header w/ checksum set to "0"

        resp_udp_crc <= x"00000" + resp_pkt(22*8-1 downto 20*8)+ -- IP source (upper)
                                   resp_pkt(20*8-1 downto 18*8)+ -- IP source (lower)
                                   resp_pkt(18*8-1 downto 16*8)+ -- IP dest (upper)	
                                   resp_pkt(16*8-1 downto 14*8)+ -- IP dest (lower)	
                                   resp_pkt(25*8-1 downto 24*8)+ -- Zeros & IP Protocol (17)	
                                   resp_pkt(10*8-1 downto  8*8)+ -- UDP Length field 
                                   resp_pkt(14*8-1 downto 12*8)+ -- Source Port 
                                   resp_pkt(12*8-1 downto 10*8)+ -- Destination Port 
                                   resp_pkt(10*8-1 downto  8*8)+ -- UDP Length field 
                                   resp_pkt( 6*8-1 downto  4*8)+ -- Data 1 (skip checksum field )
                                   resp_pkt( 4*8-1 downto  2*8)+ -- Data 2 
                                   resp_pkt( 2*8-1 downto  0*8); -- Data 3              

    -- (3) add-in the overflow bits                 
    when "011" =>
      ddr_frd_state <= "100";
      resp_ip_crc(15 downto 0)  <= std_logic_vector(unsigned(resp_ip_crc(15 downto 0)) + unsigned(resp_ip_crc(19 downto 16)));
      resp_udp_crc(15 downto 0) <= std_logic_vector(unsigned(resp_udp_crc(15 downto 0)) + unsigned(resp_udp_crc(19 downto 16)));
    -- (4) invert the result
    when "100" =>
      ddr_frd_state <= "101";
      resp_ip_crc   <= not resp_ip_crc;
      resp_udp_crc  <= not resp_udp_crc;
    -- (5) place into header 
    when "101" =>    
      ddr_frd_state <= "110";
      resp_pkt(24*8-1 downto 22*8)  <= resp_ip_crc(15 downto 0);
      resp_pkt(8*8-1 downto 6*8)    <= resp_udp_crc(15 downto 0);
    -- (6) forward response packet into TX Queue
    -- allow TX_FRD to finish up if busy, then disable further FIFO access until we are finished
    when "110" =>
      if axi_str_frd_txd_tvalid = '0' then
        ddr_resp_start  <= '1';     -- disable TX_FRD  
        ddr_frd_count   <= x"C";	-- reset count for ddr response
      end if; 
      if ddr_resp_start = '1' then
        if ddr_frd_count > x"0" then
          ddr_frd_wren	    <= '1';                   -- start writing to FIFO 
          ddr_frd_count     <= ddr_frd_count - '1';
          -- re-order data from Big endian to little endian (383->31 : 352->0)
          ddr_txfifo_din  <= resp_pkt(359 downto 352) & resp_pkt(367 downto 360) &
          					         resp_pkt(375 downto 368) & resp_pkt(383 downto 376);
          resp_pkt(383 downto 32) <= resp_pkt(351 downto 0);      -- shift data out, top first
        else
          -- stop pushing into FIFO, tx_storing will follow ddr_frd_wren 
          ddr_frd_wren	  <= '0';
          ddr_resp_start  <= '0';
          ddr_frd_state   <= "111";
          load_word_cnt		<= rxfifo_pkt_track(rxfrd_pkt_idx-1) - x"30";   -- start ddr transmission 
         end if;
      end if; 
 
		-- (7) start transmission to DDR 
	when "111" =>
        if load_word_cnt > x"0000" then
            ddr_frd_en  <= '1';                 -- Tell FIFO_MANAGER we are starting transfer of DDR data (lock out RECEIVE_FORWARD)
            if ms_ready = '0' then
                ms_en   <= '0';
                if load_word_cnt = x"2" then load_word_cnt <= load_word_cnt - x"2"; else load_word_cnt <= load_word_cnt - x"4"; end if; 
            end if;
            if ms_ready = '1' and ms_en = '0' then
                sample_out    <= rx_fifo_dout; 
                ddr_frd_rd_en <= '1';
                ms_en         <= '1';
            end if;
            if ddr_frd_rd_en = '1' then ddr_frd_rd_en <= '0'; end if; 
        else
            ddr_frd_en		  <= '0';
            ddr_frd_state	  <= "000";
            load_word_cnt   <= (others => '0');
        end if;
	when others =>
    end case;
    
	end if; 
end if; 
end process; 

-- Master Asynch ---------------------
M_AXI_ACLK_d		<= axi_str_aclk;
M_AXI_ARESETN_d	<= axi_str_aresetn;
-- Connect port to drivers
M_AXI_AWADDR_d 		<= m_axi_awaddr;
M_AXI_AWVALID_d 	<= m_axi_awvalid; 
M_AXI_WDATA_d 		<= m_axi_wdata;
M_AXI_WVALID_d 		<= m_axi_wvalid;
M_AXI_BREADY_d 		<= m_axi_bready;
M_AXI_WSTRB_d 		<= m_axi_wstrb;
-- DEBUG Slave watch
m_axi_awready			<= M_AXI_AWREADY_d;
m_axi_wready			<= M_AXI_WREADY_d;
m_axi_bresp				<= M_AXI_BRESP_d;
m_axi_bvalid			<= M_AXI_BVALID_d;
master_write: process(axi_str_aclk) begin
if rising_edge(axi_str_aclk) then
	if axi_str_aresetn = '0' then
		-- default config for output master write ports
		m_axi_wstrb		<= (others => '0');
		m_axi_awaddr	<= (others => '0');
		m_axi_awvalid	<= '0';					-- must be low during reset per spec
		m_axi_wdata		<= (others => '0');
		m_axi_wvalid	<= '0';					-- must be low during reset per spec
		m_axi_bready	<= '0';
		-- AXI State
		m_axi_state 	<= b"00";
		ms_ready			<= '1'; 
		-- DDR4 Addr
		m_addr_count	<= (others => '0');		

	else
	
    if load_word_cnt = x"0000" then m_addr_count <= (others => '0'); end if;	-- Reset our starting address
    
    if ms_en = '1' then
    
        case m_axi_state is
        when b"00" =>
            if m_axi_awvalid = '0' and m_axi_wvalid = '0' then
              -- index into sample -- most significant Byte first
              m_axi_wdata		<= sample_out;
              m_axi_wstrb		<= b"1111";
              m_axi_awaddr	<= std_logic_vector(unsigned(m_addr_count) + unsigned(addr_to_write));
              m_axi_wvalid	<= '1';
              m_axi_awvalid <= '1';
              m_axi_bready	<= '1';
              -- transition to next state
              m_axi_state <= b"01";
            end if;

        when b"01" =>
            if m_axi_awvalid = '1' and M_AXI_AWREADY = '1' then		-- handshake on write-address
              m_axi_awvalid		<= '0';
            end if;

            if m_axi_wvalid = '1' and M_AXI_WREADY = '1' then 		-- handshake on write-data
              m_axi_wvalid 		<= '0';
            end if;
            
            if m_axi_bready = '1' and M_AXI_BVALID = '1' then
              if M_AXI_BRESP /= "00" then
                -- what to do here?
              else
                m_axi_bready	<= '0';
              end if;
            end if;
            
            if m_axi_awvalid = '0' and m_axi_wvalid = '0' and m_axi_bready = '0' then		
              m_axi_state	<= b"10";
            end if; 
            
        when b"10" =>
          ms_ready			<= '0'; 
          m_axi_state		<= b"11";
          m_addr_count	<= m_addr_count + 4; 
        when b"11" =>
          ms_ready			<= '1';								  -- Reset ms_ready
          m_axi_state 	<= b"00";
        when others =>
    end case;
    else 
        ms_ready <= '1'; 			                  -- Default ms_ready = '1' 
    end if;
	end if;
end if;
end process; 
------------------------------
end Behavioral;