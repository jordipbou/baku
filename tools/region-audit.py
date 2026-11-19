#!/usr/bin/env python3
"""Static cross-region store audit for Baku's shipped sources.

The memory-management requirement says every Shen object lives in the region
that matches its lifetime, that the GC owns its own heap block, and that the
compiler and runtime create no cross-region reference outside the GC roots.
The checked store is deferred, so this source audit is the guard until a
runtime check exists.

The scan follows the shipped INCLUDED graph rooted at 4th/baku.4th and
4th/start.4th, exactly like the ANS and vendored-source audits.  For every raw
store word (!, +!, 2!, C!, DF!, F!) it classifies the destination:

  * a named dictionary cell (VARIABLE, CREATE, VALUE, DEFER, ...) and the
    standard BASE variable are ordinary cell stores;
  * any other destination is a computed address.  Those are the places where a
    value could be written into a heap object or across a region boundary, so
    every one must appear in REVIEWED below with its enclosing definition, the
    number of stores in that definition, a category and a reason.

A new raw address store anywhere, or an extra store inside a reviewed
definition, fails the audit until it is deliberately reviewed.  Object payload
stores are expected only in the value layer's constructors/writers; the closure
writer in 4th/eval.4th is the one reviewed exception, and non-pointer scalar
fields (stream mode/handle, object headers, byte buffers) are called out.

Comments and string literals are not words.
"""

import argparse
import sys
from collections import Counter
from pathlib import Path

from forth_source import build_units, collect_shipped, tokenize

# Store words that write a whole cell, a double cell or a byte.
STORE_WORDS = {"!", "+!", "2!", "C!", "DF!", "F!"}

# Words whose next token is a name or a character, not a store use.
SKIP_NEXT_TOKEN = {"CHAR", "[CHAR]", "[DEFINED]", "[UNDEFINED]"}

# Definitions that reserve an ordinary dictionary cell.  A store to one of
# these names writes the dictionary, never a heap object payload.
CELL_DEFINITIONS = {
    "VARIABLE", "CREATE", "VALUE", "DEFER", "CONSTANT", "2VARIABLE",
    "2CONSTANT", "2VALUE", "FVARIABLE", "FCONSTANT", "MARKER",
}

# Standard variable words that are dictionary cells but are not defined by the
# shipped tree.
EXTERNAL_CELLS = {"BASE"}

CATEGORY_VALUE_WRITER = "value-writer"
CATEGORY_METADATA = "metadata"
CATEGORY_DICTIONARY = "dictionary"
CATEGORY_SCALAR = "scalar"
CATEGORY_PROBE = "probe"

