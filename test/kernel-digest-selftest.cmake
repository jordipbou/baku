# Proves that a tree-digest check rejects a modified file.
#
# The real vendor tree is never touched: it is copied to the build directory,
# one file is modified there, and the verifier must fail against the recorded
# digest.
#
# The tree, provenance file, work directory name and victim glob default to the
# KLambda kernel so the existing registration keeps working.  The Shen test
# suite passes its own values.

cmake_minimum_required(VERSION 3.17)
include("${CMAKE_CURRENT_LIST_DIR}/../tools/kernel-digest.cmake")

get_filename_component(repo_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

if(NOT DEFINED SOURCE_TREE)
	set(SOURCE_TREE "${repo_root}/vendor/shen-43.2/klambda")
endif()
if(NOT DEFINED EXPECTED_FILE)
	set(EXPECTED_FILE "${repo_root}/vendor/shen-43.2/README.md")
endif()
if(NOT DEFINED WORK_NAME)
	set(WORK_NAME "kernel-digest-selftest")
endif()
if(NOT DEFINED VICTIM_GLOB)
	set(VICTIM_GLOB "*.kl")
endif()
if(NOT DEFINED LABEL)
	set(LABEL "BAKU-KERNEL-DIGEST")
endif()

if(NOT DEFINED BINARY_DIR)
	set(BINARY_DIR "${repo_root}/build")
endif()

baku_kernel_expected_digest("${EXPECTED_FILE}" expected)
baku_kernel_digest("${SOURCE_TREE}" pristine)

get_filename_component(source_name "${SOURCE_TREE}" NAME)
set(work "${BINARY_DIR}/${WORK_NAME}")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")
file(COPY "${SOURCE_TREE}" DESTINATION "${work}")
set(copy "${work}/${source_name}")

file(GLOB_RECURSE victims LIST_DIRECTORIES false RELATIVE "${copy}"
	"${copy}/${VICTIM_GLOB}")
list(SORT victims)
list(LENGTH victims count)
if(count EQUAL 0)
	message(FATAL_ERROR
		"${LABEL}-TAMPER: no files matching ${VICTIM_GLOB} in ${copy}")
endif()
list(GET victims 0 victim)

file(APPEND "${copy}/${victim}" "\n")

baku_kernel_digest("${copy}" tampered)
if(tampered STREQUAL pristine)
	message(FATAL_ERROR
		"${LABEL}-TAMPER: modifying ${victim} did not change the digest")
endif()

execute_process(
	COMMAND "${CMAKE_COMMAND}"
		"-DTREE=${copy}"
		"-DEXPECTED=${expected}"
		"-DLABEL=${LABEL}"
		-P "${repo_root}/tools/verify-kernel-digest.cmake"
	RESULT_VARIABLE result
	OUTPUT_VARIABLE output
	ERROR_VARIABLE errors)

if(result EQUAL 0)
	file(REMOVE_RECURSE "${work}")
	message(FATAL_ERROR
		"${LABEL}-TAMPER: verifier accepted a modified ${victim}\n"
		"${output}${errors}")
endif()

file(REMOVE_RECURSE "${work}")
message(STATUS
	"${LABEL}-TAMPER OK: verifier rejected a modified ${victim}")
