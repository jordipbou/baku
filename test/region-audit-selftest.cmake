# Proves the cross-region store audit detects an unreviewed raw store without
# touching the real tree.  Every case works on a temporary copy under
# BINARY_DIR.

if(NOT DEFINED PYTHON3_EXECUTABLE OR NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
	message(FATAL_ERROR "region-audit-selftest: missing PYTHON3_EXECUTABLE, SOURCE_DIR or BINARY_DIR")
endif()

set(audit_script "${SOURCE_DIR}/tools/region-audit.py")
set(work "${BINARY_DIR}/region-audit-selftest")
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
			"region-audit-selftest: ${label}: expected exit ${expected}, got ${audit_rc}\n${audit_full}")
	endif()
endmacro()

# 1. The current shipped sources pass and every computed store is reviewed.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/good")
run_audit("${work}/good" 0 "current shipped sources")
if(NOT audit_full MATCHES "REGION-AUDIT PASS")
	message(FATAL_ERROR "region-audit-selftest: current sources did not print REGION-AUDIT PASS\n${audit_full}")
endif()
if(NOT audit_full MATCHES "computed-address stores: 41")
	message(FATAL_ERROR "region-audit-selftest: current sources did not find 41 computed stores\n${audit_full}")
endif()
if(NOT audit_full MATCHES "reviewed computed-address stores: 41")
	message(FATAL_ERROR "region-audit-selftest: current sources did not review every computed store\n${audit_full}")
endif()
if(NOT audit_full MATCHES "removed-subsystem references: 0")
	message(FATAL_ERROR "region-audit-selftest: current sources name a removed subsystem\n${audit_full}")
endif()

# 2. A raw object-payload store in a compiler unit must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/raw")
file(APPEND "${work}/raw/4th/eval.4th"
	"\n: baku-region-selftest-store ( value cons -- ) baku-cons-tl-addr ! ;\n")
run_audit("${work}/raw" 1 "raw object-payload store")
if(NOT audit_full MATCHES "REGION-AUDIT FAIL"
		OR NOT audit_full MATCHES "BAKU-REGION-SELFTEST-STORE"
		OR NOT audit_full MATCHES "baku-cons-tl-addr")
	message(FATAL_ERROR "region-audit-selftest: raw store was not reported\n${audit_full}")
endif()

# 3. An extra store inside an already reviewed unit must fail the count check.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/count")
file(APPEND "${work}/count/4th/eval.4th"
	"\n: baku-closure! ( value obj i -- ) baku-closure-slot ! baku-closure-slot ! ;\n")
run_audit("${work}/count" 1 "extra store in a reviewed unit")
if(NOT audit_full MATCHES "REGION-AUDIT FAIL"
		OR NOT audit_full MATCHES "BAKU-CLOSURE!"
		OR NOT audit_full MATCHES "allowlist expects 1")
	message(FATAL_ERROR "region-audit-selftest: reviewed-unit count was not checked\n${audit_full}")
endif()

# 4. A store to a named dictionary cell is ordinary and must still pass.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/cell")
file(APPEND "${work}/cell/4th/eval.4th"
	"\nvariable baku-region-selftest-cell\n0 baku-region-selftest-cell !\n")
run_audit("${work}/cell" 0 "dictionary-cell store")
if(NOT audit_full MATCHES "REGION-AUDIT PASS")
	message(FATAL_ERROR "region-audit-selftest: a dictionary-cell store was rejected\n${audit_full}")
endif()

# 5. A removed-subsystem name in shipped source must fail the audit.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/removed")
file(APPEND "${work}/removed/4th/eval.4th" "\n\\ baku-mode\n")
run_audit("${work}/removed" 1 "removed-subsystem name")
if(NOT audit_full MATCHES "REGION-AUDIT FAIL"
		OR NOT audit_full MATCHES "removed-subsystem references: 1"
		OR NOT audit_full MATCHES "baku-mode")
	message(FATAL_ERROR "region-audit-selftest: a removed name was not reported\n${audit_full}")
endif()

message(STATUS "REGION-AUDIT-SELFTEST PASS")
