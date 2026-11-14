# Compares a fixed fixture on two Forth targets.
#
# The differential fixture prints one "BAKU-DIFF ..." line per result; only
# those lines are compared, so launcher banners, the startup probe, gforth's
# redefinition warnings and timing chatter are normalised away by construction.
# The conformance fixture has no per-result marker, so prefix mode compares the
# fixture's whole stdout through BAKU-TEST-DONE instead.  In both modes each run
# must exit zero and reach BAKU-TEST-DONE, so an aborted or incomplete program
# can never look like an empty match.
#
# Invoked by CMakeLists.txt as:
#
#   cmake -DSLOTH=<forth> -DGFORTH=<forth> [-DSLOTH_FLAGS=...]
#         [-DGFORTH_FLAGS=...] -DTEST_FILE=<file> -DWORKING_DIRECTORY=<dir>
#         -DBINARY_DIR=<dir> [-DMODE=lines|prefix] [-DMARKER=<regex>]
#         [-DLABEL=<marker>] -P differential-targets.cmake
#
# MODE defaults to lines, MARKER to the BAKU-DIFF line and LABEL to
# DIFFERENTIAL, which preserves the original differential invocation.

foreach(required SLOTH GFORTH TEST_FILE WORKING_DIRECTORY BINARY_DIR)
	if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
		message(FATAL_ERROR
			"differential-targets.cmake: missing -D${required}=...")
	endif()
endforeach()

if(NOT DEFINED MODE OR "${MODE}" STREQUAL "")
	set(MODE lines)
endif()
if(NOT DEFINED MARKER OR "${MARKER}" STREQUAL "")
	set(MARKER "BAKU-DIFF [^\n]*")
endif()
if(NOT DEFINED LABEL OR "${LABEL}" STREQUAL "")
	set(LABEL DIFFERENTIAL)
endif()
string(TOLOWER "${LABEL}" label_lower)

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
			"BAKU-${LABEL} FAIL: ${label} exited ${result}\n${transcript}")
	endif()
	if(NOT transcript MATCHES "BAKU-TEST-DONE")
		message(FATAL_ERROR
			"BAKU-${LABEL} FAIL: ${label} missing BAKU-TEST-DONE\n${transcript}")
	endif()

	# Normalise CRLF before extracting the compared text.
	string(REGEX REPLACE "\r" "" transcript "${transcript}")
	if(MODE STREQUAL "prefix")
		string(FIND "${transcript}" "BAKU-TEST-DONE" done_at)
		string(LENGTH "BAKU-TEST-DONE" done_length)
		math(EXPR done_end "${done_at} + ${done_length}")
		string(SUBSTRING "${transcript}" 0 ${done_end} block)
		set(count 1)
	else()
		string(REGEX MATCHALL "${MARKER}" lines "${transcript}")
		list(LENGTH lines count)
		if(count LESS 1)
			message(FATAL_ERROR
				"BAKU-${LABEL} FAIL: ${label} emitted no marked lines\n${transcript}")
		endif()
		string(REPLACE ";" "\n" block "${lines}")
	endif()

	set(${out_var} "${block}" PARENT_SCOPE)
	set(${out_var}_count "${count}" PARENT_SCOPE)
endfunction()

run_fixture("${SLOTH}" "${SLOTH_FLAGS}" Sloth sloth_block)
run_fixture("${GFORTH}" "${GFORTH_FLAGS}" gforth gforth_block)

if(NOT "${sloth_block}" STREQUAL "${gforth_block}")
	file(WRITE "${BINARY_DIR}/${label_lower}-sloth.txt" "${sloth_block}\n")
	file(WRITE "${BINARY_DIR}/${label_lower}-gforth.txt" "${gforth_block}\n")
	message(FATAL_ERROR
		"BAKU-${LABEL} FAIL: compared output differs between Sloth and gforth; "
		"see ${BINARY_DIR}/${label_lower}-sloth.txt and "
		"${BINARY_DIR}/${label_lower}-gforth.txt")
endif()

if(MODE STREQUAL "prefix")
	message(STATUS
		"BAKU-${LABEL} PASS: output through BAKU-TEST-DONE identical on Sloth and gforth")
else()
	message(STATUS
		"BAKU-${LABEL} PASS: ${sloth_block_count} marked lines identical on Sloth and gforth")
endif()
