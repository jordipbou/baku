\ Baku top level: the interactive REPL, expression mode and file mode.
\
\ The kernel owns the top level.  SHEN.PROMPT, READ-FROM-STRING,
\ SHEN.PACKAGE-USER-INPUT, SHEN.UPDATE-HISTORY and SHEN.EVALUATE-LINEREAD are
\ called unchanged, so package resolution, history, `it` and the type-check
\ switch keep their kernel semantics.  Baku supplies only what the kernel cannot
\ see from KLambda: the physical input source and its end.
\
\ The kernel's LINEREAD cannot report end of input.  It reads bytes through
\ READ-BYTE / READ-UNIT-STRING and, at a stream end, either raises "error: empty
\ stream" or tries to parse the partial form; SHEN.LOOP catches that and loops
\ for ever.  A top level that must exit on end of input therefore reads a line at
\ the Forth level and hands the text to the kernel reader.  The line loop keeps
\ accumulating when the kernel's parse-only reader rejects the text, so a form
\ continued across lines still parses; only at end of input is the remaining text
\ evaluated once and the loop returns.
\
\ Reading a line is the only per-target difference: a file stream reports end of
\ file as -1, while ANS KEY has no end value.  gforth raises an error when KEY
\ has no input left, and that error is the end of the standard input.  Both paths
\ are shipped; only gforth makes the standard-input path observable.
\
\ Expression mode evaluates one supplied text and returns a Forth success flag.
\ File mode and the interactive loop run the same line loop with a file stream or
\ the standard input.  Every top-level error is displayed with the kernel's
\ SHEN.TOPLEVEL-DISPLAY-EXCEPTION (thus ERROR-TO-STRING) and the loop continues,
\ which is what SHEN.LOOP does.

65536 constant baku-repl-line-max

-281 constant baku-repl-line-overflow

create baku-repl-line-buf baku-repl-line-max allot
variable baku-repl-acc-len
variable baku-repl-echo

: baku-eval-form ( form -- value )
	s" eval-kl" baku-intern baku-fn-lookup 0= if
		drop baku-eval-undefined throw
	then
	swap baku-nil baku-cons baku-apply ;

\ Call a one-argument KLambda function with a value.  The form is evaluated
\ through the registered EVAL-KL primitive, the single executor entry point.
: baku-repl-call1 ( value sym -- value )
	swap baku-nil baku-cons baku-cons baku-eval-form ;

: baku-repl-acc-put ( n -- )
	baku-repl-acc-len @ baku-repl-line-max >= if
		baku-repl-line-overflow throw
	then
	dup baku-repl-acc-len @ baku-repl-line-buf + c!
	drop
	1 baku-repl-acc-len +! ;

