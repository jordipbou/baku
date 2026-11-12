\ Fixed cross-target differential program.
\
\ The product claim is that the same shipped sources produce the same observable
\ answers on every ANS Forth 2012 target.  test/conformance.4th asserts that each
\ target computes the expected value; this file supplies the missing half: it
\ emits a deterministic line for every result so test/differential-targets.cmake
\ can compare the Sloth and gforth transcripts byte for byte.
\
\ Only the BAKU-DIFF lines are compared.  Launcher banners, the startup-probe
\ report, gforth's redefinition warnings and any timing chatter are therefore
\ normalised away without the comparison runner needing target-specific rules.
\ Each line still carries an assertion, so a wrong answer fails the target test
\ even when both targets agree on it.
\
\ The expressions cover arithmetic (including a value wider than 32 bits),
\ comparison, cons/list construction, strings, symbols, vectors, closures and
\ currying, trap-error, non-tail recursion and tail recursion.  Results printed
\ here are atoms because BAKU-PRIM-STR is the host formatter used by the kernel's
\ own STR primitive; compound values are projected to their atoms first.
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

variable diff-code
variable diff-expect
variable diff-expect-addr
variable diff-expect-len

: bad ( -- )
	." BAKU-TEST-FAIL: differential check " diff-code @ . cr abort ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a differential form" cr abort
	then
	baku-native-eval-kl ;

\ Convert an atom result to text with the same formatter the kernel STR
\ primitive uses, then emit one compare line.
: emit ( c-addr u value -- )
	baku-prim-str                     ( c-addr u str )
	>r                                ( c-addr u | R: str )
	." BAKU-DIFF " type ." = "
	r> dup baku-string-addr swap baku-string-length type cr ;

: cf ( c-addr u expected -- )
	diff-expect !
	2dup run
	dup baku-fixnum? 0= if bad then
	dup baku-fixnum-value diff-expect @ = 0= if bad then
	emit ;

: cb ( c-addr u expected -- )
	diff-expect !
	2dup run
	dup baku-immediate? 0= if bad then
	dup diff-expect @ = 0= if bad then
	emit ;

: cs ( c-addr u expected-addr expected-len -- )
	diff-expect-len ! diff-expect-addr !
	2dup run
	dup baku-string? 0= if bad then
	dup diff-expect-addr @ diff-expect-len @ baku-string baku-string= 0= if bad then
	emit ;

\ ---------------------------------------------------------------------------
\ Arithmetic and comparison.
\ ---------------------------------------------------------------------------

1 diff-code ! s" (+ 2 3)" 5 cf
2 diff-code ! s" (+ 9999999999 1)" 10000000000 cf
3 diff-code ! s" (- 10 4)" 6 cf
4 diff-code ! s" (* 6 7)" 42 cf
5 diff-code ! s" (= 10000000000 10000000000)" baku-true cb
\ SHEN / is not Forth /: an inexact quotient is a boxed float.
6 diff-code ! s" (= (/ 7 2) 3.5)" baku-true cb
7 diff-code ! s" (< 1 2)" baku-true cb
8 diff-code ! s" (> 3 2)" baku-true cb
9 diff-code ! s" (= 4 5)" baku-false cb

\ ---------------------------------------------------------------------------
\ Cons and list construction.
\ ---------------------------------------------------------------------------

10 diff-code ! s" (hd (cons 1 2))" 1 cf
11 diff-code ! s" (tl (cons 1 2))" 2 cf
12 diff-code ! s" (cons? (cons 1 2))" baku-true cb
13 diff-code ! s" (cons? ())" baku-false cb
14 diff-code !
s" (= (cons 1 (cons 2 ())) (cons 1 (cons 2 ())))" baku-true cb

\ ---------------------------------------------------------------------------
\ Strings, symbols and vectors.
\ ---------------------------------------------------------------------------

\ Expected strings live in colon definitions so they are compiled into the
\ dictionary.  Two interpreted S" literals on one line can share (or overlap) a
\ transient buffer on some targets, which would let the expected text overwrite
\ the form text before RUN reads it.
: expected-42 ( -- c-addr u ) s" 42" ;
: expected-1234 ( -- c-addr u ) s" 1234" ;
: expected-2 ( -- c-addr u ) s" 2" ;
: expected-7 ( -- c-addr u ) s" 7" ;

15 diff-code ! s" (str 42)" expected-42 cs
16 diff-code ! s" (cn (str 12) (str 34))" expected-1234 cs
17 diff-code ! s" (pos (cn (str 12) (str 34)) 1)" expected-2 cs
18 diff-code ! s" (str (intern (str 7)))" expected-7 cs
19 diff-code ! s" (= (intern (str 7)) (intern (str 7)))" baku-true cb
20 diff-code !
s" (let V (absvector 3) (<-address (address-> V 0 42) 0))" 42 cf
21 diff-code ! s" (absvector? (absvector 2))" baku-true cb

\ ---------------------------------------------------------------------------
\ Closures, currying, trap-error and recursion.
\ ---------------------------------------------------------------------------

22 diff-code ! s" ((lambda X (+ X 1)) 41)" 42 cf
23 diff-code ! s" (let F (lambda X (lambda Y (+ X Y))) (let G (F 40) (G 2)))" 42 cf
24 diff-code ! s" (let F (lambda X (+ X 1)) (F 41))" 42 cf
25 diff-code ! s" (trap-error (hd 1) (lambda E 99))" 99 cf
26 diff-code ! s" (trap-error (+ 1 (hd 1)) (lambda E 7))" 7 cf

s" (defun diff.fact (N) (if (= N 0) 1 (* N (diff.fact (- N 1)))))"
	run drop
27 diff-code ! s" (diff.fact 10)" 3628800 cf

s" (defun diff.count (N) (if (= N 0) 0 (diff.count (- N 1))))"
	run drop
28 diff-code ! s" (diff.count 1000)" 0 cf

." BAKU-TEST-DONE" cr
