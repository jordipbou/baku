#!/bin/sh
# Runs every Baku test on Sloth C and gforth through CTest.
# It builds the Sloth executable pinned in CMakeLists.txt, runs each target
# separately and reports, per required target, whether it ran and passed.
#
# Both Forths are required acceptance targets (see .ralph/specs/tooling.md);
# a missing target is a hard failure, never a silent skip.

set -u

# The Shen kernel conformance suite is long (the GC interpreter runs the whole
# 43.2 test tree), so it is opt-in.  The default run excludes every test labelled
# `long`; `--kernel-suite` runs only that label.
mode=${1:-}
case "$mode" in
	"" ) ;;
	--kernel-suite ) ;;
	* )
		echo "usage: $0 [--kernel-suite]" >&2
		exit 2
		;;
esac

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

# The kernel suite is gforth-only and does not need the Sloth executable, so
# skip the build and the fast gates in this mode.
if [ "$mode" = "--kernel-suite" ]; then
	if [ "$fail" -ne 0 ]; then
		echo "BAKU-KERNEL-SUITE FAIL" >&2
		exit 1
	fi
	if ctest --test-dir build -C Debug -L long --output-on-failure; then
		echo "BAKU-KERNEL-SUITE PASS"
	else
		echo "BAKU-KERNEL-SUITE FAIL" >&2
		exit 1
	fi
	exit 0
fi

if [ "$fail" -eq 0 ]; then
	cmake --build build --config Debug --target sloth || fail=1
fi

# Host-side checks: vendored kernel digest and its deliberate-failure self-test.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_kernel_digest' \
		--output-on-failure; then
		echo "BAKU-KERNEL-DIGEST PASS"
	else
		echo "BAKU-KERNEL-DIGEST FAIL" >&2
		fail=1
	fi
fi

# Host-side check of the vendored Shen kernel test suite and its self-test.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_tests_digest' \
		--output-on-failure; then
		echo "BAKU-TESTS-DIGEST PASS"
	else
		echo "BAKU-TESTS-DIGEST FAIL" >&2
		fail=1
	fi
fi

# Host-side ANS Forth 2012 audit and its deliberate-failure self-test.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_ans_audit' \
		--output-on-failure; then
		echo "BAKU-ANS-AUDIT PASS"
	else
		echo "BAKU-ANS-AUDIT FAIL" >&2
		fail=1
	fi
fi

# Host-side vendored-kernel immutability scan and its deliberate-failure
# self-test.  The tree digest checks bytes at rest; this scan checks that no
# shipped Forth can write or replace them.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_vendor_audit' \
		--output-on-failure; then
		echo "BAKU-VENDOR-AUDIT PASS"
	else
		echo "BAKU-VENDOR-AUDIT FAIL" >&2
		fail=1
	fi
fi

# Host-side licensing and kernel-provenance audit and its deliberate-failure
# self-test: both licence texts, the pinned release metadata and the README
# references must stay complete and consistent.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_provenance_audit' \
		--output-on-failure; then
		echo "BAKU-PROVENANCE-AUDIT PASS"
	else
		echo "BAKU-PROVENANCE-AUDIT FAIL" >&2
		fail=1
	fi
fi

# Host-side cross-region store audit and its deliberate-failure self-test.
# Every raw address store in the shipped tree must be reviewed; object payload
# stores stay in the value layer while the checked store is deferred.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_region_audit' \
		--output-on-failure; then
		echo "BAKU-REGION-AUDIT PASS"
	else
		echo "BAKU-REGION-AUDIT FAIL" >&2
		fail=1
	fi
fi

# Host-side primitive manifest and its parser/classifier self-test.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_primitive_manifest' \
		--output-on-failure; then
		echo "BAKU-PRIMITIVE-MANIFEST PASS"
	else
		echo "BAKU-PRIMITIVE-MANIFEST FAIL" >&2
		fail=1
	fi
fi

# Host-side specification-to-test traceability and its deliberate-failure
# self-test: every Ralph spec criterion names a registered test or a dated
# waiver, and the generated document is current.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_spec_traceability' \
		--output-on-failure; then
		echo "BAKU-TRACEABILITY PASS"
	else
		echo "BAKU-TRACEABILITY FAIL" >&2
		fail=1
	fi
fi

# Host-side one-line user path: a copied checkout with no build machinery boots
# the kernel through 4th/start.4th and reaches the Shen top level.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_no_build$' \
		--output-on-failure; then
		echo "BAKU-NO-BUILD PASS"
	else
		echo "BAKU-NO-BUILD FAIL" >&2
		fail=1
	fi
fi

# Cross-target differential: the same fixed program must emit identical marked
# lines on Sloth and gforth.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_differential_targets$' \
		--output-on-failure; then
		echo "BAKU-DIFFERENTIAL PASS"
	else
		echo "BAKU-DIFFERENTIAL FAIL" >&2
		fail=1
	fi
fi

# Cross-target conformance: the reusable portability fixture must produce the
# same stdout through BAKU-TEST-DONE on Sloth and gforth.
if [ "$fail" -eq 0 ]; then
	if ctest --test-dir build -C Debug -R '^baku_conformance_targets$' \
		--output-on-failure; then
		echo "BAKU-CONFORMANCE PASS"
	else
		echo "BAKU-CONFORMANCE FAIL" >&2
		fail=1
	fi
fi

for target in $targets; do
	if [ "$fail" -ne 0 ]; then
		echo "BAKU-TARGET $target NOT RUN"
		continue
	fi

	count=$(ctest --test-dir build -C Debug -LE long -N -R "^baku_.*_${target}\$" |
		sed -n 's/^Total Tests: //p')
	if [ -z "$count" ] || [ "$count" -eq 0 ]; then
		echo "BAKU-TARGET $target NOT RUN: no registered tests" >&2
		fail=1
		continue
	fi

	if ctest --test-dir build -C Debug -LE long -R "^baku_.*_${target}\$" \
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
