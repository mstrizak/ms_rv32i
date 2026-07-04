//-----------------------------------------------------------------------------
// tb_top_riscv.sv
// Generic regression harness for TOP_RISCV.
//
// Runtime plusargs (no recompilation needed between tests):
//   +HEXFILE=path       instruction image, loaded into imem word array   (required)
//   +EXPFILE=path       expected data-memory results, word 0,1,2,...     (required)
//   +CYCLES=N           cycles to run before checking (default 300)
//   +MIDRESET_CYCLE=N   if >=0, pulses reset low for 1 cycle at cycle N (default: disabled)
//   +VCDFILE=path       waveform dump path (default sim/work/wave.vcd)
//   +TRACE              if present, prints PC each cycle
//
// Pass/fail is generic: each test program ends by SW-ing its result words
// to data memory addresses 0,4,8,...; the matching .expect file lists the
// expected hex values in the same order. Any expect entries left at their
// default 'x are treated as "not checked".
//-----------------------------------------------------------------------------

module tb_top_riscv;

   localparam int IMEM_ADDR_WIDTH = 10;   // 1024 words = 4KB
   localparam int DMEM_ADDR_WIDTH = 10;   // 1024 words = 4KB
   localparam int EXPECT_DEPTH    = 64;

   logic        clk;
   logic        ce;
   logic        reset;

   logic [31:0] instr_mem_address_s;
   logic [31:0] instr_mem_read_s;
   logic        instr_mem_flush_s;
   logic        instr_mem_en_s;

   logic [31:0] data_mem_address_s;
   logic [31:0] data_mem_read_s;
   logic [31:0] data_mem_write_s;
   logic [3:0]  data_mem_we_s;

   logic        instr_mem_ready_s;
   logic        data_mem_ready_s;
   logic        data_mem_en_s;

   string       hexfile_s;
   string       expfile_s;
   int          cycles_s;
   int          midreset_cycle_s;
   string       vcdfile_s;
   int          trace_en_s;
   int          imem_stall_cycle_s;
   int          imem_stall_len_s;
   int          dmem_stall_cycle_s;
   int          dmem_stall_len_s;

   int          cycle_count_s;
   int          errors_s;
   logic [31:0] expect_mem_s [0:EXPECT_DEPTH-1];

   //*********** Clock / reset ****************
   initial clk = 1'b0;
   always #5 clk = ~clk;

   //*********** DUT ****************
   TOP_RISCV dut (
      .clk                  (clk),
      .ce                   (ce),
      .reset                (reset),
      .instr_mem_address_o  (instr_mem_address_s),
      .instr_mem_read_i     (instr_mem_read_s),
      .instr_mem_flush_o    (instr_mem_flush_s),
      .instr_mem_en_o       (instr_mem_en_s),
      .instr_mem_ready_i    (instr_mem_ready_s),
      .data_mem_address_o   (data_mem_address_s),
      .data_mem_read_i      (data_mem_read_s),
      .data_mem_write_o     (data_mem_write_s),
      .data_mem_we_o        (data_mem_we_s),
      .data_mem_en_o        (data_mem_en_s),
      .data_mem_ready_i     (data_mem_ready_s)
   );

   stall_injector imem_stall_1 (
      .clk           (clk),
      .reset         (reset),
      .start_cycle_i (imem_stall_cycle_s),
      .length_i      (imem_stall_len_s),
      .ready_o       (instr_mem_ready_s)
   );

   stall_injector dmem_stall_1 (
      .clk           (clk),
      .reset         (reset),
      .start_cycle_i (dmem_stall_cycle_s),
      .length_i      (dmem_stall_len_s),
      .ready_o       (data_mem_ready_s)
   );

   sync_imem #(
      .ADDR_WIDTH (IMEM_ADDR_WIDTH)
   ) imem_1 (
      .clk     (clk),
      .en_i    (instr_mem_en_s),
      .flush_i (instr_mem_flush_s),
      .addr_i  (instr_mem_address_s),
      .rdata_o (instr_mem_read_s)
   );

   sync_mem #(
      .ADDR_WIDTH (DMEM_ADDR_WIDTH)
   ) dmem_1 (
      .clk     (clk),
      .en_i    (1'b1),
      .we_i    (data_mem_we_s),
      .addr_i  (data_mem_address_s),
      .wdata_i (data_mem_write_s),
      .rdata_o (data_mem_read_s)
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
         cycles_s = 300;
      if (!$value$plusargs("MIDRESET_CYCLE=%d", midreset_cycle_s))
         midreset_cycle_s = -1;
      if (!$value$plusargs("VCDFILE=%s", vcdfile_s))
         vcdfile_s = "sim/work/wave.vcd";
      trace_en_s = $test$plusargs("TRACE");
      if (!$value$plusargs("IMEM_STALL_CYCLE=%d", imem_stall_cycle_s))
         imem_stall_cycle_s = 0;
      if (!$value$plusargs("IMEM_STALL_LEN=%d", imem_stall_len_s))
         imem_stall_len_s = 0;
      if (!$value$plusargs("DMEM_STALL_CYCLE=%d", dmem_stall_cycle_s))
         dmem_stall_cycle_s = 0;
      if (!$value$plusargs("DMEM_STALL_LEN=%d", dmem_stall_len_s))
         dmem_stall_len_s = 0;

      $dumpfile(vcdfile_s);
      $dumpvars(0, tb_top_riscv);

      $readmemh(hexfile_s, imem_1.mem_1.mem);
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
            $display("[%0d] pc=%08h instr=%08h imem_ready=%0b dmem_en=%0b dmem_ready=%0b",
                      cycle_count_s, instr_mem_address_s, instr_mem_read_s,
                      instr_mem_ready_s, data_mem_en_s, data_mem_ready_s);
         if (cycle_count_s == midreset_cycle_s) begin
            reset = 1'b0;
            @(posedge clk);
            reset = 1'b1;
            cycle_count_s++;
         end
      end

      do_checks();

      if (errors_s == 0)
         $display("REGRESSION PASS");
      else
         $display("REGRESSION FAIL: %0d error(s)", errors_s);

      $finish;
   end

   task automatic do_checks();
      int idx;
      logic [31:0] actual;
      idx = 0;
      while (idx < EXPECT_DEPTH && !$isunknown(expect_mem_s[idx])) begin
         actual = dmem_1.mem[idx];
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

endmodule : tb_top_riscv
