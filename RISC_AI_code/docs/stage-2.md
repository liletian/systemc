# Stage 2: running user code through the TLB

**Purpose:** prove that address translation works. The same user program now lives in physical page 3 but runs at virtual address 0, under its own ASID, through a TLB entry the testbench preloads.

| | |
|---|---|
| Testbench | `testbench/test-ii.v` |
| Kernel | `software/sys-ii.s` (identical to `sys-i.s`) → `init.sys` at 0x0000 |
| User program | `software/usr-ii.s` (identical to `usr-i.s`) → `init.usr` at **0x0300** |
| Start state | user mode, **ASID 9** (`cr4 = 0x0009`), **TLB-A = asid 9, vpn 0x00 → pfn 0x03** |
| Logs | `logs/stage-2.log`, `logs/stage-2.timeline.txt` |
| Reference | `reference/ref-phase2.log` |

## What is new

- **Fetch translation.** The PC's top byte (vpn 0x00) and the PSR's ASID (9) are looked up in the TLB. TLB-A hits, so the fetch address is `{pfn 0x03, PC low byte}` = 0x0300. In the log this shows as `tlb1 asid=09 vpn=00 - pfn=03 miss=0` and `mem1 a1=0300 d1out=e071`.
- **Kernel addresses bypass the TLB.** After the trap the CPU is in kernel mode, where the fetch uses ASID 0. Page 0x00 below 0x8000 is untranslated, so the handler at 0x0042 runs without any TLB entry.

## What happens (from `logs/stage-2.timeline.txt`)

```
cycle    time  event
    5      50  exc 0x71 trap HALT (system call)  pc 0000 -> vector 0042
   10     100  halt: sys MODE_HALT from pc 0042
```

The sequence is the same as stage 1, now through the TLB. The PSR goes from 0x0009 (user, ASID 9) to 0x0089 (kernel mode pushed, ASID still 9).

## Result

```
stage-2: 11 cycles, halted, user r1-r7 = 0000 0000 0000 0000 0000 0000 0000; every cycle matches ref-phase2.log
```
