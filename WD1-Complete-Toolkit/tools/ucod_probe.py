#!/usr/bin/env python3
"""UCOD patch.dat/fat structural probe (route-2, offline file patch line).

Verified layout (2026-09-17, against user-supplied UCOD 1.1 files):
- .fat: magic '3TAF' (0x46415433 LE), u32 version=8, u32 0x00320504, u32 count,
  count * (u32 nameHashCRC, u32 flags, u32 uncSize, u32 offDiv8?), u32 zero tail.
  NOTE: off field reads as physical_offset/8 for the 45 TBX shards.
- .dat: 45 consecutive TBX shards, each exactly 32,944 bytes, UNCOMPRESSED,
  then one 948,428-byte tail blob, ALSO UNCOMPRESSED (plain strings visible).
- DB content: Dunia object records: [name]\0 + hash runs (c75c29b904, a76d9f3804,
  4474fb4312=len+TypeName) + TypeName\0 + property stream (5-byte key refs
  [crc32 + 0x04] followed by typed values incl. f32 prices).
- 52 ItemDescriptorCar records, all named CarHackingRewards.Generic.*; each paired
  with ItemDescriptorCarNoLoadResources. 51/74 of our catalog car keys appear as
  u32 LE inside the shard region, each within 400B of a car anchor.
- 72 bytes after each 'ItemDescriptorCar\\0' anchor are identical across records
  (partner-object link), so per-car properties must live in the stream after the
  NoLoadResources partner / or in separate property objects.

Usage: python3 ucod_probe.py <patch.fat> <patch.dat>
"""
import struct, sys, re

def main(fat_path, dat_path):
    fat = open(fat_path, 'rb').read()
    dat = open(dat_path, 'rb').read()
    magic, ver, unk, count = struct.unpack_from('<IIII', fat, 0)
    print(f'fat: magic={magic:#x} ver={ver} unk={unk:#x} count={count}')
    ents = [struct.unpack_from('<IIII', fat, 0x10 + i*16) for i in range(count)]
    for i, (h, fl, unc, off) in enumerate(ents):
        print(f'{i:2d} hash={h:08x} flags={fl} unc={unc:8d} off8={off:8d} off={off*8:9d}')
    tbx_end = 45 * 32944
    region = dat[:tbx_end]
    anchors = [m.start() for m in re.finditer(rb'ItemDescriptorCar\x00', region)]
    print(f'TBX shards end at {tbx_end}; tail blob {len(dat)-tbx_end} bytes')
    print(f'ItemDescriptorCar anchors: {len(anchors)}')
    for a in anchors[:5]:
        st = region.rfind(b'\x00', 0, a - 20)
        print('  ...', region[st-80:st].decode('latin1', errors='replace')[-60:])
    blocks = [region[a+18:a+18+72] for a in anchors]
    diffs = [j for j in range(72) if len({b[j] for b in blocks}) > 1]
    print('post-anchor 72B diff positions:', diffs, '(empty = uniform partner link)')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
