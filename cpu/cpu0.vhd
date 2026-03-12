--CPU0.vhd- CPU模块
--2008-03-by yuyanli
library ieee;
use ieee.std_logic_1164.all; 
use ieee.std_logic_unsigned.all;
--use work.unitPack.all;

entity cpu0 is	
	port(	reset		:in     std_logic;                    --复位
	        clk			:in 	std_logic;			          --时钟
			wr			:out 	std_logic;                    --内存读写使能
			c			:out 	std_logic;					  --flag c
			z			:out 	std_logic;					  --flag z
			v			:out 	std_logic;					  --flag v
			s			:out 	std_logic;					  --flag s
			sel			:in		std_logic_vector(1 downto 0); --选择
			reg_sel		:in		std_logic_vector(3 downto 0); --选择寄存器					
			data_bus	:inout	std_logic_vector(15 downto 0);--内存数据线 
			address_bus :out	std_logic_vector(15 downto 0);--内存地址线 
			reg_data	:out	std_logic_vector(15 downto 0) --寄存器值输出
		);
end cpu0;

architecture behave of cpu0 is

	signal  fc,fz,fv,fs,flag_c,flag_z,flag_v,flag_s,en_pc,en_reg,alu_cin,en_0,en_1,en_2,
			en_3,en_4,en_5,en_6,en_7,en_8,en_9,en_a,en_b,en_c,en_d,en_e,en_f,wre	: std_logic;
	signal  sst,sci,rec		: std_logic_vector(1 downto 0);
	signal  tim,alu_func,alu_in_sel		: std_logic_vector(2 downto 0);
	signal  d_reg,s_reg		: std_logic_vector(3 downto 0);
	signal  offset_8		: std_logic_vector(7 downto 0);
	signal	instruction,alu_sr,alu_dr,alu_out,reg_test,offset_16,ar_bus,pc_bus,reg_0,reg_1,reg_2,
			reg_3,reg_4,reg_5,reg_6,reg_7,reg_8,reg_9,reg_a,reg_b,reg_c,reg_d,reg_e,reg_f,reg_inout,
			sr,dr : std_logic_vector(15 downto 0);

	component alu is    
	port (	cin			:in std_logic;
     		alu_a,alu_b :in std_logic_vector(15 downto 0);
     		alu_func	:in std_logic_vector(2 downto 0);
     		alu_out		:out std_logic_vector(15 downto 0);
     		c,z,v,s		:out std_logic          	
		 );
	end component ;
	
	component reg_testa is    
	port (	clk,reset   : in std_logic;
		 	input_a     : in std_logic_vector(2 downto 0);
		 	input_b     : in std_logic_vector(2 downto 0);
		 	input_c     : in std_logic_vector(2 downto 0);
		 	cin         : in std_logic;
		 	rec         : in std_logic_vector(1 downto 0);
		 	pc_en,reg_en: in std_logic;
	     	q           : out std_logic_vector(15 downto 0)          	
		 );
	end component ;
	
	component flag_reg is    
	port (	sst			:in std_logic_vector(1 downto 0);
	     	c,z,v,s,clk,reset  			:in std_logic;
	     	flag_c,flag_z,flag_v,flag_s : out std_logic          	
		 );
	end component ;
	
	component t3 is    
	port (	wr          : in std_logic;
     		alu_out     : in std_logic_vector(15 downto 0);
     		output      : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component timer is    
	port (	clk   	   : in std_logic;
      		reset  	   : in std_logic;
      		ins        : in std_logic_vector(15 downto 0);
      		output     : out std_logic_vector(2 downto 0)         	
		 );
	end component ;
	
	component ir is    
	port (	mem_data   : in std_logic_vector(15 downto 0);
	     	rec		   : in std_logic_vector(1 downto 0);
	     	clk,reset  : in std_logic;
	     	q		   : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component controller is    
	port (	timer	   : in std_logic_vector(2 downto 0);
     		instruction: in std_logic_vector(15 downto 0);
     		c,z,v,s	   : in std_logic;
     		dest_reg,sour_reg: out std_logic_vector(3 downto 0);
     		offset	   : out std_logic_vector(7 downto 0);
     		sst,sci,rec: out std_logic_vector(1 downto 0);
     		alu_func,alu_in_sel: out std_logic_vector(2 downto 0);
    		en_reg,en_pc,wr: out std_logic         	
		 );
	end component ;
	
	component ar is    
	port (	alu_out	   : in std_logic_vector(15 downto 0);
	     	pc		   : in std_logic_vector(15 downto 0);
	     	rec		   : in std_logic_vector(1 downto 0);
	     	clk,reset  : in std_logic;
	     	q		   : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component pc is    
	port (	alu_out	   : in std_logic_vector(15 downto 0);
	     	en		   : in std_logic;
	     	clk,reset  : in std_logic;
	     	q		   : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component reg is    
	port (	d		   : in std_logic_vector(15 downto 0);
	     	clk,reset,en: in std_logic;
	     	q		   : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component reg_mux is    
	port (	reg_0,reg_1,reg_2,reg_3,reg_4,reg_5,reg_6,reg_7,
			reg_8,reg_9,reg_a,reg_b,reg_c,reg_d,reg_e,reg_f	 : in std_logic_vector(15 downto 0);
	     	dest_reg,sour_reg,reg_sel	: in std_logic_vector(3 downto 0);
		 	en	: in std_logic;
		 	en_0,en_1,en_2,en_3,en_4,en_5,en_6,en_7,en_8,en_9,
			en_a,en_b,en_c,en_d,en_e,en_f	: out std_logic;
	     	dr,sr,reg_out	: out std_logic_vector(15 downto 0)
	     );
	end component ;
	
	component bus_mux is    
	port (	alu_in_sel 			: in std_logic_vector(2 downto 0);
	     	data,pc,offset,sr,dr: in std_logic_vector(15 downto 0);
	     	alu_sr,alu_dr       : out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component t1 is    
	port (	flag_c	: in std_logic;
	     	sci		: in std_logic_vector(1 downto 0);
	     	alu_cin	: out std_logic         	
		 );
	end component ;
	
	component t2 is    
	port (	offset_8:in std_logic_vector(7 downto 0);
     		offset_16:out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	
	component reg_out is    
	port (	ir,pc,reg_in		: in std_logic_vector(15 downto 0);
         	offset,alu_a,alu_b	: in std_logic_vector(15 downto 0);
         	alu_out,reg_testa	: in std_logic_vector(15 downto 0);
         	reg_sel				: in std_logic_vector(3 downto 0);
         	sel					: in std_logic_vector(1 downto 0);
         	reg_data			: out std_logic_vector(15 downto 0)         	
		 );
	end component ;
	  
begin  
f1:	controller port map (	timer => tim,	   
     						instruction => instruction,
     						c => flag_c,
							z => flag_z,
							v => flag_v,
							s => flag_s,   
     						dest_reg => d_reg,
							sour_reg => s_reg,
     						offset => offset_8,	   
     						sst => sst,
							sci => sci,
							rec => rec,  
     						alu_func => alu_func,
							alu_in_sel => alu_in_sel,  
    						en_reg => en_reg,
							en_pc => en_pc,
							wr => wre
						);

	process(wre,flag_c,flag_z,flag_v,flag_s)
		begin
			wr <= wre;
			c <= flag_c;
			z <= flag_z;
			v <= flag_v;
			s <= flag_s;
	end process;
			
f2:	alu port map (	cin => alu_cin,
     				alu_a => alu_sr,
					alu_b => alu_dr,
     				alu_func => alu_func,
     				alu_out => alu_out,
     				c => fc,
					z => fz,
					v => fv,
					s => fs         	
		 		 );
		
f3:	flag_reg port map (	sst => sst,
	     				c => fc,
						z => fz,
						v => fv,
						s => fs,
						clk => clk,
						reset => reset,
	     				flag_c => flag_c,
						flag_z => flag_z,
						flag_v => flag_v,
						flag_s => flag_s         	
		 			  );
	
f4:	timer port map (	clk => clk,
      					reset => reset,
      					ins => data_bus,
      					output => tim         	
		 		   );
	
f5:	reg_testa port map (	clk => clk,
							reset => reset,
		 					input_a => tim,
		 					input_b => alu_func,
		 					input_c => alu_in_sel,
		 					cin => alu_cin,
		 					rec => rec,
		 					pc_en => en_pc,
							reg_en => en_reg,
	     					q => reg_test         	
					   );
	
f6:	ir port map (	mem_data => data_bus, 
	     			rec	=> rec,
	     			clk => clk,
					reset => reset,
	     			q => instruction        	
		 		);
		
f7:	t1 port map (	flag_c => flag_c,
	     			sci => sci,
	     			alu_cin => alu_cin        	
		 		);
		
f8:	t2 port map (	offset_8 => offset_8,
     				offset_16 => offset_16      	
		 		);
		
f9:	t3 port map (	wr => wre,
     				alu_out => alu_out,
     				output => data_bus         	
		 		);
	
f10:ar port map (	alu_out => alu_out,
	     			pc => pc_bus,
	     			rec => rec,
	     			clk => clk,
					reset => reset,
	     			q => address_bus        	
		 		);
	
f11:pc port map (	alu_out => alu_out,
	     			en => en_pc,
	     			clk => clk,
					reset => reset,
	     			q => pc_bus        	
		 		);
	
f12:reg_out port map (	ir => instruction,
						pc => pc_bus,
						reg_in => reg_inout,
         				offset => offset_16,
						alu_a => alu_sr,
						alu_b => alu_dr,
         				alu_out => alu_out,
						reg_testa => reg_test,
         				reg_sel	=> reg_sel,
         				sel	=> sel,
         				reg_data => reg_data        	
		 			 );
		
r0: reg port map (	d => alu_out,  --reg files
	     			clk => clk,
					reset => reset,
					en => en_0,
	     			q => reg_0        	
		 		 );
r1:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_1,
	     			q => reg_1        	
		 		 );
	
r2:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_2,
	     			q => reg_2        	
		 		 );
	
r3:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_3,
	     			q => reg_3        	
		 		 );
	
r4:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_4,
	     			q => reg_4        	
		 		 );
	
r5:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_5,
	     			q => reg_5        	
		 		 );
	
r6:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_6,
	     			q => reg_6        	
		 		 );
	
r7:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_7,
	     			q => reg_7        	
		 		 );
	
