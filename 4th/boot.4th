\ Baku kernel bootstrap: the load manifest, definition installation and the
\ host globals the kernel reads.
\
\ BAKU-INSTALL-FORM receives one top-level form and installs its definition
\ through the interpreter, the only executor.  The loader consumes each form
\ before the next read, because a reader form lives in the resettable scratch
\ region.
\
\ The file order below is the boot manifest.  At load time a top-level form is
\ either a DEFUN or a copyright string and no body runs, so the order has no
\ semantic effect; it is fixed so a boot is reproducible.
\
\ Initialisation is a separate step: bind the host globals, then call
\ SHEN.INITIALISE and STLIB.INITIALISE.  The interpreter keeps the IR of every
\ definition in the selected heap and every EVAL-KL call adds more, so the
\ collector must be created and activated before boot.

256 constant baku-boot-path-max
create baku-boot-path-buf baku-boot-path-max allot

variable baku-boot-name-addr
variable baku-boot-name-len
variable baku-boot-forms
variable baku-boot-defuns
variable baku-boot-files
variable baku-boot-defun-sym

: baku-boot-dir ( -- c-addr u ) s" vendor/shen-43.2/klambda/" ;

\ Build PREFIX + NAME in the path buffer and return its extent.  The buffer is
\ reused for every file and the reader copies the name it needs.
: baku-boot-path ( c-addr u -- c-addr u' )
	baku-boot-name-len ! baku-boot-name-addr !
	baku-boot-dir baku-boot-path-buf swap cmove
	baku-boot-dir nip baku-boot-path-buf +
	baku-boot-name-addr @ swap baku-boot-name-len @ cmove
	baku-boot-path-buf baku-boot-dir nip baku-boot-name-len @ + ;

\ Lowering and evaluating the form installs a DEFUN closure or returns a
\ copyright string.
: baku-install-form ( form -- ) baku-eval-kl drop ;

: baku-boot-defun? ( form -- flag )
	dup baku-cons? if baku-hd baku-boot-defun-sym @ = else drop false then ;

: baku-boot-load-source ( c-addr u -- )
	baku-read-file
	begin baku-read-form while
		dup baku-boot-defun? if 1 baku-boot-defuns +! then
		dup baku-install-form drop
		1 baku-boot-forms +!
	repeat
	drop baku-read-close ;

: baku-boot-load-file ( c-addr u -- )
	baku-boot-path baku-boot-load-source
	1 baku-boot-files +! ;

\ The manifest: 23 files, alphabetical.  Only top-level DEFUN and string forms
\ occur, so every file installs cleanly in any order.
: baku-boot-load-kernel ( -- )
	s" defun" baku-intern baku-boot-defun-sym !
	0 baku-boot-forms ! 0 baku-boot-defuns ! 0 baku-boot-files !
	s" core.kl" baku-boot-load-file
	s" declarations.kl" baku-boot-load-file
	s" dict.kl" baku-boot-load-file
	s" extension-expand-dynamic.kl" baku-boot-load-file
	s" extension-features.kl" baku-boot-load-file
	s" extension-launcher.kl" baku-boot-load-file
	s" extension-namespaces.kl" baku-boot-load-file
	s" extension-programmable-pattern-matching.kl" baku-boot-load-file
	s" extension-type-annotations.kl" baku-boot-load-file
	s" init.kl" baku-boot-load-file
	s" load.kl" baku-boot-load-file
	s" macros.kl" baku-boot-load-file
	s" prolog.kl" baku-boot-load-file
	s" reader.kl" baku-boot-load-file
	s" sequent.kl" baku-boot-load-file
	s" stlib.kl" baku-boot-load-file
	s" sys.kl" baku-boot-load-file
	s" toplevel.kl" baku-boot-load-file
	s" track.kl" baku-boot-load-file
	s" t-star.kl" baku-boot-load-file
	s" types.kl" baku-boot-load-file
	s" writer.kl" baku-boot-load-file
	s" yacc.kl" baku-boot-load-file ;

\ ---------------------------------------------------------------------------
\ Host globals.  The kernel reads these before and during initialisation; the
\ port supplies them, and SHEN.INITIALISE leaves *VERSION* to the kernel.
\ ---------------------------------------------------------------------------

: baku-boot-bind ( value c-addr u -- )
	baku-intern swap baku-global-define drop ;

: baku-boot-globals ( -- )
	s" Shen" baku-intern s" *language*" baku-boot-bind
	s" Baku" baku-intern s" *implementation*" baku-boot-bind
	s" 43.2" baku-intern s" *release*" baku-boot-bind
	s" 0.1" baku-intern s" *port*" baku-boot-bind
	s" jordipbou" baku-intern s" *porters*" baku-boot-bind
	s" linux" baku-intern s" *os*" baku-boot-bind
	baku-stdin-stream s" *stinput*" baku-boot-bind
	baku-stdout-stream s" *stoutput*" baku-boot-bind
	baku-stdout-stream s" *sterror*" baku-boot-bind
	s" " baku-string s" *home-directory*" baku-boot-bind
	baku-false s" *hush*" baku-boot-bind
	baku-nil s" *argv*" baku-boot-bind ;

\ ---------------------------------------------------------------------------
\ Initialisation order.  STLIB.INITIALISE must follow SHEN.INITIALISE; it
\ installs the stlib arities, macros, synonyms, datatypes, types and sources.
\ ---------------------------------------------------------------------------

: baku-boot-eval ( c-addr u -- value )
	baku-read-string
	baku-read-form 0= if drop baku-read-eof throw then
	baku-eval-kl ;

: baku-boot-initialise ( -- )
	s" (shen.initialise)" baku-boot-eval drop
	s" (stlib.initialise)" baku-boot-eval drop ;
