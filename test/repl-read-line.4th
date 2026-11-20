\ BAKU-REPL-READ-LINE tests.
\
\ The line reader is the shared input path of the interactive REPL and file
\ mode.  It takes a stream and returns an end-of-input flag, so it must consume
\ its stream argument on every exit.  The old newline and end-of-file exits left
\ the stream on the data stack: every line leaked one cell and a long session
\ would eventually overflow the stack.  This layer test reads a host file
\ directly and checks the net stack depth around each call, so it does not need
\ to boot the kernel.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

variable rl-stream
variable rl-depth
variable rl-eof

\ The contents are "ab\ncd": the first line exits on the newline, the second on
\ end of input, and a further call reads end of input immediately.
create rl-data 97 c, 98 c, 10 c, 99 c, 100 c,

: rl-write ( -- )
	s" baku-repl-read-line.tmp" w/o bin create-file throw >r
	rl-data 5 r@ write-file throw
	r> close-file throw ;

: rl-open ( -- )
	s" baku-repl-read-line.tmp" r/o bin open-file throw
	baku-stream-file swap baku-stream rl-stream ! ;

\ Read one line, store the flag and require the data-stack depth to return to
\ its value before the call.  A leaked stream argument shows up as depth +1.
: rl-read ( code -- )
	>r
	depth rl-depth !
	rl-stream @ baku-repl-read-line rl-eof !
	depth rl-depth @ - 0 r> check-num ;

rl-write
rl-open

0 rl-read
rl-eof @ 0= 2 check
baku-repl-acc-len @ 3 3 check-num
baku-repl-line-buf c@ 97 4 check-num
baku-repl-line-buf 1+ c@ 98 5 check-num
baku-repl-line-buf 2 + c@ 10 6 check-num

7 rl-read
rl-eof @ 8 check
baku-repl-acc-len @ 5 9 check-num
baku-repl-line-buf 3 + c@ 99 10 check-num
baku-repl-line-buf 4 + c@ 100 11 check-num

12 rl-read
rl-eof @ 13 check

rl-stream @ baku-prim-close drop
s" baku-repl-read-line.tmp" delete-file 0= 14 check

." BAKU-TEST-DONE" cr
