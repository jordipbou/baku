\ Differential between the non-GC native path and the interpreter.
\
\ The interpreter is the correctness reference and the native compiler must
\ match it.  test/native.4th already compares the two paths structurally with
\ BAKU-EQ? over a pure expression corpus.  This file supplies the missing half:
\ a fixed program set whose *observable output* must be byte-identical.
\
\ Every case is evaluated twice in one process: once through BAKU-EVAL-KL (the
\ interpreter) and once through BAKU-NATIVE-EVAL-KL (the non-GC native entry).
\ The two values must be structurally equal, and formatting both with the same
\ host STR formatter (the one the kernel STR primitive uses) must produce the
\ same bytes.  One BAKU-MODE line records the canonical text so a failing run
\ shows which case diverged.
\
\ Definitions are compared the same way without a second naming scheme: a
\ defun is installed by the interpreter, called, then installed by the native
\ backend with last-definition-wins, and called again.  The two calls therefore
\ run the same source through the two executors.
\
\ Error cases compare the caught raw Forth code, which is the observable error
\ class; both paths must raise the same class.
\
\ Results are projected to atoms because BAKU-PRIM-STR formats atoms only.  This
\ is the same projection the kernel's own STR primitive performs.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	2097152 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	2097152 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

variable mode-code
variable mode-interp
variable mode-native
variable mode-interp-out
variable mode-native-out

\ The production layer has no host THROW primitive; register the same test
\ primitive test/native.4th uses so the trap-error cases exercise a real raise
\ instead of an undefined-function error caught as a fixnum.
: mode-throw ( x -- ) baku-raise ;
' mode-throw 1 s" throw" baku-intern baku-defprim

: mode-fail ( -- )
	." BAKU-TEST-FAIL: mode differential check " mode-code @ . cr abort ;

: mode-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a mode differential form" cr abort
	then ;

: mode-eval-interp ( c-addr u -- value ) mode-read baku-eval-kl ;
: mode-eval-native ( c-addr u -- value ) mode-read baku-native-eval-kl ;

\ Compare the two captured values structurally and as printed text, then emit
\ the one canonical line for this case.
: mode-compare ( -- )
	mode-interp @ mode-native @ baku-eq? 0= if mode-fail then
	mode-interp @ baku-prim-str mode-interp-out !
	mode-native @ baku-prim-str mode-native-out !
	mode-interp-out @ mode-native-out @ baku-string= 0= if mode-fail then
	." BAKU-MODE " mode-code @ . ." = "
	mode-interp-out @ baku-string-addr
	mode-interp-out @ baku-string-length type cr ;

\ One pure form through both entries.
: mode-case ( c-addr u code -- )
	mode-code !
	2dup mode-eval-interp mode-interp !
	mode-eval-native mode-native !
	mode-compare ;

\ The same defun installed and called by each executor in turn.
variable mode-def-addr
variable mode-def-len
variable mode-call-addr
variable mode-call-len

: mode-def-case ( c-addr u call-addr call-u code -- )
	mode-code !
	mode-call-len ! mode-call-addr !
	mode-def-len ! mode-def-addr !
	mode-def-addr @ mode-def-len @ mode-eval-interp drop
	mode-call-addr @ mode-call-len @ mode-eval-interp mode-interp !
	mode-def-addr @ mode-def-len @ mode-eval-native drop
	mode-call-addr @ mode-call-len @ mode-eval-native mode-native !
	mode-compare ;

\ CATCH restores the operand stack to its state just before the protected word
\ and then pushes the throw code.  MODE-READ runs outside the protected word, so
\ on failure that restored state is just the form cell: drop it and keep the
\ code.  On success the result sits below the zero code, so NIP keeps the zero.
\
\ The xt is held in a variable rather than on the return stack across MODE-READ:
\ BAKU-READ-FORM uses CATCH internally, and a pending return-stack cell across
\ that nested catch is not reliable on every target.
variable mode-catch-xt

: mode-catch ( c-addr u xt -- code )
	mode-catch-xt ! mode-read mode-catch-xt @ catch
	dup 0= if nip else >r drop r> then ;

variable mode-form-addr
variable mode-form-len

