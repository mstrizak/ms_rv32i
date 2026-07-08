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
//
// redirect_i (if_id_flush_s | id_ex_flush_s from control_path) overrides
// if_stall: a taken branch/jump makes the in-flight IF-side access moot
// (its result will be discarded), and since id_ex_en is NOT gated by
// if_stall, the branch resolving in EX during an unrelated I$ miss would
// otherwise pulse pc_next_sel_o/the flush signals for exactly one cycle
// while pc_en/if_id_en stay frozen -- silently dropping the redirect
// forever, since that pulse is gone by the time if_stall eventually clears.
// Forcing pc_en/if_id_en high that cycle lets the redirect land immediately;
// the memory-side (I$) is responsible for tolerating its outstanding access
// being abandoned when this happens.
//
// control_pass_o is NOT gated by if_stall (a real, latent Phase 1 bug fixed
// here once a real I$ miss could expose it): if_stall only freezes PC/IF-ID,
// it does not freeze ID/EX, so whatever instruction is already sitting in ID
// is still expected to advance into EX normally every cycle, exactly as if
// there were no if_stall at all -- hazard_control_pass_i's bubble-vs-capture
// decision reflects the load-use hazard only and must stand on its own.
// Gating it by if_stall silently replaced perfectly valid, hazard-free
// instructions with bubbles any time they tried to leave ID while an
// unrelated later fetch was stalled -- invisible with the Phase 0/1
// synthetic stall_injector (whose hand-picked windows never happened to
// land on this overlap) but real cache misses hit it immediately, since a
// multi-cycle miss vastly outlasts a single instruction's one-cycle ID
// residency.
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
   input  logic redirect_i,            // 1 = a branch/jump is redirecting the PC this cycle
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

   assign pc_en_o        = hazard_pc_en_i    & (~if_stall_s | redirect_i) & ~mem_stall_s;
   assign if_id_en_o     = hazard_if_id_en_i & (~if_stall_s | redirect_i) & ~mem_stall_s;
   assign control_pass_o = hazard_control_pass_i;

   assign id_ex_en_o  = ~mem_stall_s;
   assign ex_mem_en_o = ~mem_stall_s;
   assign mem_wb_en_o = ~mem_stall_s;

endmodule : stall_unit
