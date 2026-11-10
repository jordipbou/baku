\ Baku KLambda interpreter: the correctness reference.
\
\ The front end lowers a read form into vector IR; this layer evaluates that IR.
\ It is the simplest executor that is still complete for the kernel's KLambda
\ forms: a tree walk over the IR with lexical environments captured by closures.
\ The same IR is what the native code generator consumes, so the interpreter is
\ the reference every other mode must match.
\
\ Environments are association lists of (symbol . value) conses allocated in the
\ selected heap.  A symbol evaluates to its binding when one exists and to
\ itself otherwise, which is KLambda's self-evaluating symbol rule.  A closure is
\ a BAKU-TYPE-CLOSURE object with four payload cells:
\
\   [ kind, arity, code, environment ]
\
\   kind 0  interpreted: CODE is the lambda, defun or freeze IR node and
\           ENVIRONMENT is the captured association list.
\   kind 1  primitive: CODE is a Forth execution token, ARITY is its fixed
\           argument count and ENVIRONMENT is BAKU-NIL.
\
\ Global functions live in a dictionary-side bucket table; each entry is a cons
\ of (name-symbol . closure).  BAKU-DEFPRIM installs a host primitive and
\ BAKU-EVAL-KL is the single Shen-visible entry point.  Redefinition prepends,
\ so last-definition-wins without special cases.
\
\ Errors: a host primitive that must raise a Shen error calls BAKU-RAISE, which
\ stores a Baku value and throws BAKU-EVAL-RAISED.  TRAP-ERROR catches that code
\ and hands the stored value to the handler.  A raw Forth exception code is not
\ a Shen error object; it is passed to the handler as a fixnum so a Forth failure
\ remains catchable.  The error-object payload and SIMPLE-ERROR belong to M5.
\
\ Not here yet: on-demand currying, the self-tail loop and the trampoline.  A
\ call must supply exactly the closure's arity; a program that needs partial
\ application is rejected with BAKU-EVAL-ARITY until currying lands.  Recursion
\ therefore uses the Forth return stack and the interpreter is not yet safe for
\ the kernel's deepest tail-recursive walks.

\ ---------------------------------------------------------------------------
\ Errors
\ ---------------------------------------------------------------------------

-273 constant baku-eval-raised
-274 constant baku-eval-arity
-275 constant baku-eval-undefined
-276 constant baku-eval-not-callable
-277 constant baku-eval-cond-failed
-278 constant baku-eval-malformed

variable baku-raised-value

: baku-raise ( value -- )
	baku-raised-value ! baku-eval-raised throw ;

: baku-exception-value ( code -- value )
	dup baku-eval-raised = if
		drop baku-raised-value @
	else
		baku-fixnum
	then ;

\ ---------------------------------------------------------------------------
\ Closures
\ ---------------------------------------------------------------------------

0 constant baku-closure-interpreted
1 constant baku-closure-primitive

: baku-closure? ( x -- flag )
	dup baku-object? if baku-object-type baku-type-closure = else drop false then ;

: baku-closure-slot ( obj i -- addr )
	over baku-closure? 0= if baku-eval-not-callable throw then
	cells swap cell + + ;

: baku-closure@ ( obj i -- value ) baku-closure-slot @ ;
: baku-closure! ( value obj i -- ) baku-closure-slot ! ;

: baku-closure-kind ( obj -- kind ) 0 baku-closure@ ;
: baku-closure-arity ( obj -- n ) 1 baku-closure@ ;
: baku-closure-code ( obj -- code ) 2 baku-closure@ ;
: baku-closure-env ( obj -- env ) 3 baku-closure@ ;

variable baku-mk-code
variable baku-mk-env
variable baku-mk-arity
variable baku-mk-kind

: baku-make-closure ( code env arity kind -- closure )
	baku-mk-kind ! baku-mk-arity ! baku-mk-env ! baku-mk-code !
	4 cells baku-type-closure baku-alloc >r
	baku-mk-env @ r@ 3 baku-closure!
	baku-mk-code @ r@ 2 baku-closure!
	baku-mk-arity @ r@ 1 baku-closure!
	baku-mk-kind @ r@ 0 baku-closure!
	r> ;

\ ---------------------------------------------------------------------------
\ Global function table
\ ---------------------------------------------------------------------------

create baku-fn-buckets baku-symbol-buckets-count cells allot

: baku-fn-reset ( -- )
	baku-fn-buckets baku-symbol-buckets-count 0 ?do
		0 over ! cell+
	loop drop ;

: baku-fn-bucket ( sym -- addr )
	dup baku-symbol-name-addr swap baku-symbol-name-len
	baku-hash cells baku-fn-buckets + ;

