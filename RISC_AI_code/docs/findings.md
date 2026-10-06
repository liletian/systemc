# Findings

Problems found while running the stages, in the design here and in earlier versions of the uploaded files.

## Pipeline (`RiSC.v`)

| Problem | Symptom | Status here | In the uploaded `RiSC.v` |
|---|---|---|---|
| `jalr` wrote its jump target instead of pc + 1 (present in the course skeleton) | `usr-iv-imiss.s`: each subroutine returns to itself and loops; r2 reaches 0x0124 | fixed | still present |
| A fetch that misses passed its garbage word down the pipeline | stage 3 differs from the reference on 8 lines | fixed | still present |
| A load or store that misses raised no exception | stage 3 halts after 33 of 87 cycles with r1 = 0x0f00 | fixed | fixed for `lw`, missing for `sw` |
| TLB entries A and B written in the wrong order (`RiSC-p3-2006-skeleton.v` only) | the wrong entry is evicted | correct | `RiSC_v3.v` is correct |
| No reset to the boot ROM or kernel mode | `test-BOOT.v` starts at 0x0000 and the ROM never runs | added `-DBOOT` | not present |
| `IDEX_rT__out`, `EXMEM_rT__out` declared `input` | accepted by Verilog-XL, warned by others | fixed | still present |

## Kernels (`sys-*.s`)

| File | Problem | Symptom |
|---|---|---|
| `sys-i_kmiss.s` | saves `r3` / `r7` after the page-table load that can miss; its `tlbkmiss` overwrites `r1` | `rfe` jumps to 0x0f00 and runs off; fixed version is `software/sys-iii-iv.s` |
| `sys-iv.s` | `tlbkmiss` is `.fill 0x0059`, an ordinary instruction | falls through into empty memory |
| `sys-iii.s`, `sys-i_umiss.s` | `tlbkmiss` is only `sys MODE_PANIC10` | fails as soon as a kernel miss happens |
| `sys-iii_new.s` | valid-bit check tests `r1` instead of `r2`, and its `bne` targets the next line | no effect yet, since every entry is valid; the kernel works |
| `sys.s` | none | works; 3 cycles slower than the reference in stage 3 because of an extra `nop` |

Kernels that pass every stage-4 program: `sys-iii-iv.s` (this folder), `sys.s`, `sys-iii_new.s`.

## Boot ROM (`rom-BOOT.s`)

- Uses ASID 17, while the kernel's user page table was written for ASID 9. It still works, because the ROM writes ASID 17's root entry itself.
- `lli r4, 17` adds 17 to r4; it is correct only because r4 is 0 at reset.
- The user program is never loaded: the kernel has no page-fault handler yet. See [stage 5](stage-5-boot.md).

## Assembler (`a.c`)

- A missing comma joins `"jalr" "lui"` into one string, so those two instructions skip the operand-count check.
- Needs `-std=gnu89 -include stdlib.h -include ctype.h` on a current gcc.
