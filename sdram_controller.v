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
    output    [12:0]  sdram_addr,
    output    [1:0]   sdram_ba,
    inout reg [15:0]  sdram_dq,
    output            sdram_clk,
    output            sdram_cke,
    output            sdram_cs_n,
    output            sdram_ras_n,
    output            sdram_cas_n,
    output            sdram_we_n,
    output            sdram_dqml,
    output            sdram_dqmh,

    /* AXI slave interface */
    input [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input                    s_axi_awvalid,
    output                   s_axi_awready,
 
    input [DATA_WIDTH-1:0]   s_axi_wdata,
    input                    s_axi_wvalid,
    output                   s_axi_wready,
 
    input [ADDR_WIDTH-1:0]   s_axi_araddr,
    input                    s_axi_arvalid,
    output                   s_axi_arready,

    output [DATA_WIDTH-1:0]  s_axi_rdata,
    output                   s_axi_rvalid,
    input                    s_axi_rready

);

assign sdram_cke = 1'b1;
assign sdram_cs_n = 1'b0;

reg [ADDR_WIDTH-1:0] s_axi_addr_reg;
reg [DATA_WIDTH-1:0] s_axi_data_reg;

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

localparam [3:0] idle_state    = 4'h0;
localparam [3:0] nop_state     = 4'h1;
localparam [3:0] bst_state     = 4'h2;
localparam [3:0] read_state    = 4'h3;
localparam [3:0] reada_state   = 4'h4;
localparam [3:0] write_state   = 4'h5;
localparam [3:0] writea_state  = 4'h6;
localparam [3:0] act_state     = 4'h7;
localparam [3:0] pre_state     = 4'h7;
localparam [3:0] pall_state    = 4'h8;
localparam [3:0] ref_state     = 4'h9;
localparam [3:0] self_state    = 4'hA;
localparam [3:0] mrs_state     = 4'hB;

localparam [3:0] trcd_state    = 4'hC; // Active Command To Read / Write Command Delay
localparam [3:0] trp_state     = 4'hD; // Command Period (PRE to ACT)

reg trcd_clk_counter [1:0] = 0;
reg trp_clk_counter [1:0] = 0;
reg cas_shift_register [CAS_LATENCY:0] = 0;

reg [3:0] state, next_state;

/* Mode Register Definition */
reg [12:0] mode_register;
mode_register [2:0] = 3'b000; // burst length = 1
mode_register [3] = 1'b0; // burst type is sequential
mode_register [6:4] = 3'b010; // CAS latency = 2
mode_register [8:7] = 2'b00; // operating mode is standart operation
mode_register [9] = 1'b0; // write burst mode is programmed burst mode
mode_register [12:10] = 2'b00; // reserved, should be = 0

reg read_write_request [1:0] = 2'b00;   // LSB: 1 - read/write request, 0 - no request
                                        // MSB: 1 - read request, 0 - write request

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
    s_axi_rdata <= sdram_dq;
end

/* Finite-state machine */

always @(posedge clk or posedge reset) 
begin
    if (reset)
        state <= nop_state;
    else
        state <= next_state;
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
                trcd_clk_counter = trcd_clk_counter + 1;
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
            sdram_dq = s_axi_data_reg;
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
                trp_clk_counter = trp_clk_counter + 1;
                next_state = trp_state;
            end
        end
        default:
        begin
            sdram_cmd = sdram_cmd_nop;
            next_state = idle_state;
        end 
    endcase
end

endmodule