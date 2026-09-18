#!/usr/bin/env python3
"""Route A v2: full replacement patch pair (community-validated install).

The WD1 engine ignores a patch2 slot (user-verified 2026-09-17). The
community flow (Nexus Mod Installer) merges mods INTO patch.dat/fat.
This tool reproduces that: take the vanilla patch pair, swap the car DB
entry (0x81165196) for the merged superset blob, keep every other entry's
compressed payload byte-identical, rebuild the fat (same hashes, same
order, same header flags).

Output: patch.dat/patch.fat (ours) + vanilla patch1 pair for a
consistent folder.

Usage: build_replacement_patch.py <van.dat> <van.fat> <van1.dat> <van1.fat> \
<ucod.dat> <ucod.fat> <outdir>
"""
import importlib.util
import os
import shutil
import struct
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


dunia_fat = _load('dunia_fat', os.path.join(_HERE, 'dunia_fat.py'))
bcp = _load('bcp', os.path.join(_HERE, 'build_car_patch.py'))

TARGET = bcp.HASH_FILE  # 0x81165196


def main():
    if len(sys.argv) != 8:
        print(__doc__)
        sys.exit(2)
    van_dat_p, van_fat_p, van1_dat_p, van1_fat_p, ucod_dat_p, ucod_fat_p, outdir = sys.argv[1:8]
    os.makedirs(outdir, exist_ok=True)

    blob = bcp.superset_blob(van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p)

    vdat = open(van_dat_p, 'rb').read()
    _, flags, vents = dunia_fat.read_fat(van_fat_p)

    out = bytearray()
    rows = []
    replaced = 0
    for e in vents:
        if e['nameHash'] == TARGET:
            payload = blob
            scheme = 0
            unc = len(blob)
            comp = len(blob)
            replaced += 1
        else:
            off = e['offset']
            payload = vdat[off:off + e['compressedSize']]
            assert len(payload) == e['compressedSize']
            scheme = e['scheme']
            unc = e['uncSize']
            comp = e['compressedSize']
        off_new = len(out)
        out += payload
        rows.append((e['nameHash'], unc, scheme, comp, off_new))
    assert replaced == 1
    assert len(out) == sum(r[3] for r in rows)

    fat = bytearray()
    fat += struct.pack('<4sIII', b'3TAF', 8, flags, len(rows))
    for h, unc, scheme, comp, off in rows:
        fat += struct.pack('<IIII', h,
                           ((unc & 0x1FFFFFFF) << 3) | (scheme & 7),
                           ((off & 7) << 29) | (comp & 0x1FFFFFFF),
                           off >> 3)
    fat += struct.pack('<I', 0)

    dat_path = os.path.join(outdir, 'patch.dat')
    fat_path = os.path.join(outdir, 'patch.fat')
    with open(dat_path, 'wb') as f:
        f.write(out)
    with open(fat_path, 'wb') as f:
        f.write(fat)
    shutil.copyfile(van1_dat_p, os.path.join(outdir, 'patch1.dat'))
    shutil.copyfile(van1_fat_p, os.path.join(outdir, 'patch1.fat'))
    print(f'wrote {dat_path} ({len(out)} B) + {fat_path} ({len(fat)} B) '
          f'+ vanilla patch1 pair ({replaced} entry replaced)')

    # ---- self verification: decode everything back ----
    ver2, flags2, ents2 = dunia_fat.read_fat(fat_path)
    assert ver2 == 8 and flags2 == flags and len(ents2) == len(vents)
    ndat = open(dat_path, 'rb').read()
    ok = 0
    for e_old, e_new in zip(vents, ents2):
        assert e_old['nameHash'] == e_new['nameHash']
        if e_old['nameHash'] == TARGET:
            got = dunia_fat.decode_entry(ndat, e_new)
            assert got == blob, 'target payload mismatch'
        else:
            old_decoded = dunia_fat.decode_entry(vdat, e_old)
            got = dunia_fat.decode_entry(ndat, e_new)
            assert got == old_decoded, f'entry {e_old["nameHash"]:08x} changed!'
        ok += 1
    print(f'self-verify: {ok}/{len(ents2)} entries decode byte-identical '
          f'(target == merged superset)')


if __name__ == '__main__':
    main()
