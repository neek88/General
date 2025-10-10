-- Finite impulse response filter
--  User will load FIR kernel from CPU 
--  before starting data stream
-- Setup for 8-lanes of sample traffic

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;           -- signed/ unsigned / multiplication
use ieee.std_logic_unsigned.all;

entity FIR_Filt is

  generic(
    LANE_NUM        : integer := 8;
    SAMPLE_LEN      : integer := 16;    -- 16 bit samples 
    KERNEL_LEN      : integer := 31;    -- kernel length needs to be kept as small as possible
    KERN_SAMP_LEN   : integer := 30;    -- mult factor length (30) must be double the max divisor (15) for best resolution
    KERNEL_LEN_BIT  : integer := 5;     -- ceil(log2(KERNEL_LEN)) - how many bits req. to store KERNEL_LEN
    AXI_WIDTH       : integer := 32
  );
  
  port ( 
    clk_in            : in std_logic; 
    rst_in            : in std_logic;
    bypass_sel        : in std_logic;   -- bypass the filter core 
    stream_in         : in std_logic_vector(2*SAMPLE_LEN*LANE_NUM-1 downto 0);      -- handle I and Q data separately 
                      -- [255 : 0]
                      -- [MSS : LSS]    most significant sample (high)  -> least significant sample (low)
    filt_stream_out   : out std_logic_vector(2*SAMPLE_LEN*LANE_NUM-1 downto 0);
                      -- [255 : 0]
                      -- [MSS : LSS]    most significant sample (high)  -> least significant sample (low)
    -- AXI interface 
    -- Write Side --
    -- M --> S
    S_AXI_ACLK      : in  std_logic;
    S_AXI_ARESETN   : in  std_logic;
    S_AXI_AWADDR    : in  std_logic_vector(AXI_WIDTH-1 downto 0); 	-- Write address (Master --> Slave)
    S_AXI_AWVALID   : in  std_logic;                      -- Write address valid
    S_AXI_WDATA     : in  std_logic_vector(AXI_WIDTH-1 downto 0); 	-- Write data (Master --> Slave)
    S_AXI_WVALID    : in  std_logic;                      -- Write valid
    S_AXI_BREADY    : in  std_logic;
    S_AXI_WSTRB     : in  std_logic_vector( 3 downto 0); 	-- Write strobes
    -- S --> M
    S_AXI_AWREADY   : out std_logic;                     	-- Write address ready
    S_AXI_WREADY    : out std_logic;                     	-- Write ready
    S_AXI_BRESP     : out std_logic_vector(1 downto 0);  	-- Write response
    S_AXI_BVALID    : out std_logic;                     	-- Write response valid
    -- Not necessary for basic AXI transaction
    S_AXI_AWPROT    : in  std_logic_vector(2 downto 0)		-- Write channel Protection type
  );

end FIR_Filt;

architecture Behavioral of FIR_Filt is

-- convolve one signal stream with pre-loaded kernel
component convolution
port(
  clk_in       : in std_logic;
  axi_clk_in   : in std_logic;
  rst_in       : in std_logic; 
  sample_in    : in std_logic_vector(SAMPLE_LEN-1 downto 0);
  conv_out     : out std_logic_vector(SAMPLE_LEN-1 downto 0);
  kern_load    : in std_logic;
  kern_in      : in signed(KERN_SAMP_LEN-1 downto 0)
);
end component;

component multi_lane_sum
port ( 
  clk_in            : in std_logic; 
  rst_in            : in std_logic; 
  input_samples     : in std_logic_vector(SAMPLE_LEN*LANE_NUM - 1 downto 0);
  filtered_samples  : out std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0)
);
end component;

-- AXI4LITE signals for Slave device
-- Write side - slave controlled
signal axi_awready        : std_logic;
signal axi_wready         : std_logic;
signal axi_bresp          : std_logic_vector(1 downto 0);
signal axi_bvalid         : std_logic; 
-- Write side - slave watch 
signal axi_awaddr         : std_logic_vector(31 downto 0);
signal axi_wdata          : std_logic_vector(31 downto 0); 
signal axi_bready         : std_logic; 
signal axi_wstrb          : std_logic_vector( 3 downto 0);
signal axi_wvalid         : std_logic;
signal axi_awvalid        : std_logic;
---- Internal 
signal axi_wr_ack         : std_logic;
signal int_write_addr     : integer;

