#!/bin/sh
# Runs every Baku test on Sloth C and gforth through CTest.
# It builds the Sloth executable pinned in CMakeLists.txt and runs
# each test/*.4th on both Forths, reporting a single pass/fail.

set -u

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

fail=0

if ! command -v gforth >/dev/null 2>&1; then
	echo "gforth not found on PATH; it is required to run the tests" >&2
	fail=1
fi

cmake -S . -B build -G "Ninja Multi-Config" || fail=1
cmake --build build --config Debug --target sloth || fail=1
ctest --test-dir build -C Debug -R '^baku_' --output-on-failure || fail=1

if [ "$fail" -ne 0 ]; then
	echo "Some tests failed."
	exit 1
fi

echo "All tests passed."
