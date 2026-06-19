cmake_minimum_required(VERSION 3.10)
project(ucode_language_server_native C)

# Populated by openwrt/ucode-language-server/Makefile's Build/Prepare step,
# which copies ./third_party alongside ./mod into the package build dir --
# vendored rather than fetched, since none of this is available as an
# OpenWrt feed package.
set(TREE_SITTER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tree-sitter)
set(TREE_SITTER_UCODE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tree-sitter-ucode)

find_library(UCODE_LIB ucode)

add_library(tree_sitter_core STATIC ${TREE_SITTER_DIR}/lib/src/lib.c)
target_include_directories(tree_sitter_core PUBLIC
  ${TREE_SITTER_DIR}/lib/include
  ${TREE_SITTER_DIR}/lib/src
)
set_target_properties(tree_sitter_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

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

add_library(native SHARED native.c)
set_target_properties(native PROPERTIES PREFIX "")
target_link_libraries(native ${UCODE_LIB} ucode_grammar ucdocs_grammar tree_sitter_core)

# Test-only (e2e harness process spawning). CMake-installed so it survives
# OpenWrt's build-dir autoremove cleanup (which wipes everything not under
# .pkgdir/), but the OpenWrt Package/install step never references it, so it
# never ships in the .apk.
add_library(spawn_pipes SHARED spawn_pipes.c)
set_target_properties(spawn_pipes PROPERTIES PREFIX "")
target_link_libraries(spawn_pipes ${UCODE_LIB})

if(NOT PKG_NAME)
  set(PKG_NAME "ucode_language_server")
endif()

install(TARGETS native DESTINATION lib/ucode/${PKG_NAME})
install(TARGETS spawn_pipes DESTINATION lib/ucode)
