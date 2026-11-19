\ Data-stack root adapter for the Cheney collector.
\
\ The collector roots the Forth data stack.  ANS Forth 2012 exposes no stack
\ pointer, so this adapter walks the live data stack with DEPTH and moves each
\ cell through the return stack: >R and R> are the only operations needed to
\ reach and replace every live cell.  Pushing all cells and popping them back
\ reverses twice, so the stack order is preserved.
\
\ The return stack is not scanned.  The interpreter keeps no GC reference on the
\ return stack when an allocation can run: 4th/eval.4th keeps interpreter state
\ on the data stack or in registered roots, and the remaining >R uses hold a
\ fixnum, a symbol or a dictionary address.  A collection therefore never has a
\ return-stack root to update.
\
\ BEGIN ... WHILE ... REPEAT is used instead of DO ... LOOP: DO keeps its loop
\ control on the return stack, underneath the moved cells.
\
\ If BAKU-GC-COPY throws during the scan, the CATCH in BAKU-GC-COLLECT restores
\ the data-stack pointer to the catch point.  The slots already written hold
\ updated values and the untouched slots hold the originals; the heap has not
\ flipped, so both are valid.

variable baku-gc-ds-total
variable baku-gc-ds-count

: baku-gc-scan-data-stack ( -- )
	depth dup baku-gc-ds-total ! baku-gc-ds-count !
	begin baku-gc-ds-count @ 0> while
		>r -1 baku-gc-ds-count +!
	repeat
	baku-gc-ds-total @ baku-gc-ds-count !
	begin baku-gc-ds-count @ 0> while
		r> baku-gc-copy -1 baku-gc-ds-count +!
	repeat ;

: baku-gc-scan-stacks-real ( -- ) baku-gc-scan-data-stack ;
: baku-gc-stack-scan-real ( -- flag ) true ;

' baku-gc-scan-stacks-real is baku-gc-scan-stacks
' baku-gc-stack-scan-real is baku-gc-stack-scan?
