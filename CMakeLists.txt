cmake_minimum_required(VERSION 3.17)
project(baku LANGUAGES C)

enable_testing()

include(FetchContent)
FetchContent_Declare(
	sloth
	GIT_REPOSITORY https://github.com/jordipbou/sloth
	GIT_TAG 12f7189d65e80d3617ff15967a831c01cb254ef2
	SOURCE_SUBDIR platforms/c
	EXCLUDE_FROM_ALL
)
FetchContent_MakeAvailable(sloth)

find_program(GFORTH_EXECUTABLE gforth)

file(GLOB BAKU_TESTS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/*.4th)
foreach(test_file IN LISTS BAKU_TESTS)
	get_filename_component(test_name ${test_file} NAME_WE)

	add_test(NAME baku_${test_name}_sloth
		COMMAND $<TARGET_FILE:sloth> ${test_file})
	set_tests_properties(baku_${test_name}_sloth PROPERTIES
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test
		PASS_REGULAR_EXPRESSION "BAKU-TEST-DONE")

	if(GFORTH_EXECUTABLE)
		add_test(NAME baku_${test_name}_gforth
			COMMAND ${GFORTH_EXECUTABLE} ${test_file})
		set_tests_properties(baku_${test_name}_gforth PROPERTIES
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/test
			PASS_REGULAR_EXPRESSION "BAKU-TEST-DONE")
	endif()
endforeach()
