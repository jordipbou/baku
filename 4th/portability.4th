\ Baku portability file.
\
\ Four names used by the shipped sources are not ANS Forth 2012 words:
\ CELL, -ROT, <= and >=.  They are defined here with ANS-only fallbacks, so
\ the shipped tree uses only ANS Forth 2012 words plus Baku's own definitions.
\ This file must load before every other Baku layer.

1 cells constant cell

: -rot ( a b c -- c a b ) rot rot ;
: <= ( a b -- flag ) > 0= ;
: >= ( a b -- flag ) < 0= ;
