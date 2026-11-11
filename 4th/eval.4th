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
\   kind 2  partial: ARITY is the number of arguments still needed, CODE is the
\           target closure and ENVIRONMENT is the saved argument list.
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
\ Tail calls: the front end marks a call that sits in a tail position.  Instead
\ of applying such a call recursively, BAKU-EVAL-CALL stores the closure and
\ argument list in BAKU-TAIL-FN / BAKU-TAIL-ARGS and returns BAKU-TAIL-PENDING.
\ Every enclosing evaluator frame returns that marker unchanged; the nearest
\ trampoline (BAKU-APPLY, BAKU-EVAL and the trap-error protected frame) applies
\ the request in a BEGIN ... WHILE ... REPEAT loop.  Self and mutual tail
\ recursion therefore reuse one trampoline iteration and do not grow the Forth
\ return stack.  TRAP-ERROR resolves a tail request inside its CATCH so the
\ handler frame survives; a tail call inside the protected form keeps that
\ frame, which is the semantics the tail-call spec requires.
\
\ BAKU-TAIL-PENDING is an internal evaluator marker, never a Shen value: the
\ reader parses the textual fixnum 26 as 53 ((2n)+1), so this cell can only be
\ produced here.
\
\ Currying: a closure carries the arity it still needs.  Applying it to fewer
\ arguments produces a partial closure that saves them; applying that closure to
\ the remaining ones completes the call.  Applying a closure to more arguments
\ than it needs is a catchable BAKU-EVAL-ARITY.  BAKU-APPLY resolves currying
\ before dispatch, so interpreted closures, host primitives and the tail-call
\ trampoline share the one application path.

\ ---------------------------------------------------------------------------
\ Errors
\ ---------------------------------------------------------------------------

-273 constant baku-eval-raised
-274 constant baku-eval-arity
-275 constant baku-eval-undefined
-276 constant baku-eval-not-callable
-277 constant baku-eval-cond-failed
-278 constant baku-eval-malformed
-279 constant baku-eval-unbound
-280 constant baku-eval-type

variable baku-raised-value

\ Pending tail call: BAKU-TAIL-PENDING is returned instead of a value, and the
\ trampoline consumes the two variables and applies the request.  The marker has
\ the immediate tag pattern but is not one of the three Shen immediates.
26 constant baku-tail-pending

variable baku-tail-fn
variable baku-tail-args

: baku-tail-pending? ( x -- flag ) baku-tail-pending = ;

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
2 constant baku-closure-partial

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
\
\ A bucket holds a list of entries; an entry is a cons of a BINDING and the
\ next entry, and a binding is a (name . closure) cons.  Comparing the binding's
\ head and returning its tail keeps a hash collision from hiding the older
\ definition.  BAKU-FN-DEFINE prepends, so last-definition-wins.
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
		dup baku-hd dup baku-hd 3 pick = if
			baku-tl nip nip true exit
		then
		drop baku-tl
	repeat
	2drop baku-nil false ;

: baku-fn-define ( closure sym -- )
	dup baku-fn-bucket >r
	swap baku-cons
	r@ @ baku-cons
	r> ! ;

: baku-primitive-closure ( xt arity -- closure )
	baku-nil swap 1 baku-make-closure ;

: baku-defprim ( xt arity name -- )
	>r baku-primitive-closure r> baku-fn-define ;

\ ---------------------------------------------------------------------------
\ Global variable table
\
\ SET and VALUE name a global through an interned symbol, so the table is keyed
\ by symbol identity like the function table.  An existing binding is updated in
\ place: the kernel re-sets counters such as shen.*infs* on every inference, and
\ prepending a fresh pair each time would grow the non-GC heap without bound.
\ Entries use the same (binding . next) shape as the function table, so a hash
\ collision cannot hide a binding.  A new binding is a (symbol . value) cons in
\ the selected heap; at boot that is the permanent non-GC heap, and the table is
\ a GC root.  The bucket array lives in the dictionary and survives a heap move.
\ ---------------------------------------------------------------------------

create baku-global-buckets baku-symbol-buckets-count cells allot

: baku-global-reset ( -- )
	baku-global-buckets baku-symbol-buckets-count 0 ?do
		0 over ! cell+
	loop drop ;

: baku-global-bucket ( sym -- addr )
	dup baku-symbol-name-addr swap baku-symbol-name-len
	baku-hash cells baku-global-buckets + ;

: baku-global-pair ( sym -- pair flag )
	dup baku-global-bucket @
	begin dup baku-cons? while
		dup baku-hd dup baku-hd 3 pick = if
			nip nip true exit
		then
		drop baku-tl
	repeat
	2drop false ;

: baku-global-lookup ( sym -- value flag )
	baku-global-pair if baku-tl true else baku-nil false then ;

: baku-global-define ( sym value -- value )
	over baku-global-pair if
		>r swap drop
		r@ baku-set-tl
		r> baku-tl
	else
		dup >r
		over baku-global-bucket >r
		baku-cons
		r@ @ baku-cons
		r> !
		r>
	then ;

: baku-prim-set ( sym value -- value )
	over baku-symbol? 0= if baku-eval-type throw then
	baku-global-define ;

