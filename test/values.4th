\ Value representation and region classification tests.
\
\ gforth resolves a nested INCLUDED relative to the including file; Sloth
\ resolves it relative to the working directory.  This test-only spelling is the
\ same documented difference as in 4th/baku.4th.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

\ Fixnums: identity, zero, negative and a value past 32 bits.
0 baku-fixnum baku-fixnum? 1 check
0 baku-fixnum baku-fixnum-value 0 = 2 check
1 baku-fixnum baku-fixnum? 3 check
1 baku-fixnum baku-fixnum-value 1 = 4 check
-1 baku-fixnum baku-fixnum? 5 check
-1 baku-fixnum baku-fixnum-value -1 = 6 check
-7 baku-fixnum baku-fixnum? 7 check
-7 baku-fixnum baku-fixnum-value -7 = 8 check
10000000000 baku-fixnum baku-fixnum-value 10000000000 = 9 check

\ Immediate values are neither fixnums nor heap objects, and are distinct.
baku-nil baku-fixnum? 0= 10 check
baku-nil baku-immediate? 11 check
baku-true baku-immediate? 12 check
baku-false baku-immediate? 13 check
baku-nil baku-true = 0= 14 check
baku-nil baku-false = 0= 15 check
baku-true baku-false = 0= 16 check
baku-nil baku-object? 0= 17 check
baku-true baku-object? 0= 18 check
baku-false baku-object? 0= 19 check

\ Region classification: an empty region holds nothing, and aligned addresses
\ outside every region are not objects.
baku-nongc-reset
baku-nongc-used 0= 20 check
baku-nongc-free baku-nongc-size = 21 check
baku-nongc-block baku-object? 0= 22 check
baku-nongc-block baku-nongc-size + baku-object? 0= 23 check
0 baku-object? 0= 24 check
8 baku-object? 0= 25 check
here baku-object? 0= 26 check
here aligned here = 27 check

\ A cons carries a uniform header, identifies its region, and keeps both cells.
baku-nongc-reset
1 baku-fixnum 2 baku-fixnum baku-cons
dup baku-object? 28 check
dup baku-object-type baku-type-cons = 29 check
dup baku-object-size 2 cells = 30 check
dup baku-region-of baku-region-nongc = 31 check
dup baku-hd baku-fixnum-value 1 = 32 check
dup baku-tl baku-fixnum-value 2 = 33 check
dup dup aligned = 34 check
drop
baku-nongc-used 3 cells = 35 check

\ A zero-payload object is header-only and still gets a type and a region.
baku-nongc-reset
0 baku-type-string baku-alloc
dup baku-object? 36 check
dup baku-object-type baku-type-string = 37 check
dup baku-object-size 0= 38 check
drop
baku-nongc-used 1 cells = 39 check

\ Out of memory is catchable and leaves the heap untouched and usable.
baku-nongc-reset
baku-nongc-size cell + 1+ baku-type-string ' baku-alloc catch
baku-out-of-memory = 40 check
baku-nongc-used 0= 41 check
1 baku-type-string baku-alloc drop
baku-nongc-used 2 cells = 42 check

\ Invalid objects and type mismatches throw catchable errors.
0 ' baku-object-type catch baku-invalid-object = 43 check
1 baku-fixnum ' baku-hd catch baku-cons-expected = 44 check

\ Strings are byte-counted payloads, not terminated.
baku-nongc-reset
s" hello" baku-string
dup baku-string? 45 check
dup baku-string-length 5 = 46 check
dup 0 baku-string@ char h = 47 check
dup 4 baku-string@ char o = 48 check
dup 5 ' baku-string@ catch baku-string-bounds-error = 49 check
drop
s" " baku-string dup baku-string-length 0= 50 check drop

\ Vectors are cell-counted and zero-initialised.
baku-nongc-reset
3 baku-vector
dup baku-vector? 51 check
dup baku-vector-length 3 = 52 check
dup 0 baku-vector@ 0= 53 check
7 over 1 baku-vector!
dup 1 baku-vector@ 7 = 54 check
dup 2 baku-vector@ 0= 55 check
dup 3 ' baku-vector@ catch baku-vector-bounds-error = 56 check
drop

\ Symbols are case-sensitive and identical spellings intern to one value.
baku-nongc-reset
s" foo" baku-intern
dup baku-symbol? 57 check
dup baku-symbol-name-len 3 = 58 check
drop
s" foo" baku-intern s" foo" baku-intern = 59 check
s" foo" baku-intern s" Foo" baku-intern = 0= 60 check
s" foo" baku-intern s" bar" baku-intern = 0= 61 check
s" a_b" baku-intern s" a-b" baku-intern = 0= 62 check

\ Empty strings and empty vectors are heap objects, distinct from each other and
\ from the immediate empty list.
baku-nongc-reset
s" " baku-string baku-nil = 0= 63 check
0 baku-vector baku-nil = 0= 64 check
s" " baku-string 0 baku-vector = 0= 65 check

\ Boxed floating-point values round-trip through the value layer.
baku-nongc-reset
3.5e baku-float
dup baku-float? 66 check
dup baku-float@ 3.5e 0e f~ 67 check
drop

\ A constructor leaves exactly one value on the stack.
baku-nongc-reset
depth >r s" hi" baku-string depth r> - 1 = 68 check drop

." BAKU-TEST-DONE" cr
