#!/usr/bin/env python3
"""Generate and verify the Baku primitive manifest.

The manifest is derived from the pinned Shen 43.2 KLambda corpus and from the
host primitive registrations in the shipped Forth sources.  It is a
development tool: it is never shipped and never used at runtime.

The corpus scan is a parse, not a text search.  A head symbol is an
application only when it appears in application position, so a symbol used as
data (for example `input+` in `(cons input+ ...)`) is not an application.
`defun` names, `defun`/`lambda` parameter lists, `let` variables, `cond`
clauses and the KLambda special forms are not applications.  Local `V...` and
`W...` variable heads are filtered because the Shen compiler emits them as
variables, not as function names.

Every remaining applied symbol is classified.  The classification is
bidirectional against the shipped sources: an unclassified applied symbol or a
primitive registered by `baku-defprim` that the corpus never applies fails
generation.

Usage:

    python3 tools/manifest.py --write   # regenerate docs/primitive-manifest.md
    python3 tools/manifest.py --check   # fail if the committed file is stale
    python3 tools/manifest.py --self-test
"""

import argparse
import glob
import os
import re
import sys

from klambda_parser import ParseError, read_forms

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(HERE, "vendor", "shen-43.2", "klambda")
OUTPUT = os.path.join(HERE, "docs", "primitive-manifest.md")

REGISTRATION_SOURCES = (
    "4th/eval.4th",
    "4th/primitives.4th",
)
REGISTRATION = re.compile(r's"\s*([^"\s]+)"\s+baku-intern\s+baku-defprim')

SPECIAL_FORMS = frozenset({
    "if", "and", "or", "cond", "let", "lambda", "defun", "freeze",
    "trap-error",
})
LOCAL_HEAD = re.compile(r"^[VW][0-9]+$")

COMPATIBILITY = frozenset({"input+"})
KERNEL_SPECIAL = frozenset({"type"})

