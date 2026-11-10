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
FetchContent_Declare(
	sloth
	GIT_REPOSITORY https://github.com/jordipbou/sloth
	GIT_TAG 12f7189d65e80d3617ff15967a831c01cb254ef2
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

set(BAKU_WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test)
set(BAKU_RUNNER ${CMAKE_CURRENT_SOURCE_DIR}/test/run-test.cmake)

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
	endforeach()
endforeach()
