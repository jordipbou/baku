cmake_minimum_required(VERSION 3.17)
project(baku LANGUAGES C)

enable_testing()

# Both test platforms are required acceptance targets; see
# .ralph/specs/tooling.md. A missing target is a hard configure failure so the
# CTest path can never look green with a target that was never run.
find_program(GFORTH_EXECUTABLE gforth)
if(NOT GFORTH_EXECUTABLE)
	message(FATAL_ERROR
		"gforth missing: gforth is a required Baku acceptance target. "
		"Install gforth or pass -DGFORTH_EXECUTABLE=/path/to/gforth.")
endif()

include(FetchContent)
# The pinned corpus contains one form with about 45k cons cells that the reader
# holds in its 2 MiB scratch block, so Sloth's default dictionary is too small.
# The shipped Forth, the 2 MiB symbol area and the 2 MiB reader scratch fit in
# 64 MiB with headroom; the semispaces come from the host heap.  These are
# test-platform limits, not build defaults.
set(SLOTH_DICTIONARY_SIZE 67108864 CACHE STRING
	"Sloth dictionary size for the Baku test platform" FORCE)
add_compile_definitions(SLOTH_STACK_SIZE=16384 SLOTH_RETURN_STACK_SIZE=16384)
FetchContent_Declare(
	sloth
	GIT_REPOSITORY https://github.com/jordipbou/sloth
	GIT_TAG affe6988cb0269079ddcf4526c67a2f1ab227c15
	SOURCE_SUBDIR platforms/c
	EXCLUDE_FROM_ALL
)
FetchContent_MakeAvailable(sloth)

set(BAKU_REQUIRED_TARGETS sloth gforth)
message(STATUS "Baku test targets: ${BAKU_REQUIRED_TARGETS}")

# Publish the target list for run-tests.sh so it stays in one place.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/baku-targets.txt "")
foreach(target IN LISTS BAKU_REQUIRED_TARGETS)
	file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/baku-targets.txt "${target}\n")
endforeach()

