\ Harness smoke test: the Baku sources load and basic ANS Forth works.
INCLUDE ../4th/baku.4th

1 1 + 2 <> ABORT" BAKU-TEST-FAIL: 1 1 + is not 2"

." BAKU-TEST-DONE" CR
