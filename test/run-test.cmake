# Runs one Baku test file on one Forth target.
#
# A test passes only when the Forth process exits zero AND its output contains
# the BAKU-TEST-DONE marker. CTest's PASS_REGULAR_EXPRESSION cannot express
# both conditions (it ignores the exit status), so this script is the single
# pass/fail decision. Invoked by CMakeLists.txt as:
#
#   cmake -DFORTH=<forth> [-DFORTH_FLAGS=<flags>] -DTEST_FILE=<file>
#         -DTARGET=<name> -DWORKING_DIRECTORY=<dir> -P run-test.cmake

foreach(required FORTH TEST_FILE TARGET WORKING_DIRECTORY)
	if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
		message(FATAL_ERROR "run-test.cmake: missing -D${required}=...")
	endif()
endforeach()

if(DEFINED FORTH_FLAGS AND NOT "${FORTH_FLAGS}" STREQUAL "")
	separate_arguments(forth_args UNIX_COMMAND "${FORTH_FLAGS}")
else()
	set(forth_args "")
endif()

# INPUT_FILE replaces the standard input of the Forth process.  It exists for
# the standard-input tests: without it a test that reads stdin would inherit
# the CTest stdin, which is not defined by this runner.
if(DEFINED INPUT_FILE AND NOT "${INPUT_FILE}" STREQUAL "")
	execute_process(
		COMMAND "${FORTH}" ${forth_args} "${TEST_FILE}"
		WORKING_DIRECTORY "${WORKING_DIRECTORY}"
		INPUT_FILE "${INPUT_FILE}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE errors)
else()
	execute_process(
		COMMAND "${FORTH}" ${forth_args} "${TEST_FILE}"
		WORKING_DIRECTORY "${WORKING_DIRECTORY}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE errors)
endif()

set(transcript "${output}${errors}")

if(NOT "${result}" STREQUAL "0")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} FAIL: exit status ${result}\n${transcript}")
endif()

if(NOT transcript MATCHES "BAKU-TEST-DONE")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} FAIL: missing BAKU-TEST-DONE marker\n${transcript}")
endif()

message(STATUS "BAKU-TARGET ${TARGET} PASS: ${TEST_FILE}")
