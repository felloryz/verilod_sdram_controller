/*
SDRAM controller for IS42S16320F-7TL (Terasic DE10-Lite)
*/

module sdram_controller #
(
    parameter ID_WIDTH = 8,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter IS_READ_PRIORITY = 1;
)
(
    input clk,
    input reset,

    /* SDRAM interface */
    output  [12:0]  sdram_addr,
    output  [1:0]   sdram_ba,
    inout   [15:0]  sdram_dq,
    output          sdram_clk,
    output          sdram_cke,
    output          sdram_cs_n,
    output          sdram_ras_n,
    output          sdram_cas_n,
    output          sdram_we_n,
    output          sdram_dqml,
    output          sdram_dqmh,

    /* AXI slave interface */
    //input [ID_WIDTH-1:0]    s_axi_awid,
    input [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input [7:0]             s_axi_awlen,
    input [2:0]             s_axi_awsize,
    input                   s_axi_awvalid,
    output                  s_axi_awready,

    input [DATA_WIDTH-1:0]  s_axi_wdata,
    input                   s_axi_wlast,
    input                   s_axi_wvalid,
    output                  s_axi_wready,

    input [ID_WIDTH-1:0]    s_axi_arid,
    input [ADDR_WIDTH-1:0]  s_axi_araddr,
    input [7:0]             s_axi_arlen,
    input [2:0]             s_axi_arsize,
    input                   s_axi_arvalid,
    output                  s_axi_arready,

    input [ID_WIDTH-1:0]    s_axi_rid,
    input [DATA_WIDTH-1:0]  s_axi_rdata,
    input                   s_axi_rlast,
    input                   s_axi_rvalid,
    output                  s_axi_rready

);

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

reg [3:0] state, next_state;

reg read_request, write_request;

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
            if (read_request | write_request)
            begin
                sdram_cmd = sdram_cmd_act;
                sdram_ba = ...; // bank address
                sdram_addr = ...; // row address
                sdram_dqm = ...;
                next_state = act_state;
            end
            else
            begin
                sdram_cmd = sdram_cmd_nop;
                next_state = idle_state;
            end
        end
        act_state:
        begin
            if (read_request)
            begin
                sdram_cmd = sdram_cmd_read;
                sdram_addr[10] = 1'b0; // no auto precharge
                sdram_ba = ...;
                sdram_addr[9:0] = ...; // column address
                sdram_dqm = ...;
                next_state = read_state;
            end
            else if (write_request)
            begin
                sdram_cmd = sdram_cmd_write;
                sdram_addr[10] = 1'b0; // no auto precharge
                sdram_ba = ...;
                sdram_addr[9:0] = ...; // column address
                sdram_dqm = ...;
                next_state = write_state;
            end
        end
        read_state:
        begin
            sdram_cmd = sdram_cmd_precharge;
            sdram_addr[10] = 1'b0;
            sdram_ba = ...;
            next_state = pre_state; // precharge select bank
        end
        write_state:
        begin
            sdram_cmd = sdram_cmd_precharge;
            sdram_addr[10] = 1'b0;
            sdram_ba = ...;
            next_state = pre_state;
        end
        pre_state:
        begin
            sdram_cmd = sdram_cmd_nop;
            next_state = idle_state;
        end
        default:
        begin
            sdram_cmd = sdram_cmd_nop;
            next_state = idle_state;
        end 
    endcase
end

endmodule