\ GC mode selection and the interpreter-in-GC path.
\
\ The execution mode follows the active memory region: an activated collector
\ selects the interpreter with all code and data in the from-space, and
\ otherwise non-GC mode compiles native code.  The kernel-visible EVAL-KL is the
\ single dispatcher, so these tests evaluate through the registered function
\ entry rather than calling a backend directly.
\
\ The collector runs on both targets: its stack-scan adapter uses only ANS words.
\ The test runs the real interpreter under repeated collections on Sloth and
\ gforth.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

variable gcm-old
variable gcm-cells
variable gcm-value
variable gcm-nongc-tail

gcm-value 1 baku-gc-root+

: gcm-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a GC-mode form" cr abort
	then ;

\ Evaluate through the registered EVAL-KL entry so the mode dispatch itself is
\ under test.  A direct BAKU-EVAL-KL call would bypass the selector.
: gcm-eval ( c-addr u -- value )
	gcm-read
	s" eval-kl" baku-intern baku-fn-lookup 0= if
		baku-eval-undefined throw
	then
	swap baku-nil baku-cons baku-apply ;

\ Call the native backend directly and return its caught code.  Used to prove
\ that GC mode refuses dictionary code generation with a catchable error.
: gcm-native ( c-addr u -- code )
	gcm-read ['] baku-native-eval-kl catch
	dup if nip exit then
	2drop 0 ;

: gcm-add-form ( -- c-addr u ) s" (+ 1 2)" ;
: gcm-fact-def ( -- c-addr u )
	s" (defun gcm-fact (N) (if (= N 0) 1 (* N (gcm-fact (- N 1)))))" ;
: gcm-fact-call ( -- c-addr u ) s" (gcm-fact 10)" ;
: gcm-build-def ( -- c-addr u )
	s" (defun gcm-build (N Acc) (if (= N 0) Acc (gcm-build (- N 1) (cons N Acc))))" ;
: gcm-build-call ( -- c-addr u ) s" (gcm-build 3000 ())" ;
: gcm-float-form ( -- c-addr u ) s" 3.5" ;
: gcm-tail-def ( -- c-addr u )
	s" (defun gcm-tail (N) (if (= N 0) 0 (gcm-tail (- N 1))))" ;
: gcm-tail-shallow ( -- c-addr u ) s" (gcm-tail 2500)" ;
: gcm-tail-deep ( -- c-addr u ) s" (gcm-tail 100000)" ;

: gcm-report-mode ( -- )
	." BAKU-MODE " baku-mode baku-mode-name type cr ;

: gcm-supported-test ( -- )
	baku-mode baku-mode-nongc = 1 check
	gcm-report-mode

	\ Non-GC mode compiles native code and never invokes the collector.
	baku-native-code-cells @ gcm-cells !
	baku-gc-collections @ gcm-old !
	gcm-add-form gcm-eval baku-fixnum-value 3 = 2 check
	baku-native-code-cells @ gcm-cells @ > 3 check
	baku-gc-collections @ gcm-old @ = 4 check
	baku-mode baku-mode-nongc = 5 check

	\ Reference run for the depth-independence checks below: the same
	\ one-parameter countdown at 2,500 depth goes through the non-GC native
	\ backend before the collector exists.  The deep GC run must reproduce
	\ this result, and the existing non-GC parameterised tail checks
	\ (test/eval.4th and test/native.4th) pin the same 2,500-deep case
	\ independently.
	gcm-tail-def gcm-eval drop
	gcm-tail-shallow gcm-eval baku-fixnum-value gcm-nongc-tail !

	\ GC mode selects the interpreter and generates no dictionary code.
	131072 baku-gc-semispace-request !
	baku-gc-create
	baku-gc-created? @ 11 check
	baku-gc-activate
	baku-gc-active? 12 check
	baku-mode baku-mode-gc = 13 check
	gcm-report-mode
	baku-native-code-cells @ gcm-cells !
	gcm-add-form gcm-eval baku-fixnum-value 3 = 14 check
	baku-native-code-cells @ gcm-cells @ = 15 check
	baku-mode baku-mode-gc = 16 check

	\ The native backend is refused with the executor's catchable mode code.
	gcm-add-form gcm-native baku-mode-error = 17 check

	\ A recursive defun's closure code is a GC object; it must stay valid after
	\ the collector moves it.
	gcm-fact-def gcm-eval drop
	gcm-fact-call gcm-eval baku-fixnum-value 3628800 = 18 check
	baku-gc-collect
	gcm-fact-call gcm-eval baku-fixnum-value 3628800 = 19 check

	\ An allocation-heavy tail loop must trigger collections, and its list must
	\ survive several moves with its contents intact.
	gcm-build-def gcm-eval drop
	baku-gc-collections @ gcm-old !
	gcm-build-call gcm-eval gcm-value !
	gcm-value @ baku-list-length 3000 = 20 check
	baku-gc-collections @ gcm-old @ > 21 check
	gcm-value @ gcm-old !
	baku-gc-collect
	gcm-old @ gcm-value @ <> 22 check
	gcm-value @ baku-list-length 3000 = 23 check
	gcm-value @ baku-hd baku-fixnum-value 1 = 24 check

	\ A float literal is read into reader scratch.  The front end must copy it
	\ into the GC heap; otherwise the IR would hold a scratch pointer and the
	\ collector would leave the float behind.
	gcm-float-form gcm-eval gcm-value !
	gcm-value @ baku-float? 25 check
	gcm-value @ baku-float@ 3.5e 0.000001e f~ 26 check
	baku-gc-collect
	gcm-value @ baku-float? 27 check
	gcm-value @ baku-float@ 3.5e 0.000001e f~ 28 check

	\ Depth independence under the collector.  A parameterised interpreted
	\ tail call allocates one environment and one argument list per iteration
	\ (about 168 bytes), so a 100,000-deep chain allocates far more than the
	\ 128 KiB semispace.  It can only finish if every iteration's frames are
	\ reclaimed, and its result must equal the non-GC 2,500-deep reference.
	\ Redefining the function now installs an interpreted closure whose IR
	\ lives in the GC, shadowing the non-GC native definition.
	gcm-tail-def gcm-eval drop
	baku-gc-collections @ gcm-old !
	gcm-tail-shallow gcm-eval baku-fixnum-value gcm-nongc-tail @ = 29 check
	gcm-tail-deep gcm-eval baku-fixnum-value gcm-nongc-tail @ = 30 check
	baku-gc-collections @ gcm-old @ > 31 check
	baku-gc-collect
	baku-gc-used? baku-gc-semispace @ < 32 check
	baku-mode baku-mode-gc = 33 check ;

: gcm-run ( -- )
	gcm-supported-test ;

gcm-run

." BAKU-TEST-DONE" cr
