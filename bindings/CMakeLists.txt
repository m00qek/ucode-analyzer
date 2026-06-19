cmake_minimum_required(VERSION 3.13)
project(ucode_ts_binding C)

set(UCODE_SOURCE_DIR "" CACHE PATH "Path to a checkout of jow-/ucode (lang/), for headers")
set(TREE_SITTER_UCODE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tree-sitter-ucode" CACHE PATH "Path to tree-sitter-ucode (defaults to the vendored submodule)")

if(NOT UCODE_SOURCE_DIR)
  message(FATAL_ERROR "Set -DUCODE_SOURCE_DIR=/path/to/ucode (lang checkout)")
endif()

if(NOT EXISTS "${TREE_SITTER_UCODE_DIR}/src/parser.c")
  message(FATAL_ERROR "tree-sitter-ucode sources not found at ${TREE_SITTER_UCODE_DIR} -- run 'git submodule update --init' or pass -DTREE_SITTER_UCODE_DIR=")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(TREE_SITTER REQUIRED tree-sitter)

add_library(ucode_grammar STATIC
  ${TREE_SITTER_UCODE_DIR}/src/parser.c
  ${TREE_SITTER_UCODE_DIR}/src/scanner.c
)
target_include_directories(ucode_grammar PRIVATE ${TREE_SITTER_UCODE_DIR}/src)
set_target_properties(ucode_grammar PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(ucdocs_grammar STATIC
  ${TREE_SITTER_UCODE_DIR}/ucdocs/src/parser.c
)
target_include_directories(ucdocs_grammar PRIVATE ${TREE_SITTER_UCODE_DIR}/ucdocs/src)
set_target_properties(ucdocs_grammar PROPERTIES POSITION_INDEPENDENT_CODE ON)

# Native module is named "ts_native", distinct from the public "ts" module
# (bindings/ts.uc), so the two can coexist in the same search-path directory
# without ucode's module resolver shadowing one with the other.
add_library(ts_native MODULE ts_binding.c)
set_target_properties(ts_native PROPERTIES
  OUTPUT_NAME ts_native
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)
target_include_directories(ts_native PRIVATE ${UCODE_SOURCE_DIR}/include ${TREE_SITTER_INCLUDE_DIRS})
target_link_directories(ts_native PRIVATE ${TREE_SITTER_LIBRARY_DIRS})
target_link_libraries(ts_native PRIVATE ucode_grammar ucdocs_grammar ${TREE_SITTER_LIBRARIES})
