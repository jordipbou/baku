#!/usr/bin/env python3
"""Static vendored-kernel immutability audit for Baku's shipped sources.

The kernel-provenance requirement says no shipped Baku source may edit, patch,
wrap or string-replace a file under vendor/shen-43.2/.  The tree digest proves
the vendored bytes are untouched at rest; this scan proves the shipped Forth
has no write or replacement path aimed at them.

The scan treats the shipped tree as the INCLUDED graph rooted at 4th/baku.4th
and 4th/start.4th, exactly like the ANS audit.  It enforces one read prefix:

  * the only vendored path literal allowed is the prefix returned by
    BAKU-BOOT-DIR in 4th/boot.4th;
  * no unit that mentions that prefix (or another BAKU-BOOT- word) may contain
    a file-write, rename, delete, resize or string-replacement operation.

A future legitimate vendored read must go through BAKU-BOOT-DIR/BAKU-BOOT-PATH;
a new literal or a write in the boot path fails the scan and needs a deliberate
change to this allowlist.  Comments and string data are not words.
"""

import argparse
import sys
from pathlib import Path

from forth_source import collect_shipped, tokenize

VENDOR_MARKER = "vendor/shen-43.2"
ALLOWED_LITERAL_FILE = "4th/boot.4th"
ALLOWED_LITERAL_UNIT = "BAKU-BOOT-DIR"

# Output words that mutate a named file.  OPEN-FILE is added only when the unit
# also names an output file access method.
FILE_MUTATION_WORDS = {
    "CREATE-FILE", "DELETE-FILE", "RENAME-FILE", "RESIZE-FILE",
    "WRITE-FILE", "WRITE-LINE", "FLUSH-FILE",
}
WRITE_FAM = {"W/O", "R/W"}

# Word-name fragments that denote a write or a string replacement.  These catch
# a Baku-specific helper (for example a FUTURE BAKU-REPLACE-FILE) that is not
# one of the standard file words.  Matching is on the whole upper-case token.
MUTATION_FRAGMENTS = (
    "WRITE", "PATCH", "REPLACE", "SUBSTITUTE", "OVERWRITE", "REWRITE",
    "TRUNCATE", "RESIZE", "MODIFY", "DELETE", "RENAME",
)

# Any unit that mentions a boot word can carry the vendored prefix.  Boot has
# one name family, so a write added anywhere in it is rejected.
VENDOR_UNIT_PREFIX = "BAKU-BOOT-"


def is_vendor_literal(text):
    return VENDOR_MARKER in text.replace("\\", "/").lower()


def build_units(tokens):
    """Group tokens into colon definitions and one top-level unit."""
    top = {"name": "<TOPLEVEL>", "line": 1, "indices": []}
    units = [top]
    current = top
    index = 0
    while index < len(tokens):
        kind, value, line = tokens[index]
        upper = value.upper() if kind == "word" else ""
        if kind == "word" and upper in (":", ":NONAME"):
            name = "<NONAME>"
            next_index = index + 1
            if (upper == ":" and next_index < len(tokens)
                    and tokens[next_index][0] == "word"):
                name = tokens[next_index][1].upper()
                next_index += 1
            unit = {"name": name, "line": line, "indices": []}
            units.append(unit)
            current = unit
            index = next_index
            continue
        if kind == "word" and upper == ";" and current is not top:
            current = top
            index += 1
            continue
        current["indices"].append(index)
        index += 1
    return units


def mutation_hits(tokens, indices):
    """Return (token index, word) for every write/replace operation."""
    hits = {}
    has_write_fam = False
    for index in indices:
        kind, value, _ = tokens[index]
        if kind != "word":
            continue
        upper = value.upper()
        if upper in WRITE_FAM:
            has_write_fam = True
        if upper in FILE_MUTATION_WORDS:
            hits[index] = value
        elif any(fragment in upper for fragment in MUTATION_FRAGMENTS):
            hits[index] = value
    if has_write_fam:
        for index in indices:
            kind, value, _ = tokens[index]
            if kind == "word" and value.upper() == "OPEN-FILE":
                hits[index] = value
    return sorted(hits.items())


def unit_touches_vendor(unit, tokens):
    for index in unit["indices"]:
        kind, value, _ = tokens[index]
        if kind != "word":
            continue
        if value.upper().startswith(VENDOR_UNIT_PREFIX):
            return True
    return False


def audit(root, verbose=False):
    shipped, _ = collect_shipped(root)

    violations = []
    literal_count = 0
    touching_units = 0
    writes = 0

    for path in shipped:
        rel = path.relative_to(root).as_posix()
        tokens = tokenize(path.read_text())
        units = build_units(tokens)
        owner = {}
        for unit in units:
            for index in unit["indices"]:
                owner[index] = unit

        for index, (kind, value, line) in enumerate(tokens):
            if kind != "string" or not is_vendor_literal(value):
                continue
            literal_count += 1
            unit = owner.get(index, units[0])
            if rel == ALLOWED_LITERAL_FILE and unit["name"] == ALLOWED_LITERAL_UNIT:
                continue
            violations.append(
                (rel, line, f"vendored path literal {value!r} outside "
                            f"{ALLOWED_LITERAL_FILE} {ALLOWED_LITERAL_UNIT} "
                            f"(unit {unit['name']})"))

        for unit in units:
            if not unit_touches_vendor(unit, tokens):
                continue
            touching_units += 1
            for index, word in mutation_hits(tokens, unit["indices"]):
                _, _, line = tokens[index]
                writes += 1
                violations.append(
                    (rel, line, f"{word} can rewrite a vendored file "
                                f"(unit {unit['name']})"))

    if literal_count != 1:
        violations.append(
            ("4th/boot.4th", 1,
             f"expected exactly one vendored path literal, found {literal_count}"))

    print("Vendored kernel source audit")
    print(f"  root: {root}")
    print(f"  shipped files: {len(shipped)}")
    print(f"  vendored path literals: {literal_count} "
          f"(allowed only in {ALLOWED_LITERAL_FILE} {ALLOWED_LITERAL_UNIT})")
    print(f"  vendor-touching units: {touching_units}")
    print(f"  write/replace operations in vendor-touching units: {writes}")
    if verbose:
        for path in shipped:
            print(f"    {path.relative_to(root).as_posix()}")

    if violations:
        print("VENDOR-MUTATIONS:")
        for rel, line, reason in sorted(violations):
            print(f"  {rel}:{line}: {reason}")

    ok = not violations
    print("VENDOR-AUDIT " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="repository root containing 4th/baku.4th and 4th/start.4th")
    parser.add_argument("--verbose", action="store_true",
                        help="list every shipped file")
    args = parser.parse_args()
    return audit(Path(args.root).resolve(), args.verbose)


if __name__ == "__main__":
    sys.exit(main())
