\ Baku native compiler tests.
\
\ The native backend lowers the same shared IR to dictionary threaded code.  It
\ must agree with the tree-walking interpreter on every construct and must not
\ call the interpreter at run time.  Differential checks run both backends over
\ a pure expression corpus; definition, currying, global and tail-call checks
\ then drive the native path directly because they change shared tables.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

\ Interpreted reference entry, the same helper shape as test/eval.4th.
: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused an evaluator form" cr abort
	then
	baku-eval-kl ;

: nat ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a native form" cr abort
	then
	baku-native-eval-kl ;

: check-same ( c-addr u code -- )
	>r 2dup run >r nat r> baku-eq? r> check ;

: check-native-error ( c-addr u expected code -- )
	>r >r ['] nat catch r> = r> check ;

\ ---------------------------------------------------------------------------
\ Test primitives, registered through the production path.
\ ---------------------------------------------------------------------------

: pid ( x -- x ) ;
: pthrow ( x -- ) baku-raise ;
: peq ( a b -- x ) = if baku-true else baku-false then ;
: pdo ( a b -- b ) nip ;

' pid 1 s" id" baku-intern baku-defprim
' pthrow 1 s" throw" baku-intern baku-defprim
' peq 2 s" eq" baku-intern baku-defprim
' pdo 2 s" do" baku-intern baku-defprim

\ ---------------------------------------------------------------------------
\ Differential corpus: every pure IR kind and value shape.  Both backends must
\ return structurally equal values.
\ ---------------------------------------------------------------------------

s" 42" 1 check-same
s" -7" 2 check-same
s" 10000000000" 3 check-same
s" true" 4 check-same
s" false" 5 check-same
s" ()" 6 check-same
s" foo" 7 check-same

s" (+ 1 2)" 8 check-same
s" (+ 1 (* 2 3))" 9 check-same
s" (cons 1 2)" 10 check-same
s" (hd (cons 1 2))" 11 check-same
s" (tl (cons 1 2))" 12 check-same
s" (str foo)" 13 check-same
s" (let V (absvector 3) (<-address (address-> V 0 42) 0))" 14 check-same

s" (if true 1 2)" 15 check-same
s" (if false 1 2)" 16 check-same
s" (and false (throw 9))" 17 check-same
s" (or true (throw 9))" 18 check-same
s" (and true (id 5))" 19 check-same
s" (or false (id 5))" 20 check-same
s" (cond (false 1) (true 2))" 21 check-same
s" (cond ((eq 1 2) 10) (true 20))" 22 check-same

s" (let X 1 (+ X 1))" 23 check-same
s" (let X 1 (let X 2 X))" 24 check-same
s" (let X 1 (let Y 2 (+ X Y)))" 25 check-same
s" ((lambda X (+ X 1)) 41)" 26 check-same
s" (let Y 10 ((lambda X (+ X Y)) 5))" 27 check-same
s" (let F (lambda X (+ X 1)) (F 41))" 28 check-same
s" (let A 1 (let B 2 ((lambda X (+ X B)) A)))" 29 check-same
s" ((freeze 7))" 30 check-same
s" (let Y 3 ((freeze (+ Y 4))))" 31 check-same
s" (let F (lambda X (+ X 1)) (let G (cons 1 2) (F 41)))" 32 check-same

s" (trap-error (+ 1 2) (lambda E 0))" 33 check-same
s" (trap-error (throw 7) (lambda E E))" 34 check-same
s" (let Y 5 (trap-error (throw 7) (lambda E (+ E Y))))" 35 check-same
s" (trap-error (trap-error (throw 1) (lambda E (throw (+ E 1)))) (lambda E E))" 36 check-same
s" (do (id 1) (id 2))" 37 check-same

s" (let F (+ 1) (F 2))" 38 check-same
s" (let F (cons 1) (F 2))" 39 check-same
s" ((lambda X X) 41)" 40 check-same

\ ---------------------------------------------------------------------------
\ Error behaviour is shared with the interpreter.
\ ---------------------------------------------------------------------------

s" (cond (false 1))" baku-eval-cond-failed 41 check-native-error
s" (no-such-native-function 1)" baku-eval-undefined 42 check-native-error
s" (1 2)" baku-eval-not-callable 43 check-native-error
s" ((lambda X X) 1 2)" baku-eval-arity 44 check-native-error
s" (if X)" baku-front-arity 45 check-native-error

\ ---------------------------------------------------------------------------
\ Definitions, currying, globals and shadowing on the native path.
\ ---------------------------------------------------------------------------

s" (defun native-add1 (X) (+ X 1))" nat s" native-add1" baku-intern = 46 check
s" (native-add1 41)" nat baku-fixnum-value 42 = 47 check

s" (defun native-arr () 42)" nat s" native-arr" baku-intern = 48 check
s" (native-arr)" nat baku-fixnum-value 42 = 49 check

s" (defun native-two (X Y) (- X Y))" nat drop
s" (native-two 10 3)" nat baku-fixnum-value 7 = 50 check
s" (let F (native-two 10) (F 3))" nat baku-fixnum-value 7 = 51 check

s" (defun native-redefined () 1)" nat drop
s" (defun native-redefined () 2)" nat drop
s" (native-redefined)" nat baku-fixnum-value 2 = 52 check

s" (set native-g 42)" nat baku-fixnum-value 42 = 53 check
s" (value native-g)" nat baku-fixnum-value 42 = 54 check
s" (set native-g (freeze 11))" nat drop
s" ((value native-g))" nat baku-fixnum-value 11 = 55 check

\ ---------------------------------------------------------------------------
\ Tail calls: the native backend uses the shared trampoline, so return-stack
\ space stays constant and zero-parameter loops allocate nothing.
\ ---------------------------------------------------------------------------

variable tail-counter

: pset ( n -- x ) baku-fixnum-value tail-counter ! baku-nil ;
: pstep ( -- x )
	tail-counter @ 0 > if
		tail-counter @ 1- tail-counter !
		baku-true
	else
		baku-false
	then ;

' pset 1 s" pset" baku-intern baku-defprim
' pstep 0 s" pstep" baku-intern baku-defprim

s" (defun native-tail-spin () (if (pstep) (native-tail-spin) 0))" nat drop
s" (pset 100000)" nat drop
baku-nongc-used
s" (native-tail-spin)" nat baku-fixnum-value 0 = 56 check
baku-nongc-used swap - 4096 < 57 check
tail-counter @ 0 = 58 check
baku-native-self-jumps @ 100000 >= 72 check

s" (defun native-tail-even () (if (pstep) (native-tail-odd) 0))" nat drop
s" (defun native-tail-odd () (if (pstep) (native-tail-even) 0))" nat drop
s" (pset 100000)" nat drop
s" (native-tail-even)" nat baku-fixnum-value 0 = 59 check
tail-counter @ 0 = 60 check

s" (defun native-tail-count (N) (if (= N 0) 0 (native-tail-count (- N 1))))" nat drop
s" (native-tail-count 2500)" nat baku-fixnum-value 0 = 61 check

s" (defun native-tail-cond () (cond ((pstep) (native-tail-cond)) (true 0)))" nat drop
s" (pset 1000)" nat drop
s" (native-tail-cond)" nat baku-fixnum-value 0 = 62 check

s" (defun native-tail-let () (let X 0 (if (pstep) (native-tail-let) X)))" nat drop
s" (pset 1000)" nat drop
s" (native-tail-let)" nat baku-fixnum-value 0 = 63 check

s" (defun native-tail-and () (and (pstep) (native-tail-and)))" nat drop
s" (pset 1000)" nat drop
s" (native-tail-and)" nat baku-false = 64 check

\ An under-applied self-tail call must curry, not take the self-jump path.
s" (defun native-tail-under (X) (native-tail-under))" nat drop
s" (native-tail-under 1)" nat baku-closure? 73 check

\ An over-applied self-tail call must raise the shared arity error.
s" (defun native-tail-over (X) (native-tail-over X X))" nat drop
s" (native-tail-over 1)" baku-eval-arity 74 check-native-error

s" (trap-error (if true (throw 7) 0) (lambda E E))" nat baku-fixnum-value 7 = 65 check
s" (trap-error (trap-error (if true (throw 1) 0) (lambda E (throw (+ E 1)))) (lambda E E))"
nat baku-fixnum-value 2 = 66 check

\ ---------------------------------------------------------------------------
\ Compiled code must not call the tree-walking interpreter.  Rebinding the IR
\ entry to a thrower leaves the native path usable; restore it afterwards.
\ ---------------------------------------------------------------------------

: native-forbidden ( ir -- value )
	drop baku-eval-malformed throw ;

' native-forbidden is baku-eval-ir
s" (let F (lambda X (+ X 1)) (F 41))" nat baku-fixnum-value 42 = 67 check
s" (native-add1 41)" nat baku-fixnum-value 42 = 68 check
' baku-eval-ir-real is baku-eval-ir

s" (native-add1 41)" nat baku-fixnum-value 42 = 69 check

\ The boot installer consumes one read form at a time, like the interpreter
\ installer, and installs a native definition.
s" (defun native-installed () 7)" baku-read-string
baku-read-form drop baku-native-install-form
s" (native-installed)" nat baku-fixnum-value 7 = 70 check
baku-native-code-cells @ 0 > 71 check

." BAKU-TEST-DONE" cr
