\ Baku KLambda compiler front end.
\
\ The reader produces the raw form tree.  This layer validates it and lowers it
\ into an intermediate representation consumed by the interpreter.  Tail-position
\ analysis lives here; the front end and the vector IR are retained as the base
\ for a future compiler.
\
\ An IR node is a Baku vector:
\
\   [ kind, tail, payload... ]
\
\ TAIL is BAKU-TRUE or BAKU-FALSE.  It is the flag a consumer needs to emit a
\ self-tail loop or a trampoline call.  Function bodies (lambda, defun and
\ freeze) are always tail positions because they are the value a call returns.
\
\ Tail rules:
\   if          test not tail; then and else inherit the node's tail
\   and, or     left not tail; right inherits the node's tail
\   cond        each test not tail; each result inherits the node's tail
\   let         bound expression not tail; body inherits the node's tail
\   lambda      body is tail
\   defun       body is tail
\   freeze      body is tail
\   trap-error  protected form inherits the node's tail; handler expression is
\               evaluated before the protected form and is not a tail call.
\               The handler's own body is a tail position because it is a lambda.
\   call        operator and arguments are not tail; the call inherits the
\               node's tail.  DO is an ordinary kernel function in 43.2, so a DO
\               form is a call whose arguments all keep ordinary call semantics.
\
\ Only a call can be a tail call, so atom and symbol nodes always carry
\ BAKU-FALSE.  A branch or body that ends in an atom needs no trampoline.
\
\ An IR node built from a reader form is valid only until the next read: the
\ node itself is allocated in the selected heap, but string and symbol payloads
\ in the form may point into the reader scratch region.  The caller must consume
\ or copy the node first.  The front end itself is independent of any backend.

\ ---------------------------------------------------------------------------
\ Errors
\ ---------------------------------------------------------------------------

-271 constant baku-front-malformed
-272 constant baku-front-arity

\ ---------------------------------------------------------------------------
\ IR kinds
\ ---------------------------------------------------------------------------

0 constant baku-ir-atom
1 constant baku-ir-symbol
2 constant baku-ir-call
3 constant baku-ir-if
4 constant baku-ir-and
5 constant baku-ir-or
6 constant baku-ir-cond
7 constant baku-ir-let
8 constant baku-ir-lambda
9 constant baku-ir-defun
10 constant baku-ir-freeze
11 constant baku-ir-trap-error

\ ---------------------------------------------------------------------------
\ Special-form names.  They are interned once; a head symbol is compared by
\ identity, which is exact because the symbol table is permanent and the reader
\ interns every spelling.
\ ---------------------------------------------------------------------------

variable baku-sym-if
variable baku-sym-and
variable baku-sym-or
variable baku-sym-cond
variable baku-sym-let
variable baku-sym-lambda
variable baku-sym-defun
variable baku-sym-freeze
variable baku-sym-trap-error
variable baku-sym-type

: baku-frontend-init ( -- )
	s" if" baku-intern baku-sym-if !
	s" and" baku-intern baku-sym-and !
	s" or" baku-intern baku-sym-or !
	s" cond" baku-intern baku-sym-cond !
	s" let" baku-intern baku-sym-let !
	s" lambda" baku-intern baku-sym-lambda !
	s" defun" baku-intern baku-sym-defun !
	s" freeze" baku-intern baku-sym-freeze !
	s" trap-error" baku-intern baku-sym-trap-error !
	s" type" baku-intern baku-sym-type ! ;

: baku-special-kind ( sym -- kind|-1 )
	dup baku-sym-if @ = if drop baku-ir-if exit then
	dup baku-sym-and @ = if drop baku-ir-and exit then
	dup baku-sym-or @ = if drop baku-ir-or exit then
	dup baku-sym-cond @ = if drop baku-ir-cond exit then
	dup baku-sym-let @ = if drop baku-ir-let exit then
	dup baku-sym-lambda @ = if drop baku-ir-lambda exit then
	dup baku-sym-defun @ = if drop baku-ir-defun exit then
	dup baku-sym-freeze @ = if drop baku-ir-freeze exit then
	dup baku-sym-trap-error @ = if drop baku-ir-trap-error exit then
	drop -1 ;

