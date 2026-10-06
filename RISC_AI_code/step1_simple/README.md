# Step 1: single-cycle RiSC-16

**Purpose:** the simplest correct implementation of the base instruction set, one instruction per clock. It is the baseline the pipeline in step 2 must agree with.

| Folder | File | Role |
|---|---|---|
| `design/` | `RiSC.v` | single-cycle CPU (new for this step) |
| | `memories.v` | memory (`three_port_aram`) and register file (`three_port_aregfile`) |
| `software/` | `prog.s` | test program |
| `testbench/` | `test.v` | loads `prog.hex` at 0, runs until `halted`, prints registers and the data word |
| `logs/` | `prog.log`, `summary.txt` | output of `run.sh` |

```
./run.sh
```

## The design

Each clock does the whole instruction:
1. fetch `mem[pc]` on memory port 1 and split it into op, rA, rB, rC and the immediate;
2. read rB, and rC (for `add`/`nand`) or rA (everything else);
3. compute: `add`, `nand`, `lui` (immediate into the top 10 bits), or rB + immediate for `addi`, `lw` and `sw`;
4. load or store on memory port 2;
5. write rA (with the ALU result, the loaded word, or pc + 1 for `jalr`) and choose the next PC: pc + 1, the `bne` target, or rB for `jalr`.

Any extended opcode-7 instruction (`halt`) stops the machine.

## The test program

`prog.s` uses every base instruction:

| Lines | Instructions | Checks |
|---|---|---|
| `movi r1, 0x1234` | `lui` + `addi` | large immediates |
| loop | `add`, `addi`, `bne` taken 4×, not taken 1× | arithmetic and branches; r3 = 5+4+3+2+1 |
| `sw` / `lw` / `nand` | store, load, then use the loaded value at once | memory, and in step 2 the load-use stall |
| `movi r6, sub`, `jalr r7, r6`, `jalr r0, r7` | call and return | `jalr` link and jump |

Expected at halt: r1-r7 = `1234 0000 000f 0010 fff0 000e 000d`, and `mem[0x0010]` = `000f`.

## The log

One line per clock: the PC, the instruction, its decoded fields, and the registers *before* it executes. For example, the loop's branch:

```
cycle   6  pc=0006  instr=c87d  bne  rA=2 rB=0 rC=5 imm=fffd   regs 1234 0004 0005 0000 0000 0000 0000
cycle   7  pc=0004  instr=0d82  add  rA=3 rB=3 rC=2 imm=0002   regs 1234 0004 0005 0000 0000 0000 0000
```

## Result

```
prog: halted after 28 cycles; r1-r7 = 1234 0000 000f 0010 fff0 000e 000d; mem[data] = 000f; expected values: yes
```

28 cycles for 28 instructions executed: exactly one per clock.
