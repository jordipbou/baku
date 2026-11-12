\ Baku portability file.
\
\ Four names used by the shipped sources are not ANS Forth 2012 words:
\ CELL, -ROT, <= and >=.  They are defined here with ANS-only fallbacks, so
\ the shipped tree uses only ANS Forth 2012 words plus Baku's own definitions.
\ This file must load before every other Baku layer.
\
\ A test may include this file once to seed BAKU-NONGC-REQUEST and then include
\ the tree again.  The four fallbacks below stay unconditional: Sloth defines
\ them through its conditional ?: form, and the ANS definition must replace it.
\ Only the request cell is guarded, so a second inclusion keeps its value.

1 cells constant cell

: -rot ( a b c -- c a b ) rot rot ;
: <= ( a b -- flag ) > 0= ;
: >= ( a b -- flag ) < 0= ;

\ The non-GC heap is sized when VALUE.4TH loads.  The default covers the symbol
\ table and constants; the boot test raises the request before including the
\ tree because the interpreter loader keeps one IR node per kernel definition.
[DEFINED] baku-nongc-request [IF] [ELSE]
	variable baku-nongc-request
	524288 baku-nongc-request !
[THEN]

\ The native backend lowers one top-level form at a time into a scratch block
\ and discards the IR after compiling it to dictionary code.  The default holds
\ the largest pinned kernel form with headroom; a native boot test may raise it
\ before including the tree.  The interpreter backend does not use this block:
\ it keeps IR as closure code in the non-GC heap.
[DEFINED] baku-ir-scratch-request [IF] [ELSE]
	variable baku-ir-scratch-request
	4194304 baku-ir-scratch-request !
[THEN]
