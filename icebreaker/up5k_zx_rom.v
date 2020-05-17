module up5k_zx_rom (
	input clk,
  input wen,
	input [13:0] addr,
	input [7:0] wdata,
	output [7:0] rdata
);

wire [15:0] rdata_0;
wire [3:0] maskwren;

assign rdata = addr[0] == 0 ? rdata_0[7:0] : rdata_0[15:8];

assign maskwren = addr[0] == 0 ? 4'b0011 : 4'b1100;

wire [15:0] data_write = addr[0] == 0 ? {8'b0, wdata} : {wdata, 8'b0};

SB_SPRAM256KA ram00
  (
    .ADDRESS({1'b0, addr[13:1]}),
    .DATAIN(data_write),
    .MASKWREN(maskwren),
    .WREN(wen),
    .CHIPSELECT(1'b1),
    .CLOCK(clk),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
    .DATAOUT(rdata_0)
  );
//`endif
endmodule
