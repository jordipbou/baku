\ Baku native code generator: the non-GC and arena backend.
\
\ The shared front end produces vector IR.  This layer lowers that IR into a
\ dictionary-resident threaded code block and executes it with a small inner
\ interpreter.  The representation is Forth-native: a code block is an array of
\ dictionary cells, not a heap object and not C.  The tree-walking interpreter
\ in EVAL.4TH remains the correctness reference; every construct here mirrors
\ its semantics and uses the same helpers (environments, currying, the global
\ tables, the tail-call trampoline, the shared error cells).
\
\ A code block starts with its arity, then one dictionary cell per parameter
\ symbol, then instructions, and ends with an explicit RET.  Parameter cells are
\ interned symbols, which are permanent non-GC objects, so dictionary code holds
\ no arena or GC reference.  Code addresses are raw dictionary addresses; they
\ are never classified as Baku objects and are only interpreted by the native
\ closure kind.
\
\ Closure kind 3 (BAKU-CLOSURE-NATIVE) has the usual four-cell payload:
\
\   [ kind=3, arity, code-address, captured-environment ]
\
\ ARITY is a raw count, as for every other closure kind.  Applying a native
\ closure binds its parameter cells to the argument list, then runs the block.
\ A tail call stores its closure and arguments in the shared tail cells and
\ returns BAKU-TAIL-PENDING, so the BAKU-APPLY trampoline resolves it without
\ growing the Forth return stack.  A non-tail call goes through BAKU-APPLY.
\
\ LET compiles its body as a separate block and runs it with the extended
\ environment.  That keeps environment restoration automatic on both normal and
\ non-local exits.  LAMBDA, DEFUN, FREEZE and TRAP-ERROR also own child blocks.
\
\ Dictionary code is allocated by moving HERE with ALLOT.  UNUSED is checked
\ before every reservation so exhaustion is a catchable error.  The arena layer
\ binds BAKU-DICT-RESERVE so a reservation made while an arena is active also
\ advances that arena's bump pointer; the MARKER then reclaims the code.

\ ---------------------------------------------------------------------------
\ Instruction set.  An operand cell follows every opcode that needs one.
\ ---------------------------------------------------------------------------

0 constant baku-native-op-lit
1 constant baku-native-op-sym
2 constant baku-native-op-call
3 constant baku-native-op-tailcall
4 constant baku-native-op-jz
5 constant baku-native-op-jmp
6 constant baku-native-op-and
7 constant baku-native-op-or
8 constant baku-native-op-let
9 constant baku-native-op-lambda
10 constant baku-native-op-freeze
11 constant baku-native-op-defun
12 constant baku-native-op-trap
13 constant baku-native-op-condfail
14 constant baku-native-op-ret

\ Parameter symbols are copied into this buffer before a block is reserved.
128 constant baku-native-param-max
create baku-native-param-buf baku-native-param-max cells allot

: baku-native-param-set ( value i -- )
	cells baku-native-param-buf + ! ;

1024 constant baku-native-args-max
create baku-native-args-buf baku-native-args-max cells allot

variable baku-native-code-cells
variable baku-native-emit-addr
variable baku-native-ip
variable baku-native-env
variable baku-native-result
variable baku-native-self-code
variable baku-native-collect-n

\ ---------------------------------------------------------------------------
\ Size computation.  The size of a block that owns child blocks counts only its
\ own instruction cells; a child block is reserved separately and referenced by
\ its address.
\ ---------------------------------------------------------------------------

defer baku-native-size
defer baku-native-emit
defer baku-native-exec
defer baku-native-bind

variable baku-native-size-node
variable baku-native-size-i
variable baku-native-size-n
variable baku-native-size-total

: baku-native-args-size ( node n -- cells )
	baku-native-size-node @ >r
	baku-native-size-i @ >r
	baku-native-size-n @ >r
	baku-native-size-total @ >r
	baku-native-size-n ! baku-native-size-node !
	0 baku-native-size-total ! 0 baku-native-size-i !
	begin baku-native-size-i @ baku-native-size-n @ < while
		baku-native-size-node @ baku-native-size-i @ baku-ir-call-arg
		baku-native-size baku-native-size-total +!
		1 baku-native-size-i +!
	repeat
	baku-native-size-total @
	r> baku-native-size-total ! r> baku-native-size-n !
	r> baku-native-size-i ! r> baku-native-size-node ! ;