# One row per applied host symbol: the ANS Forth 2012 words it uses and the
# reason for the mapping.  "Baku heap" means the primitive is implemented on
# Baku's own value layer and no ANS word applies.  The table is the M5
# deliverable; --check fails when it and the classified host symbols disagree,
# and a mapping row may never name a defun-defined kernel function.
MAPPING = {
    "*": ("Core `*`; Double `M*`; Floating `F*`",
          "fixnum product widened with `M*` then range-checked; a float "
          "operand uses `F*`"),
    "+": ("Core `+`; Double `D+`; Floating `F+`",
          "fixnum sum widened to a double cell then range-checked; a float "
          "operand uses `F+`"),
    "-": ("Core `-`; Double `D-`; Floating `F-`",
          "fixnum difference widened to a double cell then range-checked; a "
          "float operand uses `F-`"),
    "/": ("Core `/` `MOD`; Double `S>D`; Floating `S>F F/`",
          "exact fixnum quotient when divisible, otherwise a boxed float; "
          "division by any numeric zero is catchable"),
    "<": ("Core `<`; Floating `F<`",
          "numeric comparison across fixnums and boxed floats; returns a "
          "Shen Boolean"),
    "<-address": ("Baku heap; Core `@ CELLS +`",
                  "0-based vector read with a bounds check"),
    "<=": ("Core `<=`; Floating comparison",
           "numeric comparison; returns a Shen Boolean"),
    "=": ("Core `=`; Floating `F~`; String `COMPARE`; Baku heap",
          "total Shen equality: numeric across fixnums/floats, string bytes, "
          "symbol identity, element-wise vectors, recursive conses; opaque "
          "objects compare false"),
    ">": ("Core `>`; Floating `F>`",
          "numeric comparison; returns a Shen Boolean"),
    ">=": ("Core `>=`; Floating comparison",
           "numeric comparison; returns a Shen Boolean"),
    "absvector": ("Baku heap; Core `CELLS`",
                  "allocates N zero-filled cells"),
    "absvector?": ("Baku heap header test",
                   "returns a Shen Boolean"),
    "address->": ("Baku heap; Core `! CELLS +`",
                  "KLambda order `(vector index value)`; returns the vector"),
    "char-stream?": ("Baku heap stream object",
                     "arity 1; files are byte streams, standard streams are "
                     "character streams; returns a Shen Boolean"),
    "close": ("File `CLOSE-FILE`",
              "returns its stream; a standard stream is a no-op"),
    "cn": ("Baku heap; Core Ext `CMOVE CMOVE>`",
           "string concatenation"),
    "cons": ("Baku heap cons cell; Core `@ !`",
             "allocates one cons"),
    "cons?": ("Baku heap header test",
              "returns a Shen Boolean"),
    "error-to-string": ("Baku heap error object; Core `CMOVE`",
                        "copies the inline message; a non-error is rendered by "
                        "the `str` rules"),
    "eval-kl": ("Baku evaluator/compiler (no ANS word)",
                "single Shen-visible entry into the evaluator; lowers a form "
                "through the shared front end"),
    "get-time": ("Facility `TIME&DATE`; Core `MAX`",
                 "`unix` is local-time epoch seconds; `run` is non-decreasing "
                 "elapsed seconds from one `TIME&DATE` source"),
    "hd": ("Baku heap; Core `@`",
           "non-cons raises a catchable type error"),
    "input+": ("Baku heap (interpreted delegate)",
               "two-place KLambda delegate to `shen.input-h+`; resolved at "
               "application time, not a Forth primitive"),
    "intern": ("Baku symbol table; String `COMPARE`",
               "case-sensitive; `_` and `-` stay distinct; `true`/`false` map "
               "to the reserved immediates"),
    "n->string": ("Baku heap; Core `C!`",
                  "byte code 0..255 to a unit string"),
    "number?": ("Baku heap tag and header test",
                "fixnum or boxed float; returns a Shen Boolean"),
    "open": ("File `R/O W/O BIN OPEN-FILE CREATE-FILE`",
             "`in` opens read-only; `out` creates or truncates"),
    "pos": ("Baku heap string slice",
            "0-based index; returns a one-byte unit string"),
    "read-byte": ("File `READ-FILE`; Core `KEY`",
                  "returns -1 at end of file; standard input uses `KEY`"),
    "read-unit-string": ("File `READ-FILE`; Core `KEY`",
                         "reads one unit string"),
    "set": ("Baku global table; Core `@ !`",
            "updates an existing binding in place; returns the stored value"),
    "simple-error": ("Exception `THROW`; Baku heap error object",
                     "copies the message bytes inline, so no cross-region "
                     "reference is stored"),
    "str": ("Core `<# #S #> SIGN`; Floating `REPRESENT`; String `COMPARE`; "
            "Baku heap",
            "renders symbols, quoted strings, fixnums, boxed floats and "
            "booleans; non-atoms are a catchable type error"),
    "string->n": ("Baku heap; Core `C@`",
                  "first byte of a non-empty string as a fixnum"),
    "string?": ("Baku heap header test",
                "returns a Shen Boolean"),
    "tl": ("Baku heap; Core `@`",
           "non-cons raises a catchable type error"),
    "tlstr": ("Baku heap string slice",
              "all but the first byte; the empty string is a catchable bounds "
              "error"),
    "type": ("Shen special form (no ANS word)",
             "listed in `shen.*special*`; expanded before KLambda and never "
             "host-implemented"),
    "value": ("Baku global table; Core `@`",
              "an unbound symbol raises a catchable error"),
    "write-byte": ("File `WRITE-FILE`; Core `EMIT`",
                   "returns its stream; standard output uses `EMIT`"),
    "write-string": ("File `WRITE-FILE`; Core `TYPE`",
                     "returns its string; standard output uses `TYPE`"),
}


class ManifestError(Exception):
    """The corpus and the declared classification do not agree."""


