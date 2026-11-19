\ Baku KLambda reader.
\
\ Reads the pinned Shen 43.2 .kl sources into Baku values.  This is the KLambda
\ text reader only; the Shen reader in the kernel is a different component and
\ is not reimplemented here.
\
\ The reader is streaming at the form level: BAKU-READ-FORM returns one
\ top-level form and allocates its tree in a scratch region.  The next call
\ resets that region, so a form is valid only until the next read.  Symbols are
\ interned in the permanent non-GC heap and survive the reset.  This is what
\ keeps the peak memory at the largest single form instead of the whole corpus.
\
\ Strings are literal: '"' terminates, a backslash is data, embedded newlines
\ are data, and no Forth/JSON escape sequences are decoded.  Comments are Shen's
\ '\\' line comment and '\* ... *\' block comment.  ';' and '#' are symbol
\ characters.

-268 constant baku-read-eof
-269 constant baku-read-syntax
-270 constant baku-read-number

\ ---------------------------------------------------------------------------
\ Source: a file read in chunks, or an in-memory string
\ ---------------------------------------------------------------------------

1 constant baku-src-file
2 constant baku-src-string

4096 constant baku-src-buffer-size
512 constant baku-src-name-max

create baku-src-buffer baku-src-buffer-size allot
create baku-src-name baku-src-name-max allot

variable baku-src-kind
variable baku-src-fileid
variable baku-src-open
variable baku-src-addr
variable baku-src-len
variable baku-src-pos
variable baku-src-line
variable baku-src-col
variable baku-src-peek-char
variable baku-src-has-peek
variable baku-src-name-len

: baku-src-set-name ( c-addr u -- )
	dup baku-src-name-max > if
		2drop s" (name too long)"
	then
	dup baku-src-name-len !
	baku-src-name swap cmove ;

: baku-read-source-name ( -- c-addr u )
	baku-src-name baku-src-name-len @ ;

: baku-read-line ( -- n ) baku-src-line @ ;
: baku-read-col ( -- n ) baku-src-col @ ;

: baku-src-close ( -- )
	baku-src-open @ if
		baku-src-fileid @ close-file throw
		0 baku-src-open !
	then ;

: baku-src-reset ( kind -- )
	baku-src-kind !
	0 baku-src-pos !
	1 baku-src-line !
	1 baku-src-col !
	0 baku-src-has-peek ! ;

: baku-read-file ( c-addr u -- )
	2dup baku-src-set-name
	baku-src-close
	r/o bin open-file throw
	baku-src-fileid !
	1 baku-src-open !
	baku-src-file baku-src-reset
	baku-src-buffer baku-src-addr !
	0 baku-src-len ! ;

: baku-read-string ( c-addr u -- )
	baku-src-close
	2dup baku-src-len !
	baku-src-addr !
	2drop
	s" (string)" baku-src-set-name
	baku-src-string baku-src-reset ;

: baku-read-close ( -- ) baku-src-close ;

: baku-src-refill ( -- flag )
	baku-src-kind @ baku-src-file = if
		baku-src-buffer baku-src-buffer-size baku-src-fileid @ read-file throw
		dup baku-src-len !
		0= if false exit then
		baku-src-buffer baku-src-addr !
		0 baku-src-pos !
		true
	else
		false
	then ;

: baku-src-raw ( -- char true | false )
	baku-src-kind @ baku-src-file = if
		begin
			baku-src-pos @ baku-src-len @ >=
		while
			baku-src-refill 0= if false exit then
		repeat
	then
	baku-src-pos @ baku-src-len @ >= if false exit then
	baku-src-addr @ baku-src-pos @ + c@
	baku-src-pos @ 1+ baku-src-pos !
	true ;

: baku-src-advance ( c -- )
	dup 10 = if
		drop
		baku-src-line @ 1+ baku-src-line !
		1 baku-src-col !
	else
		drop
		1 baku-src-col +!
	then ;

: baku-src-peek ( -- char true | false )
	baku-src-has-peek @ 0= if
		baku-src-raw if
			baku-src-peek-char !
			1 baku-src-has-peek !
		then
	then
	baku-src-has-peek @ if
		baku-src-peek-char @ true
	else
		false
	then ;

: baku-src-next ( -- char true | false )
	baku-src-has-peek @ if
		0 baku-src-has-peek !
		baku-src-peek-char @ dup baku-src-advance true
	else
		baku-src-raw if
			dup baku-src-advance true
		else
			false
		then
	then ;

: baku-src-eat ( -- ) baku-src-next 2drop ;

: baku-whitespace? ( c -- flag )
	dup 32 = if drop true exit then
	dup 9 = if drop true exit then
	dup 10 = if drop true exit then
	13 = ;

