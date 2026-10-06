# Step 2: five-stage pipeline

**Purpose:** overlap instructions in a five-stage pipeline and handle the hazards this creates, while producing exactly the same results as step 1. There is still no TLB and no exception handling.

| Folder | File | Role |
|---|---|---|
| `design/` | `RiSC.v` | pipelined CPU (new for this step) |
| | `memories.v` | memory and register file |
| `software/` | `prog.s` | the same program as step 1 |
| `testbench/` | `test.v` | the same testbench as step 1 |
| `logs/` | `prog.log`, `summary.txt` | output of `run.sh` |

```
./run.sh
```

## The design

```
IF -> [IFID] -> ID -> [IDEX] -> EX -> [EXMEM] -> MEM -> [MEMWB] -> WB
```

| Stage | Work |
|---|---|
| IF | read `mem[PC]` |
| ID | decode, read registers, forward, resolve `bne` and `jalr` |
| EX | ALU; `lui` and `jalr` pass op0 (the immediate or pc + 1) through |
| MEM | load or store |
| WB | write the register file |

What the pipeline adds to step 1:

- **Forwarding.** If an older instruction still in EX, MEM or WB writes a register that ID reads, ID takes the value from that stage instead of the stale register file. The youngest producer wins.
- **Load-use stall.** A `lw` in EX has no data yet, so an instruction in ID that needs it waits one cycle: PC and IF/ID hold, and a bubble (`add r0,r0,r0`) goes into EX.
- **Branch squash.** `bne` and `jalr` resolve in ID. When one redirects the PC, the instruction just fetched behind it is wrong and is replaced with a zero word.
- **Halt.** When `halt` decodes, fetching stops. The machine halts when `halt` reaches WB, after every older instruction has finished.

## The log

One line per clock: what each stage holds (its PC, plus the instruction in ID), the value written back, `STALL` / `SQUASH` / `HALT` markers, and the registers. The load-use stall:

```
cycle  26  IF 000a | ID 0009 5604 nand | EX 0008 lw   | MEM 0007 sw   | WB 0006 r0=0000  STALL
cycle  27  IF 000a | ID 0009 5604 nand | EX 0009 add  | MEM 0008 lw   | WB 0007 r0=0010
cycle  28  IF 000b | ID 000a 7800 lui  | EX 0009 nand | MEM 0009 add  | WB 0008 r4=000f
```

At cycle 26 `nand r5, r4, r4` needs r4 from the `lw` in EX, so it waits. At cycle 27 the bubble (`add`) is in EX and the `lw` is in MEM, from where the loaded value is forwarded. At cycle 28 `nand` executes.

A taken branch:

```
cycle   7  IF 0007 | ID 0006 c87d bne  | EX 0005 addi | ...          SQUASH
cycle   8  IF 0004 | ID 0000 0000 add  | EX 0006 bne  | ...
```

The instruction at 0x0007, fetched behind the `bne`, is discarded, and fetching restarts at the loop head 0x0004.

## Result

```
prog: halted after 39 cycles; r1-r7 = 1234 0000 000f 0010 fff0 000e 000d; mem[data] = 000f; expected values: yes
        pipeline events: 1 stall, 6 squashed fetches
```

The results are identical to step 1. The 39 cycles are the same 28 instructions, plus 4 cycles to fill the pipeline, 1 stall, 6 squashed fetches, and the cycles that empty it after `halt`.
