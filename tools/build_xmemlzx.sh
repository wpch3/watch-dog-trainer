#!/bin/sh
# Build the XMem-LZX chunk decoder used by dunia_fat.py (libmspack lzxd).
cd "$(dirname "$0")"
gcc -O2 -o xmemlzx lzxd_src/xmemlzx.c lzxd_src/lzxd.c -Ilzxd_src
