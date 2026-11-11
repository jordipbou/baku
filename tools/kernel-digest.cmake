# Canonical digest of the vendored KLambda tree.
#
# The exact method is documented in vendor/shen-43.2/README.md.  A manifest is
# built with one line per file, ordered by relative path:
#
#   <lowercase-sha256-of-file-bytes>  <relative-posix-path>\n
#
# The tree digest is the SHA-256 of those manifest bytes.

function(baku_kernel_digest tree out_var)
	get_filename_component(tree "${tree}" ABSOLUTE)
	if(NOT IS_DIRECTORY "${tree}")
		message(FATAL_ERROR "kernel digest: not a directory: ${tree}")
	endif()
	file(GLOB_RECURSE files LIST_DIRECTORIES false RELATIVE "${tree}"
		"${tree}/*")
	list(SORT files)
	set(manifest "")
	foreach(file IN LISTS files)
		file(SHA256 "${tree}/${file}" file_digest)
		string(APPEND manifest "${file_digest}  ${file}\n")
	endforeach()
	string(SHA256 digest "${manifest}")
	set(${out_var} "${digest}" PARENT_SCOPE)
endfunction()

function(baku_kernel_expected_digest readme out_var)
	if(NOT EXISTS "${readme}")
		message(FATAL_ERROR "kernel digest: no provenance file: ${readme}")
	endif()
	file(STRINGS "${readme}" lines REGEX "Tree SHA-256:")
	list(LENGTH lines count)
	if(NOT count EQUAL 1)
		message(FATAL_ERROR
			"kernel digest: expected exactly one 'Tree SHA-256:' line in ${readme}, found ${count}")
	endif()
	list(GET lines 0 line)
	string(REGEX MATCH "Tree SHA-256:[^0-9a-fA-F]*([0-9a-fA-F]+)"
		match "${line}")
	if(NOT match)
		message(FATAL_ERROR
			"kernel digest: cannot parse 'Tree SHA-256:' line in ${readme}: ${line}")
	endif()
	set(expected "${CMAKE_MATCH_1}")
	string(LENGTH "${expected}" length)
	if(NOT length EQUAL 64)
		message(FATAL_ERROR
			"kernel digest: 'Tree SHA-256:' value is not 64 hex digits in ${readme}: ${expected}")
	endif()
	string(TOLOWER "${expected}" expected)
	set(${out_var} "${expected}" PARENT_SCOPE)
endfunction()
