# Pre-locate ld.lld before Zephyr's FindLlvmLld.cmake runs.
#
# Zephyr's FindLlvmLld.cmake restricts its search to TOOLCHAIN_HOME (the SDK
# directory) when that variable is set, using NO_DEFAULT_PATH.  With a GCC
# toolchain, the SDK ships ld.bfd but not ld.lld, so the search fails.
#
# We broaden the search: first check the SDK bin directory (where
# setup_lld.sh creates a symlink), then fall back to standard system paths.
# Setting LLVMLLD_LINKER as a CACHE variable satisfies FindLlvmLld.cmake.

if(NOT DEFINED LLVMLLD_LINKER OR NOT EXISTS "${LLVMLLD_LINKER}")
  # Clear any non-existent cached value so find_program can do its job.
  unset(LLVMLLD_LINKER CACHE)

  # 1) Look in the SDK's cross-compiler bin directory first (setup_lld.sh symlink).
  find_program(_marble_lld_candidate ld.lld
    PATHS "${ZEPHYR_SDK_INSTALL_DIR}/arm-zephyr-eabi/arm-zephyr-eabi/bin"
    NO_DEFAULT_PATH)

  # 2) Fall back to system-wide search (apt install lld, LLVM download, etc.)
  if(NOT _marble_lld_candidate)
    find_program(_marble_lld_candidate ld.lld)
  endif()

  if(_marble_lld_candidate)
    set(LLVMLLD_LINKER "${_marble_lld_candidate}" CACHE FILEPATH "Path to ld.lld" FORCE)
  endif()
  unset(_marble_lld_candidate CACHE)
endif()

# Forward to Zephyr's lld linker target module.
include(${ZEPHYR_BASE}/cmake/linker/lld/target.cmake)
