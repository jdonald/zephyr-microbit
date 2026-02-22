cmake_minimum_required(VERSION 3.20.0)

# ---------------------------------------------------------------------------
# Option to use LLVM's lld linker (experimental — with GCC compiler).
# Usage: west build ... -- -DUSE_LLD=ON
#
# See README.md § "Experimental: lld Linker" for details and caveats.
# ---------------------------------------------------------------------------
option(USE_LLD "Use LLVM lld linker (-fuse-ld=lld) instead of default ld.bfd" OFF)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(marble_game)

target_sources(app PRIVATE src/main.c)

if(USE_LLD)
  message(STATUS ">>> Marble Game: appending -fuse-ld=lld to override ld.bfd")

  # Zephyr's "ld" linker module adds --sort-common=descending which is a
  # GNU ld extension not supported by lld.  Replace the property to keep only
  # --sort-section=alignment (supported by both linkers).
  set_property(TARGET linker PROPERTY sort_alignment
    ${LINKERFLAGPREFIX},--sort-section=alignment)

  # Append -fuse-ld=lld *after* Zephyr's -fuse-ld=bfd.  GCC honours the last
  # -fuse-ld= flag, so this effectively switches the linker.
  zephyr_link_libraries(-fuse-ld=lld)
endif()
