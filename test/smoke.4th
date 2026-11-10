\ Harness smoke test: the Baku sources load and basic ANS Forth works.
[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

1 1 + 2 <> ABORT" BAKU-TEST-FAIL: 1 1 + is not 2"

." BAKU-TEST-DONE" CR