# Every computed-address store in the shipped tree, keyed by
# (relative source file, enclosing colon definition).  The value is
# (expected store count, category, reason).  Editing this table is the review.
REVIEWED = {
    # Evaluator tables are dictionary arrays.
    ("4th/eval.4th", "BAKU-CLOSURE!"):
        (1, CATEGORY_VALUE_WRITER,
         "single closure payload writer; callers keep values same-region"),
    ("4th/eval.4th", "BAKU-FN-DEFINE"):
        (1, CATEGORY_DICTIONARY, "function bucket array is dictionary memory"),
    ("4th/eval.4th", "BAKU-FN-RESET"):
        (1, CATEGORY_DICTIONARY, "clears the function bucket array"),
    ("4th/eval.4th", "BAKU-GLOBAL-PREPEND"):
        (1, CATEGORY_DICTIONARY, "global bucket array is dictionary memory"),
    ("4th/eval.4th", "BAKU-GLOBAL-RESET"):
        (1, CATEGORY_DICTIONARY, "clears the global bucket array"),

    # Collector metadata and the explicit root registry.
    ("4th/gc.4th", "BAKU-GC-COPY"):
        (1, CATEGORY_METADATA, "forwarding header in the from-space"),
    ("4th/gc.4th", "BAKU-GC-ROOT+"):
        (3, CATEGORY_METADATA, "registered root cells"),
    ("4th/gc.4th", "BAKU-GC-ROOT-CELL"):
        (1, CATEGORY_METADATA, "registered root range cells"),
    ("4th/gc.4th", "BAKU-GC-SCAN-TABLE-ENTRY"):
        (1, CATEGORY_METADATA, "updates a shape-aware table root cell"),
    ("4th/gc.4th", "BAKU-GC-TABLE+"):
        (2, CATEGORY_METADATA, "table root registry cells"),

    # Threaded code, its parameter cells and argument scratch are dictionary
    # memory.  Literals are copied into the permanent non-GC heap first.
    ("4th/native.4th", "BAKU-NATIVE-COLLECT"):
        (1, CATEGORY_DICTIONARY, "native argument buffer"),
    ("4th/native.4th", "BAKU-NATIVE-COMPILE-BLOCK"):
        (2, CATEGORY_DICTIONARY, "threaded code block header and parameters"),
    ("4th/native.4th", "BAKU-NATIVE-PARAM-SET"):
        (1, CATEGORY_DICTIONARY, "native parameter buffer"),
    ("4th/native.4th", "BAKU-NATIVE-PUT"):
        (1, CATEGORY_DICTIONARY, "threaded code emission cursor"),

    # Scalar object fields and byte buffers carry no reference.
    ("4th/primitives.4th", "BAKU-NUM-C!"):
        (1, CATEGORY_SCALAR, "formatter scratch buffer in dictionary memory"),
    ("4th/primitives.4th", "BAKU-STREAM"):
        (2, CATEGORY_SCALAR, "stream mode and handle are non-pointer fields"),

    # A diagnostic probe writes a Forth flag into a caller-supplied variable.
    ("4th/probe.4th", "BAKU-PROBE-WORD"):
        (1, CATEGORY_PROBE, "writes a missing-wordset flag into a caller cell"),

    # Scratch buffers.
    ("4th/reader.4th", "BAKU-BUF-PUT"):
        (1, CATEGORY_SCALAR, "builds a scratch string payload byte by byte"),
    ("4th/repl.4th", "BAKU-REPL-ACC-PUT"):
        (1, CATEGORY_DICTIONARY, "line buffer in dictionary memory"),

    # The value layer owns allocation, headers, the region map and the object
    # writers.
    ("4th/value.4th", "BAKU-ALLOC"):
        (2, CATEGORY_METADATA, "bump pointer and uniform object header"),
    ("4th/value.4th", "BAKU-CONS"):
        (2, CATEGORY_VALUE_WRITER, "cons constructor writers"),
    ("4th/value.4th", "BAKU-FLOAT"):
        (1, CATEGORY_VALUE_WRITER, "boxed double payload"),
    ("4th/value.4th", "BAKU-INTERN"):
        (2, CATEGORY_VALUE_WRITER,
         "permanent symbol payload and its bucket chain"),
    ("4th/value.4th", "BAKU-OBJECT-SIZE!"):
        (1, CATEGORY_METADATA, "rewrites the object header size field"),
    ("4th/value.4th", "BAKU-REGION+"):
        (3, CATEGORY_METADATA, "region map arrays are dictionary memory"),
    ("4th/value.4th", "BAKU-REGION-UPDATE"):
        (3, CATEGORY_METADATA, "region map arrays are dictionary memory"),
    ("4th/value.4th", "BAKU-SET-HD"):
        (1, CATEGORY_VALUE_WRITER, "cons head writer"),
    ("4th/value.4th", "BAKU-SET-TL"):
        (1, CATEGORY_VALUE_WRITER, "cons tail writer"),
    ("4th/value.4th", "BAKU-STRING-QUOTE"):
        (2, CATEGORY_SCALAR, "quote bytes inside the string payload"),
    ("4th/value.4th", "BAKU-SYMBOL-RESET"):
        (1, CATEGORY_DICTIONARY, "clears the symbol bucket array"),
    ("4th/value.4th", "BAKU-VECTOR!"):
        (1, CATEGORY_VALUE_WRITER, "vector element writer"),
}

# Files whose job is compiling or running Shen code.  Only their reviewed
# value-layer writer may touch an object payload.
COMPILER_RUNTIME = {
    "4th/eval.4th",
    "4th/frontend.4th",
    "4th/native.4th",
    "4th/boot.4th",
    "4th/repl.4th",
    "4th/compat.4th",
}


def definition_cells(shipped):
    """Return the upper-case names defined as dictionary cells."""
    cells = set()
    for path in shipped:
        tokens = tokenize(path.read_text())
        for index, (kind, value, _) in enumerate(tokens):
            if kind != "word" or value.upper() not in CELL_DEFINITIONS:
                continue
            if index + 1 < len(tokens) and tokens[index + 1][0] == "word":
                cells.add(tokens[index + 1][1].upper())
    return cells