set(BAKU_WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
set(BAKU_RUNNER ${CMAKE_CURRENT_SOURCE_DIR}/test/run-test.cmake)

# The ANS Forth 2012 static audit is a host-side development check.  It scans
# only shipped Forth; tools/ and the build are not part of the runtime.
find_program(PYTHON3_EXECUTABLE python3)
if(NOT PYTHON3_EXECUTABLE)
	message(FATAL_ERROR
		"python3 missing: python3 is required for the ANS Forth static audit.")
endif()
add_test(NAME baku_ans_audit
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/ans-audit.py
		--root ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME baku_ans_audit_selftest
	COMMAND ${CMAKE_COMMAND}
		-DPYTHON3_EXECUTABLE=${PYTHON3_EXECUTABLE}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/ans-audit-selftest.cmake)

# The vendored kernel must never be rewritten by shipped Forth.  This static
# scan allows one read prefix and rejects any write or replacement in the boot
# path; the tree digest remains the byte-level check.
add_test(NAME baku_vendor_audit
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/vendor-audit.py
		--root ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME baku_vendor_audit_selftest
	COMMAND ${CMAKE_COMMAND}
		-DPYTHON3_EXECUTABLE=${PYTHON3_EXECUTABLE}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/vendor-audit-selftest.cmake)

# Cross-region stores are a compiler/runtime invariant while the checked store
# is deferred.  This static scan reviews every raw address store and fails on an
# unreviewed one or an extra store in a reviewed definition.
add_test(NAME baku_region_audit
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/region-audit.py
		--root ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME baku_region_audit_selftest
	COMMAND ${CMAKE_COMMAND}
		-DPYTHON3_EXECUTABLE=${PYTHON3_EXECUTABLE}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/region-audit-selftest.cmake)

# Licensing and kernel provenance are a requirement, not prose: the audit
# checks both licence texts, the pinned release metadata and the README
# references.  The tree digests above still verify the vendored bytes.
add_test(NAME baku_provenance_audit
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/provenance-audit.py
		--root ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME baku_provenance_audit_selftest
	COMMAND ${CMAKE_COMMAND}
		-DPYTHON3_EXECUTABLE=${PYTHON3_EXECUTABLE}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/provenance-audit-selftest.cmake)

# The project entry's Links section is part of the requirement source.  The
# audit extracts every link from the entry, requires it to resolve (or to carry
# a reviewed dated offline acceptance), and checks the generated record against
# the entry so an added, removed or reordered link cannot pass silently.  It
# performs live HTTP requests, so an offline machine must record the accepted
# links explicitly in the tool.
add_test(NAME baku_link_audit
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/link-audit.py
		--root ${CMAKE_CURRENT_SOURCE_DIR} --check)
add_test(NAME baku_link_audit_selftest
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/link-audit.py --self-test)
set_tests_properties(baku_link_audit PROPERTIES TIMEOUT 600)

# The primitive manifest is generated from the parsed kernel corpus and the
# baku-defprim registrations.  The check fails on a stale manifest, an
# unclassified applied symbol, or a registered primitive with no application.
add_test(NAME baku_primitive_manifest
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/manifest.py --check)
add_test(NAME baku_primitive_manifest_selftest
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/manifest.py --self-test)

# The one-line user path: copy a checkout without build/, CMakeLists.txt or
# run-tests.sh, load 4th/start.4th through the gforth target, and require the
# top level to answer while boot generates no .4th file.  It boots the whole
# kernel, so it runs only on gforth.
add_test(NAME baku_no_build
	COMMAND ${CMAKE_COMMAND}
		-DGFORTH_EXECUTABLE=${GFORTH_EXECUTABLE}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/no-build.cmake)

# Host-side checks: the vendored kernel bytes and a self-test that proves a
# modified .kl file is rejected.  These do not depend on a Forth target.
add_test(NAME baku_kernel_digest
	COMMAND ${CMAKE_COMMAND}
		-DTREE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/klambda
		-DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/README.md
		-P ${CMAKE_CURRENT_SOURCE_DIR}/tools/verify-kernel-digest.cmake)
add_test(NAME baku_kernel_digest_tamper
	COMMAND ${CMAKE_COMMAND}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/kernel-digest-selftest.cmake)

# The Shen kernel test suite is vendored verbatim beside the KLambda sources.
# It is Shen source for a booted top level, so these checks only verify the
# pinned bytes; running the suite is a target-level test.
add_test(NAME baku_tests_digest
	COMMAND ${CMAKE_COMMAND}
		-DTREE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/tests
		-DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/TESTS.md
		-DLABEL=BAKU-TESTS-DIGEST
		-P ${CMAKE_CURRENT_SOURCE_DIR}/tools/verify-kernel-digest.cmake)
add_test(NAME baku_tests_digest_tamper
	COMMAND ${CMAKE_COMMAND}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-DSOURCE_TREE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/tests
		-DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/vendor/shen-43.2/TESTS.md
		-DWORK_NAME=tests-digest-selftest
		-DVICTIM_GLOB=*.shen
		-DLABEL=BAKU-TESTS-DIGEST
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/kernel-digest-selftest.cmake)

# The official release tarball is vendored beside the extracted trees so the
# checksum check runs offline.  It recomputes the asset SHA-256, extracts the
# tarball and re-verifies both extracted trees with the one digest verifier.
# The self-test corrupts a copy and requires the checksum check to fail.
add_test(NAME baku_release_asset
	COMMAND ${CMAKE_COMMAND}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/release-asset.cmake)
add_test(NAME baku_release_asset_selftest
	COMMAND ${CMAKE_COMMAND}
		-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/release-asset-selftest.cmake)

file(GLOB BAKU_TESTS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/*.4th)
# These tests initialise the whole kernel and are too slow on Sloth's Debug
# build; each entry carries its own reason for the traceability audit.  Every
# glob-registered test that is not enabled for Sloth must appear here.
set(BAKU_GFORTH_ONLY_TESTS
	gc-boot      # boots and initialises the whole kernel under the collector
	kernel       # initialises the whole kernel; Debug on Sloth takes minutes
	repl         # boots the whole kernel before the REPL; Debug on Sloth takes minutes
	kernel-suite # long collector conformance run with a large semispace
)
# These tests run on both targets but need a specific gforth stack size to
# expose a host limit; the traceability audit does not exclude them from Sloth.
set(BAKU_SMALL_RETURN_STACK_TESTS
	gc-deep-stack # 12,000 live cells must not be moved through the return stack
)
foreach(test_file IN LISTS BAKU_TESTS)
	get_filename_component(test_name ${test_file} NAME_WE)

	# The boot acceptance tests (gc-boot, kernel, repl) initialise the whole
	# kernel.  Sloth's Debug execution takes about 10 minutes for
	# SHEN.INITIALISE alone and several times that for STLIB.INITIALISE, so
	# those tests run on gforth.  kernel-suite is the long collector run and is
	# excluded for the same speed reason.  The standard-input test reads the
	# CTest input file and is registered below.
	set(test_targets ${BAKU_REQUIRED_TARGETS})
	if(test_name IN_LIST BAKU_GFORTH_ONLY_TESTS)
		list(REMOVE_ITEM test_targets sloth)
	endif()
	if(test_name STREQUAL "repl-eof")
		continue()
	endif()

	foreach(target IN LISTS test_targets)
		if(target STREQUAL "sloth")
			set(forth_command $<TARGET_FILE:sloth>)
			set(forth_flags "")
		elseif(target STREQUAL "gforth")
			set(forth_command ${GFORTH_EXECUTABLE})
			# The measured default boot needs -m 64M for the shipped Forth plus
			# the 2 MiB symbol area, and larger data/return stacks for the
			# deepest reader form and STLIB.INITIALISE.  The kernel suite
			# overrides the symbol area to 64 MiB, so it needs a larger
			# dictionary; every other test fits 64M.
			if(test_name STREQUAL "kernel-suite")
				set(forth_flags "-m 128M -d 16M -r 16M")
			elseif(test_name IN_LIST BAKU_GFORTH_ONLY_TESTS)
				set(forth_flags "-m 64M -d 16M -r 16M")
			elseif(test_name IN_LIST BAKU_SMALL_RETURN_STACK_TESTS)
				set(forth_flags "-m 64M -d 16M -r 64k")
			else()
				set(forth_flags "-m 64M")
			endif()
		else()
			message(FATAL_ERROR "Unknown Baku test target '${target}'")
		endif()

		# The runner, not PASS_REGULAR_EXPRESSION, decides the outcome: a
		# test passes only when it exits zero and prints BAKU-TEST-DONE.
		add_test(NAME baku_${test_name}_${target}
			COMMAND ${CMAKE_COMMAND}
				-DFORTH=${forth_command}
				-DFORTH_FLAGS=${forth_flags}
				-DTEST_FILE=${test_file}
				-DTARGET=${target}
				-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
				-P ${BAKU_RUNNER})

		# The Shen kernel suite is a conformance measurement, not a fast
		# regression test: type checking under the GC interpreter takes a long
		# time.  Label it long so the default target run excludes it and give it
		# a generous timeout; run-tests.sh --kernel-suite runs it explicitly.
		if(test_name STREQUAL "kernel-suite")
			set_tests_properties(baku_${test_name}_${target}
				PROPERTIES LABELS long TIMEOUT 14400)
		endif()

		# The startup probe report is checked line by line as well: every
		# required wordset must print PRESENT, never only the test marker.
		if(test_name STREQUAL "probe")
			add_test(NAME baku_probe_report_${target}
				COMMAND ${CMAKE_COMMAND}
					-DFORTH=${forth_command}
					-DFORTH_FLAGS=${forth_flags}
					-DTEST_FILE=${test_file}
					-DTARGET=${target}
					-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
					-P ${CMAKE_CURRENT_SOURCE_DIR}/test/probe-report.cmake)
		endif()
	endforeach()
endforeach()

# Cross-target differential: the same fixture must emit the same marked lines on
# both targets.  The fixture is registered as a normal target test by the glob
# above; this host-side check compares the two transcripts.  Only BAKU-DIFF lines
# are compared, so launcher banners and target-specific warnings are normalised
# away without weakening the exit-status and marker requirements.
add_test(NAME baku_differential_targets
	COMMAND ${CMAKE_COMMAND}
		-DSLOTH=$<TARGET_FILE:sloth>
		-DGFORTH=${GFORTH_EXECUTABLE}
		"-DGFORTH_FLAGS=-m 64M"
		-DTEST_FILE=${CMAKE_CURRENT_SOURCE_DIR}/test/differential.4th
		-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/differential-targets.cmake)

# Cross-target conformance: the portability fixture must produce the same stdout
# through BAKU-TEST-DONE on both targets.  It reuses the differential comparator
# in prefix mode, so launcher chatter after the marker is normalised away and
# both runs must still exit zero and reach the marker.
add_test(NAME baku_conformance_targets
	COMMAND ${CMAKE_COMMAND}
		-DSLOTH=$<TARGET_FILE:sloth>
		-DGFORTH=${GFORTH_EXECUTABLE}
		"-DGFORTH_FLAGS=-m 64M"
		-DTEST_FILE=${CMAKE_CURRENT_SOURCE_DIR}/test/conformance.4th
		-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
		-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
		-DMODE=prefix
		-DLABEL=CONFORMANCE
		-P ${CMAKE_CURRENT_SOURCE_DIR}/test/differential-targets.cmake)

# The standard-input end test is the only test that needs an empty stdin, so it
# is registered with the runner's INPUT_FILE instead of the glob above.  gforth
# is the target whose KEY reports end of input (see the test file).
add_test(NAME baku_repl-eof_gforth
	COMMAND ${CMAKE_COMMAND}
		-DFORTH=${GFORTH_EXECUTABLE}
		-DFORTH_FLAGS="-m 64M"
		-DTEST_FILE=${CMAKE_CURRENT_SOURCE_DIR}/test/repl-eof.4th
		-DTARGET=gforth
		-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
		-DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/test/empty.stdin
		-P ${BAKU_RUNNER})

# Specification-to-test traceability is a requirement of the test strategy, not
# prose: the audit maps every Ralph spec criterion to a registered test or a
# dated waiver.  The specs live beside the checkout in the Ralph workspace, so
# the directory is a configure-time input.  The registered-test list is written
# below, after every add_test, so the audit resolves claims against the real
# CTest set instead of a copy of the registration rules.
set(BAKU_SPECS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.ralph/specs" CACHE PATH
	"Ralph specification directory for traceability")
set(BAKU_AGENTS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../.ralph/AGENTS.md" CACHE FILEPATH
	"Ralph AGENTS.md scanned for status prose")
set(BAKU_REGISTERED_TESTS_FILE ${CMAKE_CURRENT_BINARY_DIR}/baku-tests.txt)

add_test(NAME baku_spec_traceability
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/traceability-audit.py
		--check
		--root ${CMAKE_CURRENT_SOURCE_DIR}
		--specs ${BAKU_SPECS_DIR}
		--tests-file ${BAKU_REGISTERED_TESTS_FILE}
		--agents ${BAKU_AGENTS_FILE})
add_test(NAME baku_spec_traceability_selftest
	COMMAND ${PYTHON3_EXECUTABLE}
		${CMAKE_CURRENT_SOURCE_DIR}/tools/traceability-audit.py --self-test)

get_property(BAKU_DIRECTORY_TESTS DIRECTORY PROPERTY TESTS)
list(FILTER BAKU_DIRECTORY_TESTS INCLUDE REGEX "^baku_")
list(SORT BAKU_DIRECTORY_TESTS)
file(WRITE ${BAKU_REGISTERED_TESTS_FILE} "")
foreach(test_name IN LISTS BAKU_DIRECTORY_TESTS)
	file(APPEND ${BAKU_REGISTERED_TESTS_FILE} "${test_name}\n")
endforeach()
