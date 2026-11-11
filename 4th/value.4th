\ Baku value representation.
\
\ Every Shen value is one cell.  A value is classified without a heap lookup:
\
\   odd                         fixnum, value = (cell - 1) / 2
\   low three bits zero         pointer candidate, region decided by address
\   low three bits 010          immediate (empty list, true, false)
\
\ A pointer is a heap object only when its address lies in a registered region.
\ The region is never stored in the value or in the object header: only the
\ address range decides it.
\
\ Every heap object begins with a uniform header:
\
\   header = payload-bytes * 256 + object-type
\
\ so a collector can identify and size an object without a side table.  Payload
\ bytes exclude the header; the allocator keeps that logical size so strings keep
\ their exact length, and rounds only the advance.  Use BAKU-OBJECT-TOTAL when
\ walking the heap.

\ Object types.  The closure, stream and error kinds are reserved here; their
\ payload layouts belong to the layers that own them (M4 for closures/code,
\ M5 for streams and errors).
1 constant baku-type-cons
2 constant baku-type-string
3 constant baku-type-symbol
4 constant baku-type-vector
5 constant baku-type-closure
6 constant baku-type-stream
7 constant baku-type-error
8 constant baku-type-float

\ Reserved immediate values.  All have low three bits 010 so a future immediate
\ can be added without colliding with fixnums or pointers.  They are not Forth
\ flags and they are not null pointers.
2 constant baku-nil
10 constant baku-false
18 constant baku-true

\ Private THROW codes.  Standard Forth codes are negative; these start below
\ them.  Every error here is catchable by the caller.
-256 constant baku-out-of-memory
-257 constant baku-region-full
-258 constant baku-region-overlap
-259 constant baku-invalid-object
-260 constant baku-cons-expected
-261 constant baku-string-expected
-262 constant baku-vector-expected
-263 constant baku-symbol-expected
-264 constant baku-float-expected
-265 constant baku-string-bounds-error
-266 constant baku-vector-bounds-error
-267 constant baku-invalid-argument

\ Floating point is required for the kernel's float literals.  Probe it here so
\ a target without the wordset fails loudly at load time instead of producing a
\ wrong value later.
[DEFINED] DF@ [DEFINED] DF! and 0= [IF]
	." Baku requires the Floating wordset (DF@ DF!)" cr
	abort
[THEN]

\ ---------------------------------------------------------------------------
\ Region map
\ ---------------------------------------------------------------------------

1 constant baku-region-nongc
2 constant baku-region-arena
3 constant baku-region-gc

16 constant baku-region-max

create baku-region-starts baku-region-max cells allot
create baku-region-ends   baku-region-max cells allot
create baku-region-kinds  baku-region-max cells allot
variable baku-region-count

variable baku-new-start
variable baku-new-end
variable baku-new-kind

: baku-region-init ( -- )
	0 baku-region-count ! ;

\ Register [ start, end ) where END is the address of a cell holding the current
\ end, so a growing bump region updates its own extent.  Regions may be empty at
\ registration time but must never overlap once they grow.
: baku-region+ ( start end-addr kind -- index )
	baku-new-kind ! baku-new-end ! baku-new-start !
	baku-region-count @ baku-region-max >= if baku-region-full throw then
	baku-region-count @ 0 ?do
		baku-new-start @ baku-region-ends i cells + @ @ u<
		baku-region-starts i cells + @ baku-new-end @ @ u< and
		if baku-region-overlap throw then
	loop
	baku-region-count @ >r
	baku-new-kind @ baku-region-kinds r@ cells + !
	baku-new-end @ baku-region-ends r@ cells + !
	baku-new-start @ baku-region-starts r@ cells + !
	r@ 1+ baku-region-count !
	r> ;

: baku-region-of ( addr -- kind )
	baku-region-count @ 0 ?do
		dup baku-region-starts i cells + @ u< if
			\ addr is below this region; try the next one
		else
			dup baku-region-ends i cells + @ @ u< if
				drop baku-region-kinds i cells + @
				unloop exit
			then
		then
	loop
	drop 0 ;

\ ---------------------------------------------------------------------------
\ Tags, immediates and object classification
\ ---------------------------------------------------------------------------

: baku-fixnum ( n -- x ) 2* 1+ ;
: baku-fixnum? ( x -- flag ) 1 and 0<> ;
: baku-fixnum-value ( x -- n ) 1- 2/ ;

: baku-immediate? ( x -- flag ) 7 and 2 = ;

: baku-pointer? ( x -- flag )
	dup 1 and 0= swap 7 and 0= and ;

: baku-object? ( x -- flag )
	dup baku-pointer? if baku-region-of 0<> else drop false then ;

: baku-assert-object ( obj code -- obj )
	over baku-object? 0= if nip throw then drop ;

: baku-object-type ( obj -- type )
	baku-invalid-object baku-assert-object @ 255 and ;

: baku-object-size ( obj -- payload-bytes )
	baku-invalid-object baku-assert-object @ 8 rshift ;

variable baku-assert-code

