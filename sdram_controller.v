/*
SDRAM controller for IS42S16320F-7TL (Terasic DE10-Lite)
Estimated clock frequency 100 MHz

This version of controller works with read/write burst length = 1.
Controller can handle one read/write operation at a time.
*/

module sdram_controller #
(
    parameter ID_WIDTH = 8,
    parameter ADDR_WIDTH = 25,
    parameter DATA_WIDTH = 16,
    parameter TRCD_CYCLES = 2,
    parameter TRP_CYCLES = 2,
    parameter CAS_LATENCY = 2
)
(
    input clk,
    input reset,

    /* SDRAM interface */
    output reg  [12:0]  sdram_addr,
    output reg  [1:0]   sdram_ba,
    inout  	    [15:0]  sdram_dq,
    output              sdram_clk,
    output              sdram_cke,
    output              sdram_cs_n,
    output              sdram_ras_n,
    output              sdram_cas_n,
    output              sdram_we_n,
    output              sdram_dqml,
    output              sdram_dqmh,

    /* AXI slave interface */
    input [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input                       s_axi_awvalid,
    output                      s_axi_awready,
    
    input [DATA_WIDTH-1:0]      s_axi_wdata,
    input                       s_axi_wvalid,
    output                      s_axi_wready,
    
    input [ADDR_WIDTH-1:0]      s_axi_araddr,
    input                       s_axi_arvalid,
    output                      s_axi_arready,

    output reg [DATA_WIDTH-1:0] s_axi_rdata,
    output                      s_axi_rvalid,
    input                       s_axi_rready

);

assign sdram_cke = 1'b1;
assign sdram_cs_n = 1'b0;

reg [ADDR_WIDTH-1:0] s_axi_addr_reg;
reg [DATA_WIDTH-1:0] s_axi_data_reg;

reg [1:0] read_write_request = 2'b00;   // LSB: 1 - read/write request, 0 - no request
                                        // MSB: 1 - read request, 0 - write request

assign sdram_dq = (read_write_request == 2'b01) ? s_axi_data_reg : 16'bz;

/* {sdram_ras_n, sdram_cas_n, sdram_we_n} */
localparam [2:0] sdram_cmd_nop          = 3'b111; 
localparam [2:0] sdram_cmd_bst          = 3'b110;
localparam [2:0] sdram_cmd_read         = 3'b101;
localparam [2:0] sdram_cmd_write        = 3'b100;
localparam [2:0] sdram_cmd_act          = 3'b011;
localparam [2:0] sdram_cmd_precharge    = 3'b010;
localparam [2:0] sdram_cmd_refresh      = 3'b001;
localparam [2:0] sdram_cmd_mrs          = 3'b000;

reg [2:0] sdram_cmd;
assign {sdram_ras_n, sdram_cas_n, sdram_we_n} = sdram_cmd;

/* {sdram_dqml, sdram_dqmh} */
reg [1:0] sdram_dqm = 2'b11; // output disable by default
assign {sdram_dqml, sdram_dqmh} = sdram_dqm;

reg [4:0] state, next_state;

localparam [4:0] idle_state     = 5'h0; // No operation (NOP)
localparam [4:0] bst_state      = 5'h1; // Burst stop (BST)
localparam [4:0] read_state     = 5'h2; 
localparam [4:0] reada_state    = 5'h3; // Read with auto precharge
localparam [4:0] write_state    = 5'h4;
localparam [4:0] writea_state   = 5'h5; // Write with auto precharge
localparam [4:0] act_state      = 5'h6; // Bank activate (ACT)
localparam [4:0] pre_state      = 5'h7; // Precharge select bank (PRE)
localparam [4:0] pall_state     = 5'h8; // Precharge all banks (PALL)
localparam [4:0] ref_state      = 5'h9; // CBR Auto-Refresh (REF)
localparam [4:0] self_state     = 5'hA; // Self-Refresh (SELF)
localparam [4:0] mrs_state      = 5'hB; // Mode register set (MRS)

localparam [4:0] trcd_state     = 5'hC; // Active Command To Read / Write Command Delay
localparam [4:0] trp_state      = 5'hD; // Command Period (PRE to ACT)

localparam [4:0] init_power_up_state	= 5'hE;
localparam [4:0] init_pre_state			= 5'hF;
localparam [4:0] init_ref_state			= 5'h10;

reg [1:0] trcd_clk_counter = 0;
reg [1:0] trp_clk_counter = 0;
reg [CAS_LATENCY:0] cas_shift_register = 0;

/* Mode Register Definition */
localparam [2:0] burst_length = 3'b000;     // [A2:A0] burst length = 1
localparam burst_type = 1'b0;               // [A3] burst type is sequential
localparam [2:0]latency_mode = 3'b010;      // [A6:A4] CAS latency = 2
localparam [1:0] operating_mode = 2'b00;    // [A8:A7] operating mode is standart operation
localparam write_burst_mode = 1'b0;         // [A9] write burst mode is programmed burst mode
localparam [1:0] reserved_mode = 2'b00;     // [A12:A10] reserved, should be = 0
reg [12:0] mode_register = {reserved_mode, write_burst_mode, operating_mode, latency_mode, burst_type, burst_length};

/* AXI interface logic */

always @(posedge clk) 
begin
    if (s_axi_arvalid & s_axi_rready)
    begin
        read_write_request <= 2'b11;
        s_axi_addr_reg <= s_axi_araddr;
    end
    else if (s_axi_awvalid & s_axi_wready & s_axi_wvalid & s_axi_wready)
    begin
        read_write_request <= 2'b01;
        s_axi_addr_reg <= s_axi_awaddr;
        s_axi_data_reg <= s_axi_wdata;
    end
    
    if (state == (read_state | write_state))
        read_write_request <= 2'b00;
end

assign s_axi_arready = (state == idle_state);
assign s_axi_awready = (state == idle_state);
assign s_axi_wready = (state == idle_state);

/* CAS Latency */

always @(posedge clk)
begin
    cas_shift_register <= {cas_shift_register[CAS_LATENCY:1], state == read_state};
end

assign s_axi_rvalid = cas_shift_register[CAS_LATENCY];

always @(posedge clk)
begin
	if (read_write_request == 2'b11)
	begin
		s_axi_rdata <= sdram_dq;
	end
end

/* Initialization */

reg [15:0] power_up_counter = 0;
reg [1:0] trp_counter = 0;
reg [3:0] trc_counter = 0;
reg [4:0] refresh_counter = 0;
reg [1:0] tmrd_counter = 0;

//reg [3:0] init_refresh_cycles = 0;
//reg [1:0] pre_to_ref_cycles = 0;
//reg ref_to_ref_flag = 0;
//reg [1:0] mrs_to_command_cycles = 0;
//reg mrs_to_command_flag = 0;

/* Finite-state machine */

always @(posedge clk or posedge reset) 
begin
    if (reset)
        state <= init_power_up_state;
    else
	 begin
		  state <= next_state;
	 end
end

always @(*)
begin
    case (state)
        idle_state:
        begin
            sdram_cmd = sdram_cmd_nop;
            next_state = read_write_request[0] ? act_state : idle_state;
        end
        act_state:
        begin
            sdram_cmd = sdram_cmd_act;
            sdram_dqm = 2'b00; // data write / output enable
            sdram_ba = s_axi_addr_reg[24:23]; // bank address
            sdram_addr[12:0] = s_axi_addr_reg[22:10]; // row address
            next_state = trcd_state;
        end
        trcd_state:
        begin
            sdram_cmd = sdram_cmd_nop;
            if (trcd_clk_counter == TRCD_CYCLES-2)
            begin
                trcd_clk_counter = 0;
                next_state = read_write_request[1] ? read_state : write_state;
            end
            else
            begin
                trcd_clk_counter = trcd_clk_counter + 1'b1;
                next_state = trcd_state;
            end
        end
        read_state:
        begin
            sdram_cmd = sdram_cmd_read;
            sdram_addr[10] = 1'b0; // disable auto precharge
            sdram_ba = s_axi_addr_reg[24:23]; // bank address
            next_state = pre_state;
        end
        write_state:
        begin
            sdram_cmd = sdram_cmd_write;
            sdram_addr[10] = 1'b0; // disable auto precharge
            sdram_ba = s_axi_addr_reg[24:23]; // bank address
            // sdram_dq = s_axi_data_reg;
            next_state = pre_state;
        end
        pre_state:
        begin
            sdram_cmd = sdram_cmd_precharge;
            sdram_addr[10] = 1'b0; // precharge select bank
            sdram_ba = s_axi_addr_reg[24:23]; // bank address
            next_state = trp_state;
        end
        trp_state:
        begin
            sdram_cmd = sdram_cmd_nop;
            if (trp_clk_counter == TRP_CYCLES-2)
            begin
                trp_clk_counter = 0;
                next_state = idle_state;
            end
            else
            begin
                trp_clk_counter = trp_clk_counter + 1'b1;
                next_state = trp_state;
            end
        end
        mrs_state:
        begin
				sdram_cmd = (tmrd_counter == 0) ? sdram_cmd_mrs : sdram_cmd_nop;
				sdram_addr = mode_register;
				sdram_ba = 2'b00;
				if(tmrd_counter == 2-1)
					next_state = idle_state;
//            if (!mrs_to_command_flag)
//            begin
//                sdram_cmd = sdram_cmd_mrs;
//                sdram_addr = mode_register;
//                sdram_ba = 2'b00;
//                mrs_to_command_flag = 1;
//                next_state = mrs_state;             
//            end
//            else
//            begin
//                if (mrs_to_command_cycles == 2-1)
//                begin
//                    mrs_to_command_flag = 0;
//                    next_state = idle_state;
//                end
//                else
//                begin
//                    mrs_to_command_cycles = mrs_to_command_cycles + 1'b1;
//                    next_state = mrs_state;
//                end
//            end
        end
        init_power_up_state:
        begin
            sdram_cmd = sdram_cmd_nop;
				next_state = (power_up_counter == 'd20000 - 'b1) ? init_pre_state : init_power_up_state;
//            if (power_up_counter == 'd20000)
//                next_state = init_pre_state;
//				else
//					 next_state = init_power_up_state;
        end
        init_pre_state:
        begin
            sdram_cmd = (trp_counter == 0) ? sdram_cmd_precharge : sdram_cmd_nop;
            sdram_addr[10] = 1'b1; // precharge all banks
				next_state = (trp_counter == 3-1) ? init_ref_state : init_pre_state;
//				if (trp_counter == 3-1)
//					next_state = init_ref_state;
        end
        init_ref_state:
        begin
				sdram_cmd = (trc_counter == 0) ? sdram_cmd_refresh : sdram_cmd_nop;
				next_state = (trc_counter == 10-1 && refresh_counter == 8-1) ? mrs_state : init_ref_state;
//				if (trc_counter == 10-1 && refresh_counter == 8-1)
//					next_state = mrs_state;
					
//            if (!ref_to_ref_flag)
//            begin
//                sdram_cmd = sdram_cmd_refresh;
//                ref_to_ref_flag = 1;
//                next_state = init_ref_state;
//            end
//            else
//            begin
//                sdram_cmd = sdram_cmd_nop;
//                if (trc_counter == 10-1)
//                begin
//                    ref_to_ref_flag = 0;
//                    trc_counter = 0;
//                    next_state = (init_refresh_cycles == 8-1) ? mrs_state : init_ref_state;
//                    if (init_refresh_cycles == 8-1) init_refresh_cycles = 0;
//                end
//                else
//                begin
//                    init_refresh_cycles = init_refresh_cycles + 1'b1;
//                    trc_counter = trc_counter + 1'b1;
//                    next_state = init_ref_state;
//                end
//            end
        end
        default:
        begin
            sdram_cmd = sdram_cmd_nop;
            next_state = idle_state;
        end 
    endcase
end

always @(posedge clk)
begin
	if (reset)
	begin
		power_up_counter <= 0;
		trp_counter <= 0;
		trc_counter <= 0;
		refresh_counter <= 0;
		tmrd_counter <= 0;
	end
	else
	begin
		power_up_counter <= (state == init_power_up_state) ? power_up_counter + 'b1 : 0;
		trp_counter <= (state == init_pre_state) ? trp_counter + 'b1 : 0;
		trc_counter <= (state == init_ref_state && trc_counter != 10-1) ? trc_counter + 'b1 : 0;
		refresh_counter <= (state == init_ref_state && trc_counter == 10-1 && refresh_counter != 8-1) ? refresh_counter + 1 : ((refresh_counter == 8-1 && trc_counter == 10-1) ? 0 : refresh_counter);
		tmrd_counter <= (state == mrs_state) ? tmrd_counter + 1 : 0;	
	end
end

endmodule