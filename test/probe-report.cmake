# Checks the startup probe report for one Baku target.
#
# A passing test must exit zero and contain one PRESENT line for every required
# wordset, Facility TIME&DATE, and the MARKER/DOES> result.  This is stronger
# than the generic marker runner: an absent required wordset aborts the probe,
# so it cannot be hidden behind BAKU-TEST-DONE.
#
#   cmake -DFORTH=<forth> [-DFORTH_FLAGS=<flags>] -DTEST_FILE=<file>
#         -DTARGET=<name> -DWORKING_DIRECTORY=<dir> -P probe-report.cmake

foreach(required FORTH TEST_FILE TARGET WORKING_DIRECTORY)
	if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
		message(FATAL_ERROR "probe-report.cmake: missing -D${required}=...")
	endif()
endforeach()

if(DEFINED FORTH_FLAGS AND NOT "${FORTH_FLAGS}" STREQUAL "")
	separate_arguments(forth_args UNIX_COMMAND "${FORTH_FLAGS}")
else()
	set(forth_args "")
endif()

execute_process(
	COMMAND "${FORTH}" ${forth_args} "${TEST_FILE}"
	WORKING_DIRECTORY "${WORKING_DIRECTORY}"
	RESULT_VARIABLE result
	OUTPUT_VARIABLE output
	ERROR_VARIABLE errors)

set(transcript "${output}${errors}")

if(NOT "${result}" STREQUAL "0")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} PROBE FAIL: exit status ${result}\n${transcript}")
endif()

foreach(wordset
		"FACILITY"
		"MEMORY-ALLOCATION"
		"FLOATING"
		"FILE"
		"EXCEPTION"
		"DOUBLE-NUMBER")
	if(NOT transcript MATCHES "BAKU-PROBE ${wordset}[ ]+PRESENT")
		message(FATAL_ERROR
			"BAKU-TARGET ${TARGET} PROBE FAIL: ${wordset} not reported PRESENT\n${transcript}")
	endif()
endforeach()

if(NOT transcript MATCHES "BAKU-PROBE FACILITY/TIME&DATE[ ]+PRESENT")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} PROBE FAIL: FACILITY/TIME&DATE not reported PRESENT\n${transcript}")
endif()

if(NOT transcript MATCHES "BAKU-PROBE MARKER/DOES>[ ]+PRESENT")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} PROBE FAIL: MARKER/DOES> not reported PRESENT\n${transcript}")
endif()

if(transcript MATCHES "BAKU-PROBE FAIL:")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} PROBE FAIL: required wordset(s) absent\n${transcript}")
endif()

if(NOT transcript MATCHES "BAKU-TEST-DONE")
	message(FATAL_ERROR
		"BAKU-TARGET ${TARGET} PROBE FAIL: missing BAKU-TEST-DONE marker\n${transcript}")
endif()

message(STATUS "BAKU-TARGET ${TARGET} PROBE REPORT PASS")
