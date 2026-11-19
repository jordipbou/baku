\ GC-only execution: the collector is the heap and the interpreter is the
\ executor.
\
\ There is one execution path.  The Cheney collector owns the selected heap and
\ the tree-walking interpreter evaluates heap-resident IR; there is no separate
\ backend and no lifetime selector.  This test therefore creates and activates
\ the collector, evaluates through the registered EVAL-KL primitive (the
\ kernel-visible entry point), and repeats the interesting cases across a
\ forced collection.
\
\ The collector runs on both targets: its stack-scan adapter uses only ANS words.
\ A deliberately small semispace forces collections and keeps the evidence in
\ this file, rather than relying on the shipped default.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

variable gcm-value
variable gcm-old
variable gcm-clo

gcm-value 1 baku-gc-root+

: gcm-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a GC form" cr abort
	then ;

\ Evaluate through the registered EVAL-KL entry, so the single consumer is under
\ test rather than a direct BAKU-EVAL-KL call.
: gcm-eval ( c-addr u -- value )
	gcm-read
	s" eval-kl" baku-intern baku-fn-lookup 0= if
		baku-eval-undefined throw
	then
	swap baku-nil baku-cons baku-apply ;

\ Run a form and return the caught evaluator code, or 0 on success.
: gcm-error ( c-addr u -- code )
	['] gcm-eval catch
	?dup if >r 2drop r> else 2drop 0 then ;

: gcm-eval-kl-primitive? ( -- flag )
	s" eval-kl" baku-intern baku-fn-lookup 0= if false exit then
	dup baku-closure-kind baku-closure-primitive = swap
	baku-closure-arity 1 = and ;

\ A definition installed under the collector must be an interpreted closure
\ whose code slot is a GC object; there is no separate closure kind any more.
: gcm-interpreted-definition? ( c-addr u -- flag )
	baku-intern baku-fn-lookup 0= if drop false exit then
	gcm-clo !
	gcm-clo @ baku-closure-kind baku-closure-interpreted <> if false exit then
	gcm-clo @ baku-closure-code
	dup baku-object? if baku-region-of baku-region-gc = else drop false then ;

: gcm-add-form ( -- c-addr u ) s" (+ 1 2)" ;
: gcm-fact-def ( -- c-addr u )
	s" (defun gcm.fact (N) (if (= N 0) 1 (* N (gcm.fact (- N 1)))))" ;
: gcm-fact-call ( -- c-addr u ) s" (gcm.fact 10)" ;
: gcm-add1-def ( -- c-addr u ) s" (defun gcm.add1 (X) (+ X 1))" ;
: gcm-trap-form ( -- c-addr u )
	s" (trap-error (hd 1) (lambda E 99))" ;
: gcm-not-callable ( -- c-addr u ) s" (1 2)" ;
: gcm-over-apply ( -- c-addr u ) s" ((lambda X X) 1 2)" ;
: gcm-float-form ( -- c-addr u ) s" 3.5" ;
: gcm-build-def ( -- c-addr u )
	s" (defun gcm.build (N Acc) (if (= N 0) Acc (gcm.build (- N 1) (cons N Acc))))" ;
: gcm-build-call ( -- c-addr u ) s" (gcm.build 3000 ())" ;
: gcm-tail-def ( -- c-addr u )
	s" (defun gcm.tail (N) (if (= N 0) 0 (gcm.tail (- N 1))))" ;
: gcm-tail-call ( -- c-addr u ) s" (gcm.tail 2500)" ;
: gcm-tail-deep ( -- c-addr u ) s" (gcm.tail 100000)" ;
: gcm-even-def ( -- c-addr u )
	s" (defun gcm.even () (if (gcm-pstep) (gcm.odd) 0))" ;
: gcm-odd-def ( -- c-addr u )
	s" (defun gcm.odd () (if (gcm-pstep) (gcm.even) 0))" ;
: gcm-even-call ( -- c-addr u ) s" (gcm.even)" ;

\ ---------------------------------------------------------------------------
\ The collector and the single consumer.
\ ---------------------------------------------------------------------------

131072 baku-gc-semispace-request !
baku-gc-create
baku-gc-created? @ 1 check
baku-gc-activate
baku-gc-active? 2 check

gcm-eval-kl-primitive? 3 check
gcm-add-form gcm-eval baku-fixnum-value 3 = 4 check

\ ---------------------------------------------------------------------------
\ A definition is an interpreted closure with heap-resident IR, and its code
\ survives a move.
\ ---------------------------------------------------------------------------

gcm-fact-def gcm-eval drop
s" gcm.fact" gcm-interpreted-definition? 5 check
gcm-fact-call gcm-eval baku-fixnum-value 3628800 = 6 check
baku-gc-collect
gcm-fact-call gcm-eval baku-fixnum-value 3628800 = 7 check

\ ---------------------------------------------------------------------------
\ Currying before and after a collection.  The stored partial is a root, so the
\ collector must update its target and saved arguments.
\ ---------------------------------------------------------------------------

gcm-add1-def gcm-eval drop
s" (gcm.add1 41)" gcm-eval baku-fixnum-value 42 = 8 check
s" (gcm.add1)" gcm-eval dup baku-closure? 9 check
gcm-value !
gcm-value @ baku-closure-kind baku-closure-partial = 10 check
baku-gc-collect
gcm-value @ 41 baku-fixnum baku-nil baku-cons baku-apply
	baku-fixnum-value 42 = 11 check

\ ---------------------------------------------------------------------------
\ TRAP-ERROR before and after a collection.
\ ---------------------------------------------------------------------------

gcm-trap-form gcm-eval baku-fixnum-value 99 = 12 check
baku-gc-collect
gcm-trap-form gcm-eval baku-fixnum-value 99 = 13 check

\ ---------------------------------------------------------------------------
\ A non-callable value and an over-applied closure raise the catchable
\ evaluator codes before and after a collection.
\ ---------------------------------------------------------------------------

gcm-not-callable gcm-error baku-eval-not-callable = 14 check
gcm-over-apply gcm-error baku-eval-arity = 15 check
baku-gc-collect
gcm-not-callable gcm-error baku-eval-not-callable = 16 check
gcm-over-apply gcm-error baku-eval-arity = 17 check

\ ---------------------------------------------------------------------------
\ String and float literals are read into reader scratch, then copied into the
\ selected heap by the front end.  Both must survive a move.
\ ---------------------------------------------------------------------------

create gcm-string-form
	34 c, 97 c, 98 c, 99 c, 34 c,

gcm-string-form 5 gcm-eval
dup baku-string? 18 check
gcm-value !
gcm-value @ s" abc" baku-string baku-string= 19 check
baku-gc-collect
gcm-value @ baku-string? 20 check
gcm-value @ s" abc" baku-string baku-string= 21 check

gcm-float-form gcm-eval
dup baku-float? 22 check
gcm-value !
gcm-value @ baku-float@ 3.5e 0.000001e f~ 23 check
baku-gc-collect
gcm-value @ baku-float? 24 check
gcm-value @ baku-float@ 3.5e 0.000001e f~ 25 check

\ ---------------------------------------------------------------------------
\ An allocation-heavy tail loop triggers collections; the resulting list must
\ survive several moves with its contents intact.
\ ---------------------------------------------------------------------------

gcm-build-def gcm-eval drop
baku-gc-collections @ gcm-old !
gcm-build-call gcm-eval gcm-value !
gcm-value @ baku-list-length 3000 = 26 check
baku-gc-collections @ gcm-old @ > 27 check
gcm-value @ gcm-old !
baku-gc-collect
gcm-old @ gcm-value @ <> 28 check
gcm-value @ baku-list-length 3000 = 29 check
gcm-value @ baku-hd baku-fixnum-value 1 = 30 check

\ ---------------------------------------------------------------------------
\ Self tail recursion.  The one-parameter countdown allocates a frame per
\ iteration, so 100,000 iterations reuse the trampoline and let the collector
\ reclaim each frame; the result before and after a forced collection agrees.
\ ---------------------------------------------------------------------------

gcm-tail-def gcm-eval drop
gcm-tail-call gcm-eval baku-fixnum-value 0 = 31 check
baku-gc-collect
gcm-tail-call gcm-eval baku-fixnum-value 0 = 32 check

baku-gc-collections @ gcm-old !
gcm-tail-deep gcm-eval baku-fixnum-value 0 = 33 check
baku-gc-collections @ gcm-old @ > 34 check
baku-gc-collect
baku-gc-used? baku-gc-semispace @ < 35 check

\ ---------------------------------------------------------------------------
\ Mutual tail recursion with the collector active.  The zero-allocation
\ even/odd pair runs far beyond the return-stack depth on both targets; the
\ collector is active for the whole chain and a forced collection leaves the
\ definitions usable.
\ ---------------------------------------------------------------------------

variable gcm-counter

: gcm-pset ( n -- n' ) baku-fixnum-value dup gcm-counter ! baku-fixnum ;

: gcm-pstep ( -- flag )
	gcm-counter @ 0> if
		gcm-counter @ 1- gcm-counter !
		baku-true
	else
		baku-false
	then ;

' gcm-pset 1 s" gcm-pset" baku-intern baku-defprim
' gcm-pstep 0 s" gcm-pstep" baku-intern baku-defprim

gcm-even-def gcm-eval drop
gcm-odd-def gcm-eval drop
s" (gcm-pset 100000)" gcm-eval drop
gcm-even-call gcm-eval baku-fixnum-value 0 = 36 check
gcm-counter @ 0 = 37 check
baku-gc-collect
s" (gcm-pset 100000)" gcm-eval drop
gcm-even-call gcm-eval baku-fixnum-value 0 = 38 check
gcm-counter @ 0 = 39 check

." BAKU-TEST-DONE" cr
