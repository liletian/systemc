# Extra: booting from ROM

**Purpose:** start the machine the way real hardware does. After reset the CPU runs a boot ROM, which asks a simulated disk to load the operating system, creates one user process and jumps to it. This uses the step 4 design and kernel.

| Folder | File | Role |
|---|---|---|
| `software/` | `rom-BOOT.s` | boot ROM, loaded at 0x7e00 |
| | `sys-iii-iv.s` | the step 4 kernel, loaded by the ROM from disk file 3 |
| | `usr-iii.s` | disk file 1, the user program |
| `testbench/` | `test-BOOT.v` | course testbench with the simulated disk |
| design | `../../step4_tlb_umiss/design/` | compiled with `-DBOOT`: PC resets to 0x7e00, PSR to kernel mode |

```
./run.sh
```

## The simulated disk (`test-BOOT.v`)

| Address | Meaning |
|---|---|
| 0x7f10 | request: 0x1234 = read |
| 0x7f11 | file number: 1 = `init.usr1`, 2 = `init.usr2`, 3 = `init.sys` |
| 0x7f12 | load address |
| 0x7f13 | status: becomes 1 when the read is done |

## What happens

1. **Cycles 1–23:** the ROM asks for file 3 at address 0 and polls the status word. The log prints `IO Read Request -- reading init.sys into 0000`.
2. **Cycles 24–40:** the ROM picks ASID 17, writes its root page-table entry (0x8002 at 0xd1), sets the PSR's ASID and runs `rfe r0` into user mode at address 0.
3. From `logs/boot.timeline.txt`, the first user fetch misses and the step 4 handlers map page 0:
   ```
      40     400  rfe        -> resume at 0000
      45     450  exc 0x51 user TLB miss            pc 0000 -> vector 0103
      55     550  exc 0x52 kernel TLB miss          pc 0108 -> vector 010e
      61     610  tlbw       asid 0: vpn d1 -> pfn 02
      64     640  rfe        -> resume at 0108
      70     700  tlbw       asid 17: vpn 00 -> pfn 03
      74     740  rfe        -> resume at 0000
   ```
4. Frame 3 is empty, because nothing has loaded the user program, so the CPU runs no-ops until the testbench stops at cycle 100.

The first 46 fetches are identical to `reference/BOOT-log.txt`. After that, the reference kernel takes a different path: a page-fault handler at 0x0180 loads the program from disk.

## What is still missing

- user page-table entries that start invalid;
- a valid-bit test in `tlbumiss`;
- a page-fault handler that reads disk file 1 into a free frame and maps it;
- one ASID used consistently: the ROM uses 17, the kernel's user page table was written for 9.

## Result

```
boot: boot ROM ran, loaded the OS from disk, entered user code at 0x0000
      first 46 fetches identical to reference/BOOT-log.txt (that kernel's handlers sit at other addresses)
      not expected to halt: the kernel has no page-fault handler, so the user program is never loaded
```