-- intermediate connecting signals
signal I_samples          : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);
signal Q_samples          : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);
signal conv_out_I         : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);     -- output from each convolution block
signal conv_out_Q         : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);     -- output from each convolution block
signal I_filt_strm        : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);
signal Q_filt_strm        : std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0);
signal signed_write_data  : signed(AXI_WIDTH-1 downto 0);

-- Debug
attribute mark_debug		: string; 
-- GEN
attribute mark_debug of bypass_sel  : signal is "true";
-- AXI 
attribute mark_debug of axi_awready  : signal is "true";
attribute mark_debug of axi_awvalid  : signal is "true";
attribute mark_debug of axi_wvalid  : signal is "true";
attribute mark_debug of axi_wr_ack  : signal is "true";
attribute mark_debug of int_write_addr  : signal is "true";
attribute mark_debug of signed_write_data  : signal is "true";
-- SAMPLES
--attribute mark_debug of conv_out_I  : signal is "true";
--attribute mark_debug of I_filt_strm  : signal is "true";
--attribute mark_debug of I_samples  : signal is "true";
--attribute mark_debug of Q_samples  : signal is "true";

begin 

-- split incoming sample stream into I / Q data 
I_samples       <= stream_in(SAMPLE_LEN*LANE_NUM - 1  downto 0);                      -- Least Significant Samples 
Q_samples       <= stream_in(2*SAMPLE_LEN*LANE_NUM - 1  downto SAMPLE_LEN*LANE_NUM);  -- Most Significant Samples 

-- recombine I/ Q sample streams together at output
filt_stream_out <= (Q_filt_strm & I_filt_strm); --when bypass_sel = '0' else stream_in;

-- track AXI addresses in real time
--    shift address left by two - divide by four to get index
--    address = 4 		-> index = 1
--    address = 128 	-> index = 32
int_write_addr <= to_integer(unsigned(axi_awaddr(7 downto 2))); -- Valid data is on external axi_awaddr line

axi_wstrb <= S_AXI_WSTRB;
-- debugging...
-- Write side 
axi_wvalid  <= S_AXI_WVALID; 
axi_awvalid <= S_AXI_AWVALID;
axi_awaddr  <= S_AXI_AWADDR;
axi_wdata   <= S_AXI_WDATA;
axi_bready  <= S_AXI_BREADY; 
-- Slave response
-- Write side
S_AXI_AWREADY <= axi_awready;
S_AXI_WREADY  <= axi_wready;
S_AXI_BRESP   <= axi_bresp;
S_AXI_BVALID  <= axi_bvalid;
-- general assignments
axi_bvalid <= '1';
axi_bresp  <= "00";
axi_wready  <= axi_wr_ack;
axi_awready <= axi_wr_ack;

-- AXI write interface to load kernel values before signal transmission
signed_write_data <= signed(S_AXI_WDATA);
load_kernel : process(S_AXI_ACLK, S_AXI_ARESETN, rst_in) begin
  if rising_edge(S_AXI_ACLK) then
    if(S_AXI_ARESETN = '0' or rst_in = '1') then
      axi_wr_ack 	<= '0'; 			  -- not ready to receive write-data
    else
      -- initiate handshaking on ADDRESS, Make Sure Address AND Data are ready to allow seamless transaction 
      if(axi_awready = '0' and axi_awvalid = '1' and axi_wvalid = '1') then
        axi_wr_ack  <= '1';
      else
        axi_wr_ack  <= '0';
      end if;
    end if;
  end if;
end process;


-- connect convolution block outputs
--  to convolution sum block 
reconstruct_I : multi_lane_sum
port map(
  clk_in            => clk_in,
  rst_in            => rst_in,
  input_samples     => conv_out_I,
  filtered_samples  => I_filt_strm
);

