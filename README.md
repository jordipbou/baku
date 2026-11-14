# Baku

Baku is a port of the Shen OS Kernel to ANS Forth 2012. It reads the unmodified
Shen 43.2 KLambda kernel at load time and provides the Shen top level. The
implementation is Forth source; CMake, Sloth and gforth are development tools,
not part of the user path.

The requirements are the project entry `~/hub/org/proj.baku.org`
("Project: Baku"), including its `Links` section. This README does not add
requirements: it explains the implementation, records the choices behind it, and
points at the executable checks. Where a choice is not forced by the entry, the
text says so.

The generated primitive-to-ANS mapping is in
[`docs/primitive-manifest.md`](docs/primitive-manifest.md). Its source is
`tools/manifest.py`; do not hand-edit the table.

## Contents

- [Using the sources](#using-the-sources)
- [Architecture](#architecture)
- [Values](#values)
- [Memory](#memory)
- [Execution modes](#execution-modes)
- [Reading and booting the kernel](#reading-and-booting-the-kernel)
- [Primitives, errors and I/O](#primitives-errors-and-io)
- [Testing](#testing)
- [Tooling](#tooling)
- [Licensing and kernel provenance](#licensing-and-kernel-provenance)
- [Design decisions and rejected alternatives](#design-decisions-and-rejected-alternatives)
- [Specification to test traceability](#specification-to-test-traceability)

## Using the sources

There is no build step. The shipped library entry point is `4th/baku.4th`, and
the shipped one-line user entry is `4th/start.4th`. Forth loads every layer with
`INCLUDED`; no generated `.4th` file is created and CMake is not needed to run
Baku.

To reach the Shen top level, include the user entry from the repository root.
The target must be started with enough dictionary space for the non-GC boot
(about 490 MiB of retained kernel data); on gforth:

```sh
gforth -m 768M -d 16M -r 16M
s" 4th/start.4th" INCLUDED
```

or as one command:

```sh
gforth -m 768M -d 16M -r 16M -e 's" 4th/start.4th" INCLUDED'
```

`4th/start.4th` raises the non-GC heap request before `4th/value.4th` loads,
loads `4th/baku.4th`, selects the native installer, reads the 23 vendored
KLambda files, runs `shen.initialise` then `stlib.initialise`, prints
`BAKU-STARTED`, and enters `baku-repl`. It takes about 45 seconds on gforth.

The dictionary flags are a target requirement, not a build step. Why the entry
file exists instead of one word inside `4th/baku.4th`: the non-GC block is a
dictionary reservation sized when `4th/value.4th` loads, the native installer is
selected by the caller so the interpreter remains available as the reference, and
the kernel globals are bound after loading but before initialisation. Loading the
library by itself therefore cannot also choose a lifetime policy without forcing
one on every embedder.

To load only the layers and check the environment, include the library entry
point. It creates no generated file and prints the startup probe:

```sh
gforth -m 64M
s" 4th/baku.4th" INCLUDED
```

The probe reports each required ANS Forth 2012 wordset as `PRESENT` or `ABSENT`
and aborts if one is missing. Baku requires Facility, Memory-Allocation,
Floating, File, Exception and Double-Number; see `4th/probe.4th`.

The one-line session spelled out, for an embedder that wants to pick each step:

```sh
gforth -m 768M -d 16M -r 16M
s" 4th/portability.4th" INCLUDED
536870912 baku-nongc-request !
s" 4th/baku.4th" INCLUDED
' baku-native-install-form is baku-install-form
baku-boot-load-kernel
baku-boot-globals
baku-boot-initialise
baku-repl
```

`baku-boot-initialise` runs `shen.initialise` then `stlib.initialise`, in that
order. The kernel suite's collector boot is the alternative lifetime policy: a
64 MiB non-GC symbol area plus a 256 MiB allocated semispace, with the
interpreter as the executor.

On Sloth the same session works from the repository root; start Sloth with a
dictionary large enough for the heap. The `[DEFINED] gforth` switch at the top of
`4th/baku.4th`, `4th/start.4th` and every test file is the only per-target
*file-inclusion* difference: gforth resolves a nested `INCLUDED` relative to the
including file, Sloth relative to the working directory. It changes no
semantics; the other target difference is the `[DEFINED]`-gated stack-root
adapter in `4th/gc-stack.4th`.

To run the whole test gate:

```sh
./run-tests.sh
```

`./run-tests.sh --kernel-suite` runs the Shen 43.2 kernel suite instead. The
suite is a long conformance measurement (about 100 minutes) and is not part of
the default gate; see [Testing](#testing).

## Architecture

The layers load in a fixed order; each one owns one boundary and later layers
consume the earlier representation.

| File | Responsibility |
|---|---|
| `4th/portability.4th` | ANS fallbacks for `CELL`, `-ROT`, `<=`, `>=`; the pre-load heap and scratch request cells |
| `4th/probe.4th` | Startup probe for the required ANS Forth 2012 wordsets |
| `4th/value.4th` | Tagged values, region map, uniform object headers, constructors and accessors |
| `4th/gc.4th` | Cheney copying collector, roots and activation rules |
| `4th/gc-stack.4th` | Target stack-root adapter; the only non-ANS word use, gated by `[DEFINED]` |
| `4th/arena.4th` | LIFO dictionary arenas released with `MARKER` |
| `4th/reader.4th` | Streaming KLambda text reader |
| `4th/frontend.4th` | Form validation, vector IR and shared tail-position analysis |
| `4th/eval.4th` | Tree-walking interpreter, the correctness reference |
| `4th/native.4th` | Dictionary threaded-code compiler for non-GC and arena modes |
| `4th/primitives.4th` | KLambda host primitives on ANS Forth words |
| `4th/compat.4th` | `input+`, installed as an interpreted KLambda definition |
| `4th/boot.4th` | Kernel load manifest, host globals and the two initialisers |
| `4th/repl.4th` | Top level: standard input, expression mode and file mode |
| `4th/start.4th` | One-line user entry: heap request, native installer, kernel boot and REPL |

The reader produces forms; the front end lowers a form into a mode-independent
IR; both executors consume that IR. The interpreter is not a fallback that can
drift: it is the reference the compiler must match, and the mode matrix compares
them.

## Values

Every Shen value is one Forth cell (`4th/value.4th`). The cell alone decides what
it is:

- an odd cell is a fixnum, represented as `2n+1`;
- a cell whose low three bits are zero is a pointer candidate, and the registered
  regions decide whether it is an object and which lifetime it has;
- a cell whose low three bits are `010` is an immediate; the reserved immediates
  are the empty list, `false` and `true`.

Only pointer cells need region detection, and the region is found from the
address range, never stored in the value or in the object header. Every heap
object starts with a uniform header `payload-bytes*256 + object-type`, so the
collector can classify and size an object without a side table. The object kinds
are cons, string, symbol, vector, closure, stream, error and boxed float.

Symbols are interned case-sensitively in a permanent non-GC table. Interning
after GC activation is the documented exception to the "no non-GC allocation
after bootstrap" rule: a symbol is identity, never traced, never moved, and must
outlive every form that names it. Strings are byte-counted, not terminated;
`\"` does not escape and embedded newlines are data.

The fixnum range is derived from `CELL`, not hard-coded. A fixnum arithmetic
result outside the range is a catchable error rather than a silent wrap. The
current target is 64-bit cells; a later 32-bit Forth adaptation keeps 64-bit
cells and uses double-number arithmetic, so the shipped source already uses the
Double-Number wordset for range checks.

## Memory

Baku has three lifetimes, longest to shortest. The implementation plan records
the reasoning in more detail.

**Non-GC.** A Forth dictionary block created during bootstrap. It holds native
code, constants and permanent symbols. It is never collected. Its size is the
`baku-nongc-request` cell, set before the tree is included; the default 512 KiB
covers the symbol table and constants, and a boot raises it.

**Arenas.** LIFO scopes over the dictionary. Creating an arena defines an ANS
`MARKER` at the current dictionary point and selects a bump heap that advances
`HERE`; freeing the arena executes the marker. There is no collection latency and
no preallocated size. An arena's registered extent ends at its bump pointer, not
at the dictionary limit, so a nested arena does not overlap the outer one and
unallocated space never classifies as an object. The function and global bucket
arrays are snapshotted into the arena and restored before the marker runs, and a
global definition made while an arena is active prepends rather than mutating a
pre-arena binding.

**Cheney GC.** Two semispaces in their own allocated block. When active, the
selected Baku heap is the from-space, so every constructor allocates there
without a second allocator. A collection copies reachable objects with Cheney's
scan, then swaps the semispaces. Forwarding is stored in the old header with the
cell sign bit set; a real header cannot set that bit. The region map is updated
on each flip.

Activation rules follow the entry: the GC is active only when it has been
activated and no arena is active. Activating the GC while an arena exists, or
collecting while one exists, is refused with a catchable error. A freed arena
restores the GC heap and collection resumes.

Roots are the only non-GC memory allowed to hold GC references. They are
registered dictionary cells and ranges, the function and global tables (whose
chains may live in non-GC memory), and the Forth data and return stacks. ANS
Forth 2012 exposes no stack pointer, so `4th/gc-stack.4th` isolates the target
words (`SP0`/`SP@`/`RP0`/`RP@` on gforth) behind `[DEFINED]`; a target without
them keeps the default adapter and GC activation fails with the catchable
`baku-gc-unsupported` instead of collecting with a missing root. The pinned Sloth
takes that documented branch.

Arenas may hold GC references because every arena is freed before the GC moves
or compacts; the GC must not hold references to arena objects. The checked store
is deferred by the project entry, so a violation is a bug rather than a catchable
error. The compiler and runtime avoid raw cross-region stores outside the roots.

## Execution modes

The memory state selects the backend; a user selects a lifetime policy, not a
language. `baku-mode` in `4th/eval.4th` returns arena, GC or non-GC, and the
kernel-visible `eval-kl` dispatches on it.

- **Non-GC** (no GC, no arena): compile KLambda to dictionary threaded code with
  `4th/native.4th`. A code block is `[arity, parameter-symbols..., instructions...,
  RET]`; parameter cells are permanent interned symbols, so dictionary code holds
  no arena or GC reference. Applying a native closure binds the parameters and
  executes the block. Self-tail calls jump back to the block start (`BEGIN ...
  AGAIN`); other tail calls use the shared trampoline.
- **Arena** (arena active, GC on or off): the same native compiler. Raw dictionary
  reservations go through `baku-dict-reserve`, so generated code advances the
  active arena and the `MARKER` reclaims it.
- **GC** (GC active, no arena): the interpreter in `4th/eval.4th` is the executor.
  Code and closures live in the heap and are traced by the collector. The native
  entry refuses GC mode with the catchable `baku-mode-error` rather than writing
  unreclaimable dictionary code.

Tail-position analysis lives once in `4th/frontend.4th`, so every mode uses the
same tail flags. The interpreter's trampoline is its self-tail loop as well: a
tail call stores the closure and arguments in the shared tail cells and returns
`baku-tail-pending`; the nearest trampoline applies the request in a loop. The
observable result is constant return-stack space for self and mutual tail calls.
Native TCO on a particular Forth is optional and not implemented; the self-tail
loop plus the trampoline already provide that property portably.

## Reading and booting the kernel

`4th/reader.4th` is a streaming reader for KLambda text. It returns one top-level
form at a time in a resettable 2 MiB scratch arena; the next read resets it, so a
form is valid only until that next read. This keeps peak memory at the largest
single form (about 1.1 MiB in the pinned corpus) instead of the whole tree.
Symbols are interned permanently and survive the reset. Strings are literal:
`"` terminates, a backslash is data, embedded newlines are data, and no
Forth/JSON escape is decoded. Comments are Shen's `\\` line comment and
`\* ... *\` block comment; `;` and `#` are symbol characters.

`4th/boot.4th` holds the boot manifest: the 23 vendored `.kl` files, the host
globals and the initialisation order. Each form is streamed through the deferred
`baku-install-form`. The default installer is the interpreter, which keeps every
definition's IR in the non-GC heap and is the reference path. A native backend
overrides the deferred word before calling `baku-boot-load-kernel`; the native
installer compiles each form and discards the IR, which is why the supported
non-GC boot keeps much less IR and why `test/boot.4th` measures 6.8 MiB with the
interpreter loader.

The pinned corpus yields 1124 top-level forms: 1118 `defun` forms and 6
copyright strings, with 1117 distinct names because `min` is defined twice. The
loader accepts last-definition-wins. `tools/klambda_parser.py` is the single
corpus parser used by the manifest and expected-definition generators; a raw text
scan gives the wrong counts because `load.kl` contains a defun-shaped string and
`sys.kl` has two forms on one line.

The loader binds the host globals, then `baku-boot-initialise` calls
`shen.initialise` and `stlib.initialise`. `stlib.initialise` is required
(port-upgrades 41.1): without it the stlib arities, macros, synonyms, datatypes
and types are missing even though the defuns exist.

`4th/repl.4th` supplies the top level. The kernel's `lineread` cannot report end
of input, so the host reads lines, uses the kernel parse-only reader to detect an
incomplete form, and then calls the kernel reader, package mapping, history and
evaluator unchanged. Errors are displayed through the kernel
`toplevel-display-exception` and the loop continues. Standard input, a file
script and a supplied expression use the same rules.

## Primitives, errors and I/O

`4th/primitives.4th` implements exactly the host primitives the pinned kernel
applies but does not define. The list and its ANS Forth mapping are generated,
not maintained by hand: `python3 tools/manifest.py --write` regenerates
[`docs/primitive-manifest.md`](docs/primitive-manifest.md), and
`python3 tools/manifest.py --check` fails on a stale file, an unclassified
applied symbol, or a registered primitive the corpus never applies. The manifest
also records every kernel-defined name that resembles a primitive, so a host
implementation cannot silently shadow it.

KLambda special forms (`if`, `and`, `or`, `cond`, `let`, `lambda`, `defun`,
`freeze`, `trap-error`) belong to the front end and evaluator, not to the
primitive table. `eval-kl` is the single Shen-visible executor entry point; the
kernel also calls it as a function, so it is registered as an arity-1 primitive
closure over the Forth entry, not as a second evaluator. `input+` is different:
the kernel has no `defun` for it, so `4th/compat.4th` installs the two-place
`(defun input+ (X Y) (shen.input-h+ X Y))` once as interpreted KLambda
(port-upgrades 41.3).

Arithmetic follows Shen, not Forth: `/` returns an exact integer quotient when
the fixnums divide exactly and a float otherwise, and division by any numeric
zero is catchable. `=` is total Shen equality over numbers, strings, symbols,
vectors and conses; opaque objects compare false. A fixnum result outside the
range is catchable rather than wrapping.

Shen errors are Baku values, not raw Forth codes. A primitive calls
`baku-raise`; `trap-error` is a special form that catches the stored value.
`simple-error` builds an error object with its message bytes inline, and
`error-to-string` copies the message back out. A raw Forth exception remains
catchable as a fixnum. Streams are `baku-type-stream` objects holding a mode and
a file handle: files are byte streams, standard input and output are character
streams. `read-byte` returns `-1` at end of file; `open`, `close`, `write-byte`
and `write-string` return the value the port-upgrade contract requires. A
relative file name is resolved against `*home-directory*` so `cd` and `load`
agree.

## Testing

Tests are `test/*.4th`, registered by CMake for Sloth and gforth. A test passes
only when it exits zero *and* prints `BAKU-TEST-DONE`; `test/run-test.cmake` is
the runner that enforces both, because CTest's output matching alone would ignore
a non-zero exit. `./run-tests.sh` builds the pinned Sloth, runs each target and
prints one PASS/FAIL/NOT RUN line per target plus the host checks.

The layers and their tests:

- values, primitives, vectors, symbols, errors and I/O: direct calls and calls
  through `baku-eval-kl`;
- `test/reader.4th`: the real 23-file corpus, form and definition counts, the
  string traps and reader errors;
- `test/frontend.4th`, `test/eval.4th`, `test/native.4th`: IR shape and tail
  positions, special forms, currying, globals, tail calls, native codegen,
  installer and error paths;
- `test/gc.4th`, `test/arena.4th`, `test/arena-native.4th`: region classification,
  release, roots, cycles, cross-region rules and native code in arenas;
- `test/gc-mode.4th`, `test/mode-differential.4th`, `test/mode-matrix.4th`: the
  same program through the interpreter, native non-GC, arena and GC paths, with
  structural equality, formatted bytes and error classes compared;
- `test/conformance.4th`, `test/differential.4th`,
  `test/differential-targets.cmake`: a fixed program set on both targets with
  byte-identical output (marked lines for the differential, everything through
  `BAKU-TEST-DONE` for the conformance fixture);
- `test/boot.4th`, `test/boot-native.4th`, `test/repl.4th`, `test/repl-eof.4th`,
  `test/kernel.4th`: the load manifest, both initialisers, the top level and
  kernel-defined behaviour after boot.

`docs/spec-traceability.md` maps every specification acceptance criterion and
every contract entry statement to a registered test or a dated waiver.
`tools/traceability-audit.py --check` is the gate: it fails on an orphan
criterion, a stale row, an unknown test name or a stale document, and it also
executes the documentation criteria (README sections, rejected alternatives,
runner markers and no status prose in `.ralph/AGENTS.md`). Regenerate the
document with `--write` after changing a spec or the coverage table.

The official Shen 43.2 suite is vendored under `vendor/shen-43.2/tests` and run
by `test/kernel-suite.4th`. It is Shen source for a booted top level: the test
boots under the Cheney collector with a 256 MiB semispace, loads `harness.shen`
then `kerneltests.shen`, supplies `y` lines for a failed-check prompt, and gates
on the package-scoped counters. It is labelled `long` and excluded from the
default target loops.

The native non-GC boot keeps every allocation, so `test/boot-native.4th`,
`test/kernel.4th` and `test/repl.4th` request a 512 MiB non-GC heap, a 4 MiB IR
scratch and a 2 MiB reader scratch. They are gforth-only because Sloth's Debug
native execution is too slow for the gate; the exclusion is explicit in
`CMakeLists.txt`, not a silent skip. The collector tests run on both targets, but
Sloth asserts the documented unsupported activation path because it exposes no
stack pointers.

## Tooling

CMake and Ninja orchestrate the tests only. Configure and run the fast gate
manually with:

```sh
cmake -S . -B build -G "Ninja Multi-Config"
cmake --build build --config Debug --target sloth
ctest --test-dir build -C Debug -LE long -R '^baku_' --output-on-failure
```

CMake fetches the pinned Sloth revision and builds a 640 MiB-dictionary test
platform with 16384-cell data and return stacks. It also requires gforth and
python3 at configure time: gforth is a required acceptance target, and python3
runs the ANS audit and the primitive manifest. Their absence is a loud configure
failure, never a silent skip. `build/baku-targets.txt` is generated at configure
time and is the single target list that `run-tests.sh` reads.

Host-side checks that do not need a Forth target:

```sh
ctest --test-dir build -C Debug -R '^baku_(kernel_digest|tests_digest|release_asset)' --output-on-failure
ctest --test-dir build -C Debug -R '^baku_(ans_audit|vendor_audit|region_audit|provenance_audit|primitive_manifest)' --output-on-failure
```

`tools/ans-audit.py` follows `4th/baku.4th` and maps every external word to its
ANS Forth 2012 wordset. It fails on any non-standard word except the two
documented stack-pointer words isolated in `4th/gc-stack.4th`. This keeps the
"completely ANS Forth 2012" claim executable rather than aspirational.

`tools/vendor-audit.py` uses the same shipped-file graph. It allows exactly one
vendored path literal, the `BAKU-BOOT-DIR` read prefix in `4th/boot.4th`, and
fails if any boot-path unit contains a write, rename, delete, resize or
string-replacement operation. Its self-test inserts a write through the prefix
and a replacement aimed at a vendored file; both must be reported.

`tools/region-audit.py` reviews every raw address store in the same shipped
graph. Stores to named dictionary cells are ordinary; every computed-address
store must appear in its reviewed table with the enclosing definition, a
category and a reason. Object payload stores are allowed only in the value
layer's constructors and writers, plus the closure writer. A new raw store, or
an extra store inside a reviewed definition, fails the audit. Its self-test
injects a raw cons-payload store in the compiler and an extra store in a
reviewed writer; both must be reported, while a dictionary-cell store still
passes. This is the executable form of the deferred checked-store rule.

`tools/provenance-audit.py` checks the licence and provenance obligation: the
MIT repository licence, the BSD 3-Clause kernel licence, the pinned release
identity recorded in both provenance files, the vendored release tarball's
SHA-256, and the README references to both. Its self-test corrupts each of those
in turn and requires the audit to fail. `test/release-asset.cmake` extracts the
vendored tarball and re-runs the tree-digest verifier on both extracted trees,
so the extracted bytes are proved against the artifact without a download while
the digest tests above check the trees at rest.

## Licensing and kernel provenance

Baku is MIT-licensed; see [`LICENSE`](LICENSE). The vendored Shen kernel is
Copyright (c) 2010-2022 Mark Tarver and is distributed under the BSD 3-Clause
license; see `vendor/shen-43.2/LICENSE.txt`.

The kernel under `vendor/shen-43.2/klambda/` is the unmodified official
`shen-43.2` release. `vendor/shen-43.2/README.md` records the upstream project,
tag, commit, asset URL, asset SHA-256, extracted-tree digest and vendoring date.
The official test suite is vendored verbatim beside it under
`vendor/shen-43.2/tests/`, with the same provenance in
`vendor/shen-43.2/TESTS.md`. The unmodified release tarball
`vendor/shen-43.2/ShenOSKernel-43.2.tar.gz` is vendored with them so the checksum
check runs offline. Do not edit either tree; a boot failure is fixed in Baku's
reader, executor or primitives, never in a kernel file. The tree digests prove
the bytes at rest, `test/release-asset.cmake` proves the extracted trees are the
tarball's trees, `tools/vendor-audit.py` proves shipped Forth has no write or
replacement path aimed at them, `tools/provenance-audit.py` proves the licence
and metadata obligation, and the no-build test re-digests the copied corpus
after a full boot.

Recompute both tree digests with the same verifier:

```sh
cmake -DTREE=vendor/shen-43.2/klambda \
      -DEXPECTED_FILE=vendor/shen-43.2/README.md \
      -P tools/verify-kernel-digest.cmake
cmake -DTREE=vendor/shen-43.2/tests \
      -DEXPECTED_FILE=vendor/shen-43.2/TESTS.md \
      -DLABEL=BAKU-TESTS-DIGEST \
      -P tools/verify-kernel-digest.cmake
```

`ctest -R '^baku_kernel_digest|^baku_tests_digest'` also runs deliberate-tamper
self-tests, so a broken verifier cannot look green.

## Design decisions and rejected alternatives

- **One-cell tagged values with a uniform header.** Requirement: values are
  tagged and GC pointers are region-detected by address. Choice: `2n+1` fixnums,
  three-bit immediates, and a `payload-bytes*256+type` header on every object.
  Rejected: a separate tag word or a side table for object kinds, which costs
  memory and breaks the collector's ability to size an arbitrary object.
- **Region by address.** Requirement: no separate region tag. Choice: an ordered
  region map, exact `[start, end)` bounds and a pop on release. Rejected: a region
  tag in the value or header, which would have to be maintained on every store and
  copied object.
- **Three lifetimes instead of one collector.** Requirement: non-GC native code,
  `MARKER`-released arenas and a Cheney GC. Choice: keep the three mechanisms and
  select the executor from the active memory state. Rejected: collecting
  everything with one GC, which would make native code and deterministic
  temporary scopes pay collection latency; rejected: one lifetime, which cannot
  meet both no-latency reclaim and a bounded dynamic heap.
- **Deferred checked store.** Requirement: no cross-region references outside the
  roots; the checked store is explicitly deferred. Choice: rely on the allocator
  and constructor APIs plus tests, and review every raw address store with
  `tools/region-audit.py` so an unreviewed one fails the gate. Rejected: a tagged
  store on every write, which the entry does not require and which would slow
  every mutation while adding an error path the kernel does not expect.
- **Dictionary threaded code, not C or bytecode.** Requirement: ANS Forth only,
  no host-language runtime. Choice: emit dictionary cells with an explicit opcode
  and a small inner interpreter; the parameter cells are permanent symbols.
  Rejected: C code generation (violates the Forth-only rule) and a heap bytecode
  VM for non-GC mode (cannot use `MARKER` reclaim and adds a fourth
  representation).
- **The interpreter is the reference.** Choice: every mode consumes the same IR
  and must produce the same value, printed bytes and error class; the matrix test
  compares them. Rejected: trusting the compiler as both implementation and
  oracle, which would hide a shared lowering bug.
- **Streaming reader.** Choice: one form at a time in a resettable scratch arena,
  with permanent symbols. Rejected: parsing the whole corpus into one tree, which
  needs the whole-corpus peak plus a second copy and makes a short-memory target
  unusable.
- **Permanent symbols.** Choice: a case-sensitive non-GC symbol table; interning
  after GC activation is the documented exception. Rejected: GC-allocated symbols,
  which would make symbol identity depend on collection and force the collector to
  trace every symbol reference.
- **Sloth and gforth are test platforms, not requirements.** Choice: run the same
  sources on both where they can, and fail loudly if a required target is absent.
  Rejected: declaring a product target list; the entry requires ANS Forth 2012,
  not a particular implementation.
- **Vendored kernel and suite.** Choice: vendor the pinned release bytes with
  digests instead of fetching at load time. Rejected: fetching a moving branch,
  which would make a boot result depend on the network and the calendar.

## Status

The pinned kernel boots and initialises on gforth. The long kernel-suite gate
requires at least 154 passes and zero failures; it is opt-in because the
interpreter boot under the collector takes about 100 minutes. The default Debug
gate covers the value, memory, reader, front-end, evaluator, native, arena, GC,
mode, differential, boot and top level layers on Sloth and gforth. Current counts
and remaining work belong to the development plan, not to this README.

## Specification to test traceability

The test strategy requires every acceptance criterion to have a named test.
`docs/spec-traceability.md` is generated from `.ralph/specs/*.md` and the
reviewed coverage table in `tools/traceability-audit.py`; do not hand-edit it.
A criterion is covered by registered CTest names or by a dated waiver, and the
audit resolves every name against `build/baku-tests.txt`, which CMake writes
from the real CTest registrations. This keeps one source of truth for the tests
and one for the mapping, and turns a renamed test or a new spec bullet into a
gate failure instead of silent drift.
