#!/usr/bin/env python3
"""String-aware parser for the vendored Shen 43.2 KLambda corpus.

This is a development-only module shared by the dev tools.  It is never
shipped and never used at runtime.

The corpus uses literal strings, not escape sequences: a backslash inside a
string is data and a '"' always terminates the string.  Comments follow the
Shen source syntax used by 4th/reader.4th: '\\\\' starts a line comment and
'\\*' starts a block comment ending at '*\\'.

Forms are represented as:

  * list                 -> a KLambda list
  * str                  -> an atom (symbol or number)
  * StringLiteral        -> a string literal, kept distinct from atoms

The parser deliberately has no number conversion: the manifest only needs the
application structure, so keeping numbers as atoms is both simpler and exact.
"""


class ParseError(Exception):
    """The input is not a balanced KLambda form."""


class StringLiteral:
    """A KLambda string, distinct from a symbol with the same spelling."""

    __slots__ = ("text",)

    def __init__(self, text):
        self.text = text

    def __eq__(self, other):
        return isinstance(other, StringLiteral) and other.text == self.text

    def __hash__(self):
        return hash((StringLiteral, self.text))

    def __repr__(self):
        return "StringLiteral(%r)" % (self.text,)


def tokenize(text):
    """Return '(' / ')' / atom strings / StringLiteral tokens."""
    tokens = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c == "(" or c == ")":
            tokens.append(c)
            i += 1
            continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 1
            if j >= n:
                raise ParseError("unterminated string at offset %d" % i)
            tokens.append(StringLiteral(text[i + 1:j]))
            i = j + 1
            continue
        if c == "\\":
            if i + 1 >= n:
                raise ParseError("dangling backslash at offset %d" % i)
            kind = text[i + 1]
            if kind == "\\":
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
                continue
            if kind == "*":
                j = text.find("*\\", i + 2)
                if j < 0:
                    raise ParseError("unterminated block comment at offset %d" % i)
                i = j + 2
                continue
            raise ParseError("unknown backslash sequence at offset %d" % i)
        j = i
        while j < n:
            c = text[j]
            if c.isspace() or c in '()"\\':
                break
            j += 1
        tokens.append(text[i:j])
        i = j
    return tokens


def parse_list(tokens, pos):
    if pos >= len(tokens) or tokens[pos] != "(":
        raise ParseError("expected '(' at token %d" % pos)
    pos += 1
    items = []
    while True:
        if pos >= len(tokens):
            raise ParseError("unterminated list")
        token = tokens[pos]
        if token == ")":
            return items, pos + 1
        if token == "(":
            item, pos = parse_list(tokens, pos)
        else:
            item = token
            pos += 1
        items.append(item)


def read_forms(text):
    """Parse every top-level form in text, including bare strings/atoms."""
    tokens = tokenize(text)
    forms = []
    pos = 0
    while pos < len(tokens):
        token = tokens[pos]
        if token == "(":
            form, pos = parse_list(tokens, pos)
        elif token == ")":
            raise ParseError("unexpected ')' at token %d" % pos)
        else:
            form = token
            pos += 1
        forms.append(form)
    return forms
