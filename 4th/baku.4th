\ Baku — Shen on ANS Forth.
\
\ Entry point.  Load from the repository root:
\
\   S" 4th/baku.4th" INCLUDED
\
\ gforth resolves a nested INCLUDED relative to the including file, while Sloth
\ resolves it relative to the working directory.  The spelling below is the only
\ documented per-target difference in file inclusion; it changes no semantics.

[DEFINED] gforth
[IF]
	S" value.4th" INCLUDED
	S" reader.4th" INCLUDED
	S" frontend.4th" INCLUDED
[ELSE]
	S" 4th/value.4th" INCLUDED
	S" 4th/reader.4th" INCLUDED
	S" 4th/frontend.4th" INCLUDED
[THEN]
