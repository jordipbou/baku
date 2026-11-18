\ Boot through the collector with the shipped defaults.
\
\ This is the user path from 4th/start.4th: the permanent symbol area is the
\ default sized by 4th/portability.4th, the collector is created from the
\ default semispace request and activated before the first kernel form is read,
\ and both initialisers run with the tree-walking interpreter as the only
\ executor.  A forced collection after boot must preserve the boot globals, the
\ installed kernel functions and a live reader form.
\
\ The boot runs on gforth; Sloth's Debug execution is too slow for the fast gate.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

variable gb-old
variable gb-form

\ ---------------------------------------------------------------------------
\ Create and activate the collector before the first kernel read.
\ ---------------------------------------------------------------------------

baku-gc-create
baku-gc-created? @ 1 check
baku-gc-semispace @ baku-gc-semispace-request @ = 2 check
baku-gc-active? 0= 3 check
baku-gc-activate
baku-gc-active? 4 check

\ ---------------------------------------------------------------------------
\ Boot: the loader, the host globals and both initialisers.
\ ---------------------------------------------------------------------------

baku-boot-load-kernel

baku-boot-files @ 23 5 check-num
baku-boot-forms @ 1124 6 check-num
baku-boot-defuns @ 1118 7 check-num

baku-boot-globals
baku-boot-initialise

\ The shipped reservation is two semispaces plus the permanent symbol area.
\ It must stay at or below about 40 MiB.
2 baku-gc-semispace @ * baku-nongc-size + 41943040 <= 8 check

\ The symbol area holds every interned symbol and still has free space.
baku-nongc-free 0> 9 check
baku-nongc-used baku-nongc-size < 10 check

\ The permanent block holds symbols, not code or IR: an interned symbol lands
\ there, a booted defun is an interpreted closure whose code slot is a GC
\ object.
s" gc-boot-symbol" baku-intern baku-region-of baku-region-nongc = 11 check

: gb-fn ( c-addr u -- closure )
	baku-intern baku-fn-lookup 0= if
		." BAKU-TEST-FAIL: missing kernel function after boot" cr abort
	then ;

: gb-language-ok? ( -- flag )
	s" *language*" baku-intern baku-global-lookup if
		s" Shen" baku-intern =
	else
		false
	then ;

: gb-read-live ( -- form )
	s" (1 2 3)" baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused the live form" cr abort
	then ;

s" factorial" gb-fn
dup baku-closure-kind baku-closure-interpreted = 12 check
baku-closure-code baku-region-of baku-region-gc = 13 check

\ ---------------------------------------------------------------------------
\ A live reader form lives in the reader scratch region, distinct from the
\ permanent block and the collector's from-space.  Only three region kinds
\ exist, so excluding both proves the form is in scratch.
\ ---------------------------------------------------------------------------

gb-read-live gb-form !
gb-form @ baku-cons? 14 check
gb-form @ baku-region-of baku-region-nongc <> 15 check
gb-form @ baku-region-of baku-region-gc <> 16 check

baku-gc-collect

gb-form @ baku-cons? 17 check
gb-form @ baku-hd baku-fixnum-value 1 = 18 check
gb-form @ baku-tl baku-hd baku-fixnum-value 2 = 19 check

gb-language-ok? 20 check

s" shen.initialise" baku-intern baku-fn-lookup nip 21 check

\ ---------------------------------------------------------------------------
\ Allocation-heavy use after boot must collect and still leave free space; the
\ boot state must survive the collections.
\ ---------------------------------------------------------------------------

: gb-cons-loop ( n -- )
	0 ?do baku-nil baku-nil baku-cons drop loop ;

baku-gc-collections @ gb-old !
1000000 gb-cons-loop
baku-gc-collections @ gb-old @ > 22 check
baku-gc-free? 0> 23 check

baku-gc-collect

gb-language-ok? 24 check
s" factorial" baku-intern baku-fn-lookup nip 25 check
gb-form @ baku-cons? 26 check
gb-form @ baku-tl baku-tl baku-hd baku-fixnum-value 3 = 27 check

." BAKU-TEST-DONE" cr