\ ---------------------------------------------------------------------------
\ IR construction and accessors
\ ---------------------------------------------------------------------------

: baku-ir-make ( n kind tail -- node )
	rot baku-vector ( kind tail node )
	>r
	swap baku-fixnum r@ 0 baku-vector!
	if baku-true else baku-false then r@ 1 baku-vector!
	r> ;

: baku-ir-kind ( node -- kind ) 0 baku-vector@ baku-fixnum-value ;
: baku-ir-tail? ( node -- flag ) 1 baku-vector@ baku-true = ;
: baku-ir-length ( node -- n ) baku-vector-length ;

\ A consumer of IR trusts the front end, but a corrupted or foreign value must
\ fail as a catchable error instead of being used as a vector header.
: baku-ir-node? ( x -- flag )
	dup baku-object? if
		dup baku-vector? if
			dup baku-vector-length 2 >= if
				dup 0 baku-vector@ baku-fixnum? if
					baku-ir-kind dup 0 >= swap 11 <= and
				else drop false then
			else drop false then
		else drop false then
	else drop false then ;

: baku-ir-value ( node -- value ) 2 baku-vector@ ;
: baku-ir-call-operator ( node -- ir ) 2 baku-vector@ ;
: baku-ir-call-arity ( node -- n ) baku-vector-length 3 - ;
: baku-ir-call-arg ( node i -- ir ) 3 + baku-vector@ ;

: baku-ir-if-test ( node -- ir ) 2 baku-vector@ ;
: baku-ir-if-then ( node -- ir ) 3 baku-vector@ ;
: baku-ir-if-else ( node -- ir ) 4 baku-vector@ ;

: baku-ir-and-left ( node -- ir ) 2 baku-vector@ ;
: baku-ir-and-right ( node -- ir ) 3 baku-vector@ ;
: baku-ir-or-left ( node -- ir ) 2 baku-vector@ ;
: baku-ir-or-right ( node -- ir ) 3 baku-vector@ ;

: baku-ir-cond-clauses ( node -- list ) 2 baku-vector@ ;

: baku-ir-let-var ( node -- sym ) 2 baku-vector@ ;
: baku-ir-let-expr ( node -- ir ) 3 baku-vector@ ;
: baku-ir-let-body ( node -- ir ) 4 baku-vector@ ;

: baku-ir-lambda-param ( node -- sym ) 2 baku-vector@ ;
: baku-ir-lambda-body ( node -- ir ) 3 baku-vector@ ;

: baku-ir-defun-name ( node -- sym ) 2 baku-vector@ ;
: baku-ir-defun-params ( node -- vector ) 3 baku-vector@ ;
: baku-ir-defun-body ( node -- ir ) 4 baku-vector@ ;

: baku-ir-freeze-body ( node -- ir ) 2 baku-vector@ ;

: baku-ir-trap-expr ( node -- ir ) 2 baku-vector@ ;
: baku-ir-trap-handler ( node -- ir ) 3 baku-vector@ ;

\ ---------------------------------------------------------------------------
\ Form list helpers.  Every malformed list is a catchable error.
\ ---------------------------------------------------------------------------

: baku-list-length ( list -- n )
	0 swap
	begin dup baku-cons? while
		baku-tl swap 1+ swap
	repeat
	baku-nil = if else baku-front-malformed throw then ;

: baku-list-nth ( list i -- value )
	begin dup 0> while
		over baku-cons? 0= if baku-front-malformed throw then
		swap baku-tl swap 1-
	repeat
	drop baku-hd ;

\ Reverse a proper list into fresh conses.  Both the source list and the
\ growing result stay on the data stack, which the collector scans, so no
\ reference is ever reachable only through the return stack.  The reader's
\ BAKU-LIST-REVERSE reverses in place, so it cannot be used on a list the
\ caller may still share.
: baku-list-copy-reverse ( list -- rev )
	baku-nil swap
	begin dup baku-cons? while
		dup baku-hd
		2 pick baku-cons
		swap baku-tl
		rot drop
	repeat
	dup baku-nil = 0= if baku-front-malformed throw then
	drop ;

