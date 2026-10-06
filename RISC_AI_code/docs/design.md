# Design notes

How the full `RiSC.v` and `memories.v` (steps 3 and 4, `step*_tlb_*/design/`) work, and what was filled into the course skeleton.

## Instruction set

Every instruction is one 16-bit word: `[15:13]` opcode, `[12:10]` rA, `[9:7]` rB, `[6:0]` a signed 7-bit immediate (or rC in `[2:0]`). There are eight registers; r0 always reads 0.

| op | Instruction | Effect |
|---|---|---|
| 0 | `add rA, rB, rC` | rA = rB + rC |
| 1 | `addi rA, rB, imm` | rA = rB + imm (−64…63) |
| 2 | `nand rA, rB, rC` | rA = ~(rB & rC) |
| 3 | `lui rA, imm` | rA = imm10 << 6 |
| 4 | `sw rA, rB, imm` | mem[rB + imm] = rA |
| 5 | `lw rA, rB, imm` | rA = mem[rB + imm] |
| 6 | `bne rA, rB, label` | branch if rA ≠ rB |
| 7, imm = 0 | `jalr rA, rB` | rA = pc + 1, jump to rB |
| 7, imm ≠ 0 | extended op | imm is a system code |

| Code | Meaning |
|---|---|
| 0x02 | `sys MODE_HALT`: stop |
| 0x11 | `tlbw rA, rB`: TLB entry from rB = `{2 bits, asid, vpn}`, frame from the low byte of rA |
| 0x30 | `rfe rB`: return from exception to rB |
| 0x51 / 0x52 | user / kernel TLB miss |
| 0x71 | `halt` trap (system call) |

In kernel mode r1–r7 name a second bank, cr1–cr7. `cr3` receives the address that missed, `cr4` is the PSR (low six bits = ASID), and `cr7` receives the EPC.

## Pipeline

| Stage | Responsibilities |
|---|---|
| Fetch | translate PC[15:8] through TLB port 1; physical address = {frame, PC[7:0]}; a miss tags the instruction 0x51/0x52 and replaces it with a zero word |
| Decode | read the r or cr bank by the kernel-mode bit; forward from later stages; stall one cycle after a `lw` whose result is needed; resolve `bne`/`jalr` and squash the next fetch |
| Execute | ALU add / nand / pass-through; `lui` and `jalr` write op0 (immediate or pc + 1), other opcode-7 ops pass op1; `rfe` carries rB as its PC |
| Memory | translate loads and stores through TLB port 2; a miss raises 0x51/0x52; `tlbw` writes the TLB here and is not passed on |
| Write-back | write results; take an exception if one arrives |

**Taking an exception in write-back**, in one cycle:
1. EPC → `cr7`: the instruction's own PC for a TLB miss (so it is retried), PC + 1 otherwise.
2. The missed address → `cr3`: `{11, asid, vpn}` for a user miss, `{00000000, vpn}` for a kernel miss.
3. Push a 1 onto the PSR's stack of mode bits (`psr_kfifo[15:7]`); `rfe` pops it.
4. Next PC = `mem[exception code]`, the vector table.
5. Flush IF/ID, ID/EX, EX/MEM and MEM/WB.

## TLB

Two entries, each with a valid bit, ASID, virtual page and frame. An entry hits when it is valid and ASID and page both match. ASID 0 with page bit 7 clear is untranslated (frame = page), which is how kernel code runs without TLB entries. Instruction fetch uses ASID 0 in kernel mode; loads and stores use the PSR's ASID. New entries are written alternately into B and A, starting with B.

## What was filled into the skeleton

The course skeleton (`RiSC_26112008.v`) left these as blanks; the choices below reproduce the reference logs cycle for cycle.

| Blank | Filled with |
|---|---|
| TLB write enables | `tlbA__we = write & ctr`, `tlbB__we = write & ~ctr` |
| TLB hit, kernel bypass, pfn, miss | as described above |
| PC mux, rfe / exception | `rfe` → `MEMWB_pc`; exception → `MEM__data2out` (the vector) |
| Fetch address, TLB port 1 | `{TLB_pfn1, PC[7:0]}`, vpn = PC[15:8], asid = kmode ? 0 : asid |
| Fetch on a miss | instruction replaced with zero |
| IF/ID, ID/EX reset | also cleared when an exception reaches write-back |
| `MUXrfe_out` | `rfe` ? op1 (rB) : IDEX_pc |
| TLB port 2 | `tlbw` uses ALUout[13:8] / ALUout[7:0]; loads and stores use the PSR ASID and ALUout[15:8] |
| `MEM__addr2` | exception ? `{9'd0, MEMWB_exc}` : `{TLB_pfn2, ALUout[7:0]}` |
| Store enable | not on a TLB miss or while an exception is in write-back |
| `MEMWB_exc__in` | drop `TLB_WRITE`; keep an earlier exception; else raise 0x51/0x52 for a load or store that misses |
| PSR | written on every exception; push 1 on entry, pop on `rfe` |

Two further changes:
- **`jalr`:** the skeleton passed op1 (the jump target) through the ALU for every opcode-7 instruction, so `jalr` wrote back its own target. It now writes op0 (pc + 1). `tlbw` and `rfe` still use op1.
- **Port directions:** `IDEX_rT__out` and `EXMEM_rT__out` were declared `input`; they are `output`.

## Reset and the `BOOT` option

Built normally, the PC resets to 0x0000 and the PSR to user mode, as stages 1–4 expect. Built with `-DBOOT`, the PC resets to 0x7e00 and the PSR to kernel mode, as `test-BOOT.v` expects. `memories.v` takes the PSR reset value as a parameter, `psr_reset`.

## The TLB handlers (`step4_tlb_umiss/software/sys-iii-iv.s`)

```
tlbumiss:  addi  r1, r4, 0     # save PSR (the ASID)
           addi  r4, r0, 0     # ASID 0
           nop                 # let it take effect
           sw    r3, r0, u_r3  # save BadVA and EPC before the load:
           sw    r7, r0, u_r7  #   a nested kernel miss overwrites both
           lw    r2, r3, 0     # page-table entry; may miss
           tlbw  r2, r3
           lw    r7, r0, u_r7  # restore EPC
           addi  r4, r1, 0     # restore ASID
           rfe   r7
           sys   MODE_PANIC9   # never reached

tlbkmiss:  lw    r2, r3, 0     # root entry, physical address
           tlbw  r2, r3
           lw    r3, r0, u_r3  # give tlbumiss its BadVA back
           rfe   r7            # retry the load in tlbumiss
```
