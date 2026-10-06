# Stage 4: nested misses with an empty TLB

**Purpose:** stress the miss handling. The TLB starts empty, so the very first user miss also causes a kernel miss inside the handler. Two TLB entries for seven pages force constant replacement. The second and third programs touch six pages each, once with loads and once with subroutine calls.

| | |
|---|---|
| Testbench | `testbench/test-iv.v` (runs up to 500 cycles) |
| Kernel | `software/sys-iii-iv.s` → `init.sys` |
| User programs | `usr-iii.s`, `usr-iv-dmiss.s`, `usr-iv-imiss.s` → `init.usr` at 0x0300, one run each |
| Start state | user mode, ASID 9, **empty TLB** |
| Logs | `logs/stage-4-iii.*`, `logs/stage-4-dmiss.*`, `logs/stage-4-imiss.*` |
| Reference | none; each run is checked against the user registers it must end with |

## The nested miss, step by step (from `logs/stage-4-iii.timeline.txt`)

```
cycle    time  event
    5      50  exc 0x51 user TLB miss            pc 0000 -> vector 0103
   15     150  exc 0x52 kernel TLB miss          pc 0108 -> vector 010e
   21     210  tlbw       asid 0: vpn c9 -> pfn 02
   24     240  rfe        -> resume at 0108
   30     300  tlbw       asid 9: vpn 00 -> pfn 03
   34     340  rfe        -> resume at 0000
```

1. The fetch at pc 0 misses: `cr7 = 0x0000`, `cr3 = 0xc900`.
2. `tlbumiss` saves `r3` and `r7` to memory, then loads the entry from 0xc900. Page 0xc9 is not in the TLB, so that load misses: `cr7 = 0x0108`, `cr3 = 0x00c9`. Both registers `tlbumiss` needed are overwritten here, which is why it saved them first.
3. `tlbkmiss` loads the root entry from physical 0x00c9 (= 0x8002), writes `0:c9 → 02`, restores `r3 = 0xc900` and returns to 0x0108.
4. The retried load now hits. `tlbumiss` writes `9:00 → 03`, restores `r7` and returns to the user program.

## The three programs

| Program | What it does | Expected user registers at halt |
|---|---|---|
| `usr-iii.s` | one load from 0x0f00 | r1 = 2112 |
| `usr-iv-dmiss.s` | loads from 0xf00, 0xe00, 0xd00, 0xc00, 0xb00, 0xa00 into r1–r6 | 0001 0002 0003 0004 0c00 0b00, r7 = 0a00 |
| `usr-iv-imiss.s` | `jalr` to a subroutine on each of those six pages; each adds a constant to one register and returns | 0001 0002 0003 0004 000a 000b, r7 = 000c (last return address) |

In `usr-iv-dmiss.s` every load costs two or three exceptions: a user miss, a nested kernel miss for page 0xc9, and often a second user miss to bring back page 0x00, which the previous write evicted. Its timeline lists 18 TLB writes in 347 cycles.

`usr-iv-imiss.s` is the program that found the `jalr` bug (see [findings](findings.md)). Before the fix, `jalr` wrote its jump target instead of pc + 1 into rA, so every subroutine returned to itself.

## Results

```
stage-4-iii:   67 cycles,  halted, user r1-r7 = 2112 0000 0000 0000 0000 0000 0f00; registers correct
stage-4-dmiss: 347 cycles, halted, user r1-r7 = 0001 0002 0003 0004 0c00 0b00 0a00; registers correct
stage-4-imiss: 371 cycles, halted, user r1-r7 = 0001 0002 0003 0004 000a 000b 000c; registers correct
```
