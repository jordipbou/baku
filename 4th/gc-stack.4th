\ Data-stack root adapter for the Cheney collector.
\
\ The collector roots the Forth data stack.  ANS Forth 2012 exposes no stack
\ pointer, so the adapter walks the live data stack with DEPTH.  It snapshots
\ the cells into a host buffer sized for this one collection, then copies each
\ snapshot back through BAKU-GC-COPY and restores the original order.
\
\ The return stack is not used to hold the walk.  Moving every live data-stack
\ cell through the return stack grows its use with the data-stack depth, and on
\ a target with fixed stack sizes a deep but valid data stack overflows it
\ during the collection.  That is a valid-heap route into the unsafe unwind: the
\ collector has already moved roots and tables, so it cannot resume.  The host
\ buffer keeps the adapter's return-stack use constant.
\
\ The loops use BEGIN ... WHILE ... REPEAT and a dictionary counter, not
\ DO ... LOOP: this adapter must not depend on the host's loop implementation
\ while it is moving data-stack cells.
\
\ The return stack is not scanned.  The interpreter keeps no GC reference on the
\ return stack when an allocation can run: 4th/eval.4th keeps interpreter state
\ on the data stack or in registered roots, and the remaining >R uses hold a
\ fixnum, a symbol or a dictionary address.  A collection therefore never has a
\ return-stack root to update.
\
\ The collector validates the heap layout and every root before it mutates
\ anything (see the pre-collection validation section in Gc.4th).  That pass
\ proves the reachable bytes fit the equal-sized to-space, so BAKU-GC-COPY does
\ not reach its to-space limit and a collection either completes or aborts
\ before the first header or root is touched.

variable baku-gc-ds-buf
variable baku-gc-ds-total
variable baku-gc-ds-count

\ Write each live cell to the snapshot buffer from the top down, then push the
\ copied cells back in their original order.  The buffer is a host allocation,
\ not a registered Baku region: it holds raw cells only while this word runs and
\ is freed before the Cheney scan starts.
: baku-gc-scan-data-stack ( -- )
	depth dup baku-gc-ds-total ! baku-gc-ds-count !
	baku-gc-ds-total @ 0= if exit then
	baku-gc-ds-total @ cells allocate throw baku-gc-ds-buf !
	begin baku-gc-ds-count @ 0> while
		baku-gc-ds-buf @ baku-gc-ds-count @ 1- cells + !
		-1 baku-gc-ds-count +!
	repeat
	baku-gc-ds-total @ baku-gc-ds-count !
	begin baku-gc-ds-count @ 0> while
		baku-gc-ds-buf @ baku-gc-ds-total @ baku-gc-ds-count @ - cells + @
		baku-gc-copy
		-1 baku-gc-ds-count +!
	repeat
	baku-gc-ds-buf @ free throw ;

: baku-gc-scan-stacks ( -- ) baku-gc-scan-data-stack ;
