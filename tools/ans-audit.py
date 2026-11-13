#!/usr/bin/env python3
"""Static ANS Forth 2012 audit for Baku's shipped sources.

The shipped path starts at every entry point (4th/baku.4th and the one-line
user entry 4th/start.4th) and follows every INCLUDED reference.  For each
shipped file the audit:

  * lists every external word and maps it to an ANS Forth 2012 wordset;
  * fails on any word that is neither ANS Forth 2012 nor defined by Baku;
  * fails on any C, Java, JavaScript or shell file in the shipped path;
  * fails on any DODO reference in the shipped path.

Comments (\\ to end of line and ( ... )) and string literals are not words.

Baku may also document a portability-file exception: add the file and its
allowed non-ANS words to DOCUMENTED_PORTABILITY_EXCEPTIONS.  The exception is
reported explicitly and is the only place a non-ANS word may appear.

The ANS word list in tools/ans-2012-words.txt is generated from the Forth 2012
Annex H (Alphabetic list of words), one "WORD<TAB>WORDSET" per line.
"""

import argparse
import sys
from pathlib import Path

from forth_source import (
    DEFINING_WORDS,
    ENTRIES,
    NUMBER_RE,
    SKIP_NEXT_TOKEN,
    STRING_WORDS,
    collect_shipped,
    resolve_include,
    tokenize,
)

# A single documented portability file may isolate a non-ANS word.  Baku has
# no such file today; keep this empty rather than silently allowing words.
DOCUMENTED_PORTABILITY_EXCEPTIONS = {
    # The GC needs the Forth stack roots.  This one adapter is [DEFINED]-gated;
    # a target without stack pointers keeps a no-op adapter and refuses GC
    # activation with a catchable error instead of missing a root.
    "4th/gc-stack.4th": {"SP0", "SP@", "RP0", "RP@"},
}

# The project spec (specs/forth-portability.md) says INCLUDE is not the
# standard word to use; INCLUDED is.  The 2012 annex lists INCLUDE as a
# File-Access extension, so treat it as forbidden for Baku anyway.
FORBIDDEN = {
    "INCLUDE": "use INCLUDED; INCLUDE is forbidden by specs/forth-portability.md",
}

HOST_EXTENSIONS = {
    ".c", ".h", ".cc", ".cpp", ".cxx", ".hpp",
    ".java", ".class", ".jar",
    ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx",
    ".sh", ".bash", ".zsh", ".ksh",
}

def load_standard(path):
    standard = {}
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        word, _, wordset = line.partition("\t")
        standard[word.strip().upper()] = wordset.strip()
    return standard


def audit(root, verbose=False):
    standard = load_standard(Path(__file__).resolve().parent / "ans-2012-words.txt")
    shipped, includes = collect_shipped(root)

    violations = []
    dodo = []
    host_files = []
    standard_used = {}
    baku_used = set()
    exceptions_used = []
    literals = set()

    all_defs = set()
    all_tokens = {}
    for path in shipped:
        toks = tokenize(path.read_text())
        all_tokens[path] = toks
        for idx, (kind, value, line) in enumerate(toks):
            if kind != "word":
                continue
            up = value.upper()
            if up in DEFINING_WORDS and idx + 1 < len(toks):
                nxt = toks[idx + 1]
                if nxt[0] == "word":
                    all_defs.add(nxt[1].upper())

    for path in shipped:
        rel = path.relative_to(root).as_posix()
        if path.suffix.lower() in HOST_EXTENSIONS:
            host_files.append(rel)
        allowed_exceptions = DOCUMENTED_PORTABILITY_EXCEPTIONS.get(rel, set())
        toks = all_tokens[path]
        idx = 0
        while idx < len(toks):
            kind, value, line = toks[idx]
            idx += 1
            if kind != "word":
                continue
            up = value.upper()
            if "DODO" in up:
                dodo.append((rel, line, value))
            if NUMBER_RE.match(up):
                literals.add(up)
                continue
            if up in SKIP_NEXT_TOKEN:
                idx += 1
                continue
            if up in DEFINING_WORDS:
                continue
            if up in all_defs:
                baku_used.add(up)
                continue
            if up in FORBIDDEN:
                violations.append((rel, line, value, FORBIDDEN[up]))
                continue
            if up in allowed_exceptions:
                exceptions_used.append((rel, line, value))
                continue
            if up in standard:
                standard_used[up] = standard[up]
                continue
            violations.append((rel, line, value, "not ANS Forth 2012"))

    for path, line, target in includes:
        rel = path.relative_to(root).as_posix()
        suffix = Path(target).suffix.lower()
        if suffix in HOST_EXTENSIONS:
            host_files.append(f"{rel}:{line}: INCLUDED {target}")
        if "DODO" in target.upper():
            dodo.append((rel, line, target))
        if resolve_include(root, path, target) is None:
            violations.append((rel, line, target, "included file not found"))

    # Any host-language file physically present in the shipped directory tree
    # is a violation even if nothing includes it.
    fourth = root / "4th"
    if fourth.is_dir():
        for path in sorted(fourth.rglob("*")):
            if path.is_file() and path.suffix.lower() in HOST_EXTENSIONS:
                rel = path.relative_to(root).as_posix()
                if rel not in host_files:
                    host_files.append(rel)

    print("ANS Forth 2012 audit")
    print(f"  root: {root}")
    print(f"  shipped files: {len(shipped)}")
    for path in shipped:
        print(f"    {path.relative_to(root).as_posix()}")
    print(f"  standard words used: {len(standard_used)}")
    for word in sorted(standard_used):
        print(f"    {word}\t{standard_used[word]}")
    print(f"  Baku-defined words used: {len(baku_used)}")
    if verbose:
        for word in sorted(baku_used):
            print(f"    {word}")
    if literals:
        print(f"  numeric literals: {len(literals)}")
    if exceptions_used:
        print("  documented portability exceptions:")
        for rel, line, word in exceptions_used:
            print(f"    {rel}:{line}: {word}")

    if host_files:
        print("HOST-LANGUAGE FILES:")
        for item in sorted(host_files):
            print(f"  {item}")
    if dodo:
        print("DODO REFERENCES:")
        for rel, line, word in sorted(dodo):
            print(f"  {rel}:{line}: {word}")
    if violations:
        print("NON-ANS WORDS:")
        for rel, line, word, reason in sorted(violations):
            print(f"  {rel}:{line}: {word} ({reason})")

    ok = not violations and not host_files and not dodo
    print("ANS-AUDIT " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="repository root containing 4th/baku.4th and 4th/start.4th")
    parser.add_argument("--verbose", action="store_true",
                        help="also list Baku-defined words")
    args = parser.parse_args()
    return audit(Path(args.root).resolve(), args.verbose)


if __name__ == "__main__":
    sys.exit(main())
