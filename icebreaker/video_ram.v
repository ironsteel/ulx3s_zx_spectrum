module video_ram(
  input clk,
  input we,
  input [12:0] addr_a,
  input [7:0] din_a,
  output reg [7:0] dout_a,
  input [12:0] addr_b,
  output reg [7:0] dout_b
);

reg [7:0] mem[0:6910];

always @(posedge clk) begin
  if (we)
    mem[addr_a] <= din_a;
  dout_a <= mem[addr_a];
  dout_b <= mem[addr_b];
end
   
endmodule
