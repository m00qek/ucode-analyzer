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

add_library(tree_sitter_native SHARED tree_sitter/native.c)
set_target_properties(tree_sitter_native PROPERTIES PREFIX "")
target_link_libraries(tree_sitter_native ${UCODE_LIB} ucode_grammar ucdocs_grammar tree_sitter_core)

# Raw stdin I/O primitives for the server's uloop-driven read loop.
add_library(language_server_native SHARED language_server/native.c)
set_target_properties(language_server_native PROPERTIES PREFIX "")
target_link_libraries(language_server_native ${UCODE_LIB})

# Test-only (JSON-RPC client primitives for the e2e harness). Its source lives
# under test/mod/rpc_client/ and is flattened into the build dir by Build/Prepare
# so it resolves here at rpc_client/native.c. CMake-installed into the staging
# tree so the separate ucode-mod-language-server-test-client package can pick it
# up (and so it survives OpenWrt's build-dir autoremove, which keeps only
# .pkgdir/). It is deliberately kept out of the production packages.
add_library(rpc_client_native SHARED rpc_client/native.c)
set_target_properties(rpc_client_native PROPERTIES PREFIX "")
target_link_libraries(rpc_client_native ${UCODE_LIB})

if(NOT PKG_NAME)
  set(PKG_NAME "ucode_language_server")
endif()

# Both targets are installed as native.so under their respective namespace
# directories so ucode resolves them as 'tree_sitter.native' and
# 'rpc_client.native'. The build names (tree_sitter_native / rpc_client_native)
# must differ to avoid a CMake/Ninja conflict in the shared build directory.
install(FILES $<TARGET_FILE:tree_sitter_native>
        DESTINATION lib/ucode/tree_sitter RENAME native.so)
install(FILES $<TARGET_FILE:language_server_native>
        DESTINATION lib/ucode/language_server RENAME native.so)
install(FILES $<TARGET_FILE:rpc_client_native>
        DESTINATION lib/ucode/rpc_client RENAME native.so)
