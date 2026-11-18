\ Native bootstrap: compile the kernel to dictionary code, initialise it and run
\ a few kernel functions.
\
\ Non-GC mode keeps every allocation made during initialisation, so the boot
\ needs a much larger heap than the loader.  The request is set before the tree
\ is included; CTest sizes the Sloth dictionary and the gforth dictionary for
\ this file.  The front-end IR is lowered into the shared 4 MiB scratch block
\ and discarded after each form, so the heap growth is kernel data, not IR.
\
\ The chosen bootstrap mode is native non-GC, so the root-set acceptance check
\ cannot run during boot: the collector does not exist yet.  The same forced
\ collection runs after boot once the collector exists, which is this file's
\ second half.  It proves the booted globals, a live reader form and the
\ kernel's native closures survive a collection, and that a pre-activation
\ (non-GC) table binding is updated when a GC value moves in it.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

: ev ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if drop baku-read-eof throw then
	baku-eval-kl ;

variable root-before

\ ---------------------------------------------------------------------------
\ Boot order: the roots exist before the loader allocates anything.  The
\ explicit range registry, the function/global bucket tables and the target
\ stack-scan adapter are created by the shipped layers at load time, so the
\ collector can never run with a missing root.  This file is gforth-only, so
\ the stack adapter must be the real one.
\ ---------------------------------------------------------------------------

baku-gc-created? @ 0= 1 check
baku-gc-active? 0= 2 check
baku-gc-stack-scan? 3 check
baku-gc-root-count @ 34 >= 4 check
baku-gc-table-count @ 2 >= 5 check

\ ---------------------------------------------------------------------------
\ Install the kernel natively.  The native installer is the non-GC backend:
\ every top-level defun becomes a dictionary code block.
\ ---------------------------------------------------------------------------

' baku-native-install-form is baku-install-form

baku-boot-load-kernel

baku-boot-files @ 23 6 check-num
baku-boot-forms @ 1124 7 check-num
baku-boot-defuns @ 1118 8 check-num

\ ---------------------------------------------------------------------------
\ Initialise.  BAKU-BOOT-INITIALISE runs SHEN.INITIALISE then STLIB.INITIALISE
\ in the documented order.  Nested EVAL-KL calls go through the native path
\ because NATIVE.4TH registers BAKU-NATIVE-EVAL-KL as the callable primitive.
\ ---------------------------------------------------------------------------

baku-boot-globals
baku-boot-initialise

s" (arity factorial)" ev baku-fixnum-value 1 9 check-num
s" (+ 1 2)" ev baku-fixnum-value 3 10 check-num
s" (factorial 10)" ev baku-fixnum-value 3628800 11 check-num
s" (abs -5)" ev baku-fixnum-value 5 12 check-num
s" (arity abs)" ev baku-fixnum-value 1 13 check-num

\ ---------------------------------------------------------------------------
\ Forced collection after a non-GC boot.
\ ---------------------------------------------------------------------------

\ A binding that exists before the collector does.  Its entry stays in the
\ non-GC heap when a GC value is written into its tail, so the collector must
\ walk the table entry by shape rather than as a GC object.
s" baku.root.old" baku-intern
1 baku-fixnum baku-global-define drop

131072 baku-gc-semispace-request !
baku-gc-create
baku-gc-created? @ 14 check
baku-gc-collections @ 0= 15 check

baku-gc-activate
baku-gc-active? 16 check
baku-mode baku-mode-gc = 17 check

\ The boot globals are non-GC values, and the kernel functions are native
\ dictionary closures.  A collection must leave both usable.
baku-gc-collect
baku-gc-collections @ 0<> 18 check
baku-gc-active? 19 check
s" (factorial 10)" ev baku-fixnum-value 3628800 20 check-num
s" (+ 1 2)" ev baku-fixnum-value 3 21 check-num
s" (arity factorial)" ev baku-fixnum-value 1 22 check-num

\ A fresh global is a GC entry in the function's bucket array.  The rooted
\ value must move to the new from-space and read back through the table.
s" (set baku.root.fresh (cons 9 10))" ev root-before !
baku-gc-collect
s" (value baku.root.fresh)" ev
dup baku-cons? 23 check
dup root-before @ <> 24 check
dup baku-region-of baku-region-gc = 25 check
dup baku-prim-hd baku-fixnum-value 9 26 check-num
baku-prim-tl baku-fixnum-value 10 27 check-num

\ A GC value stored into the pre-activation non-GC binding must be updated
\ when the object moves.
s" (set baku.root.old (cons 11 12))" ev drop
baku-gc-collect
s" (value baku.root.old)" ev
dup baku-cons? 28 check
dup baku-prim-hd baku-fixnum-value 11 29 check-num
baku-prim-tl baku-fixnum-value 12 30 check-num

\ An interpreted defun created under the collector lives in the GC heap; its
\ closure and code must survive a collection.
s" (defun baku.root.count (N) (if (= N 0) 1 (* N (baku.root.count (- N 1)))))"
ev drop
baku-gc-collect
s" (baku.root.count 5)" ev baku-fixnum-value 120 31 check-num

\ A reader form that stays live across a collection.  Reader scratch is a
\ dictionary arena region, so the collector must leave it untouched.
: rs-live-form ( -- value )
	s" (+ 20 22)" baku-read-string
	baku-read-form 0= if baku-read-eof throw then
	baku-gc-collect
	baku-eval-kl ;

rs-live-form baku-fixnum-value 42 32 check-num

\ A cached raw address outside the roots is detected: after the move it no
\ longer classifies as a GC object, so a stale cache cannot masquerade as a
\ live value.
baku-nil baku-nil baku-cons root-before !
baku-gc-collect
root-before @ baku-region-of baku-region-gc <> 33 check

." BAKU-TEST-DONE" cr
