\ Kernel-level semantics through the booted kernel.
\
\ The native boot installs and initialises the whole 43.2 kernel, so this test
\ has the same acceptance cost as test/boot-native.4th: a 512 MiB non-GC heap
\ plus the IR and reader scratch, and gforth-only registration (Sloth's Debug
\ native execution is far too slow for the gate).
\
\ The checks cover the kernel-defined behaviour that Baku must not reimplement:
\ the input+ compatibility path, zero-place fn/thaw, the kernel vector
\ accessors and classifiers, and the kernel writer's reader round-trip.  They
\ are evaluated through BAKU-EVAL-KL, the interpreter reference, which still
\ dispatches into native kernel closures after a native boot.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

: ev ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if drop baku-read-eof throw then
	baku-eval-kl ;

: test-str= ( obj c-addr u -- flag )
	baku-string baku-prim-eq baku-true = ;

\ ---------------------------------------------------------------------------
\ Boot and initialise.  This is the same path as the native boot test.
\ ---------------------------------------------------------------------------

' baku-native-install-form is baku-install-form

baku-boot-load-kernel

baku-boot-files @ 23 1 check-num
baku-boot-forms @ 1124 2 check-num
baku-boot-defuns @ 1118 3 check-num

baku-boot-globals
baku-boot-initialise

\ ---------------------------------------------------------------------------
\ input+: the kernel installs the arity and the lambda form, and the
\ compatibility delegate in 4th/compat.4th resolves SHEN.INPUT-H+ at
\ application time.  MACROEXPAND follows the kernel's process-input+ path.
\ ---------------------------------------------------------------------------

s" (arity input+)" ev baku-fixnum-value 2 4 check-num

s" (fn input+)" ev baku-closure? 5 check

s" (macroexpand (cons input+ (cons number ())))" ev
	dup baku-cons? 6 check
	dup baku-hd s" shen.input-h+" baku-intern = 7 check
	baku-tl baku-hd s" number" baku-intern = 8 check

\ The real delegation reads a monotype-checked form from *STINPUT*.  The file
\ holds two forms so the direct call and the curried (fn input+) call each
\ consume one and the stream position proves they are real reads.
create test-input-bytes 51 c, 10 c, 52 c, 10 c,

: test-write-input ( -- )
	s" baku-kernel-input.kl" w/o bin create-file throw >r
	test-input-bytes 4 r@ write-file throw
	r> close-file throw ;

: test-open-input ( -- obj )
	s" baku-kernel-input.kl" r/o bin open-file baku-stream-from-file ;

variable test-stdin
variable test-saved-stdin

test-write-input
test-open-input test-stdin !
s" *stinput*" baku-intern baku-global-lookup
	test-saved-stdin !
s" *stinput*" baku-intern test-stdin @ baku-global-define drop

s" (input+ number (stinput))" ev baku-fixnum-value 3 9 check-num
s" (((fn input+) number) (stinput))" ev baku-fixnum-value 4 10 check-num

s" *stinput*" baku-intern test-saved-stdin @ baku-global-define drop
test-stdin @ baku-prim-close drop
s" baku-kernel-input.kl" delete-file 0= 11 check

\ ---------------------------------------------------------------------------
\ Zero-place fn and thaw.  FN invokes a zero-arity function directly and
\ returns the lambda form otherwise; THAW is application.
\ ---------------------------------------------------------------------------

s" (arity version)" ev baku-fixnum-value 0 12 check-num
s" (fn version)" ev s" 43.2" test-str= 13 check
s" (thaw (freeze 7))" ev baku-fixnum-value 7 14 check-num
s" (thaw (freeze (+ 1 2)))" ev baku-fixnum-value 3 15 check-num
s" ((fn not) true)" ev baku-false = 16 check

\ ---------------------------------------------------------------------------
\ Kernel vector accessors.  VECTOR N builds a vector whose slot 0 is the
\ length; HDV and TLV are kernel defuns over <-VECTOR/VECTOR->.
\ ---------------------------------------------------------------------------