\ One byte from a REPL input stream.  A file returns -1 at end of file; KEY has
\ no end value, so a KEY error is the end of the standard input.
: baku-repl-byte ( stream -- n )
	dup baku-stream-mode baku-stream-input = if
		drop ['] key catch if -1 then
	else
		baku-read-one-byte
	then ;

\ Append one line to the accumulator and report whether the input ended.  A
\ newline is kept as the separator between continued lines; CR also ends a line
\ so raw terminals and CRLF files behave like LF input.  The interactive path
\ echoes printable bytes and handles backspace, because KEY does not echo on the
\ supported targets.
: baku-repl-read-line ( stream -- eof? )
	begin
		dup baku-repl-byte
		dup 0< if
			drop true exit
		then
		dup 10 = over 13 = or if
			drop 10 baku-repl-acc-put
			baku-repl-echo @ if 10 emit then
			false exit
		then
		dup 8 = over 127 = or if
			drop
			baku-repl-echo @ if
				baku-repl-acc-len @ 0> if
					-1 baku-repl-acc-len +!
					8 emit bl emit 8 emit
				then
			else
				8 baku-repl-acc-put
			then
		else
			baku-repl-echo @ if
				dup 32 >= over 126 <= and if dup emit then
			then
			baku-repl-acc-put
		then
	again ;

: baku-repl-eval-line ( c-addr u -- value )
	baku-string s" baku.repl-eval" baku-intern baku-repl-call1 ;

: baku-repl-parse? ( c-addr u -- flag )
	baku-string s" baku.repl-parse" baku-intern
	['] baku-repl-call1 catch if
		2drop false
	else
		drop true
	then ;

\ Evaluate one line at the top level and display any error.  The exception value
\ is the value TRAP-ERROR would hand the kernel handler; a raw Forth code reaches
\ the display as a fixnum, the same way SHEN.LOOP sees it.
: baku-repl-try ( c-addr u -- ok? )
	['] baku-repl-eval-line catch dup if
		>r 2drop r> baku-exception-value
		s" shen.toplevel-display-exception" baku-intern
		baku-repl-call1 drop
		false
	else
		drop drop true
	then ;

: baku-repl-eval-acc ( -- )
	baku-repl-line-buf baku-repl-acc-len @ baku-repl-try drop ;

: baku-repl-prompt ( -- )
	s" shen.prompt" baku-intern baku-nil baku-cons baku-eval-form drop ;

\ The shared loop.  It prompts only at the start of a new form (not for a
\ continuation line) when the prompt flag is set.  A line that parses is
\ evaluated immediately; a line that does not parse is kept and more input is
\ read.  At end of input the remaining text is evaluated once, errors included,
\ and the loop returns.
: baku-repl-stream ( stream prompt? -- )
	>r 0 baku-repl-acc-len !
	begin
		r@ if
			baku-repl-acc-len @ 0= if baku-repl-prompt then
		then
		dup baku-repl-read-line
		if
			drop
			baku-repl-acc-len @ 0<> if
				baku-repl-eval-acc 0 baku-repl-acc-len !
			then
			r> drop exit
		then
		baku-repl-line-buf baku-repl-acc-len @ baku-repl-parse? if
			baku-repl-eval-acc
			0 baku-repl-acc-len !
		then
	again ;

\ Expression mode: evaluate supplied KLambda text.  The flag is the documented
\ CLI exit decision; the error text already went to *STOUTPUT*.
: baku-repl-eval ( c-addr u -- ok? ) baku-repl-try ;

\ File mode: run a line-oriented Shen script.  Program files with multi-line
\ definitions are better loaded with the kernel's own LOAD function from the
\ REPL; this mode is the batch form of the same top-level rules.  The stream is
\ closed even when a structural error (for example a line over the buffer limit)
\ escapes the loop.
: baku-repl-file ( c-addr u -- )
	false baku-repl-echo !
	baku-string s" in" baku-intern baku-prim-open
	dup false ['] baku-repl-stream catch dup if
		>r baku-prim-close drop r> throw
	then
	drop
	baku-prim-close drop ;

\ Interactive mode: prompt, read the standard input, evaluate and display
\ errors.  End of input returns cleanly.
: baku-repl ( -- )
	true baku-repl-echo !
	baku-stdin-stream true baku-repl-stream ;

\ ---------------------------------------------------------------------------
\ Kernel-side helpers.  They are installed once as interpreted KLambda
\ definitions (the same path INPUT+ uses), so the kernel functions they name are
\ resolved when the top level runs, not when this layer loads.
\ ---------------------------------------------------------------------------

\ Parse-only check used for continuation.  READ-FROM-STRING-UNPROCESSED is the
\ kernel's try-parse boundary: it fails on an incomplete form and succeeds on a
\ complete one, without macroexpanding or typechecking first.
s" (defun baku.repl-parse (Text) (read-from-string-unprocessed Text))"
	baku-compat-eval-source

\ One REPL line: the kernel reader, package mapping, history and the
\ type-check-aware evaluator, in the same order SHEN.READ-EVALUATE-PRINT uses.
\ A blank line is skipped, like LINEREAD skipping an empty line.
s" (defun baku.repl-eval (Text) (if (shen.+string? (shen.trim-it Text)) (let Forms (read-from-string Text) (do (set shen.*it* Text) (let History (shen.update-history) (shen.evaluate-lineread (shen.package-user-input (value shen.*package*) Forms) History (value shen.*tc*))))) shen.skip))"
	baku-compat-eval-source
