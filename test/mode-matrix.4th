\ Full execution-mode equivalence matrix.
\
\ The same fixed program set must produce byte-identical observable output in
\ non-GC native, arena native and GC interpreter mode.  The set is a single
\ colon definition, MATRIX-RUN-CASES, executed three times: the case text is
\ compiled into the dictionary, so arena creation (which runs EVALUATE for its
\ MARKER) cannot clobber it, and every pass exercises exactly the same forms in
\ exactly the same order.
\
\ Non-GC is the reference pass: it evaluates through the registered EVAL-KL
\ entry, which selects the native backend, and stores each result (or caught
\ error class) as the baseline.  The arena pass evaluates the same forms inside
\ a live arena through the same registered entry, compares before releasing the
\ arena, and proves no collection ran.  The GC pass activates the collector and
\ evaluates the same forms through the registered entry, which selects the
\ interpreter: results must stay structurally and textually equal to the
\ non-GC baseline, no dictionary code may be generated, collections must occur,
\ and the post-collection live heap must stay below the semispace.
\
\ The collector needs stack roots, which the pinned Sloth does not expose.  Its
\ branch runs the non-GC and arena passes, then asserts activation is the
\ documented catchable unsupported error, so the two available modes are still
\ compared instead of skipped.  This is the same explicit capability branch as
\ test/gc-mode.4th, not a silent skip.
\
\ Results are projected to atoms because BAKU-PRIM-STR formats atoms only; the
\ compound cases use structural equality.  A defun case installs the same source
\ with each mode's executor and calls it, so closure capture and recursion run
\ through every backend.  Error cases compare the caught raw Forth code, the
\ observable error class.
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

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

variable matrix-code
variable matrix-n
variable matrix-pass
variable matrix-total
variable matrix-got
variable matrix-error-got
variable matrix-cells
variable matrix-collections
variable matrix-got-text
variable matrix-expected-text

\ Baseline values are allocated in the non-GC heap, which the collector never
\ moves.  The current value and the two formatted strings can hold GC objects,
\ so their dictionary cells are registered as roots before any collection.
64 constant matrix-max
create matrix-values matrix-max cells allot
create matrix-errors matrix-max cells allot

matrix-got 1 baku-gc-root+
matrix-got-text 1 baku-gc-root+
matrix-expected-text 1 baku-gc-root+

: matrix-fail ( -- )
	." BAKU-TEST-FAIL: mode matrix check " matrix-code @ . cr abort ;

: matrix-value-slot ( -- addr ) matrix-values matrix-n @ cells + ;
: matrix-error-slot ( -- addr ) matrix-errors matrix-n @ cells + ;
: matrix-next ( -- ) matrix-n @ 1+ matrix-n ! ;

: matrix-mode-header ( -- )
	." BAKU-MATRIX-MODE " baku-mode baku-mode-name type cr ;

\ Evaluate through the registered entry so the memory state selects the mode.
: matrix-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a mode matrix form" cr abort
	then ;

: matrix-eval ( c-addr u -- value )
	matrix-read
	s" eval-kl" baku-intern baku-fn-lookup 0= if
		baku-eval-undefined throw
	then
	swap baku-nil baku-cons baku-apply ;

