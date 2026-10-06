//
// testbench for steps 1 and 2: load prog.hex at address 0, run until the CPU
// sets "halted", then print the registers and the data word
//
// +define+DATA=<address of the label "data"> selects the memory word to print
//
module top ();
	reg	clk, reset;

	RiSC	cpu (clk, reset);

	initial begin
		clk = 0;
		reset = 1;
		$readmemh("prog.hex", cpu.MEM.m);
		#12 reset = 0;
		#5000 $display("TIMEOUT: no halt after 500 cycles");
		$finish;
	end

	always #5 clk = ~clk;

	always @(posedge clk) begin
		if (!reset && cpu.halted) begin
			$display("HALT after %0d cycles", cpu.cycle);
			$display("final regs r1-r7: %h %h %h %h %h %h %h",
				cpu.RF.m[1], cpu.RF.m[2], cpu.RF.m[3], cpu.RF.m[4], cpu.RF.m[5], cpu.RF.m[6], cpu.RF.m[7]);
			$display("mem[%h] (data) = %h", `DATA, cpu.MEM.m[`DATA]);
			$finish;
		end
	end
endmodule
