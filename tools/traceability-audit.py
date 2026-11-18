#!/usr/bin/env python3
"""Prove specification-to-test traceability for Baku.

The test-strategy requirement says every specification acceptance criterion has
at least one named test.  The specs live in the Ralph workspace, outside this
repository, so this audit reads them at check time and compares them with a
reviewed coverage table.  A criterion is either covered by one or more
registered CTest tests, or it carries a dated waiver explaining why it cannot
run here.

The coverage table below is the single source of truth for the mapping.  The
committed ``docs/spec-traceability.md`` is generated from it and from the spec
criteria; ``--check`` fails when either side drifts.

Checks:

  * every acceptance criterion and every contract entry statement has exactly
    one coverage row, and every row names a real criterion;
  * every named test is registered in the CTest list written by CMake, so a
    renamed or removed test cannot leave a stale claim;
  * every glob-registered test that is not enabled for Sloth is either in the
    explicit exclusion list with a reason comment or explicitly registered with
    a comment;
  * every registered host primitive is called directly by a test file, with a
    documented exception for ``eval-kl`` (the kernel applies it);
  * the generated traceability document matches the table and the specs;
  * the documentation criteria are executable: README headings, the
    problem/choice/rejected shape of every design decision, the requirements
    pointer, the runner markers, and no status or progress prose in
    ``.ralph/AGENTS.md``;
  * a dated waiver replaces the tests when a criterion cannot run in this
    environment (offline checks and the deferred 32-bit adaptation).

Usage:

    python3 tools/traceability-audit.py --write
    python3 tools/traceability-audit.py --check
    python3 tools/traceability-audit.py --self-test
"""

import argparse
import datetime
import os
import re
import sys
import tempfile
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
DEFAULT_SPECS = HERE.parent / ".ralph" / "specs"
DEFAULT_AGENTS = HERE.parent / ".ralph" / "AGENTS.md"
OUTPUT = HERE / "docs" / "spec-traceability.md"

WAIVER_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}):\s+\S")

# "eval-kl" is the executor entry point: the kernel applies it during
# initialisation, so no test calls the host word directly.  The boot and kernel
# tests exercise it end to end.
PRIMITIVE_EXCEPTIONS = {
    "eval-kl": "the kernel applies it; the boot, no-build and kernel tests "
               "exercise it end to end",
}

