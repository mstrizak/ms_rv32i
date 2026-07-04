//-----------------------------------------------------------------------------
// alu_decoder.sv
// SystemVerilog conversion of alu_decoder.vhd
// Finds the appropriate ALU operation from ctrl_decoder output and
// funct3/funct7 instruction fields
//-----------------------------------------------------------------------------

module alu_decoder
   import util_pkg::*;
(
   // from control decoder / pipeline
   input  logic [1:0] alu_2bit_op_i,
   input  logic [2:0] funct3_i,
   input  logic [6:0] funct7_i,
   // to data_path
   output alu_op_t    alu_op_o
);

   always_comb begin : alu_dec
      // default
      alu_op_o = add_op;
      case (alu_2bit_op_i)
         2'b00: begin
            alu_op_o = add_op;
         end
         // 2'b01: (branch comparisons - handled elsewhere, kept commented as in original)
         default: begin
            case (funct3_i)
               3'b000: begin
                  alu_op_o = add_op;
                  if (alu_2bit_op_i == 2'b10 && funct7_i[5] == 1'b1)
                     alu_op_o = sub_op;
                  // else if (funct7_i[0] == 1'b1) alu_op_o = mulu_op;
               end
               3'b001: begin
                  alu_op_o = sll_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = mulhs_op;
               end
               3'b010: begin
                  alu_op_o = lts_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = mulhsu_op;
               end
               3'b011: begin
                  alu_op_o = ltu_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = mulhu_op;
               end
               3'b100: begin
                  alu_op_o = xor_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = divs_op;
               end
               3'b101: begin
                  alu_op_o = srl_op;
                  if (funct7_i[5] == 1'b1)
                     alu_op_o = sra_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = divu_op;
               end
               3'b110: begin
                  alu_op_o = or_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = rems_op;
               end
               default: begin
                  alu_op_o = and_op;
                  // if (alu_2bit_op_i == 2'b10 && funct7_i[0] == 1'b1) alu_op_o = remu_op;
               end
            endcase
         end
      endcase
   end

endmodule : alu_decoder
