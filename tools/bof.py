#!/usr/bin/env python3
"""WD1 (Disrupt) BinaryObjectFile ('FCbn') parser/builder.

Format (from Gibbed.Disrupt BinaryObjectFile/BinaryObject, validated):
  u32 'FCbn' (bytes 6e 62 43 46 LE), u16 version=3, u16 flags=0,
  u32 totalObjectCount, u32 totalValueCount, then root object.

Object:
  count := ReadCount: u8 <0xFE -> inline; 0xFE -> offset-ref (u32 index into
  pointer list, DAG sharing); 0xFF -> inline u32.
  If the child count read is an offset-ref, this slot re-uses an earlier object.
  Else: u32 nameHash, valueCount (inline), then fields:
      u32 fieldHash, size (inline), bytes
  then `childCount` child objects.

Gibbed Hashing.CRC32 == standard zlib CRC32 (poly 0xEDB88320).
"""
import struct
import zlib


def crc32(name):
    return zlib.crc32(name.encode()) & 0xFFFFFFFF


class Obj:
    __slots__ = ('name_hash', 'fields', 'children')

    def __init__(self, name_hash=0):
        self.name_hash = name_hash
        self.fields = {}      # u32 hash -> bytes
        self.children = []    # [Obj]

    def __repr__(self):
        return f'Obj({self.name_hash:08x} f={len(self.fields)} c={len(self.children)})'


class BOF:
    def __init__(self):
        self.objects = []   # every object in first-appearance order (pointer list)
        self.root = None
        self.total_objects = 0
        self.total_values = 0

    # ---- read ----
    @classmethod
    def parse(cls, data):
        bof = cls()
        magic, ver, flags, tobj, tval = struct.unpack_from('<IHHII', data, 0)
        assert magic == 0x4643626E, hex(magic)
        assert ver == 3, ver
        assert flags == 0, flags
        bof.total_objects = tobj
        bof.total_values = tval
        pos = 16
        ptrs = []

        def read_count(p):
            v = data[p]
            if v < 0xFE:
                return v, False, p + 1
            if v == 0xFF:
                n = struct.unpack_from('<I', data, p + 1)[0]
                return n, False, p + 5
            n = struct.unpack_from('<I', data, p + 1)[0]
            return n, True, p + 5

        def read_obj(p, ptrs):
            n, is_ref, p = read_count(p)
            if is_ref:
                return ptrs[n], p
            name_hash = struct.unpack_from('<I', data, p)[0]
            p += 4
            obj = Obj(name_hash)
            ptrs.append(obj)
            vn, is_ref2, p = read_count(p)
            assert not is_ref2, 'value-count offset not supported'
            for _ in range(vn):
                fh = struct.unpack_from('<I', data, p)[0]
                p += 4
                sz, is_ref3, p = read_count(p)
                if is_ref3:
                    # size stored earlier: count lives at (countpos - sz) where
                    # countpos = p - 5 (ref counts are always 0xFE + u32)
                    rp = p - 5 - sz
                    real, is4, rp2 = read_count(rp)
                    assert not is4
                    val = data[rp2:rp2 + real]
                    # resume after the count already consumed at p-5..p
                    obj.fields[fh] = val
                    continue
                obj.fields[fh] = data[p:p + sz]
                p += sz
            for _ in range(n):
                c, p = read_obj(p, ptrs)
                obj.children.append(c)
            return obj, p

        bof.root, end = read_obj(pos, ptrs)
        assert end == len(data), f'trailing {len(data)-end} bytes'
        bof.objects = ptrs
        return bof

    # ---- write ----
    def build(self):
        out = bytearray()
        ptrs = {}   # id(obj) -> index
        tobj = [0]
        tval = [0]

        def write_count(ba, v):
            if v < 0xFE:
                ba.append(v)
            else:
                ba.append(0xFF)
                ba += struct.pack('<I', v)

        def wr(obj):
            nonlocal out
            # DAG: repeat appearance -> ref (matches engine-side reader)
            if id(obj) in ptrs:
                out.append(0xFE)
                out += struct.pack('<I', ptrs[id(obj)])
                return
            ptrs[id(obj)] = len(self._seq)
            self._seq.append(obj)
            tobj[0] += len(obj.children)
            tval[0] += len(obj.fields)
            write_count(out, len(obj.children))
            out += struct.pack('<I', obj.name_hash)
            write_count(out, len(obj.fields))
            for fh, val in obj.fields.items():
                out += struct.pack('<I', fh)
                write_count(out, len(val))
                out += val
            for c in obj.children:
                wr(c)

        self._seq = []
        wr(self.root)
        head = struct.pack('<IHHII', 0x4643626E, 3, 0, tobj[0], tval[0])
        return head + bytes(out)

    def walk(self, obj=None):
        if obj is None:
            obj = self.root
        yield obj
        for c in obj.children:
            yield from self.walk(c)
