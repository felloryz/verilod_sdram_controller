`timescale 1ns/1ps

// `define den512Mb
// `define sg6a
// `define x16

module testbench;

localparam ADDR_WIDTH = 25;
localparam DATA_WIDTH = 16;

reg clk, reset;

wire [12:0]  sdram_addr;
wire [1:0]   sdram_ba;
wire [15:0]  sdram_dq;
wire         sdram_clk;
wire         sdram_cke;
wire         sdram_cs_n;
wire         sdram_ras_n;
wire         sdram_cas_n;
wire         sdram_we_n;
wire         sdram_dqml;
wire         sdram_dqmh;

wire [1:0]    sdram_dqm;
assign sdram_dqm = {sdram_dqml, sdram_dqmh};

reg  [ADDR_WIDTH-1:0]      s_axi_araddr;
reg                        s_axi_arvalid;
wire                       s_axi_arready;

wire  [DATA_WIDTH-1:0]     s_axi_rdata;
wire                       s_axi_rvalid;
reg                        s_axi_rready;

reg  [ADDR_WIDTH-1:0]      s_axi_awaddr;
reg                        s_axi_awvalid;
wire                       s_axi_awready;

reg  [DATA_WIDTH-1:0]      s_axi_wdata;
reg                        s_axi_wvalid;
wire                       s_axi_wready;

sdram_controller controller (
    .clk            (clk        ),
    .reset          (reset      ),
    .sdram_addr     (sdram_addr ),
    .sdram_ba       (sdram_ba   ),
    .sdram_dq       (sdram_dq   ),
    .sdram_clk      (sdram_clk  ),
    .sdram_cke      (sdram_cke  ),
    .sdram_cs_n     (sdram_cs_n ),
    .sdram_ras_n    (sdram_ras_n),
    .sdram_cas_n    (sdram_cas_n),
    .sdram_we_n     (sdram_we_n ),
    .sdram_dqml     (sdram_dqml ),
    .sdram_dqmh     (sdram_dqmh ),

    .s_axi_araddr   (s_axi_araddr ),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_arready  (s_axi_arready),

    .s_axi_rdata    (s_axi_rdata  ),
    .s_axi_rvalid   (s_axi_rvalid ),
    .s_axi_rready   (s_axi_rready ),

    .s_axi_awaddr   (s_axi_awaddr ),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awready  (s_axi_awready),

    .s_axi_wdata     (s_axi_wdata ),
    .s_axi_wvalid    (s_axi_wvalid),
    .s_axi_wready    (s_axi_wready)
);

sdr sdram (
    .Clk    (sdram_clk  ),
    .Cke    (sdram_cke  ),
    .Cs_n   (sdram_cs_n ),
    .Ras_n  (sdram_ras_n),
    .Cas_n  (sdram_cas_n),
    .We_n   (sdram_we_n ),
    .Addr   (sdram_addr ),
    .Ba     (sdram_ba   ),
    .Dq     (sdram_dq   ),
    .Dqm    (sdram_dqm  )
);

initial
begin
    clk = 0;
    forever #5 clk = ~ clk;
end

initial
begin
    reset = 1;
    #40
    reset = 0;
    #400000
    $stop;
end

initial
begin
    wait(~reset);
    s_axi_rready <= 1;
end

task read(input [ADDR_WIDTH-1:0] addr);
begin
    if (~(s_axi_arvalid & s_axi_arready))
        @(posedge clk);
    s_axi_arvalid <= 1;
    s_axi_araddr <= addr;
    @(posedge clk);
    while (~s_axi_arready) @(posedge clk);
    s_axi_arvalid <= 0;
end
endtask

task write(input [ADDR_WIDTH-1:0] addr, [DATA_WIDTH-1:0] data);
begin
    if (~(s_axi_awvalid & s_axi_awready & s_axi_wvalid & s_axi_wready))
        @(posedge clk);
    s_axi_awvalid <= 1;
    s_axi_awaddr <= addr;
    s_axi_wvalid <= 1;
    s_axi_wdata <= data;
    @(posedge clk);
    while (~(s_axi_awready & s_axi_wready)) 
        @(posedge clk);
    s_axi_awvalid <= 0;
    s_axi_wvalid <= 0;
end
endtask

initial
begin
    wait(~reset);
    write(1, 1);
    read(1);
    write(2, 2);
    read(2);
    write(3, 3);
    read(3);
end


endmodule