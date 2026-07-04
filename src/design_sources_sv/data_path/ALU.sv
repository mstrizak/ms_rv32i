//-----------------------------------------------------------------------------
// ALU.sv
// SystemVerilog conversion of ALU.vhd
//-----------------------------------------------------------------------------

module ALU
   import util_pkg::*;
#(
   parameter int WIDTH = 32
)(
   input  logic [WIDTH-1:0] a_i,   // first input
   input  logic [WIDTH-1:0] b_i,   // second input
   input  alu_op_t          op_i,  // operation select
   output logic [WIDTH-1:0] res_o  // result
   // output logic          zero_o, // zero flag
   // output logic          of_o    // overflow flag
);

   localparam int L2WIDTH = $clog2(WIDTH);

   logic [WIDTH-1:0] lts_res, ltu_res, add_res, sub_res, or_res, and_res, res_s, xor_res;
   logic [WIDTH-1:0] sll_res, srl_res, sra_res;
   // logic [WIDTH-1:0] eq_res;

   // addition
   assign add_res = a_i + b_i;
   // subtraction
   assign sub_res = a_i - b_i;
   // and gate
   assign and_res = a_i & b_i;
   // or gate
   assign or_res  = a_i | b_i;
   // xor gate
   assign xor_res = a_i ^ b_i;
   // equal
   // assign eq_res = ($signed(a_i) == $signed(b_i)) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
   // less than signed
   assign lts_res = ($signed(a_i) < $signed(b_i)) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
   // less than unsigned
   assign ltu_res = (a_i < b_i) ? {{(WIDTH-1){1'b0}}, 1'b1} : '0;
   // shift results (shift amount width matches original: bits [L2WIDTH:0])
   assign sll_res = a_i << b_i[L2WIDTH:0];
   assign srl_res = a_i >> b_i[L2WIDTH:0];
   assign sra_res = $signed(a_i) >>> b_i[L2WIDTH:0];

   // SELECT RESULT
   assign res_o = res_s;

   always_comb begin
      unique case (op_i)
         and_op:  res_s = and_res;  // and
         or_op:   res_s = or_res;   // or
         xor_op:  res_s = xor_res;  // xor
         add_op:  res_s = add_res;  // add
         sub_op:  res_s = sub_res;  // sub
         lts_op:  res_s = lts_res;  // set less than signed
         ltu_op:  res_s = ltu_res;  // set less than unsigned
         sll_op:  res_s = sll_res;  // shift left logic
         srl_op:  res_s = srl_res;  // shift right logic
         sra_op:  res_s = sra_res;  // shift right arithmetic
         default: res_s = '1;
      endcase
   end

   // flag outputs
   // assign zero_o = (res_s == '0);
   // assign of_o   = ((op_i == add_op && (a_i[WIDTH-1] == b_i[WIDTH-1]) && ((a_i[WIDTH-1] ^ res_s[WIDTH-1]) == 1'b1)) ||
   //                  (op_i == sub_op && (a_i[WIDTH-1] == res_s[WIDTH-1]) && ((a_i[WIDTH-1] ^ b_i[WIDTH-1]) == 1'b1)));

endmodule : ALU