# Coverage rows keyed by criterion id.  The value is (tests, evidence): tests
# is a comma-separated list of registered CTest names, and evidence explains
# what the named checks prove or why a dated waiver is the honest answer.
COVERAGE = {
    # ans-forth-only.md
    "ans-forth-only#1": (
        "baku_ans_audit, baku_ans_audit_selftest",
        "The audit lists every shipped word with its ANS Forth 2012 wordset; the "
        "self-test proves a forbidden word fails the check.",
    ),
    "ans-forth-only#2": (
        "baku_ans_audit_selftest",
        "The self-test injects a DODO word, a host-language construct and a "
        "non-standard word and requires a non-zero result.",
    ),
    "ans-forth-only#3": (
        "baku_values_sloth, baku_values_gforth, baku_conformance_sloth, "
        "baku_conformance_gforth",
        "The same sources run on the two 64-bit targets; the 32-bit adaptation is "
        "deferred by the M0 decision.",
    ),
    "ans-forth-only#4": (
        "baku_ans_audit, baku_ans_audit_selftest",
        "The static scan rejects host-language constructs, DODO references and "
        "[DEFINED]/[UNDEFINED] guards on C, Java or JavaScript, while allowing ANS "
        "words and the gforth target; the self-test injects a host-conditional branch "
        "and a legal ANS-word guard.",
    ),

    # bootstrap-and-repl.md
    "bootstrap-and-repl#1": (
        "",
        "2026-11-18: the collector boot path lands in P2; the current boot tests "
        "select the native installer, so no test yet boots through the collector.",
    ),
    "bootstrap-and-repl#2": (
        "",
        "2026-11-18: the GC boot-order test lands in P2; boot-native currently "
        "activates the collector after a non-GC boot.",
    ),
    "bootstrap-and-repl#3": (
        "baku_repl_gforth, baku_no_build",
        "The Shen top level prints 3 for (+ 1 2) in both the script and the "
        "copied-checkout path.",
    ),
    "bootstrap-and-repl#4": (
        "baku_repl_gforth, baku_no_build",
        "The top level prints 3628800 for (factorial 10).",
    ),
    "bootstrap-and-repl#5": (
        "baku_kernel_gforth, baku_kernel-suite_gforth",
        "arity factorial is 1, stlib arities resolve, and the suite exercises stlib "
        "macros and datatypes.",
    ),
    "bootstrap-and-repl#6": (
        "baku_repl_gforth",
        "The version output and credits banner report 43.2.",
    ),
    "bootstrap-and-repl#7": (
        "baku_repl_gforth, baku_primitives_gforth",
        "A top-level error is caught through error-to-string and the next expression "
        "still evaluates.",
    ),
    "bootstrap-and-repl#8": (
        "baku_repl-eof_gforth, baku_no_build, baku_io_sloth, baku_io_gforth",
        "End of input exits with status zero; the boot path closes every file it opens "
        "and the no-build run re-digests the corpus afterwards.",
    ),
    "bootstrap-and-repl#9": (
        "baku_boot_sloth, baku_boot_gforth",
        "The boot test checks the manifest against the loader, the 23 files, 1124 "
        "forms and 1118 defuns, and it uses the default interpreter installer rather "
        "than a native installer.",
    ),

    # contract.md
    "contract#1": (
        "baku_spec_traceability",
        "This audit and its generated document map every contract statement and every "
        "spec criterion to a test or a dated waiver.",
    ),
    "contract#2": (
        "baku_ans_audit, baku_ans_audit_selftest, baku_probe_sloth, baku_probe_gforth, "
        "baku_values_sloth, baku_values_gforth, baku_conformance_sloth, "
        "baku_conformance_gforth, baku_reader_sloth, baku_reader_gforth, "
        "baku_boot_sloth, baku_boot_gforth, baku_kernel-suite_gforth, baku_gc_gforth, "
        "baku_region_audit, baku_region_audit_selftest, baku_eval_sloth, "
        "baku_eval_gforth",
        "Statements 2, 3, 4, 7, 13 and 17 are each checked by the named audits and "
        "tests; the superseded and deferred statements carry dated waivers in their "
        "own rows.",
    ),
    "contract#3": (
        "baku_compat_sloth, baku_compat_gforth, baku_kernel_gforth, "
        "baku_primitives_sloth, baku_primitives_gforth, baku_io_sloth, baku_io_gforth",
        "stlib.initialise, callable input+, zero-place fn/thaw and the public "
        "char-stream?/read-unit-string/write-string arities have named checks.",
    ),
    "contract#4": (
        "baku_ans_audit, baku_vendor_audit, baku_no_build",
        "The shipped graph is a static Forth-only view; the no-build test runs the "
        "sources without CMake or a build directory.",
    ),
    "contract#5": (
        "baku_no_build, baku_probe_sloth, baku_probe_gforth, baku_ans_audit",
        "4th/start.4th loads with INCLUDED from the repository root and the probe "
        "reports the required wordsets.",
    ),
    "contract#6": (
        "baku_kernel_digest, baku_tests_digest, baku_kernel-suite_gforth",
        "Behaviour is checked against the pinned corpus and suite digests, not a "
        "moving branch.",
    ),
    "contract#statement-1": (
        "baku_kernel-suite_gforth, baku_ans_audit",
        "The Shen 43.2 suite runs on the ANS Forth 2012 sources.",
    ),
    "contract#statement-2": (
        "baku_ans_audit, baku_ans_audit_selftest, baku_probe_sloth, baku_probe_gforth",
        "The audit rejects anything outside the standard; the probe uses [DEFINED] "
        "detection for optional wordsets.",
    ),
    "contract#statement-3": (
        "baku_values_sloth, baku_values_gforth, baku_conformance_sloth, "
        "baku_conformance_gforth",
        "64-bit cells and wide literals are exercised on both targets; the 32-bit "
        "adaptation remains deferred.",
    ),
    "contract#statement-4": (
        "baku_reader_sloth, baku_reader_gforth, baku_boot_sloth, baku_boot_gforth, "
        "baku_kernel-suite_gforth",
        "The KLambda corpus reads and boots unmodified, including the Shen reader and "
        "compiler it ships.",
    ),
    "contract#statement-5": (
        "baku_values_sloth, baku_values_gforth, baku_gc_gforth, baku_primitives_sloth, "
        "baku_primitives_gforth, baku_eval_sloth, baku_eval_gforth",
        "The value layer, collector, primitives and the interpreter executor are "
        "exercised by named tests.",
    ),
    "contract#statement-6": (
        "baku_boot_sloth, baku_boot_gforth, baku_kernel_gforth, "
        "baku_kernel-suite_gforth, baku_no_build",
        "Full Shen boots and initialises through the KLambda layer.",
    ),
    "contract#statement-7": (
        "baku_values_sloth, baku_values_gforth, baku_gc_gforth",
        "Values are tagged; region classification is by exact address range.",
    ),
    "contract#statement-8": (
        "",
        "2026-11-18: superseded by the JTBD; the non-GC block is now the permanent "
        "symbol area and the replacement entry text is proposed in the final report.",
    ),
    "contract#statement-9": (
        "",
        "2026-11-18: superseded by the JTBD; the arena subsystem is removed and the "
        "replacement entry text is proposed in the final report.",
    ),
    "contract#statement-10": (
        "baku_gc_sloth, baku_gc_gforth, baku_gc-mode_gforth",
        "The Cheney collector owns its heap block; when active, code lives in the heap "
        "and the interpreter runs it.",
    ),
    "contract#statement-11": (
        "",
        "2026-11-18: superseded by the JTBD; there is no arena-activation rule in the "
        "target and the replacement entry text is proposed in the final report.",
    ),
    "contract#statement-12": (
        "baku_gc_gforth, baku_gc-mode_gforth, baku_kernel-suite_gforth",
        "Roots are created before the loader runs and traced across the forced "
        "collection after the boot.",
    ),
    "contract#statement-13": (
        "baku_region_audit, baku_region_audit_selftest",
        "Every raw address store is reviewed; the self-test proves an injected "
        "unreviewed store fails.",
    ),
    "contract#statement-14": (
        "",
        "2026-11-18: superseded by the JTBD; arenas and arena-held references are "
        "removed and the replacement entry text is proposed in the final report.",
    ),
    "contract#statement-15": (
        "",
        "2026-11-18: superseded by the JTBD; the three compilation modes are removed "
        "and the replacement entry text is proposed in the final report.",
    ),
    "contract#statement-16": (
        "",
        "2026-11-18: deferred with the native compiler; the interpreter uses the "
        "shared trampoline and the replacement entry text is proposed in the final "
        "report.",
    ),
    "contract#statement-17": (
        "baku_eval_sloth, baku_eval_gforth, baku_gc-mode_sloth, baku_gc-mode_gforth",
        "Mutual tail calls run in constant return-stack space through the interpreter "
        "trampoline.",
    ),
    "contract#statement-18": (
        "baku_frontend_sloth, baku_frontend_gforth",
        "Tail-position analysis is part of the shared front end and its tail flags are "
        "checked.",
    ),
    "contract#statement-19": (
        "",
        "2026-11-18: deferred with the native compiler; native TCO is not part of the "
        "GC-only target and the replacement entry text is proposed in the final "
        "report.",
    ),
    "contract#statement-20": (
        "baku_spec_traceability, baku_kernel-suite_gforth",
        "The Links section is the requirement source and kernel behaviour is checked "
        "against the pinned suite, not an imported port design.",
    ),
    "contract#statement-21": (
        "baku_no_build",
        "A copied checkout with only 4th/ and the corpus reaches the Shen top level "
        "through one include line.",
    ),

    # documentation.md
    "documentation#1": (
        "baku_link_audit, baku_link_audit_selftest",
        "The audit extracts every link from proj.baku.org and requires each to be "
        "reachable or to carry a reviewed dated offline acceptance; its self-test "
        "proves a missing, extra, dangling or unreviewed link fails.",
    ),
    "documentation#2": (
        "baku_spec_traceability",
        "The audit checks the purpose statement and the architecture, memory, "
        "execution, I/O, testing and licensing sections. The single-execution-path "
        "wording is a dated waiver until P5 rewrites the README and README_HEADINGS "
        "together.",
    ),
    "documentation#3": (
        "baku_spec_traceability",
        "The audit requires every design-decision bullet to state the choice and the "
        "alternative it rejected.",
    ),
    "documentation#4": (
        "baku_spec_traceability, baku_no_build",
        "The README's documented commands include a passing test command; the no-build "
        "test runs the same user path.",
    ),
    "documentation#5": (
        "baku_spec_traceability",
        "The audit rejects pass counts, gate outcomes and iteration status in "
        ".ralph/AGENTS.md.",
    ),
    "documentation#6": (
        "baku_spec_traceability, baku_provenance_audit",
        "The README names proj.baku.org, states that it adds no requirements and links "
        "the generated documents instead of copying them.",
    ),
    "documentation#7": (
        "",
        "2026-11-18: the README and generated traceability document are rewritten to "
        "the single collector lifetime and single interpreter executor in P5.",
    ),
    "documentation#8": (
        "",
        "2026-11-18: the measurement table, exact verification commands and proposed "
        "replacement entry text are the final-report deliverable in P5.",
    ),

    # forth-portability.md
    "forth-portability#1": (
        "baku_conformance_sloth, baku_conformance_gforth",
        "The fixed expression set loads 4th/baku.4th and prints the marker on both "
        "targets.",
    ),
    "forth-portability#2": (
        "baku_conformance_sloth, baku_conformance_gforth",
        "The set covers arithmetic, comparison, cons/list, strings, symbols, vectors, "
        "trap-error and a tail countdown.",
    ),
    "forth-portability#3": (
        "baku_conformance_targets",
        "The same file runs on Sloth and gforth; only its stdout through "
        "BAKU-TEST-DONE is compared, so launcher chatter is normalised away.",
    ),
    "forth-portability#4": (
        "baku_ans_audit",
        "The audit reports every non-ANS word; the only exceptions are the two "
        "documented stack-pointer words in the gated GC adapter.",
    ),
    "forth-portability#5": (
        "baku_values_sloth, baku_values_gforth, baku_probe_sloth, baku_probe_gforth",
        "Both targets report 64-bit cells and pass the value suite.",
    ),
    "forth-portability#6": (
        "",
        "2026-11-14: the 32-bit adaptation is deferred by the M0 decision; the gap is "
        "recorded here and in the plan, and no 32-bit target exists.",
    ),

    # gc-only-execution.md
    "gc-only-execution#1": (
        "",
        "2026-11-18: the arena and native sources are removed in P3 and P4; until then "
        "shipped source still names them and boot-native is the user path.",
    ),
    "gc-only-execution#2": (
        "",
        "2026-11-18: the collector boot and its post-boot collection land in P2.",
    ),
    "gc-only-execution#3": (
        "",
        "2026-11-18: the curried-application and trap-error checks under the collector "
        "are added to gc-mode in P4.",
    ),
    "gc-only-execution#4": (
        "",
        "2026-11-18: the non-callable and over-applied closure checks under the "
        "collector are added to gc-mode in P4.",
    ),
    "gc-only-execution#5": (
        "",
        "2026-11-18: the reader scratch region is renamed and its survival test is "
        "added in P3.",
    ),
    "gc-only-execution#6": (
        "",
        "2026-11-18: the native backend is removed in P4; until then it is a second "
        "consumer of the IR.",
    ),
    "gc-only-execution#7": (
        "",
        "2026-11-18: the GC-only tail test, including mutual recursion, is rewritten "
        "in P4.",
    ),
    "gc-only-execution#8": (
        "",
        "2026-11-18: the removed-name static check and the source deletions land in "
        "P4.",
    ),
    "gc-only-execution#9": (
        "",
        "2026-11-18: the collector-before-kernel boot order is added in P2; the Sloth "
        "load-order evidence is measured then.",
    ),

    # kernel-provenance.md
    "kernel-provenance#1": (
        "baku_release_asset, baku_release_asset_selftest, baku_provenance_audit, "
        "baku_kernel_digest",
        "The release-asset check recomputes the vendored tarball's official SHA-256 "
        "and re-runs the tree digest on its extracted klambda/ tree; the provenance "
        "audit re-hashes the asset and the kernel digest checks the tree at rest.",
    ),
    "kernel-provenance#2": (
        "baku_release_asset, baku_kernel_digest",
        "No upstream checkout exists in this sandbox; the vendored tarball is "
        "extracted and both extracted trees must match the recorded digests, the "
        "offline equivalent of an empty upstream diff, while the tree digest checks "
        "the vendored bytes at rest.",
    ),
    "kernel-provenance#3": (
        "baku_reader_sloth, baku_reader_gforth, baku_boot_sloth, baku_boot_gforth",
        "The parsed corpus yields 1124 forms, 1118 defuns and 1117 distinct names, and "
        "the loader accepts the duplicate min.",
    ),
    "kernel-provenance#4": (
        "baku_reader_sloth, baku_reader_gforth",
        "The reader test compares the parsed set with an independent string-aware "
        "parser and pins both corpus traps.",
    ),
    "kernel-provenance#5": (
        "baku_vendor_audit, baku_vendor_audit_selftest, baku_kernel_digest_tamper, "
        "baku_tests_digest_tamper",
        "The source scan rejects writes or replacements; the tamper tests reject "
        "modified bytes.",
    ),
    "kernel-provenance#6": (
        "baku_provenance_audit, baku_provenance_audit_selftest",
        "Both licence texts and the README references are checked, and the self-test "
        "corrupts each record in turn.",
    ),

    # klambda-primitives.md
    "klambda-primitives#1": (
        "baku_primitive_manifest, baku_primitive_manifest_selftest",
        "The manifest is generated from parsed applications and classifies every "
        "applied host symbol; eval-kl is a registered primitive.",
    ),
    "klambda-primitives#2": (
        "baku_primitive_manifest, baku_primitive_manifest_selftest",
        "The check is bidirectional over corpus applications, registrations and defun "
        "names.",
    ),
    "klambda-primitives#3": (
        "baku_primitive_manifest, baku_primitive_manifest_selftest",
        "Every row names its ANS words or Baku heap and the excluded names carry their "
        "defining file.",
    ),
    "klambda-primitives#4": (
        "baku_spec_traceability, baku_primitives_sloth, baku_primitives_gforth, "
        "baku_io_sloth, baku_io_gforth, baku_compat_sloth, baku_compat_gforth",
        "The audit requires a direct test call for every registered primitive (eval-kl "
        "is the kernel-applied exception); the type-error paths are checked in the "
        "primitive and I/O tests.",
    ),
    "klambda-primitives#5": (
        "baku_primitives_sloth, baku_primitives_gforth",
        "The error group checks the inline message, one-shot handlers, nesting and "
        "re-raising.",
    ),
    "klambda-primitives#6": (
        "baku_io_sloth, baku_io_gforth",
        "The I/O group round-trips bytes and text through a file and closes every "
        "stream.",
    ),
    "klambda-primitives#7": (
        "baku_kernel_gforth, baku_io_sloth, baku_io_gforth",
        "kernel.4th checks (arity char-stream?) 1, (arity read-unit-string) 1 and "
        "(arity write-string) 2; the I/O group checks the results.",
    ),
    "klambda-primitives#8": (
        "baku_compat_sloth, baku_compat_gforth, baku_kernel_gforth",
        "input+ is a two-place closure that delegates to shen.input-h+, including the "
        "higher-order (fn input+) form.",
    ),
    "klambda-primitives#9": (
        "baku_primitives_sloth, baku_primitives_gforth",
        "The time group checks unix plausibility and run monotonicity with catchable "
        "argument errors.",
    ),
    "klambda-primitives#10": (
        "",
        "2026-11-14: the fixnum edge is checked on 64-bit cells; the 32-bit cell "
        "adaptation that this criterion names is deferred by M0.",
    ),

    # klambda-reader.md
    "klambda-reader#1": (
        "baku_reader_sloth, baku_reader_gforth",
        "All 23 vendored files read with zero errors.",
    ),
    "klambda-reader#2": (
        "baku_reader_sloth, baku_reader_gforth",
        "The counts are 1118 defuns and 1117 distinct names.",
    ),
    "klambda-reader#3": (
        "baku_reader_sloth, baku_reader_gforth",
        "The six copyright strings read as top-level strings and the following defuns "
        "still read.",
    ),
    "klambda-reader#4": (
        "baku_reader_sloth, baku_reader_gforth",
        "The name set matches the independent parser and both corpus traps are "
        "explicit checks.",
    ),
    "klambda-reader#5": (
        "baku_reader_sloth, baku_reader_gforth, baku_boot_sloth, baku_boot_gforth",
        "Both min forms read and last-definition-wins is checked.",
    ),
    "klambda-reader#6": (
        "baku_reader_sloth, baku_reader_gforth, baku_kernel_gforth",
        "The pre-boot test-local printer round-trips a representative corpus; the "
        "booted kernel writer round-trip is a separate kernel check.",
    ),
    "klambda-reader#7": (
        "baku_reader_sloth, baku_reader_gforth, baku_primitives_sloth, "
        "baku_primitives_gforth",
        "The literals read and compare on 64-bit cells; the 32-bit cell run is part of "
        "the deferred adaptation.",
    ),
    "klambda-reader#8": (
        "baku_reader_sloth, baku_reader_gforth",
        "2^62-1 and -2^62 are accepted and one past each end raises the located number "
        "error.",
    ),
    "klambda-reader#9": (
        "baku_reader_sloth, baku_reader_gforth",
        "Comment-only fixtures yield an empty form list.",
    ),
    "klambda-reader#10": (
        "baku_reader_sloth, baku_reader_gforth",
        "A malformed fixture reports a location and the reader still reads the next "
        "valid form.",
    ),

    # memory-management.md
    "memory-management#1": (
        "baku_region_audit, baku_region_audit_selftest",
        "Every raw store is reviewed; the self-test injects an unreviewed "
        "computed-address store.",
    ),
    "memory-management#2": (
        "baku_region_audit, baku_region_audit_selftest, baku_gc_gforth",
        "The audit accepts reviewed same-region writers and the permanent symbol "
        "table; gc.4th interns a new symbol after activation and keeps it across a "
        "collection.",
    ),
    "memory-management#3": (
        "",
        "2026-11-18: the permanent-symbol survival check lands with the reader scratch "
        "check in P3.",
    ),
    "memory-management#4": (
        "",
        "2026-11-18: the reader scratch extent check lands in P3 with the arena "
        "removal.",
    ),
    "memory-management#5": (
        "baku_gc_gforth",
        "The collector preserves cycles, shared tails and reachable values and "
        "reclaims unreachable ones.",
    ),
    "memory-management#6": (
        "baku_gc_gforth",
        "A stress loop allocates and collects repeatedly with consistent accounting.",
    ),

    # no-build-step.md
    "no-build-step#1": (
        "baku_no_build",
        "A clean copied checkout loads 4th/start.4th and reaches BAKU-STARTED and the "
        "Shen top level.",
    ),
    "no-build-step#2": (
        "baku_no_build",
        "The test copies the checkout to a fresh path with no build directory.",
    ),
    "no-build-step#3": (
        "baku_no_build",
        "The copied tree omits CMakeLists.txt, run-tests.sh and build/ and still "
        "boots.",
    ),
    "no-build-step#4": (
        "baku_no_build",
        "The test requires the shipped .4th file set to be unchanged after the boot.",
    ),

    # startup-memory.md
    "startup-memory#1": (
        "",
        "2026-11-18: the request cell and its assertion are added in P1.",
    ),
    "startup-memory#2": (
        "",
        "2026-11-18: the default GC boot is the P2 user path.",
    ),
    "startup-memory#3": (
        "",
        "2026-11-18: the 8/16/32 MiB measurement table is a P1 process deliverable "
        "recorded in the final report.",
    ),
    "startup-memory#4": (
        "",
        "2026-11-18: the total-reservation budget assertion is added to gc-boot in P2.",
    ),
    "startup-memory#5": (
        "",
        "2026-11-18: the symbol-area capacity checks land with gc-boot and the suite "
        "override in P2.",
    ),
    "startup-memory#6": (
        "",
        "2026-11-18: the post-boot collection and allocation loop are added to gc-boot "
        "in P2.",
    ),
    "startup-memory#7": (
        "",
        "2026-11-18: the user entry and no-build flags shrink to the measured "
        "dictionary in P1 and P2.",
    ),
    "startup-memory#8": (
        "",
        "2026-11-18: the shared defaults are wired through start.4th, gc-boot, "
        "no-build and the suite in P1 and P2.",
    ),

    # tail-calls.md
    "tail-calls#1": (
        "baku_eval_sloth, baku_eval_gforth",
        "100,000-deep self-tail countdowns complete through the interpreter trampoline "
        "without overflowing the return stack.",
    ),
    "tail-calls#2": (
        "baku_eval_sloth, baku_eval_gforth",
        "The mutual even/odd deep chain completes in constant space through the "
        "interpreter trampoline.",
    ),
    "tail-calls#3": (
        "baku_boot_sloth, baku_boot_gforth, baku_repl_gforth",
        "Boot loads the tail-recursive kernel loop and the top level drives shen.loop.",
    ),
    "tail-calls#4": (
        "",
        "2026-11-18: the return-stack bound under the collector moves to the GC-only "
        "gc-mode test in P4; eval.4th runs on the layer heap.",
    ),
    "tail-calls#5": (
        "",
        "2026-11-18: the cross-mode differential is removed; P4 adds the "
        "before/after-collection tail comparison to gc-mode.",
    ),
    "tail-calls#6": (
        "baku_frontend_sloth, baku_frontend_gforth, baku_eval_sloth, baku_eval_gforth",
        "The front end pins tail flags through if/cond and let bodies, and a non-tail "
        "branch consumes a frame.",
    ),

    # testing.md
    "testing#1": (
        "baku_spec_traceability",
        "The audit checks that run-tests.sh prints one pass/fail marker for each "
        "layer, and CTest owns the per-test decision.",
    ),
    "testing#2": (
        "",
        "2026-11-14: the Forth 2012 suite is a recorded manual run in M1 (the pinned "
        "Sloth baseline has one known FP failure); the automated baku gate runs the "
        "probe and every layer test but not a second Sloth FP-disabled build.",
    ),
    "testing#3": (
        "baku_spec_traceability, baku_spec_traceability_selftest",
        "This audit fails on an orphan criterion, a stale row, an unknown test or an "
        "undated waiver; the self-test proves each failure path.",
    ),
    "testing#4": (
        "baku_kernel-suite_gforth",
        "The pinned suite runs under the collector and the gate pins zero failures.",
    ),
    "testing#5": (
        "baku_differential_targets, baku_conformance_targets, baku_differential_sloth, "
        "baku_differential_gforth, baku_conformance_sloth, baku_conformance_gforth",
        "Cross-target comparisons are byte-exact over the marked output.",
    ),
    "testing#6": (
        "baku_spec_traceability, baku_differential_targets",
        "Target tests are named baku_<layer>_<target> and the differential comparator "
        "names the target, so a failure identifies layer and target.",
    ),
    "testing#7": (
        "baku_spec_traceability, baku_differential_targets",
        "The gate enumerates every registered target test, and unresolved failures or "
        "offline waivers are dated in this mapping and the plan.",
    ),

    # tooling.md
    "tooling#1": (
        "baku_smoke_sloth, baku_smoke_gforth, baku_no_build",
        "run-tests.sh builds the pinned Sloth and runs the suites; the smoke test "
        "proves the harness end to end.",
    ),
    "tooling#2": (
        "baku_spec_traceability, baku_spec_traceability_selftest",
        "The registered-test list is written by CMake after the glob; the audit "
        "requires every glob-registered test that is not enabled for Sloth to carry an "
        "explicit exclusion with a reason comment, or an explicit registration with a "
        "comment, and the self-test proves a missing reason fails.",
    ),
    "tooling#3": (
        "baku_spec_traceability",
        "test/run-test.cmake requires exit zero and the marker; the audit rejects an "
        "unknown test name so a stale claim cannot pass.",
    ),
    "tooling#4": (
        "baku_spec_traceability",
        "CMake makes a missing gforth a fatal configure error and run-tests.sh prints "
        "a distinct gforth-missing message; the audit requires the runner markers.",
    ),
    "tooling#5": (
        "baku_spec_traceability",
        "The audit requires a 40-hex GIT_TAG pin in CMakeLists.txt, not a moving "
        "branch.",
    ),
    "tooling#6": (
        "baku_smoke_sloth, baku_smoke_gforth",
        "A second CTest run reuses the configured build and still passes.",
    ),

    # value-representation.md
    "value-representation#1": (
        "baku_values_sloth, baku_values_gforth, baku_primitives_sloth, "
        "baku_primitives_gforth",
        "Cons, string, symbol, vector and closure round-trips are direct value and "
        "primitive checks.",
    ),
    "value-representation#2": (
        "baku_values_sloth, baku_values_gforth, baku_conformance_sloth, "
        "baku_conformance_gforth",
        "Tag and header checks run on 64-bit cells; the 32-bit run is deferred.",
    ),
    "value-representation#3": (
        "baku_values_sloth, baku_values_gforth, baku_gc_gforth",
        "Region classification is exact for non-GC and GC objects with no false "
        "positive for aligned non-heap addresses. The scratch case is a dated waiver "
        "until P3 adds the reader scratch check.",
    ),
    "value-representation#4": (
        "baku_primitives_sloth, baku_primitives_gforth, baku_kernel_gforth",
        "The host classifiers and the kernel-defined classifiers are tested at their "
        "own boundary.",
    ),
    "value-representation#5": (
        "baku_values_sloth, baku_values_gforth, baku_primitives_sloth, "
        "baku_primitives_gforth",
        "Interning is case-sensitive and punctuation survives.",
    ),
    "value-representation#6": (
        "baku_reader_sloth, baku_reader_gforth, baku_primitives_sloth, "
        "baku_primitives_gforth",
        "10000000000 and 3.1415926535897 read and format without loss.",
    ),
    "value-representation#7": (
        "baku_values_sloth, baku_values_gforth",
        "The type is read from the object header, with no external table.",
    ),

}