\ Concatenate two proper lists, preserving source order.  The evaluator uses
\ this to accumulate the arguments of a partial application, so it lives with
\ the other shared list helpers.  Reverse-and-copy keeps every live reference
\ on the data stack across the allocations, unlike a return-stack recursion.
: baku-list-append ( a b -- a++b )
	over baku-cons? if
		swap baku-list-copy-reverse
		begin dup baku-cons? while
			dup baku-hd
			rot baku-cons
			swap baku-tl
		repeat
		dup baku-nil = 0= if baku-front-malformed throw then
		drop
	else
		over baku-nil = 0= if baku-front-malformed throw then
		nip
	then ;

\ ---------------------------------------------------------------------------
\ Recursive builders.  BAKU-FRONTEND is deferred so the helpers below and the
\ builders can call it before its definition is reached.
\ ---------------------------------------------------------------------------

defer baku-frontend

\ Partly built IR lives in the selected heap.  The Forth return stack is not a
\ GC root, so a builder must not leave a node there across a recursive call that
\ can collect.  This registered cell stack holds the current node instead; a
\ nested builder pushes its own cell and pops it before returning, so each level
\ keeps a distinct root.  BAKU-FRONT-ROOT-MAX bounds the form nesting the
\ compiler accepts; a deeper form raises a catchable region-full error.
1024 constant baku-front-root-max
create baku-front-root-cells baku-front-root-max cells allot
variable baku-front-root-depth
0 baku-front-root-depth !

: baku-front-root-push ( node -- )
	baku-front-root-depth @ baku-front-root-max >= if baku-region-full throw then
	baku-front-root-depth @ cells baku-front-root-cells + !
	1 baku-front-root-depth +! ;

: baku-front-root-pop ( -- node )
	baku-front-root-depth @ 0= if baku-region-full throw then
	-1 baku-front-root-depth +!
	baku-front-root-depth @ cells baku-front-root-cells + @ ;

: baku-front-root@ ( -- node )
	baku-front-root-depth @ 0= if baku-region-full throw then
	baku-front-root-depth @ 1- cells baku-front-root-cells + @ ;

: baku-front-root-pick ( n -- node )
	dup baku-front-root-depth @ >= if baku-region-full throw then
	baku-front-root-depth @ swap - 1- cells baku-front-root-cells + @ ;

: baku-front-nth ( form i tail -- ir )
	>r baku-list-nth r> baku-frontend ;

: baku-front-fill ( form i tail slot -- )
	>r baku-front-nth baku-front-root@ r> baku-vector! ;

\ A string literal read from the reader scratch region must be copied into the
\ selected heap before its form is released; the IR outlives the form.  Only a
\ scratch-resident string needs the copy, so a string built directly in the
\ permanent heap keeps its identity.
: baku-front-persist-string ( value -- value )
	dup baku-string? if
		dup baku-region-of baku-region-scratch = if
			dup baku-string-addr over baku-string-length baku-string nip
		then
	then ;

\ A boxed float has the same lifetime hazard as a string literal: the reader
\ allocates it in scratch, while the IR outlives the form.  Copy a
\ scratch-resident float into the selected heap; a float already in the permanent
\ or GC heap keeps its identity.
: baku-front-persist-float ( value -- value )
	dup baku-float? if
		dup baku-region-of baku-region-scratch = if
			dup baku-float@ baku-float nip
		then
	then ;

: baku-front-atom ( value -- node )
	baku-front-persist-string
	baku-front-persist-float
	dup baku-symbol? if
		3 baku-ir-symbol false baku-ir-make
	else
		3 baku-ir-atom false baku-ir-make
	then
	>r r@ 2 baku-vector! r> ;

\ Compile every argument, preserving the source order.  The result is a list of
\ IR nodes in the selected heap, later copied into the call node.
: baku-front-args ( args -- list )
	dup baku-cons? if
		dup baku-hd false baku-frontend ( args ir )
		swap baku-tl recurse ( ir rest )
		baku-cons
	else
		dup baku-nil = 0= if baku-front-malformed throw then
		drop baku-nil
	then ;

