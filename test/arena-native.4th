\ Baku arena native code generation tests.
\
\ Arena mode compiles the same dictionary threaded code as non-GC mode, but the
\ code and every object it creates belong to the arena's lifetime.  These tests
\ prove that: code reservation keeps the arena bump pointer in step with HERE,
\ a later arena allocation cannot rewind over a code block, the same fixed
\ program set gives the same value and printed text in both modes, errors keep
\ the same class, the collector never runs, and DEFUN/SET entries installed in
\ an arena are removed when its MARKER runs.  Nested arenas keep the same table
\ discipline.
\
\ The form is evaluated through the registered EVAL-KL entry so the mode
\ selector performs the dispatch; calling the native backend directly would not
\ prove arena mode is selected.  A result must be compared before the arena is
\ freed, because releasing the arena invalidates it.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

variable an-code
variable an-outside
variable an-inside
variable an-format-a
variable an-format-b
variable an-cells
variable an-collections
variable an-base

: an-fail ( -- )
	." BAKU-TEST-FAIL: arena native check " an-code @ . cr abort ;

\ The form is evaluated once before the arena exists and once inside it.  An
\ interpreted S" buffer is transient, and BAKU-ARENA-CREATE runs EVALUATE while
\ defining its MARKER, so the text must be copied into the dictionary first.
4096 constant an-form-max
create an-form-buf an-form-max allot
variable an-form-len

: an-stash ( c-addr u -- )
	dup an-form-max u> if ." BAKU-TEST-FAIL: arena form too long" cr abort then
	dup an-form-len !
	an-form-buf swap move ;

: an-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused an arena native form" cr abort
	then ;

\ Evaluate through the registered entry so arena mode is chosen by the memory
\ state, not by the test.
: an-eval ( c-addr u -- value )
	an-read
	s" eval-kl" baku-intern baku-fn-lookup 0= if
		baku-eval-undefined throw
	then
	swap baku-nil baku-cons baku-apply ;

