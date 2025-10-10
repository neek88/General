-- final sum for multi-path convolution

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;               -- signed/ unsigned / multiplication
use ieee.std_logic_unsigned.all;
  
entity multi_lane_sum is
  generic(
    SAMPLE_LEN      : integer := 16;    -- 16 bit samples 
    LANE_NUM        : integer := 8;     -- 8 lanes of sample traffic
    EXT_SMPL_LEN    : integer := 19     -- length of sum overflow : ceil(log2(LANE_NUM)) + SAMPLE_LEN = 19
  );
  
  port ( 
    clk_in            : in std_logic; 
    rst_in            : in std_logic; 
    input_samples     : in std_logic_vector(SAMPLE_LEN*LANE_NUM - 1 downto 0);
    filtered_samples  : out std_logic_vector(SAMPLE_LEN*LANE_NUM - 1  downto 0)
  );

end multi_lane_sum;

architecture Behavioral of multi_lane_sum is

-- Create FIFO's to store input samples, kernel multipliers, and multiplication results
type sample_fifo is array (LANE_NUM-1 downto 0) of signed(SAMPLE_LEN-1 downto 0);          -- 16 bits to store input samples
type ext_sample_fifo is array(LANE_NUM-1 downto 0) of signed(EXT_SMPL_LEN-1 downto 0);   -- 19 bits to store overlow sum

-- zeros for default assignment on reset
constant zero_sample : signed(SAMPLE_LEN-1 downto 0) := x"0000";
constant zero_fifo : sample_fifo := (others => zero_sample);

constant zero_ext_sample : signed(EXT_SMPL_LEN-1 downto 0) := "000" & x"0000";
constant zero_ext : ext_sample_fifo := (others => zero_ext_sample);

-- input signal, kernel, multiplication result fifo's
signal conv_res_prev : ext_sample_fifo;     -- stores previous value of convolution result input samples
signal conv_sum_out : ext_sample_fifo;     -- stores the corrected samples of convolution sum combination

-- summation staging signals
signal conv_sum_out_sg1 : ext_sample_fifo;
signal conv_sum_out_sg2 : ext_sample_fifo;

-- Debug 
attribute mark_debug		: string;
--attribute mark_debug of conv_sum_out  : signal is "true";
--attribute mark_debug of conv_res_prev : signal is "true";

begin
-- connect convolution sum array to output vector
-- grab high-order bits from conv_sum_out - acts as a right shift by 3 (divide by 8)
gen_conv_blocks : for i in 1 to LANE_NUM generate
  filtered_samples(i*SAMPLE_LEN-1 downto (i-1)*SAMPLE_LEN)  <= std_logic_vector(conv_sum_out(i-1)(EXT_SMPL_LEN-1 downto 3));
end generate;

