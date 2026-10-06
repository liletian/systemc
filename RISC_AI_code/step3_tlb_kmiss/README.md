# Step 3: TLB, exceptions and the kernel TLB-miss handler

**Purpose:** add virtual memory and exceptions to the pipeline, then handle the simplest kind of TLB miss: a miss by the kernel itself, which needs only one memory lookup to resolve.

| Folder | File | Role |
|---|---|---|
| `design/` | `RiSC.v` | the full pipeline: TLB, user/kernel modes, exceptions, `tlbw`, `rfe` |
| | `memories.v` | memory, the two-bank register file and the PSR |
| `software/` | `sys-i.s`, `usr-i.s` | test 3a: vector table and `trap_halt`; a user `halt` |
| | `sys-ii.s`, `usr-ii.s` | test 3b: the same programs (identical to the stage-i files) |
| | `sys-kmiss.s` | test 3c: kernel test code, root page tables, `tlbkmiss` (new for this step) |
| `testbench/` | `test-i.v`, `test-ii.v` | course testbenches |
| | `test-kmiss.v` | starts in kernel mode with an empty TLB (new for this step) |
| `logs/` | `<test>.log`, `<test>.timeline.txt`, `summary.txt` | output of `run.sh` |

```
./run.sh
```

What the full `RiSC.v` adds to step 2 is described in [`../docs/design.md`](../docs/design.md). In short:
- a two-entry TLB on the fetch and on the memory stage;
- a second register bank (cr1–cr7) for kernel mode;
- exceptions taken in write-back, which save the EPC in `cr7` and the missed address in `cr3`, enter kernel mode, flush the pipeline and jump through the vector table at `mem[code]`.

## 3a: trap through the vector table (course stage i)

`usr-i.s` executes `halt`, the trap 0x71. No virtual memory is involved: ASID 0, untranslated.

```
cycle    time  event
    5      50  exc 0x71 trap HALT (system call)  pc 0000 -> vector 0042
   10     100  halt: sys MODE_HALT from pc 0042
```

The trap reaches write-back at cycle 5. The hardware saves EPC 0x0001 in `cr7`, enters kernel mode (PSR 0x0080) and loads the PC from `mem[0x71]` = 0x0042, where `trap_halt` stops the machine.

## 3b: user code through the TLB (course stage ii)

The same programs, but the user code is loaded at physical 0x0300 and runs at virtual 0 as ASID 9, through a TLB entry the testbench preloads (`9:00 → 03`). The fetch shows the translation: `tlb1 asid=09 vpn=00 - pfn=03 miss=0`, `mem1 a1=0300`. The event sequence is the same as in 3a, and the PSR ends as 0x0089 (kernel mode, ASID 9).

## 3c: kernel TLB miss and `tlbkmiss`

`sys-kmiss.s` runs from address 0 in kernel mode, ASID 0, with an empty TLB:

```
ktest:	lui	r1, 0xc900	# a mapped kernel address (0x8000 and above go through the TLB)
	lw	r2, r1, 0	# misses on page 0xc9
	lw	r5, r1, 15	# same page, now hits
	halt

tlbkmiss:	lw	r2, r3, 0	# r3 = 0x00c9: the root page-table entry, a physical address
		tlbw	r2, r3		# TLB: asid 0, page 0xc9 -> frame from the entry (0x8002 -> 2)
		rfe	r7		# r7 = EPC = the lw: retry it
```

How the miss is resolved: on a kernel miss the hardware writes `cr3 = {00000000, page}` = 0x00c9. That is the address of the root page-table entry for page 0xc9, and it is in untranslated kernel memory, so the handler's own load cannot miss.

From `logs/3c-kmiss.timeline.txt`:

```
cycle    time  event
    6      60  exc 0x52 kernel TLB miss          pc 0001 -> vector 0103
   12     120  tlbw       asid 0: vpn c9 -> pfn 02
   14     140  rfe        -> resume at 0001
   21     210  exc 0x71 trap HALT (system call)  pc 0003 -> vector 0102
   26     260  halt: sys MODE_HALT from pc 0102
```

1. **Cycle 6:** the `lw` at 0x0001 misses. The hardware saves EPC 0x0001 (the `lw` itself, so it will be retried), sets `cr3` = 0x00c9 and jumps through `mem[0x52]` to `tlbkmiss`.
2. **Cycles 7–14:** `tlbkmiss` reads 0x8002 from 0x00c9, writes `0:c9 → 02` into the TLB and returns.
3. The retried `lw` now hits: physical 0x0200 = 0x8003. The next `lw`, on the same page, hits at once: 0x020f = 0x8004.

## Result

```
3a-trap:      halted after 11 cycles; every cycle matches ref-phase1.log
3b-translate: halted after 11 cycles; every cycle matches ref-phase2.log
3c-kmiss:     halted after 27 cycles; cr1-cr7 = c900 8003 00c9 0180 8004 0000 0004; expected registers: yes
```

In 3c, `cr1` = 0xc900, `cr2` = 0x8003 and `cr5` = 0x8004 are the test's results, `cr3` = 0x00c9 is the address the hardware wrote at the miss, and the PSR 0x0180 has two kernel-mode bits stacked: the test started in kernel mode, then took the `halt` trap.

This `tlbkmiss` works when kernel code misses directly. In step 4 it has to run *inside* the user-miss handler, and it gains one more instruction.
