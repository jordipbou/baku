\ Target stack-root adapter for the Cheney collector.
\
\ The memory rules root the Forth data and return stacks, but ANS Forth 2012
\ does not expose stack pointers.  This file is the one place a target word is
\ used: gforth provides SP0/RP0 (the stack bases) and SP@/RP@ (the current
\ pointers).  [DEFINED] gates the binding, so a target without them keeps the
\ default no-op adapter and BAKU-GC-ACTIVATE raises BAKU-GC-UNSUPPORTED instead
\ of running a collector that would miss a stack root.  The pinned Sloth exposes
\ neither word and therefore reports GC as unsupported.
\
\ The addresses are compared before scanning because a stack may grow up or
\ down.  Every cell in the live extent is offered to the root updater; a cell is
\ changed only when it is a pointer into the from-space, so return addresses,
\ loop control and immediates are left alone.

[DEFINED] sp0 [DEFINED] sp@ and [DEFINED] rp0 [DEFINED] rp@ and [IF]

: baku-gc-stack-range ( start end -- )
	2dup u> if swap then baku-gc-scan-range ;

: baku-gc-scan-stacks-real ( -- )
	sp0 @ sp@ baku-gc-stack-range
	rp0 @ rp@ baku-gc-stack-range ;

: baku-gc-stack-scan-real ( -- flag ) true ;

[ELSE]

: baku-gc-scan-stacks-real ( -- ) ;
: baku-gc-stack-scan-real ( -- flag ) false ;

[THEN]

' baku-gc-scan-stacks-real is baku-gc-scan-stacks
' baku-gc-stack-scan-real is baku-gc-stack-scan?