: mode-error-case ( c-addr u code -- )
	mode-code !
	mode-form-len ! mode-form-addr !
	mode-form-addr @ mode-form-len @
		['] baku-eval-kl mode-catch mode-interp !
	mode-form-addr @ mode-form-len @
		['] baku-native-eval-kl mode-catch mode-native !
	mode-interp @ 0= if mode-fail then
	mode-interp @ mode-native @ <> if mode-fail then
	." BAKU-MODE " mode-code @ . ." error=" mode-interp @ . cr ;

\ ---------------------------------------------------------------------------
\ Arithmetic and comparison.
\ ---------------------------------------------------------------------------

s" (+ 1 2)" 1 mode-case
s" (+ 9999999999 1)" 2 mode-case
s" (- 10 4)" 3 mode-case
s" (* 6 7)" 4 mode-case
s" (= 10000000000 10000000000)" 5 mode-case
\ SHEN / is not Forth /: an inexact quotient is a boxed float.
s" (= (/ 7 2) 3.5)" 6 mode-case
s" (< 1 2)" 7 mode-case
s" (> 3 2)" 8 mode-case
s" (= 4 5)" 9 mode-case

\ ---------------------------------------------------------------------------
\ Cons, strings, symbols and vectors.
\ ---------------------------------------------------------------------------

s" (hd (cons 1 2))" 10 mode-case
s" (tl (cons 1 2))" 11 mode-case
s" (cons? (cons 1 2))" 12 mode-case
s" (cons? ())" 13 mode-case
14 mode-code !
s" (= (cons 1 (cons 2 ())) (cons 1 (cons 2 ())))" 14 mode-case
s" (str 42)" 15 mode-case
s" (cn (str 12) (str 34))" 16 mode-case
s" (pos (cn (str 12) (str 34)) 1)" 17 mode-case
s" (str (intern (str 7)))" 18 mode-case
s" (= (intern (str 7)) (intern (str 7)))" 19 mode-case
20 mode-code !
s" (let V (absvector 3) (<-address (address-> V 0 42) 0))" 20 mode-case
s" (absvector? (absvector 2))" 21 mode-case

\ ---------------------------------------------------------------------------
\ Closures, currying and trap-error.
\ ---------------------------------------------------------------------------

s" ((lambda X (+ X 1)) 41)" 22 mode-case
23 mode-code !
s" (let F (lambda X (lambda Y (+ X Y))) (let G (F 40) (G 2)))" 23 mode-case
s" (let F (lambda X (+ X 1)) (F 41))" 24 mode-case
s" (let F (+ 1) (F 2))" 25 mode-case
s" (hd (let F (cons 1) (F 2)))" 26 mode-case
s" (trap-error (+ 1 2) (lambda E 0))" 27 mode-case
s" (trap-error (throw 7) (lambda E E))" 28 mode-case
s" (trap-error (hd 1) (lambda E 99))" 29 mode-case
s" (trap-error (+ 1 (hd 1)) (lambda E 7))" 30 mode-case

\ ---------------------------------------------------------------------------
\ Recursion, tail recursion and allocation-heavy loops.
\ ---------------------------------------------------------------------------

: mode-fact-def ( -- c-addr u )
	s" (defun mode.fact (N) (if (= N 0) 1 (* N (mode.fact (- N 1)))))" ;
: mode-fact-call ( -- c-addr u ) s" (mode.fact 10)" ;
mode-fact-def mode-fact-call 31 mode-def-case

: mode-count-def ( -- c-addr u )
	s" (defun mode.count (N) (if (= N 0) 0 (mode.count (- N 1))))" ;
: mode-count-call ( -- c-addr u ) s" (mode.count 1000)" ;
mode-count-def mode-count-call 32 mode-def-case

\ A non-tail recursion that allocates a cons per step.
: mode-build-def ( -- c-addr u )
	s" (defun mode.build (N) (if (= N 0) () (cons N (mode.build (- N 1)))))" ;
: mode-build-call ( -- c-addr u ) s" (hd (mode.build 200))" ;
mode-build-def mode-build-call 33 mode-def-case

\ A tail recursion that allocates a let binding per step.
: mode-alloc-def ( -- c-addr u )
	s" (defun mode.alloc (N) (if (= N 0) 0 (let X (cons N N) (mode.alloc (- N 1)))))" ;
: mode-alloc-call ( -- c-addr u ) s" (mode.alloc 1000)" ;
mode-alloc-def mode-alloc-call 34 mode-def-case

\ ---------------------------------------------------------------------------
\ Error classes.
\ ---------------------------------------------------------------------------

\ The form text is needed across a call and across a caught throw, so keep it
\ in a colon definition rather than an interpreted S" transient buffer.
: mode-cond-form ( -- c-addr u ) s" (cond (false 1))" ;
: mode-not-callable-form ( -- c-addr u ) s" (1 2)" ;
: mode-undefined-form ( -- c-addr u ) s" (no-such-mode-function 1)" ;
: mode-arity-form ( -- c-addr u ) s" ((lambda X X) 1 2)" ;
: mode-front-form ( -- c-addr u ) s" (if X)" ;

mode-cond-form 35 mode-error-case
mode-not-callable-form 36 mode-error-case
mode-undefined-form 37 mode-error-case
mode-arity-form 38 mode-error-case
mode-front-form 39 mode-error-case

." BAKU-MODE-TOTAL 39" cr
." BAKU-TEST-DONE" cr
