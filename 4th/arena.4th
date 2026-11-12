\ Baku dictionary arenas.
\
\ An arena is a lifetime scope over the Forth dictionary, not a preallocated
\ block: creating one defines an ANS MARKER at the current dictionary point and
\ selects a bump heap that grows with HERE; freeing it executes that marker.
\ The marker removes its own definition and every arena object allocated after
\ it, so resuming the same code costs no collection latency.
\
\ The marker is created at run time by evaluating the MARKER definition.  A
\ statically named marker word can only be executed once (it removes itself), so
\ every arena needs its own freshly defined word; EVALUATE is the portable way
\ to define one without host-language help.  A fixed name is reused, so a nested
\ arena makes the target warn about a redefinition; the warning is harmless
\ because each arena keeps the execution token taken at its own creation.
\
\ Arenas are LIFO.  The region map is ordered by registration, so freeing the
\ youngest arena is a pop.  Reading an object after its arena is freed is a bug:
\ the bytes may still be in the dictionary, but the address no longer classifies
\ as an object because its region is gone.
\
\ The arena's region extent ends at its bump pointer, not at the dictionary
\ limit.  That lets a nested arena start where the outer one ends without
\ tripping the region-overlap check, and it means unallocated dictionary space
\ never classifies as a live object.  The allocator guard uses the separate
\ arena limit, which is the dictionary space remaining when the arena was
\ created.
\
\ Every arena allocation also advances HERE.  Without that step the next word
\ definition or nested MARKER would overwrite arena objects.  BAKU-ALLOC-SYNC is
\ the single hook that does it; it only acts while this arena's heap is selected,
\ so the reader scratch, IR scratch, non-GC heap and symbol interning keep their
\ existing behaviour.

8 constant baku-arena-max

variable baku-arena-depth
variable baku-arena-sync-here

create baku-arena-marks   baku-arena-max cells allot
create baku-arena-regions baku-arena-max cells allot
create baku-arena-heres   baku-arena-max cells allot
create baku-arena-limits  baku-arena-max cells allot
create baku-arena-prev-heres baku-arena-max cells allot
create baku-arena-prev-ends  baku-arena-max cells allot
create baku-arena-prev-syncs baku-arena-max cells allot

0 baku-arena-depth !
0 baku-arena-sync-here !

: baku-arena-active? ( -- flag ) baku-arena-depth @ 0<> ;

\ The arena's bump pointer doubles as the region's end cell: it always holds
\ the first unallocated address, so the registered extent grows with the arena.
: baku-arena-create ( -- )
	baku-arena-depth @ baku-arena-max >= if baku-arena-full throw then
	align
	baku-arena-depth @ >r
	baku-heap-here @ r@ cells baku-arena-prev-heres + !
	baku-heap-end @ r@ cells baku-arena-prev-ends + !
	baku-arena-sync-here @ r@ cells baku-arena-prev-syncs + !
	\ Define the marker at the dictionary point a release must return to.
	s" MARKER baku-arena-mark" evaluate
	s" ' baku-arena-mark" evaluate r@ cells baku-arena-marks + !
	align
	\ Objects start after the marker word, which the marker also reclaims.
	here r@ cells baku-arena-heres + !
	here unused + r@ cells baku-arena-limits + !
	here r@ cells baku-arena-heres + baku-region-arena baku-region+
	r@ cells baku-arena-regions + !
	r@ cells baku-arena-heres + r@ cells baku-arena-limits + baku-use-heap
	r@ cells baku-arena-heres + baku-arena-sync-here !
	r> 1+ baku-arena-depth !
;

: baku-arena-free ( -- )
	baku-arena-depth @ 0= if baku-no-arena throw then
	baku-arena-depth @ 1- >r
	\ Restore the previous selection before the marker rewinds the dictionary.
	r@ cells baku-arena-prev-heres + @
	r@ cells baku-arena-prev-ends + @ baku-use-heap
	r@ cells baku-arena-prev-syncs + @ baku-arena-sync-here !
	r@ cells baku-arena-marks + @ execute
	baku-region-drop
	r> baku-arena-depth !
;

: baku-arena-remaining ( -- bytes )
	baku-arena-depth @ 0= if baku-no-arena throw then
	baku-arena-depth @ 1- cells
	dup baku-arena-limits + @ swap baku-arena-heres + @ - ;

: baku-arena-alloc-sync ( -- )
	baku-arena-sync-here @ ?dup if
		baku-heap-here @ = if
			baku-heap-here @ @ here - allot
		then
	then ;

' baku-arena-alloc-sync is baku-alloc-sync