: baku-digit? ( c -- flag )
	dup 48 >= swap 57 <= and ;

\ ---------------------------------------------------------------------------
\ Errors
\ ---------------------------------------------------------------------------

: baku-reader-message ( code -- code )
	dup baku-read-eof = if ." unexpected end of input" else
	dup baku-read-syntax = if ." syntax error" else
	dup baku-read-number = if ." number out of range" else
	." reader error"
	then then then ;

: baku-reader-fail ( code -- )
	." Baku reader error at " baku-read-source-name type
	." :" baku-read-line . ." :" baku-read-col . ." : "
	baku-reader-message
	cr throw ;

\ ---------------------------------------------------------------------------
\ Comments and whitespace
\ ---------------------------------------------------------------------------

: baku-skip-line-comment ( -- )
	begin
		baku-src-next 0= if exit then
		dup 10 = if drop exit then
		drop
	again ;

variable baku-comment-star

: baku-skip-block-comment ( -- )
	0 baku-comment-star !
	begin
		baku-src-next 0= if baku-read-eof baku-reader-fail then
		dup 92 = if
			baku-comment-star @ if drop exit then
			drop 0 baku-comment-star !
		else
			dup 42 = if 1 else 0 then baku-comment-star !
			drop
		then
	again ;

: baku-skip ( -- )
	begin
		baku-src-peek 0= if exit then
		dup baku-whitespace? if
			drop baku-src-eat
		else
			dup 92 = if
				drop
				baku-src-eat
				baku-src-peek 0= if baku-read-eof baku-reader-fail then
				dup 92 = if
					drop baku-src-eat baku-skip-line-comment
				else
					dup 42 = if
						drop baku-src-eat baku-skip-block-comment
					else
						baku-read-syntax baku-reader-fail
					then
				then
			else
				drop exit
			then
		then
	again ;

\ ---------------------------------------------------------------------------
\ Growable byte builder for atoms and string literals
\
\ The builder allocates a capacity-sized string object from the selected heap
\ and rewrites the header to the exact length when finalised.  Strings and atoms
\ never nest, so one builder is enough: finalising a string marks the builder so
\ the next atom starts a fresh buffer instead of overwriting the string.
\ ---------------------------------------------------------------------------

variable baku-buf-addr
variable baku-buf-cap
variable baku-buf-len
variable baku-buf-finalized

: baku-buf-reset ( -- )
	0 baku-buf-addr !
	0 baku-buf-cap !
	0 baku-buf-len !
	0 baku-buf-finalized ! ;

variable baku-buf-newcap

: baku-buf-ensure ( n -- )
	baku-buf-cap @ over >= if drop exit then
	dup baku-buf-newcap !
	baku-buf-cap @ 2* baku-buf-newcap @ > if
		baku-buf-cap @ 2* baku-buf-newcap !
	then
	baku-buf-newcap @ 256 < if
		256 baku-buf-newcap !
	then
	baku-buf-newcap @ >r
	drop
	r@ baku-type-string baku-alloc
	dup >r
	baku-buf-addr @ if
		baku-buf-addr @ cell + r@ cell + baku-buf-len @ cmove
	then
	drop
	r> baku-buf-addr !
	r> baku-buf-cap ! ;

: baku-buf-put ( c -- )
	baku-buf-len @ 1+ baku-buf-ensure
	baku-buf-addr @ cell + baku-buf-len @ + c!
	baku-buf-len @ 1+ baku-buf-len ! ;

: baku-buf-addr@ ( -- c-addr ) baku-buf-addr @ cell + ;
: baku-buf-len@ ( -- u ) baku-buf-len @ ;

: baku-buf-finalize ( -- obj )
	baku-buf-addr @ 0= if 1 baku-buf-ensure then
	baku-buf-len @ baku-buf-addr @ baku-object-size!
	1 baku-buf-finalized !
	baku-buf-addr @ ;

: baku-buf-begin-atom ( -- )
	baku-buf-finalized @ if baku-buf-reset then
	0 baku-buf-len ! ;

\ ---------------------------------------------------------------------------
\ Atoms: integers, floats, symbols, booleans
\ ---------------------------------------------------------------------------

variable baku-lit-addr
variable baku-lit-len

: baku-token= ( addr u lit-addr lit-u -- flag )
	baku-lit-len ! baku-lit-addr !
	dup baku-lit-len @ <> if 2drop false exit then
	baku-lit-addr @ swap baku-bytes= ;

: baku-delimiter? ( c -- flag )
	dup baku-whitespace? if drop true exit then
	dup 40 = if drop true exit then
	dup 41 = if drop true exit then
	dup 34 = if drop true exit then
	92 = ;

