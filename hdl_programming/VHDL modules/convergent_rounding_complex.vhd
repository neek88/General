-- Computes the convergent rounding algorithm to remove DC offset from truncation events
-- Adds one cycle of delay to pipeline
entity convergent_rounding_complex is 
    generic(
        IWID : integer := 32;
        OWID : integer := 16
    );
    Port(
        clk : in std_logic;
        rst : in std_logic;
        sample_in : in std_logic_vector(2*IWID-1 downto 0);
        sample_in_valid : in std_logic;
        sample_out : out std_logic_vector(2*OWID-1 downto 0);
        sample_out_valid : out std_logic
    );
end convergent_rounding_complex;

architecture Behavioral convergent_rounding_complex is 

signal cr_res_i : signed(IWID-1 downto 0);
signal cr_res_q : signed(IWID-1 downto 0);

signal cr_l_i : std_logic_vector((IWID-OWID-1)-1 downto 0);
signal cr_l_q : std_logic_vector((IWID-OWID-1)-1 downto 0);

begin 

cr_l_i <= (others => not sample_in(IWID-OWID));
cr_l_q <= (others => not sample_in(2*IWID-OWID));

sample_out <= std_logic_vector(cr_res_q(IWID-1 downto IWID-OWID)) &
                                cr_res_i(IWID-1 downto IWID-OWID));



compute_rounding : process(clk) begin 
if(rising_edge(clk)) then 
    if(rst = '1') then 
        cr_res_i <= (others => '0');
        cr_res_q <= (others => '0');
    else 
        if(sample_in_valid = '1') then 
            cr_res_i <= signed(sample_in(IWID-1 downto 0)) + signed(resize(unsigned(sample_in(IWID-OWID) & cr_l_i), cr_res_i'length));
            cr_res_q <= signed(sample_in(2*IWID-1 downto IWID)) + signed(resize(unsigned(sample_in(2*IWID-OWID) & cr_l_q), cr_res_q'length));
            sample_out_valid <= '1';
        else 
            sample_out_valid <= '0';
        end if;
    end if;
end if;
end process;


end Behavioral;