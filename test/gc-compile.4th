\ Compilation under the collector.
\
\ Partly built IR lives in the heap the collector owns.  The Forth return stack
\ is not a GC root, so a builder must never leave a node there across a
\ recursive compile that can collect.  This test fills a small semispace, then
\ compiles a deeply nested form and a partial application so at least one
\ collection runs while IR is under construction.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

65536 baku-gc-semispace-request !
baku-gc-create
baku-gc-activate

variable gc-compile-old

: gc-compile-garbage ( n -- )
	0 ?do baku-nil baku-nil baku-cons drop loop ;

\ Leave room for part of the IR, so the next collection lands after some nodes
\ exist rather than before the first allocation.
: gc-compile-fill ( -- )
	begin
		baku-gc-used? baku-gc-semispace @ 11000 - <
	while
		baku-nil baku-nil baku-cons drop
	repeat ;

\ (if false 0 inner), with the clause list built directly so the test does not
\ depend on the reader.
: gc-compile-wrap ( inner -- outer )
	baku-nil baku-cons
	0 baku-fixnum swap baku-cons
	baku-false swap baku-cons
	s" if" baku-intern swap baku-cons ;

: gc-compile-nest ( n -- form )
	42 baku-fixnum swap 0 ?do gc-compile-wrap loop ;

: gc-compile-read ( c-addr u -- form )
	baku-read-string
	baku-read-form 0= if drop baku-read-eof throw then ;

\ Build the form first, then fill the heap so the collection lands inside the
\ compile rather than while the form is being read or built.
200 gc-compile-nest
gc-compile-fill
baku-gc-collections @ gc-compile-old !
baku-eval-kl baku-fixnum-value 42 = 1 check
baku-gc-collections @ gc-compile-old @ > 2 check

\ A partial application accumulates its saved and new arguments through
\ BAKU-LIST-APPEND, which must also keep its lists rooted across a collection.
s" (defun gc-add (X Y) (+ X Y))" gc-compile-read baku-eval-kl drop
s" (gc-add 1)" gc-compile-read baku-eval-kl
dup baku-closure-kind baku-closure-partial = 3 check
drop
4000 gc-compile-garbage
s" ((gc-add 1) 41)" gc-compile-read baku-eval-kl baku-fixnum-value 42 = 4 check

\ A caught malformed form must not leave a compiler root behind; the next
\ compile must still start at depth zero.  The CATCH wraps a colon definition
\ because `[']` has compilation semantics and Sloth only accepts it there.
: gc-compile-try ( c-addr u -- code )
	gc-compile-read ['] baku-eval-kl catch ;

s" (if 1 2)" gc-compile-try 0= 0= 5 check
baku-front-root-depth @ 0= 6 check
s" (gc-add 2 3)" gc-compile-read baku-eval-kl baku-fixnum-value 5 = 7 check

." BAKU-TEST-DONE" cr