: baku-native-cond-size ( clauses -- cells )
	dup baku-cons? if
		dup baku-hd
		dup 0 baku-vector@ baku-native-size
		over 1 baku-vector@ baku-native-size + 4 +
		>r drop baku-tl recurse r> +
	else
		drop 1
	then ;

: baku-native-size-real ( ir -- cells )
	dup baku-ir-kind
	dup baku-ir-atom = if drop drop 2 exit then
	dup baku-ir-symbol = if drop drop 2 exit then
	dup baku-ir-call = if drop
		dup baku-ir-call-operator baku-native-size
		>r
		dup baku-ir-call-arity baku-native-args-size
		r> + 2 +
		exit
	then
	dup baku-ir-if = if drop
		dup baku-ir-if-test baku-native-size
		over baku-ir-if-then baku-native-size +
		over baku-ir-if-else baku-native-size + 4 + nip exit
	then
	dup baku-ir-and = if drop
		dup baku-ir-and-left baku-native-size
		over baku-ir-and-right baku-native-size + 2 + nip exit
	then
	dup baku-ir-or = if drop
		dup baku-ir-or-left baku-native-size
		over baku-ir-or-right baku-native-size + 2 + nip exit
	then
	dup baku-ir-cond = if drop
		dup baku-ir-cond-clauses baku-native-cond-size nip exit
	then
	dup baku-ir-let = if drop
		dup baku-ir-let-expr baku-native-size 3 + nip exit
	then
	dup baku-ir-lambda = if drop drop 2 exit then
	dup baku-ir-defun = if drop drop 3 exit then
	dup baku-ir-freeze = if drop drop 2 exit then
	dup baku-ir-trap-error = if drop drop 3 exit then
	drop drop baku-eval-malformed throw ;

' baku-native-size-real is baku-native-size

\ ---------------------------------------------------------------------------
\ Dictionary reservation
\ ---------------------------------------------------------------------------

: baku-native-reserve ( cells -- addr )
	align
	dup cells unused u> if baku-out-of-memory throw then
	dup baku-native-code-cells +!
	cells baku-dict-reserve ;

\ ---------------------------------------------------------------------------
\ Emission.  BAKU-NATIVE-EMIT-ADDR is a single forward cursor, so recursive
\ emission of inline subexpressions needs no state of its own.  A child block
\ reserves its own dictionary area and saves/restores the cursor.
\ ---------------------------------------------------------------------------

variable baku-native-block-addr
variable baku-native-block-arity
variable baku-native-block-ir
variable baku-native-block-i
variable baku-native-saved-emit

: baku-native-put ( cell -- )
	baku-native-emit-addr @ ! cell baku-native-emit-addr +! ;

: baku-native-compile-block ( ir arity -- addr )
	baku-native-block-addr @ >r
	baku-native-block-arity @ >r
	baku-native-block-ir @ >r
	baku-native-saved-emit @ >r
	baku-native-block-arity ! baku-native-block-ir !
	baku-native-block-arity @ 1+
	baku-native-block-ir @ baku-native-size + 1 +
	baku-native-reserve baku-native-block-addr !
	baku-native-block-arity @ baku-native-block-addr @ !
	0 baku-native-block-i !
	begin baku-native-block-i @ baku-native-block-arity @ < while
		baku-native-param-buf baku-native-block-i @ cells + @
		baku-native-block-addr @ baku-native-block-i @ 1+ cells + !
		1 baku-native-block-i +!
	repeat
	baku-native-emit-addr @ baku-native-saved-emit !
	baku-native-block-addr @ baku-native-block-arity @ 1+ cells +
	baku-native-emit-addr !
	baku-native-block-ir @ baku-native-emit
	baku-native-op-ret baku-native-put
	baku-native-saved-emit @ baku-native-emit-addr !
	baku-native-block-addr @
	r> baku-native-saved-emit ! r> baku-native-block-ir !
	r> baku-native-block-arity ! r> baku-native-block-addr ! ;

variable baku-native-set-vector
variable baku-native-set-n
variable baku-native-set-i

