#!/bin/sh
# Runs every Baku test on Sloth C and gforth through CTest.
# It builds the Sloth executable pinned in CMakeLists.txt, runs each target
# separately and reports, per required target, whether it ran and passed.
#
# Both Forths are required acceptance targets (see .ralph/specs/tooling.md);
# a missing target is a hard failure, never a silent skip.

set -u

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

fail=0

if ! command -v gforth >/dev/null 2>&1; then
	echo "BAKU: gforth missing: gforth is a required Baku acceptance target" >&2
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	echo "Some tests failed: required target not run."
	exit 1
fi

cmake -S . -B build -G "Ninja Multi-Config" || fail=1

targets_file=build/baku-targets.txt
if [ ! -f "$targets_file" ]; then
	echo "BAKU: no target list at $targets_file; configuration failed" >&2
	fail=1
	targets=""
else
	targets=$(cat "$targets_file")
fi

if [ "$fail" -eq 0 ]; then
	cmake --build build --config Debug --target sloth || fail=1
fi

for target in $targets; do
	if [ "$fail" -ne 0 ]; then
		echo "BAKU-TARGET $target NOT RUN"
		continue
	fi

	count=$(ctest --test-dir build -C Debug -N -R "^baku_.*_${target}\$" |
		sed -n 's/^Total Tests: //p')
	if [ -z "$count" ] || [ "$count" -eq 0 ]; then
		echo "BAKU-TARGET $target NOT RUN: no registered tests" >&2
		fail=1
		continue
	fi

	if ctest --test-dir build -C Debug -R "^baku_.*_${target}\$" \
		--output-on-failure; then
		echo "BAKU-TARGET $target PASS ($count tests)"
	else
		echo "BAKU-TARGET $target FAIL" >&2
		fail=1
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "Some tests failed."
	exit 1
fi

echo "All tests passed."
