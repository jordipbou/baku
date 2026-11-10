\ KLambda front end and tail-position tests.
\
\ The front end is the only place tail-position analysis lives.  These tests
\ use the real reader, not hand-built conses, so the form shapes are the same
\ ones the kernel corpus contains.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: read-one ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if ." BAKU-TEST-FAIL: reader refused a front-end form" cr abort then ;

: root ( c-addr u -- ir )
	read-one true baku-frontend ;

: check-kind ( node kind code -- )
	>r >r baku-ir-kind r> = r> check ;

: check-tail ( node flag code -- )
	>r >r baku-ir-tail? r> = r> check ;

: compile-form ( c-addr u -- ir )
	read-one true baku-frontend ;

: check-error ( addr u expected code -- )
	>r >r ['] compile-form catch ( addr u actual )
	r> = ( addr u flag )
	r> ( addr u flag code )
	check 2drop ;

\ ---------------------------------------------------------------------------
\ Atoms and calls
\ ---------------------------------------------------------------------------

s" 42" root
dup baku-ir-atom 1 check-kind
dup false 2 check-tail
dup baku-ir-value baku-fixnum-value 42 = 3 check
drop

s" foo" root
dup baku-ir-symbol 4 check-kind
dup baku-ir-value s" foo" baku-intern = 5 check
dup false 6 check-tail
drop

s" (f 1 2)" root
dup baku-ir-call 7 check-kind
dup true 8 check-tail
dup baku-ir-call-arity 2 = 9 check
dup baku-ir-call-operator baku-ir-symbol 10 check-kind
dup baku-ir-call-operator baku-ir-value s" f" baku-intern = 11 check
dup baku-ir-call-operator false 12 check-tail
dup 0 baku-ir-call-arg baku-ir-atom 13 check-kind
dup 0 baku-ir-call-arg false 14 check-tail
dup 1 baku-ir-call-arg baku-ir-value baku-fixnum-value 2 = 15 check
drop

\ A special-form spelling outside head position is data, not a special form.
s" (f if)" root
dup 0 baku-ir-call-arg baku-ir-symbol 16 check-kind
dup 0 baku-ir-call-arg baku-ir-value s" if" baku-intern = 17 check
drop

\ ---------------------------------------------------------------------------
\ IF: test is not tail; branches inherit the node's tail position
\ ---------------------------------------------------------------------------

s" (if X (f) (g))" root
dup baku-ir-if 18 check-kind
dup true 19 check-tail
dup baku-ir-if-test baku-ir-symbol 20 check-kind
dup baku-ir-if-test false 21 check-tail
dup baku-ir-if-then baku-ir-call 22 check-kind
dup baku-ir-if-then true 23 check-tail
dup baku-ir-if-else true 24 check-tail
drop

\ In non-tail context the branches are not tail positions either.
s" (f (if X (g) 2))" root
dup 0 baku-ir-call-arg baku-ir-if 25 check-kind
dup 0 baku-ir-call-arg false 26 check-tail
dup 0 baku-ir-call-arg baku-ir-if-test false 27 check-tail
dup 0 baku-ir-call-arg baku-ir-if-then baku-ir-call 28 check-kind
dup 0 baku-ir-call-arg baku-ir-if-then false 29 check-tail
drop

\ ---------------------------------------------------------------------------
\ AND / OR: only the last operand is a tail position
\ ---------------------------------------------------------------------------

s" (and A (f))" root
dup baku-ir-and 30 check-kind
dup baku-ir-and-left false 31 check-tail
dup baku-ir-and-right baku-ir-call 32 check-kind
dup baku-ir-and-right true 33 check-tail
drop

s" (or (f) (g))" root
dup baku-ir-or 34 check-kind
dup baku-ir-or-left baku-ir-call 35 check-kind
dup baku-ir-or-left false 36 check-tail
dup baku-ir-or-right baku-ir-call 37 check-kind
dup baku-ir-or-right true 38 check-tail
drop

\ ---------------------------------------------------------------------------
\ COND: tests are not tail; results inherit the node's tail position
\ ---------------------------------------------------------------------------

s" (cond (A (f)) (true (g)))" root
dup baku-ir-cond 38 check-kind
dup true 40 check-tail
dup baku-ir-cond-clauses baku-hd
	dup 0 baku-vector@ baku-ir-symbol 41 check-kind
	dup 0 baku-vector@ false 42 check-tail
	dup 1 baku-vector@ baku-ir-call 43 check-kind
	dup 1 baku-vector@ true 44 check-tail
	drop
dup baku-ir-cond-clauses baku-tl baku-hd 1 baku-vector@ baku-ir-tail? 45 check
drop

s" (f (cond (A (g))))" root
dup 0 baku-ir-call-arg baku-ir-cond 46 check-kind
dup 0 baku-ir-call-arg false 47 check-tail
dup 0 baku-ir-call-arg baku-ir-cond-clauses baku-hd 1 baku-vector@ baku-ir-tail? 0= 48 check
drop

\ ---------------------------------------------------------------------------
\ LET: bound expression is not tail; body inherits the node's tail position
\ ---------------------------------------------------------------------------

s" (let X 1 (f X))" root
dup baku-ir-let 49 check-kind
dup baku-ir-let-var s" X" baku-intern = 50 check
dup baku-ir-let-expr baku-ir-atom 51 check-kind
dup baku-ir-let-expr false 52 check-tail
dup baku-ir-let-body baku-ir-call 53 check-kind
dup baku-ir-let-body true 54 check-tail
drop

s" (let X (g) X)" root
dup baku-ir-let-expr baku-ir-call 55 check-kind
dup baku-ir-let-expr false 56 check-tail
drop

\ ---------------------------------------------------------------------------
\ LAMBDA / FREEZE: a function body is always a tail position
\ ---------------------------------------------------------------------------

s" (lambda X (f X))" root
dup baku-ir-lambda 57 check-kind
dup baku-ir-lambda-param s" X" baku-intern = 58 check
dup baku-ir-lambda-body baku-ir-call 59 check-kind
dup baku-ir-lambda-body true 60 check-tail
drop

s" (f (lambda X (g X)))" root
dup 0 baku-ir-call-arg baku-ir-lambda 61 check-kind
dup 0 baku-ir-call-arg false 62 check-tail
dup 0 baku-ir-call-arg baku-ir-lambda-body baku-ir-tail? 63 check
drop

s" (freeze (f))" root
dup baku-ir-freeze 64 check-kind
dup baku-ir-freeze-body baku-ir-call 65 check-kind
dup baku-ir-freeze-body true 66 check-tail
drop

s" (f (freeze (g)))" root
dup 0 baku-ir-call-arg baku-ir-freeze 67 check-kind
dup 0 baku-ir-call-arg false 68 check-tail
dup 0 baku-ir-call-arg baku-ir-freeze-body baku-ir-tail? 69 check
drop

\ ---------------------------------------------------------------------------
\ DEFUN: parameters become a vector; the body is a tail position
\ ---------------------------------------------------------------------------

s" (defun f (X Y) (g X))" root
dup baku-ir-defun 70 check-kind
dup false 71 check-tail
dup baku-ir-defun-name s" f" baku-intern = 72 check
dup baku-ir-defun-params baku-vector-length 2 = 73 check
dup baku-ir-defun-params 0 baku-vector@ s" X" baku-intern = 74 check
dup baku-ir-defun-params 1 baku-vector@ s" Y" baku-intern = 75 check
dup baku-ir-defun-body baku-ir-call 76 check-kind
dup baku-ir-defun-body true 77 check-tail
drop

\ ---------------------------------------------------------------------------
\ TRAP-ERROR: protected form is tail; the handler expression is not a call
\ ---------------------------------------------------------------------------

s" (trap-error (f) (lambda Z (g Z)))" root
dup baku-ir-trap-error 78 check-kind
dup baku-ir-trap-expr baku-ir-call 79 check-kind
dup baku-ir-trap-expr true 80 check-tail
dup baku-ir-trap-handler baku-ir-lambda 81 check-kind
dup baku-ir-trap-handler false 82 check-tail
dup baku-ir-trap-handler baku-ir-lambda-body baku-ir-tail? 83 check
drop

\ ---------------------------------------------------------------------------
\ DO is an ordinary kernel function, not a sequencing special form
\ ---------------------------------------------------------------------------

s" (do (f) (g))" root
dup baku-ir-call 84 check-kind
dup baku-ir-call-operator baku-ir-value s" do" baku-intern = 85 check
dup 0 baku-ir-call-arg baku-ir-call 86 check-kind
dup 0 baku-ir-call-arg false 87 check-tail
dup 1 baku-ir-call-arg baku-ir-call 88 check-kind
dup 1 baku-ir-call-arg false 89 check-tail
drop

\ ---------------------------------------------------------------------------
\ Malformed forms are catchable errors, not memory corruption
\ ---------------------------------------------------------------------------

s" (if X)" baku-front-arity 89 check-error
s" (if X 1)" baku-front-arity 90 check-error
s" (and A)" baku-front-arity 91 check-error
s" (or A B C)" baku-front-arity 92 check-error
s" (lambda 1 X)" baku-front-malformed 93 check-error
s" (let 1 2 3)" baku-front-malformed 94 check-error
s" (defun f X 1)" baku-front-malformed 95 check-error
s" (defun 1 (X) X)" baku-front-malformed 96 check-error
s" (cond (A))" baku-front-arity 97 check-error
s" (cond)" baku-front-arity 98 check-error
s" (freeze)" baku-front-arity 99 check-error
s" (trap-error X)" baku-front-arity 100 check-error

\ The front end is still usable after a failed form.
s" (f 1)" root baku-ir-call 102 check-kind

\ A zero-arity defun is valid: the kernel contains several.
s" (defun tc? () (value shen.*tc*))" root
dup baku-ir-defun 103 check-kind
dup baku-ir-defun-params baku-vector-length 0= 104 check
dup baku-ir-defun-body baku-ir-call 105 check-kind
drop

." BAKU-TEST-DONE" cr
