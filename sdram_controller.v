module sdram_controller #
(
    parameter ID_WIDTH = 8,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
)
(
    input clk,
    input rst,

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
    
endmodule