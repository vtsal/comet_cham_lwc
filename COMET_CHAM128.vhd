----------------------------------------------------------------------------------
-- COMET-CHAM(V1)
-- Behnaz Rezvani
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.SomeFunction.all;
--use work.design_pkg.all;

-- Entity
----------------------------------------------------------------------------------
entity COMET_CHAM128 is
    Port(
        clk             : in std_logic;
        rst             : in std_logic;
        -- Data Input
        key             : in std_logic_vector(31 downto 0); -- SW = 32
        bdi             : in std_logic_vector(31 downto 0); -- W = 32
        -- Key Control
        key_valid       : in std_logic;
        key_ready       : out std_logic;
        key_update      : in std_logic;
        -- BDI Control
        bdi_valid       : in std_logic;
        bdi_ready       : out std_logic;
        bdi_pad_loc     : in std_logic_vector(3 downto 0); -- W/8 = 4
        bdi_valid_bytes : in std_logic_vector(3 downto 0); -- W/8 = 4
        bdi_size        : in std_logic_vector(2 downto 0); -- W/(8+1) = 3
        bdi_eot         : in std_logic;
        bdi_eoi         : in std_logic;
        bdi_type        : in std_logic_vector(3 downto 0);
        hash_in         : in std_logic;
        decrypt_in      : in std_logic;
        -- Data Output
        bdo             : out std_logic_vector(31 downto 0); -- W = 32
        -- BDO Control
        bdo_valid       : out std_logic;
        bdo_ready       : in std_logic;
        bdo_valid_bytes : out std_logic_vector(3 downto 0); -- W/8 = 4
        end_of_block    : out std_logic;
        bdo_type        : out std_logic_vector(3 downto 0);
        -- Tag Verification
        msg_auth        : out std_logic;
        msg_auth_valid  : out std_logic;
        msg_auth_ready  : in std_logic    
    );
end COMET_CHAM128;