DOC_HEADER = """\
# Specification to test traceability

Generated by `tools/traceability-audit.py --write` from `.ralph/specs/*.md` and
the coverage table in that tool. Do not hand-edit.

Every acceptance criterion and every contract entry statement below names the
registered CTest tests that verify it, or carries a dated waiver explaining why
it cannot run in this environment. `baku_spec_traceability` fails when a
criterion loses its row, a claimed test is not registered, a waiver loses its
date, or this document drifts from the specs.

"""

README_HEADINGS = (
    "## Architecture",
    "## Values",
    "## Memory",
    "## Execution modes",
    "## Primitives, errors and I/O",
    "## Testing",
    "## Licensing and kernel provenance",
    "## Design decisions and rejected alternatives",
)

RUNNER_MARKERS = (
    "BAKU-KERNEL-DIGEST",
    "BAKU-TESTS-DIGEST",
    "BAKU-RELEASE-ASSET",
    "BAKU-ANS-AUDIT",
    "BAKU-VENDOR-AUDIT",
    "BAKU-PROVENANCE-AUDIT",
    "BAKU-LINK-AUDIT",
    "BAKU-REGION-AUDIT",
    "BAKU-PRIMITIVE-MANIFEST",
    "BAKU-TRACEABILITY",
    "BAKU-CONFORMANCE",
    "BAKU-NO-BUILD",
    "BAKU-DIFFERENTIAL",
    "BAKU-KERNEL-SUITE",
    "BAKU-TARGET",
)

