INCLUDE ../4th/baku.4th

: check ( flag code -- )
	swap if ." BAKU-TEST-FAIL: " . cr abort then drop ;

baku-heap-reset

baku-heap-used 0 <> 1 check
baku-heap-free baku-heap-size <> 2 check

1 baku-fixnum baku-fixnum? 0= 3 check
1 baku-fixnum baku-fixnum-value 1 <> 4 check
-7 baku-fixnum baku-fixnum-value -7 <> 5 check
0 baku-fixnum baku-fixnum-value 0 <> 6 check
baku-heap-area baku-fixnum? 7 check
baku-heap-area baku-object? 8 check

baku-heap-reset
0 baku-cons baku-alloc
dup baku-object? 0= 9 check
dup baku-object-type baku-cons <> 10 check
dup dup aligned = 0= 11 check
dup baku-heap-area <> 12 check
baku-heap-used 1 cells <> 13 check
drop

baku-heap-reset
1 baku-string baku-alloc
dup dup aligned = 0= 14 check
baku-heap-used 2 cells <> 15 check
1 baku-string baku-alloc
dup dup aligned = 0= 16 check
baku-heap-used 4 cells <> 17 check
drop drop

baku-heap-reset
2 baku-vector baku-alloc-cells
dup baku-object-type baku-vector <> 18 check
baku-heap-used 3 cells <> 19 check
drop

baku-heap-reset
1 baku-string ' baku-alloc catch 0 <> 20 check
drop

baku-heap-reset
baku-heap-free 1+ baku-cons ' baku-alloc catch
dup baku-out-of-memory <> 21 check
drop
baku-heap-used 0 <> 22 check

." BAKU-TEST-DONE" CR
