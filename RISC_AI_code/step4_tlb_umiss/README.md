# Step 4: the user TLB-miss handler, with nested kernel misses

**Purpose:** let user programs run with demand-filled TLB entries. A user miss needs a two-level page-table walk, and the walk itself can miss in the TLB, so the kernel-miss handler from step 3 now runs nested inside the user-miss handler.

| Folder | File | Role |
|---|---|---|
| `design/` | `RiSC.v`, `memories.v` | the same full design as step 3 |
| `software/` | `sys-iii-iv.s` | kernel: vector table, root page tables, ASID 9's page table, `tlbumiss` and `tlbkmiss` |
| | `usr-iii.s` | one load from virtual 0x0f00 |
| | `usr-iv-dmiss.s` | loads from six pages (0xf00 … 0xa00) |
| | `usr-iv-imiss.s` | `jalr` calls into six pages |
| `testbench/` | `test-iii.v` | course stage iii: TLB-B preloaded with kernel page 0xc9 |
| | `test-iv.v` | course stage iv: empty TLB |
| `logs/` | `<test>.log`, `<test>.timeline.txt`, `summary.txt` | output of `run.sh` |

```
./run.sh
```

## How a user miss is resolved

On a user miss the hardware writes `cr3 = {11, asid, page}`, for example 0xc900 for ASID 9, page 0. That is the kernel-mapped virtual address of the page-table entry: page 0xc9 holds ASID 9's page table, and the root entry at physical 0x00c9 says that page is in frame 2. So `tlbumiss` reads the entry with a single `lw r2, r3, 0`. That load goes through the TLB and can miss itself, which raises a kernel miss inside the handler.

```
tlbumiss:  addi  r1, r4, 0     # save PSR (the ASID)
           addi  r4, r0, 0     # ASID 0
           nop                 # let it take effect
           sw    r3, r0, u_r3  # save BadVA and EPC BEFORE the load:
           sw    r7, r0, u_r7  #   a nested kernel miss overwrites cr3 and cr7
           lw    r2, r3, 0     # the page-table entry; may miss
           tlbw  r2, r3        # TLB: asid 9, page -> frame from the entry
           lw    r7, r0, u_r7  # restore EPC
           addi  r4, r1, 0     # restore ASID
           rfe   r7

tlbkmiss:  lw    r2, r3, 0     # as in step 3
           tlbw  r2, r3
           lw    r3, r0, u_r3  # NEW: give tlbumiss its BadVA back
           rfe   r7            # retry tlbumiss's load
```

What changed since step 3: `tlbumiss` saves `r3` and `r7` before its load, and `tlbkmiss` restores `r3` before returning. Without them the nested miss destroys the address and the return PC that `tlbumiss` still needs.

## 4a: user misses, course stage iii

The testbench preloads TLB-B with `0:c9 → 02`, so the first walk does not nest. From `logs/4a-umiss.timeline.txt`:

```
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
```

1. **Cycle 5:** the fetch at virtual 0 misses. The handler writes `9:00 → 03`, which replaces the preloaded `0:c9` in TLB-B (entries are written alternately into B and A).
2. **Cycle 26:** `lw r1, 0(r7)` misses on page 0x0f. Its entry is at 0xc90f, and page 0xc9 is gone, so the handler's load misses too (**cycle 36**). `tlbkmiss` refills page 0xc9 into TLB-A and returns to retry the load at 0x0108. `tlbumiss` then writes `9:0f → 04` into TLB-B, evicting page 0x00.
3. **Cycle 60:** the user fetch misses on page 0x00 again and is refilled into TLB-A.

## 4b–4d: empty TLB, course stage iv

Now even the first miss nests. From `logs/4b-nested.timeline.txt`:

```
    5      50  exc 0x51 user TLB miss            pc 0000 -> vector 0103
   15     150  exc 0x52 kernel TLB miss          pc 0108 -> vector 010e
   21     210  tlbw       asid 0: vpn c9 -> pfn 02
   24     240  rfe        -> resume at 0108
   30     300  tlbw       asid 9: vpn 00 -> pfn 03
   34     340  rfe        -> resume at 0000
```

| Test | Program | Expected user registers at halt |
|---|---|---|
| 4b-nested | `usr-iii.s` | r1 = 2112 (the word at virtual 0x0f00 = physical 0x0400) |
| 4c-six-loads | `usr-iv-dmiss.s` | r1–r6 = the words on frames 4–9: `0001 0002 0003 0004 0c00 0b00` |
| 4d-six-calls | `usr-iv-imiss.s` | r1–r6 = each subroutine's increment: `0001 0002 0003 0004 000a 000b`; r7 = `000c`, the last return address |

With seven pages in use and two TLB entries, almost every new page costs a user miss, a nested kernel miss, and a second user miss to bring back page 0x00. `4c-six-loads` writes the TLB 18 times in 347 cycles. `4d-six-calls` also checks `jalr` across pages, where each call's fetch misses.

## Result

```
4a-umiss:     halted after 87 cycles;  r1 = 2112; every cycle matches ref-phase3.log; expected registers: yes
4b-nested:    halted after 67 cycles;  r1 = 2112; expected registers: yes
4c-six-loads: halted after 347 cycles; 0001 0002 0003 0004 0c00 0b00 0a00; expected registers: yes
4d-six-calls: halted after 371 cycles; 0001 0002 0003 0004 000a 000b 000c; expected registers: yes
```
