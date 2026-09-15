#!/usr/bin/env python3
"""Public game-only release package. No legacy platform module or private game data."""
from pathlib import Path
import hashlib,zipfile
R=Path(__file__).resolve().parents[1]
SKIP={'ui-companion.png','ui-native.png','ui-steam.png','release-tests/Test-Core.exe','SHA256SUMS.txt'}
EXCLUDED={'__pycache__','.cache','.git','reports','backups','private-saves','node_modules','dist','build'}
files=[]
for f in sorted(R.rglob('*')):
 if not f.is_file():continue
 rel=f.relative_to(R).as_posix()
 if rel in SKIP or any(p in EXCLUDED for p in f.relative_to(R).parts):continue
 if f.suffix.lower() in {'.exe','.dll','.asi','.pdb','.dmp','.save','.sav','.ct'} and rel!='WD1-Toolkit.exe':raise RuntimeError('Unexpected binary/private content: '+rel)
 if f.name in {'WD1-Achievements.exe','WD1.SteamBridge.dll','steamclient.dll','WD1-Report.json.txt'}:raise RuntimeError('Removed/private component: '+rel)
 files.append(f)
(R/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.relative_to(R).as_posix()+'\n' for f in files),encoding='utf8')
files.append(R/'SHA256SUMS.txt');archive=R.parent/'WD1-Game-Toolkit-v0.3.3-alpha.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for f in files:z.write(f,'WD1-Game-Toolkit-v0.3.3/'+f.relative_to(R).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for f in files:assert z.read('WD1-Game-Toolkit-v0.3.3/'+f.relative_to(R).as_posix())==f.read_bytes()
print('Archive:',archive.name,'Entries:',len(files),'Bytes:',archive.stat().st_size)
print('SHA256:',hashlib.sha256(archive.read_bytes()).hexdigest())
