-- Simple AXI interface allowing two way communication between Register file and CPU

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity bpsk_gen_axi_interface is
generic(
  NUM_SLV_REGS    : integer := 11
);
port(
	reg_rf_ctrl      : out std_logic_vector(15 downto 0); 
	reg_rf_skipcnt   : out std_logic_vector(15 downto 0);
	reg_rf_lusi_en   : out std_logic;
	reg_rf_prn_sel   : out std_logic_vector( 5 downto 0);
	reg_boc_prn_en   : out std_logic;
	reg_rf_freq_div  : out std_logic_vector(15 downto 0);
	reg_boc_freq_div : out std_logic_vector(15 downto 0);
	reg_rf_boc_en    : out std_logic;
	reg_boc_phase    : out std_logic;
	reg_data_en      : out std_logic;
	reg_pwr_div      : out std_logic_vector( 3 downto 0);
  reg_rf_baddr0    : out std_logic_vector(15 downto 0);
  reg_rf_baddr1    : out std_logic_vector(15 downto 0);
  reg_rf_baddr2    : out std_logic_vector(15 downto 0);
  reg_rf_baddr3    : out std_logic_vector(15 downto 0);
  reg_rf_baddr4    : out std_logic_vector(15 downto 0);
  reg_rf_baddr5    : out std_logic_vector(15 downto 0);
  reg_rf_baddr6    : out std_logic_vector(15 downto 0);
  reg_rf_baddr7    : out std_logic_vector(15 downto 0);
  reg_rf_baddr8    : out std_logic_vector(15 downto 0); 
  reg_rf_baddr9    : out std_logic_vector(15 downto 0);
  reg_rf_baddr10   : out std_logic_vector(15 downto 0);
  reg_rf_baddr11   : out std_logic_vector(15 downto 0);
  reg_rf_baddr12   : out std_logic_vector(15 downto 0);
  reg_rf_baddr13   : out std_logic_vector(15 downto 0);
  reg_rf_baddr14   : out std_logic_vector(15 downto 0);
  reg_rf_baddr15   : out std_logic_vector(15 downto 0);

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
end bpsk_gen_axi_interface;

architecture Behavioral of bpsk_gen_axi_interface is

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
signal reg_mval        : std_logic_vector(31 downto 0);
signal write_handshake : std_logic_vector(1 downto 0);
signal read_handshake  : std_logic_vector(1 downto 0);
signal read_data       : std_logic_vector(31 downto 0); 
signal axi_r_state     : std_logic_vector(1 downto 0);
signal axi_wr_ack      : std_logic;
signal busy            : std_logic;
signal int_read_addr   : integer;
signal int_write_addr  : integer;
signal int_iq_addr_idx : integer;
signal ctr_iq          : integer;
signal lusi_base_addrs_accum_i : std_logic_vector(15 downto 0);
signal lusi_base_addrs_accum_q : std_logic_vector(15 downto 0);

-- LUT base address arrays for I/ Q data
type lusi_base_addrs_type is array(7 downto 0) of std_logic_vector(15 downto 0);
signal lusi_base_addrs_i : lusi_base_addrs_type;
signal lusi_base_addrs_q : lusi_base_addrs_type;

-- AXI slave register array 
type   slv_reg is array (0 to NUM_SLV_REGS-1) of std_logic_vector(31 downto 0);
signal slv_regs       : slv_reg; 

-- state machine for
--  skip_cnt + base address calculations
type eo_state_type is(
  eo_idle,
  eo_calc_skipcnt,
  eo_calc_iq_addrs
);
signal eo_state : eo_state_type;

begin   -- Asynchronous connections

-- CLK/ RESET connections
clk <= s_axi_aclk;
rst <= not s_axi_aresetn;

-- AXI connections
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

-- internal register connection
reg_rf_ctrl      <= slv_regs( 0)(15 downto 0);
reg_mval         <= slv_regs( 1); -- internal use but can be read back
reg_rf_lusi_en   <= slv_regs( 2)(0);
reg_rf_prn_sel   <= slv_regs( 3)(5 downto 0);
reg_boc_prn_en   <= slv_regs( 4)(0); 
reg_rf_freq_div  <= slv_regs( 5)(15 downto 0);
reg_boc_freq_div <= slv_regs( 6)(15 downto 0); 
reg_rf_boc_en    <= slv_regs( 7)(0);
reg_boc_phase    <= slv_regs( 8)(0);
reg_data_en      <= slv_regs( 9)(0); 
reg_pwr_div      <= slv_regs(10)(3 downto 0);
----
reg_rf_baddr0    <= lusi_base_addrs_i(0); -- i0
reg_rf_baddr1    <= lusi_base_addrs_i(1); -- i1
reg_rf_baddr2    <= lusi_base_addrs_i(2); -- i2
reg_rf_baddr3    <= lusi_base_addrs_i(3); -- i3
reg_rf_baddr4    <= lusi_base_addrs_i(4); -- i4
reg_rf_baddr5    <= lusi_base_addrs_i(5); -- i5
reg_rf_baddr6    <= lusi_base_addrs_i(6); -- i6
reg_rf_baddr7    <= lusi_base_addrs_i(7); -- i7
reg_rf_baddr8    <= lusi_base_addrs_q(0); -- q0
reg_rf_baddr9    <= lusi_base_addrs_q(1); -- q1
reg_rf_baddr10   <= lusi_base_addrs_q(2); -- q2
reg_rf_baddr11   <= lusi_base_addrs_q(3); -- q3
reg_rf_baddr12   <= lusi_base_addrs_q(4); -- q4
reg_rf_baddr13   <= lusi_base_addrs_q(5); -- q5
reg_rf_baddr14   <= lusi_base_addrs_q(6); -- q6
reg_rf_baddr15   <= lusi_base_addrs_q(7); -- q7

-- AXI processes for Write + Read from register file
-- track addresses in real time
-- shift address left by two - divide by four to get index
int_read_addr  <= to_integer(unsigned(axi_araddr(7 downto 2))); -- Valid data is on internal axi_araddr REG
int_write_addr <= to_integer(unsigned(axi_awaddr(7 downto 2))); -- Valid data is on external AXI_AWADDR line

-- AXI Write Process
axi_bvalid <= '1';
axi_bresp  <= "00";
axi_wready  <= axi_wr_ack;
axi_awready <= axi_wr_ack;
wr_from_axi : process(clk) begin
  if rising_edge(clk) then
    if(rst = '1') then
      slv_regs   <= (others => x"00000000"); -- all registers default to 0
      axi_wr_ack <= '0'; -- not ready to receive write-data
    else
      -- initiate handshaking on ADDRESS, Make Sure Address AND Data are ready to allow seamless transaction 
      if(axi_awready = '0' and axi_awvalid = '1'  and axi_wvalid = '1' and busy = '0') then
        axi_wr_ack    						<= '1';
        slv_regs(int_write_addr)	<= S_AXI_WDATA;
      else
        axi_wr_ack <= '0';
      end if;

    end if;
  end if;
end process;

-- AXI read process
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
            axi_arready <= '0'; -- don't take another read address while we wait for data handshake
            axi_rvalid  <= '1'; -- next clock cycle will have valid data on the bus
            axi_rdata   <= slv_regs(int_read_addr); -- mux in correct register's data
            axi_r_state <= "01";
          end if;
          
        when "01" =>
          if axi_rready = '1' then
            axi_rvalid  <= '0';  -- Complete Data Handshake
            axi_arready <= '1';  -- signal that we're ready for next read address
            axi_r_state <= "00"; -- Reset Read - Slave
          end if; 
          
        when others =>
      end case; 
  
    end if;
  end if;
end process;

-- calculate the LUT base addresses
extra_ops : process(clk) begin
  if(rising_edge(clk)) then
    if(rst = '1') then
      busy            <= '0';
      ctr_iq          <= 0;
      reg_rf_skipcnt  <= (others => '0');
      eo_state        <= eo_idle;
      lusi_base_addrs_accum_i <= x"0000";
      lusi_base_addrs_accum_q <= x"0000";

    else
    
      case eo_state is

        when eo_idle =>
          if(axi_wr_ack = '1') then
            if(int_write_addr = 1) then -- "mval" from software, can calculate everything from this
              busy      <= '1';
              eo_state 	<= eo_calc_skipcnt;
            end if;
          end if;
          
        when eo_calc_skipcnt =>
        
          -- from software:
          -- skipcnt = mval * samples_per_cycle = mval * (BASECNT / 2) = mval * (16 / 2) = mval * 8 (so just left-shift by 3)
          -- output frequency : 37500 * x, where x = reg_mval
          -- using the bottom 13 bits of reg_mval multiplied by 8 allows us a maximum output frequency of
          -- ~ 37500 * 8192 * 8 = 2457600000 (which would just be a constant at double the nyquist rate, so we definitely have enough range)
          reg_rf_skipcnt <= reg_mval(12 downto 0) & "000";
        
          ctr_iq   <= 0;
          eo_state <= eo_calc_iq_addrs;

          lusi_base_addrs_accum_i <= x"0000";   -- start at 0 phase
          lusi_base_addrs_accum_q <= x"c000";   -- starting at -pi/2 phase (should be +pi/2 = 16,384?)
          
        when eo_calc_iq_addrs =>
        
          lusi_base_addrs_i(ctr_iq) <= lusi_base_addrs_accum_i;
          lusi_base_addrs_q(ctr_iq) <= lusi_base_addrs_accum_q;
          
          lusi_base_addrs_accum_i <= lusi_base_addrs_accum_i + reg_mval(15 downto 0);
          lusi_base_addrs_accum_q <= lusi_base_addrs_accum_q + reg_mval(15 downto 0);
          
          -- incriment base addresses
          ctr_iq <= ctr_iq + 1;
          if(ctr_iq = 7) then
            eo_state 	<= eo_idle;
            busy			<= '0';
          end if;
        
        when others =>
      end case;

    end if;
  end if;
end process;

end Behavioral;