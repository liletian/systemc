# Stage 5: booting from ROM

**Purpose:** start the machine the way real hardware does. After reset the CPU runs a boot ROM, which asks a simulated disk to load the operating system, creates one user process and jumps to it.

| | |
|---|---|
| Testbench | `testbench/test-BOOT.v`, compiled with `-DBOOT` (runs 100 cycles) |
| Boot ROM | `software/rom-BOOT.s` → `init.rom`, loaded at 0x7e00 |
| Kernel | `software/sys-iii-iv.s` → `init.sys`, loaded **by the boot ROM** through the disk |
| User program | `software/usr-iii.s` → `init.usr1`, disk file 1 (loaded only by a page-fault handler, which does not exist yet) |
| Logs | `logs/stage-5-boot.log`, `logs/stage-5-boot.timeline.txt` |
| Reference | `reference/BOOT-log.txt` (the annotated PC trace of a complete boot) |

## The `BOOT` build option

With `-DBOOT`, `design/RiSC.v` resets the PC to 0x7e00 and the PSR to kernel mode. Without these, the CPU starts at 0x0000 in user mode, the ROM never runs, and `lli r4, 17` would write the user's r4 instead of the PSR. The default build keeps the old reset values, so stages 1–4 are unaffected.

## The simulated disk

`test-BOOT.v` watches four memory words:

| Address | Meaning |
|---|---|
| 0x7f10 | request: 0x1234 = read |
| 0x7f11 | file number: 1 = `init.usr1`, 2 = `init.usr2`, 3 = `init.sys` |
| 0x7f12 | load address |
| 0x7f13 | status: becomes 1 when the read is done |

## What happens

1. **Cycles 1–23:** the ROM writes file 3, address 0 and the read request, then polls the status word. The log prints `IO Read Request -- reading init.sys into 0000`, and the `7e0b–7e0d` loop runs until the status becomes 1.
2. **Cycles 24–40:** the ROM picks ASID 17, writes the root page-table entry 0x8002 at 0xc0 + 17 = 0xd1, sets `r4` (the PSR) to ASID 17 and runs `rfe r0`, which enters user mode at address 0.
3. From `logs/stage-5-boot.timeline.txt`:
   ```
      40     400  rfe        -> resume at 0000
      45     450  exc 0x51 user TLB miss            pc 0000 -> vector 0103
      55     550  exc 0x52 kernel TLB miss          pc 0108 -> vector 010e
      61     610  tlbw       asid 0: vpn d1 -> pfn 02
      64     640  rfe        -> resume at 0108
      70     700  tlbw       asid 17: vpn 00 -> pfn 03
      74     740  rfe        -> resume at 0000
   ```
   The first user fetch misses, and the same nested-miss sequence as stage 4 maps virtual page 0 to frame 3.
4. Frame 3 is empty: nothing has loaded the user program. The CPU executes zeros (no-ops) until the testbench stops at cycle 100.

## Comparison with `BOOT-log.txt`

The first 46 fetches, the whole boot ROM plus the first user fetches, are identical to the reference trace. After that the reference kernel takes different paths: its handlers sit at 0x0100, 0x0120, 0x0180 (page fault) and 0x01f3 (halt).

## What is still missing

To finish this stage the kernel needs:
1. a user page table whose entries start **invalid**, so that touching page 0 causes a page fault;
2. a valid-bit test in `tlbumiss` (on r2, the loaded entry) that jumps to a page-fault handler;
3. the page-fault handler: pick a free frame, read file 1 from the disk into it (the same steps as the boot ROM), write the page-table entry and the TLB, and `rfe` to the user program;
4. one ASID used consistently: `rom-BOOT.s` uses 17, while the kernel's user page table was written for ASID 9.

## Result

```
stage-5-boot: 101 cycles, no halt
        boot ROM ran, loaded the OS from disk, entered user code at 0x0000 (needs a page-fault handler to go further)
        first 46 fetches identical to reference/BOOT-log.txt (its kernel uses different handler addresses after that)
```
