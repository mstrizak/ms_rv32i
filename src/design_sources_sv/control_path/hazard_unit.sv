//-----------------------------------------------------------------------------
// hazard_unit.sv
// SystemVerilog conversion of hazard_unit.vhd
// Stalls the pipeline for one cycle on a load-use hazard
//-----------------------------------------------------------------------------

module hazard_unit (
   // inputs
   input  logic [4:0] rs1_address_id_i,
   input  logic [4:0] rs2_address_id_i,
   input  logic       rs1_in_use_i,
   input  logic       rs2_in_use_i,
   input  logic [4:0] rd_address_ex_i,
   input  logic [1:0] mem_to_reg_ex_i,
   // control outputs
   output logic       pc_en_o,
   output logic       if_id_en_o,
   output logic       control_pass_o
);

   logic en_s;

   // stalls pipeline when hazard is detected by setting enable signals to zero
   always_comb begin : hazard_det
      // Load in EX stage is producing a value that is used by the
      // instruction currently in ID stage => stall the pipeline
      if ((((rs1_address_id_i == rd_address_ex_i) && (rs1_in_use_i == 1'b1)) ||
           ((rs2_address_id_i == rd_address_ex_i) && (rs2_in_use_i == 1'b1))) &&
          (mem_to_reg_ex_i == 2'b10))
         en_s = 1'b0;
      else
         // default, don't do anything
         en_s = 1'b1;
   end

   // if '0' stalls pc register
   assign pc_en_o        = en_s;
   // if '0' stalls if/id register and instruction memory
   assign if_id_en_o     = en_s;
   // when pipeline needs to stall this output is set to '0':
   //    flushes control signals in ID/EX stage to stop them from changing anything
   assign control_pass_o = en_s;

endmodule : hazard_unit
