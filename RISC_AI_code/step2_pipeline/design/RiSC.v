//
// Step 2: five-stage pipelined RiSC-16
//
//   IF  -> IFID  -> ID -> IDEX -> EX -> EXMEM -> MEM -> MEMWB -> WB
//
// Same instruction set as step 1 (no TLB, no exceptions). What the pipeline adds:
//   - forwarding: ID takes a source operand from EX, MEM or WB when an older
//     instruction still in flight writes that register
//   - load-use stall: one bubble when ID needs the result of a lw that is in EX
//   - branches and jalr resolve in ID; the instruction fetched behind a taken
//     one is squashed (replaced with a zero word, which is add r0,r0,r0)
//   - halt: when halt decodes, fetching stops; the machine halts when it
//     reaches WB, after every older instruction has completed
//
// Uses three_port_aram and three_port_aregfile from memories.v.
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

	// ---------------------------------------------------------------- state
	reg	[15:0]	PC;
	reg		fetch_stop;			// a halt has been decoded

	reg	[15:0]	IFID_instr, IFID_pc;

	reg	[2:0]	IDEX_op, IDEX_rT;
	reg	[15:0]	IDEX_op0, IDEX_op1, IDEX_op2, IDEX_pc;
	reg		IDEX_halt;

	reg	[2:0]	EXMEM_op, EXMEM_rT;
	reg	[15:0]	EXMEM_alu, EXMEM_st, EXMEM_pc;
	reg		EXMEM_halt;

	reg	[2:0]	MEMWB_rT;
	reg	[15:0]	MEMWB_data, MEMWB_pc;
	reg		MEMWB_halt;

	reg		halted;
	integer		cycle;

	// ---------------------------------------------------------------- IF
	wire	[15:0]	imem;

	// ---------------------------------------------------------------- ID
	wire	[2:0]	op = IFID_instr[15:13];
	wire	[2:0]	rA = IFID_instr[12:10];
	wire	[2:0]	rB = IFID_instr[9:7];
	wire	[2:0]	rC = IFID_instr[2:0];
	wire	[6:0]	im = IFID_instr[6:0];
	wire	[15:0]	simm = { {9{im[6]}}, im };
	wire	[15:0]	uimm = { IFID_instr[9:0], 6'd0 };
	wire		id_jalr = (op == `JALR) & (im == 7'd0);
	wire		id_halt = (op == `JALR) & (im != 7'd0);
	wire		id_writes = (op == `ADD) | (op == `ADDI) | (op == `NAND) | (op == `LUI) | (op == `LW) | id_jalr;

	wire	[2:0]	src1 = rB;
	wire	[2:0]	src2 = (op == `ADD || op == `NAND) ? rC : rA;
	wire	[15:0]	rf1, rf2;

	three_port_aregfile	RF (.on(reset), .clk(clk), .abus1(src1), .dbus1(rf1), .abus2(src2), .dbus2(rf2),
				.abus3(MEMWB_rT), .dbus3(MEMWB_data), .we(1'b1));	// rT = 0 means no write

	wire	[15:0]	ALU_out, MEM_out;

	// forwarding, youngest producer first
	wire	[15:0]	val1 =	(src1 != 0 && IDEX_rT  == src1) ? ALU_out :
				(src1 != 0 && EXMEM_rT == src1) ? MEM_out :
				(src1 != 0 && MEMWB_rT == src1) ? MEMWB_data :
				rf1;
	wire	[15:0]	val2 =	(src2 != 0 && IDEX_rT  == src2) ? ALU_out :
				(src2 != 0 && EXMEM_rT == src2) ? MEM_out :
				(src2 != 0 && MEMWB_rT == src2) ? MEMWB_data :
				rf2;

	// a lw in EX cannot forward yet: hold IF and ID for one cycle
	wire		stall = (IDEX_op == `LW) && (IDEX_rT != 0) &&
				((src1 != 0 && IDEX_rT == src1) || (src2 != 0 && IDEX_rT == src2));

	wire		taken = (op == `BNE) && (val1 != val2);
	wire		stomp = id_jalr | taken;			// squash the instruction behind it
	wire	[15:0]	next_pc = id_jalr ? val1 :
				  taken   ? IFID_pc + 16'd1 + simm :
				  PC + 16'd1;

	wire	[15:0]	op0 =	(op == `LUI) ? uimm :
				(op == `ADDI || op == `LW || op == `SW) ? simm :
				IFID_pc + 16'd1;			// jalr's return address

	// ---------------------------------------------------------------- EX
	wire	[15:0]	alu1 = (IDEX_op == `LUI || IDEX_op == `JALR) ? IDEX_op0 : IDEX_op1;
	wire	[15:0]	alu2 = (IDEX_op == `ADD || IDEX_op == `NAND) ? IDEX_op2 : IDEX_op0;
	wire	[2:0]	func = (IDEX_op == `ADDI || IDEX_op == `LW || IDEX_op == `SW) ? `ADD : IDEX_op;
	assign	ALU_out = (func == `ADD)  ? alu1 + alu2 :
			  (func == `NAND) ? ~(alu1 & alu2) :
			  alu1;					// lui, jalr

	// ---------------------------------------------------------------- MEM
	wire	[15:0]	dmem;
	three_port_aram		MEM (.clk(clk), .abus1(PC), .dbus1(imem), .abus2(EXMEM_alu), .dbus2o(dmem),
				.dbus2i(EXMEM_st), .we(EXMEM_op == `SW && !reset));
	assign	MEM_out = (EXMEM_op == `LW) ? dmem : EXMEM_alu;

	// ---------------------------------------------------------------- clock
	always @(posedge clk) begin
		if (reset) begin
			PC <= 0; fetch_stop <= 0; halted <= 0; cycle = 0;
			IFID_instr <= 0; IFID_pc <= 0;
			IDEX_op <= `ADD; IDEX_rT <= 0; IDEX_op0 <= 0; IDEX_op1 <= 0; IDEX_op2 <= 0; IDEX_pc <= 0; IDEX_halt <= 0;
			EXMEM_op <= `ADD; EXMEM_rT <= 0; EXMEM_alu <= 0; EXMEM_st <= 0; EXMEM_pc <= 0; EXMEM_halt <= 0;
			MEMWB_rT <= 0; MEMWB_data <= 0; MEMWB_pc <= 0; MEMWB_halt <= 0;
		end
		else if (!halted) begin
			show;
			cycle = cycle + 1;

			// IF and IF/ID
			if (!stall) begin
				if (!fetch_stop && !id_halt) PC <= next_pc;
				IFID_instr <= (stomp || fetch_stop || id_halt) ? 16'd0 : imem;
				IFID_pc    <= (stomp || fetch_stop || id_halt) ? 16'd0 : PC;
				if (id_halt) fetch_stop <= 1;
			end

			// ID/EX: a bubble while stalled
			IDEX_op   <= stall ? `ADD : op;
			IDEX_rT   <= (stall || !id_writes) ? 3'd0 : rA;
			IDEX_op0  <= op0;
			IDEX_op1  <= val1;
			IDEX_op2  <= val2;
			IDEX_pc   <= IFID_pc;
			IDEX_halt <= !stall && id_halt;

			// EX/MEM
			EXMEM_op   <= IDEX_op;
			EXMEM_rT   <= IDEX_rT;
			EXMEM_alu  <= ALU_out;
			EXMEM_st   <= IDEX_op2;			// rA, the value a sw stores
			EXMEM_pc   <= IDEX_pc;
			EXMEM_halt <= IDEX_halt;

			// MEM/WB
			MEMWB_rT   <= EXMEM_rT;
			MEMWB_data <= MEM_out;
			MEMWB_pc   <= EXMEM_pc;
			MEMWB_halt <= EXMEM_halt;

			// WB
			if (MEMWB_halt) halted <= 1;
		end
	end

	// one line per cycle: what each stage holds, then the register file
	task show;
		$display("cycle %3d  IF %h | ID %h %h %-4s | EX %h %-4s | MEM %h %-4s | WB %h r%0d=%h%s%s%s   regs %h %h %h %h %h %h %h",
			cycle, PC, IFID_pc, IFID_instr, name(op, im), IDEX_pc, name(IDEX_op, IDEX_halt ? 7'd1 : 7'd0),
			EXMEM_pc, name(EXMEM_op, EXMEM_halt ? 7'd1 : 7'd0), MEMWB_pc, MEMWB_rT, MEMWB_data,
			stall ? "  STALL" : "", stomp ? "  SQUASH" : "", MEMWB_halt ? "  HALT" : "",
			RF.m[1], RF.m[2], RF.m[3], RF.m[4], RF.m[5], RF.m[6], RF.m[7]);
	endtask

	function [8*4:1] name;
		input [2:0] op;
		input [6:0] im;
		case (op)
			`ADD:	name = "add";
			`ADDI:	name = "addi";
			`NAND:	name = "nand";
			`LUI:	name = "lui";
			`SW:	name = "sw";
			`LW:	name = "lw";
			`BNE:	name = "bne";
			default: name = (im == 7'd0) ? "jalr" : "halt";
		endcase
	endfunction
endmodule