def collect_applied(form, heads, include_locals=False):
    """Add every head used in application position to heads.

    Local V.../W... heads are filtered unless include_locals is true; the
    caller uses the unfiltered pass only to report how many were removed.
    """
    if not isinstance(form, list) or not form:
        return
    head = form[0]
    if isinstance(head, str):
        if LOCAL_HEAD.match(head):
            if include_locals:
                heads.add(head)
            for expr in form[1:]:
                collect_applied(expr, heads, include_locals)
            return
        if head == "defun":
            if len(form) < 4 or not isinstance(form[2], list):
                raise ManifestError("malformed defun form")
            for body in form[3:]:
                collect_applied(body, heads, include_locals)
            return
        if head == "lambda":
            if len(form) < 3 or not isinstance(form[1], str):
                raise ManifestError("malformed lambda form")
            for body in form[2:]:
                collect_applied(body, heads, include_locals)
            return
        if head == "let":
            if len(form) != 4:
                raise ManifestError("malformed let form")
            collect_applied(form[2], heads, include_locals)
            collect_applied(form[3], heads, include_locals)
            return
        if head == "cond":
            for clause in form[1:]:
                if isinstance(clause, list):
                    for expr in clause:
                        collect_applied(expr, heads, include_locals)
                else:
                    collect_applied(clause, heads, include_locals)
            return
        if head in SPECIAL_FORMS:
            for expr in form[1:]:
                collect_applied(expr, heads, include_locals)
            return
        heads.add(head)
        for expr in form[1:]:
            collect_applied(expr, heads, include_locals)
        return
    for expr in form:
        collect_applied(expr, heads, include_locals)


def collect_raw_heads(form, heads):
    """Add every list head, including binding and clause lists.

    This is the naive scan used only to report the before-filtering count in
    the manifest header.  It is not the semantic application scan.
    """
    if not isinstance(form, list) or not form:
        return
    if isinstance(form[0], str):
        heads.add(form[0])
    for expr in form:
        collect_raw_heads(expr, heads)


def load_corpus():
    files = sorted(glob.glob(os.path.join(CORPUS, "*.kl")))
    if not files:
        raise ManifestError("no .kl files under %s" % CORPUS)
    corpus = []
    for path in files:
        with open(path, encoding="ascii") as handle:
            corpus.append((os.path.basename(path), read_forms(handle.read())))
    return corpus


def load_primitives():
    primitives = set()
    for rel in REGISTRATION_SOURCES:
        path = os.path.join(HERE, rel)
        with open(path, encoding="ascii") as handle:
            primitives.update(REGISTRATION.findall(handle.read()))
    if not primitives:
        raise ManifestError("no baku-defprim registrations found")
    return primitives


def classify(name, primitives):
    matches = []
    if name in primitives:
        matches.append("primitive")
    if name in COMPATIBILITY:
        matches.append("compatibility function")
    if name in KERNEL_SPECIAL:
        matches.append("kernel special form")
    if len(matches) != 1:
        raise ManifestError(
            "applied symbol %r has %d classifications" % (name, len(matches)))
    return matches[0]


def check_mappings(host_applied, defun_names, mapping):
    """Require one mapping row per host symbol and nothing else.

    The table is a deliverable, so it must be complete in both directions: an
    applied host symbol without a row is undocumented, and a row for a symbol
    the corpus never applies is stale.  A row for a defun-defined name would
    invite a second implementation of a kernel function, so that is an error
    too.
    """
    missing = host_applied - set(mapping)
    if missing:
        raise ManifestError(
            "host symbols without a mapping row: %s"
            % ", ".join(sorted(missing)))
    shadowed = set(mapping) & defun_names
    if shadowed:
        raise ManifestError(
            "mapping rows name defun-defined kernel functions: %s"
            % ", ".join(sorted(shadowed)))
    extra = set(mapping) - host_applied
    if extra:
        raise ManifestError(
            "mapping rows for symbols the corpus never applies: %s"
            % ", ".join(sorted(extra)))
    for name, (ans, note) in sorted(mapping.items()):
        if not ans.strip():
            raise ManifestError("mapping row %r has no ANS Forth entry" % name)
        if not note.strip():
            raise ManifestError("mapping row %r has no reason" % name)


