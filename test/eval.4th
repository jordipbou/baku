\ KLambda interpreter tests.
\
\ These tests exercise BAKU-EVAL-KL, the single Shen-visible entry point, with a
\ small set of host primitives installed through BAKU-DEFPRIM.  That is the same
\ path the M5 primitive layer will use, so the dispatch, arity check and
\ environment rules are tested here rather than in a test-only evaluator.
\
\ Tail calls are tested at the end with zero-allocation counters so the deep
\ chains do not depend on the size of the non-GC heap.  Currying and the
\ error-object payload are later M4/M5 work; this file proves the tree-walking
\ reference on exact-arity calls.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( value n code -- )
	>r swap baku-fixnum-value = r> check ;

: check-eq ( value expected code -- )
	>r = r> check ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused an evaluator form" cr abort
	then
	baku-eval-kl ;

: check-error ( c-addr u expected code -- )
	>r >r ['] run catch
	r> = r> check ;

\ ---------------------------------------------------------------------------
\ Test primitives.  They use the production registration path.
\ ---------------------------------------------------------------------------

: p+ ( a b -- x )
	baku-fixnum-value swap baku-fixnum-value + baku-fixnum ;

: p* ( a b -- x )
	baku-fixnum-value swap baku-fixnum-value * baku-fixnum ;

: p- ( a b -- x )
	>r baku-fixnum-value r> baku-fixnum-value - baku-fixnum ;

: pid ( x -- x ) ;

: pcons ( a b -- x ) baku-cons ;
: phd ( x -- y ) baku-hd ;
: ptl ( x -- y ) baku-tl ;

: pthrow ( x -- ) baku-raise ;

: peq ( a b -- x )
	= if baku-true else baku-false then ;

: pdo ( a b -- b ) nip ;

' p+ 2 s" +" baku-intern baku-defprim
' p* 2 s" *" baku-intern baku-defprim
' p- 2 s" -" baku-intern baku-defprim
' pid 1 s" id" baku-intern baku-defprim
' pcons 2 s" cons" baku-intern baku-defprim
' phd 1 s" hd" baku-intern baku-defprim
' ptl 1 s" tl" baku-intern baku-defprim
' pthrow 1 s" throw" baku-intern baku-defprim
' peq 2 s" eq" baku-intern baku-defprim
' pdo 2 s" do" baku-intern baku-defprim

\ ---------------------------------------------------------------------------
\ Atoms and calls
\ ---------------------------------------------------------------------------

s" 42" run baku-fixnum-value 42 = 1 check
s" -7" run baku-fixnum-value -7 = 2 check
s" 10000000000" run baku-fixnum-value 10000000000 = 3 check
s" true" run baku-true = 4 check
s" false" run baku-false = 5 check
s" ()" run baku-nil = 6 check
s" foo" run s" foo" baku-intern = 7 check

s" (+ 1 2)" run baku-fixnum-value 3 = 8 check
s" (+ 1 (* 2 3))" run baku-fixnum-value 7 = 9 check
s" (id foo)" run s" foo" baku-intern = 10 check
s" (cons 1 2)" run baku-hd baku-fixnum-value 1 = 11 check
s" (hd (cons 1 2))" run baku-fixnum-value 1 = 12 check
s" (tl (cons 1 2))" run baku-fixnum-value 2 = 13 check

\ A string atom is returned as the string object.  The fixture is read and
\ evaluated before the next read resets the reader scratch arena.
s" test/fixtures/strings.kl" baku-read-file
baku-read-form drop baku-eval-kl
dup baku-string-length 17 = 14 check
drop
baku-read-close

\ ---------------------------------------------------------------------------
\ IF, AND, OR and COND
\ ---------------------------------------------------------------------------

s" (if true 1 2)" run baku-fixnum-value 1 = 15 check
s" (if false 1 2)" run baku-fixnum-value 2 = 16 check

s" (and false (throw 9))" run baku-false = 17 check
s" (or true (throw 9))" run baku-true = 18 check
s" (and true (id 5))" run baku-fixnum-value 5 = 19 check
s" (or false (id 5))" run baku-fixnum-value 5 = 20 check

s" (cond (false 1) (true 2))" run baku-fixnum-value 2 = 21 check
s" (cond ((eq 1 2) 10) (true 20))" run baku-fixnum-value 20 = 22 check
s" (cond (false 1))" baku-eval-cond-failed 23 check-error

\ ---------------------------------------------------------------------------
\ LET, LAMBDA and FREEZE
\ ---------------------------------------------------------------------------

s" (let X 1 (+ X 1))" run baku-fixnum-value 2 = 24 check
s" (let X 1 (let X 2 X))" run baku-fixnum-value 2 = 25 check
s" (let X 1 (let Y 2 (+ X Y)))" run baku-fixnum-value 3 = 26 check

s" ((lambda X (+ X 1)) 41)" run baku-fixnum-value 42 = 27 check
s" (let Y 10 ((lambda X (+ X Y)) 5))" run baku-fixnum-value 15 = 28 check
s" (let F (lambda X (+ X 1)) (F 41))" run baku-fixnum-value 42 = 29 check
s" (let A 1 (let B 2 ((lambda X (+ X B)) A)))" run baku-fixnum-value 3 = 30 check

s" ((freeze 7))" run baku-fixnum-value 7 = 31 check
s" (let Y 3 ((freeze (+ Y 4))))" run baku-fixnum-value 7 = 32 check

\ A closure survives allocation between its creation and its application.
s" (let F (lambda X (+ X 1)) (let G (cons 1 2) (F 41)))" run
baku-fixnum-value 42 = 33 check

\ ---------------------------------------------------------------------------
\ DEFUN and the global function table
\ ---------------------------------------------------------------------------

s" (defun add1 (X) (+ X 1))" run s" add1" baku-intern = 34 check
s" (add1 41)" run baku-fixnum-value 42 = 35 check
s" (defun forty-two () 42)" run s" forty-two" baku-intern = 36 check
s" (forty-two)" run baku-fixnum-value 42 = 37 check
s" (defun two-args (X Y) (- X Y))" run drop
s" (two-args 10 3)" run baku-fixnum-value 7 = 38 check

\ Redefinition is last-definition-wins because BAKU-FN-DEFINE prepends.
s" (defun redefined () 1)" run drop
s" (defun redefined () 2)" run drop
s" (redefined)" run baku-fixnum-value 2 = 39 check

\ ---------------------------------------------------------------------------
\ TRAP-ERROR
\ ---------------------------------------------------------------------------

s" (trap-error (throw 7) (lambda E E))" run baku-fixnum-value 7 = 40 check
s" (trap-error (+ 1 2) (lambda E 0))" run baku-fixnum-value 3 = 41 check
s" (let Y 5 (trap-error (throw 7) (lambda E (+ E Y))))" run
baku-fixnum-value 12 = 42 check
s" (trap-error (trap-error (throw 1) (lambda E (throw (+ E 1)))) (lambda E E))" run
baku-fixnum-value 2 = 43 check

\ ---------------------------------------------------------------------------
\ DO is an ordinary kernel function
\ ---------------------------------------------------------------------------

s" (do (id 1) (id 2))" run baku-fixnum-value 2 = 44 check

\ ---------------------------------------------------------------------------
\ Errors are catchable and leave the interpreter usable
\ ---------------------------------------------------------------------------

s" (no-such-function 1)" baku-eval-undefined 45 check-error
s" (add1)" baku-eval-arity 46 check-error
s" (add1 1 2)" baku-eval-arity 47 check-error
s" (1 2)" baku-eval-not-callable 48 check-error
s" (if X)" baku-front-arity 49 check-error
s" (+ 1 2)" run baku-fixnum-value 3 = 50 check

\ ---------------------------------------------------------------------------
\ Tail calls: constant return-stack space
\
\ The zero-parameter counters allocate nothing per iteration, so the deep tests
\ exercise the trampoline and not the heap.  Without tail-call elimination the
\ same chain overflows Sloth's 16384-cell return stack far below 100,000; the
\ parameterised countdown additionally proves that argument binding survives
\ tail-call elimination.  A tail call inside a trap-error protected form keeps
\ the handler frame, which is why that case is tested separately.
\ ---------------------------------------------------------------------------

variable tail-counter

: pset ( n -- ) baku-fixnum-value tail-counter ! ;

: pstep ( -- flag )
	tail-counter @ 0> if
		tail-counter @ 1- tail-counter !
		baku-true
	else
		baku-false
	then ;

' pset 1 s" pset" baku-intern baku-defprim
' pstep 0 s" pstep" baku-intern baku-defprim

s" (defun tail-spin () (if (pstep) (tail-spin) 0))" run drop
s" (defun tail-even () (if (pstep) (tail-odd) 0))" run drop
s" (defun tail-odd () (if (pstep) (tail-even) 0))" run drop

\ Self tail recursion, 100,000 deep, with no heap growth during the loop.
s" (pset 100000)" run drop
baku-nongc-used >r
s" (tail-spin)" run baku-fixnum-value 0 = 51 check
baku-nongc-used r> - 4096 < 52 check
tail-counter @ 0 = 53 check

\ Mutual tail recursion, 100,000 deep.
s" (pset 100000)" run drop
s" (tail-even)" run baku-fixnum-value 0 = 54 check
tail-counter @ 0 = 55 check

\ A parameterised tail call carries its argument through the trampoline.
s" (defun tail-count (N) (if (eq N 0) 0 (tail-count (- N 1))))" run drop
s" (tail-count 2500)" run baku-fixnum-value 0 = 56 check

\ Tail position through COND, LET and AND.
s" (defun tail-cond () (cond ((pstep) (tail-cond)) (true 0)))" run drop
s" (pset 1000)" run drop
s" (tail-cond)" run baku-fixnum-value 0 = 57 check

s" (defun tail-let () (let X 0 (if (pstep) (tail-let) X)))" run drop
s" (pset 1000)" run drop
s" (tail-let)" run baku-fixnum-value 0 = 58 check

s" (defun tail-and () (and (pstep) (tail-and)))" run drop
s" (pset 1000)" run drop
s" (tail-and)" run baku-false = 59 check

\ The top-level entry point resolves a tail call too.
s" (if true (id 3) 4)" run baku-fixnum-value 3 = 60 check

\ A tail call inside a TRAP-ERROR protected form still runs under its handler.
s" (trap-error (if true (throw 7) 0) (lambda E E))" run
baku-fixnum-value 7 = 61 check
s" (trap-error (trap-error (if true (throw 1) 0) (lambda E (throw (+ E 1)))) (lambda E E))" run
baku-fixnum-value 2 = 62 check

." BAKU-TEST-DONE" cr
