module up5k_zx_rom (
	input clk,
  input wen,
	input [13:0] addr,
	input [15:0] wdata,
	output [7:0] rdata
);

/*`ifdef SIM
  reg [7:0] data_out;
   
  reg [15:0] ram [0:16383];
  assign rdata = data_out[7:0];

  always @(posedge clk) begin
    if (wen)
      ram[addr] <= wdata;
    data_out <= addr[0] == 0 ? ram[addr[13:1]][7:0] : ram[addr[13:1]][15:8];
  end
`else*/
wire [15:0] rdata_0;

assign rdata = addr[0] == 0 ? rdata_0[7:0] : rdata_0[15:8];

SB_SPRAM256KA ram00
  (
    .ADDRESS(wen ? addr : {1'b0, addr[13:1]}),
    .DATAIN(wdata),
    .MASKWREN(4'b1111),
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
