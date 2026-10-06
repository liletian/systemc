//
// Step 1: single-cycle RiSC-16
//
// One instruction per clock, no pipeline. Every instruction reads its
// operands, computes, accesses memory and writes back within one cycle.
// Base instruction set only: add addi nand lui sw lw bne jalr, plus halt
// (any extended opcode-7 instruction stops the machine).
//
// Uses three_port_aram (memory) and three_port_aregfile (registers, r0 = 0)
// from memories.v.
//

`define ADD	3'd0
`define ADDI	3'd1
`define NAND	3'd2
`define LUI	3'd3
`define SW	3'd4
`define LW	3'd5
`define BNE	3'd6
`define JALR	3'd7

module RiSC (clk, reset);
	input	clk;
	input	reset;

	reg	[15:0]	pc;
	reg		halted;		// set once a halt has executed; the testbench watches it
	integer		cycle;

	//
	// fetch and decode
	//
	wire	[15:0]	instr;
	wire	[2:0]	op = instr[15:13];
	wire	[2:0]	rA = instr[12:10];
	wire	[2:0]	rB = instr[9:7];
	wire	[2:0]	rC = instr[2:0];
	wire	[6:0]	im = instr[6:0];
	wire	[15:0]	simm = { {9{im[6]}}, im };		// 7-bit signed immediate
	wire	[15:0]	uimm = { instr[9:0], 6'd0 };		// lui: 10-bit immediate into the top bits
	wire		is_jalr = (op == `JALR) & (im == 7'd0);
	wire		is_halt = (op == `JALR) & (im != 7'd0);

	//
	// register file: port 1 reads rB, port 2 reads rC (add, nand) or rA (everything else)
	//
	wire	[2:0]	src2 = (op == `ADD || op == `NAND) ? rC : rA;
	wire	[15:0]	valB, val2;
	wire	[15:0]	wdata;
	wire		rf_we = ~halted & ~reset &
				((op == `ADD) | (op == `ADDI) | (op == `NAND) | (op == `LUI) | (op == `LW) | is_jalr);

	three_port_aregfile	RF (.on(reset), .clk(clk), .abus1(rB), .dbus1(valB), .abus2(src2), .dbus2(val2),
				.abus3(rA), .dbus3(wdata), .we(rf_we));

	//
	// ALU
	//
	wire	[15:0]	alu =	(op == `ADD)  ? valB + val2 :
				(op == `NAND) ? ~(valB & val2) :
				(op == `LUI)  ? uimm :
				valB + simm;			// addi, and the address for lw / sw

	//
	// memory: port 1 fetches, port 2 loads and stores
	//
	wire	[15:0]	dmem;
	three_port_aram		MEM (.clk(clk), .abus1(pc), .dbus1(instr), .abus2(alu), .dbus2o(dmem),
				.dbus2i(val2), .we((op == `SW) & ~halted & ~reset));

	assign	wdata =	(op == `LW) ? dmem :
			is_jalr     ? pc + 16'd1 :
			alu;

	//
	// next PC
	//
	wire		taken = (op == `BNE) & (val2 != valB);	// bne compares rA and rB
	wire	[15:0]	next_pc = is_jalr ? valB :
				  taken   ? pc + 16'd1 + simm :
				  pc + 16'd1;

	always @(posedge clk) begin
		if (reset) begin
			pc <= 16'd0;
			halted <= 1'b0;
			cycle = 0;
		end
		else if (!halted) begin
			$display("cycle %3d  pc=%h  instr=%h  %-4s rA=%0d rB=%0d rC=%0d imm=%h   regs %h %h %h %h %h %h %h",
				cycle, pc, instr, mnemonic(op, im), rA, rB, rC, (op == `LUI) ? uimm : simm,
				RF.m[1], RF.m[2], RF.m[3], RF.m[4], RF.m[5], RF.m[6], RF.m[7]);
			cycle = cycle + 1;
			if (is_halt)
				halted <= 1'b1;
			else
				pc <= next_pc;
		end
	end

	function [8*4:1] mnemonic;
		input [2:0] op;
		input [6:0] im;
		case (op)
			`ADD:	mnemonic = "add";
			`ADDI:	mnemonic = "addi";
			`NAND:	mnemonic = "nand";
			`LUI:	mnemonic = "lui";
			`SW:	mnemonic = "sw";
			`LW:	mnemonic = "lw";
			`BNE:	mnemonic = "bne";
			default: mnemonic = (im == 7'd0) ? "jalr" : "halt";
		endcase
	endfunction
endmodule
