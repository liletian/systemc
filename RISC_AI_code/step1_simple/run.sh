#!/bin/sh
# step 1: single-cycle RiSC-16 running prog.s
cd "$(dirname "$0")" && . ../tools/lib.sh
setup "STEP 1  single-cycle RiSC-16 (no pipeline)"
run_tb prog test.v "-DDATA=16'h0010" prog.hex:prog
check_simple prog "1234 0000 000f 0010 fff0 000e 000d" 000f
finish
