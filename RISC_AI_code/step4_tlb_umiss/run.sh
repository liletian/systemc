#!/bin/sh
# step 4: the user TLB-miss handler, with kernel misses nested inside it
cd "$(dirname "$0")" && . ../tools/lib.sh
setup "STEP 4  user TLB-miss handler, with nested kernel misses"
# 4a: course stage iii: user fetch and load misses; kernel page 0xc9 preloaded in TLB-B
run_tb 4a-umiss     test-iii.v "" init.sys:sys-iii-iv init.usr:usr-iii
check_full 4a-umiss ref-phase3.log "2112 0000 0000 0000 0000 0000 0f00"
# 4b-4d: course stage iv: empty TLB, so every user miss nests a kernel miss
run_tb 4b-nested    test-iv.v  "" init.sys:sys-iii-iv init.usr:usr-iii
check_full 4b-nested - "2112 0000 0000 0000 0000 0000 0f00"
run_tb 4c-six-loads test-iv.v  "" init.sys:sys-iii-iv init.usr:usr-iv-dmiss
check_full 4c-six-loads - "0001 0002 0003 0004 0c00 0b00 0a00"
run_tb 4d-six-calls test-iv.v  "" init.sys:sys-iii-iv init.usr:usr-iv-imiss
check_full 4d-six-calls - "0001 0002 0003 0004 000a 000b 000c"
finish