\ CATCH restores the protected word's argument cells, so the failure path drops
\ the form address and length as well as the value on success.
: matrix-catch ( c-addr u -- code )
	['] matrix-eval catch
	dup 0= if nip exit then
	nip nip ;

: matrix-record-value ( -- )
	matrix-pass @ 0= if
		matrix-got @ matrix-value-slot !
	else
		matrix-got @ matrix-value-slot @ baku-eq? 0= if matrix-fail then
	then ;

: matrix-check-value-text ( -- )
	matrix-got @ baku-prim-str matrix-got-text !
	matrix-pass @ 0= if exit then
	matrix-value-slot @ baku-prim-str matrix-expected-text !
	matrix-got-text @ matrix-expected-text @ baku-string= 0= if matrix-fail then ;

: matrix-emit-value ( -- )
	." BAKU-MATRIX " matrix-code @ . ." = "
	matrix-got-text @ baku-string-addr
	matrix-got-text @ baku-string-length type cr
	matrix-next ;

: matrix-atom-case ( c-addr u code -- )
	matrix-code !
	matrix-eval matrix-got !
	matrix-record-value
	matrix-check-value-text
	matrix-emit-value ;

: matrix-eq-case ( c-addr u code -- )
	matrix-code !
	matrix-eval matrix-got !
	matrix-record-value
	." BAKU-MATRIX " matrix-code @ . ." = equal" cr
	matrix-next ;

\ The same defun source is installed by the selected executor and then called by
\ it, so the case covers code allocation and closure capture per mode.
variable matrix-def-addr
variable matrix-def-len
variable matrix-call-addr
variable matrix-call-len

: matrix-def-case ( def-addr def-u call-addr call-u code -- )
	matrix-code !
	matrix-call-len ! matrix-call-addr !
	matrix-def-len ! matrix-def-addr !
	matrix-def-addr @ matrix-def-len @ matrix-eval drop
	matrix-call-addr @ matrix-call-len @ matrix-eval matrix-got !
	matrix-record-value
	matrix-check-value-text
	matrix-emit-value ;

: matrix-error-case ( c-addr u code -- )
	matrix-code !
	matrix-catch matrix-error-got !
	matrix-pass @ 0= if
		matrix-error-got @ matrix-error-slot !
	else
		matrix-error-got @ matrix-error-slot @ <> if matrix-fail then
	then
	." BAKU-MATRIX " matrix-code @ . ." error=" matrix-error-got @ . cr
	matrix-next ;

\ The production layer has no host THROW primitive; register the same test
\ primitive test/native.4th and test/mode-differential.4th use so the trap-error
\ cases exercise a real raise instead of an undefined-function error.
: matrix-throw ( x -- ) baku-raise ;
' matrix-throw 1 s" throw" baku-intern baku-defprim

\ ---------------------------------------------------------------------------
\ The fixed program set.  Every pass runs this one word, so the case text,
\ order and numbering cannot drift between modes.
\ ---------------------------------------------------------------------------

: matrix-run-cases ( -- )
	s" (+ 1 2)" 1 matrix-atom-case
	s" (+ 9999999999 1)" 2 matrix-atom-case
	s" (- 10 4)" 3 matrix-atom-case
	s" (* 6 7)" 4 matrix-atom-case
	s" (= 10000000000 10000000000)" 5 matrix-atom-case
	s" (= (/ 7 2) 3.5)" 6 matrix-atom-case
	s" (< 1 2)" 7 matrix-atom-case
	s" (> 3 2)" 8 matrix-atom-case
	s" (= 4 5)" 9 matrix-atom-case

	s" (hd (cons 1 2))" 10 matrix-atom-case
	s" (tl (cons 1 2))" 11 matrix-atom-case
	s" (cons? (cons 1 2))" 12 matrix-atom-case
	s" (cons? ())" 13 matrix-atom-case
	s" (str 42)" 14 matrix-atom-case
	s" (cn (str 12) (str 34))" 15 matrix-atom-case
	s" (pos (cn (str 12) (str 34)) 1)" 16 matrix-atom-case
	s" (str (intern (str 7)))" 17 matrix-atom-case
	s" (= (intern (str 7)) (intern (str 7)))" 18 matrix-atom-case
	s" (absvector? (absvector 2))" 19 matrix-atom-case

	s" ((lambda X (+ X 1)) 41)" 20 matrix-atom-case
	s" (let F (lambda X (lambda Y (+ X Y))) (let G (F 40) (G 2)))" 21 matrix-atom-case
	s" (let F (lambda X (+ X 1)) (F 41))" 22 matrix-atom-case
	s" (let F (+ 1) (F 2))" 23 matrix-atom-case
	s" (hd (let F (cons 1) (F 2)))" 24 matrix-atom-case
	s" (trap-error (+ 1 2) (lambda E 0))" 25 matrix-atom-case
	s" (trap-error (throw 7) (lambda E E))" 26 matrix-atom-case
	s" (trap-error (hd 1) (lambda E 99))" 27 matrix-atom-case
	s" (trap-error (+ 1 (hd 1)) (lambda E 7))" 28 matrix-atom-case

	s" (cons 1 (cons 2 ()))" 29 matrix-eq-case
	s" (let V (absvector 3) (<-address (address-> V 0 42) 0))" 30 matrix-eq-case

	s" (defun matrix.fact (N) (if (= N 0) 1 (* N (matrix.fact (- N 1)))))"
	s" (matrix.fact 10)" 31 matrix-def-case
	s" (defun matrix.count (N) (if (= N 0) 0 (matrix.count (- N 1))))"
	s" (matrix.count 1000)" 32 matrix-def-case
	s" (defun matrix.build (N) (if (= N 0) () (cons N (matrix.build (- N 1)))))"
	s" (hd (matrix.build 200))" 33 matrix-def-case
	s" (defun matrix.alloc (N) (if (= N 0) 0 (let X (cons N N) (matrix.alloc (- N 1)))))"
	s" (matrix.alloc 1000)" 34 matrix-def-case

	\ Allocation-heavy cases above force collections in the GC pass; this
	\ closure captures a cons that may have moved by the time it is applied.
	s" (let X (cons 40 2) ((lambda Y (+ (hd X) Y)) 2))" 35 matrix-atom-case

	s" (cond (false 1))" 36 matrix-error-case
	s" (1 2)" 37 matrix-error-case
	s" (no-such-matrix-function 1)" 38 matrix-error-case
	s" ((lambda X X) 1 2)" 39 matrix-error-case
	s" (/ 1 0)" 40 matrix-error-case
	s" (if X)" 41 matrix-error-case
;

: matrix-pass-nongc ( -- )
	0 matrix-pass !
	0 matrix-n !
	matrix-mode-header
	baku-mode baku-mode-nongc = 1001 check
	baku-native-code-cells @ matrix-cells !
	baku-gc-collections @ matrix-collections !
	matrix-run-cases
	matrix-n @ matrix-total !
	baku-gc-collections @ matrix-collections @ = 1002 check
	baku-native-code-cells @ matrix-cells @ > 1003 check ;

: matrix-pass-arena ( -- )
	baku-arena-create
	1 matrix-pass !
	0 matrix-n !
	matrix-mode-header
	baku-mode baku-mode-arena = 1011 check
	baku-native-code-cells @ matrix-cells !
	baku-gc-collections @ matrix-collections !
	matrix-run-cases
	matrix-n @ matrix-total @ = 1012 check
	baku-gc-collections @ matrix-collections @ = 1013 check
	baku-native-code-cells @ matrix-cells @ > 1014 check
	baku-arena-free
	baku-mode baku-mode-nongc = 1015 check
	\ Do not leave released arena addresses in dictionary cells that the GC
	\ pass will scan as roots.
	baku-nil matrix-got !
	baku-nil matrix-got-text !
	baku-nil matrix-expected-text ! ;

: matrix-pass-gc ( -- )
	131072 baku-gc-create
	baku-gc-activate
	2 matrix-pass !
	0 matrix-n !
	matrix-mode-header
	baku-mode baku-mode-gc = 1021 check
	baku-native-code-cells @ matrix-cells !
	baku-gc-collections @ matrix-collections !
	matrix-run-cases
	matrix-n @ matrix-total @ = 1022 check
	baku-native-code-cells @ matrix-cells @ = 1023 check
	baku-gc-collections @ matrix-collections @ > 1024 check
	baku-gc-collect
	baku-gc-used? baku-gc-semispace @ < 1025 check
	baku-mode baku-mode-gc = 1026 check ;

: matrix-supported ( -- )
	matrix-pass-nongc
	matrix-pass-arena
	matrix-pass-gc ;

: matrix-unsupported ( -- )
	matrix-pass-nongc
	matrix-pass-arena
	baku-mode baku-mode-nongc = 1031 check
	131072 baku-gc-create
	baku-gc-created? @ 1032 check
	['] baku-gc-activate catch baku-gc-unsupported = 1033 check
	baku-mode baku-mode-nongc = 1034 check
	['] baku-gc-collect catch baku-gc-inactive = 1035 check ;

: matrix-run ( -- )
	baku-gc-stack-scan? if matrix-supported else matrix-unsupported then ;

matrix-run

." BAKU-MATRIX-TOTAL " matrix-total @ . cr
." BAKU-TEST-DONE" cr