: baku-native-set-params ( vector -- n )
	dup baku-native-set-vector !
	baku-vector-length dup baku-native-set-n !
	dup baku-native-param-max > if baku-invalid-argument throw then
	drop
	0 baku-native-set-i !
	begin baku-native-set-i @ baku-native-set-n @ < while
		baku-native-set-vector @ baku-native-set-i @ baku-vector@
		baku-native-set-i @ baku-native-param-set
		1 baku-native-set-i +!
	repeat
	baku-native-set-n @ ;

: baku-native-compile-expr ( ir -- addr ) 0 baku-native-compile-block ;

: baku-native-compile-lambda ( param body -- addr )
	swap 0 baku-native-param-set
	1 baku-native-compile-block ;

: baku-native-compile-freeze ( body -- addr )
	0 baku-native-compile-block ;

: baku-native-compile-defun ( params body -- addr )
	swap baku-native-set-params baku-native-compile-block ;

: baku-native-emit-args-from ( ir i -- )
	over baku-ir-call-arity over swap < if
		2dup baku-ir-call-arg baku-native-emit
		1+ recurse
	else
		2drop
	then ;

: baku-native-emit-call ( ir -- )
	dup baku-ir-call-operator baku-native-emit
	dup 0 baku-native-emit-args-from
	dup baku-ir-tail? if
		baku-native-op-tailcall
	else
		baku-native-op-call
	then
	baku-native-put
	dup baku-ir-call-arity baku-native-put
	drop ;

: baku-native-emit-if ( ir -- )
	dup baku-ir-if-test baku-native-emit
	dup baku-ir-if-then baku-native-size 4 + cells baku-native-emit-addr @ +
	>r
	baku-native-op-jz baku-native-put r> baku-native-put
	dup baku-ir-if-then baku-native-emit
	dup baku-ir-if-else baku-native-size 2 + cells baku-native-emit-addr @ +
	>r
	baku-native-op-jmp baku-native-put r> baku-native-put
	baku-ir-if-else baku-native-emit ;

: baku-native-emit-and ( ir -- )
	dup baku-native-size cells baku-native-emit-addr @ + >r
	dup baku-ir-and-left baku-native-emit
	baku-native-op-and baku-native-put r> baku-native-put
	baku-ir-and-right baku-native-emit ;

: baku-native-emit-or ( ir -- )
	dup baku-native-size cells baku-native-emit-addr @ + >r
	dup baku-ir-or-left baku-native-emit
	baku-native-op-or baku-native-put r> baku-native-put
	baku-ir-or-right baku-native-emit ;

variable baku-cond-clauses
variable baku-cond-end
variable baku-cond-test
variable baku-cond-result
variable baku-cond-next

: baku-native-emit-cond-clauses ( clauses end -- )
	baku-cond-clauses @ >r baku-cond-end @ >r
	baku-cond-test @ >r baku-cond-result @ >r baku-cond-next @ >r
	baku-cond-end ! baku-cond-clauses !
	begin baku-cond-clauses @ baku-cons? while
		baku-cond-clauses @ baku-hd
		dup 0 baku-vector@ baku-cond-test !
		1 baku-vector@ baku-cond-result !
		baku-cond-test @ baku-native-size
		baku-cond-result @ baku-native-size + 4 + cells
		baku-native-emit-addr @ + baku-cond-next !
		baku-cond-test @ baku-native-emit
		baku-native-op-jz baku-native-put
		baku-cond-next @ baku-native-put
		baku-cond-result @ baku-native-emit
		baku-native-op-jmp baku-native-put
		baku-cond-end @ baku-native-put
		baku-cond-clauses @ baku-tl baku-cond-clauses !
	repeat
	baku-native-op-condfail baku-native-put
	r> baku-cond-next ! r> baku-cond-result !
	r> baku-cond-test ! r> baku-cond-end ! r> baku-cond-clauses ! ;

: baku-native-emit-cond ( ir -- )
	>r
	r@ baku-ir-cond-clauses
	r@ baku-native-size cells baku-native-emit-addr @ +
	r> drop
	baku-native-emit-cond-clauses ;

: baku-native-emit-let ( ir -- )
	dup baku-ir-let-expr baku-native-emit
	baku-native-op-let baku-native-put
	dup baku-ir-let-var baku-native-put
	dup baku-ir-let-body baku-native-compile-expr baku-native-put
	drop ;

