-- Concepts to learn
-- 1. Floating point/ fixed point storage + math 
-- 2. Rounding after multiplication
-- 3. Data types (synth vs. non synth)
-- 4. Testbench writing
-- 5. Cordic modules


-- Notes:
-- 1. only storage elements can be given initial values

---- Library Files ----
library ieee 
use ieee.std_logic_1164.all 
use ieee.numeric_std.all 
use ieee.math_real.all
use ieee.math_complex.all 

-- Read files into your code
use ieee.std_logic_textio.all 
library STD;
use STD.textio;

---- Types ----
-- Built in types (standard library)
-----------------
signal s1 bit;                  -- 0, 1 or Z
signal s2 bit_vector(3 downto 0) := (0,0,1,Z);
signal s3 integer := 10;        -- -(2^31 - 1) to (2^31 - 1)
signal s4 natural := 0;         -- subtype of integer, 0 and above (limit: 2^31 - 1)
signal s5 positive := 1;        -- subtype of integer, 1 and above (limit: 2^31 - 1)
signal s6 character := 'a';     -- 0 to 255 ascii characters?
signal s7 string(0 to 7) := "abcdefgh";  -- array of characters
signal s8 boolean := true;
-- Non synthesizeable
signal ns_1 real := 10.5;     
signal ns_2 time := 100 ns;     -- fs, ps, ns, us, ms, sec

-- Enumerated types
type STATE_T is (
    INIT,
    STAGE_1,
    STAGE_2,
    FINAL
);
signal STATE : T_STATE;

-- std_logic_1164.all (only 0,1,Z are synthesizeable)
---------------------
signal sl_1 std_logic;            -- 0, 1, Z, U, X, H, L, W, -
signal sl_2 std_logic_vector(7 downto 0) := (0,1,1,1,1,1,0,0,0);

-- Array
type vector is array (7 downto 0) of std_logic_vector(7 downto 0);
signal my_vec vector := (others => (others => '0'));

-- Matrix
type matrix is array (3 downto 0, 3 downto 0) of integer;
signal my_matrix matrix := ((0,1,2,3),
                            (4,5,6,7),
                            (8,9,10,11),
                            (12,13,14,15));

-- numeric_std
--------------
signal ns_s signed (7 downto 0) := -128;
signal ns_u unsigned (7 downto 0) := 256;


---- Type Conversions/ resize ----

-- signed / unsigned to std_logic_vector 
sl_2 <= std_logic_vector(ns_s)

-- std_logic_vector to signed / unsigned
ns_s <= signed(sl_2)
ns_u <= unsigned(sl_2)

-- integer to signed/ unsigned
ns_u <= to_unsigned(s3, s3'length);
ns_s <= to_signed(s3, s3'length);

-- signed/unsigned to integer 
s3 <= to_integer(ns_u);

-- integer to std_logic_vector
sl_2 <= std_logic_vector(to_unsigned(s3, s3'length));

-- std_logic_vector to integer 
s3 <= to_integer(unsigned(sl_2));

resize(<unsigned_type>, to'length)

---- Component declaration ----
component mux
generic(
    n : positive
);
port(
    sel : in positive range 1 to n-1;
    din : in std_logic_vector(n-1 downto 0);
    q   : out std_logic;
); end component mux;

---- Component instantiation ----
-- 1. no way to specify which architecture to use
--  last compiled arch is the one used
-- 2. cannot use name of entity for component name
MUX_1 : mux
generic map (
    n => n
)
port map (
  sel => sel,
  din => din,
  q => q
);

---- Entity instantiation
-- label : entity library.entity(architecture)
-- architecture name is optional, but needed if you have more than one per entity
MUX : entity work.mux(rtl)
generic map(
    n => n
)
port map(
    sel => sel,
    din => din,
    q => q
);


---- Testbench tools ----

-- After statement: 
--  1. assign signal a value at specified time in future
--  2. Can be used in concurrent statments or inside process
<signal> <= <initial_value>, <end_value> after <time>;
-- Ex - single toggle
reset <= '1', '0' after 1 us;
-- Ex - continuous toggle
clock <= not clock after 10 ns;


-- wait statment:
--  1. temporarily suspend execution of code in process
--  2. used in process without sensitivity list (due to blocking behavior)
--  3. code stops for set period of time or until signal changes state
--  4. Three types:

-- suspend execution for <time>
wait for <time>;
wait; -- wait indefinately
-- Can use <rising_edge> or <falling_edge> macros for <condition>
wait until <condition> for <time>;

-- wait for <signal_name> to change state
wait on <signal_name>;
-- Ex - multiple signals
wait on sig_a, sig_b;

-- Testbench creation
--  1. Create empty entity and architecture
--      The testbench wraps around the entire project
        ----------------------------------------------
        --                                          --
        -- stimulus -> DUT -> output_capture/verify --
        --                                          --
        ----------------------------------------------

entity example_tb is
end entity example_tb;
architecture test of example_tb is    
-- Test bench code goes here
end architecture test;

--  2. Instantiate the DUT inside the arch
dut: entity work.example_design(rtl)
entity
generic map (
    WIDTH => 8
)
port map (
    clk   => clock,
    reset	=> reset,
    a     => in_a,
    b     => in_b,
    q     => out_q
);

-------------------------------------------
---- standard library (included by default)
-------------------------------------------
package standard is 
  type boolean is (false,true); 
  type bit is ('0', '1'); 
  type character is (
    nul, soh, stx, etx, eot, enq, ack, bel, 
    bs,  ht,  lf,  vt,  ff,  cr,  so,  si, 
    dle, dc1, dc2, dc3, dc4, nak, syn, etb, 
    can, em,  sub, esc, fsp, gsp, rsp, usp, 

    ' ', '!', '"', '#', '$', '%', '&', ''', 
    '(', ')', '*', '+', ',', '-', '.', '/', 
    '0', '1', '2', '3', '4', '5', '6', '7', 
    '8', '9', ':', ';', '<', '=', '>', '?', 
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 
    'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 
    'X', 'Y', 'Z', '[', '\', ']', '^', '_', 
    '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 
    'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 
    'x', 'y', 'z', '{', '|', '}', '~', del);
    -- VHDL'93 includes all 256 ASCII characters

  type severity_level is (note, warning, error, failure); 
  type integer is range -2147483647 to 2147483647; 
  type real is range -1.0E308 to 1.0E308; 
  type time is range -2147483647 to 2147483647 
    units 
      fs;
      ps = 1000 fs;
      ns = 1000 ps;
      us = 1000 ns; 
      ms = 1000 us; 
      sec = 1000 ms; 
      min = 60 sec; 
      hr = 60 min; 
    end units; 
  subtype delay_length is time range 0 fs to time'high;
  impure function now return delay_length; 
  function now return time;    -- VHDL'87 only
  subtype natural is integer range 0 to integer'high; 
  subtype positive is integer range 1 to integer'high; 
  type string is array (positive range <>) of character; 
  type bit_vector is array (natural range <>) of bit; 
  type file_open_kind is (
    read_mode,
    write_mode,
    append_mode);
  type file_open_status is (
    open_ok,
    status_error,
    name_error,
    mode_error);
  attribute foreign: string;
end standard; 