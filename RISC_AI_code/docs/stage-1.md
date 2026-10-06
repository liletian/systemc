# Stage 1: system call and vector table

**Purpose:** prove that the exception path works before any virtual memory is involved. A system call must travel down the pipeline, be taken in write-back, switch to kernel mode and jump through the vector table.

| | |
|---|---|
| Testbench | `testbench/test-i.v` |
| Kernel | `software/sys-i.s` → `init.sys`, loaded at 0x0000 |
| User program | `software/usr-i.s` → `init.usr`, loaded at 0x0000 (over the kernel's empty first 64 words) |
| Start state | user mode, ASID 0, empty TLB; ASID 0 below 0x8000 is untranslated |
| Logs | `logs/stage-1.log`, `logs/stage-1.timeline.txt` |
| Reference | `reference/ref-phase1.log` |

## The programs

`usr-i.s` is `halt` followed by three `lli`s that must never run.

`sys-i.s` lays out page 0:
- 0x00–0x3f empty (the user program goes here in this stage)
- 0x40 `error`: an endless loop
- 0x42 `trap_halt`: `sys MODE_HALT`
- 0x50–0x7f the vector table; entry 0x71 (the halt trap) points to `trap_halt`, all others to `error`

## What happens (from `logs/stage-1.timeline.txt`)

```
cycle    time  event
    5      50  exc 0x71 trap HALT (system call)  pc 0000 -> vector 0042
   10     100  halt: sys MODE_HALT from pc 0042
```

1. The `halt` at 0x0000 decodes as an extended op with code 0x71 and moves down the pipeline. The three `lli`s behind it are fetched but never complete.
2. At cycle 5 the code reaches write-back. In that one cycle the hardware saves EPC = 0x0001 in `cr7`, pushes kernel mode (the PSR becomes 0x0080), flushes the pipeline and reads the next PC from `mem[0x71]` = 0x0042.
3. `sys MODE_HALT` at 0x0042 reaches write-back at cycle 10 and the simulation stops.

The final control registers show the effect: `cr7 = 0001`, PSR `= 0080`.

## Result

```
stage-1: 11 cycles, halted, user r1-r7 = 0000 0000 0000 0000 0000 0000 0000; every cycle matches ref-phase1.log
```

The comparison skips the TLB debug lines, because the reference run used a stub TLB that reports differently. Every other line of every cycle is identical.
