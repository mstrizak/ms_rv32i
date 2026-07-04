//-----------------------------------------------------------------------------
// data_path.sv
// SystemVerilog conversion of data_path.vhd
// Five-stage pipeline datapath: IF, ID, EX, MEM, WB
//-----------------------------------------------------------------------------

module data_path
   import util_pkg::*;
(
   // global synchronization ports
   input  logic        clk,
   input  logic        ce,
   input  logic        reset,               // active-low, synchronous
   // instruction memory interface
   output logic [31:0] instr_mem_address_o,
   input  logic [31:0] instr_mem_read_i,
   // data memory interface
   output logic [31:0] data_mem_address_o,
   output logic [31:0] data_mem_write_o,
   input  logic [31:0] data_mem_read_i,
   // control signals that are forwarded from control path
   input  logic [1:0]  mem_to_reg_i,
   input  logic [2:0]  load_type_i,
   input  alu_op_t     alu_op_i,
   input  logic        alu_src_a_i,
   input  logic        alu_src_b_i,
   input  logic        pc_next_sel_i,
   input  logic        rd_we_i,
   input  logic        set_a_zero_i,
   // control signals for forwarding
   input  fwd_a_t      alu_forward_a_i,
   input  fwd_b_t      alu_forward_b_i,
   output logic        branch_condition_o,
   input  logic [1:0]  branch_op_i,
   // control signals for flushing
   input  logic        if_id_flush_i,
   input  logic        id_ex_flush_i,
   // control signals for stalling
   input  logic        pc_en_i,
   input  logic        if_id_en_i,
   input  logic        id_ex_en_i,
   input  logic        ex_mem_en_i,
   input  logic        mem_wb_en_i
);

   //*********  INSTRUCTION FETCH  **************
   logic [31:0] pc_reg_if_s;
   logic [31:0] pc_next_if_s;
   logic [31:0] pc_adder_if_s;

   //*********  INSTRUCTION DECODE **************
   logic [31:0] pc_adder_id_s;
   logic [31:0] pc_reg_id_s;
   logic [31:0] rs1_data_id_s;
   logic [31:0] rs2_data_id_s;
   logic [31:0] immediate_extended_id_s;
   logic [4:0]  rs1_address_id_s;
   logic [4:0]  rs2_address_id_s;
   logic [4:0]  rd_address_id_s;

   //*********       EXECUTE       **************
   logic [31:0] pc_adder_ex_s;
   logic [31:0] pc_reg_ex_s;
   logic [31:0] immediate_extended_ex_s;
   logic [31:0] alu_forward_a_ex_s;
   logic [31:0] alu_forward_b_ex_s;
   logic [31:0] b_ex_s, a_ex_s;
   logic [31:0] alu_result_ex_s;
   logic [31:0] rs1_data_ex_s;
   logic [31:0] rs2_data_ex_s;
   logic [4:0]  rd_address_ex_s;

   //*********       MEMORY        **************
   logic [31:0] pc_adder_mem_s;
   logic [31:0] alu_result_mem_s;
   logic [4:0]  rd_address_mem_s;
   logic [31:0] rs2_data_mem_s;

   //*********      WRITEBACK      **************
   logic [31:0] pc_adder_wb_s;
   logic [31:0] alu_result_wb_s;
   logic [31:0] extended_data_wb_s;
   logic [31:0] rd_data_wb_s;
   logic [4:0]  rd_address_wb_s;

   //***********  Sequential logic  ******************

   // Program Counter
   always_ff @(posedge clk) begin : pc_proc
      if (ce == 1'b1) begin
         if (reset == 1'b0)
            pc_reg_if_s <= '0;
         else if (pc_en_i == 1'b1)
            pc_reg_if_s <= pc_next_if_s;
      end
   end

   // IF/ID register
   always_ff @(posedge clk) begin : if_id
      if (ce == 1'b1) begin
         if (if_id_en_i == 1'b1) begin
            if (reset == 1'b0 || if_id_flush_i == 1'b1) begin
               pc_reg_id_s   <= '0;
               pc_adder_id_s <= '0;
            end
            else begin
               pc_reg_id_s   <= pc_reg_if_s;
               pc_adder_id_s <= pc_adder_if_s;
            end
         end
      end
   end

   // ID/EX register (reset checked before the new id_ex_en_i hold gate,
   // same convention as control_path's matching shadow register)
   always_ff @(posedge clk) begin : id_ex
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            pc_adder_ex_s           <= '0;
            rs1_data_ex_s           <= '0;
            rs2_data_ex_s           <= '0;
            immediate_extended_ex_s <= '0;
            rd_address_ex_s         <= '0;
         end
         else if (id_ex_en_i == 1'b1) begin
            if (id_ex_flush_i == 1'b1) begin
               pc_adder_ex_s           <= '0;
               rs1_data_ex_s           <= '0;
               rs2_data_ex_s           <= '0;
               immediate_extended_ex_s <= '0;
               rd_address_ex_s         <= '0;
            end
            else begin
               pc_adder_ex_s           <= pc_adder_id_s;
               rs1_data_ex_s           <= rs1_data_id_s;
               rs2_data_ex_s           <= rs2_data_id_s;
               immediate_extended_ex_s <= immediate_extended_id_s;
               rd_address_ex_s         <= rd_address_id_s;
            end
         end
         // else: id_ex_en_i == 0 -> hold (mem_stall in progress)
      end
   end

   // EX/MEM register (reset checked before the new ex_mem_en_i hold gate)
   always_ff @(posedge clk) begin : ex_mem
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            alu_result_mem_s <= '0;
            rs2_data_mem_s   <= '0;
            pc_adder_mem_s   <= '0;
            rd_address_mem_s <= '0;
            pc_reg_ex_s      <= '0;
         end
         else if (ex_mem_en_i == 1'b1) begin
            alu_result_mem_s <= alu_result_ex_s;
            rs2_data_mem_s   <= alu_forward_b_ex_s;
            pc_adder_mem_s   <= pc_adder_ex_s;
            rd_address_mem_s <= rd_address_ex_s;
            pc_reg_ex_s      <= pc_reg_id_s;
         end
         // else: ex_mem_en_i == 0 -> hold (mem_stall in progress)
      end
   end

   // MEM/WB register (reset checked before the new mem_wb_en_i hold gate)
   always_ff @(posedge clk) begin : mem_wb
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            alu_result_wb_s <= '0;
            pc_adder_wb_s   <= '0;
            rd_address_wb_s <= '0;
         end
         else if (mem_wb_en_i == 1'b1) begin
            alu_result_wb_s <= alu_result_mem_s;
            pc_adder_wb_s   <= pc_adder_mem_s;
            rd_address_wb_s <= rd_address_mem_s;
         end
         // else: mem_wb_en_i == 0 -> hold (mem_stall in progress)
      end
   end

   //***********  Combinational logic  ***************

   // pc_adder_s update
   assign pc_adder_if_s = pc_reg_if_s + 32'd4;

   // branch condition
   // (comparisons kept identical to the original VHDL, including the use of
   //  signed comparison for branch_op "11")
   assign branch_condition_o =
      (($signed(alu_forward_a_ex_s) == $signed(alu_forward_b_ex_s)) && branch_op_i == 2'b00) ? 1'b1 :
      (($signed(alu_forward_a_ex_s) <  $signed(alu_forward_b_ex_s)) && branch_op_i == 2'b10) ? 1'b1 :
      (($signed(alu_forward_a_ex_s) >  $signed(alu_forward_b_ex_s)) && branch_op_i == 2'b11) ? 1'b1 :
      1'b0;

   // pc_next mux
   assign pc_next_if_s = (pc_next_sel_i == 1'b0) ? pc_adder_if_s : alu_result_ex_s;

   // forwarding muxes
   assign alu_forward_a_ex_s = (alu_forward_a_i == fwd_a_from_wb)  ? rd_data_wb_s     :
                               (alu_forward_a_i == fwd_a_from_mem) ? alu_result_mem_s :
                                                                     rs1_data_ex_s;
   assign alu_forward_b_ex_s = (alu_forward_b_i == fwd_b_from_wb)  ? rd_data_wb_s     :
                               (alu_forward_b_i == fwd_b_from_mem) ? alu_result_mem_s :
                                                                     rs2_data_ex_s;

   // update alu inputs
   assign b_ex_s = (alu_src_b_i == 1'b1) ? immediate_extended_ex_s : alu_forward_b_ex_s;

   assign a_ex_s = (set_a_zero_i == 1'b1) ? '0          :
                   (alu_src_a_i  == 1'b1) ? pc_reg_ex_s :
                                            alu_forward_a_ex_s;

   // reg_bank rd_data update
   always_comb begin
      case (mem_to_reg_i)
         2'b01:   rd_data_wb_s = pc_adder_wb_s;
         2'b10:   rd_data_wb_s = extended_data_wb_s;
         default: rd_data_wb_s = alu_result_wb_s;
      endcase
   end

   // extend data based on type of load instruction
   always_comb begin
      case (load_type_i)
         3'b000:  extended_data_wb_s = {{24{data_mem_read_i[7]}},  data_mem_read_i[7:0]};   // lb
         3'b001:  extended_data_wb_s = {{16{data_mem_read_i[15]}}, data_mem_read_i[15:0]};  // lh
         3'b100:  extended_data_wb_s = {24'd0, data_mem_read_i[7:0]};                       // lbu
         3'b101:  extended_data_wb_s = {16'd0, data_mem_read_i[15:0]};                      // lhu
         default: extended_data_wb_s = data_mem_read_i;                                     // lw
      endcase
   end

   // extract operand addresses from instruction
   assign rs1_address_id_s = instr_mem_read_i[19:15];
   assign rs2_address_id_s = instr_mem_read_i[24:20];
   assign rd_address_id_s  = instr_mem_read_i[11:7];

   //***********  Instantiation ***********

   // Register bank
   register_bank #(
      .WIDTH (32)
   ) register_bank_1 (
      .clk           (clk),
      .ce            (ce),
      .reset         (reset),
      .rd_we_i       (rd_we_i),
      .rs1_address_i (rs1_address_id_s),
      .rs2_address_i (rs2_address_id_s),
      .rs1_data_o    (rs1_data_id_s),
      .rs2_data_o    (rs2_data_id_s),
      .rd_address_i  (rd_address_wb_s),
      .rd_data_i     (rd_data_wb_s)
   );

   // Immediate unit instance
   immediate immediate_1 (
      .instruction_i        (instr_mem_read_i),
      .immediate_extended_o (immediate_extended_id_s)
   );

   // ALU unit instance
   ALU #(
      .WIDTH (32)
   ) ALU_1 (
      .a_i   (a_ex_s),
      .b_i   (b_ex_s),
      .op_i  (alu_op_i),
      .res_o (alu_result_ex_s)
      // .zero_o (alu_zero_ex_s),
      // .of_o   (alu_of_ex_s)
   );

   //***********  Outputs  ***************
   // To instruction memory
   assign instr_mem_address_o = pc_reg_if_s;
   // To data memory
   assign data_mem_address_o  = alu_result_mem_s;
   assign data_mem_write_o    = rs2_data_mem_s;

endmodule : data_path
