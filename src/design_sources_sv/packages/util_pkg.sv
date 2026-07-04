//-----------------------------------------------------------------------------
// util_pkg.sv
// SystemVerilog conversion of util_pkg.vhd
//-----------------------------------------------------------------------------

package util_pkg;

   // ALU operation select type
   typedef enum logic [3:0] {
      and_op,
      or_op,
      xor_op,
      add_op,
      sub_op,
      lts_op,
      ltu_op,
      sll_op,
      srl_op,
      sra_op
   } alu_op_t;

   // Forwarding control for ALU input A
   typedef enum logic [1:0] {
      dont_fwd_a,
      fwd_a_from_mem,
      fwd_a_from_wb
   } fwd_a_t;

   // Forwarding control for ALU input B
   typedef enum logic [1:0] {
      dont_fwd_b,
      fwd_b_from_mem,
      fwd_b_from_wb
   } fwd_b_t;

   // Ceiling log2 (floor-based loop, identical to the VHDL implementation)
   function automatic integer clogb2(input integer depth);
      integer temp;
      integer ret_val;
      begin
         temp    = depth;
         ret_val = 0;
         while (temp > 1) begin
            ret_val = ret_val + 1;
            temp    = temp / 2;
         end
         return ret_val;
      end
   endfunction

endpackage : util_pkg
