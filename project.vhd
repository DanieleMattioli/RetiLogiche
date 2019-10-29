library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;



entity header_reader is
    Port ( 
           i_clk : in STD_LOGIC;
           i_rst : in STD_LOGIC;
           i_start : in STD_LOGIC;
           i_data : in STD_LOGIC_VECTOR(7 downto 0);
           end_computation : in STD_LOGIC; --segnale di reset implicito 
           raws : out unsigned (7 downto 0); --numero di righe
           columns : out unsigned (7 downto 0); --numero di colonne
           threshold : out unsigned (7 downto 0); --soglia
           read_matrix : out STD_LOGIC; --segnale che indica a matrix_reader, blocco successivo, di attivarsi
           o_en : out STD_LOGIC; 
           o_address_h : out STD_LOGIC_VECTOR (15 downto 0);
           control_1 : out std_logic  --segnale di controllo per il mux
           );
end header_reader;

architecture Behavioral of header_reader is
    signal read_header : std_logic := '0'; --segnale che rimane basso finchè start è a 0. Viene alzato quando si alza start e rimane alto fino al termine dell'esecuzione di questo blocco: serve a condizionare l'esecuzione di header_reader
    signal address: unsigned (15 downto 0) := (1 => '1', others => '0'); --segnale di supporto per incrementare o_address_h (parte da 2)

        begin
            process(i_clk, i_rst, end_computation)
            begin 
                if  i_rst = '1' or end_computation = '1' then
                        read_matrix <= '0';
                        read_header <= '0';
                        address <= (1 => '1', others => '0');
                        o_address_h <= (1 => '1', others => '0');
                        o_en <= '0';
                        control_1 <= '0';
                        
                elsif i_clk' event and i_clk = '1' then                    
                    if i_start = '1' then
                             read_header <= '1';
                             o_en <= '1'; 
                                                      
                    elsif read_header = '1' then  
                             address <= address + 1;
                             o_address_h <= std_logic_vector(address + 1);                                                                              
                             if address = 3 then   
                                columns <= unsigned(i_data);                                                                                                                   
                             elsif address = 4 then                                   
                                raws <= unsigned(i_data);                                 
                             elsif address >= 5 then
                                threshold <=  unsigned(i_data);
                                read_header <= '0'; --serve a interrompere l'esecuzione di header_reader: arrivati a questo punto ha terminato il suo compito.
                                read_matrix <= '1'; --indico a matrix_reader, blocco successivo, di attivarsi
                                control_1 <= '1'; --così il mux selezionerà l'indirizzo fornitogli dal blocco matrix_reader     
                             end if;
                    end if;                     
                end if;
           end process;         

end Behavioral;



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;



entity matrix_reader is
    Port ( 
           i_clk : in STD_LOGIC;
           i_rst : in STD_LOGIC;
           read_matrix : in STD_LOGIC; -- segnale che serve a condizionare l'esecuzione di matrix_reader. Viene alzato da header_reader
           raws : in unsigned(7 downto 0); -- numero di righe
           columns : in unsigned(7 downto 0); -- numero di colonne 
           threshold : in unsigned(7 downto 0); -- soglia
           i_data : in STD_LOGIC_VECTOR (7 downto 0);
           end_computation : in std_logic ; --segnale di reset implicito
           calc_ready : out STD_LOGIC; --segnale che indica a subtractor, blocco successivo, di attivarsi.
           first_occurency : out STD_LOGIC; --segnale che indica a subtractor, blocco successivo, se è stata trovata almeno una occorrenza valida (valore sopra la threshold) nella matrice
           first_raw : out unsigned(7 downto 0); --indice della prima riga
           first_column : out unsigned(7 downto 0); --indice della prima colonna
           last_raw : out unsigned(7 downto 0); --indice dell'ulitima riga
           last_column : out unsigned(7 downto 0); --indice dell'ultima colonna
           control_2 : out std_logic; --segnale di controllo per il mux
           o_address_m : out std_logic_vector(15 downto 0));
end matrix_reader;

