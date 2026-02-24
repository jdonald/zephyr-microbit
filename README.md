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

## Building with lld linker

The project supports building with LLVM's `ld.lld` linker while retaining
the GCC compiler from the Zephyr SDK.  This required solving three
incompatibilities between Zephyr's lld module (designed for clang) and GCC.

### Prerequisites for lld

- **lld >= 14.0** installed on the system (`apt install lld` or
  `brew install llvm`)
- One-time setup to patch the Zephyr tree and SDK (see below)

### Setup

Run the provided setup script to apply the required patches:

```bash
export ZEPHYR_BASE=~/zephyrproject/zephyr   # adjust if needed
./scripts/setup_lld.sh
```

The script applies three non-destructive, reversible patches:

1. **`cmake/linker/lld/gcc/linker_flags.cmake`** (new file in Zephyr tree) —
   bridges the lld linker module with GCC-specific flags (`-specs=`,
   `-gdwarf-4`).  Mirrors `ld/gcc/linker_flags.cmake` for the lld case.

2. **`cmake/linker/lld/linker_libraries.cmake`** (patched in Zephyr tree) —
   sets the runtime library to `-lgcc` when the compiler is GCC (the
   original sets it to `""` for clang/compiler-rt).

3. **`ld.lld` symlink** in the SDK's `arm-zephyr-eabi/arm-zephyr-eabi/bin/`
   — GCC's `collect2` must find `ld.lld` in its toolchain search path.

### Building with lld

```bash
west build -p always -b bbc_microbit_v2 -d build_lld . -- -DUSE_LLD=ON
```

When `USE_LLD=ON`, the build activates a custom toolchain variant
(`zephyr_lld`) that wraps the standard Zephyr SDK and overrides `LINKER`
from `ld` to `lld`.  This causes Zephyr's `cmake/linker/lld/` module to be
used, which:

- selects `-fuse-ld=lld` for both link steps
- preprocesses linker scripts with `__LLD_LINKER_CMD__` (avoiding GNU ld
  extensions like `ALIGN_WITH_INPUT`)
- uses lld-compatible flags (`--sort-section=alignment` instead of
  `--sort-common=descending`)

Verify with:

```bash
grep -o 'fuse-ld=[a-z]*' build_lld/build.ninja | sort | uniq -c
#   2 fuse-ld=lld
```

### How it works — three remediation paths

Zephyr's lld linker module was designed for clang+lld.  Using GCC+lld
required solving three problems:

| # | Problem | Solution |
|---|---------|----------|
| 1 | SDK unconditionally sets `LINKER=ld` | Custom toolchain variant (`cmake/toolchain/zephyr_lld/`) includes SDK then overrides `LINKER=lld` |
| 2 | `ALIGN_WITH_INPUT` in linker scripts rejected by lld | Solved by (1): the lld module preprocesses with `__LLD_LINKER_CMD__` and `linker-tool-lld.h` removes `ALIGN_WITH_INPUT` |
| 3 | Missing `-lgcc`, `-specs=` when lld module is active | Zephyr tree patches: `lld/gcc/linker_flags.cmake` + `lld/linker_libraries.cmake` |

### Undoing the patches

```bash
rm  "$ZEPHYR_BASE/cmake/linker/lld/gcc/linker_flags.cmake"
git -C "$ZEPHYR_BASE" checkout cmake/linker/lld/linker_libraries.cmake
rm  "$ZEPHYR_SDK_INSTALL_DIR/arm-zephyr-eabi/arm-zephyr-eabi/bin/ld.lld"
```

## Project structure

```
.
├── CMakeLists.txt                        # Build configuration; USE_LLD knob
├── prj.conf                              # Zephyr Kconfig (display, sensor, entropy)
├── src/
│   └── main.c                            # Game logic, physics, rendering
├── cmake/
│   ├── toolchain/zephyr_lld/             # Custom toolchain variant (Path 1)
│   │   ├── generic.cmake                 #   wraps SDK, sets LINKER=lld
│   │   └── target.cmake                  #   wraps SDK target setup
│   ├── compiler/gcc/                     # Forwarding modules (TOOLCHAIN_ROOT compat)
│   │   ├── generic.cmake
│   │   ├── target.cmake
│   │   └── compiler_flags.cmake
│   ├── linker/
│   │   ├── lld/
│   │   │   ├── target.cmake
│   │   │   ├── linker_flags.cmake
│   │   │   └── linker_libraries.cmake
│   │   └── target_template.cmake
│   └── bintools/gnu/
│       └── target.cmake
├── scripts/
│   └── setup_lld.sh                      # One-time Zephyr/SDK patching
├── .gitignore
├── LICENSE                               # MIT
└── README.md                             # This file
```

## License

MIT — see [LICENSE](LICENSE).
