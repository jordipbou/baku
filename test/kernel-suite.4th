\ Shen 43.2 kernel conformance suite through a booted Baku kernel.
\
\ The suite is the official vendored `vendor/shen-43.2/tests/` tree, Shen source
\ for a booted top level.  Its entry `runme.shen` loads `harness.shen` then
\ `kerneltests.shen`; a failed check calls `y-or-n?`, so the runner binds
\ `*stinput*` to a file of "y" answers and the suite continues instead of
\ blocking.  The final pass and fail counts are recorded and compared against the
\ pinned baseline at the end of this file.
\
\ Why GC mode: non-GC keeps every allocation.  The native boot already keeps
\ about 490 MiB, and the `primes` report allocates several GiB; a measured 2 GiB
\ non-GC run exhausted the heap inside `(prime*? 1000003)`.  The collector is the
\ only mode that can finish the suite.  GC mode uses the interpreter because
\ native code lives in the dictionary, which the collector does not trace.
\
\ Why gforth only: the collector needs Forth stack roots.  The pinned Sloth
\ exposes no stack pointer, so `baku-gc-activate` raises `baku-gc-unsupported`.
\ This is an explicit capability branch, not a silent skip: the full non-GC
\ corpus loader still runs on Sloth in test/native.4th.
\
\ Why `*home-directory*` is bound after initialisation: `stlib.initialise`
\ calls `(cd "")`, which resets it to the empty string.  `(load "file")` opens a
\ relative name through `*home-directory*`, so the suite would not find its own
\ files otherwise.  This is kernel behaviour, not a Baku defect.
\
\ Why `reset` is redefined: `kerneltests.shen` ends with `(reset)`, which clears
\ the harness counters after the last report printed them.  The harness declares
\ `reset` inside `(package test-harness ...)`, so both the unqualified external
\ name and the package-qualified function are redefined as no-ops after
\ `harness.shen` loads; the final totals then stay readable.  No test or
\ prediction is changed.

[DEFINED] gforth
[IF]
	S" ../4th/portability.4th" INCLUDED
	67108864 baku-nongc-request !
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	67108864 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

\ 256 MiB per semispace.  The booted kernel's live set is about 6.5 MiB, but the
\ suite allocates heavily; a larger semispace trades memory for far fewer
\ collections.  `ALLOCATE` uses the host heap, so this is not the gforth `-m`
\ dictionary.
\
\ The non-GC heap is permanent, and interned symbols are always placed there.
\ The suite creates a large number of symbols (gensyms and loaded programs), so
\ the 512 KiB default fills up after most of the kernel tests; 64 MiB leaves
\ ample headroom without changing any measurement.
268435456 baku-gc-create
baku-gc-activate

baku-boot-load-kernel

: baku-suite-check-boot ( -- )
	baku-boot-files @ 23 <> if ." BAKU-SUITE-FAIL boot files" cr abort then
	baku-boot-forms @ 1124 <> if ." BAKU-SUITE-FAIL boot forms" cr abort then
	baku-boot-defuns @ 1118 <> if ." BAKU-SUITE-FAIL boot defuns" cr abort then ;

baku-suite-check-boot

baku-boot-globals
baku-boot-initialise

\ ---------------------------------------------------------------------------
\ Input: the harness asks `y-or-n?` only after a failed check.  A file of 512
\ affirmative answers lets every known failure continue; running out would make
\ the read at end of file raise, so the count has ample headroom.
\ ---------------------------------------------------------------------------

create baku-suite-yes 2 allot
variable baku-suite-input-file

: baku-suite-make-input ( -- )
	121 baku-suite-yes c!
	10 baku-suite-yes 1+ c!
	s" baku-kernel-suite.stdin" w/o bin create-file throw
	baku-suite-input-file !
	512 0 ?do
		baku-suite-yes 2 baku-suite-input-file @ write-file throw
	loop
	baku-suite-input-file @ close-file throw ;

: baku-suite-open-input ( -- )
	s" *stinput*" baku-intern
	s" baku-kernel-suite.stdin" r/o bin open-file baku-stream-from-file
	baku-global-define drop ;

: baku-suite-close-input ( -- )
	s" *stinput*" baku-intern baku-global-lookup if
		dup baku-stream? if baku-prim-close then drop
	else
		drop
	then ;

: baku-suite-bind-home ( -- )
	s" *home-directory*" baku-intern
	s" vendor/shen-43.2/tests/" baku-string
	baku-global-define drop ;

baku-suite-make-input
baku-suite-open-input
baku-suite-bind-home

\ ---------------------------------------------------------------------------
\ Load the harness, replace its final `reset`, then run the kernel tests.
\ ---------------------------------------------------------------------------

: baku-suite-load ( c-addr u -- )
	baku-string s" load" baku-intern baku-repl-call1 drop ;

\ Last-definition-wins installs these in place of the harness `reset`.  The
\ harness declares the name inside its package, and the report macro calls the
\ unqualified external name, so both spellings are replaced.
: baku-suite-keep-counters ( -- )
	s" (defun reset () ok)" baku-compat-eval-source
	s" (defun test-harness.reset () ok)" baku-compat-eval-source ;

: baku-suite-run ( -- )
	s" harness.shen" baku-suite-load
	baku-suite-keep-counters
	s" kerneltests.shen" baku-suite-load ;

\ The harness counters are package-scoped: `*passed*` in the harness body is
\ `test-harness.*passed*`.  A missing counter (no test ran) reads as zero.
: baku-suite-counter ( sym -- n )
	baku-global-lookup if baku-fixnum-value else 0 then ;

: baku-suite-passed ( -- n )
	s" test-harness.*passed*" baku-intern baku-suite-counter ;
: baku-suite-failed ( -- n )
	s" test-harness.*failed*" baku-intern baku-suite-counter ;

\ Baseline from the pinned release and this runtime.  The pass count must not
\ drop and the fail count must not rise; the five named failures are recorded in
\ .ralph/IMPLEMENTATION_PLAN.md.
149 constant baku-suite-expected-passed
5 constant baku-suite-expected-failed

: baku-suite-check ( -- )
	baku-suite-passed baku-suite-expected-passed < if
		." BAKU-SUITE-FAIL passed=" baku-suite-passed .
		." expected>=" baku-suite-expected-passed . cr abort
	then
	baku-suite-failed baku-suite-expected-failed > if
		." BAKU-SUITE-FAIL failed=" baku-suite-failed .
		." expected<=" baku-suite-expected-failed . cr abort
	then ;

: baku-suite-report ( -- )
	." BAKU-KERNEL-SUITE passed=" baku-suite-passed .
	." failed=" baku-suite-failed .
	." collections=" baku-gc-collections @ . cr ;

: baku-suite-cleanup ( -- )
	baku-suite-close-input
	s" baku-kernel-suite.stdin" delete-file drop ;

variable baku-suite-throw

: baku-suite-gate ( -- )
	['] baku-suite-run catch ?dup if
		baku-suite-throw !
		baku-suite-report
		baku-suite-cleanup
		." BAKU-SUITE-THROW=" baku-suite-throw @ . cr
		abort
	then
	baku-suite-report
	baku-suite-check
	baku-suite-cleanup
	." BAKU-TEST-DONE" cr ;

baku-suite-gate
bye
