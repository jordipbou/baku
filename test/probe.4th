\ Startup probe tests: every required wordset is present, MARKER/DOES> restores
\ the dictionary, and an absent word is recorded as a failure, not a pass.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.  This is the same documented
\ test-only spelling used by the other Baku tests.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: probe-check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

baku-probe-fail @ 0= 1 probe-check
baku-probe-facility @ 0= 2 probe-check
[DEFINED] TIME&DATE 11 probe-check
baku-probe-memory @ 0= 3 probe-check
baku-probe-floating @ 0= 4 probe-check
baku-probe-file @ 0= 5 probe-check
baku-probe-exception @ 0= 6 probe-check
baku-probe-double @ 0= 7 probe-check
baku-probe-marker-ok @ 0<> 8 probe-check

\ The helper must record a missing word instead of silently passing it.
variable probe-absence 0 probe-absence !
false probe-absence s" PROBE/SELF-TEST" baku-probe-word
probe-absence @ 0<> 9 probe-check

\ The group summary must count a missing wordset as a failure.
0 baku-probe-fail !
true s" PROBE/SELF-TEST-GROUP" baku-probe-group
baku-probe-fail @ 1 = 10 probe-check

." BAKU-TEST-DONE" cr
