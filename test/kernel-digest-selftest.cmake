# Proves that the tree-digest check rejects a modified .kl file.
#
# The real vendor tree is never touched: it is copied to the build directory,
# one .kl file is modified there, and the verifier must fail against the
# recorded digest.

cmake_minimum_required(VERSION 3.17)
include("${CMAKE_CURRENT_LIST_DIR}/../tools/kernel-digest.cmake")

get_filename_component(repo_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(source_tree "${repo_root}/vendor/shen-43.2/klambda")
set(readme "${repo_root}/vendor/shen-43.2/README.md")

if(NOT DEFINED BINARY_DIR)
	set(BINARY_DIR "${repo_root}/build")
endif()

baku_kernel_expected_digest("${readme}" expected)
baku_kernel_digest("${source_tree}" pristine)

set(work "${BINARY_DIR}/kernel-digest-selftest")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")
file(COPY "${source_tree}" DESTINATION "${work}")
set(copy "${work}/klambda")

file(GLOB_RECURSE kl_files LIST_DIRECTORIES false RELATIVE "${copy}"
	"${copy}/*.kl")
list(SORT kl_files)
list(LENGTH kl_files count)
if(count EQUAL 0)
	message(FATAL_ERROR "kernel digest selftest: no .kl files in ${copy}")
endif()
list(GET kl_files 0 victim)

file(APPEND "${copy}/${victim}" "\n")

baku_kernel_digest("${copy}" tampered)
if(tampered STREQUAL pristine)
	message(FATAL_ERROR
		"kernel digest selftest: modifying ${victim} did not change the digest")
endif()

execute_process(
	COMMAND "${CMAKE_COMMAND}"
		"-DTREE=${copy}"
		"-DEXPECTED=${expected}"
		-P "${repo_root}/tools/verify-kernel-digest.cmake"
	RESULT_VARIABLE result
	OUTPUT_VARIABLE output
	ERROR_VARIABLE errors)

if(result EQUAL 0)
	file(REMOVE_RECURSE "${work}")
	message(FATAL_ERROR
		"kernel digest selftest: verifier accepted a modified ${victim}\n"
		"${output}${errors}")
endif()

file(REMOVE_RECURSE "${work}")
message(STATUS
	"BAKU-KERNEL-DIGEST-TAMPER OK: verifier rejected a modified ${victim}")
