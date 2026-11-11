\ KLambda stream and file I/O primitives.
\
\ These tests exercise 4th/primitives.4th through both boundaries: the stream
\ primitives directly and BAKU-EVAL-KL.  Files are byte streams and the standard
\ streams are character streams, matching the kernel's CHAR-STREAM? split.
\ The temporary files are removed at the end of the run.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused an I/O form" cr abort
	then
	baku-eval-kl ;

: prim-error-1 ( a xt -- code )
	catch >r drop r> ;

: prim-error-2 ( a b xt -- code )
	catch >r 2drop r> ;

: test-str= ( obj c-addr u -- flag )
	baku-string baku-prim-eq baku-true = ;

: dir-in ( -- sym ) s" in" baku-intern ;
: dir-out ( -- sym ) s" out" baku-intern ;

variable out-stream
variable in-stream
variable std-stream

\ ---------------------------------------------------------------------------
\ Byte stream: write, then read back, then end of file
\ ---------------------------------------------------------------------------

s" baku-io-test.bin" baku-string dir-out baku-prim-open
	dup baku-stream? 1 check
	dup baku-prim-char-stream? baku-false = 2 check
	out-stream !

65 baku-fixnum out-stream @ baku-prim-write-byte
	out-stream @ = 3 check
66 baku-fixnum out-stream @ baku-prim-write-byte
	out-stream @ = 4 check

s" CD" baku-string out-stream @ baku-prim-write-string
	dup s" CD" test-str= 5 check
	drop

out-stream @ baku-prim-close out-stream @ = 6 check

s" baku-io-test.bin" baku-string dir-in baku-prim-open
	dup baku-stream? 1 check
	dup baku-prim-char-stream? baku-false = 7 check
	in-stream !

in-stream @ baku-prim-read-byte baku-fixnum-value 65 = 8 check
in-stream @ baku-prim-read-byte baku-fixnum-value 66 = 9 check
in-stream @ baku-prim-read-byte baku-fixnum-value 67 = 10 check
in-stream @ baku-prim-read-byte baku-fixnum-value 68 = 11 check
in-stream @ baku-prim-read-byte baku-fixnum-value -1 = 12 check
in-stream @ baku-prim-close in-stream @ = 13 check

\ READ-UNIT-STRING reads one character and returns a one-byte string.
s" baku-io-test.bin" baku-string dir-in baku-prim-open in-stream !
in-stream @ baku-prim-read-unit-string dup s" A" test-str= 14 check drop
in-stream @ baku-prim-close drop

\ ---------------------------------------------------------------------------
\ Standard streams are character streams
\ ---------------------------------------------------------------------------

baku-stdout-stream std-stream !
std-stream @ baku-prim-char-stream? baku-true = 15 check
std-stream @ baku-prim-close std-stream @ = 16 check

baku-stdout-stream std-stream !
s" " baku-string std-stream @ baku-prim-write-string
	s" " test-str= 17 check
std-stream @ baku-prim-close drop

baku-stdin-stream std-stream !
std-stream @ baku-prim-char-stream? baku-true = 18 check
std-stream @ baku-prim-close drop

\ ---------------------------------------------------------------------------
\ Errors are catchable
\ ---------------------------------------------------------------------------

s" baku-io-no-such-file.bin" baku-string dir-in ' baku-prim-open
	prim-error-2 baku-file-error = 19 check

1 baku-fixnum dir-in ' baku-prim-open
	prim-error-2 baku-eval-type = 20 check

s" baku-io-test.bin" baku-string 1 baku-fixnum ' baku-prim-open
	prim-error-2 baku-eval-type = 21 check

s" baku-io-test.bin" baku-string s" append" baku-intern ' baku-prim-open
	prim-error-2 baku-invalid-argument = 22 check

1 baku-fixnum ' baku-prim-read-byte prim-error-1 baku-eval-type = 23 check
1 baku-fixnum ' baku-prim-close prim-error-1 baku-eval-type = 24 check
1 baku-fixnum ' baku-prim-char-stream? prim-error-1 baku-eval-type = 25 check

baku-true baku-stdout-stream ' baku-prim-write-byte
	prim-error-2 baku-eval-type = 26 check

256 baku-fixnum baku-stdout-stream ' baku-prim-write-byte
	prim-error-2 baku-invalid-argument = 27 check

1 baku-fixnum baku-stdout-stream ' baku-prim-write-string
	prim-error-2 baku-eval-type = 28 check

\ Reading from an output stream is a misuse, not a crash.
baku-stdout-stream std-stream !
std-stream @ ' baku-prim-read-byte prim-error-1
	baku-invalid-argument = 29 check
std-stream @ baku-prim-close drop

\ ---------------------------------------------------------------------------
\ Through the evaluator
\ ---------------------------------------------------------------------------

s" (let S (open (cn (str baku-io) (str .tmp)) out) (let C (char-stream? S) (let X (close S) C)))" run
	baku-false = 30 check

s" (trap-error (open (str baku-io-missing) in) (lambda E 99))" run
	baku-fixnum-value 99 = 31 check

s" baku-io-test.bin" delete-file drop
s" baku-io.tmp" delete-file drop

." BAKU-TEST-DONE" cr
