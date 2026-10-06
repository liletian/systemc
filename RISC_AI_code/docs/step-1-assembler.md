# Step 1: build the assembler and the memory images

**Purpose:** turn the assembly sources in `software/` into the hex memory images the testbenches load with `$readmemh`.

## Files

| File | Role |
|---|---|
| `assembler/a.c` | the RiSC-16 assembler |
| `software/*.s` | kernels, user programs and the boot ROM |
| `images/*.hex` | output: one 16-bit word per line, in hex |
| `reference/provided-images/` | the images that came with the course, used as a check |

## What `run_all.sh` does

```
gcc -std=gnu89 -w -include stdlib.h -include ctype.h -o build/asm assembler/a.c
build/asm software/<name>.s images/<name>.hex        # for every .s file
```

`a.c` is old-style C. On a current gcc it needs `-std=gnu89`, plus `stdlib.h` and `ctype.h` forced in, because it calls `exit`, `atoi` and `isdigit` without including their headers.

## How the assembler works

- **Pass 1** reads every line and gives each label an address. `movi` counts as two words, `.space N` as N words, everything else as one.
- **Pass 2** encodes each line. Besides the eight real instructions it accepts:
  - `nop`, `halt` (the trap 0x71), `sys CODE`, `rfe rB` and `tlbw rA, rB`
  - `lli rA, imm`, which **adds** the low 6 bits of imm to rA; it does not set rA
  - `movi rA, imm`, which is `lui` followed by `lli`
  - `.fill value` and `.space N`
  - label arithmetic such as `.space 80-here1`, and built-in names such as `MODE_HALT`

Known quirk: a missing comma in its operand table joins `"jalr" "lui"` into one string, so those two instructions skip the "too few operands" check. It has no effect on the encoded output.

## Check

`run_all.sh` compares four assembled images with the course-provided ones:

```
images/sys-i.hex      == provided init.sys_i
images/usr-i.hex      == provided init.usr_i
images/sys-iii-iv.hex == provided init.sys.important
images/usr-iii.hex    == provided init_3.usr
```

So the sources in `software/` are exactly the programs the reference logs were made with.
