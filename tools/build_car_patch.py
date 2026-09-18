#!/usr/bin/env python3
"""Build the WD1 car-unlock patch (Route A).

Strategy (validated against build 11241563 vanilla + UCOD v1.1 pair):
  * The car-on-demand reward pool lives in FCbn object file 0x81165196
    (patch.dat entry, name hash 0x81165196), container object 0xa90f3bcc.
  * Vanilla pool = 73 ItemDescriptorCar records. UCOD adds, inside the same
    container: hidden-car records bound to item keys 0x0FFFFF29..2C
    (police / madness / ... / Muscle_05) cloned from ordinary car records,
    plus availability-rule instances.
  * Superset = vanilla tree (untouched) + UCOD-only pool children + a
    generated Speed_08 record (item key 3870519146, absent from both).
  * Output: patch2.dat / patch2.fat (single stored entry, scheme 0 — the
    engine accepts stored entries, the UCOD archive is all-stored).

Usage: build_car_patch.py <van.dat> <van.fat> <ucod.dat> <ucod.fat> <outdir>
"""
import collections
import os
import struct
import sys

import importlib.util

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


dunia_fat = _load('dunia_fat', os.path.join(_HERE, 'dunia_fat.py'))
bof = _load('bof', os.path.join(_HERE, 'bof.py'))

HASH_FILE = 0x81165196       # 81165196.bin entry hash in the fat
HASH_POOL = 0xA90F3BCC       # CarHackingRewards pool container
F_NAME = 0x9D8873F8          # record-name field
F_CLASS = 0x43FB7444         # 'ItemDescriptorCar' class field
F_KEY_A = 0xB9295CC7         # key attribute (u32 LE)
F_KEY_B = 0x389F6DA7         # key attribute duplicate
SPEED_08_KEY = 3870519146    # 0xE6B36F6A, Generic.Speed.Speed_08


def sig(o):
    return (o.name_hash, tuple(sorted((h, bytes(v)) for h, v in o.fields.items())))


def find_pool(root):
    """Locate the CarHackingRewards pool container instance."""
    hits = []

    def walk(o):
        if o.name_hash == HASH_POOL and any(
                c.fields.get(F_CLASS) == b'ItemDescriptorCar\x00' for c in o.children):
            hits.append(o)
        for c in o.children:
            walk(c)
    walk(root)
    if not hits:
        raise RuntimeError('car pool container not found')
    return hits[0]


def build_speed08(template):
    """Clone an existing ItemDescriptorCar record as Speed_08."""
    import copy
    rec = copy.deepcopy(template)
    rec.fields[F_NAME] = b'CarHackingRewards.Generic.Speed.Speed_08\x00'
    kb = struct.pack('<I', SPEED_08_KEY)
    rec.fields[F_KEY_A] = kb
    rec.fields[F_KEY_B] = kb
    for c in rec.children:
        if F_KEY_A in c.fields:
            c.fields[F_KEY_A] = kb
            c.fields[F_KEY_B] = kb
    return rec