\ Copy a proper list of IR nodes into NODE starting at SLOT.  This loop never
\ recurses, so the accounting words cannot be clobbered by a nested compiler
\ call; the recursive builders above do not use them.
variable baku-copy-list
variable baku-copy-node
variable baku-copy-slot

: baku-copy-into-node ( list node slot -- )
	baku-copy-slot ! baku-copy-node ! baku-copy-list !
	begin baku-copy-list @ baku-cons? while
		baku-copy-list @ baku-hd
		baku-copy-node @ baku-copy-slot @ baku-vector!
		baku-copy-list @ baku-tl baku-copy-list !
		baku-copy-slot @ 1+ baku-copy-slot !
	repeat
	baku-copy-list @ baku-nil = 0= if baku-front-malformed throw then ;

\ The operator is compiled first and must survive the argument compilation,
\ which can collect; the root stack holds both it and the call node.
: baku-front-call ( form tail -- node )
	over baku-hd false baku-frontend ( form tail op )
	baku-front-root-push ( form tail )
	over baku-tl baku-front-args ( form tail args )
	dup baku-list-length 3 + ( form tail args size )
	baku-ir-call ( form tail args size kind )
	3 pick ( form tail args size kind tail )
	baku-ir-make ( form tail args node )
	baku-front-root-push ( form tail args )
	1 baku-front-root-pick baku-front-root@ 2 baku-vector! ( form tail args )
	baku-front-root@ 3 baku-copy-into-node ( form tail )
	baku-front-root-pop ( form tail node )
	baku-front-root-pop drop ( form tail node )
	nip nip ;

: baku-front-if ( form tail -- node )
	over baku-list-length 4 <> if baku-front-arity throw then
	5 baku-ir-if 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 false 2 baku-front-fill
	over 2 2 pick 3 baku-front-fill
	over 3 2 pick 4 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-and ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-and 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 false 2 baku-front-fill
	over 2 2 pick 3 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-or ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-or 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 false 2 baku-front-fill
	over 2 2 pick 3 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-let ( form tail -- node )
	over baku-list-length 4 <> if baku-front-arity throw then
	5 baku-ir-let 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	baku-front-root@ 2 baku-vector!
	over 2 false 3 baku-front-fill
	over 3 2 pick 4 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-lambda ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-lambda 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	baku-front-root@ 2 baku-vector!
	over 2 true 3 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-freeze ( form tail -- node )
	over baku-list-length 2 <> if baku-front-arity throw then
	3 baku-ir-freeze 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 true 2 baku-front-fill
	2drop baku-front-root-pop ;

: baku-front-trap-error ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-trap-error 2 pick baku-ir-make baku-front-root-push ( form tail )
	over 1 2 pick 2 baku-front-fill
	over 2 false 3 baku-front-fill
	2drop baku-front-root-pop ;

\ A parameter list becomes a vector of symbols so arity and binding are simple
\ consumers of the IR.  No recursive compilation happens here, so the
\ accounting words are safe.
variable baku-params-list
variable baku-params-vector
variable baku-params-slot

: baku-front-params ( list -- vector )
	dup baku-list-length baku-vector baku-params-vector !
	baku-params-list !
	0 baku-params-slot !
	begin
		baku-params-list @ baku-cons?
	while
		baku-params-list @ baku-hd
		dup baku-symbol? 0= if baku-front-malformed throw then
		baku-params-vector @ baku-params-slot @ baku-vector!
		baku-params-list @ baku-tl baku-params-list !
		baku-params-slot @ 1+ baku-params-slot !
	repeat
	baku-params-list @ baku-nil = 0= if baku-front-malformed throw then
	baku-params-vector @ ;

: baku-front-defun ( form tail -- node )
	over baku-list-length 4 <> if baku-front-arity throw then
	5 baku-ir-defun false baku-ir-make baku-front-root-push ( form tail )
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	baku-front-root@ 2 baku-vector!
	over 2 baku-list-nth baku-front-params
	baku-front-root@ 3 baku-vector!
	over 3 true 4 baku-front-fill
	2drop baku-front-root-pop ;

