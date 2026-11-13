# Proves the vendored-kernel source audit detects a rewrite path without
# touching the real tree.  Every case works on a temporary copy under
# BINARY_DIR.

if(NOT DEFINED PYTHON3_EXECUTABLE OR NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
	message(FATAL_ERROR "vendor-audit-selftest: missing PYTHON3_EXECUTABLE, SOURCE_DIR or BINARY_DIR")
endif()

set(audit_script "${SOURCE_DIR}/tools/vendor-audit.py")
set(work "${BINARY_DIR}/vendor-audit-selftest")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")

macro(run_audit root expected label)
	execute_process(
		COMMAND "${PYTHON3_EXECUTABLE}" "${audit_script}" --root "${root}"
		OUTPUT_VARIABLE audit_out
		ERROR_VARIABLE audit_err
		RESULT_VARIABLE audit_rc)
	set(audit_full "${audit_out}${audit_err}")
	if(NOT audit_rc EQUAL ${expected})
		message(FATAL_ERROR
			"vendor-audit-selftest: ${label}: expected exit ${expected}, got ${audit_rc}\n${audit_full}")
	endif()
endmacro()

# 1. The current shipped sources must pass and find the single boot prefix.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/good")
run_audit("${work}/good" 0 "current shipped sources")
if(NOT audit_full MATCHES "VENDOR-AUDIT PASS")
	message(FATAL_ERROR "vendor-audit-selftest: current sources did not print VENDOR-AUDIT PASS\n${audit_full}")
endif()
if(NOT audit_full MATCHES "vendored path literals: 1")
	message(FATAL_ERROR "vendor-audit-selftest: current sources did not find exactly one read prefix\n${audit_full}")
endif()

# 2. A write through the boot prefix must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/write")
file(APPEND "${work}/write/4th/boot.4th"
	"\n: baku-vendor-selftest-write ( -- ) baku-boot-dir drop s\" scratch\" w/o create-file throw ;\n")
run_audit("${work}/write" 1 "write through the boot prefix")
if(NOT audit_full MATCHES "VENDOR-AUDIT FAIL"
		OR NOT audit_full MATCHES "BAKU-VENDOR-SELFTEST-WRITE"
		OR NOT audit_full MATCHES "create-file")
	message(FATAL_ERROR "vendor-audit-selftest: boot-prefix write was not reported\n${audit_full}")
endif()

# 3. A direct vendored path outside BAKU-BOOT-DIR must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/literal")
file(APPEND "${work}/literal/4th/primitives.4th"
	"\n: baku-vendor-selftest-patch ( -- ) s\" vendor/shen-43.2/klambda/sys.kl\" s\" old\" s\" new\" baku-vendor-replace ;\n")
run_audit("${work}/literal" 1 "vendored path literal outside the read prefix")
if(NOT audit_full MATCHES "VENDOR-AUDIT FAIL"
		OR NOT audit_full MATCHES "vendor/shen-43.2/klambda/sys.kl"
		OR NOT audit_full MATCHES "BAKU-VENDOR-SELFTEST-PATCH")
	message(FATAL_ERROR "vendor-audit-selftest: extra vendored literal was not reported\n${audit_full}")
endif()

# 4. A Baku-specific replacement helper fed by the boot prefix must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/replace")
file(APPEND "${work}/replace/4th/boot.4th"
	"\n: baku-vendor-selftest-replace ( -- ) baku-boot-dir baku-vendor-replace ;\n")
run_audit("${work}/replace" 1 "replacement helper fed by the boot prefix")
if(NOT audit_full MATCHES "VENDOR-AUDIT FAIL"
		OR NOT audit_full MATCHES "BAKU-VENDOR-SELFTEST-REPLACE"
		OR NOT audit_full MATCHES "baku-vendor-replace")
	message(FATAL_ERROR "vendor-audit-selftest: replacement helper was not reported\n${audit_full}")
endif()

message(STATUS "VENDOR-AUDIT-SELFTEST PASS")
