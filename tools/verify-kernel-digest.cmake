# Recompute the vendored KLambda tree digest and compare it with the recorded
# value.  See vendor/shen-43.2/README.md for the method.
#
# Usage:
#   cmake -DTREE=<klambda-dir> -DEXPECTED_FILE=<README.md> \
#         -P tools/verify-kernel-digest.cmake
#   cmake -DTREE=<klambda-dir> -DEXPECTED=<hex-digest> \
#         -P tools/verify-kernel-digest.cmake
#
# With neither EXPECTED nor EXPECTED_FILE set, it uses the repository's
# vendor/shen-43.2/README.md.

cmake_minimum_required(VERSION 3.17)
include("${CMAKE_CURRENT_LIST_DIR}/kernel-digest.cmake")

get_filename_component(repo_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

if(NOT DEFINED TREE)
	set(TREE "${repo_root}/vendor/shen-43.2/klambda")
endif()

if(DEFINED EXPECTED)
	string(TOLOWER "${EXPECTED}" expected)
else()
	if(NOT DEFINED EXPECTED_FILE)
		set(EXPECTED_FILE "${repo_root}/vendor/shen-43.2/README.md")
	endif()
	baku_kernel_expected_digest("${EXPECTED_FILE}" expected)
endif()

if(NOT DEFINED LABEL)
	set(LABEL "BAKU-KERNEL-DIGEST")
endif()

baku_kernel_digest("${TREE}" actual)

if(NOT actual STREQUAL expected)
	message(FATAL_ERROR
		"${LABEL} FAIL: ${TREE}\n"
		" expected ${expected}\n"
		" got      ${actual}\n"
		" method: sorted relative paths plus file SHA-256 manifest; "
		"see vendor/shen-43.2/README.md")
endif()

message(STATUS "${LABEL} OK: ${actual}")
