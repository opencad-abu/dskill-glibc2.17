# dskill — Cadence SKILL Decompiler & Decrypt

**Authors:** 阿布 (Abu) & OCAD  
**Version:** 1.0.0

## Overview

dskill is a unified tool for working with Cadence SKILL files:
- **Decrypt** encrypted `.ile` files to readable `.il` source
- **Decompile** compiled `.cxt` (context) files back to SKILL source code

## Build

```bash
./build.sh
```

Requires: g++ (C++17), libstdc++fs

## Usage

### Decrypt ILE files

```bash
dskill -ile -i <input.ile> [-f <output.il>]
```

- `-i` — Input `.ile` file (required)
- `-f` — Output `.il` file (optional, defaults to stdout)

### Decompile CXT files

```bash
dskill -cxt -i <input.cxt> [-d <output_dir>] [-m <max_funcs>] [-n <func_name>]
```

- `-i` — Input `.cxt` file (required)
- `-d` — Output directory (default: `./output`)
- `-m` — Maximum number of functions to process (default: all)
- `-n` — Process only a specific named function

### Other

```bash
dskill -h | --help      # Show help
dskill -V | --version   # Show version
```

## Examples

```bash
# Decrypt an encrypted SKILL file
dskill -ile -i tslPostOA.ile -f tslPostOA.il

# Decompile all functions from a context file
dskill -cxt -i pdkUtils64bit.cxt -d ./output

# Decompile only 10 functions for quick inspection
dskill -cxt -i pdkUtils64bit.cxt -d ./output -m 10

# Decompile a specific function by name
dskill -cxt -i pdkUtils64bit.cxt -d ./output -n myFunction
```

## Output

Decompiled functions are written as individual `.il` files in the output directory.
- Named functions: `<function_name>.il`
- Lambda (unnamed) functions: `func_N.il`

## Notes

- Context (.cxt) files are binary snapshots of the SKILL interpreter state
- Some bytecode patterns may not be fully recognized, resulting in `nil` placeholders
- Lambda functions (unnamed function objects) are decompiled as `(lambda (args) body...)`

## Platform Support

| Platform | GLIBC | Status |
|----------|-------|--------|
| RHEL 8+ / Rocky 8+ | ≥ 2.28 | ✅ Pre-built binary works |
| Ubuntu 20.04+ | ≥ 2.31 | ✅ Pre-built binary works |
| RHEL 7 | 2.17 | ⚠️ Build from source (see below) |

### RHEL 7 Build

```bash
# Requires devtoolset for C++17 support
yum install devtoolset-11
scl enable devtoolset-11 bash
cd /path/to/dskill && bash build.sh
```

## Implementation

See [PRINCIPLE.md](PRINCIPLE.md) for detailed implementation principles.
