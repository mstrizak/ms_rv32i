//-----------------------------------------------------------------------------
// stall_injector.sv
// TB-only (non-synthesizable) fake slow-memory model. Holds ready_o low for
// a configurable window of absolute cycles counted from reset release,
// independent of any core signal -- deliberately NOT derived from the
// core's own en/access strobes, since those already depend on the ready
// signal this module drives (a same-cycle combinational loop otherwise).
// Directed tests pick the window empirically (via +TRACE) to land on a
// specific instruction's IF or MEM cycle.
//
// start_cycle_i == 0 permanently disables this instance (ready_o == 1
// always), which is the state every Phase 0 test runs in -- the regression
// argument that Phase 1 doesn't disturb Phase 0 behavior.
//-----------------------------------------------------------------------------

module stall_injector (
   input  logic        clk,
   input  logic        reset,          // active-low, synchronous
   input  logic [31:0] start_cycle_i,  // first cycle to hold ready low; 0 = disabled
   input  logic [31:0] length_i,       // number of cycles to hold ready low
   output logic        ready_o
);

   logic [31:0] cycle_count_s;
   logic        stalling_s;

   always_ff @(posedge clk) begin
      if (reset == 1'b0)
         cycle_count_s <= 32'd0;
      else
         cycle_count_s <= cycle_count_s + 32'd1;
   end

   assign stalling_s = (start_cycle_i != 32'd0) &&
                       (cycle_count_s >= start_cycle_i) &&
                       (cycle_count_s < start_cycle_i + length_i);

   assign ready_o = ~stalling_s;

endmodule : stall_injector
