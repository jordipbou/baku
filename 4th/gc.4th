\ Baku Cheney copying collector.
\
\ The GC owns one heap block split into two semispaces.  When it is active the
\ selected Baku heap is the from-space, so every constructor allocates there
\ without a second allocator.  A collection copies every reachable object into
\ the to-space, then the two halves swap roles.  Object addresses change during
\ a move, so every reference must be reachable from a root that the collector
\ updates.
\
\ Roots are the only non-GC memory allowed to hold GC references:
\
\   * explicitly registered dictionary cells and ranges;
\   * the function and global variable tables, whose bucket chains may live in
\     non-GC memory and still hold GC binding values;
\   * the Forth data stack, through a portable stack-scan adapter.
\
\ ANS Forth 2012 exposes no stack pointer, so the adapter walks the live data
\ stack with DEPTH and >R/R>.  The return stack is not a root: GC mode keeps no
\ GC reference on it when an allocation can run, so the adapter never needs to
\ reach it.  The adapter uses only ANS words and never fails activation.
\
\ Region detection stays exact: only the from-space is registered as a GC
\ region.  The to-space is not a live region, so a pointer to it is never
\ mistaken for a from-space object.  A copied from-space object's header is
\ overwritten with its to-space address; an original header always has a type
\ in its low byte (1..8), while a forwarding address is cell-aligned and has a
\ zero low byte.  That is the forwarding marker, including for zero-length
\ strings and errors.
\
\ Arenas may hold GC references, but the GC must not hold arena references and
\ must not move while an arena exists.  BAKU-GC-ACTIVE? is therefore false while
\ an arena is active, activation is refused, and a collection is refused.  The
\ arena layer binds BAKU-GC-ARENA-ACTIVE? after loading.

-282 constant baku-gc-inactive
-283 constant baku-gc-arena-active
-284 constant baku-gc-unsupported

variable baku-gc-created?
variable baku-gc-activated?
variable baku-gc-collecting?
variable baku-gc-collections
variable baku-gc-region
variable baku-gc-semispace

variable baku-gc-from-start
variable baku-gc-from-here
variable baku-gc-from-end
variable baku-gc-to-start
variable baku-gc-to-here
variable baku-gc-to-end

variable baku-gc-scan

variable baku-gc-tmp1
variable baku-gc-tmp2

0 baku-gc-created? !
0 baku-gc-activated? !
0 baku-gc-collecting? !
0 baku-gc-collections !
-1 baku-gc-region !

\ The arena layer binds this; before it loads there can be no arena.
defer baku-gc-arena-active?
: baku-gc-arena-active-none ( -- flag ) false ;
' baku-gc-arena-active-none is baku-gc-arena-active?

\ Target stack-root adapter.  The default is the documented unsupported case.
defer baku-gc-scan-stacks
: baku-gc-scan-stacks-none ( -- ) ;
' baku-gc-scan-stacks-none is baku-gc-scan-stacks

defer baku-gc-stack-scan?
: baku-gc-stack-scan-none ( -- flag ) false ;
' baku-gc-stack-scan-none is baku-gc-stack-scan?

\ ---------------------------------------------------------------------------
\ Copying and tracing
\ ---------------------------------------------------------------------------

variable baku-gc-copy-src
variable baku-gc-copy-h
variable baku-gc-copy-total
variable baku-gc-copy-new

: baku-gc-header-total ( header -- bytes )
	8 rshift baku-round-cells cell + ;

\ A forwarding address is stored in the old header's cell with the cell's sign
\ bit set.  A real header is payload-bytes*256+type and stays well below that
\ bit because a semispace is at most a few MiB, so the marker is unambiguous and
\ the address's low alignment bits are preserved.
1 cell 8 * 1- lshift constant baku-gc-forward-bit

: baku-gc-forward? ( header -- flag ) 0< ;
: baku-gc-forwarded ( header -- addr ) baku-gc-forward-bit invert and ;

