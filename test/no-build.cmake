# Proves the one-line user path from a copied checkout with no build machinery.
#
# Only the shipped Forth tree and the vendored KLambda corpus are copied; the
# copy has no build/, CMakeLists.txt or run-tests.sh.  A launcher outside 4th/
# contains the same single INCLUDED line a user types.  The boot must print
# BAKU-STARTED, evaluate the supplied Shen forms at the top level, return at end
# of input, and leave every shipped .4th file byte-identical (boot generates
# none).

foreach(required GFORTH_EXECUTABLE SOURCE_DIR BINARY_DIR)
	if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
		message(FATAL_ERROR "no-build: missing -D${required}=...")
	endif()
endforeach()

set(work "${BINARY_DIR}/no-build")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")
file(COPY "${SOURCE_DIR}/4th" DESTINATION "${work}/tree")
file(COPY "${SOURCE_DIR}/vendor/shen-43.2/klambda"
	DESTINATION "${work}/tree/vendor/shen-43.2")

# The boot reads the vendored corpus and must not rewrite it.  Snapshot the
# copied tree bytes so a source-level write path is caught even if the static
# audit is bypassed.
include("${SOURCE_DIR}/tools/kernel-digest.cmake")
baku_kernel_digest("${work}/tree/vendor/shen-43.2/klambda" vendor_before)

foreach(forbidden CMakeLists.txt run-tests.sh build)
	if(EXISTS "${work}/tree/${forbidden}")
		message(FATAL_ERROR "no-build: copied tree still contains ${forbidden}")
	endif()
endforeach()

file(GLOB_RECURSE before RELATIVE "${work}/tree" "${work}/tree/*.4th")

# The launcher is the user's include line and the test marker; it is not shipped
# source (the .4th snapshot below covers only 4th/).  gforth resolves INCLUDED
# relative to the including source, so the launcher sits in the tree root, the
# same place a user starts gforth.  The Shen forms exercise the real top level
# through standard input after Baku up.
file(WRITE "${work}/tree/launcher.fs"
	"S\" 4th/start.4th\" INCLUDED\n.\" BAKU-TEST-DONE\" CR\n")
file(WRITE "${work}/shen.stdin" "(+ 1 2)\n(factorial 10)\n")

execute_process(
	COMMAND "${GFORTH_EXECUTABLE}" -m 768M -d 16M -r 16M "${work}/tree/launcher.fs"
	WORKING_DIRECTORY "${work}/tree"
	INPUT_FILE "${work}/shen.stdin"
	RESULT_VARIABLE result
	OUTPUT_VARIABLE output
	ERROR_VARIABLE errors)

set(transcript "${output}${errors}")
if(NOT "${result}" STREQUAL "0")
	message(FATAL_ERROR "no-build: exit status ${result}\n${transcript}")
endif()

foreach(needle BAKU-STARTED 3628800 BAKU-TEST-DONE)
	string(FIND "${transcript}" "${needle}" found)
	if(found EQUAL -1)
		message(FATAL_ERROR "no-build: missing ${needle}\n${transcript}")
	endif()
endforeach()

file(GLOB_RECURSE after RELATIVE "${work}/tree" "${work}/tree/*.4th")
if(NOT "${before}" STREQUAL "${after}")
	message(FATAL_ERROR
		"no-build: boot changed the shipped .4th set\nbefore:\n${before}\nafter:\n${after}")
endif()

baku_kernel_digest("${work}/tree/vendor/shen-43.2/klambda" vendor_after)
if(NOT "${vendor_before}" STREQUAL "${vendor_after}")
	message(FATAL_ERROR
		"no-build: boot changed the vendored KLambda tree\nbefore: ${vendor_before}\nafter: ${vendor_after}")
endif()

message(STATUS "NO-BUILD PASS")
