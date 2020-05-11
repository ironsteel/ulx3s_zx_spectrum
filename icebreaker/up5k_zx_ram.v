module up5k_zx_ram(
  input            clk_a,
  input            we_a,
  input [15:0]     addr_a,
  input [7:0]      din_a,
  output [7:0] dout_a
);

wire cs_0 = !addr_a[14];
wire cs_1 = addr_a[14];
wire [3:0] wren_mask = addr_a[0] == 0 ? 4'b0011 : 4'b1100;

wire [15:0] wdata = addr_a[0] == 0 ? {8'b0, din_a} : {din_a, 8'b0};

assign dout_a = addr_a[14] ? (addr_a[0] == 0 ? rdata_1[7:0] : rdata_1[15:8]) :
                             (addr_a[0] == 0 ? rdata_0[7:0] : rdata_0[15:8]);
wire [15:0] rdata_0;
wire [15:0] rdata_1;

SB_SPRAM256KA ram00
  (
    .ADDRESS(addr_a[14:1]),
    .DATAIN(wdata),
    .MASKWREN(wren_mask),
    .WREN(we_a),
    .CHIPSELECT(cs_0),
    .CLOCK(clk_a),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
    .DATAOUT(rdata_0)
  );

SB_SPRAM256KA ram01
  (
    .ADDRESS(addr_a[14:1]),
    .DATAIN(wdata),
    .MASKWREN(wren_mask),
    .WREN(we_a),
    .CHIPSELECT(cs_1),
    .CLOCK(clk_a),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
    .DATAOUT(rdata_1)
  );
endmodule