-- Architecture
----------------------------------------------------------------------------------
architecture Behavioral of COMET_CHAM128 is

    -- Constants -----------------------------------------------------------------
    --bdi_type and bdo_type encoding
    constant HDR_AD         : std_logic_vector(3 downto 0) := "0001";
    constant HDR_MSG        : std_logic_vector(3 downto 0) := "0100";
    constant HDR_CT         : std_logic_vector(3 downto 0) := "0101";
    constant HDR_TAG        : std_logic_vector(3 downto 0) := "1000";
    constant HDR_KEY        : std_logic_vector(3 downto 0) := "1100";
    constant HDR_NPUB       : std_logic_vector(3 downto 0) := "1101";
    
    -- All zero constant
    constant zero123         : std_logic_vector(122 downto 0) := (others => '0');
    constant zero120         : std_logic_vector(119 downto 0) := (others => '0');
    
    -- Types ---------------------------------------------------------------------
    type fsm is (idle, wait_key, load_key, wait_Npub, load_Npub, process_Npub, wait_AD,
                 load_AD, process_AD, wait_data, load_data, process_data, prepare_output_data,
                 output_data, process_tag, output_tag, wait_tag, load_tag,verify_tag);

    -- Signals -------------------------------------------------------
    -- CHAM signals
    signal CHAM_key         : std_logic_vector(127 downto 0);
    signal CHAM_in          : std_logic_vector(127 downto 0);
    signal CHAM_out         : std_logic_vector(127 downto 0);
    signal CHAM_start       : std_logic;
    signal CHAM_done        : std_logic;

    -- Data signals
    signal bdoReg_rst       : std_logic;
    signal bdoReg_en        : std_logic;
    signal bdoReg_in        : std_logic_vector(31 downto 0);
    
    signal KeyReg128_rst    : std_logic;
    signal KeyReg128_en     : std_logic;
    signal KeyReg128_in     : std_logic_vector(127 downto 0);
    signal secret_key_reg   : std_logic_vector(127 downto 0);
    
    signal iDataReg_rst     : std_logic;
    signal iDataReg_en      : std_logic;
    signal iDataReg_in      : std_logic_vector(127 downto 0);
    signal iDataReg_out     : std_logic_vector(127 downto 0);
    
    signal oDataReg_rst     : std_logic;
    signal oDataReg_en      : std_logic;
    signal oDataReg_in      : std_logic_vector(127 downto 0);
    signal oDataReg_out     : std_logic_vector(127 downto 0);
    
    signal ZstateReg_rst    : std_logic;
    signal ZstateReg_en     : std_logic;
    signal ZstateReg_in     : std_logic_vector(127 downto 0);
    signal ZstateReg_out    : std_logic_vector(127 downto 0);
    
    signal YstateReg_rst    : std_logic;
    signal YstateReg_en     : std_logic;
    signal YstateReg_in     : std_logic_vector(127 downto 0);
    signal YstateReg_out    : std_logic_vector(127 downto 0);

    -- Control Signals
    signal init             : std_logic; -- For initialization state
    
    signal ValidBytesReg_rst: std_logic;
    signal ValidBytesReg_en : std_logic;
    signal ValidBytesReg_out: std_logic_vector(3 downto 0);
    
    signal bdi_eot_rst      : std_logic;
    signal bdi_eot_en       : std_logic;
    signal bdi_eot_reg      : std_logic;
    
    signal bdi_eoi_rst      : std_logic;
    signal bdi_eoi_en       : std_logic;
    signal bdi_eoi_reg      : std_logic;
    
    signal decrypt_rst      : std_logic;
    signal decrypt_set      : std_logic;
    signal decrypt_reg      : std_logic;
    
    signal first_AD_reg     : std_logic;
    signal first_AD_rst     : std_logic;
    signal first_AD_set     : std_logic;
    
    signal last_AD_reg      : std_logic;
    signal last_AD_rst      : std_logic;
    signal last_AD_set      : std_logic;
    
    signal no_AD_reg        : std_logic;
    signal no_AD_rst        : std_logic;
    signal no_AD_set        : std_logic;
    
    signal first_M_reg      : std_logic;
    signal first_M_rst      : std_logic;
    signal first_M_set      : std_logic;
    
    signal last_M_reg       : std_logic;
    signal last_M_rst       : std_logic;
    signal last_M_set       : std_logic;
    
    signal no_M_reg         : std_logic;
    signal no_M_rst         : std_logic;
    signal no_M_set         : std_logic;
    
    signal bdo_valid_rst    : std_logic;
    signal bdo_valid_set    : std_logic;
    
    signal end_of_block_rst : std_logic;
    signal end_of_block_set : std_logic;
    signal end_of_block_M   : std_logic;
    
    signal bdoTypeReg_rst   : std_logic;
    signal bdoTypeReg_en    : std_logic := '0';
    signal bdoTypeReg_in    : std_logic_vector(3 downto 0);
    
    signal bdoValidBReg_rst : std_logic;
    signal bdoValidBReg_en  : std_logic := '0';
    signal bdoValidBReg_in  : std_logic_vector(3 downto 0);

    -- Counter signals
    signal ctr_words_rst    : std_logic;
    signal ctr_words_inc    : std_logic;
    signal ctr_words        : std_logic_vector(2 downto 0);
    
    signal ctr_bytes_rst    : std_logic;
    signal ctr_bytes_inc    : std_logic;
    signal ctr_bytes_dec    : std_logic;
    signal ctr_bytes        : std_logic_vector(4 downto 0); -- Truncate the output based on this counter value
    
    -- State machine signals
    signal state            : fsm;
    signal next_state       : fsm;
    
    -- Components ----------------------------------------------------
    component CHAM128 is
        Port(
            clk, rst    : in std_logic;
            start       : in std_logic;
            Key         : in std_logic_vector(127 downto 0);
            CHAM_in     : in std_logic_vector(127 downto 0);
            CHAM_out    : out std_logic_vector(127 downto 0);
            done        : out std_logic
        );
    end component CHAM128;
