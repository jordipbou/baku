\ Baku portability file.
\
\ Four names used by the shipped sources are not ANS Forth 2012 words:
\ CELL, -ROT, <= and >=.  They are defined here with ANS-only fallbacks, so
\ the shipped tree uses only ANS Forth 2012 words plus Baku's own definitions.
\ This file must load before every other Baku layer.
\
\ A test may include this file once to seed the request cells and then include
\ the tree again.  The four fallbacks below stay unconditional: Sloth defines
\ them through its conditional ?: form, and the ANS definition must replace it.
\ Every request cell below is guarded, so a second inclusion keeps its value.

1 cells constant cell

: -rot ( a b c -- c a b ) rot rot ;
: <= ( a b -- flag ) > 0= ;
: >= ( a b -- flag ) < 0= ;

\ The permanent non-GC block is sized when VALUE.4TH loads.  Under the collector
\ it holds only interned symbols, not interpreter IR.  A measured boot interns
\ about 225 KiB of symbols, so 2 MiB leaves headroom; a caller that needs more
\ must set this cell before including the tree.
[DEFINED] baku-nongc-request [IF] [ELSE]
	variable baku-nongc-request
	2097152 baku-nongc-request !
[THEN]

\ The collector reads this cell when it is created, so a test or embedder can
\ size the heap without a second creation API.  BAKU-GC-CREATE allocates two
\ semispaces of this size, so the heap cost is twice the request.  The measured
\ boot's live set is about 5.9 MiB; 16 MiB leaves room for allocation-heavy use.
[DEFINED] baku-gc-semispace-request [IF] [ELSE]
	variable baku-gc-semispace-request
	16777216 baku-gc-semispace-request !
[THEN]
