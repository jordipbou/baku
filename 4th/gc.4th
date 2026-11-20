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
\ stack with DEPTH and snapshots the cells into a host buffer, keeping its
\ return-stack use constant.  The return stack is not a root: the interpreter
\ keeps no GC reference on it when an allocation can run, so the adapter never
\ needs to reach it.  The adapter uses only ANS words and never fails activation.
\
\ Region detection stays exact: only the from-space is registered as a GC
\ region.  The to-space is not a live region, so a pointer to it is never
\ mistaken for a from-space object.  A copied from-space object's header is
\ overwritten with its to-space address; an original header always has a type
\ in its low byte (1..8), while a forwarding address is cell-aligned and has a
\ zero low byte.  That is the forwarding marker, including for zero-length
\ strings and errors.

-282 constant baku-gc-inactive
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

\ One bit per from-space cell marks an object start for the pre-collection
\ validation pass.  The bitmap is host memory outside every Baku region; it
\ holds no Shen value and is never scanned.
variable baku-gc-start
variable baku-gc-start-bytes

0 baku-gc-created? !
0 baku-gc-activated? !
0 baku-gc-collecting? !
0 baku-gc-collections !
-1 baku-gc-region !

\ The data-stack root adapter is a direct definition from Gc-Stack.4th; it is
\ included below, after BAKU-GC-COPY and before the first user.  There is no
\ runtime capability flag: the collector path is the only execution path.

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

\ Copy one from-space object and return its to-space address.  Non-GC and
\ immediate values are returned unchanged.  An already-forwarded object
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

\ The stack adapter uses BAKU-GC-COPY, so it loads here, before any collection
\ code that calls BAKU-GC-SCAN-STACKS is compiled.  The spelling follows the
\ same include convention as the rest of the tree.
[DEFINED] gforth
[IF]
	S" gc-stack.4th" INCLUDED
[ELSE]
	S" 4th/gc-stack.4th" INCLUDED
[THEN]

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
				\ holds an xt.
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
\ A table cell points at an entry (binding . next).  A non-GC entry came from
\ bootstrap and may still hold a GC value in its binding tail after a SET; walk
\ it by shape, without treating an arbitrary non-GC object (a symbol or
\ closure) as a cons.  A GC entry is copied, and the walk continues through the
\ copied chain: the ordinary Cheney scan traces a copied entry's next cell, but
\ BAKU-GC-COPY leaves a non-GC next entry unchanged, so a non-GC tail behind a
\ GC head would otherwise never reach its binding value.
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
		baku-gc-table-entry @ baku-pointer? 0= if exit then
		baku-gc-table-entry @ baku-region-of baku-region-gc = if
			\ A copied entry lives in the to-space, which is not a
			\ registered region, so read its next cell directly instead of
			\ through BAKU-TL.  The Cheney scan traces its binding; the walk
			\ continues only to reach a non-GC tail behind it.
			baku-gc-table-entry @ baku-gc-copy
			dup baku-gc-table-cell @ !
			dup baku-gc-table-entry !
			2 cells + baku-gc-table-cell !
			baku-gc-table-entry @ 2 cells + @ baku-gc-table-entry !
		else
			\ Non-GC entry: (binding . next).  The binding is a
			\ (name . value) cons; only the value can be a GC reference.
			baku-gc-table-entry @ baku-cons-tl-addr baku-gc-table-cell !
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
\ Pre-collection validation
\
\ A collection must either complete or leave the from-space and every root
\ unchanged.  The copy loop can only throw when the to-space fills, so before
\ any mutation the collector proves that cannot happen:
\
\   * every from-space object is a complete, packed object with a valid header;
\   * every structural field and every root is either non-GC or the header cell
\     of one of those objects.
\
\ The reachable set is then a subset of the objects the linear walk found, so
\ the bytes copied are at most the from-space used, which is at most one
\ semispace.  A corrupt heap or an interior pointer aborts before a header,
\ root or table cell is touched.  The bitmap marks object starts; the value
\ check rejects any GC pointer that is not one.
\ ---------------------------------------------------------------------------

variable baku-gc-check-addr
variable baku-gc-check-obj
variable baku-gc-check-h
variable baku-gc-check-type
variable baku-gc-check-payload
variable baku-gc-check-kind

