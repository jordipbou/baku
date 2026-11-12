\ Baku dictionary arena tests.
\
\ An arena is a lifetime scope over the dictionary: creation defines an ANS
\ MARKER at the current HERE and selects a bump heap that grows with the
\ dictionary; release executes the marker and pops the region.  These tests
\ prove that objects allocated since the mark are reclaimed, that older objects
\ are untouched, that arenas nest, and that the allocator guard uses the arena's
\ remaining space rather than the whole dictionary.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

\ Catch a failure of BAKU-ALLOC and return its THROW code.  CATCH restores the
\ protected word's arguments, so the payload and type must be dropped.
: alloc-code ( payload type -- code )
	['] baku-alloc catch >r 2drop r> ;

variable arena-base
variable arena-cons
variable arena-string
variable arena-vector
variable arena-inner
variable arena-pre
variable arena-symbol
variable arena-before

\ A non-GC object allocated before any arena must survive every release.
1 baku-fixnum 2 baku-fixnum baku-cons arena-pre !

align here arena-base !

baku-arena-active? 0= 1 check
' baku-arena-remaining catch baku-no-arena = 2 check

baku-arena-create
baku-arena-active? 3 check
arena-base @ here < 4 check
baku-arena-remaining 0 > 5 check

1 baku-fixnum 2 baku-fixnum baku-cons arena-cons !
arena-cons @ baku-cons? 6 check
arena-cons @ baku-region-of baku-region-arena = 7 check
arena-cons @ baku-hd baku-fixnum-value 1 = 8 check
arena-cons @ baku-tl baku-fixnum-value 2 = 9 check
arena-cons @ aligned arena-cons @ = 10 check

s" hello" baku-string arena-string !
arena-string @ baku-string? 11 check
arena-string @ baku-region-of baku-region-arena = 12 check
arena-string @ baku-string-length 5 = 13 check
arena-string @ 0 baku-string@ 104 = 14 check
arena-string @ aligned arena-string @ = 15 check

3 baku-vector arena-vector !
arena-vector @ baku-vector? 16 check
arena-vector @ baku-vector-length 3 = 17 check
42 baku-fixnum arena-vector @ 0 baku-vector!
arena-vector @ 0 baku-vector@ baku-fixnum-value 42 = 18 check
arena-vector @ aligned arena-vector @ = 19 check

\ Symbols are permanent even when interning happens inside an arena.
s" arena-sym" baku-intern arena-symbol !
arena-symbol @ baku-region-of baku-region-nongc = 20 check

\ A nested arena may start where the outer one ends; freeing the inner one
\ leaves the outer objects alive.
baku-arena-create
baku-arena-active? 21 check
3 baku-fixnum 4 baku-fixnum baku-cons arena-inner !
arena-inner @ baku-region-of baku-region-arena = 22 check

baku-arena-free
baku-arena-active? 23 check
arena-inner @ baku-object? 0= 24 check
arena-cons @ baku-object? 25 check
arena-cons @ baku-hd baku-fixnum-value 1 = 26 check
arena-string @ baku-string-length 5 = 27 check
arena-symbol @ baku-region-of baku-region-nongc = 28 check

\ The outer bump pointer resumes where the inner arena started.
5 baku-fixnum 6 baku-fixnum baku-cons arena-inner !
arena-inner @ baku-region-of baku-region-arena = 29 check
arena-inner @ baku-hd baku-fixnum-value 5 = 30 check

baku-arena-free
baku-arena-active? 0= 31 check
here arena-base @ = 32 check
arena-cons @ baku-object? 0= 33 check
arena-string @ baku-object? 0= 34 check
arena-vector @ baku-object? 0= 35 check
arena-inner @ baku-object? 0= 36 check
arena-pre @ baku-object? 37 check
arena-pre @ baku-hd baku-fixnum-value 1 = 38 check
arena-pre @ baku-tl baku-fixnum-value 2 = 39 check
arena-symbol @ baku-region-of baku-region-nongc = 40 check

\ Allocation after release goes back to the non-GC heap.
7 baku-fixnum 8 baku-fixnum baku-cons baku-region-of baku-region-nongc = 41 check

\ The allocator guard must use the arena's remaining space, not the whole
\ dictionary: a request of the remaining payload cannot fit its own header and
\ alignment.  A failed allocation leaves the arena unchanged and usable.
baku-arena-create
baku-arena-remaining arena-before !
baku-arena-remaining baku-type-string alloc-code baku-out-of-memory = 42 check
arena-before @ baku-arena-remaining = 43 check
9 baku-fixnum 10 baku-fixnum baku-cons arena-cons !
arena-cons @ baku-object? 44 check
arena-cons @ baku-region-of baku-region-arena = 45 check
baku-arena-free
here arena-base @ = 46 check

." BAKU-TEST-DONE" cr
