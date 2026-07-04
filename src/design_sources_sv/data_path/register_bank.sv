//-----------------------------------------------------------------------------
// register_bank.sv
// SystemVerilog conversion of register_bank.vhd
// 32 x 32-bit register file:
//   - synchronous write on FALLING clock edge (as in the original design,
//     so a value written in WB can be read in the same cycle in ID)
//   - asynchronous read, register x0 hardwired to zero
//-----------------------------------------------------------------------------

module register_bank #(
   parameter int WIDTH = 32
)(
   input  logic             clk,
   input  logic             ce,
   input  logic             reset,          // active-low, synchronous
   input  logic [4:0]       rs1_address_i,
   input  logic [4:0]       rs2_address_i,
   output logic [WIDTH-1:0] rs1_data_o,
   output logic [WIDTH-1:0] rs2_data_o,
   input  logic             rd_we_i,
   input  logic [4:0]       rd_address_i,
   input  logic [WIDTH-1:0] rd_data_i
);

   logic [31:0] reg_bank_s [0:31];

   // synchronous write, reset (falling edge of clk, gated by ce)
   always_ff @(negedge clk) begin : reg_bank_write
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            for (int i = 0; i < 32; i++)
               reg_bank_s[i] <= '0;
         end
         else if (rd_we_i == 1'b1) begin
            reg_bank_s[rd_address_i] <= rd_data_i;
         end
      end
   end

   // asynchronous read (zero-th register set to zero as per spec)
   always_comb begin : reg_bank_read
      if (rs1_address_i == 5'd0)
         rs1_data_o = '0;
      else
         rs1_data_o = reg_bank_s[rs1_address_i];

      if (rs2_address_i == 5'd0)
         rs2_data_o = '0;
      else
         rs2_data_o = reg_bank_s[rs2_address_i];
   end

endmodule : register_bank