\ The bitmap index uses the cell size from the target, so the same source works
\ on the deferred 32-bit adaptation.
: baku-gc-start-index ( addr -- byte-addr mask )
	baku-gc-from-start @ -
	1 cells /
	dup 8 / baku-gc-start @ +
	swap 7 and 1 swap lshift ;

: baku-gc-start-mark! ( addr -- )
	baku-gc-start-index
	over c@ or
	swap c! ;

: baku-gc-start-marked? ( addr -- flag )
	baku-gc-start-index
	swap c@ and 0<> ;

: baku-gc-check-value ( x -- )
	dup baku-pointer? 0= if drop exit then
	dup baku-region-of baku-region-gc <> if drop exit then
	baku-gc-start-marked? 0= if baku-invalid-object throw then ;

: baku-gc-check-field ( addr -- ) @ baku-gc-check-value ;

: baku-gc-check-object ( addr -- )
	baku-gc-check-obj !
	baku-gc-check-obj @ @ 255 and baku-gc-check-type !
	baku-gc-check-obj @ @ 8 rshift baku-round-cells baku-gc-check-payload !
	baku-gc-check-type @ baku-type-cons = if
		baku-gc-check-obj @ cell + baku-gc-check-field
		baku-gc-check-obj @ 2 cells + baku-gc-check-field
	else
		baku-gc-check-type @ baku-type-vector = if
			baku-gc-check-payload @ cell / 0 ?do
				baku-gc-check-obj @ i 1+ cells + baku-gc-check-field
			loop
		else
			baku-gc-check-type @ baku-type-closure = if
				baku-gc-check-obj @ 1 cells + @ baku-gc-check-kind !
				baku-gc-check-kind @ baku-closure-interpreted =
				baku-gc-check-kind @ baku-closure-partial = or if
					baku-gc-check-obj @ 3 cells + baku-gc-check-field
				then
				baku-gc-check-obj @ 4 cells + baku-gc-check-field
			then
		then
	then ;

: baku-gc-heap-check ( -- )
	baku-gc-from-here @ baku-gc-from-end @ u> if baku-invalid-object throw then
	baku-gc-from-here @ baku-gc-from-start @ u< if baku-invalid-object throw then
	baku-gc-start @ baku-gc-start-bytes @ 0 fill
	baku-gc-from-start @ baku-gc-check-addr !
	begin
		baku-gc-check-addr @ baku-gc-from-here @ u<
	while
		baku-gc-check-addr @ baku-gc-start-mark!
		baku-gc-check-addr @ @ baku-gc-check-h !
		baku-gc-check-h @ baku-gc-forward? if baku-invalid-object throw then
		baku-gc-check-h @ 255 and dup 1 >= swap 8 <= and 0= if
			baku-invalid-object throw
		then
		baku-gc-check-h @ baku-gc-header-total
		baku-gc-check-addr @ +
		dup baku-gc-from-here @ u> if baku-invalid-object throw then
		baku-gc-check-addr !
	repeat
	baku-gc-check-addr @ baku-gc-from-here @ <> if baku-invalid-object throw then ;

: baku-gc-check-objects ( -- )
	baku-gc-from-start @ baku-gc-check-addr !
	begin
		baku-gc-check-addr @ baku-gc-from-here @ u<
	while
		baku-gc-check-addr @ baku-gc-check-object
		baku-gc-check-addr @ @ baku-gc-header-total baku-gc-check-addr +!
	repeat ;

: baku-gc-check-range ( start end -- )
	begin
		2dup u<
	while
		over @ baku-gc-check-value
		swap cell+ swap
	repeat
	2drop ;

\ PICK is not constant-space on every target: Sloth implements it as a
\ recursive Forth word, so reading a deep data stack through PICK would grow
\ the return stack with the stack depth.  Snapshot the cells into the same host
\ buffer the copy adapter uses, then validate each snapshot cell.
variable baku-gc-check-count
variable baku-gc-check-stack-total