\ COND lowers to a node holding a list of [test, result] clause vectors.  The
\ recursive walk returns the clause list in source order; each clause vector is
\ held in the root stack while the rest of the clauses are compiled.
: baku-front-cond-clause ( clause tail -- vector )
	over baku-list-length 2 <> if baku-front-arity throw then
	over 0 false baku-front-nth ( clause tail test )
	2 pick 1 3 pick baku-front-nth ( clause tail test result )
	2 baku-vector baku-front-root-push ( clause tail test result )
	baku-front-root@ 1 baku-vector!
	baku-front-root@ 0 baku-vector!
	baku-front-root-pop ( clause tail vector )
	rot drop nip ;

: baku-front-cond-clauses ( clauses tail -- list )
	over baku-cons? if
		over baku-tl ( clauses tail rest )
		2 pick baku-hd ( clauses tail rest clause )
		2 pick baku-front-cond-clause ( clauses tail rest vector )
		baku-front-root-push ( clauses tail rest )
		swap recurse ( clauses restlist )
		baku-front-root-pop ( clauses restlist vector )
		rot drop ( restlist vector )
		swap baku-cons
	else
		over baku-nil = 0= if baku-front-malformed throw then
		2drop baku-nil
	then ;

: baku-front-cond ( form tail -- node )
	>r ( form | R: tail )
	dup baku-list-length dup 2 < if baku-front-arity throw then
	drop
	dup baku-tl ( form clauses | R: tail )
	r@ baku-front-cond-clauses ( form list | R: tail )
	swap drop ( list | R: tail )
	3 baku-ir-cond r> baku-ir-make ( list node )
	dup >r 2 baku-vector! r> ;

\ ---------------------------------------------------------------------------
\ Entry point
\ ---------------------------------------------------------------------------

variable baku-front-special

: baku-frontend-inner ( form tail -- ir )
	over baku-cons? if
		over baku-hd dup baku-symbol? if
			dup baku-sym-type @ = if
				drop
				over baku-list-length 3 <> if baku-front-arity throw then
				over baku-tl baku-hd swap baku-frontend nip exit
			then
			baku-special-kind
		else
			drop -1
		then
		dup -1 <> if
			baku-front-special !
			baku-front-special @ baku-ir-if = if baku-front-if exit then
			baku-front-special @ baku-ir-and = if baku-front-and exit then
			baku-front-special @ baku-ir-or = if baku-front-or exit then
			baku-front-special @ baku-ir-cond = if baku-front-cond exit then
			baku-front-special @ baku-ir-let = if baku-front-let exit then
			baku-front-special @ baku-ir-lambda = if baku-front-lambda exit then
			baku-front-special @ baku-ir-defun = if baku-front-defun exit then
			baku-front-special @ baku-ir-freeze = if baku-front-freeze exit then
			baku-front-special @ baku-ir-trap-error = if baku-front-trap-error exit then
			baku-front-call
		else
			drop baku-front-call
		then
	else
		drop baku-front-atom
	then ;

\ A malformed form throws from inside a builder after it has pushed a root.  The
\ outermost compile therefore owns the root stack: it resets the depth on both
\ success and a caught throw, so one bad form cannot leave a stale root or make
\ the next form start at a raised depth.
variable baku-front-compiling?
0 baku-front-compiling? !

: baku-frontend-real ( form tail -- ir )
	baku-front-compiling? @ if baku-frontend-inner exit then
	1 baku-front-compiling? !
	0 baku-front-root-depth !
	['] baku-frontend-inner catch
	0 baku-front-compiling? !
	0 baku-front-root-depth !
	?dup if throw then ;

' baku-frontend-real is baku-frontend

\ The IR is built in the selected heap, which is the collector's from-space when
\ it is active.  These dictionary cells hold partly built IR across a recursive
\ compilation call that can allocate, so the collector updates them when the IR
\ moves.  BAKU-FRONT-ROOT-CELLS is a range because builders nest.
baku-front-root-cells baku-front-root-max baku-gc-root+
baku-copy-list 1 baku-gc-root+
baku-copy-node 1 baku-gc-root+
baku-params-list 1 baku-gc-root+
baku-params-vector 1 baku-gc-root+

baku-frontend-init