\ Copy one from-space object and return its to-space address.  Non-GC, arena
\ and immediate values are returned unchanged.  An already-forwarded object
\ returns the address stored in its old header.
: baku-gc-copy ( x -- x' )
	dup baku-pointer? 0= if exit then
	dup baku-region-of baku-region-gc <> if exit then
	dup @ dup baku-gc-forward? if baku-gc-forwarded nip exit then
	dup 255 and dup 1 >= swap 8 <= and 0= if drop exit then
	dup baku-gc-copy-h !
	baku-gc-copy-h @ baku-gc-header-total baku-gc-copy-total !
	drop
	baku-gc-copy-src !
	baku-gc-to-here @ baku-gc-copy-new !
	baku-gc-copy-new @ baku-gc-copy-total @ +
	dup baku-gc-to-end @ u> if baku-out-of-memory throw then
	drop
	baku-gc-copy-src @ baku-gc-copy-new @ baku-gc-copy-total @ cmove
	baku-gc-copy-new @ baku-gc-forward-bit or baku-gc-copy-src @ !
	baku-gc-copy-new @ baku-gc-copy-total @ + baku-gc-to-here !
	baku-gc-copy-new @ ;


: baku-gc-root-cell ( addr -- )
	dup @ baku-gc-copy swap ! ;

variable baku-gc-scan-type
variable baku-gc-scan-payload
variable baku-gc-scan-kind

\ Trace one copied object at BAKU-GC-SCAN, then advance over it.
: baku-gc-scan-object ( -- )
	baku-gc-scan @ @ dup 255 and baku-gc-scan-type !
	8 rshift baku-round-cells baku-gc-scan-payload !
	baku-gc-scan-type @ baku-type-cons = if
		baku-gc-scan @ cell + baku-gc-root-cell
		baku-gc-scan @ 2 cells + baku-gc-root-cell
	else
		baku-gc-scan-type @ baku-type-vector = if
			baku-gc-scan-payload @ cell / 0 ?do
				baku-gc-scan @ i 1+ cells + baku-gc-root-cell
			loop
		else
			baku-gc-scan-type @ baku-type-closure = if
				\ The kind slot holds the raw constant, not a tagged fixnum.
				\ Only an interpreted or partial closure's code slot is a
				\ Baku reference (IR node or target closure); a primitive
				\ holds an xt and a native closure a dictionary address.
				baku-gc-scan @ 1 cells + @ baku-gc-scan-kind !
				baku-gc-scan-kind @ baku-closure-interpreted =
				baku-gc-scan-kind @ baku-closure-partial = or if
					baku-gc-scan @ 3 cells + baku-gc-root-cell
				then
				baku-gc-scan @ 4 cells + baku-gc-root-cell
			then
		then
	then
	baku-gc-scan @ baku-gc-scan-payload @ cell + + baku-gc-scan ! ;

\ ---------------------------------------------------------------------------
\ Root registry
\ ---------------------------------------------------------------------------

128 constant baku-gc-root-max

create baku-gc-roots baku-gc-root-max 2* cells allot
variable baku-gc-root-count
0 baku-gc-root-count !

\ A registered range is (address, cell count).  A variable is registered as one
\ cell; the function and global bucket arrays use the table registry instead,
\ because their non-GC chains need a shape-aware walk.  Registration clears the
\ cells to NIL: a newly created VARIABLE has no defined contents on every
\ target, and an old/arbitrary cell could otherwise look like a from-space
\ pointer during the first collection.
variable baku-gc-root-add-addr
variable baku-gc-root-add-cells

: baku-gc-root+ ( addr cells -- )
	baku-gc-root-count @ baku-gc-root-max >= if baku-region-full throw then
	baku-gc-root-add-cells ! baku-gc-root-add-addr !
	baku-gc-root-add-cells @ 0 ?do
		baku-nil baku-gc-root-add-addr @ i cells + !
	loop
	baku-gc-root-add-addr @ baku-gc-root-add-cells @
	baku-gc-root-count @ 2* cells baku-gc-roots + >r
	r@ cell + ! r> !
	1 baku-gc-root-count +! ;


: baku-gc-scan-range ( start end -- )
	begin
		2dup u<
	while
		over baku-gc-root-cell
		swap cell+ swap
	repeat
	2drop ;

: baku-gc-scan-roots ( -- )
	baku-gc-root-count @ 0 ?do
		baku-gc-roots i 2* cells + @
		baku-gc-roots i 2* cells + cell + @
		cells over + baku-gc-scan-range
	loop ;

\ ---------------------------------------------------------------------------
\ Table roots
\
\ A table cell points at an entry (binding . next).  A GC entry is copied and
\ then traced by the ordinary Cheney scan.  A non-GC entry came from bootstrap
\ and may still hold a GC value in its binding tail after a GC-mode SET; walk it
\ by shape, without treating an arbitrary non-GC object (a symbol or closure) as
\ a cons.
\ ---------------------------------------------------------------------------

16 constant baku-gc-table-max

create baku-gc-tables baku-gc-table-max 2* cells allot
variable baku-gc-table-count
0 baku-gc-table-count !

: baku-gc-table+ ( addr cells -- )
	baku-gc-table-count @ baku-gc-table-max >= if baku-region-full throw then
	baku-gc-table-count @ 2* cells baku-gc-tables + >r
	r@ cell + ! r> !
	1 baku-gc-table-count +! ;

variable baku-gc-table-cell
variable baku-gc-table-entry

: baku-gc-scan-table-entry ( addr-of-cell -- )
	dup baku-gc-table-cell !
	@ baku-gc-table-entry !
	begin baku-gc-table-entry @ 0<> while
		baku-gc-table-entry @ baku-pointer? if
			baku-gc-table-entry @ baku-region-of baku-region-gc = if
				baku-gc-table-entry @ baku-gc-copy
				baku-gc-table-cell @ !
				exit
			then
			\ Non-GC entry: (binding . next).  The binding is a
			\ (name . value) cons; only the value can be a GC reference.
			baku-gc-table-entry @ baku-hd baku-pointer? if
				baku-gc-table-entry @ baku-hd
				dup baku-region-of baku-region-gc = if
					baku-gc-copy
					baku-gc-table-entry @ baku-set-hd
				else
					drop
					baku-gc-table-entry @ baku-hd
					baku-cons-tl-addr baku-gc-root-cell
				then
			then
			baku-gc-table-entry @ baku-tl baku-gc-table-entry !
		else
			exit
		then
	repeat ;

: baku-gc-scan-tables ( -- )
	baku-gc-table-count @ 0 ?do
		baku-gc-tables i 2* cells + @
		baku-gc-tables i 2* cells + cell + @
		0 ?do
			dup i cells + baku-gc-scan-table-entry
		loop
		drop
	loop ;

\ ---------------------------------------------------------------------------
\ Creation, activation and collection
\ ---------------------------------------------------------------------------

: baku-gc-active? ( -- flag )
	baku-gc-activated? @ if
		baku-gc-arena-active? 0=
	else
		false
	then ;

\ The caller sizes the heap by setting BAKU-GC-SEMISPACE-REQUEST before creation;
\ the request is read here so tests and embedders share one creation API.  Two
\ semispaces of that size are allocated from the host heap.
: baku-gc-create ( -- )
	baku-gc-created? @ if baku-invalid-argument throw then
	baku-gc-semispace-request @
	dup 0 <= if baku-invalid-argument throw then
	dup baku-gc-semispace !
	allocate throw baku-gc-from-start !
	baku-gc-semispace @ allocate throw baku-gc-to-start !
	baku-gc-from-start @ baku-gc-from-here !
	baku-gc-from-start @ baku-gc-semispace @ + baku-gc-from-end !
	baku-gc-to-start @ baku-gc-to-here !
	baku-gc-to-start @ baku-gc-semispace @ + baku-gc-to-end !
	baku-gc-from-start @
	baku-gc-from-here baku-region-gc baku-region+ baku-gc-region !
	1 baku-gc-created? ! ;

: baku-gc-activate ( -- )
	baku-gc-arena-active? if baku-gc-arena-active throw then
	baku-gc-activated? @ if exit then
	baku-gc-created? @ 0= if baku-gc-unsupported throw then
	baku-gc-stack-scan? 0= if baku-gc-unsupported throw then
	baku-gc-from-here baku-gc-from-end baku-use-heap
	1 baku-gc-activated? ! ;

: baku-gc-flip ( -- )
	baku-gc-from-start @ baku-gc-tmp1 !
	baku-gc-from-end @ baku-gc-tmp2 !
	baku-gc-to-start @ baku-gc-from-start !
	baku-gc-to-end @ baku-gc-from-end !
	baku-gc-to-here @ baku-gc-from-here !
	baku-gc-tmp1 @ baku-gc-to-start !
	baku-gc-tmp2 @ baku-gc-to-end !
	baku-gc-to-start @ baku-gc-to-here !
	baku-gc-from-start @ baku-gc-from-here
	baku-region-gc baku-gc-region @ baku-region-update ;

: baku-gc-collect-real ( -- )
	baku-gc-to-start @ baku-gc-to-here !
	baku-gc-scan-roots
	baku-gc-scan-tables
	baku-gc-scan-stacks
	baku-gc-to-start @ baku-gc-scan !
	begin baku-gc-scan @ baku-gc-to-here @ u< while
		baku-gc-scan-object
	repeat
	baku-gc-flip ;

: baku-gc-collect ( -- )
	baku-gc-arena-active? if baku-gc-arena-active throw then
	baku-gc-active? 0= if baku-gc-inactive throw then
	baku-gc-collecting? @ if exit then
	1 baku-gc-collecting? !
	['] baku-gc-collect-real catch ?dup if
		0 baku-gc-collecting? !
		throw
	then
	1 baku-gc-collections +!
	0 baku-gc-collecting? ! ;

: baku-gc-free? ( -- bytes )
	baku-gc-from-end @ baku-gc-from-here @ - ;

: baku-gc-used? ( -- bytes )
	baku-gc-from-here @ baku-gc-from-start @ - ;

: baku-gc-alloc-full-real ( -- )
	baku-gc-collecting? @ if baku-out-of-memory throw then
	baku-gc-active? if
		baku-heap-here @ baku-gc-from-here = if
			baku-gc-collect
		else
			baku-out-of-memory throw
		then
	else
		baku-out-of-memory throw
	then ;

' baku-gc-alloc-full-real is baku-alloc-full

\ ---------------------------------------------------------------------------
\ Value-layer roots and the target stack adapter
\ ---------------------------------------------------------------------------

baku-cat-a 1 baku-gc-root+
baku-cat-b 1 baku-gc-root+
baku-quote-src 1 baku-gc-root+
baku-slice-src 1 baku-gc-root+
baku-error-string-src 1 baku-gc-root+
baku-error-copy-src 1 baku-gc-root+

\ The stack adapter binds BAKU-GC-SCAN-STACKS and BAKU-GC-STACK-SCAN?; the
\ spelling follows the same include convention as the rest of the tree.
[DEFINED] gforth
[IF]
	S" gc-stack.4th" INCLUDED
[ELSE]
	S" 4th/gc-stack.4th" INCLUDED
[THEN]
