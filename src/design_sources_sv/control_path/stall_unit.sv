//-----------------------------------------------------------------------------
// stall_unit.sv
// Centralizes pipeline freeze/bubble arbitration on top of hazard_unit's
// existing load-use stall. hazard_unit is unmodified; this module combines
// its outputs with the new I$/D$ "not ready" stand-ins.
//
// Two structurally different responses:
//  - bubble: stage advances every cycle but with cleared/NOP content.
//    Correct for the load-use hazard and for an IF-side miss (if_stall) --
//    nothing valid is lost by clearing ID while PC/IF-ID retry.
//  - hold/freeze: register does not change at all, because it holds
//    genuinely valid in-flight work. Required for a MEM-side miss
//    (mem_stall) -- must not clear anything, and must freeze PC through
//    MEM/WB simultaneously so no younger instruction overtakes the
//    stalled older one.
//
// mem_stall always wins because id_ex_en/ex_mem_en/mem_wb_en are the OUTER
// gate on their registers (same pattern control_path's if_id already uses
// for if_id_en): when an enable is 0, neither the clear-condition nor the
// capture-condition executes, so a same-cycle branch-flush or load-use
// bubble is simply suppressed and re-evaluated identically once unstalled.
//-----------------------------------------------------------------------------

module stall_unit (
   // from hazard_unit, unchanged semantics
   input  logic hazard_pc_en_i,
   input  logic hazard_if_id_en_i,
   input  logic hazard_control_pass_i,
   // stand-ins for future I$/D$ "not ready" signals
   input  logic instr_mem_ready_i,     // 0 = IF-stage access outstanding
   input  logic data_mem_ready_i,      // 0 = MEM-stage access outstanding
   input  logic data_mem_access_i,     // 1 = MEM-stage instruction is a load or store
   // final enables
   output logic pc_en_o,
   output logic if_id_en_o,
   output logic control_pass_o,
   output logic id_ex_en_o,
   output logic ex_mem_en_o,
   output logic mem_wb_en_o
);

   logic if_stall_s, mem_stall_s;

   assign if_stall_s  = ~instr_mem_ready_i;
   assign mem_stall_s = data_mem_access_i & ~data_mem_ready_i;

   assign pc_en_o        = hazard_pc_en_i    & ~if_stall_s & ~mem_stall_s;
   assign if_id_en_o     = hazard_if_id_en_i & ~if_stall_s & ~mem_stall_s;
   assign control_pass_o = hazard_control_pass_i & ~if_stall_s;

   assign id_ex_en_o  = ~mem_stall_s;
   assign ex_mem_en_o = ~mem_stall_s;
   assign mem_wb_en_o = ~mem_stall_s;

endmodule : stall_unit
