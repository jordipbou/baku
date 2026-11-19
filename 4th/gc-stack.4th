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
\ The collector requires a well-formed heap: every root and table binding must
\ point at the header cell of a from-space object.  With that precondition the
\ copied live bytes are at most the from-space used, so a copy cannot overflow
\ the equal-sized to-space.  A copy throw therefore means the heap broke the
\ precondition, and a partially copied collection is not safe to resume.

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

: baku-gc-scan-stacks ( -- ) baku-gc-scan-data-stack ;
