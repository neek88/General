-- Computes running convolution between two
--  sample streams. Block can be loaded with
--  fixed length kernel before signal
--  transmission begins

-- NOTES:
--  Since we are doing alot of addition and multiplication,
--    we have to keep track of resultant lengths
--  n bits + n bits = n+1 bits              convolution result sum
--  n bits * m bits = n + m bits            multiplication terms
--  (n bits * m bits) >> m bits = n bits    mult. terms post division

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;                         -- signed/ unsigned / multiplication
use ieee.std_logic_unsigned.all;

entity convolution is
  generic(
        SAMPLE_LEN      : integer := 16;          -- 16 bit samples 
        KERNEL_LEN      : integer := 31;          -- kernel length needs to be kept as small as possible
        OVRFLW_SUM      : integer := 21;          -- ceil(log2(KERNEL_LEN)) + sample_len = 21 bits
        KERN_DIV_LEN    : integer := 15;          -- 16 bit number can be right shifted at MOST 15 times
        KERN_SAMP_LEN   : integer := 30;          -- mult factor length (30) must be double the max divisor (15) for best resolution
        MULT_RES_LEN    : integer := 30 + 16      -- multiplying (30) bit number with (16) bit number results ina (30 + 16 = 46) bit number
  );
  
  port ( 
        clk_in       : in std_logic; 
        axi_clk_in   : in std_logic;
        rst_in       : in std_logic; 
        sample_in    : in std_logic_vector(SAMPLE_LEN-1 downto 0);
        conv_out     : out std_logic_vector(SAMPLE_LEN-1 downto 0);
        kern_load    : in std_logic;
        kern_in      : in signed(KERN_SAMP_LEN-1 downto 0)
  );
end convolution;

architecture Behavioral of convolution is

-- Create FIFO's to store input samples, kernel multipliers, and multiplication results
type   kern_fifo is array (KERNEL_LEN-1 downto 0) of signed(KERN_SAMP_LEN-1 downto 0);      -- 30 bits required for kernel values
type   conv_fifo is array (KERNEL_LEN-1 downto 0) of signed(SAMPLE_LEN-1 downto 0);         -- 16 bits to store shifted input samples
type   mult_fifo is array (KERNEL_LEN-1 downto 0) of signed(MULT_RES_LEN-1 downto 0);       -- 30 + 16 bits to store multiplication factor
type   sign_fifo is array (KERNEL_LEN-1 downto 0) of signed(OVRFLW_SUM-1 downto 0);         -- 21 bits to store sign extended dn_fifo values

-- zeros for default assignment on reset
constant test_kernel_val : signed(KERN_SAMP_LEN-1 downto 0) := "00" & x"0421084";
constant zero_kernel : signed(KERN_SAMP_LEN-1 downto 0) := "00" & x"0000000";
constant test_kern_ma : kern_fifo := (others => test_kernel_val);                   -- preload moving average kernel 
constant zero_kern : kern_fifo := (others => zero_kernel);                          -- preload zero kernel 

-- test bandpass kernel (102.4M w/ 20M BW) 
constant test_kern_bp: kern_fifo := ("00"& x"0000000", "00"& x"0000C4F", "11"& x"FFFB371", "00"& x"0004EC3",
                                     "00"& x"00249C6", "11"& x"FF738BC", "00"& x"008EA53", "00"& x"0176BB6",
                                     "11"& x"F7C6E12", "00"& x"0F1CE87", "00"& x"05719F1", "11"& x"C3A9C1B",
                                     "00"& x"5B9F46E", "11"& x"DF7CC52", "11"& x"A868604", "00"& x"95BBF0C",
                                     "11"& x"A868604", "11"& x"DF7CC52", "00"& x"5B9F46E", "11"& x"C3A9C1B",
                                     "00"& x"05719F1", "00"& x"0F1CE87", "11"& x"F7C6E12", "00"& x"0176BB6",
                                     "00"& x"008EA53", "11"& x"FF738BC", "00"& x"00249C6", "00"& x"0004EC3",
                                     "11"& x"FFFB371", "00"& x"0000C4F", "00"& x"0000000");
--                                    (0, 		3151, -19599, 20163, 
--                                    149958, -575300, 584275, 1534902, 
--                                    -8622574, 15847047, 5708273, -63267813,
--                                    96072814, -34091950, -91847164, 157007628,
--                                    -91847164, -34091950, 96072814, -63267813,
--                                    5708273, 15847047, -8622574, 1534902, 
--                                    584275, -575300, 149958, 20163,
--                                    -19599,  3151, 0);

constant zero_convolution : signed(SAMPLE_LEN-1 downto 0) := x"0000";
constant zero_conv : conv_fifo := (others => zero_convolution);

constant zero_multip : signed(MULT_RES_LEN-1 downto 0) := "00" & x"00000000000";
constant zero_mult : mult_fifo := (others => zero_multip);

-- input signal, kernel, multiplication result fifo's
signal kernel   : kern_fifo;    -- stores kernel values, loaded at startup                  (30 bits/ entry)
signal xn_fifo  : conv_fifo;    -- stores input samples used in calculating convolution sum (16 bits/ entry)
signal mn_fifo  : mult_fifo;    -- result of multiplication between kernel + xn_fifo        (36 bits/ entry)
signal dn_fifo  : conv_fifo;    -- result of 'division'; right shifted multiplication       (16 bits/ entry)
signal sum_fifo : sign_fifo;    -- result of sign-extending the division result
signal kern_load_d : std_logic;   -- kern_load signal, one cycle delayed

