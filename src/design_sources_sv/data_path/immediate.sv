//-----------------------------------------------------------------------------
// immediate.sv
// SystemVerilog conversion of immediate.vhd
// Sign/zero extension of instruction immediates for every RV32I format
//-----------------------------------------------------------------------------

module immediate (
   input  logic [31:0] instruction_i,
   output logic [31:0] immediate_extended_o
);

   logic [6:0]  opcode;
   logic [2:0]  instruction_type;
   logic [2:0]  funct3;
   logic [19:0] extension;

   localparam logic [2:0] r_type_instruction = 3'b000;
   localparam logic [2:0] i_type_instruction = 3'b001;
   localparam logic [2:0] s_type_instruction = 3'b010;
   localparam logic [2:0] b_type_instruction = 3'b011;
   localparam logic [2:0] u_type_instruction = 3'b100;
   localparam logic [2:0] j_type_instruction = 3'b101;
   localparam logic [2:0] shamt_instruction  = 3'b110;
   localparam logic [2:0] fence_ecall_ebreak = 3'b111;

   assign opcode    = instruction_i[6:0];
   assign extension = {20{instruction_i[31]}};
   assign funct3    = instruction_i[14:12];

   // based on opcode find instruction type
   always_comb begin
      case (opcode[6:2])
         5'b01100: instruction_type = r_type_instruction;
         5'b00000: instruction_type = i_type_instruction;
         5'b00100: begin
            if (funct3 == 3'b001 || funct3 == 3'b101)
               instruction_type = shamt_instruction;
            else
               instruction_type = i_type_instruction;
         end
         5'b11001: instruction_type = i_type_instruction;
         5'b01000: instruction_type = s_type_instruction;
         5'b11000: instruction_type = b_type_instruction;
         5'b01101: instruction_type = u_type_instruction;
         5'b00101: instruction_type = u_type_instruction;
         5'b11011: instruction_type = j_type_instruction;
         default:  instruction_type = fence_ecall_ebreak;
      endcase
   end

   // based on instruction type from previous process extend data
   always_comb begin
      case (instruction_type)
         i_type_instruction:
            immediate_extended_o = {extension, instruction_i[31:20]};
         shamt_instruction:
            immediate_extended_o = {27'd0, instruction_i[24:20]};
         b_type_instruction:
            immediate_extended_o = {extension[18:0], instruction_i[31], instruction_i[7],
                                    instruction_i[30:25], instruction_i[11:8], 1'b0};
         s_type_instruction:
            immediate_extended_o = {extension[19:0], instruction_i[31:25], instruction_i[11:7]};
         u_type_instruction:
            immediate_extended_o = {instruction_i[31:12], 12'd0};
         j_type_instruction:
            immediate_extended_o = {extension[10:0], instruction_i[31], instruction_i[19:12],
                                    instruction_i[20], instruction_i[30:21], 1'b0};
         default:
            immediate_extended_o = '0;
      endcase
   end

endmodule : immediate
