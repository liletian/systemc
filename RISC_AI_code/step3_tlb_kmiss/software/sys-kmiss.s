#
# step 3 kernel: kernel-mode code touches a TLB-mapped kernel page, and the
# kernel TLB-miss handler resolves it on its own (no user process involved)
#
# ktest runs in kernel mode with ASID 0 (the testbench sets the PSR). Kernel
# addresses at 0x8000 and above go through the TLB. 0xc900 is page 0xc9, the
# kernel-mapped view of ASID 9's page table; the root page tables (0xc0-0xff)
# say that page 0xc9 lives in physical frame 2.
#
# kernel mode uses the control-register bank: r1 = cr1, r2 = cr2, r3 = cr3
# (written by the hardware on a miss), r4 = cr4 (the PSR), r7 = cr7 (the EPC),
# so the test uses only r1, r2 and r5.
#
# expected at halt: cr1 = c900, cr2 = 8003, cr5 = 8004, TLB holds 0:c9 -> 02
#
ktest:	lui	r1, 0xc900	# r1 = 0xc900, a mapped kernel address
	lw	r2, r1, 0	# TLB miss on page 0xc9 -> exception 0x52 -> tlbkmiss
				#   -> retried: r2 = mem[0x0200] = 0x8003
	lw	r5, r1, 15	# page 0xc9 is now in the TLB: r5 = mem[0x020f] = 0x8004
	halt

here1:	.space	80-here1

#
# now comes the IVT ... three groups of 16 addresses.
# first: the exceptions
# second: the interrupts
# third: the traps
#
# might as well fill them all in with "error" except the
# one that we want to implement, so we can catch it if we
# jump to the wrong place
#

#
# EXCEPTION VECTORS
#
	.fill	error
	.fill	error		# 0x51 user TLB miss: not handled in step 3
	.fill	tlbkmiss	# 0x52 kernel TLB miss
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error
#
# INTERRUPT VECTORS
#
	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error
#
# TRAP VECTORS
#
	.fill	error
	.fill	trap_halt
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error

	.fill	error
	.fill	error
	.fill	error
	.fill	error


#
# now comes the kernel's page table ...
# (unused for now)
#

	.space	64


#
# now comes the various root page tables
#

asid00:		.fill	0
asid01:		.fill	0
asid02:		.fill	0
asid03:		.fill	0
asid04:		.fill	0
asid05:		.fill	0
asid06:		.fill	0
asid07:		.fill	0
asid08:		.fill	0
asid09:		.fill	0x8002  # put user page table in PFN2
asid0a:		.fill	0
asid0b:		.fill	0
asid0c:		.fill	0
asid0d:		.fill	0
asid0e:		.fill	0
asid0f:		.fill	0

asid10:		.fill	0
asid11:		.fill	0
asid12:		.fill	0
asid13:		.fill	0
asid14:		.fill	0
asid15:		.fill	0
asid16:		.fill	0
asid17:		.fill	0
asid18:		.fill	0
asid19:		.fill	0
asid1a:		.fill	0
asid1b:		.fill	0
asid1c:		.fill	0
asid1d:		.fill	0
asid1e:		.fill	0
asid1f:		.fill	0

asid20:		.fill	0
asid21:		.fill	0
asid22:		.fill	0
asid23:		.fill	0
asid24:		.fill	0
asid25:		.fill	0
asid26:		.fill	0
asid27:		.fill	0
asid28:		.fill	0
asid29:		.fill	0
asid2a:		.fill	0
asid2b:		.fill	0
asid2c:		.fill	0
asid2d:		.fill	0
asid2e:		.fill	0
asid2f:		.fill	0

asid30:		.fill	0
asid31:		.fill	0
asid32:		.fill	0
asid33:		.fill	0
asid34:		.fill	0
asid35:		.fill	0
asid36:		.fill	0
asid37:		.fill	0
asid38:		.fill	0
asid39:		.fill	0
asid3a:		.fill	0
asid3b:		.fill	0
asid3c:		.fill	0
asid3d:		.fill	0
asid3e:		.fill	0
asid3f:		.fill	0

#
# PHYSICAL PAGE 1 begins here ...
#

#
# put the handlers all into physical page #1
#
error:	lli	r1,1
	bne	r0,r1,-1		# jumps to itself in an endless loop
					# this is added just to aid in debugging
		
trap_halt:	sys	MODE_HALT	# kills the machine
					# (in a real system, it would first shut down
					# all user processes gracefully, then sync the
					# file systems, etc. ... lastly, it would 
					# kill the machine)

tlbkmiss:	lw	r2, r3, 0	# r3 = 0x00vv: the root page-table entry for page vv, a physical address
		tlbw	r2, r3		# TLB: asid 0, page vv -> frame in the entry's low byte
		rfe	r7		# r7 = EPC = the faulting lw: retry it

#
# the user page table for ASID 8 will go into page 2
# (so skip the rest of page 1)
#

here2:		.space	512-here2

#
# an example user page table (that works with usr-iii.s):
#

vpn00:		.fill	0x8003	# put VPN0 of the program into PFN3
vpn01:		.fill	0
vpn02:		.fill	0
vpn03:		.fill	0
vpn04:		.fill	0
vpn05:		.fill	0
vpn06:		.fill	0
vpn07:		.fill	0
vpn08:		.fill	0
vpn09:		.fill	0
vpn0a:		.fill	0x8009
vpn0b:		.fill	0x8008
vpn0c:		.fill	0x8007
vpn0d:		.fill	0x8006
vpn0e:		.fill	0x8005
vpn0f:		.fill	0x8004

#
# mark all the rest invalid for now ...

		.space 240
