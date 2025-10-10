-- Simple AXI interface allowing two way communication between Register file and CPU

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity axi_interface is

port(
  -- Global AXI connections
  S_AXI_ACLK      : in  std_logic;   -- Clock Signal
  S_AXI_ARESETN   : in  std_logic;   -- Reset Signal - Active LOW

  -- Write Side --
  -- M --> S
  S_AXI_AWADDR    : in  std_logic_vector(31 downto 0); 	-- Write address (Master --> Slave)
  S_AXI_AWVALID   : in  std_logic;                      -- Write address valid
  S_AXI_WDATA     : in  std_logic_vector(31 downto 0); 	-- Write data (Master --> Slave)
  S_AXI_WVALID    : in  std_logic;                      -- Write valid
  S_AXI_BREADY    : in  std_logic;
  S_AXI_WSTRB     : in  std_logic_vector( 3 downto 0); 	-- Write strobes
  -- S --> M
  S_AXI_AWREADY   : out std_logic;                     	-- Write address ready
  S_AXI_WREADY    : out std_logic;                     	-- Write ready
  S_AXI_BRESP     : out std_logic_vector(1 downto 0);  	-- Write response
  S_AXI_BVALID    : out std_logic;                     	-- Write response valid
  -- Not necessary for basic AXI transaction
  S_AXI_AWPROT    : in  std_logic_vector(2 downto 0);		-- Write channel Protection type
  --- Read Side ---
  -- M --> S
  S_AXI_ARADDR    : in  std_logic_vector(31 downto 0);  -- Read address  (Master --> Slave)
  S_AXI_ARVALID   : in  std_logic;                      -- Read address valid
  S_AXI_RREADY    : in  std_logic;                      -- Read ready
  -- S --> M 
  S_AXI_ARREADY   : out std_logic;                      -- Read address ready
  S_AXI_RDATA     : out std_logic_vector(31 downto 0);  -- Read data (issued by slave)
  S_AXI_RRESP     : out std_logic_vector(1 downto 0);   -- Read response
  S_AXI_RVALID    : out std_logic;                      -- Read valid
  -- Not necessary for basic AXI transaction
  S_AXI_ARPROT    : in  std_logic_vector(2 downto 0)
  );
end axi_interface;

architecture arch_imp of axi_interface is

signal clk : std_logic;
signal rst : std_logic;

-- AXI4LITE signals for Slave device
---- Write side - slave controlled
signal axi_awready     : std_logic;
signal axi_wready      : std_logic;
signal axi_bresp       : std_logic_vector(1 downto 0);
signal axi_bvalid      : std_logic; 
-- Write side - slave watch 
signal axi_awaddr      : std_logic_vector(31 downto 0);
signal axi_wdata       : std_logic_vector(31 downto 0); 
signal axi_bready      : std_logic; 
signal axi_wstrb       : std_logic_vector( 3 downto 0);
signal axi_wvalid      : std_logic;
signal axi_awvalid     : std_logic;

---- Read side - slave controlled 
signal axi_arready     : std_logic;
signal axi_rdata       : std_logic_vector(31 downto 0);
signal axi_rresp       : std_logic_vector(1 downto 0);
signal axi_rvalid      : std_logic;
-- Read side - slave watch
signal axi_araddr      : std_logic_vector(31 downto 0);
signal axi_rready      : std_logic;
signal axi_arvalid     : std_logic; 

---- Internal 
signal write_handshake : std_logic_vector(1 downto 0);
signal read_handshake  : std_logic_vector(1 downto 0);
signal read_data       : std_logic_vector(31 downto 0); 
signal axi_r_state     : std_logic_vector(1 downto 0);
signal axi_wr_ack      : std_logic;
signal int_read_addr   : integer;
signal int_write_addr  : integer;

---- Slave Register Array 
-- half are outputs (written to), half are inputs (read from)
type   slv_reg is array (0 to 7) of std_logic_vector(31 downto 0);
signal slv_reg_write      : slv_reg; 
signal slv_reg_read				: slv_reg;

begin   -- Asynchronous connections

clk <= s_axi_aclk;
rst <= not s_axi_aresetn;
axi_wstrb <= S_AXI_WSTRB;

-- debugging...
-- Write side 
axi_wvalid  <= S_AXI_WVALID; 
axi_awvalid <= S_AXI_AWVALID;
axi_awaddr  <= S_AXI_AWADDR;
axi_wdata   <= S_AXI_WDATA;
axi_bready  <= S_AXI_BREADY; 

-- Read Side 
axi_rready  <= S_AXI_RREADY; 
axi_arvalid <= S_AXI_ARVALID; 
axi_araddr  <= s_axi_araddr;
---
-- Slave response
-- Write
S_AXI_AWREADY <= axi_awready;
S_AXI_WREADY  <= axi_wready;
S_AXI_BRESP   <= axi_bresp;
S_AXI_BVALID  <= axi_bvalid;

-- Read
S_AXI_ARREADY <= axi_arready;
S_AXI_RDATA   <= axi_rdata;
S_AXI_RRESP   <= axi_rresp;
S_AXI_RVALID  <= axi_rvalid;

-- track addresses in real time
-- shift address left by two - divide by four to get index
-- address = 4 		-> index = 1
-- address = 128 	-> index = 32
int_read_addr  <= to_integer(unsigned(axi_araddr(7 downto 2))); -- Valid data is on internal axi_araddr REG
int_write_addr <= to_integer(unsigned(axi_awaddr(7 downto 2))); -- Valid data is on external axi_awaddr line

axi_bvalid <= '1';
axi_bresp  <= "00";
axi_wready  <= axi_wr_ack;
axi_awready <= axi_wr_ack;

wr_from_axi : process(clk) begin
  if rising_edge(clk) then
    if(rst = '1') then
      slv_reg_write   <= (others => x"00000000"); -- all registers default to 0
      axi_wr_ack 			<= '0'; 			-- not ready to receive write-data
    else

      -- initiate handshaking on ADDRESS, Make Sure Address AND Data are ready to allow seamless transaction 
      if(axi_awready = '0' and axi_awvalid = '1'  and axi_wvalid = '1') then
        axi_wr_ack    								<= '1';
        slv_reg_write(int_write_addr)	<= S_AXI_WDATA;
      else
        axi_wr_ack  									<= '0';
      end if;

    end if;
  end if;
end process;

axi_rresp <= (others => '0');
read_proc : process(clk) begin
  if rising_edge(clk) then
    if rst = '1' then
      axi_arready <= '1';             -- ready to receive read address
      axi_rvalid  <= '0';             -- read-data output not valid
      axi_rdata   <= (others => '0'); -- read-data defualt to 0-string 
      axi_r_state <= "00";
    else
    
      case axi_r_state is
      
        when "00" =>
                
          if(axi_arvalid = '1') then
            axi_arready <= '0'; 												-- don't take another read address while we wait for data handshake
            axi_rvalid  <= '1'; 												-- next clock cycle will have valid data on the bus
            axi_rdata   <= slv_reg_read(int_read_addr); -- mux in correct register's data
            axi_r_state <= "01";
          end if;
          
        when "01" =>
          
          if axi_rready = '1' then
            axi_rvalid  <= '0';  		-- Complete Data Handshake
            axi_arready <= '1';  		-- signal that we're ready for next read address
            axi_r_state <= "00"; 		-- Reset Read - Slave
          end if; 
          
        when others =>
      end case;
    end if;
  end if;
  
end process;

end arch_imp; 
