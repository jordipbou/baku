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
# The pinned corpus contains one form with about 45k cons cells, and Sloth's
# default stack and dictionary are too small for the reader tests.  The loader
# test raises the non-GC heap request to 16 MiB.  The native boot test requests
# 512 MiB because non-GC initialisation keeps every allocation, plus the 4 MiB
# IR scratch and the 2 MiB reader scratch.  These are test-platform limits; the
# default Baku sources reserve only 512 KiB.
set(SLOTH_DICTIONARY_SIZE 671088640 CACHE STRING
	"Sloth dictionary size for the Baku test platform" FORCE)
add_compile_definitions(SLOTH_STACK_SIZE=16384 SLOTH_RETURN_STACK_SIZE=16384)
FetchContent_Declare(
	sloth
	GIT_REPOSITORY https://github.com/jordipbou/sloth
	GIT_TAG a04bc75d5dd7b91e756b5e69de0ded0e00095738
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
# kernel, so it is gforth-only for the same reason as boot-native.
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

file(GLOB BAKU_TESTS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/*.4th)
# These tests initialise the whole kernel and/or need GC stack roots; see the
# exclusions below.  kernel-suite boots under the collector, which Sloth cannot
# activate, so it is a gforth-only long test.
set(BAKU_NATIVE_BOOT_TESTS boot-native kernel repl kernel-suite)
foreach(test_file IN LISTS BAKU_TESTS)
	get_filename_component(test_name ${test_file} NAME_WE)

	# The native boot acceptance tests (boot-native, kernel, repl) initialise
	# the whole kernel.  Sloth's Debug native execution takes about 10 minutes
	# for SHEN.INITIALISE alone and several times that for STLIB.INITIALISE, so
	# those tests run on gforth.  The full corpus native install still runs on
	# Sloth in test/native.4th's code path and in the manual install experiment.
	# kernel-suite needs the Cheney collector, whose stack roots only gforth
	# exposes.  The standard-input test reads the CTest input file and is
	# registered below.
	set(test_targets ${BAKU_REQUIRED_TARGETS})
	if(test_name IN_LIST BAKU_NATIVE_BOOT_TESTS)
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
			# The native boot test reserves a 512 MiB non-GC heap, the 4 MiB IR
			# scratch and the 2 MiB reader scratch; every other test fits 64M.
			if(test_name IN_LIST BAKU_NATIVE_BOOT_TESTS)
				set(forth_flags "-m 768M -d 16M -r 16M")
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
