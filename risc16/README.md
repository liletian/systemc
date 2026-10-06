# RiSC-16 pipeline with TLB and exceptions

This directory holds the completed `RiSC.v` skeleton: a 5-stage RiSC-16 pipeline with a 2-entry TLB, kernel/user mode, exceptions and `rfe`. It also holds a testbench that checks it cycle by cycle against reference simulation logs.

```
./run.sh        # needs Icarus Verilog (iverilog, vvp)
phase 1: MATCH (11 cycles)
phase 2: MATCH (11 cycles)
phase 3: MATCH (87 cycles)
```

| phase | memory image | user code at | start state | reference |
|---|---|---|---|---|
| 1 | `init.sys_i` | 0x0000 | ASID 0 (no translation) | `ref-phase1.log` |
| 2 | `init.sys_i` | 0x0300 | ASID 9, TLB-A = 9:00 -> 03 | `ref-phase2.log` |
| 3 | `init.sys.important` | 0x0300 (`init_3.usr`) | ASID 9, TLB-B = 0:c9 -> 02 | `ref-phase3.log` |

The phase-1 reference was built with a stub TLB, so the TLB debug lines are left out of that comparison.

## How the blanks were filled in

- **TLB**: a hit needs `v`, a matching ASID and a matching VPN. ASID 0 with VPN bit 7 clear is kernel-physical (pfn = vpn). Writes alternate between entries B and A (`ctr`). Fetch uses ASID 0 in kernel mode. `tlbw rA, rB` takes asid/vpn from rB = `{2'b11, asid, vpn}` and the pfn from the low byte of rA.
- **Fetch**: a fetch that misses in the TLB is replaced with a zero instruction (a no-op), so a bogus instruction from frame 0 can't run.
- **Exceptions**: when an exception reaches write-back, IF/ID, ID/EX, EX/MEM and MEM/WB are all flushed. The PC is loaded from the vector table at `mem[exc]`.
- **rfe**: `rfe` carries rB (the EPC) as its PC down the pipeline, and the PC jumps there when it reaches write-back.
- **PSR**: the PSR keeps a stack of k-mode bits in `[15:7]`. An exception pushes a 1 and `rfe` pops it.
- **Memory stage**: a load or store that misses raises a user or kernel TLB-miss exception, based on the k-mode bit in the instruction's rT. A store that misses doesn't write memory. `TLB_WRITE` is not passed on to write-back.
- **Port fixes**: `IDEX_rT__out` and `EXMEM_rT__out` were declared as `input`; they are now `output`.