r8:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_8,
	     			q => reg_8        	
		 		 );
r9:	reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_9,
	     			q => reg_9        	
		 		 );
	
r10:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_a,
	     			q => reg_a        	
		 		 );
	
r11:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_b,
	     			q => reg_b        	
		 		 );
	
r12:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_c,
	     			q => reg_c        	
		 		 );
	
r13:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_d,
	     			q => reg_d        	
		 		 );
	
r14:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_e,
	     			q => reg_e        	
		 		 );
	
r15:reg port map (	d => alu_out,
	     			clk => clk,
					reset => reset,
					en => en_f,
	     			q => reg_f        	
		 		 );
								
rm:	reg_mux port map (	reg_0 => reg_0,
	     				reg_1 => reg_1,
		 				reg_2 => reg_2,
		 				reg_3 => reg_3,
		 				reg_4 => reg_4,
		 				reg_5 => reg_5,
		 				reg_6 => reg_6,
		 				reg_7 => reg_7,
		 				reg_8 => reg_8,
		 				reg_9 => reg_9,
		 				reg_a => reg_a,
		 				reg_b => reg_b,
		 				reg_c => reg_c,
   						reg_d => reg_d,
		 				reg_e => reg_e,
		 				reg_f => reg_f,
		 				dest_reg => d_reg,
		 				sour_reg => s_reg,
		 				reg_sel => reg_sel,
		 				en => en_reg,
		 				en_0 => en_0,
	     				en_1 => en_1,
		 				en_2 => en_2,
		 				en_3 => en_3,
		 				en_4 => en_4,
		 				en_5 => en_5,
		 				en_6 => en_6,
		 				en_7 => en_7,
		 				en_8 => en_8,
		 				en_9 => en_9,
		 				en_a => en_a,
		 				en_b => en_b,
		 				en_c => en_c,
   		 				en_d => en_d,
		 				en_e => en_e,
		 				en_f => en_f,
		 				dr => dr,
	     				sr => sr,
	     				reg_out => reg_inout        	
		 			 );
		
bm:	bus_mux port map (	alu_in_sel => alu_in_sel,
	     				data => data_bus,
						pc => pc_bus,
						offset => offset_16,
						sr => sr,
						dr => dr,
	     				alu_sr => alu_sr,
						alu_dr => alu_dr       	
		 			 );
								
end architecture ;