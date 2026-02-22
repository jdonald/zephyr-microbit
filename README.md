# Marble Game — micro:bit V2 on Zephyr RTOS

A tilt-controlled marble puzzle for the BBC micro:bit V2, built with
[Zephyr RTOS](https://zephyrproject.org/).

The 5×5 LED grid shows a marble and a walled receptacle (open on one side).
Tilt the board to roll the marble into the receptacle — bigger tilts mean
faster rolling, and diagonal motion works naturally. When you succeed, a
star graphic flashes three times and a new random level is generated.

## Prerequisites

| Tool | Tested version | Notes |
|------|----------------|-------|
| [Zephyr SDK](https://github.com/zephyrproject-rtos/sdk-ng/releases) | 0.17.0 | Includes the `arm-zephyr-eabi` GCC toolchain |
| [west](https://docs.zephyrproject.org/latest/develop/west/index.html) | 1.5+ | `pip install west` |
| [CMake](https://cmake.org/) | 3.20+ | |
| [Ninja](https://ninja-build.org/) | 1.10+ | |
| Python 3 | 3.10+ | Required by west and Zephyr scripts |

### Platform notes

These instructions work on **Linux** (x86-64) and **macOS** (Intel or Apple
Silicon). On macOS replace `apt` commands with the Homebrew equivalents
(`brew install cmake ninja`). The Zephyr SDK provides pre-built toolchains for
both platforms.

## Setting up the Zephyr workspace

If you don't already have a Zephyr workspace, create one:

```bash
# 1. Install west
pip3 install west

# 2. Initialize a workspace (uses Zephyr v4.0.0)
west init -m https://github.com/zephyrproject-rtos/zephyr --mr v4.0.0 ~/zephyrproject
cd ~/zephyrproject
west update

# 3. Export Zephyr to the CMake package registry
west zephyr-export

# 4. Install Zephyr's Python dependencies
pip3 install -r zephyr/scripts/requirements.txt
```

### Installing the Zephyr SDK

Download and install from
<https://github.com/zephyrproject-rtos/sdk-ng/releases>:

```bash
# Linux example (adjust version / arch as needed)
cd /opt
wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz
tar xf zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz
cd zephyr-sdk-0.17.0
./setup.sh -t arm-zephyr-eabi -c
```

On **macOS** use the `_macos-*` archive from the same releases page and
run the same `./setup.sh` command.

## Building (default — ld.bfd linker)

```bash
export ZEPHYR_BASE=~/zephyrproject/zephyr   # adjust if your workspace is elsewhere

# From the root of this repository:
west build -p always -b bbc_microbit_v2 .
```

The firmware image is produced at `build/zephyr/zephyr.hex`.

## Flashing

Connect the micro:bit V2 via USB. It appears as a USB mass-storage device.

```bash
west flash
```

Or manually copy the hex file:

```bash
cp build/zephyr/zephyr.hex /Volumes/MICROBIT/    # macOS
# cp build/zephyr/zephyr.hex /media/$USER/MICROBIT/  # Linux
```

## How to play

1. Power on the micro:bit — a marble (LED dot) and a receptacle (LED dot)
   appear at random positions.
2. The receptacle is walled on three sides. Observe its position along an
   edge to infer which side is open.
3. Tilt the board to roll the marble. Greater tilt = faster motion.
   Diagonal tilting works — the marble moves in the combined direction.
4. The edges of the 5×5 grid act as walls; the marble cannot roll off.
5. Guide the marble into the receptacle through its open side.
6. On success a star pattern flashes three times (~1 s), then a new level
   starts automatically.

## Validating the build

After building, you can inspect `build/build.ninja` to confirm that both
link steps (the intermediate `zephyr_pre0.elf` and the final `zephyr.elf`)
use the expected linker:

```bash
grep -o 'fuse-ld=[a-z]*' build/build.ninja | sort | uniq -c
#   2 fuse-ld=bfd       ← default build
```

---

## Experimental: lld Linker

The project includes a `USE_LLD` CMake option for experimenting with LLVM's
`ld.lld` linker while retaining the GCC compiler from the Zephyr SDK.

### How it works

```bash
west build -p always -b bbc_microbit_v2 -d build_lld . -- -DUSE_LLD=ON
```

When `USE_LLD=ON`, the `CMakeLists.txt`:

1. **Patches the `sort_alignment` linker property** — removes
   `--sort-common=descending` (a GNU ld extension unsupported by lld) while
   keeping `--sort-section=alignment` (supported by both).
2. **Appends `-fuse-ld=lld`** after Zephyr's `-fuse-ld=bfd` via
   `zephyr_link_libraries()`. GCC honours the *last* `-fuse-ld=` flag, so
   lld takes precedence.

You can verify the flags in `build_lld/build.ninja`:

```bash
grep -o 'fuse-ld=[a-z]*' build_lld/build.ninja | sort | uniq -c
#   2 fuse-ld=bfd       ← Zephyr's default (appears first)
#   2 fuse-ld=lld       ← our override  (appears last — wins)
```

### Prerequisites for lld

The system `ld.lld` must be discoverable by GCC's `collect2`. This means
placing (or symlinking) `ld.lld` into the Zephyr SDK's linker search path:

```bash
# Example — adjust SDK path as appropriate
ln -sf $(which ld.lld) \
  /path/to/zephyr-sdk-0.17.0/arm-zephyr-eabi/arm-zephyr-eabi/bin/ld.lld
```

### Current status: linker-script incompatibility (blocker)

As of Zephyr v4.0.0 the lld build **does not yet link successfully** due to
a fundamental mismatch between Zephyr's linker-script preprocessing and the
linker that is actually invoked:

| Aspect | `LINKER=ld` (default) | `LINKER=lld` (Zephyr's own lld module) |
|--------|----------------------|----------------------------------------|
| Preprocessor define | `__GCC_LINKER_CMD__` | `__LLD_LINKER_CMD__` |
| Linker-script syntax | GNU ld extensions (`ALIGN_WITH_INPUT`, etc.) | lld-compatible subset |
| Loaded by | `cmake/linker/ld/target.cmake` | `cmake/linker/lld/target.cmake` |

Because the Zephyr SDK unconditionally sets `LINKER=ld` in
`<sdk>/cmake/zephyr/generic.cmake` (a non-cache `set()` that overrides any
prior cache value), the linker scripts are always preprocessed with
`__GCC_LINKER_CMD__` — producing GNU ld syntax that lld rejects:

```
ld.lld: error: linker_zephyr_pre0.cmd:105: { expected, but got ALIGN_WITH_INPUT
>>>  app_shmem_regions : ALIGN_WITH_INPUT
```

### Paths to investigate next

1. **Custom toolchain variant** — Create a thin
   `cmake/toolchain/zephyr_lld/generic.cmake` that `include()`s the SDK's
   `generic.cmake` and then resets `LINKER` to `lld`. This would cause
   Zephyr's own `cmake/linker/lld/target.cmake` to be used, which
   preprocesses linker scripts with `__LLD_LINKER_CMD__` and emits
   lld-compatible flags.  The trade-off is that `lld/target.cmake` calls
   `find_package(LlvmLld 14.0.0 REQUIRED)`, so a system lld ≥ 14 is
   required.

2. **Patch the SDK's `generic.cmake`** — Change the unconditional
   `set(LINKER ld)` to `set_ifndef(LINKER ld)` so that a cache variable set
   by the application or on the command line is respected.  This is arguably
   the cleanest upstream fix.

3. **Board-level linker-script overlay** — Provide a board overlay that
   wraps `ALIGN_WITH_INPUT` and other GNU ld extensions behind
   `#ifdef __GCC_LINKER_CMD__` guards.  This is fragile but could unblock
   the link step without changing the Zephyr SDK.

## Project structure

```
.
├── CMakeLists.txt   # Build configuration; USE_LLD knob
├── prj.conf         # Zephyr Kconfig (display, sensor, entropy)
├── src/
│   └── main.c       # Game logic, physics, rendering
├── .gitignore
├── LICENSE           # MIT
└── README.md         # This file
```

## License

MIT — see [LICENSE](LICENSE).