reconstruct_Q : multi_lane_sum
port map(
  clk_in            => clk_in,
  rst_in            => rst_in,
  input_samples     => conv_out_Q,
  filtered_samples  => Q_filt_strm
);

-- 8 blocks needed for convolution
--  of incoming I samples 
gen_I_conv_blocks : for i in 1 to LANE_NUM generate
  conv_block_I : convolution
  port map(
    clk_in       => clk_in,
    axi_clk_in   => S_AXI_ACLK,
    rst_in       => rst_in,
    sample_in    => I_samples(i*SAMPLE_LEN-1 downto (i-1)*SAMPLE_LEN),
    conv_out     => conv_out_I(i*SAMPLE_LEN-1 downto (i-1)*SAMPLE_LEN),
    kern_load    => axi_wr_ack,
    kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
  );
end generate;

-- 8 blocks needed for convolution
--  of incoming Q samples 
gen_Q_conv_blocks : for i in 1 to LANE_NUM generate
  conv_block_Q : convolution
  port map(
    clk_in       => clk_in,
    axi_clk_in   => S_AXI_ACLK,
    rst_in       => rst_in,
    sample_in    => Q_samples(i*SAMPLE_LEN-1 downto (i-1)*SAMPLE_LEN),
    conv_out     => conv_out_Q(i*SAMPLE_LEN-1 downto (i-1)*SAMPLE_LEN),
    kern_load    => axi_wr_ack,
    kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
  );
end generate;

--conv_block_I0 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(SAMPLE_LEN-1 downto 0),
--  conv_out     => conv_out_I(SAMPLE_LEN-1 downto 0),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I1 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(2*SAMPLE_LEN-1 downto (2-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(2*SAMPLE_LEN-1 downto (2-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I2 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(3*SAMPLE_LEN-1 downto (3-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(3*SAMPLE_LEN-1 downto (3-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I3 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(4*SAMPLE_LEN-1 downto (4-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(4*SAMPLE_LEN-1 downto (4-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I4 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(5*SAMPLE_LEN-1 downto (5-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(5*SAMPLE_LEN-1 downto (5-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I5 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(6*SAMPLE_LEN-1 downto (6-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(6*SAMPLE_LEN-1 downto (6-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I6 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(7*SAMPLE_LEN-1 downto (7-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(7*SAMPLE_LEN-1 downto (7-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_I7 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => I_samples(8*SAMPLE_LEN-1 downto (8-1)*SAMPLE_LEN),
--  conv_out     => conv_out_I(8*SAMPLE_LEN-1 downto (8-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q0 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(SAMPLE_LEN-1 downto 0),
--  conv_out     => conv_out_Q(SAMPLE_LEN-1 downto 0),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q1 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(2*SAMPLE_LEN-1 downto (2-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(2*SAMPLE_LEN-1 downto (2-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q2 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(3*SAMPLE_LEN-1 downto (3-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(3*SAMPLE_LEN-1 downto (3-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q3 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(4*SAMPLE_LEN-1 downto (4-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(4*SAMPLE_LEN-1 downto (4-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q4 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(5*SAMPLE_LEN-1 downto (5-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(5*SAMPLE_LEN-1 downto (5-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q5 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(6*SAMPLE_LEN-1 downto (6-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(6*SAMPLE_LEN-1 downto (6-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q6 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(7*SAMPLE_LEN-1 downto (7-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(7*SAMPLE_LEN-1 downto (7-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);

--conv_block_Q7 : convolution
--port map(
--  clk_in       => clk_in,
--  axi_clk_in   => S_AXI_ACLK,
--  rst_in       => rst_in,
--  sample_in    => Q_samples(8*SAMPLE_LEN-1 downto (8-1)*SAMPLE_LEN),
--  conv_out     => conv_out_Q(8*SAMPLE_LEN-1 downto (8-1)*SAMPLE_LEN),
--  kern_load    => axi_wr_ack,
--  kern_in      => signed_write_data(KERN_SAMP_LEN-1 downto 0)
--);



--------------
end Behavioral;
