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
\   =          Shen equality: numeric across fixnum/float, byte equality for
\              strings, identity for interned symbols and immediates, element
\              equality for vectors, recursive equality for conses; a closure,
\              stream or error object compares false instead of raising
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

\ ---------------------------------------------------------------------------
\ Fixnum range
\
\ A fixnum n is represented as 2n+1, so the representable range is
\ [-2^(w-2), 2^(w-2)-1] for a w-bit cell.  The bounds are computed from CELL
\ instead of hard-coding 64 so the same source works on the deferred 32-bit
\ adaptation.
\ ---------------------------------------------------------------------------

: baku-fixnum-max-value ( -- n )
	1 s>d cell 8 * 2 - 0 ?do d2* loop 1 s>d d- d>s ;

: baku-fixnum-min-value ( -- n )
	1 s>d cell 8 * 2 - 0 ?do d2* loop dnegate d>s ;

baku-fixnum-max-value constant baku-fixnum-max
baku-fixnum-min-value constant baku-fixnum-min

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

\ Shen equality is total.  A closure, stream or error object has no Shen
\ equality structure, so two different such objects compare false rather than
\ raising; the kernel's writer relies on comparing an arbitrary value with
\ (fail) without trapping an error.
: baku-eq? ( a b -- flag )
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
\ Classifiers
\ ---------------------------------------------------------------------------

: baku-prim-number? ( x -- result )
	baku-number? if baku-true else baku-false then ;

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
	['] baku-prim-number? 1 s" number?" baku-intern baku-defprim ;

baku-primitives-init
