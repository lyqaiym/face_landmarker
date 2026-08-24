cmake_minimum_required(VERSION 3.13)

# Stand-in for the //mediapipe/tasks/cc/metadata:metadata_parser_h genrule, which shells
# out to sed. The version string is single-sourced from the schema's
# "// Schema Semantic version: X.Y.Z" comment so it cannot drift from the .fbs.
#
# Usage: cmake -DSCHEMA=<metadata_schema.fbs> -DTEMPLATE=<metadata_parser.h.template>
#              -DOUTPUT=<metadata_parser.h> -P metadata_parser_version.cmake

if(NOT DEFINED SCHEMA OR NOT DEFINED TEMPLATE OR NOT DEFINED OUTPUT)
  message(FATAL_ERROR
    "usage: cmake -DSCHEMA=<f> -DTEMPLATE=<f> -DOUTPUT=<f> -P metadata_parser_version.cmake")
endif()

file(STRINGS "${SCHEMA}" hits REGEX "Schema Semantic version")
if(NOT hits)
  message(FATAL_ERROR "no 'Schema Semantic version' comment in ${SCHEMA}")
endif()

list(GET hits 0 line)
# Mirror sed's greedy `s/.*\: *//`: drop everything through the last colon.
string(REGEX REPLACE "^.*: *" "" version "${line}")
if(version STREQUAL "")
  message(FATAL_ERROR "could not parse version from: ${line}")
endif()

file(READ "${TEMPLATE}" text)
string(REPLACE "{LATEST_METADATA_PARSER_VERSION}" "${version}" text "${text}")
file(WRITE "${OUTPUT}" "${text}")
