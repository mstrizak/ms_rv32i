//-----------------------------------------------------------------------------
// dcache.sv
// Write-back, write-allocate, blocking, 4-way set-associative data cache.
// 4KB total: 32 sets x 4 ways x 32B (8-word) lines, true-LRU (2-bit rank
// per way per set, a 0..3 permutation, 3=MRU/0=LRU).
// Address breakdown (byte address): tag[31:10] | index[9:5] | offset[4:2]
//
// Same two timing lessons learned from icache.sv apply here:
//  - Hit detection (for ready_o) is COMBINATIONAL off address_i, not
//    registered -- otherwise the pipeline could commit to advancing past
//    the current MEM-stage access before knowing it was about to miss.
//  - The registered read-data path is gated by en_i (data_mem_en_o), like
//    sync_mem.sv's own enable-gated capture, so it correctly holds during
//    any freeze rather than silently tracking address_i regardless.
//
// A miss retries naturally: address_i/we_i/write_i are frozen (mem_stall
// holds EX/MEM/WB) for as long as the miss is in progress, so once the
// requested line is loaded and LOOKUP re-evaluates the same (unchanged)
// request, it simply hits and -- for a store -- performs the write that
// cycle. No separate "replay the store after fill" logic is needed.
//-----------------------------------------------------------------------------

