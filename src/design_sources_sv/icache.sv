//-----------------------------------------------------------------------------
// icache.sv
// Read-only, blocking, 2-way set-associative instruction cache.
// 4KB total: 64 sets x 2 ways x 32B (8-word) lines, 1-bit-per-set LRU.
// Address breakdown (byte address): tag[31:11] | index[10:5] | offset[4:2]
//
// Core-facing port mirrors sim/models/sync_imem.sv's exact contract,
// including the combinational flush-to-zero override (read_o forced to 0
// whenever flush_i is asserted, regardless of hit/miss/fill state) -- this
// is what makes the pipeline's redirect-during-miss fix (stall_unit.sv's
// redirect_i) sufficient with no extra "pending flush" latch needed here.
//
// On a miss, the FILL state runs to completion unconditionally even if the
// core's address_i changes mid-fill (a redirect can force pc_en/if_id_en
// high despite ready_o=0, see stall_unit.sv) -- the old fill is harmless
// background work; LOOKUP simply re-evaluates the (possibly new) address_i
// once FILL finishes.
//-----------------------------------------------------------------------------

module icache (
   input  logic        clk,
   input  logic        reset,          // active-low, synchronous
   // core-facing (mirrors sync_imem.sv)
   input  logic        en_i,           // instr_mem_en_o (if_id_en) from the core
   input  logic        flush_i,
   input  logic [31:0] address_i,
   output logic [31:0] read_o,
   output logic        ready_o,
   // backing memory (sync_mem.sv contract, read-only use)
   output logic [31:0] mem_address_o,
   output logic        mem_en_o,
   input  logic [31:0] mem_read_i
);

   localparam int NUM_SETS   = 64;
   localparam int INDEX_BITS = 6;
   localparam int OFFSET_BITS = 3;
   localparam int TAG_BITS   = 32 - INDEX_BITS - OFFSET_BITS - 2;

   localparam LOOKUP = 1'b0;
   localparam FILL   = 1'b1;

   // per-way storage arrays (BRAM-inferable: one always_ff per array)
   logic [TAG_BITS-1:0] tag_mem0 [0:NUM_SETS-1];
   logic [TAG_BITS-1:0] tag_mem1 [0:NUM_SETS-1];
   logic                valid_mem0 [0:NUM_SETS-1];
   logic                valid_mem1 [0:NUM_SETS-1];
   logic [31:0]         data_mem0 [0:(NUM_SETS*8)-1];
   logic [31:0]         data_mem1 [0:(NUM_SETS*8)-1];
   logic                lru_mem [0:NUM_SETS-1];         // 0 = way0 is LRU, 1 = way1 is LRU

   logic [INDEX_BITS-1:0] index_s;
   assign index_s = address_i[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];

   // Hit detection is COMBINATIONAL (same cycle as address_i), not registered.
   // This is what lets ready_o correctly gate whether the pipeline may
   // advance PAST the address it is presenting *this* cycle: pc_en is
   // computed this same cycle, so if hit detection lagged by a cycle (as an
   // earlier draft did), the core would already commit to moving past an
   // address before knowing it was about to miss, permanently losing that
   // fetch. Tag/valid arrays are small enough to read combinationally.
   logic hit0_s, hit1_s, hit_s;
   assign hit0_s = valid_mem0[index_s] && (tag_mem0[index_s] == address_i[31:32-TAG_BITS]);
   assign hit1_s = valid_mem1[index_s] && (tag_mem1[index_s] == address_i[31:32-TAG_BITS]);
   assign hit_s  = hit0_s || hit1_s;

   // Data output still has the ORIGINAL 1-cycle registered latency (matching
   // sync_imem's contract): decode consumes read_o the cycle *after* the
   // corresponding address was presented, so registering a same-cycle-valid
   // hit0_s/hit1_s (rather than re-deriving it from a delayed tag compare)
   // is sufficient and avoids re-introducing the timing bug above.
   //
   // Gated by en_i, exactly like sync_imem.sv's rdata_reg_s: when the core
   // isn't advancing IF/ID (en_i=0 -- a load-use hazard bubble, or any other
   // reason if_id_en drops), this must HOLD its previous output rather than
   // keep tracking address_i, which can (and does, e.g. under a load-use
   // hazard) keep changing even while en_i=0. Without this gate, read_o
   // would silently skip past the instruction hazard_unit needs to see held
   // stable for the bubble cycle.
   logic        hit0_prev_s, hit1_prev_s;
   logic [31:0] way0_data_r_s, way1_data_r_s;
   logic [31:0] hit_data_s;

   always_ff @(posedge clk) begin
      if (en_i) begin
         hit0_prev_s   <= hit0_s;
         hit1_prev_s   <= hit1_s;
         way0_data_r_s <= data_mem0[{index_s, address_i[OFFSET_BITS+1:2]}];
         way1_data_r_s <= data_mem1[{index_s, address_i[OFFSET_BITS+1:2]}];
      end
   end

   assign hit_data_s = hit0_prev_s ? way0_data_r_s : way1_data_r_s;

   logic                   state_s;
   logic [3:0]             fill_cnt_s;      // 0..8 (9 states: issue 8 words, capture last one)
   logic [31:0]            fill_base_addr_s;
   logic [INDEX_BITS-1:0]  fill_index_s;
   logic [TAG_BITS-1:0]    fill_tag_s;
   logic                   fill_way_s;
   logic [3:0]             capture_word_full_s;
   logic [OFFSET_BITS-1:0] capture_word_s;

   assign capture_word_full_s = fill_cnt_s - 4'd1;
   assign capture_word_s      = capture_word_full_s[OFFSET_BITS-1:0];

   always_ff @(posedge clk) begin
      if (reset == 1'b0) begin
         state_s    <= LOOKUP;
         fill_cnt_s <= '0;
         for (int i = 0; i < NUM_SETS; i++) begin
            valid_mem0[i] <= 1'b0;
            valid_mem1[i] <= 1'b0;
            lru_mem[i]    <= 1'b0;
         end
      end
      else begin
         case (state_s)
            LOOKUP: begin
               if (!hit_s) begin
                  state_s          <= FILL;
                  fill_cnt_s       <= '0;
                  fill_base_addr_s <= {address_i[31:OFFSET_BITS+2], {(OFFSET_BITS+2){1'b0}}};
                  fill_index_s     <= index_s;
                  fill_tag_s       <= address_i[31:32-TAG_BITS];
                  fill_way_s       <= lru_mem[index_s];
               end
               else begin
                  // update LRU: the way that just hit becomes MRU
                  lru_mem[index_s] <= hit0_s ? 1'b1 : 1'b0;
               end
            end

            FILL: begin
               // capture word (fill_cnt_s - 1), returned this cycle by the backing
               // memory (issued the previous cycle)
               if (fill_cnt_s >= 4'd1 && fill_cnt_s <= 4'd8) begin
                  if (fill_way_s == 1'b0)
                     data_mem0[{fill_index_s, capture_word_s}] <= mem_read_i;
                  else
                     data_mem1[{fill_index_s, capture_word_s}] <= mem_read_i;
               end

               if (fill_cnt_s == 4'd8) begin
                  // word 7 just captured above this same cycle -- commit tag/valid/lru
                  if (fill_way_s == 1'b0) begin
                     tag_mem0[fill_index_s]   <= fill_tag_s;
                     valid_mem0[fill_index_s] <= 1'b1;
                  end
                  else begin
                     tag_mem1[fill_index_s]   <= fill_tag_s;
                     valid_mem1[fill_index_s] <= 1'b1;
                  end
                  lru_mem[fill_index_s] <= ~fill_way_s;
                  fill_cnt_s             <= 4'd9;
               end
               else if (fill_cnt_s == 4'd9) begin
                  // settle cycle: gives the registered data readout one clear
                  // cycle where the commit write above and its own read are
                  // not on the same edge, before LOOKUP starts relying on it
                  // (hit0_s/hit1_s themselves are combinational off tag/valid,
                  // so they don't need this -- only the data path does).
                  state_s <= LOOKUP;
               end
               else begin
                  fill_cnt_s <= fill_cnt_s + 4'd1;
               end
            end
         endcase
      end
   end

   // backing memory port: present word (fill_cnt_s) of the missed line while issuing
   assign mem_address_o = fill_base_addr_s + {29'b0, fill_cnt_s[2:0], 2'b00};
   assign mem_en_o       = (state_s == FILL) && (fill_cnt_s < 4'd8);

   // core-facing output: combinational flush override, regardless of state
   assign read_o  = flush_i ? 32'h0 : hit_data_s;
   assign ready_o = (state_s == LOOKUP) && hit_s;

endmodule : icache
