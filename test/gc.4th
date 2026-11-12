\ Baku Cheney collector tests.
\
\ The collector only runs on a target whose stack-scan adapter found the Forth
\ stack bases.  gforth has SP0/SP@/RP0/RP@; the pinned Sloth has neither, so its
\ branch proves activation fails with the documented catchable error instead of
\ silently missing a root.  The supported branch covers value tracing, cycles,
\ shared tails, explicit roots, stack roots, table roots, code/closure roots,
\ arena coexistence and a garbage stress loop.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

variable gc-list
variable gc-string
variable gc-vector
variable gc-closure
variable gc-cycle
variable gc-tail-a
variable gc-tail-b
variable gc-holder
variable gc-arena-cons
variable gc-old
variable gc-pre-list
variable gc-pre-sym
variable gc-new-sym

\ Test variables are dictionary cells; the collector must update them when
\ their contents move.
gc-list 1 baku-gc-root+
gc-string 1 baku-gc-root+
gc-vector 1 baku-gc-root+
gc-closure 1 baku-gc-root+
gc-cycle 1 baku-gc-root+
gc-tail-a 1 baku-gc-root+
gc-tail-b 1 baku-gc-root+
gc-holder 1 baku-gc-root+
gc-arena-cons 1 baku-gc-root+
gc-pre-list 1 baku-gc-root+

: gc-unsupported-test ( -- )
	65536 baku-gc-create
	baku-gc-created? @ 1 check
	baku-gc-active? 0= 2 check
	['] baku-gc-activate catch baku-gc-unsupported = 3 check
	baku-gc-active? 0= 4 check
	['] baku-gc-collect catch baku-gc-inactive = 5 check ;

: gc-garbage ( n -- )
	0 ?do
		baku-nil baku-nil baku-cons drop
	loop ;

: gc-supported-test ( -- )
	65536 baku-gc-create
	baku-gc-created? @ 1 check
	baku-gc-active? 0= 2 check
	baku-gc-activate
	baku-gc-active? 3 check
	baku-gc-used? 0= 4 check

	\ A cons, its two cells and a move to the other semispace.
	1 baku-fixnum 2 baku-fixnum baku-cons gc-list !
	gc-list @ baku-region-of baku-region-gc = 5 check
	gc-list @ gc-old !
	baku-gc-collect
	gc-list @ gc-old @ <> 6 check
	gc-list @ baku-region-of baku-region-gc = 7 check
	gc-list @ baku-hd baku-fixnum-value 1 = 8 check
	gc-list @ baku-tl baku-fixnum-value 2 = 9 check

	\ A value that is only on the Forth data stack across the collection.
	7 baku-fixnum 8 baku-fixnum baku-cons
	baku-gc-collect
	dup baku-cons? 10 check
	dup baku-hd baku-fixnum-value 7 = 11 check
	dup baku-tl baku-fixnum-value 8 = 12 check
	drop

	\ A cycle reachable from one root survives, and its two objects remain a
	\ cycle after both are moved.
	baku-nil baku-nil baku-cons gc-cycle !
	baku-nil baku-nil baku-cons gc-tail-b !
	gc-tail-b @ gc-cycle @ baku-set-tl
	gc-cycle @ gc-tail-b @ baku-set-tl
	baku-gc-collect
	gc-cycle @ baku-cons? 13 check
	gc-cycle @ baku-tl baku-cons? 14 check
	gc-cycle @ baku-tl baku-tl gc-cycle @ = 15 check

	\ Two lists sharing a tail must still share it after a move.
	baku-nil baku-nil baku-cons gc-tail-a !
	baku-nil gc-tail-a @ baku-cons gc-cycle !
	baku-nil gc-tail-a @ baku-cons gc-tail-b !
	baku-gc-collect
	gc-cycle @ baku-tl gc-tail-b @ baku-tl = 16 check
	gc-tail-a @ baku-cons? 17 check

	\ A string carries its length and bytes through a move.
	s" gc string" baku-string gc-string !
	baku-gc-collect
	gc-string @ baku-string-length 9 = 18 check
	gc-string @ 0 baku-string@ 103 = 19 check

	\ A vector traces every element.
	3 baku-vector gc-vector !
	gc-list @ gc-vector @ 0 baku-vector!
	baku-gc-collect
	gc-vector @ baku-vector-length 3 = 20 check
	gc-vector @ 0 baku-vector@ baku-cons? 21 check
	gc-vector @ 0 baku-vector@ gc-list @ = 22 check

	\ An interpreted closure traces its code slot and captured environment.
	baku-nil 1 baku-fixnum 2 baku-fixnum baku-cons 0 0 baku-make-closure
	gc-closure !
	baku-gc-collect
	gc-closure @ baku-closure? 23 check
	gc-closure @ baku-closure-env baku-cons? 24 check
	gc-closure @ baku-closure-env baku-hd baku-fixnum-value 1 = 25 check

	\ A pre-GC global entry lives in non-GC memory.  Updating its binding to a
	\ GC value after activation exercises the shape-aware table root walk.
	gc-pre-sym @ gc-list @ baku-global-define drop
	baku-gc-collect
	gc-pre-sym @ baku-global-lookup if gc-list @ = else false then 26 check
	gc-pre-list @ baku-region-of baku-region-nongc = 27 check
	gc-pre-list @ baku-hd baku-fixnum-value 1 = 28 check

	\ A global entry created after activation lives in the GC and is reached
	\ through a bucket root.
	s" gc-new-global" baku-intern gc-new-sym !
	gc-new-sym @ gc-list @ baku-global-define drop
	baku-gc-collect
	gc-new-sym @ baku-global-lookup if gc-list @ = else false then 29 check

	\ Unreachable allocation is reclaimed: the stress loop allocates far more
	\ than one semispace and several collections must run.
	baku-gc-collections @ gc-old !
	20000 gc-garbage
	baku-gc-collections @ gc-old @ > 30 check
	baku-gc-collect
	baku-gc-used? 4096 < 31 check

	\ An arena may be created while the GC is activated.  The GC becomes
	\ inactive, refuses to collect or activate, and resumes after the release.
	baku-nil baku-nil baku-cons gc-holder !
	baku-arena-create
	baku-gc-active? 0= 32 check
	['] baku-gc-collect catch baku-gc-arena-active = 33 check
	['] baku-gc-activate catch baku-gc-arena-active = 34 check
	baku-nil baku-nil baku-cons gc-arena-cons !
	gc-arena-cons @ baku-region-of baku-region-arena = 35 check
	gc-arena-cons @ gc-holder @ baku-set-hd
	baku-arena-free
	baku-gc-active? 36 check
	baku-gc-collect
	gc-holder @ baku-cons? 37 check
	gc-holder @ baku-hd baku-object? 0= 38 check ;

: gc-pre-setup ( -- )
	1 baku-fixnum 2 baku-fixnum baku-cons gc-pre-list !
	s" gc-pre" baku-intern gc-pre-sym !
	gc-pre-sym @ 7 baku-fixnum baku-global-define drop ;

: gc-run ( -- )
	baku-gc-stack-scan? if gc-supported-test else gc-unsupported-test then ;

gc-pre-setup
gc-run

." BAKU-TEST-DONE" cr