STATUS_PATTERNS = (
    (re.compile(r"\b\d+(?:st|nd|rd|th)[- ]iteration\b", re.IGNORECASE),
     "iteration status"),
    (re.compile(r"(?<![\d/])\d+\s*/\s*\d+(?![\d/])"), "pass count"),
    (re.compile(r"\b\d+\s+passed\b", re.IGNORECASE), "pass count"),
    (re.compile(r"\b\d+\s+failed\b", re.IGNORECASE), "failure count"),
    (re.compile(r"full Debug gate (?:was|is)\b", re.IGNORECASE),
     "gate outcome"),
)


def normalize(text):
    return re.sub(r"\s+", " ", text).strip()


def sections(lines):
    title = None
    body = []
    for line in lines:
        match = re.match(r"^(#{1,6})\s+(.*)$", line)
        if match and len(match.group(1)) == 2:
            if title is not None:
                yield title, body
            title = match.group(2).strip()
            body = []
        elif title is not None:
            body.append(line)
    if title is not None:
        yield title, body


def bullets(lines):
    items = []
    current = None
    for line in lines:
        if line.startswith("- "):
            if current is not None:
                items.append(current)
            current = line[2:]
        elif current is not None and line.startswith(("  ", "\t")):
            current += " " + line.strip()
        elif current is not None:
            items.append(current)
            current = None
    if current is not None:
        items.append(current)
    return [normalize(item) for item in items if normalize(item)]


