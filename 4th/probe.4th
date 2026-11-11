\ Baku startup probe for the required ANS Forth 2012 wordsets.
\
\ Baku declares the Facility, Memory-Allocation, Floating, File, Exception and
\ Double-Number wordsets as required.  A target that lacks one is unsupported and
\ must fail at load time, never silently produce a wrong value later.
\
\ The probe reports one PRESENT/ABSENT line per representative word and one per
\ wordset, then aborts if any required wordset is incomplete.  Absence is a
\ failure, never a pass.
\
\ The Floating probe that used to live in value.4th is consolidated here so there
\ is exactly one startup check for the required wordsets.

variable baku-probe-fail        0 baku-probe-fail !
variable baku-probe-facility    0 baku-probe-facility !
variable baku-probe-memory      0 baku-probe-memory !
variable baku-probe-floating    0 baku-probe-floating !
variable baku-probe-file        0 baku-probe-file !
variable baku-probe-exception   0 baku-probe-exception !
variable baku-probe-double      0 baku-probe-double !

\ flag missing-var c-addr u.  Print the word result and remember a miss so the
\ wordset summary can fail even when only one representative word is absent.
: baku-probe-word ( present? missing-var c-addr u -- )
	2>r swap if
		drop ." BAKU-PROBE " 2r@ type ."  PRESENT" cr
	else
		true swap ! ." BAKU-PROBE " 2r@ type ."  ABSENT" cr
	then
	2r> 2drop ;

\ missing? c-addr u.  Print the wordset result and count a missing wordset.
: baku-probe-group ( missing? c-addr u -- )
	2>r if
		." BAKU-PROBE " 2r@ type ."  ABSENT" cr
		1 baku-probe-fail +!
	else
		." BAKU-PROBE " 2r@ type ."  PRESENT" cr
	then
	2r> 2drop ;

: baku-probe-finish ( -- )
	baku-probe-facility @  s" FACILITY"          baku-probe-group
	baku-probe-memory @    s" MEMORY-ALLOCATION" baku-probe-group
	baku-probe-floating @  s" FLOATING"          baku-probe-group
	baku-probe-file @      s" FILE"              baku-probe-group
	baku-probe-exception @ s" EXCEPTION"         baku-probe-group
	baku-probe-double @    s" DOUBLE-NUMBER"     baku-probe-group
	baku-probe-fail @ if
		." BAKU-PROBE FAIL: required standard wordset(s) absent" cr
		abort
	then ;

\ Facility.  The words below are the standard Facility structure and screen
\ words Baku can rely on; TIME&DATE is a Facility extension that Sloth lacks,
\ so it is not part of this required-wordset probe.
[DEFINED] AT-XY            baku-probe-facility s" FACILITY/AT-XY"            baku-probe-word
[DEFINED] BEGIN-STRUCTURE  baku-probe-facility s" FACILITY/BEGIN-STRUCTURE"  baku-probe-word
[DEFINED] END-STRUCTURE    baku-probe-facility s" FACILITY/END-STRUCTURE"    baku-probe-word
[DEFINED] +FIELD           baku-probe-facility s" FACILITY/+FIELD"           baku-probe-word
[DEFINED] FIELD:          baku-probe-facility s" FACILITY/FIELD:"           baku-probe-word
[DEFINED] CFIELD:         baku-probe-facility s" FACILITY/CFIELD:"          baku-probe-word

\ Memory-Allocation.
[DEFINED] ALLOCATE baku-probe-memory s" MEMORY-ALLOCATION/ALLOCATE" baku-probe-word
[DEFINED] FREE     baku-probe-memory s" MEMORY-ALLOCATION/FREE"     baku-probe-word
[DEFINED] RESIZE   baku-probe-memory s" MEMORY-ALLOCATION/RESIZE"   baku-probe-word

\ Floating.  DF@/DF! are the value layer's boxed doubles; F0=, F< and F- are
\ used by the arithmetic primitives and its equality helpers.
[DEFINED] DF@ baku-probe-floating s" FLOATING/DF@" baku-probe-word
[DEFINED] DF! baku-probe-floating s" FLOATING/DF!" baku-probe-word
[DEFINED] F0= baku-probe-floating s" FLOATING/F0=" baku-probe-word
[DEFINED] F<  baku-probe-floating s" FLOATING/F<"  baku-probe-word
[DEFINED] F-  baku-probe-floating s" FLOATING/F-"  baku-probe-word

