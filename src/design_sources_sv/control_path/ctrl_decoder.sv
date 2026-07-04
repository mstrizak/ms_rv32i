//-----------------------------------------------------------------------------
// ctrl_decoder.sv
// SystemVerilog conversion of ctrl_decoder.vhd
// Decodes the opcode field into pipeline control signals
//-----------------------------------------------------------------------------

module ctrl_decoder (
   // from data_path
   input  logic [6:0] opcode_i,
   // to data_path
   output logic [1:0] branch_type_o,
   output logic [1:0] mem_to_reg_o,
   output logic       data_mem_we_o,
   output logic       alu_src_b_o,
   output logic       alu_src_a_o,
   output logic       rd_we_o,
   output logic       set_a_zero_o,
   output logic       rs1_in_use_o,
   output logic       rs2_in_use_o,
   output logic [1:0] alu_2bit_op_o
);

   always_comb begin : control_dec
      // default
      branch_type_o = 2'b00;
      mem_to_reg_o  = 2'b00;
      data_mem_we_o = 1'b0;
      alu_src_b_o   = 1'b0;
      alu_src_a_o   = 1'b0;
      rd_we_o       = 1'b0;
      alu_2bit_op_o = 2'b00;
      set_a_zero_o  = 1'b0;
      rs1_in_use_o  = 1'b0;
      rs2_in_use_o  = 1'b0;

      case (opcode_i)
         7'b0000011: begin              // LOAD
            mem_to_reg_o  = 2'b10;
            alu_src_b_o   = 1'b1;
            rd_we_o       = 1'b1;
            rs1_in_use_o  = 1'b1;
         end
         7'b0100011: begin              // STORE
            data_mem_we_o = 1'b1;
            alu_src_b_o   = 1'b1;
            rs1_in_use_o  = 1'b1;
            rs2_in_use_o  = 1'b1;
         end
         7'b0110011: begin              // R type
            alu_2bit_op_o = 2'b10;
            rd_we_o       = 1'b1;
            rs1_in_use_o  = 1'b1;
            rs2_in_use_o  = 1'b1;
         end
         7'b0010011: begin              // I type
            alu_2bit_op_o = 2'b11;
            alu_src_b_o   = 1'b1;
            rd_we_o       = 1'b1;
            rs1_in_use_o  = 1'b1;
         end
         7'b1100011: begin              // B type
            alu_2bit_op_o = 2'b00;
            alu_src_a_o   = 1'b1;
            alu_src_b_o   = 1'b1;
            branch_type_o = 2'b01;
            rs1_in_use_o  = 1'b1;
            rs2_in_use_o  = 1'b1;
         end
         7'b1101111: begin              // JAL
            rd_we_o       = 1'b1;
            alu_src_a_o   = 1'b1;
            alu_src_b_o   = 1'b1;
            mem_to_reg_o  = 2'b01;
            branch_type_o = 2'b10;
         end
         7'b1100111: begin              // JALR
            rs1_in_use_o  = 1'b1;
            mem_to_reg_o  = 2'b01;
            rd_we_o       = 1'b1;
            alu_src_b_o   = 1'b1;
            branch_type_o = 2'b11;
         end
         7'b0010111: begin              // AUIPC
            rd_we_o       = 1'b1;
            alu_src_b_o   = 1'b1;
            alu_src_a_o   = 1'b1;
         end
         7'b0110111: begin              // LUI
            set_a_zero_o  = 1'b1;
            rd_we_o       = 1'b1;
            alu_src_b_o   = 1'b1;
         end
         default: ;                     // keep defaults
      endcase
   end

endmodule : ctrl_decoder
