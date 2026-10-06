#
# step 1 / step 2 test program: every base instruction, a loop, a load right
# after the value it needs, and a subroutine call
#
# expected at halt:
#   r1 = 1234   (lui + lli)
#   r2 = 0000   (loop counter ran down to 0)
#   r3 = 000f   (5+4+3+2+1)
#   r4 = 0010   (15 loaded back from memory, +1 in the subroutine)
#   r5 = fff0   (nand of 15 with itself)
#   r6 = address of sub, r7 = return address after the jalr
#   mem[data] = 000f   (data assembles to address 0x0010)
#
start:	movi	r1, 0x1234	# lui r1, 0x1200 then lli r1, 0x34
	addi	r2, r0, 5	# loop counter
	addi	r3, r0, 0	# sum
loop:	add	r3, r3, r2	# sum += counter
	addi	r2, r2, -1
	bne	r2, r0, loop	# taken 4 times, falls through once
	sw	r3, r0, data	# mem[data] = 15
	lw	r4, r0, data	# r4 = 15
	nand	r5, r4, r4	# uses r4 straight after the load: r5 = ~15
	movi	r6, sub
	jalr	r7, r6		# call sub; r7 = return address
	halt

sub:	addi	r4, r4, 1	# r4 = 16
	jalr	r0, r7		# return

data:	.fill	0
