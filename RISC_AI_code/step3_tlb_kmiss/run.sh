#!/bin/sh
# step 3: the full RiSC.v (TLB, kernel mode, exceptions) and the kernel TLB-miss handler
cd "$(dirname "$0")" && . ../tools/lib.sh
setup "STEP 3  TLB, exceptions and the kernel TLB-miss handler"
# 3a: a system call goes through the vector table to halt (course stage i)
run_tb 3a-trap      test-i.v     "" init.sys:sys-i  init.usr:usr-i
check_full 3a-trap ref-phase1.log -
# 3b: user code runs at virtual 0 through a preloaded TLB entry (course stage ii)
run_tb 3b-translate test-ii.v    "" init.sys:sys-ii init.usr:usr-ii
check_full 3b-translate ref-phase2.log -
# 3c: kernel code touches mapped page 0xc9 with an empty TLB; tlbkmiss resolves it
run_tb 3c-kmiss     test-kmiss.v "" init.sys:sys-kmiss
check_full 3c-kmiss - "cr:c900 8003 00c9 0180 8004 0000 0004"
finish