s" (let V (vector 3) (let A (vector-> V 1 10) (let B (vector-> V 2 20) (let C (vector-> V 3 30) (hdv V)))))"
	ev baku-fixnum-value 10 17 check-num
s" (let V (vector 3) (let A (vector-> V 1 10) (let B (vector-> V 2 20) (let C (vector-> V 3 30) (limit (tlv V))))))"
	ev baku-fixnum-value 2 18 check-num
s" (let V (vector 3) (let A (vector-> V 1 10) (let B (vector-> V 2 20) (let C (vector-> V 3 30) (<-vector (tlv V) 1)))))"
	ev baku-fixnum-value 20 19 check-num
s" (let V (vector 3) (let A (vector-> V 1 10) (let B (vector-> V 2 20) (let C (vector-> V 3 30) (<-vector (tlv V) 2)))))"
	ev baku-fixnum-value 30 20 check-num

s" (trap-error (hdv (vector 0)) (lambda E 99))" ev baku-fixnum-value 99 21 check-num
s" (trap-error (tlv (vector 0)) (lambda E 99))" ev baku-fixnum-value 99 22 check-num
s" (trap-error (hdv 3) (lambda E 99))" ev baku-fixnum-value 99 23 check-num

\ ---------------------------------------------------------------------------
\ Kernel classifiers.  These are the kernel's own definitions, not host
\ primitives: every host value shape goes through them.
\ ---------------------------------------------------------------------------

s" (integer? 3)" ev baku-true = 24 check
s" (integer? 10000000000)" ev baku-true = 25 check
s" (integer? 3.5)" ev baku-false = 26 check
s" (integer? (str 3))" ev baku-false = 27 check

s" (symbol? (intern (str foo)))" ev baku-true = 28 check
s" (symbol? 3)" ev baku-false = 29 check
s" (symbol? true)" ev baku-false = 30 check
s" (symbol? ())" ev baku-false = 31 check

s" (boolean? true)" ev baku-true = 32 check
s" (boolean? false)" ev baku-true = 33 check
s" (boolean? 0)" ev baku-false = 34 check

s" (vector? (vector 2))" ev baku-true = 35 check
s" (vector? 3)" ev baku-false = 36 check
s" (vector? (cons 1 2))" ev baku-false = 37 check

\ ---------------------------------------------------------------------------
\ Writer round-trip.  A form read by the shipped KLambda reader is printed by
\ the kernel writer, emitted through PR to a byte stream, read back from the
\ file, and re-read; the second form must equal the first.  SHEN.APP with mode
\ SHEN.R is the writer's value-to-text stage and produces a parenthesised form;
\ PR is the stream emitter.  The cases cover punctuation symbols, an embedded
\ newline string, a literal backslash string and the real literal-backslash
\ defun lines in the pinned stlib.kl corpus.
\ ---------------------------------------------------------------------------

create test-writer-buf 8192 allot
create test-writer-line-buf 4096 allot
variable test-writer-fileid
variable test-writer-scan-fileid
variable test-writer-found

: test-writer-set ( value c-addr u -- )
	baku-intern swap baku-global-define drop ;

: test-writer-get ( c-addr u -- value )
	baku-intern baku-global-lookup drop ;

