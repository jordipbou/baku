\ Native bootstrap: compile the kernel to dictionary code, initialise it and run
\ a few kernel functions.
\
\ Non-GC mode keeps every allocation made during initialisation, so the boot
\ needs a much larger heap than the loader.  The request is set before the tree
\ is included; CTest sizes the Sloth dictionary and the gforth dictionary for
\ this file.  The front-end IR is lowered into the shared 4 MiB scratch block
\ and discarded after each form, so the heap growth is kernel data, not IR.
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

\ ---------------------------------------------------------------------------
\ Install the kernel natively.  The native installer is the non-GC backend:
\ every top-level defun becomes a dictionary code block.
\ ---------------------------------------------------------------------------

' baku-native-install-form is baku-install-form

baku-boot-load-kernel

baku-boot-files @ 23 1 check-num
baku-boot-forms @ 1124 2 check-num
baku-boot-defuns @ 1118 3 check-num

\ ---------------------------------------------------------------------------
\ Initialise.  BAKU-BOOT-INITIALISE runs SHEN.INITIALISE then STLIB.INITIALISE
\ in the documented order.  Nested EVAL-KL calls go through the native path
\ because NATIVE.4TH registers BAKU-NATIVE-EVAL-KL as the callable primitive.
\ ---------------------------------------------------------------------------

baku-boot-globals
baku-boot-initialise

s" (arity factorial)" ev baku-fixnum-value 1 4 check-num
s" (+ 1 2)" ev baku-fixnum-value 3 5 check-num
s" (factorial 10)" ev baku-fixnum-value 3628800 6 check-num
s" (abs -5)" ev baku-fixnum-value 5 7 check-num
s" (arity abs)" ev baku-fixnum-value 1 8 check-num

." BAKU-TEST-DONE" cr