: baku-native-emit-lambda ( ir -- )
	dup baku-ir-lambda-param over baku-ir-lambda-body
	baku-native-compile-lambda
	>r baku-native-op-lambda baku-native-put r> baku-native-put drop ;

: baku-native-emit-freeze ( ir -- )
	dup baku-ir-freeze-body baku-native-compile-freeze
	>r baku-native-op-freeze baku-native-put r> baku-native-put drop ;

: baku-native-emit-defun ( ir -- )
	dup baku-ir-defun-params over baku-ir-defun-body
	baku-native-compile-defun
	>r baku-native-op-defun baku-native-put
	dup baku-ir-defun-name baku-native-put
	r> baku-native-put drop ;

: baku-native-emit-trap ( ir -- )
	dup baku-ir-trap-expr baku-native-compile-expr
	over baku-ir-trap-handler baku-native-compile-expr
	>r >r baku-native-op-trap baku-native-put
	r> baku-native-put r> baku-native-put drop ;

\ A dictionary code block holds raw addresses, so a heap-object literal (a
\ string or a boxed float) must live in the permanent non-GC heap, not in the
\ disposable IR scratch.  Symbols are already permanent and immediates need no
\ storage.  Copy each literal once at emission time.
: baku-native-literal ( x -- x' )
	dup baku-string? if
		baku-heap-save >r >r
		dup baku-string-addr swap baku-string-length
		baku-use-nongc
		baku-string
		r> r> baku-heap-restore exit
	then
	dup baku-float? if
		baku-heap-save >r >r
		cell + df@
		baku-use-nongc
		baku-float
		r> r> baku-heap-restore exit
	then ;

: baku-native-emit-real ( ir -- )
	dup baku-ir-kind
	dup baku-ir-atom = if
		drop baku-native-op-lit baku-native-put
		dup baku-ir-value baku-native-literal baku-native-put drop exit
	then
	dup baku-ir-symbol = if
		drop baku-native-op-sym baku-native-put
		dup baku-ir-value baku-native-put drop exit
	then
	dup baku-ir-call = if drop baku-native-emit-call exit then
	dup baku-ir-if = if drop baku-native-emit-if exit then
	dup baku-ir-and = if drop baku-native-emit-and exit then
	dup baku-ir-or = if drop baku-native-emit-or exit then
	dup baku-ir-cond = if drop baku-native-emit-cond exit then
	dup baku-ir-let = if drop baku-native-emit-let exit then
	dup baku-ir-lambda = if drop baku-native-emit-lambda exit then
	dup baku-ir-defun = if drop baku-native-emit-defun exit then
	dup baku-ir-freeze = if drop baku-native-emit-freeze exit then
	dup baku-ir-trap-error = if drop baku-native-emit-trap exit then
	drop drop baku-eval-malformed throw ;

' baku-native-emit-real is baku-native-emit

\ ---------------------------------------------------------------------------
\ Execution
\ ---------------------------------------------------------------------------

: baku-fetch ( -- cell )
	baku-native-ip @ @ cell baku-native-ip +! ;

: baku-native-symbol-value ( sym -- value )
	dup baku-native-env @ baku-env-lookup if nip else drop then ;

: baku-native-resolve-operator ( value -- closure )
	dup baku-symbol? if
		dup baku-fn-lookup if nip exit then
		2drop baku-eval-undefined throw
	then ;

: baku-native-collect ( n -- list )
	dup baku-native-args-max > if baku-invalid-argument throw then
	dup baku-native-collect-n !
	0 ?do
		baku-native-collect-n @ 1- i - cells baku-native-args-buf + !
	loop
	baku-nil
	baku-native-collect-n @ 0 ?do
		baku-native-collect-n @ 1- i - cells baku-native-args-buf + @
		swap baku-cons
	loop ;

: baku-native-call ( -- )
	baku-fetch baku-native-collect swap baku-native-resolve-operator
	swap baku-apply ;

variable baku-self-code
variable baku-native-self-jumps
variable baku-native-self-fn
variable baku-native-self-env

: baku-native-tailcall ( -- )
	baku-fetch baku-native-collect swap baku-native-resolve-operator
	dup baku-native-self-fn @ =
	over baku-closure-code baku-native-self-code @ = and
	2 pick baku-list-length 2 pick baku-closure-arity = and
	if
		dup baku-closure-code baku-self-code !
		baku-closure-env baku-native-self-env !
		baku-self-code @ baku-native-self-env @ rot
		baku-native-bind baku-native-env !
		1 baku-native-self-jumps +!
		baku-self-code @ dup @ 1+ cells + baku-native-ip !
	else
		baku-tail-fn ! baku-tail-args ! baku-tail-pending
	then ;

: baku-native-jz ( -- )
	baku-fetch swap baku-false = if baku-native-ip ! else drop then ;

: baku-native-and ( -- )
	baku-fetch swap
	dup baku-false = if
		>r baku-native-ip ! r>
	else
		drop drop
	then ;

: baku-native-or ( -- )
	baku-fetch swap baku-false = if
		drop
	else
		baku-native-ip ! baku-true
	then ;

variable baku-native-let-var
variable baku-native-let-body

: baku-native-let ( -- )
	baku-fetch baku-native-let-var !
	baku-fetch baku-native-let-body !
	baku-native-let-var @ baku-native-env @ baku-bind
	baku-native-let-body @ swap 0 baku-native-exec ;

: baku-native-lambda ( -- )
	baku-fetch dup @ baku-native-env @ swap
	baku-closure-native baku-make-closure ;

: baku-native-freeze ( -- )
	baku-fetch dup @ baku-native-env @ swap
	baku-closure-native baku-make-closure ;

: baku-native-defun ( -- )
	baku-fetch >r
	baku-fetch dup @ baku-nil swap
	baku-closure-native baku-make-closure
	r> dup >r
	baku-fn-define
	r> ;

variable baku-native-trap-prot
variable baku-native-trap-handler
variable baku-native-trap-env

: baku-native-protected ( -- value )
	baku-native-trap-prot @ baku-native-trap-env @ 0 baku-native-exec
	baku-tail-run ;

\ The enclosing continuation and the previous trap cells live on the return
\ stack, not in variables: a trap-error inside the protected form (for example
\ the one SHEN.ATOM->STR uses around STR) must not clobber the outer trap's
\ saved state.  CATCH restores the return stack to the depth at its call, so
\ these six cells survive a throw.  On the error path the previous trap cells
\ are restored before the handler runs and the continuation after it.
: baku-native-trap-run ( prot handler env -- value )
	baku-native-ip @ >r
	baku-native-env @ >r
	baku-native-self-code @ >r
	baku-native-trap-prot @ >r
	baku-native-trap-handler @ >r
	baku-native-trap-env @ >r
	baku-native-trap-env ! baku-native-trap-handler ! baku-native-trap-prot !
	['] baku-native-protected catch
	dup if
		baku-exception-value
		baku-native-trap-handler @ baku-native-trap-env @ 0
		r> baku-native-trap-env !
		r> baku-native-trap-handler !
		r> baku-native-trap-prot !
		baku-native-exec
		swap baku-nil baku-cons baku-apply
	else
		drop
		r> baku-native-trap-env !
		r> baku-native-trap-handler !
		r> baku-native-trap-prot !
	then
	r> baku-native-self-code !
	r> baku-native-env !
	r> baku-native-ip ! ;

: baku-native-trap ( -- )
	baku-fetch baku-fetch
	baku-native-env @ baku-native-trap-run ;

: baku-native-step ( op -- )
	dup baku-native-op-lit = if
		drop baku-fetch false exit
	then
	dup baku-native-op-sym = if
		drop baku-fetch baku-native-symbol-value false exit
	then
	dup baku-native-op-call = if
		drop baku-native-call false exit
	then
	dup baku-native-op-tailcall = if
		drop baku-native-tailcall false exit
	then
	dup baku-native-op-jz = if
		drop baku-native-jz false exit
	then
	dup baku-native-op-jmp = if
		drop baku-fetch baku-native-ip ! false exit
	then
	dup baku-native-op-and = if
		drop baku-native-and false exit
	then
	dup baku-native-op-or = if
		drop baku-native-or false exit
	then
	dup baku-native-op-let = if
		drop baku-native-let false exit
	then
	dup baku-native-op-lambda = if
		drop baku-native-lambda false exit
	then
	dup baku-native-op-freeze = if
		drop baku-native-freeze false exit
	then
	dup baku-native-op-defun = if
		drop baku-native-defun false exit
	then
	dup baku-native-op-trap = if
		drop baku-native-trap false exit
	then
	dup baku-native-op-condfail = if
		drop baku-eval-cond-failed throw
	then
	dup baku-native-op-ret = if
		drop baku-native-result ! true exit
	then
	drop baku-eval-malformed throw ;

: baku-native-exec-real ( code env self -- value )
	baku-native-self-code @ >r
	baku-native-env @ >r
	baku-native-ip @ >r
	baku-native-self-code !
	baku-native-env !
	dup @ 1+ cells + baku-native-ip !
	begin baku-fetch baku-native-step until
	r> r> r>
	baku-native-self-code ! baku-native-env ! baku-native-ip !
	baku-native-result @ ;

' baku-native-exec-real is baku-native-exec

variable baku-native-run-code
variable baku-native-run-env
variable baku-native-run-args

: baku-native-bind-real ( code env args -- env' )
	baku-native-run-args ! baku-native-run-env ! baku-native-run-code !
	baku-native-run-code @ @ 0= if
		baku-native-run-env @ exit
	then
	baku-native-run-code @ @ 0 ?do
		baku-native-run-args @ baku-hd
		baku-native-run-code @ i 1+ cells + @
		baku-native-run-env @ baku-bind
		baku-native-run-env !
		baku-native-run-args @ baku-tl baku-native-run-args !
	loop
	baku-native-run-args @ baku-nil = 0= if baku-eval-arity throw then
	baku-native-run-env @ ;

' baku-native-bind-real is baku-native-bind

: baku-native-run-real ( code env args -- value )
	baku-native-self-fn @ >r
	baku-apply-fn @ baku-native-self-fn !
	baku-native-bind
	baku-native-run-code @ swap
	baku-native-run-code @ baku-native-exec
	r> baku-native-self-fn ! ;

' baku-native-run-real is baku-native-run

\ ---------------------------------------------------------------------------
\ Entry points and the boot installer
\ ---------------------------------------------------------------------------

: baku-native-eval ( ir -- value )
	baku-native-compile-expr baku-nil 0 baku-native-exec baku-tail-run ;

\ One form at a time: lower it into the IR scratch, compile the resulting IR to
\ dictionary code, then return to the permanent heap for execution.  The IR is
\ dead once compilation finishes, so the scratch is reset even when lowering,
\ compilation or execution throws.  A nested EVAL-KL during execution resets the
\ scratch too; the outer IR is already compiled, so that is safe.
variable baku-native-eval-saved-here
variable baku-native-eval-saved-end

: baku-native-eval-scratch ( form -- value )
	true baku-frontend
	baku-native-compile-expr
	baku-native-eval-saved-here @ baku-native-eval-saved-end @ baku-heap-restore
	baku-nil 0 baku-native-exec baku-tail-run ;

: baku-native-eval-kl ( form -- value )
	\ GC mode stores code in the heap and runs the interpreter; compiling to
	\ dictionary code here would put an unreclaimable object outside the GC.
	baku-gc-active? if baku-mode-error throw then
	baku-heap-save baku-native-eval-saved-end ! baku-native-eval-saved-here !
	baku-ir-scratch-reset
	baku-use-ir-scratch
	['] baku-native-eval-scratch catch
	baku-native-eval-saved-here @ baku-native-eval-saved-end @ baku-heap-restore
	baku-ir-scratch-reset
	?dup if swap drop throw then ;

: baku-native-install-form ( form -- ) baku-native-eval-kl drop ;

\ The kernel-visible EVAL-KL follows the memory state: GC mode interprets from
\ the heap, while non-GC and arena modes compile native dictionary code.  This
\ is the single mode selector; callers do not choose a backend directly.
: baku-eval-kl-mode ( form -- value )
	baku-mode baku-mode-gc = if baku-eval-kl else baku-native-eval-kl then ;

' baku-eval-kl-mode 1 s" eval-kl" baku-intern baku-defprim