def numbered(lines):
    items = []
    number = None
    current = None
    for line in lines:
        match = re.match(r"^(\d+)\.\s+(.*)$", line)
        if match:
            if current is not None:
                items.append((number, current))
            number = int(match.group(1))
            current = match.group(2)
        elif current is not None and line.startswith(("  ", "\t")):
            current += " " + line.strip()
        elif current is not None:
            items.append((number, current))
            number = None
            current = None
    if current is not None:
        items.append((number, current))
    return [(number, normalize(text)) for number, text in items if text]


def collect_criteria(specs):
    criteria = {}
    for path in sorted(specs.glob("*.md")):
        stem = path.stem
        for title, body in sections(path.read_text(encoding="utf-8").splitlines()):
            if title == "Acceptance criteria":
                for index, item in enumerate(bullets(body), 1):
                    criteria[f"{stem}#{index}"] = item
            elif stem == "contract" and title == "Required behaviour from the entry":
                for number, item in numbered(body):
                    criteria[f"{stem}#statement-{number}"] = item
    return criteria


def criterion_order(criteria):
    groups = {}
    for criterion in criteria:
        groups.setdefault(criterion.split("#", 1)[0], []).append(criterion)

    def key(criterion):
        tail = criterion.split("#", 1)[1]
        if tail.startswith("statement-"):
            return (1, int(tail.split("-", 1)[1]))
        return (0, int(tail))

    ordered = []
    for stem in sorted(groups):
        ordered.extend(sorted(groups[stem], key=key))
    return ordered


def load_registered(path):
    if path is None or not path.is_file():
        return None
    names = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            names.add(line)
    return names


def row_parts(value):
    if not isinstance(value, tuple) or len(value) != 2:
        raise ValueError("coverage row is not a (tests, evidence) pair")
    tests, evidence = value
    names = [name.strip() for name in tests.split(",") if name.strip()]
    return names, evidence.strip()


