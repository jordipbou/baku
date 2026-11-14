# Verify the vendored Shen 43.2 release tarball.
#
# The release asset is vendored beside the extracted trees so this check runs
# offline.  It recomputes the official artifact SHA-256, extracts the tarball
# into the build tree, and re-runs the one tree-digest verifier against both
# extracted trees.  The hash proves the artifact identity; the digests prove the
# vendored `klambda/` and `tests/` trees are byte-identical to the tarball.
#
# Usage:
#   cmake -DSOURCE_DIR=<repo> -DBINARY_DIR=<build> -P test/release-asset.cmake

cmake_minimum_required(VERSION 3.17)

if(NOT DEFINED SOURCE_DIR)
	get_filename_component(SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
if(NOT DEFINED BINARY_DIR)
	set(BINARY_DIR "${SOURCE_DIR}/build")
endif()
if(NOT DEFINED ASSET_FILE)
	set(ASSET_FILE
		"${SOURCE_DIR}/vendor/shen-43.2/ShenOSKernel-43.2.tar.gz")
endif()
if(NOT DEFINED README)
	set(README "${SOURCE_DIR}/vendor/shen-43.2/README.md")
endif()
if(NOT DEFINED TESTS_MD)
	set(TESTS_MD "${SOURCE_DIR}/vendor/shen-43.2/TESTS.md")
endif()

set(label "BAKU-RELEASE-ASSET")

if(NOT EXISTS "${ASSET_FILE}")
	message(FATAL_ERROR
		"${label} FAIL: missing vendored release asset ${ASSET_FILE}")
endif()
if(NOT EXISTS "${README}")
	message(FATAL_ERROR
		"${label} FAIL: missing kernel provenance file ${README}")
endif()
if(NOT EXISTS "${TESTS_MD}")
	message(FATAL_ERROR
		"${label} FAIL: missing test-suite provenance file ${TESTS_MD}")
endif()

# The asset identity has one source of truth: the provenance record.  The
# provenance audit separately proves that both provenance files record the same
# pinned value, so this script does not repeat the pin.
file(STRINGS "${README}" sha_lines REGEX "Asset SHA-256:")
list(LENGTH sha_lines sha_count)
if(NOT sha_count EQUAL 1)
	message(FATAL_ERROR
		"${label} FAIL: expected exactly one 'Asset SHA-256:' line in "
		"${README}, found ${sha_count}")
endif()
list(GET sha_lines 0 sha_line)
string(REGEX MATCH "Asset SHA-256:[^0-9a-fA-F]*([0-9a-fA-F]+)"
	sha_match "${sha_line}")
if(NOT sha_match)
	message(FATAL_ERROR
		"${label} FAIL: cannot parse 'Asset SHA-256:' line: ${sha_line}")
endif()
set(expected "${CMAKE_MATCH_1}")
string(LENGTH "${expected}" expected_length)
if(NOT expected_length EQUAL 64)
	message(FATAL_ERROR
		"${label} FAIL: 'Asset SHA-256:' is not 64 hex digits: ${expected}")
endif()
string(TOLOWER "${expected}" expected)

file(SHA256 "${ASSET_FILE}" actual)
if(NOT actual STREQUAL expected)
	message(FATAL_ERROR
		"${label} FAIL: checksum mismatch for ${ASSET_FILE}\n"
		" expected ${expected}\n"
		" got      ${actual}")
endif()

# Extract and prove the vendored trees are the tarball's trees.  The one
# verifier owns the tree-digest method; do not add a second implementation.
set(work "${BINARY_DIR}/release-asset")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")
file(ARCHIVE_EXTRACT INPUT "${ASSET_FILE}" DESTINATION "${work}")

set(extracted "${work}/ShenOSKernel-43.2")
if(NOT IS_DIRECTORY "${extracted}")
	message(FATAL_ERROR
		"${label} FAIL: tarball does not contain ShenOSKernel-43.2/")
endif()

function(check_extracted_tree tree_name expected_file)
	execute_process(
		COMMAND "${CMAKE_COMMAND}"
			"-DTREE=${extracted}/${tree_name}"
			"-DEXPECTED_FILE=${expected_file}"
			"-DLABEL=${label}"
			-P "${SOURCE_DIR}/tools/verify-kernel-digest.cmake"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE errors)
	if(NOT result EQUAL 0)
		message(FATAL_ERROR
			"${label} FAIL: extracted ${tree_name}/ does not match the "
			"recorded digest\n${output}${errors}")
	endif()
endfunction()

check_extracted_tree("klambda" "${README}")
check_extracted_tree("tests" "${TESTS_MD}")

message(STATUS "${label} OK: ${actual}")
