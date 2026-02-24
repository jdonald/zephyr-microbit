# SPDX-License-Identifier: MIT
#
# Custom toolchain variant: Zephyr SDK GCC compiler + LLVM lld linker.
#
# This wraps the standard "zephyr" toolchain and overrides LINKER from "ld"
# to "lld" so that Zephyr's cmake/linker/lld/ module is selected.

include(${ZEPHYR_SDK_INSTALL_DIR}/cmake/zephyr/generic.cmake)

# Override the linker set by the SDK's generic.cmake.
set(LINKER lld)
