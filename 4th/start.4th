\ Baku user entry: load the library, boot under the collector and start Shen.
\
\ This is the one-line user path described in README.md.  It exists because the
\ symbol-area request is read when 4th/value.4th loads and the semispace request
\ when BAKU-GC-CREATE runs, and the kernel globals must be bound before boot, so
\ the library entry point 4th/baku.4th cannot also boot itself without forcing a
\ lifetime policy on every embedder.  Loading this file is the whole install:
\ no build step, no generated .4th file, and the kernel is read from
\ vendor/shen-43.2/klambda/ at run time.
\
\ The boot runs on the Cheney collector with the tree-walking interpreter as
\ the only executor.  4th/portability.4th sizes the permanent symbol area and
\ both semispaces; a caller that needs a different lifetime sets
\ BAKU-NONGC-REQUEST before loading the tree and BAKU-GC-SEMISPACE-REQUEST
\ before creating the collector.  On gforth, from the repository root:
\
\   gforth -m 64M -d 16M -r 16M
\   s" 4th/start.4th" INCLUDED
\
\ or as one command:
\
\   gforth -m 64M -d 16M -r 16M -e 's" 4th/start.4th" INCLUDED'
\
\ The gforth data and return stacks must hold the deepest reader and
\ initialisation recursion; the dictionary only holds the shipped Forth and the
\ permanent symbol block.

[DEFINED] gforth
[IF]
	S" portability.4th" INCLUDED
	S" baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	S" 4th/baku.4th" INCLUDED
[THEN]

baku-gc-create
baku-gc-activate

\ Install the KLambda compatibility and top-level helpers after activation so
\ their closures and IR are GC objects; 4th/baku.4th cannot do this at load
\ time because the collector does not exist yet.
baku-compat-init
baku-repl-init

baku-boot-load-kernel
baku-boot-globals
baku-boot-initialise

." BAKU-STARTED" CR

baku-repl
