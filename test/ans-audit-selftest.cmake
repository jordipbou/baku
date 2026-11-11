# Proves the ANS static audit detects violations without touching the real tree.
# Every case works on a temporary copy under BINARY_DIR.

if(NOT DEFINED PYTHON3_EXECUTABLE OR NOT DEFINED SOURCE_DIR OR NOT DEFINED BINARY_DIR)
	message(FATAL_ERROR "ans-audit-selftest: missing PYTHON3_EXECUTABLE, SOURCE_DIR or BINARY_DIR")
endif()

set(audit_script "${SOURCE_DIR}/tools/ans-audit.py")
set(work "${BINARY_DIR}/ans-audit-selftest")
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
			"ans-audit-selftest: ${label}: expected exit ${expected}, got ${audit_rc}\n${audit_full}")
	endif()
endmacro()

# 1. The current shipped sources must pass.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/good")
run_audit("${work}/good" 0 "current sources")
if(NOT audit_full MATCHES "ANS-AUDIT PASS")
	message(FATAL_ERROR "ans-audit-selftest: current sources did not print ANS-AUDIT PASS\n${audit_full}")
endif()

# 2. A deliberately inserted non-ANS word must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/badword")
file(APPEND "${work}/badword/4th/primitives.4th"
	"\n: baku-audit-bad-word ( -- ) NON-ANS-AUDIT-WORD ;\n")
run_audit("${work}/badword" 1 "inserted non-ANS word")
if(NOT audit_full MATCHES "NON-ANS-AUDIT-WORD")
	message(FATAL_ERROR "ans-audit-selftest: non-ANS word was not reported\n${audit_full}")
endif()

# 3. A deliberately inserted DODO reference must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/dodo")
file(APPEND "${work}/dodo/4th/primitives.4th"
	"\n: baku-audit-dodo ( -- ) dodo-audit-call ;\n")
run_audit("${work}/dodo" 1 "inserted DODO reference")
if(NOT audit_full MATCHES "DODO REFERENCES" OR NOT audit_full MATCHES "dodo-audit-call")
	message(FATAL_ERROR "ans-audit-selftest: DODO reference was not reported\n${audit_full}")
endif()

# 4. A host-language file in the shipped path must fail.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/host")
file(WRITE "${work}/host/4th/helper.c" "int helper(void) { return 0; }\n")
run_audit("${work}/host" 1 "host-language file")
if(NOT audit_full MATCHES "HOST-LANGUAGE FILES" OR NOT audit_full MATCHES "helper.c")
	message(FATAL_ERROR "ans-audit-selftest: host-language file was not reported\n${audit_full}")
endif()

# 5. Comments and strings are not words: mentioning a non-ANS name there passes.
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/comment")
file(APPEND "${work}/comment/4th/primitives.4th"
	"\n\\ NON-ANS-AUDIT-COMMENT is only a comment\ns\" NON-ANS-AUDIT-STRING\" drop\n")
run_audit("${work}/comment" 0 "comment and string text")
if(audit_full MATCHES "NON-ANS-AUDIT-COMMENT" OR audit_full MATCHES "NON-ANS-AUDIT-STRING")
	message(FATAL_ERROR "ans-audit-selftest: comment or string was reported as a word\n${audit_full}")
endif()

message(STATUS "ANS-AUDIT-SELFTEST PASS")