-- instantaneous sum of the convolution
signal conv_sum_std : std_logic_vector(OVRFLW_SUM-1 downto 0); -- convert sum to std_logic_vector
signal conv_sum     : signed(OVRFLW_SUM-1 downto 0);      -- final output sum
signal conv_sum_sg1 : signed(OVRFLW_SUM-1 downto 0);  -- output sum must be calculated in stages due to timing constraints    
signal conv_sum_sg2 : signed(OVRFLW_SUM-1 downto 0);      
signal conv_sum_sg3 : signed(OVRFLW_SUM-1 downto 0);         
signal conv_sum_sg4 : signed(OVRFLW_SUM-1 downto 0);     
signal conv_sum_sg5 : signed(OVRFLW_SUM-1 downto 0);               
signal conv_sum_sg6 : signed(OVRFLW_SUM-1 downto 0);               

-- Debug 
attribute mark_debug		: string; 
--attribute mark_debug of mn_fifo  : signal is "true";
--attribute mark_debug of dn_fifo  : signal is "true";
--attribute mark_debug of kernel  : signal is "true";
--attribute mark_debug of sum_fifo  : signal is "true";
--attribute mark_debug of conv_sum  : signal is "true";
--attribute mark_debug of kern_load  : signal is "true";

begin 
--  we must take into account overflow:
--      - the final sum will be 16-bit + 16-bit + ... 16-bit number
--      - there are 'KERNEL_LEN' terms in the sum, so the final result will
--      - have a maximum length of 16_bits * log2(KERNEL_LEN)_bits = 16 + log2(KERNEL_LEN)
--      - KERNEL_LEN = 31, ceil(log2(KERNEL_LEN)) = 5, 
--      - convolution_sum length = 16 + 5 = 21 
--  ALTHOUGH
--      - since the kernel values are fractional, the convolution_sum should never
--      - break 16 bits

-- shift in data, multiplying by kernel value
--  divide result by right shift
conv : process(clk_in, rst_in) begin 
if rising_edge(clk_in) then
  if(rst_in = '1') then
    mn_fifo   <= zero_mult;
    xn_fifo   <= zero_conv;
    dn_fifo   <= zero_conv;
  else
  
    -- update xn_FIFO
    --  store converted sample input
    xn_fifo(0)  <= signed(sample_in);
    -- shift xn_FIFO
    for i in 1 to KERNEL_LEN-1 loop 
      xn_fifo(i)  <= xn_fifo(i-1);
    end loop; 
    
    -- update MN_FIFO
    --  calculate mult between kernel and inputs 
    for i in 0 to KERNEL_LEN-1 loop 
      mn_fifo(i)  <= xn_fifo(i) * kernel(i);   
    end loop;   
    
    -- update DN_FIFO
    --  right shift mn_fifo values, completing the 'division through multiplication'
    for i in 0 to KERNEL_LEN-1 loop
      dn_fifo(i)  <= mn_fifo(i)(MULT_RES_LEN-1 downto KERN_SAMP_LEN);
    end loop;
 
    -- sign extend the dn_fifo values to allow for an overflow-sum calculation
    for i in 0 to KERNEL_LEN-1 loop
      sum_fifo(i) <= resize(dn_fifo(i),OVRFLW_SUM);  
    end loop;
  
    -- break sum down into multiple sections to appease timing...
    conv_sum_sg1  <= sum_fifo(0) + sum_fifo(1) + sum_fifo(2) + sum_fifo(3) + sum_fifo(4);
    conv_sum_sg2  <= sum_fifo(5) + sum_fifo(6) + sum_fifo(7) + sum_fifo(8) + sum_fifo(9);
    conv_sum_sg3  <= sum_fifo(10) + sum_fifo(11) + sum_fifo(12) + sum_fifo(13) + sum_fifo(14);
    conv_sum_sg4  <= sum_fifo(15) + sum_fifo(16) + sum_fifo(17) + sum_fifo(18) + sum_fifo(19);
    conv_sum_sg5  <= sum_fifo(20) + sum_fifo(21) + sum_fifo(22) + sum_fifo(23) + sum_fifo(24);
    conv_sum_sg6  <= sum_fifo(25) + sum_fifo(26) + sum_fifo(27) + sum_fifo(28) + sum_fifo(29);
    
    -- take sum of sign-extended quotient data
    conv_sum  <= conv_sum_sg1 + conv_sum_sg2 + conv_sum_sg3 + conv_sum_sg4 + conv_sum_sg5 + conv_sum_sg6;
    
    -- convert sum back to std_logic_vector
    conv_sum_std  <= std_logic_vector(conv_sum);
    
    -- grab the higher order bits (20:5)?   (is there overflow?)
    conv_out      <= conv_sum_std(15 downto 0);

  end if;
end if; 
end process; 

load_kernel : process(axi_clk_in, rst_in) begin 
if rising_edge(axi_clk_in) then
  if(rst_in = '1') then
    kernel  <= test_kern_bp;   -- default kernel to zero's
    kern_load_d <= '0';
  else
  
    kern_load_d <= kern_load;
    
    -- shift in data into kernel fifo 
    if(kern_load = '1' and kern_load_d = '0') then
      --  store converted sample input
      kernel(0)  <= kern_in;
      -- shift kernel fifo
      for i in 1 to KERNEL_LEN-1 loop 
        kernel(i)  <= kernel(i-1);
      end loop; 

    end if;
  end if;

end if;
end process;

--------------
end Behavioral;