----------------------------------------------------------------------------------    
begin

    CHAM_in     <= iDataReg_out when (init = '1') else
                   YstateReg_out(31 downto 0) & YstateReg_out(63 downto 32) &
                   YstateReg_out(95 downto 64) & YstateReg_out(127 downto 96);
    CHAM_key    <= secret_key_reg when (init = '1') else
                   ZstateReg_out(31 downto 0) & ZstateReg_out(63 downto 32) &
                   ZstateReg_out(95 downto 64) & ZstateReg_out(127 downto 96);
    
    Ek: CHAM128
    Port map(
        clk         => clk,
        rst         => rst,
        start       => CHAM_start,
        Key         => CHAM_key,
        CHAM_in     => CHAM_in,
        CHAM_out    => CHAM_out,
        done        => CHAM_done
    );
    
    bdoReg: entity work.myReg
    generic map( b => 32)
    Port map(
        clk     => clk,
        rst     => bdoReg_rst,
        en      => bdoReg_en,
        D_in    => bdoReg_in,
        D_out   => bdo
    );
    
    KeyReg128: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => KeyReg128_rst,
        en      => KeyReg128_en,
        D_in    => KeyReg128_in,
        D_out   => secret_key_reg
    );
     
    iDataReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => iDataReg_rst,
        en      => iDataReg_en,
        D_in    => iDataReg_in,
        D_out   => iDataReg_out
    );
    
    oDataReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => oDataReg_rst,
        en      => oDataReg_en,
        D_in    => oDataReg_in,
        D_out   => oDataReg_out
    );
    
    ZstateReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => ZstateReg_rst,
        en      => ZstateReg_en,
        D_in    => ZstateReg_in,
        D_out   => ZstateReg_out
    );
    
    YstateReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => YstateReg_rst,
        en      => YstateReg_en,
        D_in    => YstateReg_in,
        D_out   => YstateReg_out
    );
    
    ValidBytesReg: entity work.myReg
    generic map( b => 4)
    Port map(
        clk     => clk,
        rst     => ValidBytesReg_rst,
        en      => ValidBytesReg_en,
        D_in    => bdi_valid_bytes,
        D_out   => ValidBytesReg_out
    );
    
    bdoTypeReg: entity work.myReg
    generic map( b => 4)
    Port map(
        clk     => clk,
        rst     => bdoTypeReg_rst,
        en      => bdoTypeReg_en,
        D_in    => bdoTypeReg_in,
        D_out   => bdo_type
    );
    
    bdoValidBReg: entity work.myReg
    generic map( b => 4)
    Port map(
        clk     => clk,
        rst     => bdoValidBReg_rst,
        en      => bdoValidBReg_en,
        D_in    => bdoValidBReg_in,
        D_out   => bdo_valid_bytes
    );
    
    ---------------------------------------------------------------------------------
    Sync: process(clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state   <= idle;
            else
                state   <= next_state;
            
                if (ctr_words_rst = '1') then
                    ctr_words   <= "000";
                elsif (ctr_words_inc = '1') then
                    ctr_words   <= ctr_words + 1;
                end if;
                
                if (ctr_bytes_rst = '1') then
                    ctr_bytes   <= "00000";
                elsif (ctr_bytes_inc = '1') then
                    ctr_bytes   <= ctr_bytes + bdi_size;
                elsif (ctr_bytes_dec = '1') then
                    ctr_bytes   <= ctr_bytes - 4;
                end if;
                
                if (decrypt_rst = '1') then
                    decrypt_reg <= '0';
                elsif (decrypt_set = '1') then
                    decrypt_reg <= '1';
                end if;
                
                if (first_AD_rst = '1') then
                    first_AD_reg <= '0';
                elsif (first_AD_set = '1') then
                    first_AD_reg <= '1';
                end if;
                
                if (last_AD_rst = '1') then
                    last_AD_reg <= '0';
                elsif (last_AD_set = '1') then
                    last_AD_reg <= '1';
                end if;

                if (no_AD_rst = '1') then
                    no_AD_reg   <= '0';
                elsif (no_AD_set = '1') then
                    no_AD_reg   <= '1';
                end if;
                
                if (first_M_rst = '1') then
                    first_M_reg <= '0';
                elsif (first_M_set = '1') then
                    first_M_reg <= '1';
                end if;
                
                if (last_M_rst = '1') then
                    last_M_reg  <= '0';
                elsif (last_M_set = '1') then
                    last_M_reg  <= '1';
                end if;

                if (no_M_rst = '1') then
                    no_M_reg   <= '0';
                elsif (no_M_set = '1') then
                    no_M_reg   <= '1';
                end if;
                
                if (bdo_valid_rst = '1') then
                    bdo_valid   <= '0';
                elsif (bdo_valid_set = '1') then
                    bdo_valid   <= '1';
                end if;
                 
                if (end_of_block_rst = '1') then
                    end_of_block   <= '0';
                elsif (end_of_block_set = '1') then
                    end_of_block   <= '1';
                elsif (end_of_block_M = '1') then
                    end_of_block   <= last_M_reg;
                end if;
                
            end if;
        end if;
    end process;
    
    Controller: process(state, key, key_valid, key_update, bdi, bdi_valid, bdi_eot, bdi_eoi, bdi_type,
                        ctr_words, ctr_bytes, CHAM_done, bdo_ready, msg_auth_ready)
                       
    begin
        init                <= '0';
        next_state          <= idle;
        key_ready           <= '0';
        bdi_ready           <= '0';
        ctr_words_rst       <= '0';
        ctr_words_inc       <= '0';
        ctr_bytes_rst       <= '0';
        ctr_bytes_inc       <= '0';
        ctr_bytes_dec       <= '0';
        bdoReg_rst          <= '0';
        bdoReg_en           <= '0';
        bdoReg_in           <= (others => '0');
        KeyReg128_rst       <= '0';
        KeyReg128_en        <= '0';
        KeyReg128_in        <= (others => '0');
        iDataReg_rst        <= '0';
        iDataReg_en         <= '0';
        iDataReg_in         <= (others => '0');
        oDataReg_rst        <= '0';
        oDataReg_en         <= '0';
        oDataReg_in         <= (others => '0');
        ZstateReg_rst       <= '0';
        ZstateReg_en        <= '0';
        ZstateReg_in        <= (others => '0');
        YstateReg_rst       <= '0';
        YstateReg_en        <= '0';
        YstateReg_in        <= (others => '0');
        ValidBytesReg_rst   <= '0';
        ValidBytesReg_en    <= '0';
        bdoTypeReg_rst      <= '0';
        bdoTypeReg_en       <= '0';
        bdoTypeReg_in       <= (others => '0');
        bdoValidBReg_rst    <= '0';
        bdoValidBReg_en     <= '0';
        bdoValidBReg_in     <= (others => '0');
        decrypt_rst         <= '0';
        decrypt_set         <= '0';
        first_AD_rst        <= '0';
        first_AD_set        <= '0';
        last_AD_rst         <= '0';
        last_AD_set         <= '0';
        no_AD_rst           <= '0';
        no_AD_set           <= '0';
        first_M_rst         <= '0';
        first_M_set         <= '0';
        last_M_rst          <= '0';
        last_M_set          <= '0';
        no_M_rst            <= '0';
        no_M_set            <= '0';
        bdo_valid_rst       <= '1'; -- The bdo_valid should be always zero, unless the ciphercore wants to put data on bdo
        bdo_valid_set       <= '0';
        end_of_block_rst    <= '0';
        end_of_block_set    <= '0';
        end_of_block_M      <= '0'; -- It is used for output data, based on the input data
        --decrypt_out         <= '0';
        msg_auth            <= '0';
        msg_auth_valid      <= '0';      
        CHAM_start          <= '0';
        
        case state is
            when idle =>
                ctr_words_rst   <= '1';
                ctr_bytes_rst   <= '1';
                bdoReg_rst      <= '1';
                iDataReg_rst    <= '1';
                oDataReg_rst    <= '1';
                ZstateReg_rst   <= '1';
                YstateReg_rst   <= '1';
                decrypt_rst     <= '1';
                first_AD_rst    <= '1';
                last_AD_rst     <= '1';
                no_AD_rst       <= '1';
                first_M_rst     <= '1';
                last_M_rst      <= '1';
                no_M_rst        <= '1';
                end_of_block_rst<= '1';
                bdoValidBReg_rst<= '1';
                next_state      <= wait_key;
                
            when wait_key =>
                if (key_valid = '1' and key_update = '1') then
                    KeyReg128_rst   <= '1'; -- No need to keep the previous key
                    next_state      <= load_key;
                elsif (bdi_valid = '1') then
                    next_state      <= wait_Npub;
                else
                    next_state      <= wait_key;
                end if;
                
            when load_key =>
                key_ready       <= '1';
                KeyReg128_en    <= '1';
                KeyReg128_in    <= secret_key_reg(95 downto 0) & key(7 downto 0) & key(15 downto 8) & key(23 downto 16) & key(31 downto 24);
                ctr_words_inc   <= '1';
                if (ctr_words = 3) then
                    ctr_words_rst   <= '1';
                    next_state      <= wait_Npub;
                else
                    next_state      <= load_key;
                end if;
                
            when wait_Npub =>
                if (bdi_valid = '1' and bdi_type = HDR_NPUB) then
                    next_state  <= load_Npub;
                else
                    next_state  <= wait_Npub;
                end if;
                
            when load_Npub =>
                bdi_ready           <= '1';
                iDataReg_en         <= '1';
                iDataReg_in         <= iDataReg_out(95 downto 0) & bdi(7 downto 0) & bdi(15 downto 8) & bdi(23 downto 16) & bdi(31 downto 24);
                ctr_words_inc       <= '1';
                if (decrypt_in = '1') then -- Decryption
                    decrypt_set     <= '1';
                else                       -- Encryption
                    decrypt_rst     <= '1';
                end if;
                if (bdi_eoi = '1') then -- No AD and no data
                    no_AD_set       <= '1';
                    no_M_set        <= '1';
                end if;
                if (ctr_words = 3) then 
                    ctr_words_rst   <= '1';
                    next_state      <= process_Npub;
                else
                    next_state      <= load_Npub;
                end if;
                
            when process_Npub =>
                init                <= '1';
                CHAM_start          <= '1';
                if (CHAM_done = '1') then
                    CHAM_start          <= '0';
                    ZstateReg_en        <= '1';
                    ZstateReg_in        <= CHAM_out; -- Z0 = E(N, key)
                    YstateReg_en        <= '1';
                    YstateReg_in        <= secret_key_reg(31 downto 0) & secret_key_reg(63 downto 32) & -- Y0 = key
                                           secret_key_reg(95 downto 64) & secret_key_reg(127 downto 96); 
                    if (no_AD_reg = '1' and no_M_reg = '1') then  -- No AD and no data
                        ZstateReg_en    <= '1';
                        ZstateReg_in    <= phi(CHAM_out xor ("10000" & zero123)); -- Z: CHAM key
                        next_state  <= process_tag;
                    elsif (bdi_type = HDR_AD) then
                        first_AD_set    <= '1';
                        next_state      <= wait_AD;
                    elsif ((bdi_type = HDR_MSG) or (bdi_type = HDR_CT)) then -- No AD
                        no_AD_set       <= '1';
                        first_M_set     <= '1';
                        next_state      <= wait_data; 
                    end if;
                else
                    next_state          <= process_Npub;
                end if;
                
            when wait_AD =>
                if (first_AD_reg = '1') then
                    first_AD_rst    <= '1';
                    ZstateReg_en    <= '1';
                    ZstateReg_in    <= ZstateReg_out xor ("00001" & zero123); -- Start of non-empty AD
                end if;
                if (bdi_valid = '1') then                    
                    iDataReg_rst    <= '1';
                    next_state      <= load_AD;
                else
                    next_state  <= wait_AD;
                end if;    
            
            when load_AD =>
                bdi_ready       <= '1';
                ctr_words_inc   <= '1';
                ctr_bytes_inc   <= '1';
                iDataReg_en     <= '1';
                iDataReg_in     <= myMux(iDataReg_out, bdi(7 downto 0) & bdi(15 downto 8) & bdi(23 downto 16) & bdi(31 downto 24), ctr_words);
                if (bdi_eot = '1' and bdi_eoi = '1') then -- No data
                    no_M_set        <= '1';
                end if;
                if (bdi_eot = '1') then -- Last block of AD
                    last_AD_set     <= '1';
                end if;
                if (bdi_eot = '1' or ctr_words = 3) then -- Have gotten a full block of AD
                    ctr_words_rst   <= '1';
                    ZstateReg_en    <= '1';
                    if (bdi_size /= "100") then -- Last partial block
                        ZstateReg_in    <= phi(ZstateReg_out xor ("00010" & zero123)); -- Z: CHAM key
                    else
                        ZstateReg_in    <= phi(ZstateReg_out); -- Z: CHAM key
                    end if;
                    next_state      <= process_AD;
                else
                    next_state      <= load_AD;
                end if;                   
            
            when process_AD =>
                CHAM_start          <= '1';
                if (CHAM_done = '1') then
                    CHAM_start      <= '0';
                    ctr_bytes_rst   <= '1';
                    YstateReg_en        <= '1';
                    YstateReg_in        <= CHAM_out xor pad(iDataReg_out, conv_integer(ctr_bytes)); -- CHAM_out: X, iDataReg_out: AD, Y: CHAM input
                    if (no_M_reg = '1' and last_AD_reg = '1') then -- No data, go to process tag
                        iDataReg_rst<= '1';
                        ZstateReg_en    <= '1';
                        ZstateReg_in    <= phi(ZstateReg_out xor ("10000" & zero123)); -- Z: CHAM key
                        next_state  <= process_tag;
                    elsif (last_AD_reg = '0') then -- Still loading AD
                        next_state  <= wait_AD;
                    elsif (no_M_reg = '0') then -- No AD, start loading data
                        first_M_set <= '1';
                        next_state  <= wait_data;
                    end if;
                else
                    next_state      <= process_AD;
                end if;
                
             when wait_data =>
                if (first_M_reg = '1') then
                    first_M_rst     <= '1';
                    ZstateReg_en    <= '1';
                    ZstateReg_in    <= ZstateReg_out xor (zero120 & "00100000"); -- Start of non-empty M
                end if;
                if (bdi_valid = '1' and (bdi_type = HDR_MSG or bdi_type = HDR_CT)) then
                    iDataReg_rst    <= '1';                
                    next_state      <= load_data;
                else
                    next_state      <= wait_data;
                end if;
                
            when load_data =>
                bdi_ready           <= '1'; 
                ctr_words_inc       <= '1';
                ctr_bytes_inc       <= '1';
                ValidBytesReg_en    <= '1'; -- Register bdi_valid_bytes for outputting CT
                iDataReg_en         <= '1';
                iDataReg_in         <= myMux(iDataReg_out, bdi(7 downto 0) & bdi(15 downto 8) & bdi(23 downto 16) & bdi(31 downto 24), ctr_words);            
                if (bdi_eot = '1') then -- Last block of data
                    last_M_set      <= '1';
                end if;
                if (bdi_eot = '1' or ctr_words = 3) then -- Have gotten a block of M
                    ctr_words_rst   <= '1';
                    ZstateReg_en    <= '1';
                    if (bdi_size /= "100") then -- Last partial block
                        ZstateReg_in    <= phi(ZstateReg_out xor ("01000" & zero123)); -- Z: CHAM key
                    else
                        ZstateReg_in    <= phi(ZstateReg_out); -- Z: CHAM key
                    end if;
                    next_state      <= process_data;
                else
                    next_state      <= load_data;
                end if;
            
            when process_data =>
                CHAM_start          <= '1';
                if (CHAM_done = '1') then
                    CHAM_start      <= '0';
                    YstateReg_en    <= '1';
                    if (decrypt_reg = '0') then -- Encryption 
                        YstateReg_in    <= CHAM_out xor pad(iDataReg_out, conv_integer(ctr_bytes)); -- CHAM_out: X, iDataReg_out: M, Y: CHAM input
                    else                        -- Decryption
                        YstateReg_in    <= CHAM_out xor pad((shuffle(CHAM_out) xor iDataReg_out), conv_integer(ctr_bytes)); -- CHAM_out: X, iDataReg_out: CT, Y: CHAM input
                    end if;
                    oDataReg_en     <= '1';
                    oDataReg_in     <= shuffle(CHAM_out) xor iDataReg_out; -- Enc: CT = shuffle(X) xor M, Dec: M = shuffle(X) xor CT
                    next_state      <= output_data;
                else
                    next_state      <= process_data;
                end if;
                
            when output_data =>
                if (bdo_ready = '1') then
                    bdo_valid_rst       <= '0';
                    bdo_valid_set       <= '1'; -- Set bdo_valid
                    ctr_words_inc       <= '1';
                    bdoTypeReg_en       <= '1';
                    if (decrypt_reg = '0') then -- Encryption
                        bdoTypeReg_in   <= HDR_CT;
                    else                        -- Decryption
                        bdoTypeReg_in   <= HDR_MSG;
                    end if;
                    if (ctr_bytes <= 4) then -- Last 4 bytes of data
                        end_of_block_M   <= '1';
                    else
                        end_of_block_rst <= '1';
                    end if;
                end if;
                if (bdo_ready = '1' and last_M_reg = '1' and ctr_bytes <= 4) then -- Last word of last block of output
                    ctr_words_rst   <= '1';
                    ctr_bytes_rst   <= '1';
                    iDataReg_rst    <= '1';
                    bdoValidBReg_en <= '1';
                    bdoValidBReg_in <= ValidBytesReg_out;
                    bdoReg_en       <= '1';
                    bdoReg_in       <= chop(BE2LE(oDataReg_out((conv_integer(ctr_words)*32 + 31) downto (conv_integer(ctr_words)*32))), ctr_bytes);
                    ZstateReg_en    <= '1';
                    ZstateReg_in    <= phi(ZstateReg_out xor ("10000" & zero123)); -- Z: CHAM key
                    next_state      <= process_tag; -- No more M and no more CT, go to process tag
                elsif (bdo_ready = '1') then
                    bdoValidBReg_en <= '1';
                    bdoValidBReg_in <= "1111"; -- All four bytes of CT/PT are valid
                    bdoReg_en       <= '1';
                    bdoReg_in       <= BE2LE(oDataReg_out((conv_integer(ctr_words)*32 + 31) downto (conv_integer(ctr_words)*32)));
                    ctr_bytes_dec   <= '1';
                    if (ctr_words = 3) then -- 4 words of CT are done
                        ctr_words_rst   <= '1';
                        ctr_bytes_rst   <= '1';
                        next_state      <= wait_data;
                    else
                        next_state  <= output_data;
                    end if;
                else
                    next_state      <= output_data;
                end if;

            when process_tag =>
                CHAM_start          <= '1';
                if (CHAM_done = '1') then
                    CHAM_start      <= '0';
                    oDataReg_en     <= '1';
                    oDataReg_in     <= CHAM_out(7 downto 0)    & CHAM_out(15 downto 8)    & CHAM_out(23 downto 16)   & CHAM_out(31 downto 24) &
                                       CHAM_out(39 downto 32)  & CHAM_out(47 downto 40)   & CHAM_out(55 downto 48)   & CHAM_out(63 downto 56) &
                                       CHAM_out(71 downto 64)  & CHAM_out(79 downto 72)   & CHAM_out(87 downto 80)   & CHAM_out(95 downto 88) &
                                       CHAM_out(103 downto 96) & CHAM_out(111 downto 104) & CHAM_out(119 downto 112) & CHAM_out(127 downto 120);
                    if (decrypt_reg = '0') then -- Encryption
                        next_state  <= output_tag;
                    else                        -- Decryption
                        next_state  <= wait_tag;   
                    end if;
                else
                    next_state      <= process_tag;
                end if;
                
            when output_tag =>
                if (bdo_ready = '1') then
                    bdo_valid_rst        <= '0';
                    bdo_valid_set        <= '1'; -- Set bdo_valid
                    bdoValidBReg_en      <= '1';
                    bdoValidBReg_in      <= "1111"; -- All four bytes of Tag are valid
                    bdoTypeReg_en        <= '1';
                    bdoTypeReg_in        <= HDR_TAG;
                    --decrypt_out          <= decrypt_reg;
                    bdoReg_en            <= '1';
                    bdoReg_in            <= oDataReg_out((127 - conv_integer(ctr_words)*32) downto (96 - conv_integer(ctr_words)*32)); -- Here, oDataReg_out is the output tag
                    ctr_words_inc        <= '1';
                    if (ctr_words = 3) then -- Last 4 bytes of Tag
                        end_of_block_set <= '1';
                    else
                        end_of_block_rst <= '1';
                    end if;
                 end if;
                 if (ctr_words = 3) then
                    ctr_words_rst        <= '1';
                    next_state           <= idle;
                 else
                    next_state           <= output_tag;
                 end if; 
                 
           when wait_tag =>
                if (bdi_valid = '1' and bdi_type = HDR_TAG) then
                    iDataReg_rst    <= '1'; 
                    next_state      <= load_tag;
                else
                    next_state      <= wait_tag;
                end if;
             
            when load_tag =>
                bdi_ready           <= '1';
                iDataReg_en         <= '1';
                iDataReg_in         <= iDataReg_out(95 downto 0) & bdi; -- Here, iDataReg_out is the input tag
                ctr_words_inc       <= '1';
                if (ctr_words = 3) then
                    ctr_words_rst   <= '1';
                    next_state      <= verify_tag;
                else
                    next_state      <= load_tag;
                end if;   
            
            when verify_tag =>
                if (msg_auth_ready = '1' and oDataReg_out = iDataReg_out) then -- Here, oDataReg_out is the output tag and iDataReg_out is the input tag
                    msg_auth_valid  <= '1';
                    msg_auth        <= '1';
                    next_state      <= idle; 
                elsif (msg_auth_ready = '1') then
                    msg_auth_valid  <= '1';
                    msg_auth        <= '0';
                    next_state      <= idle;
                else
                    next_state      <= verify_tag;
                end if;
                
           when others => null;
        end case;
    end process;


end Behavioral;
