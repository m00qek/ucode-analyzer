#!/usr/bin/env bash
# Builds the ts binding (if needed) and runs the Milestone 0 smoke test.
#
# Env overrides:
#   UCODE_SOURCE_DIR        path to a checkout of jow-/ucode (defaults to ../../../lang)
#   TREE_SITTER_UCODE_DIR   path to tree-sitter-ucode (defaults to the vendored submodule)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UCODE_SOURCE_DIR="${UCODE_SOURCE_DIR:-$ROOT/../lang}"

if [ ! -x "$UCODE_SOURCE_DIR/build/ucode" ]; then
	cmake -S "$UCODE_SOURCE_DIR" -B "$UCODE_SOURCE_DIR/build" -DCMAKE_BUILD_TYPE=Debug >/dev/null
	cmake --build "$UCODE_SOURCE_DIR/build" -j"$(nproc)" >/dev/null
fi

cmake -S "$ROOT/bindings" -B "$ROOT/bindings/build" \
	-DUCODE_SOURCE_DIR="$UCODE_SOURCE_DIR" \
	${TREE_SITTER_UCODE_DIR:+-DTREE_SITTER_UCODE_DIR="$TREE_SITTER_UCODE_DIR"} >/dev/null
cmake --build "$ROOT/bindings/build" -j"$(nproc)" >/dev/null

LD_LIBRARY_PATH="$UCODE_SOURCE_DIR/build" \
	"$UCODE_SOURCE_DIR/build/ucode" -L "$ROOT/bindings" \
	"$ROOT/test/smoke/ts_binding_test.uc"
