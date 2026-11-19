\ Fixed portability conformance set.
\
\ Portability is the product claim: the same shipped sources must produce the
\ same Shen-level answers on every ANS Forth 2012 target.  This file therefore
\ evaluates one fixed expression set through the shipped KLambda entry point and
\ is registered for every available target by the CMake test glob.  Passing on
\ both Sloth and gforth is the 64-bit-cell acceptance evidence required by
\ specs/forth-portability.md.
\
\ The set covers integer arithmetic (including a value wider than 32 bits),
\ comparison, cons/list construction, string construction and access, symbol
\ interning, vector creation and access, trap-error catchability and a
\ tail-recursive countdown.  It deliberately uses only fixnum-to-string and
\ string concatenation for its strings: a Forth S" literal cannot contain the
\ KLambda double quote, and building the forms by concatenation keeps the test
\ independent of host string-escape extensions.
\
\ The parameterised countdown allocates one interpreted frame per iteration, so
\ the symbol-area request is raised from the default to 1 MiB.  Deeper
\ constant-space evidence is in test/eval.4th and test/gc-mode.4th; this file
\ only needs the answer to agree across targets.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	1048576 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	1048576 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a conformance form" cr abort
	then
	baku-eval-kl ;

\ Decode a fixnum result; a float or another type is a failure, not a silent
\ reinterpretation of the tagged cell.  The check number makes a type failure
\ as locatable as a value mismatch.
variable conf-code

: fix ( value -- n )
	dup baku-fixnum? 0= if
		." BAKU-TEST-FAIL: expected a fixnum at " conf-code @ . cr abort
	then
	baku-fixnum-value ;

: check-fix ( c-addr u expected code -- )
	dup conf-code !
	>r >r run fix r> = r> check ;

: check-bool ( c-addr u expected code -- )
	>r >r run r> = r> check ;

: check-eq ( value expected code -- )
	>r baku-eq? r> check ;

\ SYMBOL? is a kernel defun, not a host primitive, so the symbol check reads the
\ host classifier instead of evaluating an undefined head before boot.
: check-symbol ( c-addr u code -- )
	>r run dup baku-symbol? r> check drop ;

\ ---------------------------------------------------------------------------
\ Integer arithmetic.  The last pair needs more than 32 bits, so it is the
\ 64-bit-cell check; a 32-bit adaptation must keep this value in a double or a
\ boxed integer.
\ ---------------------------------------------------------------------------

s" (+ 2 3)" 5 1 check-fix
s" (- 10 4)" 6 2 check-fix
s" (* 6 7)" 42 3 check-fix
s" (/ 10 2)" 5 4 check-fix
s" (+ 9999999999 1)" 10000000000 5 check-fix
s" (= 10000000000 10000000000)" baku-true 6 check-bool

\ Exact integer division stays a fixnum; an inexact quotient is a boxed float.
s" (/ 10 2)" run dup baku-fixnum? 7 check baku-fixnum-value 5 = 8 check
s" (/ 7 2)" run dup baku-float? 9 check baku-float@ 3.5e 0.000001e f~ 10 check

\ ---------------------------------------------------------------------------
\ Comparison.
\ ---------------------------------------------------------------------------

s" (< 1 2)" baku-true 11 check-bool
s" (> 3 2)" baku-true 12 check-bool
s" (>= 2 2)" baku-true 13 check-bool
s" (<= 2 3)" baku-true 14 check-bool
s" (= 4 4)" baku-true 15 check-bool
s" (= 4 5)" baku-false 16 check-bool

\ ---------------------------------------------------------------------------
\ Cons and list construction.
\ ---------------------------------------------------------------------------

s" (hd (cons 1 2))" 1 17 check-fix
s" (tl (cons 1 2))" 2 18 check-fix
s" (cons? (cons 1 2))" baku-true 19 check-bool
s" (hd (tl (cons 1 (cons 2 ()))))" 2 20 check-fix
s" (= (cons 1 (cons 2 ())) (cons 1 (cons 2 ())))" baku-true 21 check-bool

\ ---------------------------------------------------------------------------
\ Strings.  BAKU.CONFORMANCE.S holds "1234" as (CN (STR 12) (STR 34)).
\ ---------------------------------------------------------------------------
s" (set baku.conformance.s (cn (str 12) (str 34)))"
	run s" 1234" baku-string 22 check-eq
s" (string? (value baku.conformance.s))" baku-true 23 check-bool
s" (pos (value baku.conformance.s) 1)" run s" 2" baku-string 24 check-eq
s" (tlstr (value baku.conformance.s))"
	run s" 234" baku-string 25 check-eq
s" (str 42)" run s" 42" baku-string 26 check-eq

\ ---------------------------------------------------------------------------
\ Symbol interning.  Two interns of the same spelling are the same object;
\ distinct spellings are not.
\ ---------------------------------------------------------------------------

s" (intern (str 7))" 27 check-symbol
s" (set baku.conformance.y (intern (str 7)))" run drop
s" (= (value baku.conformance.y) (intern (str 7)))" baku-true 28 check-bool
s" (= (intern (str 7)) (intern (str 8)))" baku-false 29 check-bool

\ ---------------------------------------------------------------------------
\ Vector creation and access.  ADDRESS-> stores in place and returns the vector.
\ An unset slot holds raw zero, which is not a Shen value, so store before read.
\ ---------------------------------------------------------------------------

s" (set baku.conformance.v (absvector 3))" run dup baku-vector? 30 check drop
s" (address-> (value baku.conformance.v) 0 42)" run dup baku-vector? 31 check drop
s" (<-address (value baku.conformance.v) 0)" 42 32 check-fix
s" (absvector? (value baku.conformance.v))" baku-true 33 check-bool

\ ---------------------------------------------------------------------------
\ Trap-error catchability.
\ ---------------------------------------------------------------------------

s" (trap-error (hd 1) (lambda E 99))" 99 34 check-fix
s" (trap-error (+ 1 (hd 1)) (lambda E 7))" 7 35 check-fix
s" (trap-error (= 1 1) (lambda E 0))" baku-true 36 check-bool
s" (trap-error (simple-error (str 9)) (lambda E (error-to-string E)))"
	run s" 9" baku-string 37 check-eq

\ ---------------------------------------------------------------------------
\ Tail-recursive countdown.  The call is in tail position, so the shared
\ trampoline must run the 1000 iterations without growing the Forth return
\ stack.  Deeper TCO evidence lives in test/eval.4th, which is not part of the
\ cross-target conformance set.
\ ---------------------------------------------------------------------------

s" (defun baku.conformance.countdown (N) (if (= N 0) 0 (baku.conformance.countdown (- N 1))))"
	run drop
s" (baku.conformance.countdown 1000)" 0 38 check-fix

." BAKU-TEST-DONE" cr
