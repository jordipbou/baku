# Shen 43.2 — vendored kernel test suite

This directory's `tests/` subtree is the unmodified test suite from the official
Shen OS Kernel release 43.2.

- Project: Shen
- Upstream: https://github.com/Shen-Language/shen-sources
- Release: Shen OS Kernel 43.2
- Tag: `shen-43.2`
- Commit: `e6947f507ebc03f7ade5d2a8d971bd05d84a5bae`
- Asset: https://github.com/Shen-Language/shen-sources/releases/download/shen-43.2/ShenOSKernel-43.2.tar.gz
- Asset SHA-256: `23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32`
- Tree SHA-256: `c6cfd16a7f034e877aefbe7129f632149fdd5155188adf5386df2b6d18d6dd98`
- Vendored on: 2026-11-12

The `tests/` files are copied verbatim from `ShenOSKernel-43.2/tests/`; do not edit
them. The suite is Shen source, not KLambda: it is meant to be run from a booted
Shen top level, starting with `(load "runme.shen")` in `tests/`. The canonical
kernel suite is `kerneltests.shen`; `runme.shen` loads `harness.shen` and then
`kerneltests.shen`. `tests/extensions/` holds the extension-specific suites and
`tests/extensions/runme.shen` their entry point.

The suite uses `y-or-n?` when a check fails, so a headless run must supply stdin
or treat the prompt as a failure boundary.

## Tree digest

The tree digest covers the extracted `tests/` bytes, so the vendored tree can be
verified without re-downloading the release asset.

Method: take every file under `tests/`, order them by relative POSIX path
bytewise, and build a manifest with one line per file:

```
<lowercase SHA-256 of file bytes>  <relative path>\n
```

The tree digest is the SHA-256 of the manifest bytes, in lowercase hex. The pinned
tree contains 74 files (72 `.shen` plus `README` and `n queens.axioms`).

Recompute and compare with the recorded value:

```sh
cmake -DTREE=vendor/shen-43.2/tests \
      -DEXPECTED_FILE=vendor/shen-43.2/TESTS.md \
      -DLABEL=BAKU-TESTS-DIGEST \
      -P tools/verify-kernel-digest.cmake
```

`ctest --test-dir build -R '^baku_tests_digest'` runs the same check plus a
self-test that appends a byte to a temporary copy of a `.shen` file and requires
the check to fail.

## License

The Shen kernel and its test suite are Copyright (c) 2010-2022, Mark Tarver, and
are distributed under the BSD 3-Clause license. See `LICENSE.txt`.
