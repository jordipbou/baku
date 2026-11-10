\ Baku KLambda compiler front end.
\
\ The reader produces the raw form tree.  This layer validates it and lowers it
\ into a mode-independent intermediate representation shared by the interpreter
\ and the native code generator.  Tail-position analysis lives here, not in a
\ mode: every mode consumes the same tail flags.
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
\ in the form may point into the reader scratch arena.  The caller must consume
\ or copy the node first.  The front end itself is mode-agnostic: the memory mode
\ selects a backend, not a language.

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

: baku-frontend-init ( -- )
	s" if" baku-intern baku-sym-if !
	s" and" baku-intern baku-sym-and !
	s" or" baku-intern baku-sym-or !
	s" cond" baku-intern baku-sym-cond !
	s" let" baku-intern baku-sym-let !
	s" lambda" baku-intern baku-sym-lambda !
	s" defun" baku-intern baku-sym-defun !
	s" freeze" baku-intern baku-sym-freeze !
	s" trap-error" baku-intern baku-sym-trap-error ! ;

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

\ ---------------------------------------------------------------------------
\ Recursive builders.  BAKU-FRONTEND is deferred so the helpers below and the
\ builders can call it before its definition is reached.
\ ---------------------------------------------------------------------------

defer baku-frontend

: baku-front-nth ( form i tail -- ir )
	>r baku-list-nth r> baku-frontend ;

: baku-front-nth! ( form i tail node slot -- )
	>r >r baku-front-nth r> r> baku-vector! ;

: baku-front-atom ( value -- node )
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

variable baku-call-op
variable baku-call-args
variable baku-call-node

: baku-front-call ( form tail -- node )
	over baku-hd false baku-frontend ( form tail op )
	>r ( form tail | R: op )
	over baku-tl baku-front-args ( form tail args | R: op )
	r> baku-call-op ! ( form tail args )
	dup baku-list-length 3 + ( form tail args size )
	baku-ir-call ( form tail args size kind )
	3 pick ( form tail args size kind tail )
	baku-ir-make ( form tail args node )
	baku-call-node ! ( form tail args )
	baku-call-args ! ( form tail )
	2drop
	baku-call-op @ baku-call-node @ 2 baku-vector!
	baku-call-args @ baku-call-node @ 3 baku-copy-into-node
	baku-call-node @ ;

: baku-front-if ( form tail -- node )
	over baku-list-length 4 <> if baku-front-arity throw then
	5 baku-ir-if 2 pick baku-ir-make ( form tail node )
	>r ( form tail | R: node )
	over 1 false r@ 2 baku-front-nth!
	over 2 2 pick r@ 3 baku-front-nth!
	over 3 2 pick r@ 4 baku-front-nth!
	2drop r> ;

: baku-front-and ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-and 2 pick baku-ir-make
	>r
	over 1 false r@ 2 baku-front-nth!
	over 2 2 pick r@ 3 baku-front-nth!
	2drop r> ;

: baku-front-or ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-or 2 pick baku-ir-make
	>r
	over 1 false r@ 2 baku-front-nth!
	over 2 2 pick r@ 3 baku-front-nth!
	2drop r> ;

: baku-front-let ( form tail -- node )
	over baku-list-length 4 <> if baku-front-arity throw then
	5 baku-ir-let 2 pick baku-ir-make
	>r
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	r@ 2 baku-vector!
	over 2 false r@ 3 baku-front-nth!
	over 3 2 pick r@ 4 baku-front-nth!
	2drop r> ;

: baku-front-lambda ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-lambda 2 pick baku-ir-make
	>r
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	r@ 2 baku-vector!
	over 2 true r@ 3 baku-front-nth!
	2drop r> ;

: baku-front-freeze ( form tail -- node )
	over baku-list-length 2 <> if baku-front-arity throw then
	3 baku-ir-freeze 2 pick baku-ir-make
	>r
	over 1 true r@ 2 baku-front-nth!
	2drop r> ;

: baku-front-trap-error ( form tail -- node )
	over baku-list-length 3 <> if baku-front-arity throw then
	4 baku-ir-trap-error 2 pick baku-ir-make
	>r
	over 1 2 pick r@ 2 baku-front-nth!
	over 2 false r@ 3 baku-front-nth!
	2drop r> ;

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
	5 baku-ir-defun false baku-ir-make
	>r
	over 1 baku-list-nth
	dup baku-symbol? 0= if baku-front-malformed throw then
	r@ 2 baku-vector!
	over 2 baku-list-nth baku-front-params
	r@ 3 baku-vector!
	over 3 true r@ 4 baku-front-nth!
	2drop r> ;

\ COND lowers to a node holding a list of [test, result] clause vectors.  The
\ recursive walk returns the clause list in source order; the node is built once
\ after the walk, so only the tail flag lives across the recursion.
: baku-front-cond-clauses ( clauses tail -- list )
	over baku-cons? if
		over baku-hd ( clauses tail clause )
		dup baku-list-length 2 <> if baku-front-arity throw then
		dup 0 false baku-front-nth ( clauses tail clause test )
		>r ( clauses tail clause | R: test )
		1 2 pick baku-front-nth ( clauses tail result | R: test )
		r> ( clauses tail result test )
		2 baku-vector ( clauses tail result test clause-vector )
		>r ( clauses tail result test | R: clause-vector )
		r@ 0 baku-vector!
		r@ 1 baku-vector!
		r> ( clauses tail clause-vector )
		rot baku-tl ( tail clause-vector rest )
		swap ( tail rest clause-vector )
		>r ( tail rest | R: clause-vector )
		swap recurse ( restlist | R: clause-vector )
		r> swap baku-cons
	else
		over baku-nil = 0= if baku-front-malformed throw then
		2drop baku-nil
	then ;

: baku-front-cond ( form tail -- node )
	>r ( form | R: tail )
	dup baku-list-length dup 2 < if baku-front-arity throw then
	drop
	dup baku-tl ( form clauses | R: tail )
	r@ baku-front-cond-clauses ( form clauses-list | R: tail )
	swap drop ( clauses-list | R: tail )
	3 baku-ir-cond r> baku-ir-make
	dup >r 2 baku-vector! r> ;

\ ---------------------------------------------------------------------------
\ Entry point
\ ---------------------------------------------------------------------------

variable baku-front-special

: baku-frontend-real ( form tail -- ir )
	over baku-cons? if
		over baku-hd dup baku-symbol? if
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

' baku-frontend-real is baku-frontend

baku-frontend-init
