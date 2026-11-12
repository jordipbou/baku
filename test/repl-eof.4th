\ End of the standard input.
\
\ ANS KEY has no end-of-input value: gforth raises when no input is left.  The
\ REPL maps that error to -1, the same value a file stream reports, so the
\ interactive loop exits cleanly instead of looping or hanging.  This test runs
\ with an empty standard input (CTest passes test/empty.stdin), which is the one
\ place gforth can observe the KEY path; Sloth's KEY cannot reach end of input in
\ the harness.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

baku-stdin-stream baku-repl-byte -1 = 1 check

." BAKU-TEST-DONE" cr
