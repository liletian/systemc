//
// testbench for RiSC.v -- compile with +define+PHASE1, PHASE2 or PHASE3
//
//   PHASE1: init.sys_i at 0, init.usr_i at 0, ASID 0 (no translation)
//   PHASE2: init.sys_i at 0, init.usr_i at 0x300, ASID 9, TLB-A preloaded (9:00 -> 03)
//   PHASE3: init.sys.important at 0, init_3.usr at 0x300, ASID 9, TLB-B preloaded (0:c9 -> 02)
//
module top;
	reg	clk, reset;

	RiSC	risc (.clk(clk), .reset(reset));

	initial begin
		clk = 0; reset = 1;
		#2 clk = 1;
		#3 clk = 0;
		forever #5 clk = ~clk;
	end

	initial begin
`ifdef PHASE1
		$readmemh("init.sys_i", risc.MEM.m);
		$readmemh("init.usr_i", risc.MEM.m, 16'h0000);
`elsif PHASE2
		$readmemh("init.sys_i", risc.MEM.m);
		$readmemh("init.usr_i", risc.MEM.m, 16'h0300);
`else
		$readmemh("init.sys.important", risc.MEM.m);
		$readmemh("init_3.usr", risc.MEM.m, 16'h0300);
`endif
		#3 reset = 0;
`ifndef PHASE1
		risc.RF.cr[4] = 16'h0009;		// user process, ASID 9
`endif
`ifdef PHASE2
		risc.TLB.tlbregA_v.m = 1'b1;
		risc.TLB.tlbregA_asid.m = 6'd9;
		risc.TLB.tlbregA_vpn.m = 8'h00;
		risc.TLB.tlbregA_pfn.m = 8'h03;
`endif
`ifdef PHASE3
		risc.TLB.tlbregB_v.m = 1'b1;		// kernel PTE page (vpn c9) lives in frame 2
		risc.TLB.tlbregB_asid.m = 6'd0;
		risc.TLB.tlbregB_vpn.m = 8'hc9;
		risc.TLB.tlbregB_pfn.m = 8'h02;
`endif
		#5000 $display("timeout"); $finish;
	end
endmodule
