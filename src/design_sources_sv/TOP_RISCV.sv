//-----------------------------------------------------------------------------
// TOP_RISCV.sv
// SystemVerilog conversion of TOP_RISCV.vhd
// Top level of the RV32I five-stage pipelined processor:
// structural connection of data_path and control_path
//-----------------------------------------------------------------------------

module TOP_RISCV
   import util_pkg::*;
(
   // Synchronization ports
   input  logic        clk,
   input  logic        ce,
   input  logic        reset,               // active-low, synchronous
   // Instruction memory interface
   output logic [31:0] instr_mem_address_o,
   input  logic [31:0] instr_mem_read_i,
   output logic        instr_mem_flush_o,
   output logic        instr_mem_en_o,
   // Data memory interface
   output logic [31:0] data_mem_address_o,
   input  logic [31:0] data_mem_read_i,
   output logic [31:0] data_mem_write_o,
   output logic [3:0]  data_mem_we_o
);

   logic       set_a_zero_s;
   logic [1:0] mem_to_reg_s;
   logic [2:0] load_type_s;
   alu_op_t    alu_op_s;
   logic       alu_src_b_s;
   logic       alu_src_a_s;
   logic       rd_we_s;
   logic       pc_next_sel_s;

   logic       if_id_flush_s;
   logic       id_ex_flush_s;

   fwd_a_t     alu_forward_a_s;
   fwd_b_t     alu_forward_b_s;
   logic       branch_condition_s;
   logic [1:0] branch_op_s;

   logic       pc_en_s;
   logic       if_id_en_s;

   // Data_path instance
   data_path data_path_1 (
      // global synchronization signals
      .clk                 (clk),
      .ce                  (ce),
      .reset               (reset),
      // operands come from instruction memory
      .instr_mem_address_o (instr_mem_address_o),
      .instr_mem_read_i    (instr_mem_read_i),
      // interface towards data memory
      .data_mem_address_o  (data_mem_address_o),
      .data_mem_write_o    (data_mem_write_o),
      .data_mem_read_i     (data_mem_read_i),
      // control signals come from control path
      .set_a_zero_i        (set_a_zero_s),
      .mem_to_reg_i        (mem_to_reg_s),
      .load_type_i         (load_type_s),
      .alu_op_i            (alu_op_s),
      .alu_src_b_i         (alu_src_b_s),
      .alu_src_a_i         (alu_src_a_s),
      .rd_we_i             (rd_we_s),
      .pc_next_sel_i       (pc_next_sel_s),
      .branch_op_i         (branch_op_s),
      // control signals for forwarding
      .alu_forward_a_i     (alu_forward_a_s),
      .alu_forward_b_i     (alu_forward_b_s),
      .branch_condition_o  (branch_condition_s),
      // control signals for flushing
      .if_id_flush_i       (if_id_flush_s),
      .id_ex_flush_i       (id_ex_flush_s),
      // control signals for stalling
      .pc_en_i             (pc_en_s),
      .if_id_en_i          (if_id_en_s)
   );

   // flush current instruction
   assign instr_mem_flush_o = if_id_flush_s;

   // Control_path instance
   control_path control_path_1 (
      // global synchronization signals
      .clk                 (clk),
      .ce                  (ce),
      .reset               (reset),
      // instruction is read from memory
      .instruction_i       (instr_mem_read_i),
      // control signals are forwarded to data_path
      .set_a_zero_o        (set_a_zero_s),
      .mem_to_reg_o        (mem_to_reg_s),
      .load_type_o         (load_type_s),
      .alu_op_o            (alu_op_s),
      .alu_src_b_o         (alu_src_b_s),
      .alu_src_a_o         (alu_src_a_s),
      .rd_we_o             (rd_we_s),
      .pc_next_sel_o       (pc_next_sel_s),
      .branch_op_o         (branch_op_s),
      // control signals for forwarding
      .alu_forward_a_o     (alu_forward_a_s),
      .alu_forward_b_o     (alu_forward_b_s),
      .branch_condition_i  (branch_condition_s),
      // control signals for flushing
      .data_mem_we_o       (data_mem_we_o),
      .if_id_flush_o       (if_id_flush_s),
      .id_ex_flush_o       (id_ex_flush_s),
      // control signals for stalling
      .pc_en_o             (pc_en_s),
      .if_id_en_o          (if_id_en_s)
   );

   // stall current instruction
   assign instr_mem_en_o = if_id_en_s;

endmodule : TOP_RISCV