\ File.  These are the words the KLambda stream primitives map onto.
[DEFINED] OPEN-FILE       baku-probe-file s" FILE/OPEN-FILE"       baku-probe-word
[DEFINED] CLOSE-FILE      baku-probe-file s" FILE/CLOSE-FILE"      baku-probe-word
[DEFINED] CREATE-FILE     baku-probe-file s" FILE/CREATE-FILE"     baku-probe-word
[DEFINED] READ-FILE       baku-probe-file s" FILE/READ-FILE"       baku-probe-word
[DEFINED] WRITE-FILE      baku-probe-file s" FILE/WRITE-FILE"      baku-probe-word
[DEFINED] READ-LINE       baku-probe-file s" FILE/READ-LINE"       baku-probe-word
[DEFINED] WRITE-LINE      baku-probe-file s" FILE/WRITE-LINE"      baku-probe-word
[DEFINED] FILE-SIZE       baku-probe-file s" FILE/FILE-SIZE"       baku-probe-word
[DEFINED] FLUSH-FILE      baku-probe-file s" FILE/FLUSH-FILE"      baku-probe-word
[DEFINED] REPOSITION-FILE baku-probe-file s" FILE/REPOSITION-FILE" baku-probe-word
[DEFINED] DELETE-FILE     baku-probe-file s" FILE/DELETE-FILE"     baku-probe-word
[DEFINED] RENAME-FILE     baku-probe-file s" FILE/RENAME-FILE"     baku-probe-word
[DEFINED] RESIZE-FILE     baku-probe-file s" FILE/RESIZE-FILE"     baku-probe-word
[DEFINED] BIN             baku-probe-file s" FILE/BIN"             baku-probe-word
[DEFINED] R/O             baku-probe-file s" FILE/R/O"             baku-probe-word
[DEFINED] W/O             baku-probe-file s" FILE/W/O"             baku-probe-word
[DEFINED] R/W             baku-probe-file s" FILE/R/W"             baku-probe-word

\ Exception.  The KLambda trap-error path maps onto CATCH and THROW.
[DEFINED] CATCH baku-probe-exception s" EXCEPTION/CATCH" baku-probe-word
[DEFINED] THROW baku-probe-exception s" EXCEPTION/THROW" baku-probe-word

\ Double-Number.  The value layer computes its fixnum bounds with double
\ arithmetic, and the future 32-bit adaptation relies on these words.
[DEFINED] 2CONSTANT  baku-probe-double s" DOUBLE-NUMBER/2CONSTANT"  baku-probe-word
[DEFINED] 2VARIABLE  baku-probe-double s" DOUBLE-NUMBER/2VARIABLE"  baku-probe-word
[DEFINED] D+         baku-probe-double s" DOUBLE-NUMBER/D+"         baku-probe-word
[DEFINED] D-         baku-probe-double s" DOUBLE-NUMBER/D-"         baku-probe-word
[DEFINED] D<         baku-probe-double s" DOUBLE-NUMBER/D<"         baku-probe-word
[DEFINED] D=         baku-probe-double s" DOUBLE-NUMBER/D="         baku-probe-word
[DEFINED] D0<        baku-probe-double s" DOUBLE-NUMBER/D0<"        baku-probe-word
[DEFINED] D0=        baku-probe-double s" DOUBLE-NUMBER/D0="        baku-probe-word
[DEFINED] D2*        baku-probe-double s" DOUBLE-NUMBER/D2*"        baku-probe-word
[DEFINED] D2/        baku-probe-double s" DOUBLE-NUMBER/D2/"        baku-probe-word
[DEFINED] D>S        baku-probe-double s" DOUBLE-NUMBER/D>S"        baku-probe-word
[DEFINED] M*         baku-probe-double s" DOUBLE-NUMBER/M*"         baku-probe-word
[DEFINED] M*/        baku-probe-double s" DOUBLE-NUMBER/M*/"        baku-probe-word

baku-probe-finish

\ MARKER/DOES> interaction.  The mark is taken after every shipped definition in
\ this file, so executing the marker removes only the temporary words created
\ below it and leaves the real dictionary untouched.
variable baku-probe-marker-ok
variable baku-probe-marker-base
0 baku-probe-marker-ok !
here baku-probe-marker-base !

marker baku-probe-marker

: baku-probe-does-def ( -- ) does> @ ;

create baku-probe-does-created 1 ,
baku-probe-does-def

[DEFINED] baku-probe-marker [IF] [ELSE]
	." BAKU-PROBE FAIL: MARKER was not defined" cr abort
[THEN]
[DEFINED] baku-probe-does-def [IF] [ELSE]
	." BAKU-PROBE FAIL: DOES> defining word was not defined" cr abort
[THEN]
[DEFINED] baku-probe-does-created [IF] [ELSE]
	." BAKU-PROBE FAIL: DOES> word was not defined" cr abort
[THEN]

baku-probe-marker

here baku-probe-marker-base @ = [IF] [ELSE]
	." BAKU-PROBE FAIL: MARKER did not restore the dictionary" cr abort
[THEN]

[DEFINED] baku-probe-marker [IF]
	." BAKU-PROBE FAIL: MARKER did not remove itself" cr abort
[THEN]
[DEFINED] baku-probe-does-def [IF]
	." BAKU-PROBE FAIL: MARKER left the DOES> defining word" cr abort
[THEN]
[DEFINED] baku-probe-does-created [IF]
	." BAKU-PROBE FAIL: MARKER left the DOES> word" cr abort
[THEN]

1 baku-probe-marker-ok !
." BAKU-PROBE MARKER/DOES>  PRESENT" cr