def analyse():
    corpus = load_corpus()
    primitives = load_primitives()

    defuns = {}
    defun_forms = 0
    top_forms = 0
    applied_heads = set()
    raw_heads = set()

    for filename, forms in corpus:
        top_forms += len(forms)
        for form in forms:
            collect_applied(form, applied_heads, include_locals=True)
            collect_raw_heads(form, raw_heads)
            if (isinstance(form, list) and len(form) >= 2
                    and form[0] == "defun" and isinstance(form[1], str)):
                defun_forms += 1
                defuns.setdefault(form[1], set()).add(filename)

    defun_names = set(defuns)
    raw_undefined = raw_heads - defun_names
    applied_undefined = applied_heads - defun_names
    local_heads = {name for name in applied_undefined
                   if LOCAL_HEAD.match(name)}
    host_applied = applied_undefined - local_heads

    classified = primitives | COMPATIBILITY | KERNEL_SPECIAL
    if host_applied - classified:
        raise ManifestError(
            "unclassified applied symbols: %s"
            % ", ".join(sorted(host_applied - classified)))
    if classified - host_applied:
        raise ManifestError(
            "classified symbols never applied: %s"
            % ", ".join(sorted(classified - host_applied)))

    categories = {}
    for name in sorted(host_applied):
        categories[name] = classify(name, primitives)

    check_mappings(host_applied, defun_names, MAPPING)

    return {
        "corpus": corpus,
        "primitives": primitives,
        "defuns": defuns,
        "defun_forms": defun_forms,
        "top_forms": top_forms,
        "raw_heads": raw_heads,
        "raw_undefined": raw_undefined,
        "applied_heads": applied_heads,
        "applied_undefined": applied_undefined,
        "local_heads": local_heads,
        "host_applied": host_applied,
        "categories": categories,
    }


def render(data):
    lines = []
    lines.append("# Baku primitive manifest")
    lines.append("")
    lines.append("Generated by `tools/manifest.py` from the pinned Shen 43.2")
    lines.append("kernel. Do not edit; run `python3 tools/manifest.py --write`")
    lines.append("after a kernel or primitive-source change.")
    lines.append("")
    lines.append("Corpus: `vendor/shen-43.2/klambda`, %d files, %d top-level"
                 % (len(data["corpus"]), data["top_forms"]))
    lines.append("forms (%d `defun` forms and %d copyright strings), %d"
                 % (data["defun_forms"],
                    data["top_forms"] - data["defun_forms"],
                    len(data["defuns"])))
    lines.append("distinct `defun` names.")
    lines.append("")
    lines.append("Filtering: a naive scan of every list head yields %d"
                 % len(data["raw_heads"]))
    lines.append("distinct heads, %d of them not defined by `defun`."
                 % len(data["raw_undefined"]))
    lines.append("The semantic scan walks application positions only, so")
    lines.append("binding lists, `let` variables, `lambda`/`defun` parameter")
    lines.append("lists and `cond` clauses are not applications. It yields %d"
                 % len(data["applied_heads"]))
    lines.append("applied heads: %d are kernel `defun` names, %d are local"
                 % (len(data["applied_heads"]) - len(data["applied_undefined"]),
                    len(data["local_heads"])))
    lines.append("`V...`/`W...` variable heads and %d are host symbols. Every"
                 % len(data["host_applied"]))
    lines.append("host symbol is classified below. An unclassified applied")
    lines.append("symbol, or a registered primitive the corpus never applies,")
    lines.append("fails generation.")
    lines.append("")
    lines.append("## Primitive-to-ANS Forth mapping")
    lines.append("")
    lines.append("One row per applied host symbol. `Baku heap` means the")
    lines.append("primitive is implemented on Baku's value layer and no ANS")
    lines.append("word applies. The mapping is generated from the same data that")
    lines.append("validates it: a host symbol without a row, a row without an")
    lines.append("application, or a row naming a `defun`-defined function fails")
    lines.append("generation.")
    lines.append("")
    lines.append("| KLambda | Classification | ANS Forth 2012 | Implementation |")
    lines.append("|---|---|---|---|")
    for name in sorted(data["host_applied"]):
        category = data["categories"][name]
        ans, note = MAPPING[name]
        lines.append("| `%s` | %s | %s | %s |"
                     % (name, category, ans, note))
    lines.append("")
    lines.append("## Kernel-defined names (excluded)")
    lines.append("")
    lines.append("Every name defined by a top-level `(defun ...)` form in the")
    lines.append("corpus. The host must not implement any of these. A name")
    lines.append("defined more than once is listed once per defining file.")
    lines.append("")
    lines.append("| Name | Defining file |")
    lines.append("|---|---|")
    for name in sorted(data["defuns"]):
        files = ", ".join(sorted(data["defuns"][name]))
        lines.append("| `%s` | %s |" % (name, files))
    lines.append("")
    return "\n".join(lines)


def build_manifest():
    return render(analyse())


