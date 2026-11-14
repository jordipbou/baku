# Shen 43.2 — vendored KLambda kernel

This directory contains the unmodified KLambda sources from the official
Shen OS Kernel release 43.2.

- Project: Shen
- Upstream: https://github.com/Shen-Language/shen-sources
- Release: Shen OS Kernel 43.2
- Tag: `shen-43.2`
- Commit: `e6947f507ebc03f7ade5d2a8d971bd05d84a5bae`
- Asset: https://github.com/Shen-Language/shen-sources/releases/download/shen-43.2/ShenOSKernel-43.2.tar.gz
- Asset SHA-256: `23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32`
- Tree SHA-256: `b6a3610b5a7438cf6bcc6bdbbfe9eaa016420d03976652062d93cdc81ea9e80c`
- Vendored on: 2026-11-04

The `klambda/` files are the 23 `.kl` files shipped in `ShenOSKernel-43.2/klambda/`.
They are copied verbatim; do not edit them. `LICENSE.txt` is the upstream license.

## Release asset

`ShenOSKernel-43.2.tar.gz` beside this file is the unmodified official release
tarball. It is vendored so the checksum check runs offline: `test/release-asset.cmake`
recomputes its SHA-256, extracts it, and re-runs the tree-digest verifier on the
extracted `klambda/` and `tests/` trees. The asset hash and the extracted tree
digests therefore prove the vendored bytes from the repository alone.

## Tree digest

The tree digest covers the extracted `klambda/` bytes, so the vendored tree can be
verified without re-downloading the release asset.

Method: take every file under `klambda/`, order them by relative POSIX path
bytewise, and build a manifest with one line per file:

```
<lowercase SHA-256 of file bytes>  <relative path>\n
```

The tree digest is the SHA-256 of the manifest bytes, in lowercase hex. The pinned
tree contains only the 23 `.kl` files, so the manifest covers exactly those.

Recompute and compare with the recorded value:

```sh
cmake -DTREE=vendor/shen-43.2/klambda \
      -DEXPECTED_FILE=vendor/shen-43.2/README.md \
      -P tools/verify-kernel-digest.cmake
```

`ctest --test-dir build -R '^baku_kernel_digest'` runs the same check plus a
self-test that appends a byte to a temporary copy of a `.kl` file and requires the
check to fail.

## Kernel test suite

The official release's `tests/` tree is vendored verbatim next to `klambda/`
under `tests/`. Its provenance and tree digest are recorded in `TESTS.md`.

## License

The Shen kernel is Copyright (c) 2010-2022, Mark Tarver, and is distributed under
the BSD 3-Clause license. See `LICENSE.txt`.

Baku itself is MIT-licensed; see the repository `LICENSE`.