def superset_blob(van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p):
    """Build the merged 81165196 object file; returns bytes."""
    van_dat = open(van_dat_p, 'rb').read()
    vver, vflags, vents = dunia_fat.read_fat(van_fat_p)
    _, _, uents = dunia_fat.read_fat(ucod_fat_p)
    ucod_dat = open(ucod_dat_p, 'rb').read()

    def entry_by_hash(ents, h):
        for e in ents:
            if e['nameHash'] == h:
                return e
        raise KeyError(hex(h))

    ve = entry_by_hash(vents, HASH_FILE)
    ue = entry_by_hash(uents, HASH_FILE)

    van_blob = dunia_fat.decode_entry(van_dat, ve)
    ucod_blob = dunia_fat.decode_entry(ucod_dat, ue)
    print(f'vanilla 81165196: {len(van_blob)} B   ucod: {len(ucod_blob)} B')

    vtree = bof.BOF.parse(van_blob)
    utree = bof.BOF.parse(ucod_blob)
    vpool = find_pool(vtree.root)
    upool = find_pool(utree.root)
    print(f'vanilla pool children: {len(vpool.children)}   ucod pool children: {len(upool.children)}')

    vc = collections.Counter(sig(c) for c in vpool.children)
    uc = collections.Counter(sig(c) for c in upool.children)
    add = uc - vc
    print(f'ucod-only pool children: {sum(add.values())} distinct {len(add)}')

    taken = collections.Counter()
    new_children = []
    for c in upool.children:
        s = sig(c)
        if taken[s] < add.get(s, 0):
            new_children.append(c)
            taken[s] += 1
    assert taken == +add, 'instance extraction mismatch'

    template = None
    for c in vpool.children:
        nm = c.fields.get(F_NAME, b'')
        if b'Speed_01' in nm:
            template = c
            break
    assert template is not None, 'no Speed template record found'
    new_children.append(build_speed08(template))

    vpool.children.extend(new_children)

    blob = vtree.build()
    print(f'merged 81165196: {len(blob)} B  (pool children {len(vpool.children)})')

    rt = bof.BOF.parse(blob)
    rpool = find_pool(rt.root)
    assert len(rpool.children) == len(vpool.children)
    return blob


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        sys.exit(2)
    van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p, outdir = sys.argv[1:6]
    os.makedirs(outdir, exist_ok=True)
    blob = superset_blob(van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p)

    bin_path = os.path.join(outdir, '81165196.bin')
    with open(bin_path, 'wb') as f:
        f.write(blob)

    dat_path = os.path.join(outdir, 'patch2.dat')
    fat_path = os.path.join(outdir, 'patch2.fat')
    with open(dat_path, 'wb') as f:
        f.write(blob)

    off = 0
    scheme = 0
    b = ((len(blob) & 0x1FFFFFFF) << 3) | scheme
    c = ((off & 7) << 29) | (len(blob) & 0x1FFFFFFF)
    d = off >> 3
    fat = struct.pack('<4sIII', b'3TAF', 8, 0x00320504, 1)
    fat += struct.pack('<IIII', HASH_FILE, b, c, d)
    fat += struct.pack('<I', 0)
    with open(fat_path, 'wb') as f:
        f.write(fat)
    print(f'wrote {dat_path} ({len(blob)} B) + {fat_path} ({len(fat)} B)')


if __name__ == '__main__':
    main()


def deepmerge_blob(van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p, ngm_payload_p):
    """Deep-merge the superset car pool INTO an NGM/other mod's 81165196 payload.

    Safety policy (learned 2026-09-17: duplicate item keys in the pool crash
    the game on save load):
      * content-multiset diff against vanilla decides what to add;
      * a candidate record whose item key already exists in the target pool
        is SKIPPED (the target's own record wins);
      * the result must contain ZERO duplicate keys - asserted.
    Returns the merged blob bytes.
    """
    import collections
    import copy as _copy

    ngm_blob = open(ngm_payload_p, 'rb').read()
    t_ngm = bof.BOF.parse(ngm_blob)
    sup = superset_blob(van_dat_p, van_fat_p, ucod_dat_p, ucod_fat_p)
    t_sup = bof.BOF.parse(sup)

    van_dat = open(van_dat_p, 'rb').read()
    _, _, vents = dunia_fat.read_fat(van_fat_p)
    ve = next(e for e in vents if e['nameHash'] == HASH_FILE)
    t_van = bof.BOF.parse(dunia_fat.decode_entry(van_dat, ve))

    pn = find_pool(t_ngm.root)
    ps = find_pool(t_sup.root)
    pv = find_pool(t_van.root)

    def msig(pool):
        return collections.Counter(sig(c) for c in pool.children)

    def keys(pool):
        out = collections.Counter()
        for c in pool.children:
            k = c.fields.get(F_KEY_A)
            if k and len(k) == 4:
                out[struct.unpack('<I', k)[0]] += 1
        return out

    need = (msig(ps) - msig(pv)) - msig(pn)
    ngm_keys = keys(pn)
    taken = collections.Counter()
    adds = []
    for c in ps.children:
        s = sig(c)
        if taken[s] < need.get(s, 0):
            taken[s] += 1
            k = c.fields.get(F_KEY_A)
            kv = struct.unpack('<I', k)[0] if (k and len(k) == 4) else None
            if kv is not None and ngm_keys.get(kv, 0) > 0:
                continue  # key exists in target pool: target wins
            adds.append(_copy.deepcopy(c))
    assert taken == +need, 'instance extraction mismatch'

    add_keys = collections.Counter()
    for c in adds:
        k = c.fields.get(F_KEY_A)
        if k and len(k) == 4:
            add_keys[struct.unpack('<I', k)[0]] += 1
    assert all(v == 1 for v in add_keys.values()), 'duplicate keys in adds'
    assert not (set(add_keys) & set(ngm_keys)), 'adds collide with target keys'

    pn.children.extend(adds)
    blob = t_ngm.build()

    # final gate: the merged pool must have zero duplicate keys
    t2 = bof.BOF.parse(blob)
    k2 = keys(find_pool(t2.root))
    dups = {k: v for k, v in k2.items() if v > 1}
    assert not dups, f'duplicate keys after merge: {dups}'
    return blob

