#!/bin/sh
# step 2: five-stage pipelined RiSC-16 running the same prog.s as step 1
cd "$(dirname "$0")" && . ../tools/lib.sh
setup "STEP 2  five-stage pipelined RiSC-16 (forwarding, load stall, branch squash; no TLB)"
run_tb prog test.v "-DDATA=16'h0010" prog.hex:prog
check_simple prog "1234 0000 000f 0010 fff0 000e 000d" 000f
say "        pipeline events: $(grep -c STALL logs/prog.log) stall, $(grep -c SQUASH logs/prog.log) squashed fetches"
finish
