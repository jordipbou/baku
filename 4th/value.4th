65536 constant baku-heap-size

1 constant baku-cons
2 constant baku-string
3 constant baku-vector
4 constant baku-symbol
5 constant baku-closure
6 constant baku-stream
7 constant baku-error

-256 constant baku-out-of-memory

: baku-fixnum ( n -- x ) 2* 1+ ;
: baku-fixnum? ( x -- f ) 1 and ;
: baku-fixnum-value ( x -- n ) 2/ ;

ALIGN CREATE baku-heap-area baku-heap-size ALLOT ALIGN

VARIABLE baku-heap-here
VARIABLE baku-heap-end

: baku-heap-reset ( -- )
	baku-heap-area baku-heap-here !
	baku-heap-area baku-heap-size + baku-heap-end ! ;

: baku-heap-used ( -- n ) baku-heap-here @ baku-heap-area - ;
: baku-heap-free ( -- n ) baku-heap-end @ baku-heap-here @ - ;

: baku-cell-round ( n -- n' )
	cell 1- + cell / cell * ;

: baku-alloc ( bytes type -- obj )
	swap baku-cell-round cell + ( type total )
	baku-heap-here @ ( type total old )
	2dup + ( type total old new )
	dup baku-heap-end @ u> if baku-out-of-memory throw then
	dup baku-heap-here ! ( type total old new )
	drop ( type total old )
	swap drop ( type old )
	swap over ! ( old ) ;

: baku-alloc-cells ( cells type -- obj )
	swap cells swap baku-alloc ;

: baku-in-heap? ( x -- f )
	dup dup aligned <> if drop false else
		dup baku-heap-area u< if drop false else
			baku-heap-here @ u<
		then
	then ;

: baku-object? ( x -- f )
	dup 1 and if drop false else baku-in-heap? then ;

: baku-object-type ( obj -- type ) @ ;

baku-heap-reset
