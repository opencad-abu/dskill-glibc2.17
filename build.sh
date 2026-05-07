#!/bin/bash
# dskill build script
# Authors: 阿布 (Abu) & OCAD

set -e
cd "$(dirname "$0")/src"

echo "=== Building dskill ==="
g++ -o ../dskill \
    main.cpp \
    dskill_ile.cpp \
    ctx.cpp \
    print.cpp \
    transform.cpp \
    -g -O3 --std=c++17

echo "=== Build complete: ../dskill ==="
echo ""
echo "Usage:"
echo "  dskill -ile  -i <input.ile>  [-f <output.il>]"
echo "  dskill -cxt  -i <input.cxt>  [-d <output_dir>] [-m <max>]"
echo "  dskill -h | --help"
echo "  dskill -V | --version"
