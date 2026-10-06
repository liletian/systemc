# Stage 3: handling a TLB miss in the kernel

**Purpose:** prove that TLB misses become exceptions, and that the kernel can resolve them. Nothing in the user's address space is in the TLB at the start, so the kernel's `tlbumiss` handler has to walk the page table and fill the TLB.

| | |
|---|---|
| Testbench | `testbench/test-iii.v` |
| Kernel | `software/sys-iii-iv.s` → `init.sys` at 0x0000 (pages 0–2) |
| User program | `software/usr-iii.s` → `init.usr` at 0x0300 (pages 3–4) |
| Start state | user mode, ASID 9; **TLB-B = asid 0, vpn 0xc9 → pfn 0x02** (the kernel page that holds ASID 9's page table) |
| Logs | `logs/stage-3.log`, `logs/stage-3.timeline.txt` |
| Reference | `reference/ref-phase3.log` |

## The programs

`usr-iii.s`:
```
	lui	r7, 0x0f00	# r7 = 0x0f00 (virtual page 0x0f)
	lw	r1, r7, 0	# r1 = mem[0x0f00]
	halt
	...                     # page 4 starts with .fill 0x2112
```

`sys-iii-iv.s` adds to the stage-1 layout:
- vector 0x51 → `tlbumiss` (0x0103) and 0x52 → `tlbkmiss` (0x010e)
- the root page tables at 0xc0–0xff; ASID 9's entry (0x00c9) is 0x8002: "valid, page table in frame 2"
- ASID 9's page table in frame 2 (0x0200): vpn 0x00 → frame 3, vpn 0x0f → frame 4, …, vpn 0x0a → frame 9
- the two TLB handlers (see [design notes](design.md) for the listing)

## How the kernel finds the page-table entry

On a user miss the hardware writes `cr3 = {11, asid, vpn}`. For ASID 9, vpn 0x00 that is 0xc900: the kernel-mapped virtual address of the entry, in page 0xc9. Because the testbench preloaded page 0xc9 → frame 2, the handler's `lw r2, r3, 0` reads physical 0x0200 directly.

## What happens (from `logs/stage-3.timeline.txt`)

```
cycle    time  event
    5      50  exc 0x51 user TLB miss            pc 0000 -> vector 0103
   16     160  tlbw       asid 9: vpn 00 -> pfn 03
   20     200  rfe        -> resume at 0000
   26     260  exc 0x51 user TLB miss            pc 0001 -> vector 0103
   36     360  exc 0x52 kernel TLB miss          pc 0108 -> vector 010e
   42     420  tlbw       asid 0: vpn c9 -> pfn 02
   45     450  rfe        -> resume at 0108
   51     510  tlbw       asid 9: vpn 0f -> pfn 04
   55     550  rfe        -> resume at 0001
   60     600  exc 0x51 user TLB miss            pc 0001 -> vector 0103
   71     710  tlbw       asid 9: vpn 00 -> pfn 03
   75     750  rfe        -> resume at 0001
   81     810  exc 0x71 trap HALT (system call)  pc 0002 -> vector 0102
   86     860  halt: sys MODE_HALT from pc 0102
```

1. **Cycle 5:** the first fetch (pc 0) misses. `tlbumiss` loads the entry and writes `9:00 → 03`. The TLB writes new entries alternately into B and A, starting with B, so this write replaces the preloaded `0:c9 → 02` in TLB-B.
2. **Cycle 26:** the `lw` at pc 1 misses on page 0x0f. Its entry is at 0xc90f, and page 0xc9 is no longer in the TLB, so the handler's own load misses too (**cycle 36**, a nested kernel miss). `tlbkmiss` writes `0:c9 → 02` into TLB-A and returns to retry the load at 0x0108. `tlbumiss` then writes `9:0f → 04` into TLB-B, evicting page 0x00.
3. **Cycle 60:** fetching pc 1 again misses on page 0x00, which is refilled into TLB-A.
4. **Cycle 81:** the `halt` trap is taken, and `trap_halt` at 0x0102 stops the machine.

r1 = 0x2112 confirms that virtual 0x0f00 was translated to physical 0x0400.

## Result

```
stage-3: 87 cycles, halted, user r1-r7 = 2112 0000 0000 0000 0000 0000 0f00; every cycle matches ref-phase3.log
```

All 87 cycles match the reference on every line, including the TLB contents.
