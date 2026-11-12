# Compares the fixed cross-target differential fixture on two Forth targets.
#
# The fixture prints one "BAKU-DIFF ..." line per result.  Only those lines are
# compared, so launcher banners, the startup probe, gforth's redefinition
# warnings and timing chatter are normalised away by construction.  Both runs
# must still exit zero and reach BAKU-TEST-DONE, so an aborted or incomplete
# program can never look like an empty match.
#
# Invoked by CMakeLists.txt as:
#
#   cmake -DSLOTH=<forth> -DGFORTH=<forth> [-DSLOTH_FLAGS=...]
#         [-DGFORTH_FLAGS=...] -DTEST_FILE=<file> -DWORKING_DIRECTORY=<dir>
#         -DBINARY_DIR=<dir> -P differential-targets.cmake

foreach(required SLOTH GFORTH TEST_FILE WORKING_DIRECTORY BINARY_DIR)
	if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
		message(FATAL_ERROR
			"differential-targets.cmake: missing -D${required}=...")
	endif()
endforeach()

function(run_fixture forth flags label out_var)
	if(DEFINED flags AND NOT "${flags}" STREQUAL "")
		separate_arguments(forth_args UNIX_COMMAND "${flags}")
	else()
		set(forth_args "")
	endif()

	execute_process(
		COMMAND "${forth}" ${forth_args} "${TEST_FILE}"
		WORKING_DIRECTORY "${WORKING_DIRECTORY}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE errors)
	set(transcript "${output}${errors}")

	if(NOT "${result}" STREQUAL "0")
		message(FATAL_ERROR
			"BAKU-DIFFERENTIAL FAIL: ${label} exited ${result}\n${transcript}")
	endif()
	if(NOT transcript MATCHES "BAKU-TEST-DONE")
		message(FATAL_ERROR
			"BAKU-DIFFERENTIAL FAIL: ${label} missing BAKU-TEST-DONE\n${transcript}")
	endif()

	# Normalise CRLF before extracting the marked lines.
	string(REGEX REPLACE "\r" "" transcript "${transcript}")
	string(REGEX MATCHALL "BAKU-DIFF [^\n]*" lines "${transcript}")
	list(LENGTH lines count)
	if(count LESS 1)
		message(FATAL_ERROR
			"BAKU-DIFFERENTIAL FAIL: ${label} emitted no BAKU-DIFF lines\n${transcript}")
	endif()

	string(REPLACE ";" "\n" block "${lines}")
	set(${out_var} "${block}" PARENT_SCOPE)
	set(${out_var}_count "${count}" PARENT_SCOPE)
endfunction()

run_fixture("${SLOTH}" "${SLOTH_FLAGS}" Sloth sloth_block)
run_fixture("${GFORTH}" "${GFORTH_FLAGS}" gforth gforth_block)

if(NOT "${sloth_block}" STREQUAL "${gforth_block}")
	file(WRITE "${BINARY_DIR}/differential-sloth.txt" "${sloth_block}\n")
	file(WRITE "${BINARY_DIR}/differential-gforth.txt" "${gforth_block}\n")
	message(FATAL_ERROR
		"BAKU-DIFFERENTIAL FAIL: marked output differs between Sloth and gforth; "
		"see ${BINARY_DIR}/differential-sloth.txt and "
		"${BINARY_DIR}/differential-gforth.txt")
endif()

message(STATUS
	"BAKU-DIFFERENTIAL PASS: ${sloth_block_count} marked lines identical on Sloth and gforth")
