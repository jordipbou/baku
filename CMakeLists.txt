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
# default stack and dictionary are too small for the reader tests.  These are
# test-platform limits; the Baku sources themselves do not require them.
set(SLOTH_DICTIONARY_SIZE 8388608 CACHE STRING
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

file(GLOB BAKU_TESTS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/*.4th)
foreach(test_file IN LISTS BAKU_TESTS)
	get_filename_component(test_name ${test_file} NAME_WE)

	foreach(target IN LISTS BAKU_REQUIRED_TARGETS)
		if(target STREQUAL "sloth")
			set(forth_command $<TARGET_FILE:sloth>)
		elseif(target STREQUAL "gforth")
			set(forth_command ${GFORTH_EXECUTABLE})
		else()
			message(FATAL_ERROR "Unknown Baku test target '${target}'")
		endif()

		# The runner, not PASS_REGULAR_EXPRESSION, decides the outcome: a
		# test passes only when it exits zero and prints BAKU-TEST-DONE.
		add_test(NAME baku_${test_name}_${target}
			COMMAND ${CMAKE_COMMAND}
				-DFORTH=${forth_command}
				-DTEST_FILE=${test_file}
				-DTARGET=${target}
				-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
				-P ${BAKU_RUNNER})

		# The startup probe report is checked line by line as well: every
		# required wordset must print PRESENT, never only the test marker.
		if(test_name STREQUAL "probe")
			add_test(NAME baku_probe_report_${target}
				COMMAND ${CMAKE_COMMAND}
					-DFORTH=${forth_command}
					-DTEST_FILE=${test_file}
					-DTARGET=${target}
					-DWORKING_DIRECTORY=${BAKU_WORKING_DIRECTORY}
					-P ${CMAKE_CURRENT_SOURCE_DIR}/test/probe-report.cmake)
		endif()
	endforeach()
endforeach()