architecture Behavioral of matrix_reader is
signal matrix_ended : std_logic := '0'; --segnale interno che indica a matrix_reader di terminare la sua esecuzione una volta letta tutta la matrice
signal r_index : unsigned(7 downto 0) := (others => '0') ;  --indice di riga
signal c_index : unsigned(7 downto 0) := (others => '0') ;  --indice di colonna
signal last_raw_int, first_raw_int, first_column_int, last_column_int : unsigned(7 downto 0) := (others => '0') ; --indici della prima e ultima  riga e colonna interni: servono per l'esecuzione dell'algoritmo
signal address :  unsigned (15 downto 0) := (1=> '1', 2 => '1', others => '0'); --segnale di supporto per incrementare o_address_h (parte da 6) 
signal first_occ : std_logic := '0'; --segnale che indica se è stata trovata almeno un'occorrenza valida
signal final_update : std_logic := '0'; --segnale che permette di aggiornare correttamente gli indici nel caso l'ultima cella della matrice sia sopra la threshold
begin
process(i_clk,i_rst, end_computation)
begin
if  i_rst = '1' or end_computation= '1'  then 
    matrix_ended <= '0'; 
    r_index <= (others => '0' ); 
    c_index <= (others => '0'); 
    address <= (1=> '1', 2 => '1', others => '0');  
    first_occ <= '0';  
    final_update <= '0';  
    first_occurency <= '0';
    calc_ready <= '0'; 
    o_address_m <= (1=> '1', 2 => '1', others => '0');
    control_2 <= '0'; 

