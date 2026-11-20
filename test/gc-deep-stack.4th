\ Deep data-stack collection test.
\
\ The collector roots the Forth data stack.  The adapter that walks it must not
\ move every live cell through the return stack: with a return stack smaller
\ than the data stack, a deep but valid data stack overflows it during the walk,
\ after the collector has already moved roots and tables, so the collection
\ cannot resume.  gforth runs this test with -r 64k for that reason; Sloth uses
\ 16384 cells for both stacks and still covers a large data-stack collection.
\
\ The test holds 12000 live conses on the data stack and forces a collection.
\ The adapter snapshots the cells into a host buffer, so its return-stack use
\ stays constant and every cons is a moved GC object afterwards.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

\ Each iteration leaves one cons, so the data stack holds all of them when the
\ loop ends.
: gds-push-conses ( n -- )
	0 ?do
		i baku-fixnum dup baku-fixnum baku-cons
	loop ;

\ Every live cons must have moved into the selected GC semispace.
: gds-check-conses ( n -- )
	0 ?do
		dup baku-cons? 0= if
			." BAKU-TEST-FAIL: data-stack value is not a cons" cr abort
		then
		dup baku-region-of baku-region-gc = 0= if
			." BAKU-TEST-FAIL: data-stack cons is not in the GC region"
			cr abort
		then
		drop
	loop ;

2097152 baku-gc-semispace-request !
baku-gc-create
baku-gc-created? @ 1 check
baku-gc-semispace @ 2097152 = 2 check
baku-gc-activate
baku-gc-active? 3 check
12000 gds-push-conses
baku-gc-collect
12000 gds-check-conses
baku-gc-collections @ 0> 4 check

." BAKU-TEST-DONE" cr