def validate_coverage(criteria, coverage, registered, violations):
    expected = set(criteria)
    rows = set(coverage)
    for criterion in sorted(expected - rows):
        violations.append(
            (criterion, "orphan criterion: no coverage row"))
    for criterion in sorted(rows - expected):
        violations.append(
            (criterion, "stale row: no such spec criterion"))
    for criterion in sorted(expected & rows):
        try:
            names, evidence = row_parts(coverage[criterion])
        except ValueError as error:
            violations.append((criterion, str(error)))
            continue
        if not evidence:
            violations.append((criterion, "empty evidence"))
            continue
        if not names:
            if not WAIVER_RE.match(evidence):
                violations.append(
                    (criterion, "no test and no dated waiver"))
            continue
        for name in names:
            if registered is not None and name not in registered:
                violations.append(
                    (criterion, f"unknown test {name!r}"))


def wrap_line(label, text, width=88):
    return textwrap.wrap(f"{label}: {text}", width=width) or [f"{label}:"]


def render(criteria, coverage):
    lines = [DOC_HEADER.rstrip(), ""]
    last_stem = None
    for criterion in criterion_order(criteria):
        stem = criterion.split("#", 1)[0]
        if stem != last_stem:
            lines.extend([f"## `{stem}.md`", ""])
            last_stem = stem
        names, evidence = row_parts(
            coverage.get(criterion, ("", "missing coverage row")))
        lines.extend([f"### `{criterion}`", ""])
        lines.append(textwrap.fill(criteria[criterion], width=88))
        lines.append("")
        if names:
            lines.extend(textwrap.wrap(
                "Tests: " + ", ".join(f"`{name}`" for name in names),
                width=88, break_long_words=False, break_on_hyphens=False))
        else:
            lines.append("Tests: none")
        lines.append("")
        lines.extend(wrap_line("Evidence", evidence))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def check_document(path, rendered, violations):
    if not path.is_file():
        violations.append((str(path), "missing generated traceability document"))
    elif path.read_text(encoding="utf-8") != rendered:
        violations.append(
            (str(path),
             "stale traceability document; run --write"))


def check_document_only(path, coverage, violations):
    if not path.is_file():
        violations.append((str(path), "missing generated traceability document"))
        return
    text = path.read_text(encoding="utf-8")
    flat = normalize(text)
    for criterion, value in sorted(coverage.items()):
        names, evidence = row_parts(value)
        if f"### `{criterion}`" not in text:
            violations.append(
                (criterion, "coverage row missing from the document"))
        for name in names:
            if name not in text:
                violations.append(
                    (criterion, f"document does not name test {name!r}"))
        if not names and normalize(evidence) not in flat:
            violations.append(
                (criterion, "document does not carry the waiver"))


def check_readme(root, violations):
    path = root / "README.md"
    if not path.is_file():
        violations.append(("README.md", "missing the project README"))
        return
    text = path.read_text(encoding="utf-8")
    flat = normalize(text)
    if "# Baku" not in text or "Shen" not in flat:
        violations.append(("README.md", "missing the purpose statement"))
    for heading in README_HEADINGS:
        if heading not in text:
            violations.append(
                ("README.md", f"missing section {heading!r}"))
    if "proj.baku.org" not in flat:
        violations.append(
            ("README.md", "does not name the requirements source"))
    if "does not add requirements" not in flat:
        violations.append(
            ("README.md", "does not state that it adds no requirements"))
    if "./run-tests.sh" not in flat or "BAKU-TEST-DONE" not in flat:
        violations.append(
            ("README.md", "does not lead a newcomer to a passing test"))
    if "docs/spec-traceability.md" not in flat:
        violations.append(
            ("README.md", "does not link the generated traceability document"))

    marker = "## Design decisions and rejected alternatives"
    if marker in text:
        body = text.split(marker, 1)[1].split("\n## ", 1)[0]
        decisions = bullets(body.splitlines())
        if not decisions:
            violations.append(
                ("README.md", "design-decision section has no bullets"))
        for decision in decisions:
            if "Rejected:" not in decision:
                violations.append(
                    ("README.md",
                     f"design choice has no rejected alternative: "
                     f"{decision[:60]!r}"))
            if "Requirement:" not in decision and "Choice:" not in decision:
                violations.append(
                    ("README.md",
                     f"design choice states no requirement or choice: "
                     f"{decision[:60]!r}"))


def check_runner(root, violations):
    path = root / "run-tests.sh"
    if not path.is_file():
        violations.append(("run-tests.sh", "missing the test runner"))
        return
    text = path.read_text(encoding="utf-8")
    for marker in RUNNER_MARKERS:
        if marker not in text:
            violations.append(
                ("run-tests.sh", f"missing pass/fail marker {marker}"))


def parse_exclusions(text):
    """Return {test name: reason or None} from the explicit gforth-only list."""
    exclusions = {}
    pattern = re.compile(
        r"set\(\s*BAKU_(?:NATIVE_BOOT|GFORTH_ONLY)_TESTS\b(.*?)\)",
        re.DOTALL)
    for match in pattern.finditer(text):
        for raw in match.group(1).splitlines():
            code, marker, reason = raw.partition("#")
            reason = reason.strip() if marker else ""
            for name in code.split():
                exclusions[name] = reason or None
    return exclusions


def explicit_registration_reason(text, stem):
    """Return the comment for an explicit add_test of this test file, if any."""
    pattern = re.compile(r"add_test\(NAME\s+baku_" + re.escape(stem) + r"_")
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not pattern.search(line):
            continue
        if "#" in line:
            reason = line.split("#", 1)[1].strip()
            if reason:
                return reason
        reason = []
        above = index - 1
        while above >= 0 and lines[above].lstrip().startswith("#"):
            reason.append(lines[above].lstrip()[1:].strip())
            above -= 1
        if reason:
            return " ".join(reversed(reason))
    return None


def check_tooling(root, registered, violations):
    path = root / "CMakeLists.txt"
    if not path.is_file():
        violations.append(("CMakeLists.txt", "missing the test platform"))
        return
    text = path.read_text(encoding="utf-8")
    active = [line for line in text.splitlines()
              if not line.lstrip().startswith("#")]
    if any("PASS_REGULAR_EXPRESSION" in line for line in active):
        violations.append(
            ("CMakeLists.txt",
             "uses PASS_REGULAR_EXPRESSION; exit status would be ignored"))
    if "gforth missing" not in text:
        violations.append(
            ("CMakeLists.txt", "missing the distinct gforth-missing error"))
    if "test/run-test.cmake" not in text:
        violations.append(
            ("CMakeLists.txt", "does not route tests through run-test.cmake"))
    pin = re.search(r"GIT_TAG\s+([0-9A-Za-z_.-]+)", text)
    if not pin or not re.fullmatch(r"[0-9a-f]{40}", pin.group(1)):
        violations.append(
            ("CMakeLists.txt", "Sloth is not pinned by a 40-hex commit"))
    if registered is None:
        return
    exclusions = parse_exclusions(text)
    for test_path in sorted((root / "test").glob("*.4th")):
        stem = test_path.stem
        sloth = f"baku_{stem}_sloth" in registered
        gforth = f"baku_{stem}_gforth" in registered
        if sloth:
            if stem in exclusions:
                violations.append(
                    (str(test_path.relative_to(root)),
                     "excluded from Sloth but registered for it"))
            continue
        if not gforth:
            violations.append(
                (str(test_path.relative_to(root)),
                 "no registered target test for this file"))
            continue
        if stem in exclusions:
            if not exclusions[stem]:
                violations.append(
                    (str(test_path.relative_to(root)),
                     "not enabled for Sloth and the exclusion has no reason "
                     "comment"))
            continue
        if explicit_registration_reason(text, stem):
            continue
        violations.append(
            (str(test_path.relative_to(root)),
             "not enabled for Sloth and not in the explicit exclusion list "
             "with a reason"))


