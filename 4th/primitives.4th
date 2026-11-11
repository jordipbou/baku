\ Baku KLambda primitives.
\
\ This layer implements the host primitives the pinned Shen 43.2 kernel
\ applies but never defines.  It loads after the evaluator and installs each
\ primitive through BAKU-DEFPRIM, so the interpreter, the tail-call trampoline
\ and every future compiler mode share one registration path.
\
\ Arithmetic:
\   + - *    two fixnums give a checked fixnum; a float operand gives a float
\   /        two fixnums give the exact integer quotient when the division is
\            exact, otherwise a float; a float operand gives a float
\            (Shen 43.2 /, not Forth's truncating integer division)
\   > < >= <=  signed numeric comparison over fixnums and floats
\   number?    true for a fixnum or a boxed float
\   string?    true for a Baku string
\   absvector? true for a Baku vector
\   absvector  allocate a zero-filled vector of N cells
\   address->  write a cell at a zero-based index and return the vector
\   <-address  read a cell at a zero-based index
\   cons cons? hd tl  Baku cons cells; HD and TL raise a catchable type error
\              on a non-cons
\   intern     intern a string case-sensitively; the textual names TRUE and
\              FALSE yield the reserved immediates, matching the reader
\   =          Shen equality: numeric across fixnum/float, byte equality for
\              strings, identity for interned symbols and immediates, element
\              equality for vectors, recursive equality for conses; a closure,
\              stream or error object compares false instead of raising
\   open close read-byte write-byte read-unit-string write-string char-stream?
\              a stream is a stream object holding a mode and a Forth fileid;
\              files are byte streams, the standard streams are character
\              streams; read-byte returns -1 at end of file
\
\ The current target has 64-bit cells and no boxed integers (M0).  A fixnum
\ arithmetic result outside the fixnum range is therefore a catchable
\ BAKU-ARITHMETIC-OVERFLOW rather than a silent wrap.  Division by any numeric
\ zero is a catchable BAKU-DIVISION-BY-ZERO.  Type errors are BAKU-EVAL-TYPE.
\ All three are raw Forth THROW codes; TRAP-ERROR maps them to a fixnum until
\ the M5 error-object payload exists.
\
\ Every arithmetic word validates both operands before it pushes anything on
\ the float stack: CATCH restores the data and return stacks on Sloth but not
\ the float stack, so leaving floats behind on an error path would leak.

\ ---------------------------------------------------------------------------
\ Errors
\ ---------------------------------------------------------------------------

-281 constant baku-arithmetic-overflow
-282 constant baku-division-by-zero
-283 constant baku-file-error

\ ---------------------------------------------------------------------------
\ Fixnum range
\
\ BAKU-FIXNUM-MIN and BAKU-FIXNUM-MAX are defined in value.4th so the reader
\ and the arithmetic primitives share one range.  The helpers here turn a
\ double-cell intermediate into a tagged fixnum, or throw when it does not fit.
\ ---------------------------------------------------------------------------

variable baku-d-lo
variable baku-d-hi

\ Turn a double-cell integer into a tagged fixnum, or throw when it does not
\ fit the fixnum range.
: baku-fixnum-of-d ( d -- x )
	baku-d-hi ! baku-d-lo !
	baku-d-lo @ baku-d-hi @ baku-fixnum-min s>d d< if
		baku-arithmetic-overflow throw
	then
	baku-fixnum-max s>d baku-d-lo @ baku-d-hi @ d< if
		baku-arithmetic-overflow throw
	then
	baku-d-lo @ baku-d-hi @ d>s baku-fixnum ;

: baku-check-fixnum-value ( n -- x )
	dup baku-fixnum-min < if baku-arithmetic-overflow throw then
	dup baku-fixnum-max > if baku-arithmetic-overflow throw then
	baku-fixnum ;

\ ---------------------------------------------------------------------------
\ Number classification and conversion
\ ---------------------------------------------------------------------------

: baku-number? ( x -- flag )
	dup baku-fixnum? if drop true else baku-float? then ;

: baku-assert-numbers ( a b -- a b )
	over baku-number? 0= if baku-eval-type throw then
	dup baku-number? 0= if baku-eval-type throw then ;

\ Convert a number to the float stack.  The caller must have validated it, so
\ this never throws after it has pushed a float.
: baku->float ( x -- ) ( F: -- r )
	dup baku-fixnum? if baku-fixnum-value s>f exit then
	baku-float@ ;

\ True when the number is zero.  Consumes the value and never leaves a float
\ on the float stack.
: baku-zero-number? ( x -- flag )
	dup baku-fixnum? if baku-fixnum-value 0= exit then
	dup baku-float? if baku-float@ f0= else drop false then ;

\ ---------------------------------------------------------------------------
\ Numeric comparison
\ ---------------------------------------------------------------------------

: baku-number< ( a b -- flag )
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-value swap baku-fixnum-value swap < exit
	then
	>r baku->float r> baku->float f< ;

: baku-number> ( a b -- flag ) swap baku-number< ;

\ Numeric equality is used by Shen =.  Sloth has no F=, and a zero-tolerance
\ F~ compares bit patterns (so +0.0 and -0.0 differ), so subtract and test for
\ zero instead.
: baku-number= ( a b -- flag )
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-value swap baku-fixnum-value = exit
	then
	>r baku->float r> baku->float f- f0= ;

\ Define <= and >= through equality instead of "not >" / "not <": a NaN has
\ every comparison false, and negating > would wrongly make NaN <= x true.
: baku-number<= ( a b -- flag )
	2dup baku-number= if 2drop true else baku-number< then ;

: baku-number>= ( a b -- flag )
	2dup baku-number= if 2drop true else baku-number> then ;

\ ---------------------------------------------------------------------------
\ Arithmetic
\ ---------------------------------------------------------------------------

: baku-fixnum-add-d ( a b -- d )
	baku-fixnum-value swap baku-fixnum-value s>d rot s>d d+ ;

: baku-fixnum-sub-d ( a b -- d )
	baku-fixnum-value swap baku-fixnum-value s>d rot s>d d- ;

: baku-fixnum-mul-d ( a b -- d )
	baku-fixnum-value swap baku-fixnum-value m* ;

: baku-prim-add ( a b -- x )
	baku-assert-numbers
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-add-d baku-fixnum-of-d exit
	then
	>r baku->float r> baku->float f+ baku-float ;

: baku-prim-sub ( a b -- x )
	baku-assert-numbers
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-sub-d baku-fixnum-of-d exit
	then
	>r baku->float r> baku->float f- baku-float ;

: baku-prim-mul ( a b -- x )
	baku-assert-numbers
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-mul-d baku-fixnum-of-d exit
	then
	>r baku->float r> baku->float f* baku-float ;

\ Shen / returns an integer when the division is exact and a float otherwise.
: baku-prim-div ( a b -- x )
	baku-assert-numbers
	dup baku-zero-number? if 2drop baku-division-by-zero throw then
	over baku-fixnum? over baku-fixnum? and if
		baku-fixnum-value swap baku-fixnum-value swap
		2dup mod 0= if
			dup -1 = if
				over baku-fixnum-min = if
					2drop baku-arithmetic-overflow throw
				then
			then
			2dup / nip nip
			baku-check-fixnum-value exit
		then
		s>f s>f fswap f/ baku-float exit
	then
	>r baku->float r> baku->float f/ baku-float ;

\ ---------------------------------------------------------------------------
\ Comparison primitives
\ ---------------------------------------------------------------------------

: baku-prim-lt ( a b -- x )
	baku-assert-numbers
	baku-number< if baku-true else baku-false then ;

: baku-prim-gt ( a b -- x )
	baku-assert-numbers
	baku-number> if baku-true else baku-false then ;

: baku-prim-le ( a b -- x )
	baku-assert-numbers
	baku-number<= if baku-true else baku-false then ;

: baku-prim-ge ( a b -- x )
	baku-assert-numbers
	baku-number>= if baku-true else baku-false then ;

\ ---------------------------------------------------------------------------
\ Shen equality
\ ---------------------------------------------------------------------------

\ Both strings must be the same length and the same bytes.  This helper does
\ not call user code, so the scratch variables cannot be clobbered.
variable baku-eq-sa
variable baku-eq-sb
variable baku-eq-slen

: baku-string= ( a b -- flag )
	baku-eq-sb ! baku-eq-sa !
	baku-eq-sa @ baku-string-length
	baku-eq-sb @ baku-string-length
	2dup <> if 2drop false exit then
	drop baku-eq-slen !
	baku-eq-sa @ baku-string-addr
	baku-eq-sb @ baku-string-addr
	baku-eq-slen @ baku-bytes= ;

defer baku-eq-vectors

\ Closures, streams and errors are outside Shen's equality range: the
\ specification says comparison of a closure or stream returns false, so even
\ the identity shortcut must not apply to them.
: baku-opaque-type? ( type -- flag )
	dup baku-type-closure = if drop true exit then
	dup baku-type-stream = if drop true exit then
	baku-type-error = ;

: baku-opaque? ( x -- flag )
	dup baku-object? if baku-object-type baku-opaque-type? else drop false then ;

\ Shen equality is total.  An opaque object compares false even with itself and
\ never raises; the kernel's writer relies on comparing an arbitrary value with
\ (fail) without trapping an error.
: baku-eq? ( a b -- flag )
	over baku-opaque? over baku-opaque? or if 2drop false exit then
	2dup = if 2drop true exit then
	over baku-number? over baku-number? and if baku-number= exit then
	over baku-string? over baku-string? and if baku-string= exit then
	over baku-cons? over baku-cons? and if
		2dup baku-hd swap baku-hd recurse if
			baku-tl swap baku-tl recurse
		else
			2drop false
		then
		exit
	then
	over baku-vector? over baku-vector? and if baku-eq-vectors exit then
	2drop false ;

\ Vector equality saves the outer element state on the return stack, because
\ comparing an element can re-enter this word through a nested vector.
variable baku-eq-va
variable baku-eq-vb
variable baku-eq-vi
variable baku-eq-vn

: baku-eq-vector-values ( a b -- flag )
	over baku-vector-length over baku-vector-length
	2dup <> if 2drop 2drop false exit then
	drop
	baku-eq-va @ >r
	baku-eq-vb @ >r
	baku-eq-vi @ >r
	baku-eq-vn @ >r
	baku-eq-vn ! baku-eq-vb ! baku-eq-va !
	0 baku-eq-vi !
	begin
		baku-eq-vi @ baku-eq-vn @ <
	while
		baku-eq-va @ baku-eq-vi @ baku-vector@
		baku-eq-vb @ baku-eq-vi @ baku-vector@
		baku-eq? 0= if
			false
			r> baku-eq-vn ! r> baku-eq-vi !
			r> baku-eq-vb ! r> baku-eq-va !
			exit
		then
		baku-eq-vi @ 1+ baku-eq-vi !
	repeat
	true
	r> baku-eq-vn ! r> baku-eq-vi !
	r> baku-eq-vb ! r> baku-eq-va ! ;

' baku-eq-vector-values is baku-eq-vectors

: baku-prim-eq ( a b -- x )
	baku-eq? if baku-true else baku-false then ;

\ ---------------------------------------------------------------------------
\ Cons and classifiers
\
\ The layer below already owns the representation (BAKU-CONS, BAKU-HD and the
\ type predicates); these words only expose it to KLambda.  HD and TL raise the
\ same BAKU-EVAL-TYPE as the arithmetic group, so TRAP-ERROR handles every
\ primitive type failure through one path.
\ ---------------------------------------------------------------------------

: baku-prim-cons ( a b -- obj ) baku-cons ;

: baku-prim-cons? ( x -- result )
	baku-cons? if baku-true else baku-false then ;

: baku-prim-hd ( obj -- hd )
	dup baku-cons? 0= if baku-eval-type throw then baku-hd ;

: baku-prim-tl ( obj -- tl )
	dup baku-cons? 0= if baku-eval-type throw then baku-tl ;

: baku-prim-number? ( x -- result )
	baku-number? if baku-true else baku-false then ;

: baku-prim-string? ( x -- result )
	baku-string? if baku-true else baku-false then ;

: baku-prim-absvector? ( x -- result )
	baku-vector? if baku-true else baku-false then ;

\ ---------------------------------------------------------------------------
\ Vectors
\
\ ABSVECTOR allocates N cells (indexed 0 .. N-1); the value layer zero-fills
\ them.  ADDRESS-> and <-ADDRESS take a zero-based index.  A non-vector or a
\ non-fixnum index is the same catchable BAKU-EVAL-TYPE as every other
\ primitive; an index outside the vector is the value layer's catchable
\ BAKU-VECTOR-BOUNDS-ERROR, matching POS/TLSTR's use of the string bounds code.
\ ---------------------------------------------------------------------------

variable baku-vec-index

: baku-prim-vector-index ( x -- i )
	dup baku-fixnum? 0= if drop baku-eval-type throw then
	baku-fixnum-value ;

: baku-prim-absvector ( n -- obj )
	baku-prim-vector-index baku-vector ;

\ KLambda order is (vector index value); the value layer writer takes
\ (value vector index), so reorder before the store.
: baku-prim-address-> ( obj index value -- obj )
	-rot                              ( value obj index )
	baku-prim-vector-index            ( value obj i )
	swap >r                           ( value i | R: obj )
	r@ baku-vector? 0= if
		drop drop r> drop baku-eval-type throw
	then
	r@ swap baku-vector!
	r> ;

: baku-prim-<-address ( obj index -- value )
	baku-prim-vector-index baku-vec-index !
	dup baku-vector? 0= if drop baku-eval-type throw then
	baku-vec-index @ baku-vector@ ;

\ ---------------------------------------------------------------------------
\ Numbers and symbols as text
\ ---------------------------------------------------------------------------

15 constant baku-float-digits-max
create baku-float-digits baku-float-digits-max allot
create baku-num-buffer 64 allot
variable baku-num-len
variable baku-fmt-exp
variable baku-fmt-sign
variable baku-fmt-count

: baku-num-reset ( -- ) 0 baku-num-len ! ;

: baku-num-c! ( c -- )
	baku-num-buffer baku-num-len @ + c!
	1 baku-num-len +! ;

: baku-num-string ( c-addr u -- )
	0 ?do dup c@ baku-num-c! char+ loop drop ;

: baku-num-fixnum ( n -- )
	dup >r s>d dabs <# #s r> sign #> baku-num-string ;

: baku-num-digit ( i -- ) baku-float-digits + c@ baku-num-c! ;

: baku-num-digits ( from to -- ) swap ?do i baku-num-digit loop ;

\ REPRESENT supplies U significant digits and a decimal exponent N: the value is
\ 0.digits * 10^N.  Keep the digits, the exponent and the sign, and trim trailing
\ zeros so 1.5 does not print as 1.5000000000000000.
: baku-float-capture ( F: r -- ; -- flag )
	baku-float-digits baku-float-digits-max represent ( n sign valid )
	dup 0= if 2drop false exit then drop
	baku-fmt-sign ! baku-fmt-exp !
	baku-float-digits-max baku-fmt-count !
	begin
		baku-fmt-count @ 1 >
		if
			baku-float-digits baku-fmt-count @ 1- + c@ [char] 0 <>
			if
				true
			else
				baku-fmt-count @ 1- baku-fmt-count !
				false
			then
		else
			true
		then
	until
	true ;

: baku-float-build ( -- )
	baku-num-reset
	baku-fmt-sign @ 0<> if [char] - baku-num-c! then
	baku-fmt-count @ 1 = if
		baku-float-digits c@ [char] 0 = if
			s" 0.0" baku-num-string exit
		then
	then
	baku-fmt-exp @ 17 > baku-fmt-exp @ -3 < or if
		baku-float-digits c@ baku-num-c!
		baku-fmt-count @ 1 > if
			[char] . baku-num-c!
			1 baku-fmt-count @ baku-num-digits
		then
		[char] e baku-num-c!
		baku-fmt-exp @ 1- baku-num-fixnum
	else
		baku-fmt-exp @ 0> if
			baku-fmt-exp @ baku-fmt-count @ < if
				0 baku-fmt-exp @ baku-num-digits
				[char] . baku-num-c!
				baku-fmt-exp @ baku-fmt-count @ baku-num-digits
			else
				0 baku-fmt-count @ baku-num-digits
				baku-fmt-exp @ baku-fmt-count @ -
				0 ?do [char] 0 baku-num-c! loop
				[char] . baku-num-c!
				[char] 0 baku-num-c!
			then
		else
			s" 0." baku-num-string
			baku-fmt-exp @ negate 0 ?do [char] 0 baku-num-c! loop
			0 baku-fmt-count @ baku-num-digits
		then
	then ;

: baku-float->string ( obj -- str )
	baku-float@ baku-float-capture if
		baku-float-build
	else
		baku-num-reset s" nan" baku-num-string
	then
	baku-num-buffer baku-num-len @ baku-string ;

: baku-fixnum->string ( x -- str )
	baku-fixnum-value
	dup >r s>d dabs <# #s r> sign #> baku-string ;

\ ---------------------------------------------------------------------------
\ String primitives
\ ---------------------------------------------------------------------------

create baku-byte-buffer 1 allot

: baku-prim-cn ( a b -- obj )
	over baku-string? 0= if baku-eval-type throw then
	dup baku-string? 0= if baku-eval-type throw then
	baku-string-cat ;

: baku-prim-pos ( obj i -- obj' )
	over baku-string? 0= if baku-eval-type throw then
	dup baku-fixnum? 0= if baku-eval-type throw then
	baku-fixnum-value 1 baku-string-slice ;

: baku-prim-tlstr ( obj -- obj' )
	dup baku-string? 0= if baku-eval-type throw then
	dup baku-string-length dup 0= if drop drop baku-string-bounds-error throw then
	1- 1 swap baku-string-slice ;

: baku-prim-string->n ( obj -- n )
	dup baku-string? 0= if baku-eval-type throw then
	dup baku-string-length dup 0= if drop drop baku-string-bounds-error throw then
	drop 0 baku-string@ baku-fixnum ;

: baku-prim-n->string ( n -- obj )
	dup baku-fixnum? 0= if baku-eval-type throw then
	baku-fixnum-value
	dup 0< over 255 > or if drop baku-invalid-argument throw then
	baku-byte-buffer c! baku-byte-buffer 1 baku-string ;

: baku-prim-str ( x -- obj )
	dup baku-symbol? if
		dup baku-symbol-name-addr swap baku-symbol-name-len baku-string exit
	then
	dup baku-string? if baku-string-quote exit then
	dup baku-fixnum? if baku-fixnum->string exit then
	dup baku-float? if baku-float->string exit then
	dup baku-true = if drop s" true" baku-string exit then
	dup baku-false = if drop s" false" baku-string exit then
	baku-eval-type throw ;

\ ---------------------------------------------------------------------------
\ Symbol primitives
\ ---------------------------------------------------------------------------

: baku-prim-intern ( obj -- sym )
	dup baku-string? 0= if baku-eval-type throw then
	dup baku-string-addr swap baku-string-length      ( c-addr u )
	2dup baku-immediate-name if nip nip exit then
	baku-intern ;

\ ---------------------------------------------------------------------------
\ Errors
\
\ SIMPLE-ERROR copies its string into a Baku error object and throws it through
\ BAKU-RAISE, so TRAP-ERROR receives the object itself.  ERROR-TO-STRING copies
\ the message back out; a non-error value is rendered with the same rules as
\ STR, because a raw Forth exception reaches a trap handler as a fixnum.
\ ---------------------------------------------------------------------------

: baku-prim-simple-error ( obj -- )
	dup baku-string? 0= if baku-eval-type throw then
	dup baku-string-addr swap baku-string-length
	baku-error baku-raise ;

: baku-prim-error-to-string ( x -- str )
	dup baku-error? if baku-error-message baku-string exit then
	baku-prim-str ;

\ ---------------------------------------------------------------------------
\ Streams and file I/O
\
\ A stream is a BAKU-TYPE-STREAM object with two raw payload cells:
\
\   [ mode, handle ]
\
\   mode 0  a file opened through OPEN, HANDLE is the Forth fileid
\   mode 1  standard input, read with KEY
\   mode 2  standard output, written with EMIT and TYPE
\
\ Files are byte streams (CHAR-STREAM? is false), which the I/O spec allows for
\ a byte-oriented port; the standard streams are character streams.  The kernel
\ chooses READ-UNIT-STRING/WRITE-STRING for a character stream and
\ READ-BYTE/WRITE-BYTE otherwise, so both paths must work.
\
\ The stream object is allocated only after the file operation succeeds, so a
\ failed OPEN leaves no handle and no heap object behind.  A failed READ, WRITE
\ or CLOSE raises the catchable BAKU-FILE-ERROR; TRAP-ERROR sees it as a fixnum
\ like every other raw Forth code.
\ ---------------------------------------------------------------------------

0 constant baku-stream-file
1 constant baku-stream-input
2 constant baku-stream-output

: baku-stream? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-stream = else drop false then ;

: baku-stream ( mode handle -- obj )
	2 cells baku-type-stream baku-alloc       ( mode handle obj )
	dup >r 2 cells + !                        ( mode | R: obj )
	r@ cell + !
	r> ;

: baku-stream-mode ( obj -- mode )
	dup baku-stream? 0= if baku-eval-type throw then cell + @ ;

: baku-stream-handle ( obj -- handle )
	dup baku-stream? 0= if baku-eval-type throw then 2 cells + @ ;

: baku-stdin-stream ( -- obj ) baku-stream-input 0 baku-stream ;
: baku-stdout-stream ( -- obj ) baku-stream-output 0 baku-stream ;

: baku-symbol-text= ( sym c-addr u -- flag )
	2>r
	dup baku-symbol? 0= if drop 2r> 2drop false exit then
	dup baku-symbol-name-len 2r@ nip <> if drop 2r> 2drop false exit then
	baku-symbol-name-addr 2r@ baku-bytes= 2r> 2drop ;

variable baku-io-stream
variable baku-io-str
variable baku-io-byte
variable baku-io-name
variable baku-io-dir
create baku-io-byte-buffer 1 allot

\ Fileid and IOR are on the stack; a non-zero IOR discards both and throws.
: baku-stream-from-file ( fileid ior -- obj )
	dup 0<> if 2drop baku-file-error throw then
	drop baku-stream-file swap baku-stream ;

: baku-prim-open ( name dir -- obj )
	baku-io-dir ! baku-io-name !
	baku-io-name @ baku-string? 0= if baku-eval-type throw then
	baku-io-dir @ baku-symbol? 0= if baku-eval-type throw then
	baku-io-dir @ s" in" baku-symbol-text= if
		baku-io-name @ baku-string-addr
		baku-io-name @ baku-string-length
		r/o bin open-file baku-stream-from-file exit
	then
	baku-io-dir @ s" out" baku-symbol-text= 0= if
		baku-invalid-argument throw
	then
	baku-io-name @ baku-string-addr
	baku-io-name @ baku-string-length
	w/o bin create-file baku-stream-from-file ;

: baku-prim-close ( obj -- obj )
	dup baku-stream? 0= if baku-eval-type throw then
	dup baku-stream-mode baku-stream-file = if
		dup baku-stream-handle close-file
		0<> if baku-file-error throw then
	then ;

: baku-prim-char-stream? ( obj -- result )
	dup baku-stream? 0= if baku-eval-type throw then
	baku-stream-mode baku-stream-file = if baku-false else baku-true then ;

\ Read one raw byte; -1 means end of file.  Standard input goes through KEY so
\ the character-stream contract holds; a file goes through READ-FILE.
: baku-read-one-byte ( obj -- n )
	dup baku-stream? 0= if baku-eval-type throw then
	dup baku-stream-mode
	dup baku-stream-input = if
		2drop key exit
	then
	dup baku-stream-file = 0= if
		2drop baku-invalid-argument throw
	then
	drop baku-stream-handle                    ( fileid )
	baku-io-byte-buffer 1 rot read-file        ( u2 ior )
	dup 0<> if 2drop baku-file-error throw then
	drop
	dup 0= if drop -1 exit then
	drop baku-io-byte-buffer c@ ;

: baku-prim-read-byte ( obj -- n )
	baku-read-one-byte baku-fixnum ;

: baku-prim-read-unit-string ( obj -- str )
	baku-read-one-byte
	dup 0< if drop baku-file-error throw then
	baku-io-byte-buffer c!
	baku-io-byte-buffer 1 baku-string ;

\ KLambda order is (byte stream); write-byte returns the stream.
: baku-prim-write-byte ( byte obj -- obj )
	baku-io-stream !
	baku-io-byte !
	baku-io-stream @ baku-stream? 0= if baku-eval-type throw then
	baku-io-byte @ dup baku-fixnum? 0= if drop baku-eval-type throw then
	baku-fixnum-value
	dup 0< over 255 > or if drop baku-invalid-argument throw then
	baku-io-byte-buffer c!
	baku-io-stream @ baku-stream-mode
	dup baku-stream-output = if
		drop baku-io-byte-buffer c@ emit baku-io-stream @ exit
	then
	baku-stream-file = if
		baku-io-stream @ baku-stream-handle
		baku-io-byte-buffer 1 rot write-file
		0<> if baku-file-error throw then
		baku-io-stream @ exit
	then
	baku-invalid-argument throw ;

\ KLambda order is (string stream); write-string returns the string.
: baku-prim-write-string ( str obj -- str )
	baku-io-stream !
	baku-io-str !
	baku-io-stream @ baku-stream? 0= if baku-eval-type throw then
	baku-io-str @ baku-string? 0= if baku-eval-type throw then
	baku-io-stream @ baku-stream-mode
	dup baku-stream-output = if
		drop
		baku-io-str @ baku-string-addr
		baku-io-str @ baku-string-length
		type baku-io-str @ exit
	then
	baku-stream-file = if
		baku-io-str @ baku-string-addr
		baku-io-str @ baku-string-length
		baku-io-stream @ baku-stream-handle
		write-file
		0<> if baku-file-error throw then
		baku-io-str @ exit
	then
	baku-invalid-argument throw ;

\ ---------------------------------------------------------------------------
\ Time
\
\ GET-TIME takes the symbol RUN or UNIX.  UNIX is epoch seconds, converted from
\ the Facility word TIME&DATE by a Gregorian civil-date count; RUN is the same
\ clock clamped so it never decreases, minus the reading taken at the first RUN
\ call.  Both therefore share one source (TIME&DATE) instead of two mappings.
\ The clamp matters because TIME&DATE reads the wall clock, which can step
\ backwards; RUN is used for elapsed measurements where a negative delta would
\ be wrong.  Second resolution is the resolution TIME&DATE offers.
\
\ TIME&DATE leaves ( sec min hour day month year ), local time.  The epoch is
\ therefore local-time epoch seconds, not UTC; the kernel only uses UNIX to seed
\ its random generator, so a timezone offset is harmless and documented here.
\ ---------------------------------------------------------------------------

create baku-time-month-days
	0 , 31 , 59 , 90 , 120 , 151 , 181 , 212 , 243 , 273 , 304 , 334 ,

variable baku-time-sec
variable baku-time-min
variable baku-time-hour
variable baku-time-day
variable baku-time-month
variable baku-time-year
variable baku-time-base
variable baku-time-last
variable baku-time-ready

: baku-time-leap? ( year -- flag )
	dup 4 mod 0= over 100 mod 0<> and swap 400 mod 0= or ;

\ Days from year 1 to the first day of YEAR, by the Gregorian leap rule.
: baku-time-days-before-year ( year -- days )
	1-                                  ( y1 )
	dup 365 *                           ( y1 n )
	over 4 / +                          ( y1 n )
	over 100 / -                        ( y1 n )
	over 400 / +                        ( y1 n )
	nip ;

\ Days from the first of the current month to the current day.
: baku-time-days-into-year ( -- days )
	baku-time-month @ 1- cells baku-time-month-days + @
	baku-time-month @ 2 > if
		baku-time-year @ baku-time-leap? if 1+ then
	then
	baku-time-day @ 1- + ;

: baku-time-epoch ( -- n )
	time&date
	baku-time-year ! baku-time-month ! baku-time-day !
	baku-time-hour ! baku-time-min ! baku-time-sec !
	baku-time-year @ baku-time-days-before-year
	1970 baku-time-days-before-year -
	baku-time-days-into-year + 86400 *
	baku-time-hour @ 3600 * +
	baku-time-min @ 60 * +
	baku-time-sec @ + ;

: baku-time-run ( -- n )
	baku-time-epoch
	baku-time-ready @ 0= if
		dup baku-time-base !
		1 baku-time-ready !
	then
	baku-time-last @ max
	dup baku-time-last !
	baku-time-base @ - ;

: baku-prim-get-time ( sym -- n )
	dup baku-symbol? 0= if drop baku-eval-type throw then
	dup s" unix" baku-symbol-text= if
		drop baku-time-epoch s>d baku-fixnum-of-d exit
	then
	dup s" run" baku-symbol-text= 0= if
		drop baku-invalid-argument throw
	then
	drop baku-time-run baku-fixnum ;

\ ---------------------------------------------------------------------------
\ Registration
\ ---------------------------------------------------------------------------

: baku-primitives-init ( -- )
	['] baku-prim-add 2 s" +" baku-intern baku-defprim
	['] baku-prim-sub 2 s" -" baku-intern baku-defprim
	['] baku-prim-mul 2 s" *" baku-intern baku-defprim
	['] baku-prim-div 2 s" /" baku-intern baku-defprim
	['] baku-prim-gt 2 s" >" baku-intern baku-defprim
	['] baku-prim-lt 2 s" <" baku-intern baku-defprim
	['] baku-prim-ge 2 s" >=" baku-intern baku-defprim
	['] baku-prim-le 2 s" <=" baku-intern baku-defprim
	['] baku-prim-eq 2 s" =" baku-intern baku-defprim
	['] baku-prim-number? 1 s" number?" baku-intern baku-defprim
	['] baku-prim-string? 1 s" string?" baku-intern baku-defprim
	['] baku-prim-absvector? 1 s" absvector?" baku-intern baku-defprim
	['] baku-prim-absvector 1 s" absvector" baku-intern baku-defprim
	['] baku-prim-address-> 3 s" address->" baku-intern baku-defprim
	['] baku-prim-<-address 2 s" <-address" baku-intern baku-defprim
	['] baku-prim-cons 2 s" cons" baku-intern baku-defprim
	['] baku-prim-cons? 1 s" cons?" baku-intern baku-defprim
	['] baku-prim-hd 1 s" hd" baku-intern baku-defprim
	['] baku-prim-tl 1 s" tl" baku-intern baku-defprim
	['] baku-prim-str 1 s" str" baku-intern baku-defprim
	['] baku-prim-pos 2 s" pos" baku-intern baku-defprim
	['] baku-prim-tlstr 1 s" tlstr" baku-intern baku-defprim
	['] baku-prim-cn 2 s" cn" baku-intern baku-defprim
	['] baku-prim-string->n 1 s" string->n" baku-intern baku-defprim
	['] baku-prim-n->string 1 s" n->string" baku-intern baku-defprim
	['] baku-prim-intern 1 s" intern" baku-intern baku-defprim
	['] baku-prim-simple-error 1 s" simple-error" baku-intern baku-defprim
	['] baku-prim-error-to-string 1 s" error-to-string" baku-intern baku-defprim
	['] baku-prim-open 2 s" open" baku-intern baku-defprim
	['] baku-prim-close 1 s" close" baku-intern baku-defprim
	['] baku-prim-read-byte 1 s" read-byte" baku-intern baku-defprim
	['] baku-prim-write-byte 2 s" write-byte" baku-intern baku-defprim
	['] baku-prim-read-unit-string 1 s" read-unit-string" baku-intern baku-defprim
	['] baku-prim-write-string 2 s" write-string" baku-intern baku-defprim
	['] baku-prim-char-stream? 1 s" char-stream?" baku-intern baku-defprim
	['] baku-prim-get-time 1 s" get-time" baku-intern baku-defprim ;

baku-primitives-init