elsif i_clk'event and i_clk = '1' then
    if read_matrix = '1' and matrix_ended = '0' then
        address <= address +1; 
        o_address_m <= std_logic_vector(address + 1);
        if (raws = 0 or columns = 0) then --caso particolare: l'area sarà 0, la matrice ha zero righe o zero colonne
            calc_ready <= '1';  --indico a subtractor, blocco successivo, di attivarsi
            matrix_ended  <= '1'; --serve a interrompere l'esecuzione di matrix_reader: arrivati a questo punto ha terminato il suo compito. 
            control_2 <= '1'; --così il mux selezionerà l'indirizzo fornitogli dal blocco mem_writer
            
        else
            if unsigned(i_data) >= threshold then
               if first_occ = '0' then
                   --se è la prima occorrenza utile inizializzo allo stesso modo tutti gli indici di prima e ultima colonna e riga
                       first_raw_int <= r_index;
                       last_raw_int<= r_index;
                       first_column_int<= c_index;
                       last_column_int<= c_index;
                       first_occ<= '1';
                       first_occurency <= '1';
                               
                else   
                       last_raw_int <= r_index; --aggiorniamo a priori last_raw_int
                       if c_index < first_column_int then   
                           first_column_int <= c_index;
                       elsif c_index > last_column_int then
                           last_column_int <= c_index;
                       end if;
                end if;
             end if;
            if c_index = columns-1 then
                    if r_index = raws-1 then --se entro qua sono arrivato all'ultima cella della matrice
                        final_update <= '1'; --devo aspettare un ciclo per aggiornare correttamente gli estremi (altrimenti avrei problemi quando l'ultimo elemento della matrice è sopra la soglia ed è quindi determinante per il calcolo degli estremi)
                        matrix_ended <= '1';  --serve a interrompere l'esecuzione di matrix_reader: arrivati a questo punto ha terminato il suo compito.    
                    else
                       c_index <= (others => '0') ;
                       r_index <= r_index+1; --aggiorno r_index solo in questo caso perchè sono arrivato in fondo a una riga se c_index = columns - 1
                    end if;
            else 
                    c_index <= c_index+1;
            end if;
        end if;
    
    elsif final_update = '1' then
                            first_raw <= first_raw_int;
                            last_raw <= last_raw_int;
                            first_column <= first_column_int;
                            last_column <= last_column_int;
                            calc_ready <= '1'; --indico a subtractor, blocco successivo, di attivarsi
                            control_2 <= '1'; --così il mux selezionerà l'indirizzo fornitogli dal blocco mem_writer     
                            final_update <= '0'; 

    end if;                   
end if;
end process;


end Behavioral;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;



entity subtractor is
    Port ( 
           calc_ready : in STD_LOGIC; -- segnale che serve a condizionare l'esecuzione di subtractor. Viene alzato da matrix_reader
           first_raw : in  unsigned(7 downto 0);
           first_column : in  unsigned(7 downto 0);
           last_raw : in  unsigned(7 downto 0);
           last_column : in  unsigned(7 downto 0);
           i_rst: in std_logic;
           end_computation: in std_logic;--segnale di reset implicito
           first_occurency : in std_logic ;  --segnale che indica a subtractor se è stata trovata almeno una occorrenza valida (valore sopra la threshold) nella matrice
           calc_area_ready : out STD_LOGIC;  --segnale che indica a multiplier, blocco successivo, di attivarsi.
           length : out unsigned (7 downto 0); --base
           width : out unsigned (7 downto 0)); --altezza
end subtractor;

architecture Behavioral of subtractor is
signal subtraction_done : std_logic := '0'; --segnale interno che indica a subtractor di terminare la sua esecuzione una volta eseguita la sottrazione

begin
process(calc_ready, i_rst, end_computation) 
begin
    if  i_rst = '1' or end_computation = '1' then 
        calc_area_ready <= '0';
        subtraction_done <= '0';       
    
    elsif calc_ready = '1' and subtraction_done = '0' then
              if first_occurency = '0' then --caso particolare: l'area è 0 perchè ho trovato zero occorrenze utili (oppure la matrice aveva 0 righe o 0 colonne)
                            width <= (others => '0'); 
                            length <= (others => '0');
              else               
                            width <=  last_raw - first_raw +1 ; --devo aggiungere 1 per comprendere entrambi gli estremi
                            length <=  last_column - first_column +1 ;  --devo aggiungere 1 per comprendere entrambi gli estremi
              end if;
        calc_area_ready <= '1';  --indico al multiplier, blocco successivo, di attivarsi
        subtraction_done <= '1'; --serve a interrompere l'esecuzione di subtractor: arrivati a questo punto ha terminato il suo compito.
                      
    end if;
     
end process;

end Behavioral;



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;


entity multiplier is
    Port ( 
           i_rst : in STD_LOGIC; 
           calc_area_ready : in STD_LOGIC; -- segnale che serve a condizionare l'esecuzione di multipler. Viene alzato da subtractor
           length : in UNSIGNED (7 downto 0);
           width : in UNSIGNED (7 downto 0);
           end_computation: in std_logic; --segnale di reset implicito
           area : out UNSIGNED (15 downto 0);
           can_write : out STD_LOGIC  --segnale che indica a mem_writer, blocco successivo, di attivarsi.
           );
end multiplier;

architecture Behavioral of multiplier is
signal multiplication_done : std_logic := '0'; --segnale interno che indica a multiplier di terminare la sua esecuzione una volta eseguita la moltiplicazione
begin
    process (calc_area_ready, i_rst, end_computation)
    begin
        if  i_rst = '1' or end_computation = '1' then
             can_write <= '0';
             multiplication_done <= '0';
        elsif calc_area_ready = '1' and multiplication_done = '0' then 
             area <= length * width;
             multiplication_done <= '1';  --serve a interrompere l'esecuzione di multiplier: arrivati a questo punto ha terminato il suo compito.
             can_write <= '1'; --indico a mem_writer, blocco successivo, di attivarsi
        end if;  
     end process;

end Behavioral;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;



entity mem_writer is
    Port ( 
           area : in unsigned (15 downto 0);
           can_write : in STD_LOGIC; -- segnale che serve a condizionare l'esecuzione di mem_writer. Viene alzato da multiplier
           i_clk : in std_logic;
           i_rst : in std_logic;
           o_address_w : out std_logic_vector(15 downto 0 );
           o_done : out STD_LOGIC;
           o_we : out STD_LOGIC;
           o_data : out std_logic_vector (7 downto 0);
           end_computation: out std_logic --segnale di reset implicito
           );
           
end mem_writer;

architecture Behavioral of mem_writer is
signal writing_done : std_logic := '0'; --segnale interno che indica a scrive_memoria di non scrivere più, ma di gestire o_done e dare il reset implicito
signal first_byte : std_logic := '0'; --segnale che mi indica se è stato già scritto il byte 1 di memoria o meno
signal up_done, low_done : std_logic := '0'; --segnali per gestire o_done: deve rimanere alto per UN SOLO ciclo di clock

begin
    process(i_clk, i_rst)
    begin
        if  i_rst= '1' then 
            o_we <= '0';
            o_address_w <= (0 => '1', others => '0' );
            o_done <= '0';
            o_data  <= ( others => '0');
            writing_done <= '0';
            first_byte <= '0';
            up_done <= '0';
            low_done <= '0';
            end_computation <= '0'; 
        elsif i_clk' event and i_clk = '1' then

            if can_write = '1' and writing_done = '0'  then
                if first_byte = '0' then
                       o_data <= std_logic_vector(area (15 downto 8));
                       o_we <= '1';
                       first_byte <= '1';

                else 
                       o_address_w <= (others => '0');
                       o_data <= std_logic_vector(area (7 downto 0));
                       up_done <= '1';
                       writing_done <= '1'; --serve a interrompere la parte di scrittura: arrivati a questo punto si deve solo dare il reset implicito e gestire o_done
               end if;
            elsif up_done = '1' then --gestisco qua il reset implicito dei segnali di mem_writer (tranne low_done e o_done che vengono abbassati al ciclo successivo)
                o_done <= '1';
                low_done <= '1';-- così abbasserà o_done al ciclo successivo
                o_we <='0';
                up_done <= '0';                    
                end_computation <= '1'; --alzo il segnale di reset implicito
                o_address_w <= (0 => '1', others => '0' );
                o_data  <= ( others => '0');
                writing_done <= '0'; 
                first_byte <= '0';
            elsif low_done = '1' then
                   o_done <= '0';
                   low_done <= '0';
                   end_computation <= '0';
                                      
            end if;
        end if;
                  
end process;
end Behavioral;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;


entity mux is
    Port ( 
          in_address_h : in STD_LOGIC_VECTOR (15 downto 0); -- è l'indirizzo che arriva dal blocco header_reader
          in_address_m : in STD_LOGIC_VECTOR (15 downto 0); -- è l'indirizzo che arriva dal blocco matrix_reader
          in_address_w : in std_logic_vector(15 downto 0); -- è l'indirizzo che arriva dal blocco mem_writer
          control_1 : in STD_LOGIC;  --segnale di controllo che arriva dal blocco header_reader
          control_2 : in STD_LOGIC;  --segnale di controllo che arriva dal blocco matrix_reader
          o_address_f : out STD_LOGIC_VECTOR (15 downto 0)); -- indirizzo selezionato in uscita
end mux;

architecture Dataflow of mux is
    
                    
begin --la combinazione control_1 = '0' and control_2 = '1' non capita mai
o_address_f <=  in_address_h when control_1= '0' and control_2 = '0'  else
                in_address_m when control_1= '1' and control_2 = '0'  else 
                in_address_w ;


end Dataflow;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is   --questo blocco connette tra loro i vari moduli
    port (
        i_clk : in std_logic;
        i_start : in std_logic;
        i_rst : in std_logic;
        i_data : in std_logic_vector(7 downto 0);
        o_address : out std_logic_vector(15 downto 0);
        o_done : out std_logic;
        o_en : out std_logic;
        o_we : out std_logic;
        o_data : out std_logic_vector (7 downto 0)
    );
    
  
end project_reti_logiche;

architecture Structural of project_reti_logiche is 
signal s_read_matrix : std_logic ;
signal s_raws, s_columns , s_threshold, s_length, s_width, s_first_raw, s_first_column, s_last_raw, s_last_column  : unsigned (7 downto 0);
signal s_area : unsigned (15 downto 0);
signal address_tmp1, address_tmp2, address_tmp3 : std_logic_vector (15 downto 0);

signal s_control_1, s_control_2, s_calc_area_ready, s_calc_ready, s_first_occurency, s_can_write, s_end_computation : std_logic;
component header_reader is
          Port ( 
           i_clk : in STD_LOGIC;
           i_rst : in STD_LOGIC;
           i_start : in STD_LOGIC;
           i_data : in STD_LOGIC_VECTOR(7 downto 0);
           end_computation : in STD_LOGIC;
           raws : out unsigned (7 downto 0);
           columns : out unsigned (7 downto 0);
           threshold : out unsigned (7 downto 0);
           read_matrix : out STD_LOGIC;
           o_en : out STD_LOGIC;
           o_address_h : out STD_LOGIC_VECTOR (15 downto 0);
           control_1 : out std_logic  
           );
end component;

component matrix_reader is
        Port ( 
           i_clk : in STD_LOGIC;
           i_rst : in STD_LOGIC;
           read_matrix : in STD_LOGIC;
           raws : in unsigned(7 downto 0);
           columns : in unsigned(7 downto 0);
           threshold : in unsigned(7 downto 0);
           i_data : in STD_LOGIC_VECTOR (7 downto 0);
           end_computation : in std_logic ;            
           calc_ready : out STD_LOGIC;
           first_occurency : out STD_LOGIC;
           first_raw : out unsigned(7 downto 0);
           first_column : out unsigned(7 downto 0);
           last_raw : out unsigned(7 downto 0);
           last_column : out unsigned(7 downto 0);
           control_2 : out std_logic;
           o_address_m : out std_logic_vector(15 downto 0));
end component;


component subtractor is 
        Port ( 
           calc_ready : in STD_LOGIC;
           first_raw : in  unsigned(7 downto 0);
           first_column : in  unsigned(7 downto 0);
           last_raw : in  unsigned(7 downto 0);
           last_column : in  unsigned(7 downto 0);
           i_rst: in std_logic;
           end_computation: in std_logic;
           first_occurency : in std_logic ;
           calc_area_ready : out STD_LOGIC;
           length : out unsigned (7 downto 0);
           width : out unsigned (7 downto 0));
end component;

component multiplier is
        Port ( 
           i_rst : in STD_LOGIC; 
           calc_area_ready : in STD_LOGIC;
           length : in UNSIGNED (7 downto 0);
           width : in UNSIGNED (7 downto 0);
           end_computation: in std_logic;
           area : out UNSIGNED (15 downto 0);
           can_write : out STD_LOGIC
           );
end component;

component mem_writer is 
        Port ( 
           area : in unsigned (15 downto 0);
           can_write : in STD_LOGIC;
           i_clk : in std_logic;
           i_rst : in std_logic;
           o_address_w : out std_logic_vector(15 downto 0 );
           o_done : out STD_LOGIC;
           o_we : out STD_LOGIC;
           o_data : out std_logic_vector (7 downto 0);
           end_computation: out std_logic
           );
           
end component;

component mux is
        Port ( 
          in_address_h : in STD_LOGIC_VECTOR (15 downto 0);
          in_address_m : in STD_LOGIC_VECTOR (15 downto 0);
          in_address_w : in std_logic_vector(15 downto 0);
          control_1 : in STD_LOGIC;
          control_2 : in STD_LOGIC;   
          o_address_f : out STD_LOGIC_VECTOR (15 downto 0));
end component;

begin

    header: header_reader 
       port map (end_computation => s_end_computation, i_clk => i_clk, i_rst => i_rst , i_start => i_start, i_data => i_data, raws=> s_raws, columns => s_columns, threshold =>s_threshold, read_matrix =>s_read_matrix , o_en => o_en, o_address_h => address_tmp1 , control_1=> s_control_1 );
        
    matrice: matrix_reader 
        port map (end_computation => s_end_computation, i_clk => i_clk, i_rst => i_rst, read_matrix => s_read_matrix, raws =>s_raws  , columns=> s_columns, threshold => s_threshold, i_data =>i_data, calc_ready=> s_calc_ready, first_occurency =>s_first_occurency, first_raw =>s_first_raw, first_column => s_first_column, last_raw => s_last_raw, last_column=> s_last_column, o_address_m=> address_tmp2, control_2 => s_control_2);
        
    sottr: subtractor
        port map (end_computation => s_end_computation,i_rst => i_rst, first_raw => s_first_raw, first_column => s_first_column, last_raw => s_last_raw, last_column => s_last_column, first_occurency => s_first_occurency, calc_ready => s_calc_ready, calc_area_ready => s_calc_area_ready, length => s_length, width => s_width);
    molt: multiplier
        port map (end_computation => s_end_computation, i_rst => i_rst, width => s_width, length => s_length, calc_area_ready => s_calc_area_ready, area => s_area, can_write => s_can_write);
    scrive: mem_writer
        port map(end_computation => s_end_computation, i_clk => i_clk, i_rst => i_rst, area => s_area, can_write => s_can_write, o_address_w => address_tmp3, o_done => o_done, o_we => o_we, o_data => o_data);
    multi: mux
           port map(in_address_h => address_tmp1, in_address_m => address_tmp2, in_address_w => address_tmp3 , control_1=> s_control_1, control_2 => s_control_2 , o_address_f => o_address);
end Structural;