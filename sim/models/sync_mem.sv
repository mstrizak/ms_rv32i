//-----------------------------------------------------------------------------
// sync_mem.sv
// Word-addressed synchronous memory, single always_ff block (BRAM-inferable).
// Byte write-enable encoding matches control_path.sv's data_mem_we_o
// (0001=SB, 0011=SH, 1111=SW). Read has 1-cycle latency, registered output.
//-----------------------------------------------------------------------------

module sync_mem #(
   parameter int    ADDR_WIDTH = 12,     // word-address bits -> 2**ADDR_WIDTH words
   parameter        INIT_FILE  = ""      // $readmemh path, "" = zero-init
)(
   input  logic         clk,
   input  logic         en_i,
   input  logic [3:0]   we_i,
   input  logic [31:0]  addr_i,          // byte address, addr_i[1:0] ignored
   input  logic [31:0]  wdata_i,
   output logic [31:0]  rdata_o
);

   logic [31:0] mem [0:(1<<ADDR_WIDTH)-1];
   logic [31:0] rdata_reg_s;

   initial begin
      if (INIT_FILE != "")
         $readmemh(INIT_FILE, mem);
   end

   always_ff @(posedge clk) begin
      if (en_i) begin
         if (we_i[0]) mem[addr_i[ADDR_WIDTH+1:2]][7:0]   <= wdata_i[7:0];
         if (we_i[1]) mem[addr_i[ADDR_WIDTH+1:2]][15:8]  <= wdata_i[15:8];
         if (we_i[2]) mem[addr_i[ADDR_WIDTH+1:2]][23:16] <= wdata_i[23:16];
         if (we_i[3]) mem[addr_i[ADDR_WIDTH+1:2]][31:24] <= wdata_i[31:24];
         rdata_reg_s <= mem[addr_i[ADDR_WIDTH+1:2]];
      end
   end

   assign rdata_o = rdata_reg_s;

endmodule : sync_mem