: baku-gc-check-stacks ( -- )
	depth dup baku-gc-check-stack-total ! baku-gc-check-count !
	baku-gc-check-stack-total @ 0= if exit then
	baku-gc-check-stack-total @ cells allocate throw baku-gc-ds-buf !
	begin baku-gc-check-count @ 0> while
		baku-gc-ds-buf @ baku-gc-check-count @ 1- cells + !
		-1 baku-gc-check-count +!
	repeat
	\ Put every cell back before validating, so a rejected value cannot leave
	\ the caller's roots half restored.
	baku-gc-check-stack-total @ baku-gc-check-count !
	begin baku-gc-check-count @ 0> while
		baku-gc-ds-buf @
			baku-gc-check-stack-total @ baku-gc-check-count @ - cells + @
		-1 baku-gc-check-count +!
	repeat
	baku-gc-check-stack-total @ baku-gc-check-count !
	begin baku-gc-check-count @ 0> while
		baku-gc-ds-buf @ baku-gc-check-count @ 1- cells + @
		baku-gc-check-value
		-1 baku-gc-check-count +!
	repeat
	baku-gc-ds-buf @ free throw ;

: baku-gc-check-roots ( -- )
	baku-gc-root-count @ 0 ?do
		baku-gc-roots i 2* cells + @
		baku-gc-roots i 2* cells + cell + @
		cells over + baku-gc-check-range
	loop ;

variable baku-gc-check-entry

: baku-gc-check-table-entry ( addr-of-cell -- )
	@ baku-gc-check-entry !
	begin baku-gc-check-entry @ 0<> while
		baku-gc-check-entry @ baku-pointer? 0= if exit then
		baku-gc-check-entry @ baku-region-of baku-region-gc = if
			baku-gc-check-entry @ baku-gc-check-value
			baku-gc-check-entry @ 2 cells + @ baku-gc-check-entry !
		else
			baku-gc-check-entry @ baku-hd baku-pointer? if
				baku-gc-check-entry @ baku-hd
				dup baku-region-of baku-region-gc = if
					baku-gc-check-value
				else
					drop
					baku-gc-check-entry @ baku-hd
					baku-cons-tl-addr @ baku-gc-check-value
				then
			then
			baku-gc-check-entry @ baku-tl baku-gc-check-entry !
		then
	repeat ;

: baku-gc-check-tables ( -- )
	baku-gc-table-count @ 0 ?do
		baku-gc-tables i 2* cells + @
		baku-gc-tables i 2* cells + cell + @
		0 ?do
			dup i cells + baku-gc-check-table-entry
		loop
		drop
	loop ;

: baku-gc-check ( -- )
	baku-gc-heap-check
	baku-gc-check-objects
	baku-gc-check-stacks
	baku-gc-check-roots
	baku-gc-check-tables ;

\ ---------------------------------------------------------------------------
\ Creation, activation and collection
\ ---------------------------------------------------------------------------

: baku-gc-active? ( -- flag )
	baku-gc-activated? @ ;

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
	baku-gc-semispace @ 1 cells / 7 + 8 /
	dup baku-gc-start-bytes ! allocate throw baku-gc-start !
	baku-gc-start @ baku-gc-start-bytes @ 0 fill
	baku-gc-from-start @
	baku-gc-from-here baku-region-gc baku-region+ baku-gc-region !
	1 baku-gc-created? ! ;

: baku-gc-activate ( -- )
	baku-gc-activated? @ if exit then
	baku-gc-created? @ 0= if baku-gc-unsupported throw then
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

\ The data stack is scanned first because it is the only root source that
\ allocates a host buffer.  If that allocation fails, no object or table root
\ has been mutated yet, so the collection can abort safely.  Root sources are
\ otherwise independent: all of them are copied before the Cheney scan.
: baku-gc-collect-real ( -- )
	baku-gc-check
	baku-gc-to-start @ baku-gc-to-here !
	baku-gc-scan-stacks
	baku-gc-scan-roots
	baku-gc-scan-tables
	baku-gc-to-start @ baku-gc-scan !
	begin baku-gc-scan @ baku-gc-to-here @ u< while
		baku-gc-scan-object
	repeat
	baku-gc-flip ;

: baku-gc-collect ( -- )
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
\ Value-layer roots
\ ---------------------------------------------------------------------------

baku-cat-a 1 baku-gc-root+
baku-cat-b 1 baku-gc-root+
baku-quote-src 1 baku-gc-root+
baku-slice-src 1 baku-gc-root+
baku-error-string-src 1 baku-gc-root+
baku-error-copy-src 1 baku-gc-root+