def check_agents(path, violations):
    if path is None or not path.is_file():
        return
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for pattern, label in STATUS_PATTERNS:
            if pattern.search(line):
                violations.append(
                    (f"{path.name}:{number}",
                     f"{label}: {line.strip()[:70]!r}"))


def check_primitives(root, violations):
    sys.path.insert(0, str(HERE / "tools"))
    try:
        import manifest
        primitives = manifest.load_primitives()
    except Exception as error:  # noqa: BLE001 - report, do not traceback
        violations.append(("primitives", f"cannot load registrations: {error}"))
        return
    texts = [path.read_text(encoding="utf-8", errors="replace")
             for path in sorted((root / "test").glob("*.4th"))]
    for name in sorted(primitives):
        if name in PRIMITIVE_EXCEPTIONS:
            continue
        word = re.compile(r"\bbaku-prim-" + re.escape(name) + r"\b")
        application = re.compile(r"\(" + re.escape(name) + r"(?=[\s)])")
        if not any(word.search(text) or application.search(text)
                   for text in texts):
            violations.append(
                (f"primitive {name}", "no direct test call"))


def audit(root, specs, tests_file, agents, coverage, write=False,
          verbose=False):
    violations = []
    registered = load_registered(tests_file)
    if registered is None:
        violations.append(
            (str(tests_file),
             "missing registered-test list; configure CMake first"))
    else:
        if "baku_spec_traceability" not in registered:
            violations.append(
                ("registered tests",
                 "baku_spec_traceability is not registered"))

    output = root / "docs" / "spec-traceability.md"
    criteria = None
    if specs is not None and specs.is_dir():
        criteria = collect_criteria(specs)
        if not criteria:
            violations.append(
                (str(specs), "no acceptance criteria found"))
        validate_coverage(criteria, coverage, registered, violations)
        rendered = render(criteria, coverage)
        if write:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(rendered, encoding="utf-8")
        check_document(output, rendered, violations)
    else:
        if write:
            violations.append(
                (str(specs), "cannot --write without the spec tree"))
        check_document_only(output, coverage, violations)

    check_readme(root, violations)
    check_runner(root, violations)
    check_tooling(root, registered, violations)
    check_agents(agents, violations)
    check_primitives(root, violations)

    print("Specification-to-test traceability audit")
    print(f"  repository: {root}")
    if criteria is not None:
        print(f"  specs: {specs} ({len(criteria)} criteria)")
    else:
        print(f"  specs: unavailable ({specs}); document checked only")
    print(f"  coverage rows: {len(coverage)}")
    print(f"  registered tests: "
          f"{len(registered) if registered is not None else 'unavailable'}")
    if verbose:
        covered = sum(1 for value in coverage.values()
                      if row_parts(value)[0])
        print(f"  rows with tests: {covered}")
        print(f"  rows with dated waivers: {len(coverage) - covered}")

    if violations:
        print("TRACEABILITY-VIOLATIONS:")
        for label, reason in sorted(violations):
            print(f"  {label}: {reason}")

    ok = not violations
    print("TRACEABILITY-AUDIT " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


SELF_SPECS = """\
# Alpha

## Acceptance criteria

- The first criterion is checked by a registered test.
- The second criterion carries a dated waiver.
"""

SELF_CONTRACT = """\
# Contract

## Required behaviour from the entry

1. The first entry statement is checked.
2. The second entry statement is checked.
"""

SELF_README = """\
# Baku

Baku is a port of Shen. The requirements are `proj.baku.org`. This README does
not add requirements. The traceability map is in `docs/spec-traceability.md`.

## Architecture

## Values

## Memory

## Execution modes

## Primitives, errors and I/O

## Testing

Run `./run-tests.sh` and require `BAKU-TEST-DONE`.

## Licensing and kernel provenance

## Design decisions and rejected alternatives

- **One choice.** Requirement: a requirement. Choice: the choice. Rejected: the
  alternative.
- **Another.** Choice: another choice. Rejected: another alternative.
"""

SELF_RUNNER = """\
#!/bin/sh
%s
""" % "\n".join(f'echo "{marker} PASS"' for marker in RUNNER_MARKERS)

SELF_CMAKE = """\
find_program(GFORTH_EXECUTABLE gforth)
if(NOT GFORTH_EXECUTABLE)
	message(FATAL_ERROR "gforth missing")
endif()
GIT_TAG 0123456789abcdef0123456789abcdef01234567
test/run-test.cmake
"""

SELF_CMAKE_EXCLUDED = """\
find_program(GFORTH_EXECUTABLE gforth)
if(NOT GFORTH_EXECUTABLE)
	message(FATAL_ERROR "gforth missing")
endif()
GIT_TAG 0123456789abcdef0123456789abcdef01234567
test/run-test.cmake
set(BAKU_GFORTH_ONLY_TESTS
	alpha  # the fixture boots the whole kernel, too slow on Sloth Debug
)
"""

SELF_CMAKE_EXCLUDED_NO_REASON = """\
find_program(GFORTH_EXECUTABLE gforth)
if(NOT GFORTH_EXECUTABLE)
	message(FATAL_ERROR "gforth missing")
endif()
GIT_TAG 0123456789abcdef0123456789abcdef01234567
test/run-test.cmake
set(BAKU_GFORTH_ONLY_TESTS
	alpha
)
"""

SELF_CMAKE_EXPLICIT = """\
find_program(GFORTH_EXECUTABLE gforth)
if(NOT GFORTH_EXECUTABLE)
	message(FATAL_ERROR "gforth missing")
endif()
GIT_TAG 0123456789abcdef0123456789abcdef01234567
test/run-test.cmake
# The fixture reads an empty stdin, which only gforth reports as end of input.
add_test(NAME baku_alpha_gforth COMMAND true)
"""

SELF_TESTS = """\
baku_alpha_sloth
baku_alpha_gforth
baku_spec_traceability
baku_spec_traceability_selftest
"""

SELF_TESTS_GFORTH_ONLY = """\
baku_alpha_gforth
baku_spec_traceability
baku_spec_traceability_selftest
"""

SELF_COVERAGE = {
    "alpha#1": ("baku_alpha_sloth, baku_alpha_gforth", "checked directly"),
    "alpha#2": ("", "2026-11-14: blocked in the fixture"),
    "contract#statement-1": ("baku_alpha_sloth", "checked directly"),
    "contract#statement-2": ("baku_alpha_gforth", "checked directly"),
}


def self_test():
    failures = []

    def report(label, violations, needle=None, expect_clean=False):
        if expect_clean:
            if violations:
                failures.append(
                    f"{label}: expected no violations, got {violations}")
            return
        if not any(needle in reason for _, reason in violations):
            failures.append(
                f"{label}: expected {needle!r}, got {violations}")

    with tempfile.TemporaryDirectory(prefix="baku-traceability-") as work:
        base = Path(work)
        specs = base / "specs"
        specs.mkdir()
        (specs / "alpha.md").write_text(SELF_SPECS, encoding="utf-8")
        (specs / "contract.md").write_text(SELF_CONTRACT, encoding="utf-8")
        criteria = collect_criteria(specs)
        registered = load_registered_text(SELF_TESTS)

        violations = []
        validate_coverage(criteria, SELF_COVERAGE, registered, violations)
        report("valid coverage", violations, expect_clean=True)

        violations = []
        validate_coverage(criteria, SELF_COVERAGE, registered, violations)
        broken = dict(SELF_COVERAGE)
        del broken["alpha#1"]
        validate_coverage(criteria, broken, registered, violations)
        report("orphan criterion", violations, "orphan criterion")

        try:
            rendered = render(criteria, broken)
        except Exception as error:  # noqa: BLE001 - report, do not traceback
            failures.append(
                f"render with orphan: raised {error!r} instead of reporting")
        else:
            if "alpha#1" not in rendered:
                failures.append(
                    "render with orphan: dropped the orphaned criterion")

        stale_render = dict(SELF_COVERAGE)
        stale_render["alpha#9"] = ("baku_alpha_sloth", "stale")
        try:
            render(criteria, stale_render)
        except Exception as error:  # noqa: BLE001 - report, do not traceback
            failures.append(
                f"render with stale row: raised {error!r} instead of reporting")

        violations = []
        stale = dict(SELF_COVERAGE)
        stale["alpha#9"] = ("baku_alpha_sloth", "stale")
        validate_coverage(criteria, stale, registered, violations)
        report("stale row", violations, "stale row")

        violations = []
        unknown = dict(SELF_COVERAGE)
        unknown["alpha#1"] = ("baku_alpha_missing", "bad test")
        validate_coverage(criteria, unknown, registered, violations)
        report("unknown test", violations, "unknown test")

        violations = []
        undated = dict(SELF_COVERAGE)
        undated["alpha#2"] = ("", "blocked without a date")
        validate_coverage(criteria, undated, registered, violations)
        report("undated waiver", violations, "no test and no dated waiver")

        rendered = render(criteria, SELF_COVERAGE)
        doc = base / "docs" / "spec-traceability.md"
        doc.parent.mkdir()
        doc.write_text(rendered, encoding="utf-8")
        violations = []
        check_document(doc, rendered, violations)
        report("current document", violations, expect_clean=True)

        violations = []
        check_document(doc, rendered + "drift\n", violations)
        report("stale document", violations, "stale traceability document")

        missing_doc = base / "docs" / "missing.md"
        violations = []
        check_document_only(missing_doc, SELF_COVERAGE, violations)
        report("missing document", violations,
               "missing generated traceability document")

        root = base / "root"
        (root / "test").mkdir(parents=True)
        (root / "test" / "alpha.4th").write_text(
            "s\" (alpha 1)\" s\" baku-prim-alpha\"\n", encoding="utf-8")
        (root / "README.md").write_text(SELF_README, encoding="utf-8")
        (root / "run-tests.sh").write_text(SELF_RUNNER, encoding="utf-8")
        (root / "CMakeLists.txt").write_text(SELF_CMAKE, encoding="utf-8")
        violations = []
        check_readme(root, violations)
        check_runner(root, violations)
        check_tooling(root, registered, violations)
        report("valid documentation", violations, expect_clean=True)

        (root / "README.md").write_text(
            SELF_README.replace("## Memory\n", ""), encoding="utf-8")
        violations = []
        check_readme(root, violations)
        report("missing README section", violations, "missing section")

        (root / "README.md").write_text(
            SELF_README.replace(
                "Rejected: the\n  alternative.", "No alternative."),
            encoding="utf-8")
        violations = []
        check_readme(root, violations)
        report("missing rejected alternative", violations,
               "no rejected alternative")

        agents = base / "AGENTS.md"
        agents.write_text(
            "Operational note about a per-iteration allocation.\n",
            encoding="utf-8")
        violations = []
        check_agents(agents, violations)
        report("clean AGENTS", violations, expect_clean=True)

        agents.write_text(
            "The 31st-iteration full Debug gate was 45/45.\n",
            encoding="utf-8")
        violations = []
        check_agents(agents, violations)
        report("status in AGENTS", violations, "iteration status")

        (root / "CMakeLists.txt").write_text(
            SELF_CMAKE.replace(
                "GIT_TAG 0123456789abcdef0123456789abcdef01234567",
                "GIT_TAG main"), encoding="utf-8")
        violations = []
        check_tooling(root, registered, violations)
        report("moving Sloth pin", violations, "40-hex commit")

        gforth_only = load_registered_text(SELF_TESTS_GFORTH_ONLY)
        (root / "CMakeLists.txt").write_text(
            SELF_CMAKE_EXCLUDED, encoding="utf-8")
        violations = []
        check_tooling(root, gforth_only, violations)
        report("excluded test with a reason", violations, expect_clean=True)

        (root / "CMakeLists.txt").write_text(
            SELF_CMAKE_EXCLUDED_NO_REASON, encoding="utf-8")
        violations = []
        check_tooling(root, gforth_only, violations)
        report("excluded test without a reason", violations,
               "no reason comment")

        (root / "CMakeLists.txt").write_text(
            SELF_CMAKE_EXPLICIT, encoding="utf-8")
        violations = []
        check_tooling(root, gforth_only, violations)
        report("explicit gforth-only registration", violations,
               expect_clean=True)

    if failures:
        print("TRACEABILITY-SELFTEST-VIOLATIONS:")
        for failure in failures:
            print(f"  {failure}")
        print("TRACEABILITY-SELFTEST FAIL")
        return 1
    print("TRACEABILITY-SELFTEST PASS")
    return 0


def load_registered_text(text):
    return {line.strip() for line in text.splitlines() if line.strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(HERE),
                        help="repository root (default: the baku checkout)")
    parser.add_argument("--specs", default=str(DEFAULT_SPECS),
                        help="specification directory")
    parser.add_argument("--tests-file", default=str(HERE / "build" / "baku-tests.txt"),
                        help="registered CTest names written by CMake")
    parser.add_argument("--agents", default=str(DEFAULT_AGENTS),
                        help=".ralph/AGENTS.md to scan for status prose")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true",
                      help="regenerate docs/spec-traceability.md")
    mode.add_argument("--check", action="store_true",
                      help="fail on drift, orphans or unknown tests")
    mode.add_argument("--self-test", action="store_true",
                      help="prove every failure path on a fixture")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    return audit(Path(args.root).resolve(), Path(args.specs).resolve(),
                 Path(args.tests_file), Path(args.agents),
                 COVERAGE, args.write, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
