# Proves the licensing and kernel-provenance audit detects each failure it
# claims to catch without touching the real tree.  Every case works on a
# temporary copy under BINARY_DIR.

if(NOT DEFINED PYTHON3_EXECUTABLE OR NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
	message(FATAL_ERROR "provenance-audit-selftest: missing PYTHON3_EXECUTABLE, SOURCE_DIR or BINARY_DIR")
endif()

set(audit_script "${SOURCE_DIR}/tools/provenance-audit.py")
set(work "${BINARY_DIR}/provenance-audit-selftest")
file(REMOVE_RECURSE "${work}")

# A minimal stand-in for the vendored tree: the audit checks the licence and
# provenance files and the KLambda file count.  The real bytes are verified by
# baku_kernel_digest and baku_tests_digest, which this audit does not duplicate.
set(base "${work}/base")
file(MAKE_DIRECTORY "${base}/vendor/shen-43.2/klambda")
file(MAKE_DIRECTORY "${base}/vendor/shen-43.2/tests")
foreach(index RANGE 1 23)
	file(WRITE "${base}/vendor/shen-43.2/klambda/file${index}.kl" "")
endforeach()
foreach(copied LICENSE README.md)
	file(COPY "${SOURCE_DIR}/${copied}" DESTINATION "${base}")
endforeach()
foreach(copied README.md TESTS.md LICENSE.txt)
	file(COPY "${SOURCE_DIR}/vendor/shen-43.2/${copied}"
		DESTINATION "${base}/vendor/shen-43.2")
endforeach()

macro(run_audit root expected label)
	execute_process(
		COMMAND "${PYTHON3_EXECUTABLE}" "${audit_script}" --root "${root}"
		OUTPUT_VARIABLE audit_out
		ERROR_VARIABLE audit_err
		RESULT_VARIABLE audit_rc)
	set(audit_full "${audit_out}${audit_err}")
	if(NOT audit_rc EQUAL ${expected})
		message(FATAL_ERROR
			"provenance-audit-selftest: ${label}: expected exit ${expected}, got ${audit_rc}\n${audit_full}")
	endif()
endmacro()

macro(expect_pass label)
	run_audit("${base}" 0 "${label}")
	if(NOT audit_full MATCHES "PROVENANCE-AUDIT PASS")
		message(FATAL_ERROR
			"provenance-audit-selftest: ${label}: did not print PROVENANCE-AUDIT PASS\n${audit_full}")
	endif()
endmacro()

macro(rewrite path old new)
	file(READ "${path}" contents)
	string(REPLACE "${old}" "${new}" contents "${contents}")
	file(WRITE "${path}" "${contents}")
endmacro()

# 1. The current provenance and licence files must pass.
expect_pass("current provenance and licences")

# 2. The repository LICENSE must remain MIT.
file(COPY "${base}" DESTINATION "${work}/mit")
rewrite("${work}/mit/base/LICENSE" "MIT License" "Apache License")
set(case_root "${work}/mit/base")
run_audit("${case_root}" 1 "non-MIT repository licence")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "missing the MIT title")
	message(FATAL_ERROR
		"provenance-audit-selftest: non-MIT licence was not reported\n${audit_full}")
endif()

# 3. The vendored kernel licence must remain the BSD 3-Clause text.
file(COPY "${base}" DESTINATION "${work}/bsd")
rewrite("${work}/bsd/base/vendor/shen-43.2/LICENSE.txt"
	"All rights reserved." "")
set(case_root "${work}/bsd/base")
run_audit("${case_root}" 1 "missing BSD clause")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "All rights reserved")
	message(FATAL_ERROR
		"provenance-audit-selftest: missing BSD clause was not reported\n${audit_full}")
endif()

# 4. Every provenance field must be present in the test-suite record.
file(COPY "${base}" DESTINATION "${work}/field")
rewrite("${work}/field/base/vendor/shen-43.2/TESTS.md"
	"- Tag: `shen-43.2`" "- Version: `shen-43.2`")
set(case_root "${work}/field/base")
run_audit("${case_root}" 1 "missing provenance field")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "missing provenance field 'Tag'")
	message(FATAL_ERROR
		"provenance-audit-selftest: missing Tag field was not reported\n${audit_full}")
endif()

# 5. The recorded asset checksum must match the pinned release.
file(COPY "${base}" DESTINATION "${work}/asset")
rewrite("${work}/asset/base/vendor/shen-43.2/README.md"
	"23c71508f0de24785e1f127ea4fab440081904d81c463090bc642ee840417f32"
	"0000000000000000000000000000000000000000000000000000000000000000")
set(case_root "${work}/asset/base")
run_audit("${case_root}" 1 "wrong asset checksum")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "expected the pinned")
	message(FATAL_ERROR
		"provenance-audit-selftest: wrong asset checksum was not reported\n${audit_full}")
endif()

# 6. The README must keep pointing at both provenance files.
file(COPY "${base}" DESTINATION "${work}/reference")
rewrite("${work}/reference/base/README.md"
	"vendor/shen-43.2/TESTS.md" "vendor/shen-43.2/notes.md")
set(case_root "${work}/reference/base")
run_audit("${case_root}" 1 "missing test-suite provenance reference")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "test-suite provenance reference")
	message(FATAL_ERROR
		"provenance-audit-selftest: missing README reference was not reported\n${audit_full}")
endif()

# 7. The two provenance files must agree on the release identity.
file(COPY "${base}" DESTINATION "${work}/mismatch")
rewrite("${work}/mismatch/base/vendor/shen-43.2/TESTS.md"
	"e6947f507ebc03f7ade5d2a8d971bd05d84a5bae"
	"0000000000000000000000000000000000000000")
set(case_root "${work}/mismatch/base")
run_audit("${case_root}" 1 "provenance mismatch")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "Commit differs")
	message(FATAL_ERROR
		"provenance-audit-selftest: provenance mismatch was not reported\n${audit_full}")
endif()

# 8. The two vendored trees must record distinct digests.
file(COPY "${base}" DESTINATION "${work}/digest")
rewrite("${work}/digest/base/vendor/shen-43.2/TESTS.md"
	"c6cfd16a7f034e877aefbe7129f632149fdd5155188adf5386df2b6d18d6dd98"
	"b6a3610b5a7438cf6bcc6bdbbfe9eaa016420d03976652062d93cdc81ea9e80c")
set(case_root "${work}/digest/base")
run_audit("${case_root}" 1 "duplicate tree digest")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "tree digests are identical")
	message(FATAL_ERROR
		"provenance-audit-selftest: duplicate tree digest was not reported\n${audit_full}")
endif()

# 9. A missing KLambda file must fail the tree count.
file(COPY "${base}" DESTINATION "${work}/count")
file(REMOVE "${work}/count/base/vendor/shen-43.2/klambda/file23.kl")
set(case_root "${work}/count/base")
run_audit("${case_root}" 1 "wrong KLambda file count")
if(NOT audit_full MATCHES "PROVENANCE-AUDIT FAIL"
		OR NOT audit_full MATCHES "expected 23 KLambda files")
	message(FATAL_ERROR
		"provenance-audit-selftest: missing KLambda file was not reported\n${audit_full}")
endif()

message(STATUS "PROVENANCE-AUDIT-SELFTEST PASS")