: baku-fn-lookup ( sym -- closure flag )
	dup baku-fn-bucket @
	begin dup baku-cons? while
		dup baku-hd 2 pick = if
			nip baku-tl true exit
		then
		baku-tl
	repeat
	2drop baku-nil false ;

: baku-fn-define ( closure sym -- )
	dup baku-fn-bucket
	>r
	swap baku-cons
	r@ @ swap
	r> ! ;

: baku-primitive-closure ( xt arity -- closure )
	baku-nil swap 1 baku-make-closure ;

: baku-defprim ( xt arity name -- )
	>r baku-primitive-closure r> baku-fn-define ;

\ ---------------------------------------------------------------------------
\ Environments
\ ---------------------------------------------------------------------------

: baku-env-lookup ( sym env -- value flag )
	begin
		dup baku-cons? while
		dup baku-hd dup baku-hd 3 pick = if
			nip nip baku-tl true exit
		then
		drop baku-tl
	repeat
	2drop baku-nil false ;

: baku-bind ( value sym env -- env' )
	>r swap baku-cons r> baku-cons ;

variable baku-bind-params
variable baku-bind-args
variable baku-bind-env
variable baku-bind-i
variable baku-bind-n

\ Bind a parameter vector to an argument list in source order.  No interpreter
\ call happens inside this loop, so the bookkeeping variables cannot be
\ clobbered by a nested application.
: baku-bind-all ( params args env -- env' )
	baku-bind-env ! baku-bind-args ! baku-bind-params !
	baku-bind-params @ baku-vector-length baku-bind-n !
	0 baku-bind-i !
	begin baku-bind-i @ baku-bind-n @ < while
		baku-bind-args @ baku-hd
		baku-bind-params @ baku-bind-i @ baku-vector@
		baku-bind-env @ baku-bind
		baku-bind-env !
		baku-bind-args @ baku-tl baku-bind-args !
		baku-bind-i @ 1+ baku-bind-i !
	repeat
	baku-bind-args @ baku-nil = 0= if baku-eval-arity throw then
	baku-bind-env @ ;

\ ---------------------------------------------------------------------------
\ Evaluation
\ ---------------------------------------------------------------------------

defer baku-eval-ir

: baku-eval-symbol ( node env -- value )
	over baku-ir-value swap baku-env-lookup
	if nip else drop baku-ir-value then ;

\ Evaluate the arguments of a call in source order.  NODE and I identify the
\ position; ENV is carried on the return stack so the value being built can sit
\ on top of it while the rest of the list is evaluated.
: baku-eval-args-from ( node i env -- list )
	>r
	over baku-ir-call-arity over swap < if
		2dup baku-ir-call-arg r@ baku-eval-ir
		>r 1+ r> r> swap >r recurse r> swap baku-cons
	else
		2drop r> drop baku-nil
	then ;

variable baku-op-env

: baku-eval-operator ( ir env -- closure )
	baku-op-env !
	dup baku-ir-kind baku-ir-symbol = if
		dup baku-ir-value baku-op-env @ baku-env-lookup
		if nip exit then
		drop
		dup baku-ir-value baku-fn-lookup
		if nip exit then
		2drop baku-eval-undefined throw
	else
		baku-op-env @ baku-eval-ir
	then ;

\ Push evaluated arguments so the first argument is deepest, matching a Forth
\ primitive's ( a b -- result ) convention.
: baku-push-args ( list -- )
	dup baku-cons? if
		dup baku-hd
		swap baku-tl
		recurse
	else
		dup baku-nil = 0= if baku-eval-malformed throw then
		drop
	then ;

variable baku-ap-args
variable baku-ap-xt

: baku-apply-primitive ( xt arity args -- value )
	baku-ap-args !
	swap baku-ap-xt !
	baku-ap-args @ baku-list-length
	over <> if baku-eval-arity throw then
	drop
	baku-ap-args @ baku-push-args
	baku-ap-xt @ execute ;

variable baku-body-code

: baku-eval-body ( env args code -- value )
	baku-body-code !
	baku-body-code @ baku-ir-kind
	dup baku-ir-lambda = if
		drop
		baku-body-code @ baku-ir-lambda-param
		>r baku-hd r> rot baku-bind
		baku-body-code @ baku-ir-lambda-body swap baku-eval-ir exit
	then
	dup baku-ir-freeze = if
		drop drop
		baku-body-code @ baku-ir-freeze-body swap baku-eval-ir exit
	then
	dup baku-ir-defun = if
		drop nip
		baku-body-code @ baku-ir-defun-params
		swap baku-nil baku-bind-all
		baku-body-code @ baku-ir-defun-body swap baku-eval-ir exit
	then
	drop baku-eval-not-callable throw ;

variable baku-apply-fn
variable baku-apply-args

: baku-apply ( closure args -- value )
	baku-apply-args ! baku-apply-fn !
	baku-apply-fn @ baku-closure? 0= if baku-eval-not-callable throw then
	baku-apply-args @ baku-list-length
	baku-apply-fn @ baku-closure-arity <>
	if baku-eval-arity throw then
	baku-apply-fn @ baku-closure-kind baku-closure-interpreted = if
		baku-apply-fn @ baku-closure-env
		baku-apply-args @
		baku-apply-fn @ baku-closure-code
		baku-eval-body
	else
		baku-apply-fn @ baku-closure-code
		baku-apply-fn @ baku-closure-arity
		baku-apply-args @
		baku-apply-primitive
	then ;

\ ---------------------------------------------------------------------------
\ Special forms
\ ---------------------------------------------------------------------------

: baku-eval-if ( node env -- value )
	over baku-ir-if-test over baku-eval-ir
	baku-false = if
		over baku-ir-if-else
	else
		over baku-ir-if-then
	then
	swap baku-eval-ir nip ;

: baku-eval-and ( node env -- value )
	over baku-ir-and-left over baku-eval-ir
	baku-false = if 2drop baku-false exit then
	over baku-ir-and-right over baku-eval-ir nip nip ;

: baku-eval-or ( node env -- value )
	over baku-ir-or-left over baku-eval-ir
	baku-false = 0= if 2drop baku-true exit then
	over baku-ir-or-right over baku-eval-ir nip nip ;

: baku-eval-cond-clauses ( clauses env -- value )
	over baku-cons? if
		over baku-hd dup 0 baku-vector@
		2 pick baku-eval-ir
		baku-false = if
			drop swap baku-tl swap recurse
		else
			1 baku-vector@ swap baku-eval-ir nip
		then
	else
		2drop baku-eval-cond-failed throw
	then ;

: baku-eval-cond ( node env -- value )
	over baku-ir-cond-clauses swap baku-eval-cond-clauses nip ;

: baku-eval-let ( node env -- value )
	over baku-ir-let-expr over baku-eval-ir
	2 pick baku-ir-let-body >r
	>r
	over baku-ir-let-var
	r> swap
	2swap swap drop
	baku-bind
	r> swap baku-eval-ir ;

: baku-eval-lambda ( node env -- value )
	1 baku-closure-interpreted baku-make-closure ;

: baku-eval-freeze ( node env -- value )
	0 baku-closure-interpreted baku-make-closure ;

: baku-eval-defun ( node env -- value )
	drop
	dup baku-ir-defun-name >r
	dup baku-ir-defun-params baku-vector-length
	baku-nil swap 0 baku-make-closure
	r> dup >r baku-fn-define r> ;

: baku-eval-trap ( node env -- value )
	over baku-ir-trap-expr over
	['] baku-eval-ir catch dup if
		>r 2drop r> >r
		over baku-ir-trap-handler over baku-eval-ir
		r> baku-exception-value
		baku-nil baku-cons
		baku-apply
		nip nip
	else
		drop nip nip
	then ;

: baku-eval-call ( node env -- value )
	over baku-ir-call-operator over baku-eval-operator
	>r
	0 swap baku-eval-args-from
	r> swap baku-apply ;

: baku-eval-ir-real ( node env -- value )
	over baku-ir-kind
	dup baku-ir-atom = if drop drop baku-ir-value exit then
	dup baku-ir-symbol = if drop baku-eval-symbol exit then
	dup baku-ir-call = if drop baku-eval-call exit then
	dup baku-ir-if = if drop baku-eval-if exit then
	dup baku-ir-and = if drop baku-eval-and exit then
	dup baku-ir-or = if drop baku-eval-or exit then
	dup baku-ir-cond = if drop baku-eval-cond exit then
	dup baku-ir-let = if drop baku-eval-let exit then
	dup baku-ir-lambda = if drop baku-eval-lambda exit then
	dup baku-ir-defun = if drop baku-eval-defun exit then
	dup baku-ir-freeze = if drop baku-eval-freeze exit then
	dup baku-ir-trap-error = if drop baku-eval-trap exit then
	2drop baku-eval-malformed throw ;

' baku-eval-ir-real is baku-eval-ir

\ ---------------------------------------------------------------------------
\ Entry points
\ ---------------------------------------------------------------------------

\ BAKU-EVAL is the internal IR entry used by tests and future compiler modes.
\ BAKU-EVAL-KL is the single Shen-visible entry point: it lowers the form through
\ the shared front end and then evaluates the IR.
: baku-eval ( ir -- value ) baku-nil baku-eval-ir ;
: baku-eval-kl ( form -- value ) true baku-frontend baku-eval ;

: baku-eval-init ( -- )
	baku-fn-reset
	baku-nil baku-raised-value ! ;

baku-eval-init
