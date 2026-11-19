\ Baku KLambda compatibility definitions.
\
\ Shen 43.2 registers INPUT+ as an arity-2 function but never defines it; the
\ kernel macro rewrites (input+ Type) into SHEN.INPUT-H+.  This test proves
\ BAKU-COMPAT-INIT installs a two-place, currying, KLambda-level INPUT+ and that
\ the delegate target is resolved when INPUT+ is applied, not when it is
\ installed, so the layer can load before the kernel.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

\ This layer test has no collector, so the install runs on the non-GC bump
\ heap; test/gc-boot.4th and test/repl.4th assert the shipped boot installs the
\ same definitions in the GC heap.
baku-compat-init

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a compatibility form" cr abort
	then
	baku-eval-kl ;

: check-error ( c-addr u expected code -- )
	>r >r ['] run catch
	r> = r> check ;

\ No kernel is loaded, so the delegate target is unbound.  INPUT+ itself is
\ already installed: only its application fails, which proves the install did
\ not capture a delegate.
s" (input+ 3 4)" baku-eval-undefined 1 check-error

\ Install the delegate through the production registration path.  It returns
\ its two arguments as a cons so this test can see both values and their order.
: compat-input-h ( a b -- pair ) baku-cons ;

' compat-input-h 2 s" shen.input-h+" baku-intern baku-defprim

\ INPUT+ is an interpreted two-place closure whose code is a DEFUN node, not a
\ host primitive.
s" input+" baku-intern baku-fn-lookup 2 check
dup baku-closure-kind baku-closure-interpreted = 3 check
dup baku-closure-arity 2 = 4 check
dup baku-closure-code baku-ir-kind baku-ir-defun = 5 check
drop

\ Both arguments reach the delegate in source order.
s" (input+ 3 4)" run
dup baku-hd baku-fixnum-value 3 = 6 check
baku-tl baku-fixnum-value 4 = 7 check

\ One argument yields a callable partial; the second completes it.
s" (input+ 3)" run
dup baku-closure? 8 check
dup baku-closure-kind baku-closure-partial = 9 check
dup baku-closure-arity 1 = 10 check
drop

s" ((input+ 3) 4)" run
dup baku-hd baku-fixnum-value 3 = 11 check
baku-tl baku-fixnum-value 4 = 12 check

\ More than two arguments is the evaluator's catchable arity error.
s" (input+ 3 4 5)" baku-eval-arity 13 check-error

." BAKU-TEST-DONE" cr
