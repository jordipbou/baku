# Proves the release-asset check recomputes the official tarball checksum and
# rejects a modified asset.  The real vendored tree is never touched: a copy of
# the tarball is corrupted in the build directory.

cmake_minimum_required(VERSION 3.17)

if(NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
	message(FATAL_ERROR
		"release-asset-selftest: missing SOURCE_DIR or BINARY_DIR")
endif()

set(audit_script "${SOURCE_DIR}/test/release-asset.cmake")
set(asset "${SOURCE_DIR}/vendor/shen-43.2/ShenOSKernel-43.2.tar.gz")
set(work "${BINARY_DIR}/release-asset-selftest")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")

macro(run_audit asset_file build_dir expected label)
	execute_process(
		COMMAND "${CMAKE_COMMAND}"
			"-DSOURCE_DIR=${SOURCE_DIR}"
			"-DBINARY_DIR=${build_dir}"
			"-DASSET_FILE=${asset_file}"
			-P "${audit_script}"
		RESULT_VARIABLE audit_rc
		OUTPUT_VARIABLE audit_out
		ERROR_VARIABLE audit_err)
	set(audit_full "${audit_out}${audit_err}")
	if(NOT audit_rc EQUAL ${expected})
		message(FATAL_ERROR
			"release-asset-selftest: ${label}: expected exit ${expected}, "
			"got ${audit_rc}\n${audit_full}")
	endif()
endmacro()

# 1. The real vendored tarball must reproduce the recorded checksum and extract
#    to both recorded tree digests.
run_audit("${asset}" "${work}/pass" 0 "real release asset")
if(NOT audit_full MATCHES "BAKU-RELEASE-ASSET OK")
	message(FATAL_ERROR
		"release-asset-selftest: real asset did not report OK\n${audit_full}")
endif()

# 2. A modified tarball must fail the checksum check before extraction.
file(COPY "${asset}" DESTINATION "${work}/corrupt")
set(corrupt "${work}/corrupt/ShenOSKernel-43.2.tar.gz")
file(APPEND "${corrupt}" "\n")
run_audit("${corrupt}" "${work}/fail" 1 "modified release asset")
if(NOT audit_full MATCHES "BAKU-RELEASE-ASSET FAIL"
		OR NOT audit_full MATCHES "checksum mismatch")
	message(FATAL_ERROR
		"release-asset-selftest: modified asset was not reported\n${audit_full}")
endif()

file(REMOVE_RECURSE "${work}")
message(STATUS "RELEASE-ASSET-SELFTEST PASS")