: baku-assert-type ( obj type code -- obj )
	baku-assert-code !
	over baku-object? 0= if baku-assert-code @ throw then
	over baku-object-type over <> if baku-assert-code @ throw then
	drop ;

\ ---------------------------------------------------------------------------
\ Non-GC heap and the selected bump heap
\ ---------------------------------------------------------------------------
\
\ The non-GC heap is permanent: symbols and constants live there for the whole
\ process.  The reader needs a second, temporary bump heap for the parse tree of
\ one top-level form; BAKU-ALLOC always uses the currently selected heap, so
\ every constructor (cons, string, vector, float) follows the selection without
\ a second implementation.  Interning a symbol explicitly binds the non-GC heap
\ because symbols outlive the form that introduced them.
\
\ 512 KiB holds the full distinct-symbol set of the pinned kernel (measured at
\ about 232 KiB) with headroom for constants.  The reader scratch block lives in
\ the reader layer; the heap selector below is what makes it usable.

524288 constant baku-nongc-size

align create baku-nongc-block baku-nongc-size allot align

variable baku-nongc-here
variable baku-nongc-end

\ Addresses of the selected heap's HERE and END variables.
variable baku-heap-here
variable baku-heap-end

: baku-use-heap ( here-addr end-addr -- )
	baku-heap-end ! baku-heap-here ! ;

: baku-use-nongc ( -- )
	baku-nongc-here baku-nongc-end baku-use-heap ;

: baku-heap-save ( -- here-addr end-addr )
	baku-heap-here @ baku-heap-end @ ;

: baku-heap-restore ( here-addr end-addr -- )
	baku-use-heap ;

: baku-nongc-init ( -- )
	baku-nongc-block baku-nongc-here !
	baku-nongc-block baku-nongc-size + baku-nongc-end !
	baku-nongc-block baku-nongc-here baku-region-nongc baku-region+ drop
	baku-use-nongc ;

: baku-nongc-used ( -- bytes ) baku-nongc-here @ baku-nongc-block - ;
: baku-nongc-free ( -- bytes ) baku-nongc-end @ baku-nongc-here @ - ;

