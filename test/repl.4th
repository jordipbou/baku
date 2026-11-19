\ Top-level tests: the interactive loop, expression mode and file mode.
\
\ This boots and initialises the whole kernel under the Cheney collector with
\ the tree-walking interpreter as the only executor.  Sloth's Debug execution
\ is far too slow for that boot, so the test is registered for gforth only (see
\ CMakeLists.txt).
\
\ Output is the observable boundary of a top level, so the test binds *STOUTPUT*
\ and *STERROR* to a file stream and reads the bytes back.  The prompt, the
\ printed value and the error display all go through the kernel writer, which is
\ exactly what a user sees.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	S" 4th/baku.4th" INCLUDED
[THEN]

baku-gc-create
baku-gc-activate
baku-compat-init
baku-repl-init

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

\ ---------------------------------------------------------------------------
\ Output capture.  A top-level run prints through the kernel writer, so the
\ test binds the stream globals and compares the file bytes.
\ ---------------------------------------------------------------------------

create test-capture-path 64 allot
variable test-capture-path-len
variable test-capture-fileid
create test-capture-buf 65536 allot
variable test-capture-len
variable test-stdout

create test-out-3  51 c, 10 c,
create test-out-1  49 c, 10 c,
create test-out-3628800  51 c, 54 c, 50 c, 56 c, 56 c, 48 c, 48 c, 10 c,

: test-bind-streams ( obj -- )
	dup s" *stoutput*" baku-intern swap baku-global-define drop
	s" *sterror*" baku-intern swap baku-global-define drop ;

: test-capture-open ( c-addr u -- )
	dup test-capture-path-len !
	2dup test-capture-path swap cmove
	w/o bin create-file throw
	baku-stream-file swap baku-stream
	test-bind-streams ;

: test-capture-close ( -- )
	s" *stoutput*" baku-intern baku-global-lookup drop
	baku-prim-close drop
	test-capture-path test-capture-path-len @
	r/o bin open-file throw test-capture-fileid !
	test-capture-buf 65536 test-capture-fileid @ read-file throw
	test-capture-len !
	test-capture-fileid @ close-file throw
	test-stdout @ test-bind-streams ;

variable test-exp-addr
variable test-exp-len

: test-show-capture ( -- )
	." capture: [" test-capture-buf test-capture-len @ type ." ]" cr ;

: test-expect ( c-addr u -- )
	test-exp-len ! test-exp-addr !
	test-exp-len @ test-capture-len @ <> if
		." BAKU-TEST-FAIL: capture length " test-capture-len @
		." expected " test-exp-len @ cr
		test-show-capture abort
	then
	test-exp-addr @ test-exp-len @
	test-capture-buf test-capture-len @ compare 0<> if
		." BAKU-TEST-FAIL: capture mismatch" cr test-show-capture abort
	then ;

: test-contains ( c-addr u -- )
	test-exp-len ! test-exp-addr !
	test-capture-buf test-capture-len @
	test-exp-addr @ test-exp-len @
	search 0= if
		." BAKU-TEST-FAIL: missing [" test-exp-addr @ test-exp-len @ type
		." ]" cr test-show-capture abort
	then
	2drop ;

\ ---------------------------------------------------------------------------
\ Boot.
\ ---------------------------------------------------------------------------

baku-boot-load-kernel

baku-boot-files @ 23 1 check-num
baku-boot-forms @ 1124 2 check-num
baku-boot-defuns @ 1118 3 check-num

baku-boot-globals
baku-boot-initialise

s" *stoutput*" baku-intern baku-global-lookup drop test-stdout !

\ ---------------------------------------------------------------------------
\ Expression mode.  The result is the kernel's printed value; the flag is the
\ CLI exit decision and is also what makes a failed evaluation detectable.
\ ---------------------------------------------------------------------------

s" baku-repl-expr.out" test-capture-open
s" (+ 1 2)" baku-repl-eval 4 check
test-capture-close
test-out-3 2 test-expect

s" baku-repl-expr.out" test-capture-open
s" (factorial 10)" baku-repl-eval 5 check
test-capture-close
test-out-3628800 8 test-expect

s" baku-repl-expr.out" test-capture-open
s" (arity factorial)" baku-repl-eval 6 check
test-capture-close
test-out-1 2 test-expect

