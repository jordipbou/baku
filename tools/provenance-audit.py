#!/usr/bin/env python3
"""Licensing and kernel-provenance audit for Baku.

The kernel-provenance requirement says Baku loads the unmodified official Shen
43.2 KLambda kernel and that the attribution and licence obligations are
recorded.  The tree digests prove the vendored bytes; this audit proves the
provenance metadata and the licence texts that accompany them are complete,
internally consistent and referenced from the README.

Checks:

  * the repository LICENSE contains the MIT grant and disclaimer;
  * vendor/shen-43.2/LICENSE.txt contains the BSD 3-Clause Mark Tarver licence;
  * vendor/shen-43.2/README.md and TESTS.md record the same pinned project,
    upstream, release, tag, commit, asset URL and asset SHA-256;
  * those values still match the release pinned by the provenance requirement,
    and each provenance file records its own 64-hex tree digest;
  * the top-level README names both licence files and both provenance files and
    states the MIT and BSD 3-Clause terms;
  * the official release tarball is vendored beside the extracted trees and its
    bytes reproduce the pinned SHA-256.

The release tarball is vendored, so this audit re-hashes it offline.  The
extracted tree digests are recomputed by baku_kernel_digest and baku_tests_digest,
and baku_release_asset extracts the tarball and re-runs those digests; this audit
does not duplicate that tree-digest logic.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path

PIN = {
    "Project": "Shen",
    "Upstream": "https://github.com/Shen-Language/shen-sources",
    "Release": "Shen OS Kernel 43.2",
    "Tag": "shen-43.2",
    "Commit": "e6947f507ebc03f7ade5d2a8d971bd05d84a5bae",
    "Asset": "https://github.com/Shen-Language/shen-sources/releases/download/"
             "shen-43.2/ShenOSKernel-43.2.tar.gz",
    "Asset SHA-256": "23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32",
}

ASSET_NAME = PIN["Asset"].rsplit("/", 1)[-1]

METADATA_KEYS = [
    "Project", "Upstream", "Release", "Tag", "Commit", "Asset",
    "Asset SHA-256", "Tree SHA-256", "Vendored on",
]
# Tree digest and vendoring date are per-tree; the release identity is shared.
SHARED_KEYS = [key for key in METADATA_KEYS
               if key not in ("Tree SHA-256", "Vendored on")]

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
FIELD_RE = re.compile(r"^-\s+([^:]+):\s+(.*?)\s*$")


def parse_metadata(path, violations):
    fields = {}
    if not path.is_file():
        violations.append((path.name, "missing provenance file"))
        return fields
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        match = FIELD_RE.match(line)
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if key in METADATA_KEYS and key not in fields:
            fields[key] = value.strip("`").strip()
    for key in METADATA_KEYS:
        if key not in fields or not fields[key]:
            violations.append((path.name, f"missing provenance field {key!r}"))
    return fields


def check_pin(fields, path, violations):
    label = path.name
    for key, expected in PIN.items():
        actual = fields.get(key)
        if actual is not None and actual != expected:
            violations.append(
                (label, f"{key} is {actual!r}, expected the pinned {expected!r}"))
    commit = fields.get("Commit")
    if commit and not COMMIT_RE.match(commit):
        violations.append((label, f"Commit is not a 40-hex commit: {commit!r}"))
    digest = fields.get("Tree SHA-256")
    if digest and not SHA256_RE.match(digest):
        violations.append(
            (label, f"Tree SHA-256 is not a 64-hex digest: {digest!r}"))
    vendored = fields.get("Vendored on")
    if vendored and not DATE_RE.match(vendored):
        violations.append(
            (label, f"Vendored on is not an ISO date: {vendored!r}"))


def check_licenses(root, violations):
    baku = root / "LICENSE"
    if not baku.is_file():
        violations.append(("LICENSE", "missing repository licence"))
    else:
        text = baku.read_text(encoding="utf-8")
        if "MIT License" not in text:
            violations.append(("LICENSE", "missing the MIT title"))
        if "Copyright (c)" not in text:
            violations.append(("LICENSE", "missing the copyright notice"))
        if "Permission is hereby granted, free of charge" not in text:
            violations.append(("LICENSE", "missing the MIT grant"))
        if 'THE SOFTWARE IS PROVIDED "AS IS"' not in text:
            violations.append(("LICENSE", "missing the MIT disclaimer"))

    kernel = root / "vendor/shen-43.2/LICENSE.txt"
    if not kernel.is_file():
        violations.append(
            ("vendor/shen-43.2/LICENSE.txt", "missing the kernel licence"))
        return
    text = kernel.read_text(encoding="utf-8")
    required = [
        "Copyright (c) 2010-2022, Mark Tarver",
        "All rights reserved.",
        "Redistribution and use in source and binary forms",
        "1. Redistributions of source code",
        "2. Redistributions in binary form",
        "3. The name of Mark Tarver",
        "THIS SOFTWARE IS PROVIDED BY Mark Tarver",
    ]
    for phrase in required:
        if phrase not in text:
            violations.append(
                ("vendor/shen-43.2/LICENSE.txt",
                 f"missing BSD 3-Clause text {phrase!r}"))


def check_readme(root, violations):
    readme = root / "README.md"
    if not readme.is_file():
        violations.append(("README.md", "missing the project README"))
        return
    text = readme.read_text(encoding="utf-8")
    required = [
        ("licensing section", "Licensing and kernel provenance"),
        ("MIT statement", "MIT"),
        ("BSD 3-Clause statement", "BSD 3-Clause"),
        ("Baku licence reference", "LICENSE"),
        ("kernel licence reference", "vendor/shen-43.2/LICENSE.txt"),
        ("kernel provenance reference", "vendor/shen-43.2/README.md"),
        ("test-suite provenance reference", "vendor/shen-43.2/TESTS.md"),
    ]
    for label, phrase in required:
        if phrase not in text:
            violations.append(("README.md", f"missing {label} ({phrase!r})"))


def check_vendor_readmes(root, violations):
    kernel = root / "vendor/shen-43.2/README.md"
    if not kernel.is_file():
        violations.append(("vendor/shen-43.2/README.md", "missing provenance"))
    else:
        text = kernel.read_text(encoding="utf-8")
        for phrase in ("BSD 3-Clause", "LICENSE.txt", "MIT", ASSET_NAME):
            if phrase not in text:
                violations.append(
                    ("vendor/shen-43.2/README.md",
                     f"missing licence/provenance reference {phrase!r}"))

    suite = root / "vendor/shen-43.2/TESTS.md"
    if not suite.is_file():
        violations.append(("vendor/shen-43.2/TESTS.md", "missing provenance"))
    else:
        text = suite.read_text(encoding="utf-8")
        for phrase in ("BSD 3-Clause", "LICENSE.txt", ASSET_NAME):
            if phrase not in text:
                violations.append(
                    ("vendor/shen-43.2/TESTS.md",
                     f"missing licence reference {phrase!r}"))


def check_release_asset(root, violations):
    asset = root / "vendor/shen-43.2" / ASSET_NAME
    label = f"vendor/shen-43.2/{ASSET_NAME}"
    if not asset.is_file():
        violations.append((label, "missing vendored release asset"))
        return
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    if digest != PIN["Asset SHA-256"]:
        violations.append(
            (label,
             f"asset SHA-256 is {digest!r}, expected the pinned "
             f"{PIN['Asset SHA-256']!r}"))


def check_trees(root, violations):
    klambda = root / "vendor/shen-43.2/klambda"
    if not klambda.is_dir():
        violations.append(
            ("vendor/shen-43.2/klambda", "missing vendored kernel tree"))
    else:
        count = len(list(klambda.glob("*.kl")))
        if count != 23:
            violations.append(
                ("vendor/shen-43.2/klambda",
                 f"expected 23 KLambda files, found {count}"))
    tests = root / "vendor/shen-43.2/tests"
    if not tests.is_dir():
        violations.append(
            ("vendor/shen-43.2/tests", "missing vendored test suite"))


def audit(root, verbose=False):
    violations = []
    vendor = root / "vendor/shen-43.2"

    kernel_fields = parse_metadata(vendor / "README.md", violations)
    suite_fields = parse_metadata(vendor / "TESTS.md", violations)

    for key in SHARED_KEYS:
        if key in kernel_fields and key in suite_fields:
            if kernel_fields[key] != suite_fields[key]:
                violations.append(
                    ("vendor/shen-43.2",
                     f"{key} differs between README.md and TESTS.md: "
                     f"{kernel_fields[key]!r} vs {suite_fields[key]!r}"))

    check_pin(kernel_fields, vendor / "README.md", violations)
    check_pin(suite_fields, vendor / "TESTS.md", violations)

    kernel_digest = kernel_fields.get("Tree SHA-256")
    suite_digest = suite_fields.get("Tree SHA-256")
    if kernel_digest and suite_digest and kernel_digest == suite_digest:
        violations.append(
            ("vendor/shen-43.2",
             "the KLambda and test-suite tree digests are identical"))

    check_licenses(root, violations)
    check_readme(root, violations)
    check_vendor_readmes(root, violations)
    check_release_asset(root, violations)
    check_trees(root, violations)

    print("Licensing and kernel provenance audit")
    print(f"  root: {root}")
    print("  Baku licence: MIT")
    print("  kernel licence: BSD 3-Clause (Mark Tarver)")
    print(f"  pinned release: {PIN['Release']} ({PIN['Tag']})")
    print(f"  pinned commit: {PIN['Commit']}")
    print(f"  pinned asset SHA-256: {PIN['Asset SHA-256']}")
    print(f"  vendored release asset: vendor/shen-43.2/{ASSET_NAME}")
    print(f"  KLambda tree digest: {kernel_digest}")
    print(f"  test-suite tree digest: {suite_digest}")
    if verbose:
        print("  provenance files: vendor/shen-43.2/README.md, TESTS.md")

    if violations:
        print("PROVENANCE-VIOLATIONS:")
        for label, reason in sorted(violations):
            print(f"  {label}: {reason}")

    ok = not violations
    print("PROVENANCE-AUDIT " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="repository root containing LICENSE and vendor/")
    parser.add_argument("--verbose", action="store_true",
                        help="extra provenance detail")
    args = parser.parse_args()
    return audit(Path(args.root).resolve(), args.verbose)


if __name__ == "__main__":
    sys.exit(main())