def scan_stores(tokens, cells):
    """Return (cell stores, computed stores) for one file.

    A computed store is (line, unit name, destination word, store word).
    """
    units = build_units(tokens)
    owner = {}
    for unit in units:
        for index in unit["indices"]:
            owner[index] = unit

    cell_stores = 0
    computed = []
    index = 0
    while index < len(tokens):
        kind, value, line = tokens[index]
        upper = value.upper() if kind == "word" else ""
        if kind == "word" and upper in SKIP_NEXT_TOKEN:
            index += 2
            continue
        if kind != "word" or upper not in STORE_WORDS:
            index += 1
            continue
        previous = tokens[index - 1] if index > 0 else ("", "", 0)
        destination = previous[1].upper() if previous[0] == "word" else None
        if destination in cells or destination in EXTERNAL_CELLS:
            cell_stores += 1
        else:
            unit = owner.get(index, units[0])
            computed.append((line, unit["name"], previous[1], value))
        index += 1
    return cell_stores, computed


def audit(root, verbose=False):
    shipped, _ = collect_shipped(root)
    cells = definition_cells(shipped)

    violations = []
    reviewed_counts = Counter()
    category_counts = Counter()
    computed_total = 0
    cell_total = 0
    runtime_payload = []

    for path in shipped:
        rel = path.relative_to(root).as_posix()
        tokens = tokenize(path.read_text())
        cell_stores, computed = scan_stores(tokens, cells)
        cell_total += cell_stores
        computed_total += len(computed)
        for line, unit_name, destination, store in computed:
            reviewed_counts[(rel, unit_name)] += 1
            entry = REVIEWED.get((rel, unit_name))
            if entry is None:
                violations.append(
                    (rel, line,
                     f"raw address store {destination} {store} in unreviewed "
                     f"unit {unit_name}"))
                continue
            _, category, _ = entry
            category_counts[category] += 1
            if category == CATEGORY_VALUE_WRITER and rel in COMPILER_RUNTIME:
                runtime_payload.append((rel, unit_name))
            if verbose:
                print(f"    {rel}:{line}: {unit_name} "
                      f"{destination} {store} [{category}]")

    for (rel, unit_name), (expected, category, reason) in sorted(REVIEWED.items()):
        actual = reviewed_counts.get((rel, unit_name), 0)
        if actual != expected:
            violations.append(
                (rel, 0,
                 f"reviewed unit {unit_name} has {actual} raw address "
                 f"stores, allowlist expects {expected} ({category}: {reason})"))

    unknown_reviews = sorted(set(REVIEWED) - set(reviewed_counts))
    for rel, unit_name in unknown_reviews:
        violations.append(
            (rel, 0,
             f"allowlist names {unit_name}, which has no raw address store"))

    print("Cross-region store audit")
    print(f"  root: {root}")
    print(f"  shipped files: {len(shipped)}")
    print(f"  dictionary-cell stores: {cell_total}")
    print(f"  computed-address stores: {computed_total}")
    print(f"  reviewed computed-address stores: {sum(reviewed_counts.values())}")
    for category in (CATEGORY_VALUE_WRITER, CATEGORY_METADATA,
                     CATEGORY_DICTIONARY, CATEGORY_SCALAR, CATEGORY_PROBE):
        print(f"    {category}: {category_counts.get(category, 0)}")
    print(f"  compiler/runtime object-payload writers: {len(runtime_payload)}")
    for rel, unit_name in sorted(set(runtime_payload)):
        print(f"    {rel} {unit_name}")

    if violations:
        print("UNREVIEWED-STORES:")
        for rel, line, reason in sorted(violations):
            location = f"{rel}:{line}" if line else rel
            print(f"  {location}: {reason}")

    ok = not violations
    print("REGION-AUDIT " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="repository root containing 4th/baku.4th and 4th/start.4th")
    parser.add_argument("--verbose", action="store_true",
                        help="list every computed-address store")
    args = parser.parse_args()
    return audit(Path(args.root).resolve(), args.verbose)


if __name__ == "__main__":
    sys.exit(main())