variable baku-int-addr
variable baku-int-len
variable baku-int-neg

: baku-int-digits? ( c-addr u -- flag )
	0 ?do
		dup c@ baku-digit? 0= if drop false unloop exit then
		char+
	loop drop true ;

: baku-parse-integer ( addr u -- n true | false )
	baku-int-len ! baku-int-addr !
	0 baku-int-neg !
	baku-int-len @ 0= if false exit then
	baku-int-addr @ c@
	dup 45 = if
		drop 1 baku-int-neg !
		baku-int-addr @ 1+ baku-int-addr !
		baku-int-len @ 1- baku-int-len !
	else
		43 = if
			baku-int-addr @ 1+ baku-int-addr !
			baku-int-len @ 1- baku-int-len !
		then
	then
	baku-int-len @ 0= if false exit then
	baku-int-addr @ baku-int-len @ baku-int-digits? 0= if false exit then
	base @ >r 10 base !
	0 0 baku-int-addr @ baku-int-len @ >number
	r> base !
	nip 0= if
		baku-int-neg @ if dnegate then
		2dup baku-fixnum-min s>d d< if 2drop baku-read-number baku-reader-fail then
		2dup baku-fixnum-max s>d 2swap d< if 2drop baku-read-number baku-reader-fail then
		drop baku-fixnum true
	else
		2drop false
	then ;

variable baku-fp-addr
variable baku-fp-len
variable baku-fp-pos
variable baku-fp-neg
variable baku-fp-mant
variable baku-fp-frac
variable baku-fp-exp
variable baku-fp-exp-neg
variable baku-fp-seen-dot
variable baku-fp-seen-exp
variable baku-fp-seen-digit
variable baku-fp-exp-digit

: baku-fp-char ( -- c ) baku-fp-addr @ baku-fp-pos @ + c@ ;
: baku-fp-more? ( -- flag ) baku-fp-pos @ baku-fp-len @ < ;
: baku-fp-take ( -- ) 1 baku-fp-pos +! ;

: baku-fp-add-mantissa ( c -- )
	48 -
	baku-fp-mant @ 10 M*
	dup 0<> if 2drop baku-read-number baku-reader-fail then
	drop + baku-fp-mant ! ;

