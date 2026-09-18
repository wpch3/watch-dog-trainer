#!/usr/bin/env python3
"""WD1 (Disrupt) FAT3 v8 archive extractor.

Format (validated against vanilla build 11241563 + UCOD mod pair):
  fat:  'FAT3' u32 version=8 u32 flags(plat<<0|cv<<8|nhv<<16) u32 count
        then count * 16B entries:
            a u32 nameHash (sorted ascending)
            b u32 (uncompressedSize29 << 3) | scheme3
            c u32 ((offset & 7) << 29) | compressedSize29
            d u32 offset >> 3                       -> offset = (d<<3)|(c>>29)
        then u32 zero tail
  scheme (compressionVersion=5): 0=None, 1=LZO1x, 2=Zlib, 3=XMemCompress(LZX)
  scheme3 block (big-endian):
            +00 u32 magic 0x0FF512EE
            +04 u32 version 0x01030000
            +08 u32 0 / +0C u32 0
            +10 u32 windowSize  (bits = log2, e.g. 32768 -> 15)
            +14 u32 chunkSize
            +18 u64 uncompressedSize (== entry uncompressedSize)
            +20 u64 compressedSize
            +28 u32 largestUncompressedChunkSize
            +2C u32 largestCompressedChunkSize
            then chunks: [u32 BE compressedChunkSize][chunk payload]
  chunk payload = sequence of sub-blocks consumed by LZX reader:
            FF + u16 BE uncompressedSize + u16 BE compressedSize + data
            or u16 BE compressedSize + data
  sub-block data = standard LZX bitstream (mspack lzxd, window_bits=15,
  reset_interval=0, output_length = chunk uncompressed size).

Usage: python3 dunia_fat.py <archive.dat> <archive.fat> <outdir>
"""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
XMEMLZX = os.path.join(HERE, 'xmemlzx')


def read_fat(fat_path):
    fat = open(fat_path, 'rb').read()
    assert fat[:4] == b'3TAF', 'not a FAT3 archive'
    version = struct.unpack_from('<I', fat, 4)[0]
    flags = struct.unpack_from('<I', fat, 8)[0]
    count = struct.unpack_from('<I', fat, 12)[0]
    assert version == 8, f'unsupported fat version {version}'
    entries = []
    for i in range(count):
        a, b, c, d = struct.unpack_from('<IIII', fat, 0x10 + i * 16)
        entries.append({
            'nameHash': a,
            'uncSize': (b >> 3) & 0x1FFFFFFF,
            'scheme': b & 7,
            'compressedSize': c & 0x1FFFFFFF,
            'offset': (d << 3) | (c >> 29),
        })
    return version, flags, entries


def lzx_chunk(payload, window_bits, outlen, workdir='/tmp'):
    src = os.path.join(workdir, '_wdlzx_in.bin')
    dst = os.path.join(workdir, '_wdlzx_out.bin')
    with open(src, 'wb') as f:
        f.write(payload)
    if os.path.exists(dst):
        os.unlink(dst)
    r = subprocess.run([XMEMLZX, src, dst, str(window_bits), str(outlen)],
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f'lzx fail rc={r.returncode} {r.stderr[:120]!r}')
    out = open(dst, 'rb').read()
    if len(out) != outlen:
        raise RuntimeError(f'lzx short {len(out)}!={outlen}')
    return out


def decode_entry(dat, e, workdir='/tmp'):
    off, unc, comp, scheme = e['offset'], e['uncSize'], e['compressedSize'], e['scheme']
    if scheme == 0:
        # stored: Gibbed writes CompressedSize bytes (UncompressedSize may be 0)
        return dat[off:off + comp]
    if unc == 0:
        return b''
    if scheme != 3:
        raise RuntimeError(f'unsupported scheme {scheme}')
    p = off
    assert int.from_bytes(dat[p:p + 4], 'big') == 0x0FF512EE, 'bad block magic'
    window_size = int.from_bytes(dat[p + 16:p + 20], 'big')
    us = int.from_bytes(dat[p + 24:p + 32], 'big')
    luc = int.from_bytes(dat[p + 40:p + 44], 'big')
    assert us == unc, (us, unc)
    wb = window_size.bit_length() - 1
    p += 48
    out = bytearray()
    while len(out) < us:
        clen = int.from_bytes(dat[p:p + 4], 'big')
        p += 4
        want = min(luc, us - len(out))
        out += lzx_chunk(dat[p:p + clen], wb, want, workdir)
        p += clen
    assert len(out) == us
    return bytes(out)


def main():
    dat_path, fat_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    dat = open(dat_path, 'rb').read()
    version, flags, entries = read_fat(fat_path)
    print(f'FAT3 v{version} flags={flags:08x} entries={len(entries)}')
    ok = 0
    for i, e in enumerate(entries):
        try:
            data = decode_entry(dat, e)
        except Exception as ex:
            print(f'[{i}] hash={e["nameHash"]:08x} FAILED: {ex}')
            continue
        ok += 1
        with open(os.path.join(outdir, f'{e["nameHash"]:08x}.bin'), 'wb') as f:
            f.write(data)
    print(f'decoded {ok}/{len(entries)} -> {outdir}')


if __name__ == '__main__':
    main()