: baku-round-cells ( bytes -- bytes' )
	cell 1- + cell / cell * ;

\ Allocate PAYLOAD-BYTES after a header.  The heap pointer advances only when
\ the request fits, so an out-of-memory THROW leaves the heap usable.
variable baku-alloc-payload
variable baku-alloc-type

: baku-alloc ( payload-bytes type -- obj )
	baku-alloc-type ! baku-alloc-payload !
	baku-alloc-payload @ baku-round-cells cell +   ( total )
	baku-heap-here @ @                             ( total old )
	2dup + baku-heap-end @ @ u> if
		2drop baku-out-of-memory throw
	then
	( total old )
	dup >r                                         ( total old | R: old )
	over + baku-heap-here @ !                      ( total )
	drop
	baku-alloc-payload @ 8 lshift baku-alloc-type @ or ( header )
	r@ !                                           ( -- | R: old )
	r> ;                                           ( -- obj )

: baku-object-total ( obj -- bytes )
	baku-object-size baku-round-cells cell + ;

\ Rewrite an object's logical payload size.  A builder allocates capacity first
\ and records the exact length here; object-total still rounds for a collector.
: baku-object-size! ( payload-bytes obj -- )
	baku-invalid-object baku-assert-object
	dup @ 255 and rot 8 lshift or swap ! ;

\ ---------------------------------------------------------------------------
\ Cons
\ ---------------------------------------------------------------------------

: baku-cons ( hd tl -- obj )
	2 cells baku-type-cons baku-alloc
	dup >r 2 cells + !         ( hd | R: obj )
	r@ cell + !                ( -- )
	r> ;

: baku-cons? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-cons = else drop false then ;

: baku-hd ( obj -- hd )
	baku-type-cons baku-cons-expected baku-assert-type cell + @ ;

: baku-tl ( obj -- tl )
	baku-type-cons baku-cons-expected baku-assert-type 2 cells + @ ;

: baku-set-hd ( value cons -- )
	baku-type-cons baku-cons-expected baku-assert-type cell + ! ;

: baku-set-tl ( value cons -- )
	baku-type-cons baku-cons-expected baku-assert-type 2 cells + ! ;

\ ---------------------------------------------------------------------------
\ Strings: a byte-counted payload, no terminator
\ ---------------------------------------------------------------------------

variable baku-string-src
variable baku-string-len

: baku-string ( c-addr u -- obj )
	dup 0 < if baku-invalid-argument throw then
	baku-string-len ! baku-string-src !
	baku-string-len @ baku-type-string baku-alloc
	>r
	baku-string-src @ r@ cell + baku-string-len @ cmove
	r> ;

: baku-string? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-string = else drop false then ;

: baku-string-addr ( obj -- c-addr )
	baku-type-string baku-string-expected baku-assert-type cell + ;

: baku-string-length ( obj -- u )
	baku-type-string baku-string-expected baku-assert-type baku-object-size ;

: baku-string-bounds ( obj i -- )
	drop drop baku-string-bounds-error throw ;

: baku-string@ ( obj i -- byte )
	dup 0 < if baku-string-bounds then
	over baku-string-length                 ( obj i len )
	2dup < if drop                          ( obj i )
		over cell + + c@ nip
	else
		drop baku-string-bounds
	then ;

\ ---------------------------------------------------------------------------
\ Vectors: a cell-counted payload.  Elements start zeroed so an uninitialised
\ absvector has a deterministic payload.
\ ---------------------------------------------------------------------------

: baku-vector ( n -- obj )
	dup 0 < if baku-invalid-argument throw then
	dup >r
	cells baku-type-vector baku-alloc
	dup cell + r@ cells 0 fill
	r> drop ;

: baku-vector? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-vector = else drop false then ;

: baku-vector-length ( obj -- n )
	baku-type-vector baku-vector-expected baku-assert-type
	baku-object-size cell / ;

: baku-vector-bounds ( obj i -- )
	drop drop baku-vector-bounds-error throw ;

: baku-vector-addr ( obj i -- addr )
	dup 0 < if baku-vector-bounds then
	over baku-vector-length                 ( obj i len )
	2dup < if drop                          ( obj i )
		cells over cell + + nip
	else
		drop baku-vector-bounds
	then ;

: baku-vector@ ( obj i -- value ) baku-vector-addr @ ;
: baku-vector! ( value obj i -- ) baku-vector-addr ! ;

\ ---------------------------------------------------------------------------
\ Symbols: permanent, case-sensitive interning into a non-GC table
\ ---------------------------------------------------------------------------

1024 constant baku-symbol-buckets-count

create baku-symbol-buckets baku-symbol-buckets-count cells allot

variable baku-match-addr
variable baku-match-len
variable baku-intern-addr
variable baku-intern-len
variable baku-new-sym
variable baku-new-bucket

: baku-symbol-reset ( -- )
	baku-symbol-buckets baku-symbol-buckets-count 0 ?do
		0 over ! cell+
	loop drop ;

: baku-nongc-reset ( -- )
	baku-nongc-block baku-nongc-here !
	baku-symbol-reset ;

: baku-bytes= ( a1 a2 u -- flag )
	0 ?do
		over c@ over c@ <> if 2drop unloop false exit then
		swap char+ swap char+
	loop
	2drop true ;

\ Small polynomial rolling hash.  The mask is tied to the bucket count so a
\ change to the table size cannot read outside the table.
: baku-hash ( c-addr u -- h )
	0 rot rot 0 ?do
		dup c@ rot 31 * + baku-symbol-buckets-count 1- and swap char+
	loop drop ;

: baku-symbol-name-addr ( sym -- c-addr )
	baku-type-symbol baku-symbol-expected baku-assert-type 2 cells + ;

: baku-symbol-name-len ( sym -- u )
	baku-type-symbol baku-symbol-expected baku-assert-type
	baku-object-size cell - ;

: baku-symbol-matches? ( sym c-addr u -- flag )
	baku-match-len ! baku-match-addr !
	dup baku-symbol-name-len baku-match-len @ <> if drop false exit then
	baku-symbol-name-addr baku-match-addr @ baku-match-len @ baku-bytes= ;

: baku-intern ( c-addr u -- sym )
	baku-intern-len ! baku-intern-addr !
	baku-intern-addr @ baku-intern-len @ baku-hash       ( h )
	baku-symbol-buckets over cells +                     ( h bucket )
	dup @                                                ( h bucket head )
	begin dup while
		dup                                              ( h bucket head head )
		baku-intern-addr @ baku-intern-len @             ( ... head c-addr u )
		baku-symbol-matches?                             ( h bucket head flag )
		if nip nip exit then                             ( h bucket head )
		cell + @                                         ( h bucket next )
	repeat
	drop                                                 ( h bucket )
	baku-new-bucket ! drop                               ( -- )
	\ Symbols are permanent: bind the non-GC heap even when the reader is
	\ building a temporary form in scratch.
	baku-heap-here @ >r baku-heap-end @ >r
	baku-use-nongc
	baku-intern-len @ cell + baku-type-symbol baku-alloc ( sym )
	dup baku-new-sym !
	baku-new-bucket @ @ over cell + !                    ( sym )
	baku-intern-addr @ baku-new-sym @ 2 cells + baku-intern-len @ cmove
	baku-new-sym @ baku-new-bucket @ !
	r> r> swap baku-heap-restore ;

: baku-symbol? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-symbol = else drop false then ;

\ ---------------------------------------------------------------------------
\ Boxed floating-point numbers
\ ---------------------------------------------------------------------------

: baku-float ( F: r -- ; -- obj )
	8 baku-type-float baku-alloc
	dup >r cell + df!
	r> ;

: baku-float? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-float = else drop false then ;

: baku-float@ ( obj -- ; F: -- r )
	baku-type-float baku-float-expected baku-assert-type cell + df@ ;

\ ---------------------------------------------------------------------------
\ Initialisation
\ ---------------------------------------------------------------------------

: baku-value-init ( -- )
	baku-region-init
	baku-symbol-reset
	baku-nongc-init ;

baku-value-init
