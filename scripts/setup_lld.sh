#!/usr/bin/env bash
# setup_lld.sh — Patch the Zephyr tree and Zephyr SDK so that the lld linker
#                can be used with the GCC compiler.
#
# Usage:
#   ./scripts/setup_lld.sh
#
# Environment variables (all optional — the script tries to auto-detect):
#   ZEPHYR_BASE            Path to the Zephyr tree (default: ~/zephyrproject/zephyr)
#   ZEPHYR_SDK_INSTALL_DIR Path to the Zephyr SDK (auto-detected from cmake registry)
#   LLD_PATH               Explicit path to the ld.lld binary (otherwise found via PATH)
#
# Prerequisites:
#   - ld.lld must be installed on the system:
#       Linux:  apt install lld  (or equivalent)
#       macOS:  download LLVM from https://github.com/llvm/llvm-project/releases
#               and set LLD_PATH=/path/to/llvm/bin/ld.lld
#
# What this script does:
#   1. Creates cmake/linker/lld/gcc/linker_flags.cmake in the Zephyr tree
#      (bridges the lld linker module with GCC-specific flags like -specs=)
#   2. Patches cmake/linker/lld/linker_libraries.cmake in the Zephyr tree
#      (adds -lgcc runtime library when using GCC instead of clang)
#   3. Symlinks ld.lld into the Zephyr SDK's cross-compiler bin directory
#      (required for GCC's collect2 to find ld.lld)
#
# These patches are needed because Zephyr's lld linker module was designed
# for clang, not GCC.  The patches are minimal and non-destructive.
#
# To undo:
#   rm  "$ZEPHYR_BASE/cmake/linker/lld/gcc/linker_flags.cmake"
#   git -C "$ZEPHYR_BASE" checkout cmake/linker/lld/linker_libraries.cmake
#   rm  "$SDK_DIR/arm-zephyr-eabi/arm-zephyr-eabi/bin/ld.lld"

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate ZEPHYR_BASE
# ---------------------------------------------------------------------------
if [ -z "${ZEPHYR_BASE:-}" ]; then
  if [ -d "$HOME/zephyrproject/zephyr" ]; then
    ZEPHYR_BASE="$HOME/zephyrproject/zephyr"
  else
    echo "ERROR: ZEPHYR_BASE is not set and ~/zephyrproject/zephyr does not exist." >&2
    exit 1
  fi
fi
echo "ZEPHYR_BASE = $ZEPHYR_BASE"

