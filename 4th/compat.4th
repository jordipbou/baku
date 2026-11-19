\ Baku KLambda compatibility definitions.
\
\ Shen 43.2 registers INPUT+ as an arity-2 external function and installs a
\ two-place lambda form (init.kl), but the kernel defines no (defun input+ ...):
\ the kernel macro SHEN.PROCESS-INPUT+ rewrites an INPUT+ application into a
\ call to SHEN.INPUT-H+ (macros.kl).  Higher-order uses such as (fn input+) still
\ need INPUT+ itself to be callable, so the missing definition is installed once
\ when this layer loads (port-upgrades 41.3).
\
\ The definition is KLambda, not a Forth primitive, so it has the same closure
\ record and the same on-demand currying as every other interpreted function.
\ Its body names SHEN.INPUT-H+ as an ordinary symbol; resolution happens when the
\ function is applied, so this layer can load before the kernel and the kernel
\ definition is the single source of the delegate behaviour.
\
\ BAKU-COMPAT-INIT installs the definition.  The user entry calls it after the
\ collector is created and activated, so the closure and its IR live in the GC
\ heap; evaluating it while this layer loads would put them in the permanent
\ non-GC block, which must hold only interned symbols.

: baku-compat-eval-source ( c-addr u -- )
	baku-read-string
	baku-read-form 0= if drop baku-read-eof throw then
	baku-eval-kl drop ;

: baku-compat-init ( -- )
	s" (defun input+ (X Y) (shen.input-h+ X Y))" baku-compat-eval-source ;