: baku-fp-scale ( n -- ) ( F: r -- r' )
	dup 0< if negate 0 ?do 10e f/ loop else 0 ?do 10e f* loop then ;

: baku-parse-float ( addr u -- value true | false )
	baku-fp-len ! baku-fp-addr !
	0 baku-fp-pos !
	0 baku-fp-neg !
	0 baku-fp-mant !
	0 baku-fp-frac !
	0 baku-fp-exp !
	0 baku-fp-exp-neg !
	0 baku-fp-seen-dot !
	0 baku-fp-seen-exp !
	0 baku-fp-seen-digit !
	0 baku-fp-exp-digit !
	baku-fp-len @ 0= if false exit then
	baku-fp-more? if
		baku-fp-char
		dup 45 = if drop 1 baku-fp-neg ! baku-fp-take
		else 43 = if baku-fp-take then then
	then
	begin
		baku-fp-more? if baku-fp-char baku-digit? else false then
	while
		baku-fp-char baku-fp-add-mantissa
		1 baku-fp-seen-digit !
		baku-fp-take
	repeat
	baku-fp-more? if
		baku-fp-char 46 = if
			baku-fp-take
			1 baku-fp-seen-dot !
			begin
				baku-fp-more? if baku-fp-char baku-digit? else false then
			while
				baku-fp-char baku-fp-add-mantissa
				baku-fp-frac @ 1+ baku-fp-frac !
				1 baku-fp-seen-digit !
				baku-fp-take
			repeat
		then
	then
	baku-fp-more? if
		baku-fp-char dup 101 = swap 69 = or if
			baku-fp-take
			1 baku-fp-seen-exp !
			baku-fp-more? if
				baku-fp-char
				dup 45 = if drop 1 baku-fp-exp-neg ! baku-fp-take
				else 43 = if baku-fp-take then then
			then
			begin
				baku-fp-more? if baku-fp-char baku-digit? else false then
			while
				baku-fp-char 48 -
				baku-fp-exp @ 10 * +
				baku-fp-exp !
				1 baku-fp-exp-digit !
				baku-fp-take
			repeat
		then
	then
	baku-fp-pos @ baku-fp-len @ <> if false exit then
	baku-fp-seen-digit @ 0= if false exit then
	baku-fp-seen-dot @ baku-fp-seen-exp @ or 0= if false exit then
	baku-fp-seen-exp @ if baku-fp-exp-digit @ 0= if false exit then then
	baku-fp-mant @ s>f
	baku-fp-exp @ baku-fp-exp-neg @ if negate then
	baku-fp-frac @ - baku-fp-scale
	baku-fp-neg @ if fnegate then
	baku-float true ;

: baku-atom->value ( -- value )
	baku-buf-addr@ baku-buf-len@
	baku-immediate-name if exit then
	baku-buf-addr@ baku-buf-len@
	2dup baku-parse-integer if rot drop nip exit then
	2dup baku-parse-float if rot drop nip exit then
	baku-intern ;

variable baku-atom-done

: baku-read-atom ( -- value )
	baku-buf-begin-atom
	0 baku-atom-done !
	begin
		baku-atom-done @ 0=
	while
		baku-src-peek if
			dup baku-delimiter? if
				drop 1 baku-atom-done !
			else
				drop
				baku-src-next drop
				baku-buf-put
			then
		else
			1 baku-atom-done !
		then
	repeat
	baku-buf-len @ 0= if baku-read-syntax baku-reader-fail then
	baku-atom->value ;

\ ---------------------------------------------------------------------------
\ Lists and strings
\ ---------------------------------------------------------------------------

variable baku-rev-prev
variable baku-rev-cur
variable baku-rev-next

: baku-list-reverse ( rev -- list )
	baku-rev-cur !
	baku-nil baku-rev-prev !
	begin
		baku-rev-cur @ baku-cons?
	while
		baku-rev-cur @ baku-tl baku-rev-next !
		baku-rev-prev @ baku-rev-cur @ baku-set-tl
		baku-rev-cur @ baku-rev-prev !
		baku-rev-next @ baku-rev-cur !
	repeat
	baku-rev-prev @ ;

defer baku-read-value

: baku-read-list ( -- list )
	baku-nil
	begin
		baku-skip
		baku-src-peek 0= if baku-read-eof baku-reader-fail then
		dup 41 = if
			drop
			baku-src-eat
			baku-list-reverse
			exit
		then
		drop
		baku-read-value
		swap baku-cons
	again ;

: baku-read-string-literal ( -- obj )
	baku-buf-reset
	begin
		baku-src-next 0= if baku-read-eof baku-reader-fail then
		dup 34 = if drop baku-buf-finalize exit then
		baku-buf-put
	again ;

: baku-read-value-real ( -- value )
	baku-skip
	baku-src-peek 0= if baku-read-eof baku-reader-fail then
	dup 40 = if drop baku-src-eat baku-read-list exit then
	dup 34 = if drop baku-src-eat baku-read-string-literal exit then
	dup 41 = if drop baku-read-syntax baku-reader-fail then
	drop
	baku-read-atom ;

' baku-read-value-real is baku-read-value

: baku-read-form-inner ( -- form flag )
	baku-skip
	baku-src-peek 0= if baku-nil false exit then
	drop
	baku-read-value true ;

\ ---------------------------------------------------------------------------
\ Scratch heap and the form-level entry points
\ ---------------------------------------------------------------------------

\ The largest pinned form (stlib.initialise-sources) is about 45k cons cells
\ plus strings, roughly 1.1 MiB.  2 MiB bounds one form with headroom.
2097152 constant baku-reader-scratch-size

align create baku-reader-scratch baku-reader-scratch-size allot align

variable baku-scratch-here
variable baku-scratch-end

: baku-use-scratch ( -- )
	baku-scratch-here baku-scratch-end baku-use-heap ;

variable baku-reader-saved-here
variable baku-reader-saved-end

: baku-read-form ( -- form flag )
	baku-heap-save
	baku-reader-saved-end ! baku-reader-saved-here !
	baku-reader-scratch baku-scratch-here !
	baku-buf-reset
	baku-use-scratch
	['] baku-read-form-inner catch
	baku-reader-saved-here @ baku-reader-saved-end @ baku-use-heap
	?dup if throw then ;

variable baku-read-all-xt

: baku-read-all ( xt -- )
	baku-read-all-xt !
	begin
		baku-read-form
	while
		baku-read-all-xt @ execute
	repeat
	drop ;

: baku-reader-init ( -- )
	baku-reader-scratch baku-scratch-here !
	baku-reader-scratch baku-reader-scratch-size + baku-scratch-end !
	baku-reader-scratch baku-scratch-here baku-region-scratch baku-region+ drop
	0 baku-src-open !
	0 baku-src-kind !
	0 baku-src-has-peek !
	0 baku-src-len !
	0 baku-src-pos !
	1 baku-src-line !
	1 baku-src-col !
	baku-src-buffer baku-src-addr !
	s" (no source)" baku-src-set-name
	baku-buf-reset
	baku-use-nongc ;

baku-reader-init
