"""Shared Forth source scanning for Baku's host-side static checks.

The ANS audit and the vendored-source audit both need the same view of Baku's
shipped Forth: whitespace-delimited words with comments and string literals
removed, plus the INCLUDED graph rooted at every shipped entry point.  Keep that
view here so the two checks cannot disagree about what a word or an include is.
"""

import re
from pathlib import Path

ENTRIES = ("4th/baku.4th", "4th/start.4th")

DEFINING_WORDS = {
    ":", ":NONAME", "VARIABLE", "CONSTANT", "CREATE", "DEFER", "VALUE",
    "MARKER", "2VARIABLE", "2CONSTANT", "2VALUE", "FVARIABLE", "FCONSTANT",
    "SYNONYM",
}

STRING_WORDS = {
    'S"', '."', 'C"', 'ABORT"', 'S\\"',
}

# Words whose next token is a literal or an environment query argument, not a
# word use: CHAR/[CHAR] take a character, [DEFINED]/[UNDEFINED] take a name.
SKIP_NEXT_TOKEN = {
    "CHAR", "[CHAR]", "[DEFINED]", "[UNDEFINED]",
}

NUMBER_RE = re.compile(
    r"^[+-]?(?:"
    r"\d+(?:\.\d*)?|\.\d+"
    r")(?:[eEdD][+-]?\d*)?$"
    r"|^\$[0-9A-Fa-f]+$"
    r"|^0[xX][0-9A-Fa-f]+$"
)


def tokenize(text):
    """Return (kind, value, line) with kind 'word' or 'string'."""
    tokens = []
    i = 0
    n = len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c.isspace():
            i += 1
            continue
        boundary = i == 0 or text[i - 1].isspace()
        if c == "\\" and boundary:
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "(" and boundary:
            j = text.find(")", i)
            if j < 0:
                j = n
            line += text.count("\n", i, j)
            i = j + 1
            continue
        j = i
        while j < n and not text[j].isspace():
            j += 1
        tok = text[i:j]
        tokens.append(("word", tok, line))
        if tok.upper() in STRING_WORDS:
            k = text.find('"', j)
            if k < 0:
                k = n
            content = text[j:k]
            tokens.append(("string", content, line))
            line += text.count("\n", j, k)
            i = k + 1
        else:
            i = j
    return tokens


def build_units(tokens):
    """Group tokens into colon definitions and one top-level unit.

    A unit owns the token indices between its defining word and the matching
    semicolon.  Returned as dicts with name, line and indices so source audits
    can attribute a word use to the definition that contains it.
    """
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


def resolve_include(root, including, target):
    candidates = [root / target, including.parent / target]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return None


def collect_shipped(root, entries=ENTRIES):
    """Return (sorted shipped files, include edges) from every entry point."""
    shipped = []
    seen = set()
    stack = []
    includes = []
    for entry_name in entries:
        entry = root / entry_name
        if not entry.is_file():
            raise SystemExit(f"forth-source: entry point not found: {entry}")
        stack.append(entry.resolve())
    while stack:
        path = stack.pop()
        if path in seen:
            continue
        seen.add(path)
        shipped.append(path)
        try:
            text = path.read_text()
        except UnicodeDecodeError as exc:
            raise SystemExit(f"forth-source: cannot read {path}: {exc}")
        tokens = tokenize(text)
        for idx, (kind, value, line) in enumerate(tokens):
            if kind != "word" or value.upper() != "INCLUDED":
                continue
            if idx == 0 or tokens[idx - 1][0] != "string":
                continue
            target = tokens[idx - 1][1].strip()
            includes.append((path, line, target))
            resolved = resolve_include(root, path, target)
            if resolved is not None:
                stack.append(resolved)
    return sorted(shipped), includes