def self_test():
    def heads(text):
        found = set()
        for form in read_forms(text):
            collect_applied(form, found)
        return found

    checks = [
        ("(defun f (V1 W2) (cons V1 (let X V2 (g X))))", {"cons", "g"}),
        ("(defun f (V1) (if V1 (and V1 V1) (or V1 (cond ((h V1) (i V1))))))",
         {"h", "i"}),
        ("(defun f (V1) (cons g V1))", {"cons"}),
        ("(defun f (V1) (V1))", set()),
        ("(defun f (V1) (lambda X (s X)))", {"s"}),
        ("(defun f (V1) ((lambda X (u X)) V1))", {"u"}),
        ("(defun f () (cons type ()))", {"cons"}),
        ("(defun f () (f))", {"f"}),
        ("(defun g () 1) (g)", {"g"}),
    ]
    for text, expected in checks:
        actual = heads(text)
        if actual != expected:
            raise ManifestError(
                "self-test: %r yielded %r, expected %r"
                % (text, actual, expected))

    local = set()
    for form in read_forms("(defun f (V1) (V1))"):
        collect_applied(form, local, include_locals=True)
    if local != {"V1"}:
        raise ManifestError("self-test: local head scan yielded %r" % (local,))

    raw = set()
    for form in read_forms("(defun f (V1) (g V1))"):
        collect_raw_heads(form, raw)
    if raw != {"defun", "V1", "g"}:
        raise ManifestError("self-test: raw head scan yielded %r" % (raw,))

    if classify("+", {"+"}) != "primitive":
        raise ManifestError("self-test: + is not classified as a primitive")
    if classify("input+", set()) != "compatibility function":
        raise ManifestError("self-test: input+ category is wrong")
    if classify("eval-kl", {"eval-kl"}) != "primitive":
        raise ManifestError("self-test: eval-kl category is wrong")
    if classify("type", set()) != "kernel special form":
        raise ManifestError("self-test: type category is wrong")
    try:
        classify("unclassified", set())
    except ManifestError:
        pass
    else:
        raise ManifestError("self-test: an unclassified symbol was accepted")

    complete = {"+": ("Core `+`", "sum")}
    check_mappings({"+", "eval-kl"}, set(), {
        "+": complete["+"],
        "eval-kl": ("Baku evaluator", "entry point"),
    })

    def expect_mapping_error(host_applied, defun_names, mapping):
        try:
            check_mappings(host_applied, defun_names, mapping)
        except ManifestError:
            return
        raise ManifestError("self-test: an invalid mapping was accepted")

    expect_mapping_error({"+", "eval-kl"}, set(), complete)
    expect_mapping_error({"+", "eval-kl"}, set(), {
        "+": complete["+"],
        "eval-kl": ("Baku evaluator", "entry point"),
        "kernel-fn": ("Baku heap", "stale row"),
    })
    expect_mapping_error({"+", "eval-kl", "kernel-fn"}, {"kernel-fn"}, {
        "+": complete["+"],
        "eval-kl": ("Baku evaluator", "entry point"),
        "kernel-fn": ("Baku heap", "shadowing row"),
    })
    expect_mapping_error({"+", "eval-kl"}, set(), {
        "+": ("", "no ANS entry"),
        "eval-kl": ("Baku evaluator", "entry point"),
    })

    print("BAKU-MANIFEST-SELFTEST PASS")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Generate or verify the Baku primitive manifest.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true",
                       help="regenerate %s" % OUTPUT)
    group.add_argument("--check", action="store_true",
                       help="fail if %s is stale" % OUTPUT)
    group.add_argument("--self-test", action="store_true",
                       help="run the parser and classifier self-test")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    try:
        generated = build_manifest()
    except (ManifestError, ParseError) as exc:
        print("BAKU-MANIFEST FAIL: %s" % exc, file=sys.stderr)
        return 1

    if args.write:
        os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
        with open(OUTPUT, "w", encoding="ascii") as handle:
            handle.write(generated)
        print("wrote %s" % OUTPUT)
        return 0

    try:
        with open(OUTPUT, encoding="ascii") as handle:
            committed = handle.read()
    except OSError as exc:
        print("BAKU-MANIFEST FAIL: cannot read %s: %s" % (OUTPUT, exc),
              file=sys.stderr)
        return 1

    if committed != generated:
        print("BAKU-MANIFEST FAIL: %s is stale; run --write" % OUTPUT,
              file=sys.stderr)
        return 1

    print("BAKU-MANIFEST PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
