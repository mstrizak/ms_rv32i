//-----------------------------------------------------------------------------
// forwarding_unit.sv
// SystemVerilog conversion of forwarding_unit.vhd
// Checks whether forwarding for instructions in the EX stage is needed.
// Forwarding from the MEM stage has priority over the WB stage, because
// the information there is more recent (MEM checks are last, so they win).
//-----------------------------------------------------------------------------

module forwarding_unit
   import util_pkg::*;
(
   // mem inputs
   input  logic       rd_we_mem_i,
   input  logic [4:0] rd_address_mem_i,
   // wb inputs
   input  logic       rd_we_wb_i,
   input  logic [4:0] rd_address_wb_i,
   // forward control outputs
   output fwd_a_t     alu_forward_a_o,
   output fwd_b_t     alu_forward_b_o,
   // ex inputs
   input  logic [4:0] rs1_address_ex_i,
   input  logic [4:0] rs2_address_ex_i
);

   always_comb begin : forward_proc
      alu_forward_a_o = dont_fwd_a;
      alu_forward_b_o = dont_fwd_b;

      // forwarding from WB stage
      if (rd_we_wb_i == 1'b1) begin
         if (rd_address_wb_i == rs1_address_ex_i)
            alu_forward_a_o = fwd_a_from_wb;
         if (rd_address_wb_i == rs2_address_ex_i)
            alu_forward_b_o = fwd_b_from_wb;
      end

      // forwarding from MEM stage (overrides WB - more recent data)
      if (rd_we_mem_i == 1'b1) begin
         if (rd_address_mem_i == rs1_address_ex_i)
            alu_forward_a_o = fwd_a_from_mem;
         if (rd_address_mem_i == rs2_address_ex_i)
            alu_forward_b_o = fwd_b_from_mem;
      end
   end

endmodule : forwarding_unit
