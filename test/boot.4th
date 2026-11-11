\ Kernel boot loader tests.
\
\ The loader keeps the IR of every kernel definition in the non-GC heap in the
\ interpreter backend, so this test raises the heap request before loading the
\ tree.  The default request stays small for every other test.  Initialisation
\ is not run here: interpreter EVAL-KL allocates permanent IR per call and needs
\ far more than the loader budget; that path belongs to the native backend.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	16777216 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	16777216 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: check-num ( actual expected code -- )
	>r = r> check ;

\ ---------------------------------------------------------------------------
\ Load the whole kernel through the default interpreter installer.
\ ---------------------------------------------------------------------------

baku-boot-load-kernel

baku-boot-files @ 23 1 check-num
baku-boot-forms @ 1124 2 check-num
baku-boot-defuns @ 1118 3 check-num
baku-boot-forms @ baku-boot-defuns @ - 6 4 check-num

\ ---------------------------------------------------------------------------
\ Every definition in the generated name list resolves.  The list is produced
\ by tools/klambda_expected.py, an independent string-aware parser, so this is
\ not a restatement of the loader.
\ ---------------------------------------------------------------------------

variable boot-missing
variable boot-seen
0 boot-missing ! 0 boot-seen !

: check-name ( sym -- )
	baku-fn-lookup if drop else 1 boot-missing +! then
	1 boot-seen +! ;

: walk-names ( -- )
	begin baku-read-form while check-name repeat
	drop baku-read-close ;

s" test/expected-defuns.kl" baku-read-file
walk-names

boot-seen @ 1117 5 check-num
boot-missing @ 0 6 check-num

\ Spot checks on names from both the kernel and the extensions.
: defined? ( c-addr u -- flag ) baku-intern baku-fn-lookup nip ;
s" shen.initialise" defined? 7 check
s" stlib.initialise" defined? 8 check
s" shen.repl" defined? 9 check
s" factorial" defined? 10 check
s" min" defined? 11 check
s" not.a.kernel.name" defined? 0= 12 check

\ ---------------------------------------------------------------------------
\ Last-definition-wins on a synthetic duplicate; the real `min` duplicate has
\ two equivalent bodies and cannot distinguish the two definitions.
\ ---------------------------------------------------------------------------

: eval-text ( c-addr u -- value )
	baku-read-string baku-read-form 0= if drop baku-read-eof throw then
	baku-eval-kl ;

s" (defun boot-last-wins () 1)" eval-text drop
s" (defun boot-last-wins () 2)" eval-text drop
s" (boot-last-wins)" eval-text baku-fixnum-value 2 13 check-num

\ ---------------------------------------------------------------------------
\ Host globals the kernel reads: bound, and with the documented values.
\ ---------------------------------------------------------------------------

baku-boot-globals

: global ( c-addr u -- value flag ) baku-intern baku-global-lookup ;
: global-bound? ( c-addr u -- flag ) global nip ;
: global-value ( c-addr u -- value ) global if else baku-nil then ;

s" *language*" global-bound? 14 check
s" *implementation*" global-bound? 15 check
s" *release*" global-bound? 16 check
s" *port*" global-bound? 17 check
s" *porters*" global-bound? 18 check
s" *os*" global-bound? 19 check
s" *stinput*" global-bound? 20 check
s" *stoutput*" global-bound? 21 check
s" *argv*" global-bound? 22 check

s" *language*" global-value s" Shen" baku-intern = 23 check
s" *release*" global-value s" 43.2" baku-intern = 24 check
s" *argv*" global-value baku-nil = 25 check
s" *hush*" global-value baku-false = 26 check
s" *stoutput*" global-value baku-object-type baku-type-stream = 27 check

\ ---------------------------------------------------------------------------
\ EVAL-KL is the executor the kernel calls as a function, so it must be a
\ callable primitive in the function table, not only a Forth word.
\ ---------------------------------------------------------------------------

: eval-kl-primitive? ( -- flag )
	s" eval-kl" baku-intern baku-fn-lookup if
		dup baku-closure-kind 1 =
		over baku-closure-arity 1 = and
		nip
	else
		false
	then ;

eval-kl-primitive? 28 check

." BAKU-TEST-DONE" cr