: baku-prim-value ( sym -- value )
	dup baku-symbol? 0= if baku-eval-type throw then
	baku-global-lookup if else drop baku-eval-unbound throw then ;

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

variable baku-partial-target
variable baku-partial-saved
variable baku-partial-arity

: baku-apply-argc ( -- n ) baku-apply-args @ baku-list-length ;
: baku-apply-arity ( -- n ) baku-apply-fn @ baku-closure-arity ;

\ Build a partial closure from the current closure and arguments.  When the
\ current closure is already partial, its target and saved arguments are reused
\ so repeated partial application stays flat instead of nesting closures.
: baku-apply-make-partial ( -- closure )
	baku-apply-fn @ baku-closure-kind baku-closure-partial = if
		baku-apply-fn @ baku-closure-code baku-partial-target !
		baku-apply-fn @ baku-closure-env baku-partial-saved !
	else
		baku-apply-fn @ baku-partial-target !
		baku-nil baku-partial-saved !
	then
	baku-apply-arity baku-apply-argc - baku-partial-arity !
	baku-partial-saved @ baku-apply-args @ baku-list-append baku-partial-saved !
	baku-partial-target @ baku-partial-saved @
	baku-partial-arity @ baku-closure-partial
	baku-make-closure ;

\ A partial closure whose remaining arguments have all arrived: prepend its
\ saved arguments to the new ones and make the target current, so the same
\ trampoline iteration applies it.
: baku-apply-resolve-partial ( -- )
	baku-apply-fn @ baku-closure-code baku-partial-target !
	baku-apply-fn @ baku-closure-env
	baku-apply-args @ baku-list-append baku-partial-saved !
	baku-partial-target @ baku-apply-fn !
	baku-partial-saved @ baku-apply-args ! ;

\ Prepare the current application.  Return the value and true when currying
\ produced it, or false after making the closure and arguments exactly
\ arity-matched.  Too few arguments build or extend a partial; too many are a
\ catchable error.
: baku-apply-curry ( -- value true | -- false )
	baku-apply-argc baku-apply-arity
	2dup < if
		drop drop baku-apply-make-partial true exit
	then
	over over > if baku-eval-arity throw then
	2drop
	baku-apply-fn @ baku-closure-kind baku-closure-partial = if
		baku-apply-resolve-partial
	then
	false ;

\ The trampoline.  Each iteration applies one closure; an interpreted body that
\ ends in a tail call leaves a request instead of recursing, so the loop adopts
\ the new closure and arguments without touching the return stack.  A primitive
\ or a body that produced an ordinary value ends the loop.  Currying is resolved
\ first, so an under-applied tail call returns its partial closure as a value
\ and an over-applied one throws.
: baku-apply ( closure args -- value )
	begin
		baku-apply-args ! baku-apply-fn !
		baku-apply-fn @ baku-closure? 0= if baku-eval-not-callable throw then
		baku-apply-curry if exit then
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
		then
		dup baku-tail-pending? if
			drop baku-tail-fn @ baku-tail-args @
		else
			exit
		then
	again ;

\ Resolve a value that may be a pending tail call.  Used at the top level and
\ inside the trap-error frame; BAKU-APPLY itself already loops, so the first
\ application normally ends the loop.
: baku-tail-run ( value -- value )
	begin dup baku-tail-pending? while
		drop baku-tail-fn @ baku-tail-args @ baku-apply
	repeat ;

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

\ The protected form runs inside CATCH.  A tail call it produces is resolved by
\ BAKU-TAIL-RUN before leaving the protected word, so the trap-error handler
\ frame is still on the return stack if that call throws.
: baku-eval-protected ( node env -- value )
	baku-eval-ir baku-tail-run ;

: baku-eval-trap ( node env -- value )
	over baku-ir-trap-expr over
	['] baku-eval-protected catch dup if
		>r 2drop r> >r
		over baku-ir-trap-handler over baku-eval-ir
		r> baku-exception-value
		baku-nil baku-cons
		baku-apply
		nip nip
	else
		drop nip nip
	then ;

\ A tail call stores its closure and argument list and returns the marker.  The
\ operator and arguments are ordinary subexpressions, so they are evaluated
\ first; only the application is deferred to the trampoline.
: baku-eval-call ( node env -- value )
	over baku-ir-tail? >r
	over baku-ir-call-operator over baku-eval-operator
	>r
	0 swap baku-eval-args-from
	r> swap
	r> if
		baku-tail-args ! baku-tail-fn !
		baku-tail-pending
	else
		baku-apply
	then ;

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
\ the shared front end and then evaluates the IR.  The top-level form is compiled
\ with the tail flag set, so a top-level tail call also goes through the
\ trampoline instead of the Forth return stack.
: baku-eval ( ir -- value ) baku-nil baku-eval-ir baku-tail-run ;
: baku-eval-kl ( form -- value ) true baku-frontend baku-eval ;

: baku-eval-init ( -- )
	baku-fn-reset
	baku-global-reset
	baku-nil baku-raised-value !
	['] baku-prim-set 2 s" set" baku-intern baku-defprim
	['] baku-prim-value 1 s" value" baku-intern baku-defprim ;

baku-eval-init
