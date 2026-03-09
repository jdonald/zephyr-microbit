# Marble Game — micro:bit V2 on Zephyr RTOS

A tilt-controlled marble puzzle for the BBC micro:bit V2, built with
[Zephyr RTOS](https://zephyrproject.org/).

The 5×5 LED grid shows a marble and a walled receptacle (open on one side).
The receptacle is drawn as a cluster of dots — three wall pixels surround
the centre, with a visible gap on the open side.  Tilt the board to roll
the marble into the receptacle through the gap — bigger tilts mean faster
rolling, and diagonal motion works naturally.  When you succeed, a star
graphic flashes three times and a new random level is generated.

## Prerequisites

| Tool | Tested version | Notes |
|------|----------------|-------|
| Python 3 | 3.10+ | Required by west and Zephyr scripts |
| [west](https://docs.zephyrproject.org/latest/develop/west/index.html) | 1.5+ | `pip install west` |
| [CMake](https://cmake.org/) | 3.20+ | `pip install cmake` |
| [Ninja](https://ninja-build.org/) | 1.10+ | `pip install ninja` |
| [Zephyr SDK](https://github.com/zephyrproject-rtos/sdk-ng/releases) | 0.17.0 | Includes the `arm-zephyr-eabi` GCC toolchain |

All Python packages (`west`, `cmake`, `ninja`) can be installed with pip in
a single command — no OS-level package manager (Homebrew, MacPorts, apt)
is required for these tools.

### Platform notes

These instructions work on **Linux** (x86-64) and **macOS** (Intel or Apple
Silicon) without requiring Homebrew or MacPorts.  The Zephyr SDK provides
pre-built GCC toolchains for both platforms.

## Setting up the Zephyr workspace

> **Disk space warning:** `west update` downloads the Zephyr tree plus all
> module repositories.  Expect roughly **13–15 GB** of disk usage for the
> full workspace.  Make sure you have sufficient free space before
> proceeding.

Create a Python virtual environment (recommended) and install the tools:

```bash
# 0. Create and activate a virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# 1. Install west, cmake, and ninja via pip
pip install west cmake ninja
```

Then initialise the workspace:

```bash
# 2. Initialize a workspace (uses Zephyr v4.0.0)
west init -m https://github.com/zephyrproject-rtos/zephyr --mr v4.0.0 ~/zephyrproject
cd ~/zephyrproject
west update            # downloads ~13 GB of source code and modules

# 3. Export Zephyr to the CMake package registry
west zephyr-export

# 4. Install Zephyr's Python dependencies
pip install -r zephyr/scripts/requirements.txt
```

### Installing the Zephyr SDK

Download the **minimal** SDK from
<https://github.com/zephyrproject-rtos/sdk-ng/releases>.

#### Linux

```bash
cd /opt   # or any directory you prefer
wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz
tar xf zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz
cd zephyr-sdk-0.17.0
./setup.sh -t arm-zephyr-eabi -c
```

#### macOS

The SDK's `setup.sh` uses `wget`, which is not installed by default on
macOS.  The simplest workaround is a small wrapper script that translates
`wget` calls to `curl`:

```bash
# Create a temporary wget wrapper (only needed during SDK setup)
cat > /tmp/wget-wrapper.sh << 'WRAPPER'
#!/bin/bash
output_file="" ; url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -O) output_file="$2"; shift ;;
     *) url="$1" ;;
  esac; shift
done
if [[ -n "$url" ]]; then
  if [[ -n "$output_file" ]]; then exec curl -L -o "$output_file" "$url"
  else exec curl -L -O "$url"; fi
else echo "Usage: $0 [-O <file>] <URL>" >&2; exit 1; fi
WRAPPER
chmod +x /tmp/wget-wrapper.sh
```

Then download and install:

```bash
cd ~/zephyr-microbit   # or any directory you prefer
curl -L -O https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_macos-x86_64_minimal.tar.xz
# Apple Silicon: use zephyr-sdk-0.17.0_macos-aarch64_minimal.tar.xz instead
tar xf zephyr-sdk-0.17.0_macos-*_minimal.tar.xz
cd zephyr-sdk-0.17.0

# Run setup with the wget wrapper on PATH so setup.sh can find "wget"
PATH="/tmp:$PATH" ln -sf /tmp/wget-wrapper.sh /tmp/wget
./setup.sh -t arm-zephyr-eabi -c
```

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

1. Power on the micro:bit — a marble (single LED dot) and a receptacle
   appear at random positions.
2. The receptacle is drawn as a cluster of dots: three wall pixels surround
   the centre, with a gap on the open side.  The gap shows you where to
   aim.
3. Tilt the board to roll the marble. Greater tilt = faster motion.
   Diagonal tilting works — the marble moves in the combined direction.
4. The edges of the 5×5 grid act as walls; the marble cannot roll off.
5. Guide the marble into the receptacle centre through the open side.
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

- **lld >= 14.0** installed on the system:
  - **Linux:** `sudo apt install lld` (Debian/Ubuntu) or equivalent
  - **macOS:** download pre-built LLVM binaries from
    <https://github.com/llvm/llvm-project/releases> (look for
    `clang+llvm-*-arm64-apple-macosx*.tar.xz` for Apple Silicon or the
    `x86_64` variant for Intel).  Extract the archive — `ld.lld` is in
    the `bin/` directory.
- One-time setup to patch the Zephyr tree and SDK (see below)

### Setup

Run the provided setup script to apply the required patches:

```bash
export ZEPHYR_BASE=~/zephyrproject/zephyr   # adjust if needed

# Linux (ld.lld is on PATH after 'apt install lld'):
./scripts/setup_lld.sh

# macOS (point to the ld.lld from your LLVM download):
LLD_PATH=/path/to/clang+llvm/bin/ld.lld ./scripts/setup_lld.sh
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
│   │   │   ├── target.cmake              #   pre-locates ld.lld, then forwards
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