--  compute the running convolution sum
--    of incoming samples and the filter kernel 
convsum : process(clk_in, rst_in) begin 
if rising_edge(clk_in) then
  if(rst_in = '1') then
    conv_res_prev     <= zero_ext;
    conv_sum_out      <= zero_ext;
    conv_sum_out_sg1  <= zero_ext;
    conv_sum_out_sg2  <= zero_ext;
  else
      
    -- capture input samples into array
    -- all input samples will be resized PER clk period
    for i in 0 to LANE_NUM-1 loop 
      conv_res_prev(i)  <= resize(signed(input_samples((i+1)*SAMPLE_LEN-1 downto SAMPLE_LEN*i)),EXT_SMPL_LEN);
    end loop; 

    -- calculate output sums from input samples/ prev samples 
    -- we are going to 'stage' the summation in order to appease timing
    ---
    conv_sum_out_sg1(0) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) +
                         conv_res_prev(1) + conv_res_prev(2) + conv_res_prev(3);
    conv_sum_out_sg2(0) <= conv_res_prev(4) + conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);
    conv_sum_out(0)     <= conv_sum_out_sg1(0) + conv_sum_out_sg2(0);
    
    ---    
    conv_sum_out_sg1(1) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) +
                           conv_res_prev(2) + conv_res_prev(3);
    conv_sum_out_sg2(1) <= conv_res_prev(4) + conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);  
    conv_sum_out(1)     <= conv_sum_out_sg1(1) + conv_sum_out_sg2(1);
    
    ---
    conv_sum_out_sg1(2) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) +
                           conv_res_prev(3);
    conv_sum_out_sg2(2) <= conv_res_prev(4) + conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);  
    conv_sum_out(2)     <= conv_sum_out_sg1(2) + conv_sum_out_sg2(2);   
                   
    ---
    conv_sum_out_sg1(3) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN);
    conv_sum_out_sg2(3) <= conv_res_prev(4) + conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);
    conv_sum_out(3)     <= conv_sum_out_sg1(3) + conv_sum_out_sg2(3);
    
    ---
    conv_sum_out_sg1(4) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN); 
    conv_sum_out_sg2(4) <= resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) +
                           conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);
    conv_sum_out(4)     <= conv_sum_out_sg1(4) + conv_sum_out_sg2(4);
    
    ---
    conv_sum_out_sg1(5) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN);
    conv_sum_out_sg2(5) <= resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
                           conv_res_prev(6) + conv_res_prev(7);
    conv_sum_out(5)     <= conv_sum_out_sg1(5) + conv_sum_out_sg2(5);
    
    ---
    conv_sum_out_sg1(6) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN);
    conv_sum_out_sg2(6) <= resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
                           resize(signed(input_samples(111 downto 96)),EXT_SMPL_LEN) +
                           conv_res_prev(7);
    conv_sum_out(6)     <= conv_sum_out_sg1(6) + conv_sum_out_sg2(6);
    
    ---
    conv_sum_out_sg1(7) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
                           resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN);
    conv_sum_out_sg2(7) <= resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
                           resize(signed(input_samples(111 downto 96)),EXT_SMPL_LEN) + resize(signed(input_samples(127 downto 112)),EXT_SMPL_LEN);
    conv_sum_out(7)     <= conv_sum_out_sg1(7) + conv_sum_out_sg2(7);                   

  end if;
end if; 
end process; 

-- This is effectivly what we're doing above. we are just staging the sum to help with timing
--    conv_sum_out(0) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) +
--                       conv_res_prev(1) + conv_res_prev(2) + conv_res_prev(3) + conv_res_prev(4) +
--                       conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);
                        
--    conv_sum_out(1) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) +
--                       conv_res_prev(2) + conv_res_prev(3) + conv_res_prev(4) +
--                       conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);

--    conv_sum_out(2) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) +
--                       conv_res_prev(3) + conv_res_prev(4) + conv_res_prev(5) +
--                       conv_res_prev(6) + conv_res_prev(7);

--    conv_sum_out(3) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN) +
--                       conv_res_prev(4) + conv_res_prev(5) + conv_res_prev(6) +
--                       conv_res_prev(7);

--    conv_sum_out(4) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) +
--                       conv_res_prev(5) + conv_res_prev(6) + conv_res_prev(7);

--    conv_sum_out(5) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
--                       conv_res_prev(6) + conv_res_prev(7);

--    conv_sum_out(6) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
--                       resize(signed(input_samples(111 downto 96)),EXT_SMPL_LEN) +
--                       conv_res_prev(7);
                       
--    conv_sum_out(7) <= resize(signed(input_samples(15 downto  0)),EXT_SMPL_LEN) + resize(signed(input_samples(31 downto 16)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(47 downto 32)),EXT_SMPL_LEN) + resize(signed(input_samples(63 downto 48)),EXT_SMPL_LEN) + 
--                       resize(signed(input_samples(79 downto 64)),EXT_SMPL_LEN) + resize(signed(input_samples(95 downto 80)),EXT_SMPL_LEN) +
--                       resize(signed(input_samples(111 downto 96)),EXT_SMPL_LEN) + resize(signed(input_samples(127 downto 112)),EXT_SMPL_LEN);

--------------
end Behavioral;