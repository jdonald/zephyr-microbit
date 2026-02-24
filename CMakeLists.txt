cmake_minimum_required(VERSION 3.20.0)

# ---------------------------------------------------------------------------
# Option to use LLVM's lld linker (with GCC compiler).
# Usage: west build ... -- -DUSE_LLD=ON
#
# When enabled, a custom toolchain variant "zephyr_lld" is activated.  It
# extends the standard Zephyr SDK but overrides LINKER from "ld" to "lld",
# which causes Zephyr's cmake/linker/lld/ module to be loaded.  That module
# selects -fuse-ld=lld, preprocesses linker scripts with __LLD_LINKER_CMD__
# (avoiding GNU ld extensions like ALIGN_WITH_INPUT), and sets lld-compatible
# linker flags.
#
# Requires ld.lld visible to GCC's collect2 (see README.md).
# ---------------------------------------------------------------------------
option(USE_LLD "Use LLVM lld linker (-fuse-ld=lld) instead of default ld.bfd" OFF)

if(USE_LLD)
  message(STATUS ">>> Marble Game: selecting LLVM lld linker via zephyr_lld toolchain variant")

  # Zephyr's FindZephyr-sdk.cmake only auto-discovers the SDK when
  # ZEPHYR_TOOLCHAIN_VARIANT is "zephyr" or unset.  Our custom variant
  # name "zephyr_lld" skips that logic, so we must ensure
  # ZEPHYR_SDK_INSTALL_DIR is defined before find_package(Zephyr).
  if(NOT DEFINED ZEPHYR_SDK_INSTALL_DIR)
    if(DEFINED ENV{ZEPHYR_SDK_INSTALL_DIR})
      set(ZEPHYR_SDK_INSTALL_DIR $ENV{ZEPHYR_SDK_INSTALL_DIR})
    else()
      # Read the cmake package registry (populated by the SDK's setup.sh).
      file(GLOB _zephyr_sdk_registry_files
           "$ENV{HOME}/.cmake/packages/Zephyr-sdk/*"
           "/root/.cmake/packages/Zephyr-sdk/*")
      foreach(_reg_file ${_zephyr_sdk_registry_files})
        file(READ "${_reg_file}" _sdk_cmake_path)
        string(STRIP "${_sdk_cmake_path}" _sdk_cmake_path)
        cmake_path(GET _sdk_cmake_path PARENT_PATH _sdk_dir_candidate)
        if(EXISTS "${_sdk_dir_candidate}/cmake/zephyr/generic.cmake")
          set(ZEPHYR_SDK_INSTALL_DIR "${_sdk_dir_candidate}")
          break()
        endif()
      endforeach()
    endif()
  endif()

  if(NOT DEFINED ZEPHYR_SDK_INSTALL_DIR)
    message(FATAL_ERROR
      "USE_LLD=ON requires the Zephyr SDK location.\n"
      "Set ZEPHYR_SDK_INSTALL_DIR as an environment variable or cmake "
      "variable (-DZEPHYR_SDK_INSTALL_DIR=...), or run the SDK's setup.sh "
      "to register it in the cmake package registry.")
  endif()

  # Point Zephyr at this project's cmake/ tree so it finds our custom
  # toolchain variant under cmake/toolchain/zephyr_lld/.
  list(APPEND TOOLCHAIN_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
  set(ZEPHYR_TOOLCHAIN_VARIANT "zephyr_lld")
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(marble_game)

target_sources(app PRIVATE src/main.c)

if(USE_LLD)
  # Zephyr's picolibc hooks re-define __retarget_lock_* symbols that also
  # exist in the SDK's picolibc libc.a.  GNU ld resolves these silently
  # via archive-member selection; lld treats them as duplicate definitions.
  zephyr_link_libraries(-Wl,--allow-multiple-definition)
endif()
