//-----------------------------------------------------------------------------
// control_path.sv
// SystemVerilog conversion of control_path.vhd
// Pipelined control path: decodes instructions and carries control signals
// through ID/EX, EX/MEM and MEM/WB pipeline registers
//-----------------------------------------------------------------------------

module control_path
   import util_pkg::*;
(
   // global synchronization signals
   input  logic        clk,
   input  logic        ce,
   input  logic        reset,              // active-low, synchronous
   // instruction is read from memory
   input  logic [31:0] instruction_i,
   // from data_path comparator
   input  logic        branch_condition_i,
   // control signals forwarded to datapath and memory
   output logic        set_a_zero_o,
   output logic [1:0]  mem_to_reg_o,
   output logic [2:0]  load_type_o,
   output alu_op_t     alu_op_o,
   output logic        alu_src_b_o,
   output logic        alu_src_a_o,
   output logic        rd_we_o,
   output logic        pc_next_sel_o,
   output logic [3:0]  data_mem_we_o,
   output logic [1:0]  branch_op_o,
   // control signals for forwarding
   output fwd_a_t      alu_forward_a_o,
   output fwd_b_t      alu_forward_b_o,
   // control signals for flushing
   output logic        if_id_flush_o,
   output logic        id_ex_flush_o,
   // control signals for stalling
   input  logic        instr_mem_ready_i,   // 0 = IF-stage access outstanding
   input  logic        data_mem_ready_i,    // 0 = MEM-stage access outstanding
   output logic        data_mem_en_o,       // 1 = MEM stage has a genuine load/store this cycle
   output logic        pc_en_o,
   output logic        if_id_en_o,
   output logic        id_ex_en_o,
   output logic        ex_mem_en_o,
   output logic        mem_wb_en_o
);

   //********** REGISTER CONTROL ***************
   logic       if_id_en_s;
   logic       if_id_flush_s;
   logic       id_ex_flush_s;

   // raw hazard_unit outputs, arbitrated together with the stall inputs by stall_unit
   logic       hazard_pc_en_s;
   logic       hazard_if_id_en_s;
   logic       hazard_control_pass_s;
   logic       data_mem_access_s;
   logic       id_ex_en_s;
   logic       ex_mem_en_s;
   logic       mem_wb_en_s;

   //*********  INSTRUCTION DECODE **************
   logic [1:0] branch_type_id_s;
   logic [2:0] funct3_id_s;
   logic [6:0] funct7_id_s;
   logic [1:0] alu_2bit_op_id_s;
   logic       set_a_zero_id_s;

   logic       control_pass_s;
   logic       rs1_in_use_id_s;
   logic       rs2_in_use_id_s;
   logic       alu_src_a_id_s;
   logic       alu_src_b_id_s;

   logic       data_mem_we_id_s;
   logic       rd_we_id_s;
   logic [1:0] mem_to_reg_id_s;
   logic [4:0] rs1_address_id_s;
   logic [4:0] rs2_address_id_s;
   logic [4:0] rd_address_id_s;

   //*********       EXECUTE       **************
   logic [1:0] branch_type_ex_s;
   logic [2:0] funct3_ex_s;
   logic [6:0] funct7_ex_s;
   logic [1:0] alu_2bit_op_ex_s;
   logic       set_a_zero_ex_s;

   logic       alu_src_a_ex_s;
   logic       alu_src_b_ex_s;

   logic       data_mem_we_ex_s;
   logic       rd_we_ex_s;
   logic [1:0] mem_to_reg_ex_s;

   logic [4:0] rs1_address_ex_s;
   logic [4:0] rs2_address_ex_s;
   logic [4:0] rd_address_ex_s;
   logic       bcc_ex_s;
   logic       branch_conf_ex_s;

   //*********       MEMORY        **************
   logic [2:0] funct3_mem_s;
   logic       data_mem_we_mem_s;
   logic       rd_we_mem_s;
   logic [1:0] mem_to_reg_mem_s;

   logic [4:0] rd_address_mem_s;

   //*********      WRITEBACK      **************
   logic [2:0] funct3_wb_s;
   logic       rd_we_wb_s;
   logic [1:0] mem_to_reg_wb_s;
   logic [4:0] rd_address_wb_s;

   //*********** Combinational logic ******************

   // branch condition complement
   // when branch instruction is executing:
   //    '0' -> beq blt bltu
   //    '1' -> bne bge bgeu  (opposite, complement of adequate comparison)
   assign bcc_ex_s    = funct3_ex_s[0];

   assign branch_op_o = funct3_ex_s[2:1];

   // extract operation and operand data from instruction
   assign rs1_address_id_s = instruction_i[19:15];
   assign rs2_address_id_s = instruction_i[24:20];
   assign rd_address_id_s  = instruction_i[11:7];

   assign funct7_id_s = instruction_i[31:25];
   assign funct3_id_s = instruction_i[14:12];

   // decoder that decides which bytes are written to memory
   assign data_mem_we_o = (data_mem_we_mem_s == 1'b1 && funct3_mem_s == 3'b000) ? 4'b0001 :  // sb
                          (data_mem_we_mem_s == 1'b1 && funct3_mem_s == 3'b001) ? 4'b0011 :  // sh
                          (data_mem_we_mem_s == 1'b1 && funct3_mem_s == 3'b010) ? 4'b1111 :  // sw
                          4'b0000;

   // branch confirmed, 1 if branch is going to be taken,
   // based on branch condition and branch complement bit
   assign branch_conf_ex_s = branch_condition_i ^ bcc_ex_s;

   // this process covers conditional and unconditional branches
   // based on which branch is executing:
   //    control pc_next mux
   //    flush appropriate registers in pipeline
   always_comb begin : pc_next_if_p
      if ((branch_type_ex_s == 2'b10) ||
          (branch_type_ex_s == 2'b01 && branch_conf_ex_s == 1'b1) ||
          (branch_type_ex_s == 2'b11)) begin
         pc_next_sel_o = 1'b1;
         if_id_flush_s = 1'b1;
         id_ex_flush_s = 1'b1;
      end
      else begin
         if_id_flush_s = 1'b0;
         id_ex_flush_s = 1'b0;
         pc_next_sel_o = 1'b0;
      end
   end

   //*********** Sequential logic ******************

   // ID/EX register
   // reset is checked before the id_ex_en_s hold gate so a reset can never
   // be masked by an in-progress mem_stall (see stall_unit.sv); when
   // id_ex_en_s is low (mem_stall), neither branch below executes and the
   // register holds -- a same-cycle bubble/flush request is simply
   // re-evaluated once unstalled.
   always_ff @(posedge clk) begin : id_ex
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            branch_type_ex_s <= '0;
            funct3_ex_s      <= '0;
            funct7_ex_s      <= '0;
            set_a_zero_ex_s  <= 1'b0;
            alu_src_a_ex_s   <= 1'b0;
            alu_src_b_ex_s   <= 1'b0;
            mem_to_reg_ex_s  <= '0;
            alu_2bit_op_ex_s <= '0;
            rs1_address_ex_s <= '0;
            rs2_address_ex_s <= '0;
            rd_address_ex_s  <= '0;
            rd_we_ex_s       <= 1'b0;
            data_mem_we_ex_s <= 1'b0;
         end
         else if (id_ex_en_s == 1'b1) begin
            if (control_pass_s == 1'b0 || id_ex_flush_s == 1'b1) begin
               branch_type_ex_s <= '0;
               funct3_ex_s      <= '0;
               funct7_ex_s      <= '0;
               set_a_zero_ex_s  <= 1'b0;
               alu_src_a_ex_s   <= 1'b0;
               alu_src_b_ex_s   <= 1'b0;
               mem_to_reg_ex_s  <= '0;
               alu_2bit_op_ex_s <= '0;
               rs1_address_ex_s <= '0;
               rs2_address_ex_s <= '0;
               rd_address_ex_s  <= '0;
               rd_we_ex_s       <= 1'b0;
               data_mem_we_ex_s <= 1'b0;
            end
            else begin
               branch_type_ex_s <= branch_type_id_s;
               funct7_ex_s      <= funct7_id_s;
               funct3_ex_s      <= funct3_id_s;
               set_a_zero_ex_s  <= set_a_zero_id_s;
               alu_src_a_ex_s   <= alu_src_a_id_s;
               alu_src_b_ex_s   <= alu_src_b_id_s;
               mem_to_reg_ex_s  <= mem_to_reg_id_s;
               alu_2bit_op_ex_s <= alu_2bit_op_id_s;
               rs1_address_ex_s <= rs1_address_id_s;
               rs2_address_ex_s <= rs2_address_id_s;
               rd_address_ex_s  <= rd_address_id_s;
               rd_we_ex_s       <= rd_we_id_s;
               data_mem_we_ex_s <= data_mem_we_id_s;
            end
         end
         // else: id_ex_en_s == 0 -> hold (mem_stall in progress)
      end
   end

   // EX/MEM register (reset checked before the new ex_mem_en_s hold gate)
   always_ff @(posedge clk) begin : ex_mem
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            funct3_mem_s      <= '0;
            data_mem_we_mem_s <= 1'b0;
            rd_we_mem_s       <= 1'b0;
            mem_to_reg_mem_s  <= '0;
            rd_address_mem_s  <= '0;
         end
         else if (ex_mem_en_s == 1'b1) begin
            funct3_mem_s      <= funct3_ex_s;
            data_mem_we_mem_s <= data_mem_we_ex_s;
            rd_we_mem_s       <= rd_we_ex_s;
            mem_to_reg_mem_s  <= mem_to_reg_ex_s;
            rd_address_mem_s  <= rd_address_ex_s;
         end
         // else: ex_mem_en_s == 0 -> hold (mem_stall in progress)
      end
   end

   // MEM/WB register (reset checked before the new mem_wb_en_s hold gate)
   always_ff @(posedge clk) begin : mem_wb
      if (ce == 1'b1) begin
         if (reset == 1'b0) begin
            funct3_wb_s     <= '0;
            rd_we_wb_s      <= 1'b0;
            mem_to_reg_wb_s <= '0;
            rd_address_wb_s <= '0;
         end
         else if (mem_wb_en_s == 1'b1) begin
            funct3_wb_s     <= funct3_mem_s;
            rd_we_wb_s      <= rd_we_mem_s;
            mem_to_reg_wb_s <= mem_to_reg_mem_s;
            rd_address_wb_s <= rd_address_mem_s;
         end
         // else: mem_wb_en_s == 0 -> hold (mem_stall in progress)
      end
   end

   //*********** Instantiation ******************

   // Control decoder
   ctrl_decoder ctrl_dec (
      .opcode_i      (instruction_i[6:0]),
      .branch_type_o (branch_type_id_s),
      .mem_to_reg_o  (mem_to_reg_id_s),
      .data_mem_we_o (data_mem_we_id_s),
      .alu_src_b_o   (alu_src_b_id_s),
      .alu_src_a_o   (alu_src_a_id_s),
      .set_a_zero_o  (set_a_zero_id_s),
      .rd_we_o       (rd_we_id_s),
      .rs1_in_use_o  (rs1_in_use_id_s),
      .rs2_in_use_o  (rs2_in_use_id_s),
      .alu_2bit_op_o (alu_2bit_op_id_s)
   );

   // ALU decoder
   alu_decoder alu_dec (
      .alu_2bit_op_i (alu_2bit_op_ex_s),
      .funct3_i      (funct3_ex_s),
      .funct7_i      (funct7_ex_s),
      .alu_op_o      (alu_op_o)
   );

   // Forwarding unit
   forwarding_unit forwarding_u (
      .rd_we_mem_i      (rd_we_mem_s),
      .rd_address_mem_i (rd_address_mem_s),
      .rd_we_wb_i       (rd_we_wb_s),
      .rd_address_wb_i  (rd_address_wb_s),
      .rs1_address_ex_i (rs1_address_ex_s),
      .rs2_address_ex_i (rs2_address_ex_s),
      .alu_forward_a_o  (alu_forward_a_o),
      .alu_forward_b_o  (alu_forward_b_o)
   );

   // Hazard unit
   hazard_unit hazard_u (
      .rs1_address_id_i (rs1_address_id_s),
      .rs2_address_id_i (rs2_address_id_s),
      .rs1_in_use_i     (rs1_in_use_id_s),
      .rs2_in_use_i     (rs2_in_use_id_s),

      .rd_address_ex_i  (rd_address_ex_s),
      .mem_to_reg_ex_i  (mem_to_reg_ex_s),

      .pc_en_o          (hazard_pc_en_s),
      .if_id_en_o       (hazard_if_id_en_s),
      .control_pass_o   (hazard_control_pass_s)
   );

   // MEM-stage instruction is a genuine load/store this cycle
   assign data_mem_access_s = data_mem_we_mem_s | (mem_to_reg_mem_s == 2'b10);

   // Stall unit: combines the load-use hazard stall (above) with the
   // external I$/D$ ready signals into the final pipeline enables
   stall_unit stall_u (
      .hazard_pc_en_i        (hazard_pc_en_s),
      .hazard_if_id_en_i     (hazard_if_id_en_s),
      .hazard_control_pass_i (hazard_control_pass_s),
      .instr_mem_ready_i     (instr_mem_ready_i),
      .data_mem_ready_i      (data_mem_ready_i),
      .data_mem_access_i     (data_mem_access_s),
      .pc_en_o               (pc_en_o),
      .if_id_en_o            (if_id_en_s),
      .control_pass_o        (control_pass_s),
      .id_ex_en_o            (id_ex_en_s),
      .ex_mem_en_o           (ex_mem_en_s),
      .mem_wb_en_o           (mem_wb_en_s)
   );

   //********** Outputs **************

   // forward control signals to datapath
   assign if_id_en_o    = if_id_en_s;
   assign id_ex_en_o    = id_ex_en_s;
   assign ex_mem_en_o   = ex_mem_en_s;
   assign mem_wb_en_o   = mem_wb_en_s;
   assign data_mem_en_o = data_mem_access_s;
   assign mem_to_reg_o  = mem_to_reg_wb_s;
   assign alu_src_b_o   = alu_src_b_ex_s;
   assign alu_src_a_o   = alu_src_a_ex_s;
   assign set_a_zero_o  = set_a_zero_ex_s;
   assign rd_we_o       = rd_we_wb_s;
   assign if_id_flush_o = if_id_flush_s;
   assign id_ex_flush_o = id_ex_flush_s;

   // load_type controls which bytes are taken from memory in wb stage
   assign load_type_o = funct3_wb_s;

endmodule : control_path
