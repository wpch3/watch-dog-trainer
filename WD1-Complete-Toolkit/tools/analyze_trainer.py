#!/usr/bin/env python3
"""Static analyzer for third-party WD1 trainer executables (MrAntiFun +19 / +27Tr etc.).

Reads only. Never executes the sample. Produces a text report + JSON with:
  - PE headers/sections/timestamp, version info strings
  - import table: memory-manipulation API usage (external-trainer classification)
  - ASCII/UTF-16 strings: AOB signatures, hex offsets, feature keywords, game exe names
  - candidate cross-reference against our src/Native/Contracts.cs offsets

Usage: python3 tools/analyze_trainer.py <path-to-exe> [more.exe ...]
Reports land in reports/trainer-analysis/ (git-ignored); the sample itself is never copied.
"""
import sys, re, json, struct, hashlib, datetime
from pathlib import Path

R = Path(__file__).resolve().parents[1]
OUT = R / 'reports' / 'trainer-analysis'

KEYWORDS = [b'money', b'skill', b'batter', b'battery', b'focus', b'ammo', b'health', b'reload',
            b'reput', b'police', b'detect', b'hack', b'trip', b'spider', b'exp', b'level',
            b'teleport', b'speed', b'onehit', b'one hit', b'radar', b'size', b'mega', b'mini',
            b'repair', b'watch_dogs', b'watchdogs', b'WatchDogs', b'.exe', b'.ct', b'cheat',
            b'engine', b'kernel', b'driver', b'sys']
AOB_RE = re.compile(rb'(?:[0-9A-Fa-f]{2}[\s\-,]?){6,}')
OFFSET_RE = re.compile(rb'\[\w+\+[0-9A-Fa-f]{2,4}\]|\+[0-9A-Fa-f]{2,4}\b')

IMPORT_HINTS = [b'ReadProcessMemory', b'WriteProcessMemory', b'OpenProcess', b'VirtualAllocEx',
                b'CreateToolhelp32Snapshot', b'Module32First', b'Process32First',
                b'GetAsyncKeyState', b'SetWindowsHookEx', b'FindWindow', b'NtReadVirtualMemory',
                b'NtWriteVirtualMemory', b'WriteProcessMemory']

def pe_info(b):
    if b[:2] != b'MZ':
        return None
    pe = struct.unpack_from('<I', b, 0x3C)[0]
    if b[pe:pe+4] != b'PE\0\0':
        return {'valid': False}
    machine, nsec, timestamp = struct.unpack_from('<HHI', b, pe+4)
    magic = struct.unpack_from('<H', b, pe+24)[0]
    bits = 64 if magic == 0x20B else 32
    opt = pe+24
    subsystem = struct.unpack_from('<H', b, opt+(68 if bits == 64 else 68))[0]
    sections = []
    off = opt + struct.unpack_from('<H', b, pe+20)[0]
    for i in range(nsec):
        name = b[off:off+8].rstrip(b'\0').decode('ascii', 'replace')
        vsize, vaddr, rsize, raddr = struct.unpack_from('<IIII', b, off+8)
        sections.append({'name': name, 'vsize': vsize, 'rsize': rsize, 'raddr': raddr})
        off += 40
    return {'valid': True, 'bits': bits, 'machine': hex(machine), 'subsystem': subsystem,
            'compiled_utc': datetime.datetime.utcfromtimestamp(timestamp).isoformat() if timestamp else None,
            'sections': sections}

def utf16_strings(b, minlen=5):
    out = []
    for m in re.finditer(rb'(?:[\x20-\x7e]\x00){%d,}' % minlen, b):
        out.append(m.group().decode('utf-16-le', 'replace'))
    return out

def ascii_strings(b, minlen=6):
    return [m.group().decode('ascii', 'replace') for m in re.finditer(rb'[\x20-\x7e]{%d,}' % minlen, b)]

def analyze(path):
    raw = path.read_bytes()
    rep = {'file': path.name, 'size': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
    rep['pe'] = pe_info(raw)
    a, w = ascii_strings(raw), utf16_strings(raw)
    # version info usually UTF-16
    vi = [s for s in w if any(k in s for k in ('ProductName', 'CompanyName', 'FileDescription', 'LegalCopyright', 'ProductVersion', 'InternalName'))]
    rep['version_info'] = vi[:20]
    # imports by ASCII name (hint only; full IAT parse not needed for classification)
    rep['import_hits'] = [h.decode() for h in IMPORT_HINTS if raw.find(h) != -1]
    # AOB-ish strings in ASCII and UTF-16
    aob = set()
    for s in a:
        for m in AOB_RE.finditer(s.encode()):
            t = m.group().decode()
            if sum(ch.isdigit() for ch in t) >= 6 and len(t.replace(' ', '')) >= 12:
                aob.add(t.strip())
    for s in w:
        for m in AOB_RE.finditer(s.encode('utf-16-le')):
            aob.add(s.strip())
    rep['aob_candidates'] = sorted(aob)[:120]
    off_hits = set()
    for s in a:
        for m in OFFSET_RE.finditer(s.encode()):
            off_hits.add(m.group().decode())
    rep['offset_candidates'] = sorted(off_hits)[:120]
    kw = {}
    for k in KEYWORDS:
        hits = [s for s in a if k in s.lower().encode()] + [s for s in w if k in s.lower().encode()]
        if hits:
            kw[k.decode()] = sorted(set(hits))[:12]
    rep['keyword_strings'] = kw
    return rep

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.exists():
            print('MISSING', p); continue
        rep = analyze(p)
        stem = p.stem.replace(' ', '_')
        (OUT / (stem + '.analysis.json')).write_text(json.dumps(rep, indent=1, ensure_ascii=False), encoding='utf-8')
        print('=' * 60)
        print(p.name, rep['size'], 'bytes  sha256', rep['sha256'][:16], '...')
        print('PE:', json.dumps(rep['pe'], ensure_ascii=False)[:300])
        print('VERSIONINFO:', rep['version_info'][:8])
        print('IMPORT HITS:', rep['import_hits'])
        print('AOB candidates:', len(rep['aob_candidates']))
        for s in rep['aob_candidates'][:25]:
            print('   ', s[:100])
        print('OFFSET candidates:', rep['offset_candidates'][:25])
        for k, v in rep['keyword_strings'].items():
            print('KW', k, '->', v[:4])
        print('report:', OUT / (stem + '.analysis.json'))

if __name__ == '__main__':
    main()