\ A stlib-defined function and its arity table entry prove STLIB.INITIALISE ran.
s" baku-repl-expr.out" test-capture-open
s" (abs -5)" baku-repl-eval 7 check
test-capture-close
create test-out-5  53 c, 10 c,
test-out-5 2 test-expect

\ The version comes from the kernel's *VERSION*, set by SHEN.INITIALISE; the
\ credits banner is the human-readable form of it.
s" baku-repl-expr.out" test-capture-open
s" (version)" baku-repl-eval 8 check
s" (shen.credits)" baku-repl-eval 9 check
test-capture-close
s" 43.2" test-contains
s" version: S43.2" test-contains

\ History and `it` are the kernel's, not a test-only reimplementation.  The
\ kernel sets `it` to the input being read, so `(it)` answers the current line;
\ the history list itself is what SHEN.UPDATE-HISTORY extends.
create test-out-it  34 c, 40 c, 105 c, 116 c, 41 c, 34 c, 10 c,
s" baku-repl-expr.out" test-capture-open
s" (+ 1 2)" baku-repl-eval 10 check
s" (it)" baku-repl-eval 11 check
test-capture-close
test-out-3 2 test-contains
test-out-it 7 test-contains

\ An error is displayed through ERROR-TO-STRING and the success flag is false.
s" baku-repl-expr.out" test-capture-open
s" (simple-error (cn (str 4) (str 2)))" baku-repl-eval 0= 12 check
test-capture-close
s" 42" test-contains

\ ---------------------------------------------------------------------------
\ File mode: the same loop over a stream.  The first form spans two lines, which
\ proves the parse-only continuation check; the input has no trailing newline,
\ which proves end of input evaluates the remaining text instead of hanging.
\ ---------------------------------------------------------------------------

variable test-script-fileid

: test-write-lines ( c-addr1 u1 c-addr2 u2 -- )
	s" baku-repl-script.kl" w/o bin create-file throw
	test-script-fileid !
	2swap
	test-script-fileid @ write-line throw
	test-script-fileid @ write-line throw
	test-script-fileid @ close-file throw ;

: test-write-content ( c-addr u -- )
	s" baku-repl-script.kl" w/o bin create-file throw >r
	r@ write-file throw r> close-file throw ;

s" (+ 1" s" 2)" test-write-lines
s" baku-repl-expr.out" test-capture-open
s" baku-repl-script.kl" baku-repl-file
test-capture-close
test-out-3 2 test-expect
s" baku-repl-script.kl" delete-file 0= 13 check

s" (+ 1 2)" test-write-content
s" baku-repl-expr.out" test-capture-open
s" baku-repl-script.kl" baku-repl-file
test-capture-close
test-out-3 2 test-expect
s" baku-repl-script.kl" delete-file 0= 14 check

\ The session continues after a top-level error: the next line still evaluates.
s" (simple-error (cn (str 4) (str 2)))"
s" (+ 1 2)" test-write-lines
s" baku-repl-expr.out" test-capture-open
s" baku-repl-script.kl" baku-repl-file
test-capture-close
s" 42" test-contains
s" 3" test-contains
s" baku-repl-script.kl" delete-file 0= 15 check

\ An empty file exits cleanly and prints nothing.
s" baku-repl-prompt.out" test-capture-open
s" " test-write-content
s" baku-repl-script.kl" baku-repl-file
test-capture-close
test-capture-len @ 0 16 check-num
s" baku-repl-script.kl" delete-file 0= 17 check

s" baku-repl-expr.out" delete-file 0= 18 check
s" baku-repl-prompt.out" delete-file 0= 19 check

\ ---------------------------------------------------------------------------
\ The compatibility and top-level helpers are installed after collector
\ activation, so their closure records and IR are GC objects.
\ ---------------------------------------------------------------------------

: test-fn ( c-addr u -- closure )
	baku-intern baku-fn-lookup 0= if
		." BAKU-TEST-FAIL: missing installed helper" cr abort
	then ;

s" input+" test-fn
dup baku-region-of baku-region-gc = 20 check
baku-closure-code baku-region-of baku-region-gc = 21 check

s" baku.repl-parse" test-fn
dup baku-region-of baku-region-gc = 22 check
baku-closure-code baku-region-of baku-region-gc = 23 check

s" baku.repl-eval" test-fn
dup baku-region-of baku-region-gc = 24 check
baku-closure-code baku-region-of baku-region-gc = 25 check

." BAKU-TEST-DONE" cr