module dcache (
   input  logic        clk,
   input  logic        reset,          // active-low, synchronous
   // core-facing (mirrors sync_mem.sv, plus en_i/ready_o)
   input  logic        en_i,           // data_mem_en_o: genuine load/store this cycle
   input  logic [3:0]  we_i,
   input  logic [31:0] address_i,
   input  logic [31:0] write_i,
   output logic [31:0] read_o,
   output logic        ready_o,
   // backing memory (sync_mem.sv contract)
   output logic [31:0] mem_address_o,
   output logic        mem_en_o,
   output logic [3:0]  mem_we_o,
   output logic [31:0] mem_write_o,
   input  logic [31:0] mem_read_i
);

   localparam int NUM_SETS    = 32;
   localparam int INDEX_BITS  = 5;
   localparam int OFFSET_BITS = 3;
   localparam int TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS - 2;

   localparam [1:0] LOOKUP    = 2'd0;
   localparam [1:0] WRITEBACK = 2'd1;
   localparam [1:0] FILL      = 2'd2;

   // per-way storage arrays (BRAM-inferable: one always_ff per array)
   logic [TAG_BITS-1:0] tag_mem   [0:3][0:NUM_SETS-1];
   logic                valid_mem [0:3][0:NUM_SETS-1];
   logic                dirty_mem [0:3][0:NUM_SETS-1];
   logic [31:0]         data_mem  [0:3][0:(NUM_SETS*8)-1];
   logic [1:0]          rank_mem  [0:3][0:NUM_SETS-1];

   logic [INDEX_BITS-1:0] index_s;
   logic [2:0]            word_s;
   assign index_s = address_i[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];
   assign word_s  = address_i[OFFSET_BITS+1:2];

   // ---- combinational hit detection (see header) ----
   logic hit0_s, hit1_s, hit2_s, hit3_s, hit_s;
   assign hit0_s = valid_mem[0][index_s] && (tag_mem[0][index_s] == address_i[31:32-TAG_BITS]);
   assign hit1_s = valid_mem[1][index_s] && (tag_mem[1][index_s] == address_i[31:32-TAG_BITS]);
   assign hit2_s = valid_mem[2][index_s] && (tag_mem[2][index_s] == address_i[31:32-TAG_BITS]);
   assign hit3_s = valid_mem[3][index_s] && (tag_mem[3][index_s] == address_i[31:32-TAG_BITS]);
   assign hit_s  = hit0_s || hit1_s || hit2_s || hit3_s;

   logic [1:0] hit_way_s;
   always_comb begin
      if (hit0_s)      hit_way_s = 2'd0;
      else if (hit1_s) hit_way_s = 2'd1;
      else if (hit2_s) hit_way_s = 2'd2;
      else             hit_way_s = 2'd3;
   end

   // ---- registered read-data path, gated by en_i (see header) ----
   logic [1:0]  hit_way_prev_s;
   logic [31:0] way_data_r_s [0:3];

   always_ff @(posedge clk) begin
      if (en_i) begin
         hit_way_prev_s  <= hit_way_s;
         way_data_r_s[0] <= data_mem[0][{index_s, word_s}];
         way_data_r_s[1] <= data_mem[1][{index_s, word_s}];
         way_data_r_s[2] <= data_mem[2][{index_s, word_s}];
         way_data_r_s[3] <= data_mem[3][{index_s, word_s}];
      end
   end

   assign read_o = way_data_r_s[hit_way_prev_s];

   // ---- LRU victim selection: prefer any invalid way, else true-LRU rank0 ----
   logic [1:0] victim_way_s;
   always_comb begin
      if (!valid_mem[0][index_s])      victim_way_s = 2'd0;
      else if (!valid_mem[1][index_s]) victim_way_s = 2'd1;
      else if (!valid_mem[2][index_s]) victim_way_s = 2'd2;
      else if (!valid_mem[3][index_s]) victim_way_s = 2'd3;
      else if (rank_mem[0][index_s] == 2'd0) victim_way_s = 2'd0;
      else if (rank_mem[1][index_s] == 2'd0) victim_way_s = 2'd1;
      else if (rank_mem[2][index_s] == 2'd0) victim_way_s = 2'd2;
      else                                   victim_way_s = 2'd3;
   end

   // ---- FSM state ----
   logic [1:0]             state_s;
   logic [3:0]             fill_cnt_s;      // 0..9 (issue 8, capture-last+commit, settle)
   logic [3:0]             wb_cnt_s;        // 0..7 (write back 8 words)
   logic [31:0]            fill_base_addr_s;
   logic [31:0]            wb_base_addr_s;
   logic [INDEX_BITS-1:0]  fill_index_s;
   logic [TAG_BITS-1:0]    fill_tag_s;
   logic [1:0]             fill_way_s;
   logic [3:0]             capture_word_full_s;
   logic [OFFSET_BITS-1:0] capture_word_s;

   assign capture_word_full_s = fill_cnt_s - 4'd1;
   assign capture_word_s      = capture_word_full_s[OFFSET_BITS-1:0];

   // updates the true-LRU rank vector for `index`, marking `way` as MRU
   task automatic touch_rank(input logic [INDEX_BITS-1:0] idx, input logic [1:0] way);
      logic [1:0] old_rank;
      begin
         case (way)
            2'd0: old_rank = rank_mem[0][idx];
            2'd1: old_rank = rank_mem[1][idx];
            2'd2: old_rank = rank_mem[2][idx];
            default: old_rank = rank_mem[3][idx];
         endcase
         if (way != 2'd0) begin
            if (rank_mem[0][idx] > old_rank) rank_mem[0][idx] <= rank_mem[0][idx] - 2'd1;
         end
         if (way != 2'd1) begin
            if (rank_mem[1][idx] > old_rank) rank_mem[1][idx] <= rank_mem[1][idx] - 2'd1;
         end
         if (way != 2'd2) begin
            if (rank_mem[2][idx] > old_rank) rank_mem[2][idx] <= rank_mem[2][idx] - 2'd1;
         end
         if (way != 2'd3) begin
            if (rank_mem[3][idx] > old_rank) rank_mem[3][idx] <= rank_mem[3][idx] - 2'd1;
         end
         case (way)
            2'd0: rank_mem[0][idx] <= 2'd3;
            2'd1: rank_mem[1][idx] <= 2'd3;
            2'd2: rank_mem[2][idx] <= 2'd3;
            default: rank_mem[3][idx] <= 2'd3;
         endcase
      end
   endtask

   always_ff @(posedge clk) begin
      if (reset == 1'b0) begin
         state_s    <= LOOKUP;
         fill_cnt_s <= '0;
         wb_cnt_s   <= '0;
         for (int w = 0; w < 4; w++) begin
            for (int i = 0; i < NUM_SETS; i++) begin
               valid_mem[w][i] <= 1'b0;
               dirty_mem[w][i] <= 1'b0;
               rank_mem[w][i]  <= w[1:0];
            end
         end
      end
      else begin
         case (state_s)
            LOOKUP: begin
               if (en_i && !hit_s) begin
                  fill_base_addr_s <= {address_i[31:OFFSET_BITS+2], {(OFFSET_BITS+2){1'b0}}};
                  fill_index_s     <= index_s;
                  fill_tag_s       <= address_i[31:32-TAG_BITS];
                  fill_way_s       <= victim_way_s;

                  if (valid_mem[victim_way_s][index_s] && dirty_mem[victim_way_s][index_s]) begin
                     state_s        <= WRITEBACK;
                     wb_cnt_s       <= '0;
                     wb_base_addr_s <= {tag_mem[victim_way_s][index_s], index_s, {(OFFSET_BITS+2){1'b0}}};
                  end
                  else begin
                     state_s    <= FILL;
                     fill_cnt_s <= '0;
                  end
               end
               else if (en_i && hit_s) begin
                  touch_rank(index_s, hit_way_s);
                  if (we_i[0]) data_mem[hit_way_s][{index_s, word_s}][7:0]   <= write_i[7:0];
                  if (we_i[1]) data_mem[hit_way_s][{index_s, word_s}][15:8]  <= write_i[15:8];
                  if (we_i[2]) data_mem[hit_way_s][{index_s, word_s}][23:16] <= write_i[23:16];
                  if (we_i[3]) data_mem[hit_way_s][{index_s, word_s}][31:24] <= write_i[31:24];
                  if (we_i != 4'b0000)
                     dirty_mem[hit_way_s][index_s] <= 1'b1;
               end
            end

            WRITEBACK: begin
               if (wb_cnt_s == 4'd7)
                  state_s <= FILL;
               fill_cnt_s <= '0;
               wb_cnt_s   <= wb_cnt_s + 4'd1;
            end

            FILL: begin
               if (fill_cnt_s >= 4'd1 && fill_cnt_s <= 4'd8)
                  data_mem[fill_way_s][{fill_index_s, capture_word_s}] <= mem_read_i;

               if (fill_cnt_s == 4'd8) begin
                  tag_mem[fill_way_s][fill_index_s]   <= fill_tag_s;
                  valid_mem[fill_way_s][fill_index_s] <= 1'b1;
                  dirty_mem[fill_way_s][fill_index_s] <= 1'b0;
                  touch_rank(fill_index_s, fill_way_s);
                  fill_cnt_s <= 4'd9;
               end
               else if (fill_cnt_s == 4'd9) begin
                  state_s <= LOOKUP;
               end
               else begin
                  fill_cnt_s <= fill_cnt_s + 4'd1;
               end
            end
         endcase
      end
   end

   // ---- backing memory port ----
   assign mem_address_o = (state_s == WRITEBACK) ? (wb_base_addr_s + {26'b0, wb_cnt_s, 2'b00})
                                                  : (fill_base_addr_s + {26'b0, fill_cnt_s[2:0], 2'b00});
   assign mem_en_o = (state_s == WRITEBACK && wb_cnt_s < 4'd8) ||
                     (state_s == FILL      && fill_cnt_s < 4'd8);
   assign mem_we_o = (state_s == WRITEBACK && wb_cnt_s < 4'd8) ? 4'b1111 : 4'b0000;
   assign mem_write_o = data_mem[fill_way_s][{fill_index_s, wb_cnt_s[2:0]}];

   assign ready_o = (state_s == LOOKUP) && (!en_i || hit_s);

endmodule : dcache