\ CATCH restores the protected word's arguments, so the failure path drops the
\ form address and length as well as the value on success.
: an-catch ( c-addr u -- code )
	['] an-eval catch
	dup 0= if nip exit then
	nip nip ;

\ Compare a value-returning form in non-GC and arena mode, including the
\ canonical atom text.  Results must be atoms because BAKU-PRIM-STR formats
\ atoms only.
: an-same ( c-addr u code -- )
	an-code !
	an-stash
	an-form-buf an-form-len @ an-eval an-outside !
	baku-arena-create
	an-form-buf an-form-len @ an-eval an-inside !
	an-outside @ an-inside @ baku-eq? 0= if an-fail then
	an-outside @ baku-prim-str an-format-a !
	an-inside @ baku-prim-str an-format-b !
	an-format-a @ an-format-b @ baku-string= 0= if an-fail then
	." BAKU-ARENA " an-code @ . ." = "
	an-format-a @ baku-string-addr
	an-format-a @ baku-string-length type cr
	baku-arena-free ;

\ Container results are compared structurally; the formatter rejects them.
: an-eq ( c-addr u code -- )
	an-code !
	an-stash
	an-form-buf an-form-len @ an-eval an-outside !
	baku-arena-create
	an-form-buf an-form-len @ an-eval an-inside !
	an-outside @ an-inside @ baku-eq? 0= if an-fail then
	." BAKU-ARENA " an-code @ . ." = equal" cr
	baku-arena-free ;

\ Error cases compare the caught raw Forth code, the observable error class.
: an-error-same ( c-addr u code -- )
	an-code !
	an-stash
	an-form-buf an-form-len @ an-catch an-outside !
	an-outside @ 0= if an-fail then
	baku-arena-create
	an-form-buf an-form-len @ an-catch an-inside !
	baku-arena-free
	an-outside @ an-inside @ = 0= if an-fail then
	." BAKU-ARENA " an-code @ . ." error=" an-outside @ . cr ;

baku-mode baku-mode-nongc = 1 check

\ The production layer has no host THROW primitive; register the same test
\ primitive test/native.4th uses so the trap-error case exercises a real raise.
: an-throw ( x -- ) baku-raise ;
' an-throw 1 s" throw" baku-intern baku-defprim

\ ---------------------------------------------------------------------------
\ Fixed program set: arithmetic, lists, strings, vectors, closures, currying,
\ trap-error.  All values are atoms so the printed text is comparable.
\ ---------------------------------------------------------------------------

s" 42" 2 an-same
s" (+ 9999999999 1)" 3 an-same
s" (= (/ 7 2) 3.5)" 4 an-same
s" (< 1 2)" 5 an-same
s" (cons? (cons 1 2))" 6 an-same
s" (hd (cons 1 2))" 7 an-same
s" (tl (cons 1 (cons 2 ())))" 8 an-eq
s" (= (cons 1 (cons 2 ())) (cons 1 (cons 2 ())))" 9 an-same
s" (cn (str 12) (str 34))" 10 an-same
s" (pos (cn (str 12) (str 34)) 1)" 11 an-same
s" (str (intern (str 7)))" 12 an-same
s" (absvector? (absvector 2))" 13 an-same
s" ((lambda X (+ X 1)) 41)" 14 an-same
s" (let F (lambda X (lambda Y (+ X Y))) (let G (F 40) (G 2)))" 15 an-same
s" (let F (+ 1) (F 2))" 16 an-same
s" (trap-error (+ 1 2) (lambda E 0))" 17 an-same
s" (trap-error (throw 7) (lambda E E))" 18 an-same
s" (trap-error (hd 1) (lambda E 99))" 19 an-same

\ Containers and vectors are equal when their contents are equal.
s" (cons 1 (cons 2 ()))" 20 an-eq
s" (let V (absvector 3) (<-address (address-> V 0 42) 0))" 21 an-eq

\ ---------------------------------------------------------------------------
\ Error classes.
\ ---------------------------------------------------------------------------

s" (cond (false 1))" 22 an-error-same
s" (1 2)" 23 an-error-same
s" (no-such-arena-function 1)" 24 an-error-same
s" ((lambda X X) 1 2)" 25 an-error-same
s" (/ 1 0)" 26 an-error-same

\ ---------------------------------------------------------------------------
\ Code allocated in the arena survives a later arena allocation.
\ ---------------------------------------------------------------------------

align here an-base !

baku-arena-create
s" (defun an.code (X) (+ X 1))" an-eval drop
s" (an.code 41)" an-eval baku-fixnum-value 42 = 27 check
s" (cons 1 2)" an-eval drop
s" (cons 3 4)" an-eval drop
s" (an.code 41)" an-eval baku-fixnum-value 42 = 28 check
baku-arena-free

\ A pure call allocates its result in the arena and compiles code there, while
\ the collector stays inactive.
baku-arena-create
baku-native-code-cells @ an-cells !
baku-gc-collections @ an-collections !
s" (cons 1 2)" an-eval an-inside !
an-inside @ baku-region-of baku-region-arena = 29 check
baku-native-code-cells @ an-cells @ > 30 check
baku-gc-collections @ an-collections @ = 31 check
baku-arena-free

here an-base @ = 32 check

\ ---------------------------------------------------------------------------
\ Definitions and globals: entries written in the arena are removed with it.
\ ---------------------------------------------------------------------------

s" (defun an.f () 1)" an-eval drop
s" (set an.g 10)" an-eval drop
s" (an.f)" an-eval baku-fixnum-value 1 = 33 check
s" (value an.g)" an-eval baku-fixnum-value 10 = 34 check

baku-arena-create
s" (defun an.f () 2)" an-eval drop
s" (defun an.only () 3)" an-eval drop
s" (set an.g 20)" an-eval drop
s" (an.f)" an-eval baku-fixnum-value 2 = 35 check
s" (an.only)" an-eval baku-fixnum-value 3 = 36 check
s" (value an.g)" an-eval baku-fixnum-value 20 = 37 check
baku-arena-free

s" (an.f)" an-eval baku-fixnum-value 1 = 38 check
s" (value an.g)" an-eval baku-fixnum-value 10 = 39 check
s" (an.only)" an-catch baku-eval-undefined = 40 check

\ A recursive definition compiled in the arena keeps working until release.
baku-arena-create
s" (defun an.count (N) (if (= N 0) 0 (an.count (- N 1))))" an-eval drop
s" (an.count 5000)" an-eval baku-fixnum-value 0 = 41 check
s" (defun an.build (N) (if (= N 0) () (cons N (an.build (- N 1)))))" an-eval drop
s" (an.build 200)" an-eval baku-list-length 200 = 42 check
baku-arena-free
s" (an.count 1)" an-catch baku-eval-undefined = 43 check
s" (an.build 1)" an-catch baku-eval-undefined = 44 check

\ ---------------------------------------------------------------------------
\ Nested arenas restore the outer snapshot, then the pre-arena tables.
\ ---------------------------------------------------------------------------

baku-arena-create
s" (defun an.n () 1)" an-eval drop
baku-arena-create
s" (defun an.n () 2)" an-eval drop
s" (an.n)" an-eval baku-fixnum-value 2 = 45 check
baku-arena-free
s" (an.n)" an-eval baku-fixnum-value 1 = 46 check
baku-arena-free
s" (an.n)" an-catch baku-eval-undefined = 47 check
baku-mode baku-mode-nongc = 48 check

." BAKU-ARENA-TOTAL 48" cr
." BAKU-TEST-DONE" cr
