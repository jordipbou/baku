\ Baku user entry: load the library, choose the non-GC boot and start Shen.
\
\ This is the one-line user path described in README.md.  It exists because the
\ non-GC heap request is read when 4th/value.4th loads, and the
\ native installer and kernel globals must be selected before boot, so the
\ library entry point 4th/baku.4th cannot also boot itself without forcing a
\ lifetime policy on every embedder.  Loading this file is the whole install:
\ no build step, no generated .4th file, and the kernel is read from
\ vendor/shen-43.2/klambda/ at run time.
\
\ The non-GC boot keeps every initialisation allocation (about 490 MiB), so the
\ target must provide enough dictionary space.  On gforth, from the repository
\ root:
\
\   gforth -m 768M -d 16M -r 16M
\   s" 4th/start.4th" INCLUDED
\
\ or as one command:
\
\   gforth -m 768M -d 16M -r 16M -e 's" 4th/start.4th" INCLUDED'
\
\ The native installer is the supported boot backend; the interpreter remains
\ available through 4th/baku.4th for tests and embedders that select it.

[DEFINED] gforth
[IF]
	S" portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" baku.4th" INCLUDED
[ELSE]
	S" 4th/portability.4th" INCLUDED
	536870912 baku-nongc-request !
	S" 4th/baku.4th" INCLUDED
[THEN]

' baku-native-install-form is baku-install-form

baku-boot-load-kernel
baku-boot-globals
baku-boot-initialise

." BAKU-STARTED" CR

baku-repl
