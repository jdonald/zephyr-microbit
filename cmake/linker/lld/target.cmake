# Pre-locate ld.lld before Zephyr's FindLlvmLld.cmake runs.
#
# Zephyr's FindLlvmLld.cmake restricts its search to TOOLCHAIN_HOME (the SDK
# directory) when that variable is set, using NO_DEFAULT_PATH.  With a GCC
# toolchain, the SDK ships ld.bfd but not ld.lld, so the search fails.
#
# We broaden the search: SDK bin dir → Xcode toolchain → system paths.
# Setting LLVMLLD_LINKER as a CACHE variable satisfies FindLlvmLld.cmake.

if(NOT DEFINED LLVMLLD_LINKER OR NOT EXISTS "${LLVMLLD_LINKER}")
  # Clear any non-existent cached value so find_program can do its job.
  unset(LLVMLLD_LINKER CACHE)

  # 1) Look in the SDK's cross-compiler bin directory (setup_lld.sh symlink).
  find_program(_marble_lld_candidate ld.lld
    PATHS "${ZEPHYR_SDK_INSTALL_DIR}/arm-zephyr-eabi/arm-zephyr-eabi/bin"
    NO_DEFAULT_PATH)

  # 2) Try Xcode / Command Line Tools toolchain (macOS).
  if(NOT _marble_lld_candidate AND CMAKE_HOST_APPLE)
    # xcrun is the canonical way to locate Xcode tools.
    execute_process(
      COMMAND xcrun --find ld.lld
      OUTPUT_VARIABLE _xcrun_lld
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET
      RESULT_VARIABLE _xcrun_rc)
    if(_xcrun_rc EQUAL 0 AND EXISTS "${_xcrun_lld}")
      set(_marble_lld_candidate "${_xcrun_lld}")
    else()
      # Direct path checks as fallback
      find_program(_marble_lld_candidate ld.lld
        PATHS
          "/Library/Developer/CommandLineTools/usr/bin"
          "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
        NO_DEFAULT_PATH)
    endif()
  endif()

  # 3) Fall back to system-wide search (apt install lld, etc.)
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
