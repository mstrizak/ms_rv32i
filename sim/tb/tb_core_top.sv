//-----------------------------------------------------------------------------
// tb_core_top.sv
// Generic regression harness for core_top (TOP_RISCV + icache + dcache).
// Same plusarg/check machinery as tb_top_riscv.sv, but drives the
// cache-enabled wrapper instead of the bare core -- reuses the exact same
// .hex/.expect test programs as a no-regression gate, plus new cache-
// specific tests. There is no synthetic stall_injector here: real cache
// misses are what drive instr_mem_ready_s/data_mem_ready_s low.
//
// Runtime plusargs:
//   +HEXFILE=path       instruction image, loaded into the icache's backing
//                       memory word array                                (required)
//   +EXPFILE=path       expected data-memory results, word 0,1,2,...      (required)
//   +CYCLES=N           cycles to run before checking (default 500 --
//                       cache fills are slower than the bare-core tests)
//   +MIDRESET_CYCLE=N   if >=0, pulses reset low for 1 cycle at cycle N (default: disabled)
//   +VCDFILE=path       waveform dump path (default sim/work/wave.vcd)
//   +TRACE              if present, prints PC/ready/dcache state each cycle
//-----------------------------------------------------------------------------

module tb_core_top;

   localparam int EXPECT_DEPTH = 64;

   logic clk;
   logic ce;
   logic reset;

   string hexfile_s;
   string expfile_s;
   int    cycles_s;
   int    midreset_cycle_s;
   string vcdfile_s;
   int    trace_en_s;

   int          cycle_count_s;
   int          errors_s;
   logic [31:0] expect_mem_s [0:EXPECT_DEPTH-1];

   //*********** Clock / reset ****************
   initial clk = 1'b0;
   always #5 clk = ~clk;

   //*********** DUT ****************
   core_top dut (
      .clk   (clk),
      .ce    (ce),
      .reset (reset)
   );

   //*********** Stimulus / checking ****************
   initial begin : main
      if (!$value$plusargs("HEXFILE=%s", hexfile_s)) begin
         $display("ERROR: +HEXFILE=<path> is required");
         $finish;
      end
      if (!$value$plusargs("EXPFILE=%s", expfile_s)) begin
         $display("ERROR: +EXPFILE=<path> is required");
         $finish;
      end
      if (!$value$plusargs("CYCLES=%d", cycles_s))
         cycles_s = 500;
      if (!$value$plusargs("MIDRESET_CYCLE=%d", midreset_cycle_s))
         midreset_cycle_s = -1;
      if (!$value$plusargs("VCDFILE=%s", vcdfile_s))
         vcdfile_s = "sim/work/wave.vcd";
      trace_en_s = $test$plusargs("TRACE");

      $dumpfile(vcdfile_s);
      $dumpvars(0, tb_core_top);

      $readmemh(hexfile_s, dut.imem_backing_1.mem);
      $readmemh(expfile_s, expect_mem_s);

      ce            = 1'b1;
      reset         = 1'b0;
      cycle_count_s = 0;
      errors_s      = 0;

      @(posedge clk);
      @(posedge clk);
      reset = 1'b1;

      while (cycle_count_s < cycles_s) begin
         @(posedge clk);
         cycle_count_s++;
         if (trace_en_s)
            $display("[%0d] pc=%08h instr=%08h iready=%0b dmem_en=%0b dready=%0b daddr=%08h dwr=%0b dwdata=%08h",
                      cycle_count_s, dut.instr_mem_address_s, dut.instr_mem_read_s,
                      dut.instr_mem_ready_s, dut.data_mem_en_s, dut.data_mem_ready_s,
                      dut.data_mem_address_s, dut.data_mem_we_s, dut.data_mem_write_s);
         if (cycle_count_s == midreset_cycle_s) begin
            reset = 1'b0;
            @(posedge clk);
            reset = 1'b1;
            cycle_count_s++;
         end
      end

      if (trace_en_s) begin
         for (int w = 0; w < 4; w++)
            $display("dcache set0 way%0d: valid=%0b dirty=%0b tag=%06h rank=%0d data0..2=%08h %08h %08h",
                      w, dut.dcache_1.valid_mem[w][0], dut.dcache_1.dirty_mem[w][0],
                      dut.dcache_1.tag_mem[w][0], dut.dcache_1.rank_mem[w][0],
                      dut.dcache_1.data_mem[w][0], dut.dcache_1.data_mem[w][1], dut.dcache_1.data_mem[w][2]);
      end

      do_checks();

      if (errors_s == 0)
         $display("REGRESSION PASS");
      else
         $display("REGRESSION FAIL: %0d error(s)", errors_s);

      $finish;
   end

   // Reads the architectural value of data-memory word `idx` (0,1,2,...).
   // dcache.sv is write-back: a dirty store can live ONLY in the cache until
   // evicted, so checking dut.dmem_backing_1.mem[idx] directly is wrong
   // whenever the line is still resident -- peek the dcache's own arrays
   // first (mirroring its tag/index/offset breakdown) and only fall back to
   // the backing memory if the line isn't cached.
   function automatic logic [31:0] read_mem_word(int idx);
      logic [31:0] byte_addr;
      logic [4:0]  index;
      logic [21:0] tag;
      logic [2:0]  offset;
      byte_addr = idx << 2;
      tag       = byte_addr[31:10];
      index     = byte_addr[9:5];
      offset    = byte_addr[4:2];
      for (int w = 0; w < 4; w++) begin
         if (dut.dcache_1.valid_mem[w][index] && dut.dcache_1.tag_mem[w][index] == tag)
            return dut.dcache_1.data_mem[w][{index, offset}];
      end
      return dut.dmem_backing_1.mem[idx];
   endfunction

   task automatic do_checks();
      int idx;
      logic [31:0] actual;
      idx = 0;
      while (idx < EXPECT_DEPTH && !$isunknown(expect_mem_s[idx])) begin
         actual = read_mem_word(idx);
         if (actual !== expect_mem_s[idx]) begin
            $display("FAIL: mem[%0d] = %08h (expected %08h)", idx, actual, expect_mem_s[idx]);
            errors_s++;
         end
         else begin
            $display("PASS: mem[%0d] = %08h", idx, actual);
         end
         idx++;
      end
      if (idx == 0)
         $display("WARNING: no expect entries found in %s", expfile_s);
   endtask

endmodule : tb_core_top
