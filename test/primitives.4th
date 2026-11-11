\ KLambda arithmetic and comparison primitives.
\
\ These tests exercise 4th/primitives.4th through both boundaries: the
\ primitive words directly (type, range and division errors) and BAKU-EVAL-KL
\ (registration, dispatch and Shen-visible semantics).  String literals are
\ built directly because a Forth S" literal cannot contain a double quote.

[DEFINED] gforth
[IF]
	S" ../4th/baku.4th" INCLUDED
[ELSE]
	S" 4th/baku.4th" INCLUDED
[THEN]

: check ( flag code -- )
	swap if drop else ." BAKU-TEST-FAIL: " . cr abort then ;

: run ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if
		." BAKU-TEST-FAIL: reader refused a primitive form" cr abort
	then
	baku-eval-kl ;

: check-error ( c-addr u expected code -- )
	>r >r ['] run catch
	>r 2drop r>
	r> = r> check ;

\ Catch a failure of a binary primitive and return its THROW code.
: prim-error ( a b xt -- code )
	catch >r 2drop r> ;

: test-str= ( obj c-addr u -- flag )
	baku-string baku-prim-eq baku-true = ;

: vec2 ( a b -- v )
	2 baku-vector >r
	r@ 1 baku-vector!
	r@ 0 baku-vector!
	r> ;

: vec3 ( a b c -- v )
	3 baku-vector >r
	r@ 2 baku-vector!
	r@ 1 baku-vector!
	r@ 0 baku-vector!
	r> ;

\ A vector whose first element is a three-element vector.
: nested-vec ( -- v )
	1 baku-fixnum 2 baku-fixnum 3 baku-fixnum vec3
	1 baku-fixnum vec2 ;

: nested-vec-other ( -- v )
	1 baku-fixnum 2 baku-fixnum 4 baku-fixnum vec3
	1 baku-fixnum vec2 ;

\ ---------------------------------------------------------------------------
\ Arithmetic primitives, directly
\ ---------------------------------------------------------------------------

1 baku-fixnum 2 baku-fixnum baku-prim-add baku-fixnum-value 3 = 1 check
5 baku-fixnum 2 baku-fixnum baku-prim-sub baku-fixnum-value 3 = 2 check
3 baku-fixnum 4 baku-fixnum baku-prim-mul baku-fixnum-value 12 = 3 check
0 baku-fixnum 7 baku-fixnum baku-prim-sub baku-fixnum-value -7 = 4 check

\ Exact integer division stays an integer.
6 baku-fixnum 2 baku-fixnum baku-prim-div
dup baku-fixnum? 5 check
baku-fixnum-value 3 = 6 check

\ Inexact division is a float.
7 baku-fixnum 2 baku-fixnum baku-prim-div
dup baku-float? 7 check
baku-float@ 3.5e 0.000001e f~ 8 check

-6 baku-fixnum 2 baku-fixnum baku-prim-div baku-fixnum-value -3 = 9 check
6 baku-fixnum -3 baku-fixnum baku-prim-div baku-fixnum-value -2 = 10 check
1 baku-fixnum 3 baku-fixnum baku-prim-div
baku-float@ 1e 3e f/ 0.000001e f~ 11 check

\ A result outside the fixnum range is catchable, not a silent wrap.
baku-fixnum-max baku-fixnum 1 baku-fixnum
' baku-prim-add prim-error baku-arithmetic-overflow = 12 check
baku-fixnum-min baku-fixnum 1 baku-fixnum
' baku-prim-sub prim-error baku-arithmetic-overflow = 13 check
baku-fixnum-max baku-fixnum 2 baku-fixnum
' baku-prim-mul prim-error baku-arithmetic-overflow = 14 check
0 baku-fixnum baku-fixnum-min baku-fixnum
' baku-prim-sub prim-error baku-arithmetic-overflow = 15 check

\ Division by any numeric zero is catchable.
1 baku-fixnum 0 baku-fixnum
' baku-prim-div prim-error baku-division-by-zero = 16 check

\ A non-number operand is a catchable type error.
1 baku-fixnum baku-true
' baku-prim-add prim-error baku-eval-type = 17 check
1 baku-fixnum baku-nil
' baku-prim-lt prim-error baku-eval-type = 18 check

\ ---------------------------------------------------------------------------
\ Comparison primitives, directly
\ ---------------------------------------------------------------------------

1 baku-fixnum 2 baku-fixnum baku-prim-lt baku-true = 19 check
2 baku-fixnum 1 baku-fixnum baku-prim-gt baku-true = 20 check
1 baku-fixnum 1e baku-float baku-prim-eq baku-true = 21 check

\ ---------------------------------------------------------------------------
\ Shen equality, directly
\ ---------------------------------------------------------------------------

s" abc" baku-string s" abc" baku-string baku-prim-eq baku-true = 22 check
s" abc" baku-string s" abd" baku-string baku-prim-eq baku-false = 23 check
s" abc" baku-string s" ab" baku-string baku-prim-eq baku-false = 24 check

1 baku-fixnum 2 baku-fixnum baku-cons
1 baku-fixnum 2 baku-fixnum baku-cons
baku-prim-eq baku-true = 25 check

1 baku-fixnum 2 baku-fixnum baku-cons
1 baku-fixnum 3 baku-fixnum baku-cons
baku-prim-eq baku-false = 26 check

1 baku-fixnum 2 baku-fixnum 3 baku-fixnum vec3
1 baku-fixnum 2 baku-fixnum 3 baku-fixnum vec3
baku-prim-eq baku-true = 27 check

1 baku-fixnum 2 baku-fixnum 3 baku-fixnum vec3
1 baku-fixnum 2 baku-fixnum 4 baku-fixnum vec3
baku-prim-eq baku-false = 28 check

0 baku-vector 0 baku-vector baku-prim-eq baku-true = 29 check
2 baku-vector 3 baku-vector baku-prim-eq baku-false = 30 check

\ Nested vectors re-enter the equality helper; the outer element state must
\ survive the inner comparison.
nested-vec nested-vec baku-prim-eq baku-true = 31 check
nested-vec nested-vec-other baku-prim-eq baku-false = 32 check

s" foo" baku-intern s" foo" baku-string baku-prim-eq baku-false = 33 check
s" a" baku-string 1 baku-fixnum baku-prim-eq baku-false = 34 check

1 baku-fixnum baku-prim-number? baku-true = 35 check
1e baku-float baku-prim-number? baku-true = 36 check
baku-true baku-prim-number? baku-false = 37 check
s" a" baku-string baku-prim-number? baku-false = 38 check

\ ---------------------------------------------------------------------------
\ Through the evaluator: registration and dispatch
\ ---------------------------------------------------------------------------

s" (+ 1 2)" run baku-fixnum-value 3 = 39 check
s" (+ 1 2.5)" run baku-float@ 3.5e 0.000001e f~ 40 check
s" (- 10 3.5)" run baku-float@ 6.5e 0.000001e f~ 41 check
s" (* 2 2.5)" run baku-float@ 5e 0.000001e f~ 42 check

s" (/ 8 2)" run dup baku-fixnum? 43 check
baku-fixnum-value 4 = 44 check
s" (/ 9 2)" run baku-float@ 4.5e 0.000001e f~ 45 check
s" (/ 1 0)" baku-division-by-zero 46 check-error
s" (trap-error (/ 1 0) (lambda E 99))" run baku-fixnum-value 99 = 47 check

s" (< 1 2)" run baku-true = 48 check
s" (< 2 1)" run baku-false = 49 check
s" (< -1 0)" run baku-true = 50 check
s" (> 2 1)" run baku-true = 51 check
s" (>= 2 2)" run baku-true = 52 check
s" (<= 2 1)" run baku-false = 53 check
s" (< 1 1.5)" run baku-true = 54 check
s" (> 1.5 1)" run baku-true = 55 check
s" (>= 2 2.0)" run baku-true = 56 check
s" (<= 2.5 2)" run baku-false = 57 check

s" (= 1 1)" run baku-true = 58 check
s" (= 1 2)" run baku-false = 59 check
s" (= 1 1.0)" run baku-true = 60 check
s" (= 1.0 1)" run baku-true = 61 check
s" (= 1.5 1)" run baku-false = 62 check
s" (= foo foo)" run baku-true = 63 check
s" (= foo bar)" run baku-false = 64 check
s" (= () ())" run baku-true = 65 check
s" (= () false)" run baku-false = 66 check
s" (= true false)" run baku-false = 67 check

\ Closures have no Shen equality; comparison is false, never an error.  ShenDoc
\ says a closure compares false even with itself, so the identity shortcut must
\ not apply.
s" (= (lambda X X) (lambda X X))" run baku-false = 68 check
s" (= (lambda X X) 1)" run baku-false = 69 check
s" (let F (lambda X X) (= F F))" run baku-false = 79 check

s" (number? 1)" run baku-true = 70 check
s" (number? -1.5)" run baku-true = 71 check
s" (number? true)" run baku-false = 72 check
s" (number? (lambda X X))" run baku-false = 73 check

\ Type errors through the evaluator are catchable by a Shen handler and leave
\ the interpreter usable.
s" (+ 1 true)" baku-eval-type 74 check-error
s" (trap-error (+ 1 true) (lambda E 98))" run baku-fixnum-value 98 = 75 check
s" (< foo 1)" baku-eval-type 76 check-error
s" (+ 2 3)" run baku-fixnum-value 5 = 77 check

\ The only exact integer quotient outside the fixnum range is min / -1.
baku-fixnum-min baku-fixnum -1 baku-fixnum
' baku-prim-div prim-error baku-arithmetic-overflow = 78 check

\ ---------------------------------------------------------------------------
\ Cons and the host classifiers
\ ---------------------------------------------------------------------------

\ Catch a failure of a unary primitive and return its THROW code.
: prim-error-1 ( a xt -- code )
	catch >r drop r> ;

: a-number ( -- x ) 5 baku-fixnum ;
: a-string ( -- x ) s" xyz" baku-string ;
: a-cons ( -- x ) 1 baku-fixnum 2 baku-fixnum baku-cons ;
: a-vector ( -- x ) 3 baku-vector ;

\ cons/decompose directly.
a-cons
dup baku-prim-cons? baku-true = 80 check
dup baku-prim-hd baku-fixnum-value 1 = 81 check
baku-prim-tl baku-fixnum-value 2 = 82 check

\ cons/decompose through the evaluator.
s" (cons 1 2)" run dup baku-prim-cons? baku-true = 83 check
dup baku-prim-hd baku-fixnum-value 1 = 84 check
baku-prim-tl baku-fixnum-value 2 = 85 check

\ A proper list decomposes at both levels.
s" (hd (cons 1 (cons 2 ())))" run baku-fixnum-value 1 = 86 check
s" (tl (cons 1 (cons 2 ())))" run baku-hd baku-fixnum-value 2 = 87 check

\ Improper lists keep the second argument as the tail, not the empty list.
s" (tl (cons 1 2))" run baku-fixnum-value 2 = 88 check

\ cons? rejects every non-cons; the empty list is not a cons.
baku-nil baku-prim-cons? baku-false = 89 check
a-number baku-prim-cons? baku-false = 90 check
a-string baku-prim-cons? baku-false = 91 check
a-vector baku-prim-cons? baku-false = 92 check

\ hd/tl on a non-cons are catchable type errors and leave the interpreter usable.
a-number ' baku-prim-hd prim-error-1 baku-eval-type = 93 check
a-string ' baku-prim-tl prim-error-1 baku-eval-type = 94 check
s" (hd 1)" baku-eval-type 95 check-error
s" (tl ())" baku-eval-type 96 check-error
s" (+ 1 2)" run baku-fixnum-value 3 = 97 check

\ Each host classifier accepts its own kind and rejects one value of every other
\ kind, so a classifier cannot silently accept an object with a different type.
a-number baku-prim-number? baku-true = 98 check
a-string baku-prim-number? baku-false = 99 check
a-cons baku-prim-number? baku-false = 100 check
a-vector baku-prim-number? baku-false = 101 check

a-number baku-prim-string? baku-false = 102 check
a-string baku-prim-string? baku-true = 103 check
a-cons baku-prim-string? baku-false = 104 check
a-vector baku-prim-string? baku-false = 105 check

a-number baku-prim-cons? baku-false = 106 check
a-string baku-prim-cons? baku-false = 107 check
a-cons baku-prim-cons? baku-true = 108 check
a-vector baku-prim-cons? baku-false = 109 check

a-number baku-prim-absvector? baku-false = 110 check
a-string baku-prim-absvector? baku-false = 111 check
a-cons baku-prim-absvector? baku-false = 112 check
a-vector baku-prim-absvector? baku-true = 113 check

\ Immediates are none of the four host object kinds.
baku-nil baku-prim-number? baku-false = 114 check
baku-nil baku-prim-string? baku-false = 115 check
baku-nil baku-prim-absvector? baku-false = 116 check
baku-true baku-prim-cons? baku-false = 117 check
baku-false baku-prim-number? baku-false = 118 check

\ The classifiers are registered, return Shen Booleans and use arity 1.
s" (cons? (cons 1 2))" run baku-true = 119 check
s" (cons? ())" run baku-false = 120 check
s" (string? 1)" run baku-false = 121 check
s" (absvector? 1)" run baku-false = 122 check


\ ---------------------------------------------------------------------------
\ String primitives
\ ---------------------------------------------------------------------------

s" ab" baku-string s" cd" baku-string baku-prim-cn s" abcd" test-str= 123 check
0 0 baku-string s" x" baku-string baku-prim-cn s" x" test-str= 124 check
s" x" baku-string 0 0 baku-string baku-prim-cn s" x" test-str= 125 check
1 baku-fixnum s" x" baku-string ' baku-prim-cn prim-error baku-eval-type = 126 check
s" x" baku-string 1 baku-fixnum ' baku-prim-cn prim-error baku-eval-type = 127 check

s" abc" baku-string 0 baku-fixnum baku-prim-pos s" a" test-str= 128 check
s" abc" baku-string 2 baku-fixnum baku-prim-pos s" c" test-str= 129 check
s" abc" baku-string 3 baku-fixnum ' baku-prim-pos prim-error baku-string-bounds-error = 130 check
s" abc" baku-string -1 baku-fixnum ' baku-prim-pos prim-error baku-string-bounds-error = 131 check
1 baku-fixnum 0 baku-fixnum ' baku-prim-pos prim-error baku-eval-type = 132 check
s" abc" baku-string baku-true ' baku-prim-pos prim-error baku-eval-type = 133 check

s" abc" baku-string baku-prim-tlstr s" bc" test-str= 134 check
s" a" baku-string baku-prim-tlstr 0 0 baku-string baku-prim-eq baku-true = 135 check
0 0 baku-string ' baku-prim-tlstr prim-error-1 baku-string-bounds-error = 136 check
1 baku-fixnum ' baku-prim-tlstr prim-error-1 baku-eval-type = 137 check

s" A" baku-string baku-prim-string->n baku-fixnum-value 65 = 138 check
s" abc" baku-string baku-prim-string->n baku-fixnum-value 97 = 139 check
0 0 baku-string ' baku-prim-string->n prim-error-1 baku-string-bounds-error = 140 check
1 baku-fixnum ' baku-prim-string->n prim-error-1 baku-eval-type = 141 check

65 baku-fixnum baku-prim-n->string s" A" test-str= 142 check
10 baku-fixnum baku-prim-n->string
dup baku-string-length 1 = 143 check
0 baku-string@ 10 = 144 check
0 baku-fixnum baku-prim-n->string
dup baku-string-length 1 = 145 check
0 baku-string@ 0 = 146 check
256 baku-fixnum ' baku-prim-n->string prim-error-1 baku-invalid-argument = 147 check
-1 baku-fixnum ' baku-prim-n->string prim-error-1 baku-invalid-argument = 148 check
baku-true ' baku-prim-n->string prim-error-1 baku-eval-type = 149 check

42 baku-fixnum baku-prim-str s" 42" test-str= 150 check
-7 baku-fixnum baku-prim-str s" -7" test-str= 151 check
0 baku-fixnum baku-prim-str s" 0" test-str= 152 check
1.5e baku-float baku-prim-str s" 1.5" test-str= 153 check
1e baku-float baku-prim-str s" 1.0" test-str= 154 check
3.1415926535897e baku-float baku-prim-str s" 3.1415926535897" test-str= 155 check
s" foo" baku-intern baku-prim-str s" foo" test-str= 156 check
baku-true baku-prim-str s" true" test-str= 157 check
baku-false baku-prim-str s" false" test-str= 158 check

s" hi" baku-string baku-prim-str
dup baku-string-length 4 = 159 check
dup 0 baku-string@ 34 = 160 check
dup 1 baku-string@ 104 = 161 check
3 baku-string@ 34 = 162 check

baku-nil ' baku-prim-str prim-error-1 baku-eval-type = 163 check
1 baku-fixnum 2 baku-fixnum baku-cons ' baku-prim-str prim-error-1 baku-eval-type = 164 check
3 baku-vector ' baku-prim-str prim-error-1 baku-eval-type = 165 check

\ Through the evaluator: registration, arity and Shen-visible results.
s" (cn (str foo) (str bar))" run s" foobar" test-str= 166 check
s" (pos (str foo) 1)" run s" o" test-str= 167 check
s" (tlstr (str foo))" run s" oo" test-str= 168 check
s" (string->n (pos (str A) 0))" run baku-fixnum-value 65 = 169 check
s" (n->string 65)" run s" A" test-str= 170 check
s" (str 42)" run s" 42" test-str= 171 check
s" (str foo)" run s" foo" test-str= 172 check
s" (str true)" run s" true" test-str= 173 check
s" (str false)" run s" false" test-str= 174 check
s" (str 1.5)" run s" 1.5" test-str= 175 check
s" (trap-error (pos (str foo) 9) (lambda E 99))" run baku-fixnum-value 99 = 176 check
s" (trap-error (cn 1 2) (lambda E 99))" run baku-fixnum-value 99 = 177 check
s" (trap-error (string->n 1) (lambda E 99))" run baku-fixnum-value 99 = 178 check
s" (trap-error (str (cons 1 2)) (lambda E 99))" run baku-fixnum-value 99 = 179 check
s" (+ 1 2)" run baku-fixnum-value 3 = 180 check

\ ---------------------------------------------------------------------------
\ Vector primitives
\ ---------------------------------------------------------------------------

\ An absvector of N cells is zero-filled and indexes 0 .. N-1.
3 baku-fixnum baku-prim-absvector
dup baku-prim-absvector? baku-true = 181 check
dup baku-vector-length 3 = 182 check
dup 0 baku-vector@ 0 = 183 check
2 baku-vector@ 0 = 184 check
0 baku-fixnum baku-prim-absvector baku-vector-length 0 = 185 check

\ address-> writes in place and returns the same object.
: test-vector-address ( -- )
	2 baku-fixnum baku-prim-absvector >r
	r@ 0 baku-fixnum 42 baku-fixnum baku-prim-address-> r@ = 186 check
	r@ 0 baku-fixnum baku-prim-<-address baku-fixnum-value 42 = 187 check
	r@ 1 baku-fixnum baku-prim-<-address 0 = 188 check
	r> drop ;

test-vector-address

\ Catch a failure of a ternary primitive and return its THROW code.
: prim-error-3 ( a b c xt -- code )
	catch >r 2drop drop r> ;

\ An index outside the vector is a catchable bounds error; the vector is
\ unchanged because the address check runs before the store.
a-vector 3 baku-fixnum ' baku-prim-<-address prim-error
	baku-vector-bounds-error = 189 check
a-vector -1 baku-fixnum ' baku-prim-<-address prim-error
	baku-vector-bounds-error = 190 check
a-vector 3 baku-fixnum 9 baku-fixnum ' baku-prim-address-> prim-error-3
	baku-vector-bounds-error = 191 check
a-vector -1 baku-fixnum 9 baku-fixnum ' baku-prim-address-> prim-error-3
	baku-vector-bounds-error = 192 check
a-vector 0 baku-fixnum baku-vector@ 0 = 193 check

\ A non-vector and a non-fixnum index are catchable type errors.
a-number 0 baku-fixnum ' baku-prim-<-address prim-error
	baku-eval-type = 194 check
a-vector baku-true ' baku-prim-<-address prim-error
	baku-eval-type = 195 check
a-string 0 baku-fixnum 1 baku-fixnum ' baku-prim-address-> prim-error-3
	baku-eval-type = 196 check
a-number 0 baku-fixnum 1 baku-fixnum ' baku-prim-address-> prim-error-3
	baku-eval-type = 197 check

baku-true ' baku-prim-absvector prim-error-1 baku-eval-type = 198 check
-1 baku-fixnum ' baku-prim-absvector prim-error-1
	baku-invalid-argument = 199 check

\ Through the evaluator: registration, arity and Shen-visible results.
s" (absvector? (absvector 3))" run baku-true = 200 check
s" (= (<-address (address-> (absvector 2) 0 5) 0) 5)" run baku-true = 201 check
s" (let V (absvector 2) (= V (address-> V 0 7)))" run baku-true = 202 check
s" (<-address (address-> (absvector 2) 1 6) 1)" run baku-fixnum-value 6 = 203 check
s" (trap-error (<-address (absvector 2) 5) (lambda E 99))" run
	baku-fixnum-value 99 = 204 check
s" (trap-error (address-> 1 0 2) (lambda E 98))" run
	baku-fixnum-value 98 = 205 check
s" (trap-error (absvector true) (lambda E 97))" run
	baku-fixnum-value 97 = 206 check
s" (+ 1 2)" run baku-fixnum-value 3 = 207 check

\ ---------------------------------------------------------------------------
\ Symbol primitive
\ ---------------------------------------------------------------------------

s" foo" baku-string baku-prim-intern baku-symbol? 208 check
s" foo" baku-string baku-prim-intern s" foo" baku-intern = 209 check
s" foo" baku-string baku-prim-intern
	s" foo" baku-string baku-prim-intern = 210 check

\ Interning is case-sensitive and treats _ and - as distinct characters.
s" Foo" baku-string baku-prim-intern s" foo" baku-intern = 0= 211 check
s" a_b" baku-string baku-prim-intern s" a-b" baku-intern = 0= 212 check
s" ;" baku-string baku-prim-intern baku-prim-str s" ;" test-str= 213 check

\ The names TRUE and FALSE denote the reserved immediates, exactly as the reader
\ maps the same tokens, so a string round-trip cannot create a second meaning.
s" true" baku-string baku-prim-intern baku-true = 214 check
s" false" baku-string baku-prim-intern baku-false = 215 check
s" true" baku-string baku-prim-intern baku-symbol? 0= 216 check

\ A non-string argument is a catchable type error at both boundaries.
1 baku-fixnum ' baku-prim-intern prim-error-1 baku-eval-type = 217 check
s" (trap-error (intern 1) (lambda E 99))" run
	baku-fixnum-value 99 = 218 check

\ Through the evaluator: registration, identity and the empty name.
s" (intern (str foo))" run s" foo" baku-intern = 219 check
s" (= (intern (str foo)) (intern (str foo)))" run baku-true = 220 check
0 0 baku-intern s" " baku-string baku-prim-intern = 221 check
s" (intern (str true))" run baku-true = 222 check

." BAKU-TEST-DONE" cr