\ Copy a reader form out of the reader scratch block into the non-GC heap, so
\ the form survives the reads that follow it.
: test-copy-form ( v -- v' )
	dup baku-fixnum? if exit then
	dup baku-nil = if exit then
	dup baku-true = if exit then
	dup baku-false = if exit then
	dup baku-symbol? if exit then
	dup baku-string? if
		dup baku-string-addr swap baku-string-length baku-string exit
	then
	dup baku-float? if baku-float@ baku-float exit then
	dup baku-cons? if
		dup baku-hd recurse
		swap baku-tl recurse
		baku-cons exit
	then
	." BAKU-TEST-FAIL: writer form has an unsupported value" cr abort ;

: test-writer-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: writer reader refused a form" cr abort
	then
	test-copy-form ;

: test-writer-format ( -- str )
	s" (shen.app (value baku.kernel.writer-form) (tlstr (str 0)) shen.r)"
		ev ;

: test-writer-read-file ( -- str )
	s" baku-writer.tmp" r/o bin open-file throw test-writer-fileid !
	test-writer-buf 8192 test-writer-fileid @ read-file throw
	test-writer-fileid @ close-file throw
	test-writer-buf swap baku-string ;

\ Read a source form with the shipped KLambda reader, print it with the kernel
\ writer, emit the text through PR to a byte stream, read the bytes back and
\ re-read them; the second form must equal the first.
: test-writer-roundtrip ( c-addr u -- flag )
	test-writer-read s" baku.kernel.writer-form" test-writer-set
	test-writer-format s" baku.kernel.writer-text" test-writer-set
	s" baku-writer.tmp" baku-string s" out" baku-intern baku-prim-open
		s" baku.kernel.writer-stream" test-writer-set
	s" (pr (value baku.kernel.writer-text) (value baku.kernel.writer-stream))"
		ev drop
	s" baku.kernel.writer-stream" test-writer-get baku-prim-close drop
	test-writer-read-file
	dup baku-string-addr swap baku-string-length
	test-writer-read
	s" baku.kernel.writer-form" test-writer-get
	baku-eq? ;

: test-has-backslash? ( c-addr u -- flag )
	begin dup 0> while
		over c@ 92 = if 2drop true exit then
		1- swap char+ swap
	repeat 2drop false ;

: test-defun-line? ( c-addr u -- flag )
	dup 7 >= if
		over 7 s" (defun " compare 0= -rot 2drop
	else
		2drop false
	then ;

s" (a-b? c_d e:f g;h i<j k=l)" test-writer-roundtrip 38 check

create test-writer-newline
	40 c, 102 c, 111 c, 111 c, 32 c, 34 c, 108 c, 105 c, 110 c, 101 c, 49 c,
	10 c, 108 c, 105 c, 110 c, 101 c, 50 c, 34 c, 41 c,
test-writer-newline 19 test-writer-roundtrip 39 check

create test-writer-backslash
	40 c, 102 c, 111 c, 111 c, 32 c, 34 c, 92 c, 34 c, 41 c,
test-writer-backslash 9 test-writer-roundtrip 40 check

\ The pinned stlib.kl has eight one-character backslash strings, two on each of
\ four single-line defuns.  Round-trip every such defun line; stop before the
\ 74 KiB source-data line, which is not a form on its own.
: test-writer-corpus-backslash ( -- )
	0 test-writer-found !
	s" vendor/shen-43.2/klambda/stlib.kl" r/o bin open-file throw
		test-writer-scan-fileid !
	begin
		test-writer-line-buf 4096 test-writer-scan-fileid @ read-line throw
		dup 0= if
			2drop
			test-writer-scan-fileid @ close-file throw
			test-writer-found @ 4 = if exit then
			." BAKU-TEST-FAIL: missing literal-backslash defun line" cr
			abort
		then
		drop test-writer-line-buf swap
		2dup test-has-backslash? >r
		2dup test-defun-line? r> and if
			test-writer-roundtrip if
				1 test-writer-found +!
			else
				." BAKU-TEST-FAIL: corpus writer round-trip " cr
				abort
			then
		else
			2drop
		then
		test-writer-found @ 4 >= if
			test-writer-scan-fileid @ close-file throw exit
		then
	again ;

test-writer-corpus-backslash
s" baku-writer.tmp" delete-file 0= 41 check
test-writer-found @ 4 = 42 check

\ ---------------------------------------------------------------------------
\ Public primitive arities.  The kernel installs these from its arity table, so
\ the Shen-visible contract is checked at the kernel boundary, not by the host
\ registration alone.
\ ---------------------------------------------------------------------------

s" (arity char-stream?)" ev baku-fixnum-value 1 43 check-num
s" (arity read-unit-string)" ev baku-fixnum-value 1 44 check-num
s" (arity write-string)" ev baku-fixnum-value 2 45 check-num

." BAKU-TEST-DONE" cr