# ---------------------------------------------------------------------------
# Locate Zephyr SDK
# ---------------------------------------------------------------------------
if [ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]; then
  # Try to read from cmake package registry
  for f in "$HOME"/.cmake/packages/Zephyr-sdk/* /root/.cmake/packages/Zephyr-sdk/* 2>/dev/null; do
    [ -f "$f" ] || continue
    candidate_cmake_dir=$(cat "$f" | tr -d '[:space:]')
    candidate_dir=$(dirname "$candidate_cmake_dir")
    if [ -f "$candidate_dir/cmake/zephyr/generic.cmake" ]; then
      ZEPHYR_SDK_INSTALL_DIR="$candidate_dir"
      break
    fi
  done
fi

if [ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]; then
  echo "ERROR: Cannot locate Zephyr SDK. Set ZEPHYR_SDK_INSTALL_DIR." >&2
  exit 1
fi
SDK_DIR="$ZEPHYR_SDK_INSTALL_DIR"
echo "SDK_DIR     = $SDK_DIR"

# ---------------------------------------------------------------------------
# Locate ld.lld
# ---------------------------------------------------------------------------
LLD_BIN=""
if [ -n "${LLD_PATH:-}" ]; then
  if [ -x "$LLD_PATH" ]; then
    LLD_BIN="$LLD_PATH"
  else
    echo "ERROR: LLD_PATH=$LLD_PATH is not an executable." >&2
    exit 1
  fi
elif command -v ld.lld >/dev/null 2>&1; then
  LLD_BIN="$(command -v ld.lld)"
else
  # On macOS, check common LLVM install locations
  for candidate in \
    /usr/local/opt/llvm/bin/ld.lld \
    /opt/homebrew/opt/llvm/bin/ld.lld \
    /usr/local/llvm/bin/ld.lld \
    /opt/llvm/bin/ld.lld; do
    if [ -x "$candidate" ]; then
      LLD_BIN="$candidate"
      break
    fi
  done
fi

if [ -z "$LLD_BIN" ]; then
  echo "ERROR: ld.lld not found." >&2
  echo "" >&2
  echo "Install lld:" >&2
  echo "  Linux:  sudo apt install lld" >&2
  echo "  macOS:  download LLVM from https://github.com/llvm/llvm-project/releases" >&2
  echo "          then: LLD_PATH=/path/to/llvm/bin/ld.lld ./scripts/setup_lld.sh" >&2
  exit 1
fi
echo "ld.lld      = $LLD_BIN"

# ---------------------------------------------------------------------------
# Patch 1: Create cmake/linker/lld/gcc/linker_flags.cmake
# ---------------------------------------------------------------------------
LLD_GCC_FLAGS="$ZEPHYR_BASE/cmake/linker/lld/gcc/linker_flags.cmake"
mkdir -p "$(dirname "$LLD_GCC_FLAGS")"

if [ -f "$LLD_GCC_FLAGS" ]; then
  echo "SKIP: $LLD_GCC_FLAGS already exists."
else
  cat > "$LLD_GCC_FLAGS" << 'CMAKE_EOF'
# SPDX-License-Identifier: Apache-2.0
#
# Bridge: using lld linker with GCC compiler.
# This file mirrors cmake/linker/ld/gcc/linker_flags.cmake for the lld case.

# GCC 11+ defaults to DWARF v5 which pyelftools can't parse.
add_link_options(-gdwarf-4)

# Extra warnings options for twister run
set_property(TARGET linker PROPERTY warnings_as_errors -Wl,--fatal-warnings)

# GCC needs the -specs= prefix for spec files (e.g. picolibc.specs).
set_linker_property(PROPERTY specs -specs=)
CMAKE_EOF
  echo "CREATED: $LLD_GCC_FLAGS"
fi

# ---------------------------------------------------------------------------
# Patch 2: Patch cmake/linker/lld/linker_libraries.cmake for GCC rt_library
# ---------------------------------------------------------------------------
LLD_LIBS="$ZEPHYR_BASE/cmake/linker/lld/linker_libraries.cmake"

if grep -q 'CMAKE_C_COMPILER_ID STREQUAL "GNU"' "$LLD_LIBS" 2>/dev/null; then
  echo "SKIP: $LLD_LIBS already patched for GCC."
else
  # Replace the rt_library line with a GCC-aware conditional
  cp "$LLD_LIBS" "${LLD_LIBS}.bak"
  cat > "$LLD_LIBS" << 'CMAKE_EOF'
# Copyright (c) 2024 Nordic Semiconductor
#
# SPDX-License-Identifier: Apache-2.0

set_linker_property(NO_CREATE TARGET linker PROPERTY c_library "-lc")
# When using GCC compiler with lld linker, we need -lgcc for ARM ABI runtime.
# For clang, this will be overridden by clang/target.cmake.
if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  set_linker_property(NO_CREATE TARGET linker PROPERTY rt_library "-lgcc")
else()
  # Default per standard, will be populated by clang/target.cmake based on clang output.
  set_linker_property(NO_CREATE TARGET linker PROPERTY rt_library "")
endif()
set_linker_property(TARGET linker PROPERTY c++_library "-lc++;-lc++abi")

if(CONFIG_CPP
   AND NOT CONFIG_MINIMAL_LIBCPP
   AND NOT CONFIG_NATIVE_LIBRARY
   # When new link principle is fully introduced, then the below condition can
   # be removed, and instead the external module c++ should use:
   # set_property(TARGET linker PROPERTY c++_library  "<external_c++_lib>")
   AND NOT CONFIG_EXTERNAL_MODULE_LIBCPP
)
  set_property(TARGET linker PROPERTY link_order_library "c++")
endif()

set_property(TARGET linker APPEND PROPERTY link_order_library "c;rt")
CMAKE_EOF
  echo "PATCHED: $LLD_LIBS (backup at ${LLD_LIBS}.bak)"
fi

# ---------------------------------------------------------------------------
# Patch 3: Symlink ld.lld into SDK's cross-compiler bin directory
# ---------------------------------------------------------------------------
SDK_BIN="$SDK_DIR/arm-zephyr-eabi/arm-zephyr-eabi/bin"
LLD_SYMLINK="$SDK_BIN/ld.lld"

if [ -f "$LLD_SYMLINK" ] || [ -L "$LLD_SYMLINK" ]; then
  echo "SKIP: $LLD_SYMLINK already exists."
else
  ln -sf "$LLD_BIN" "$LLD_SYMLINK"
  echo "SYMLINKED: $LLD_SYMLINK -> $LLD_BIN"
fi

# ---------------------------------------------------------------------------
echo ""
echo "Setup complete. You can now build with lld:"
echo "  west build -p always -b bbc_microbit_v2 -d build_lld . -- -DUSE_LLD=ON"
