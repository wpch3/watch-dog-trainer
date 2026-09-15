#!/usr/bin/env python3
"""Build game-only WD1 Toolkit against Microsoft .NET Framework 4.8 references.
Never fall back to Mono's runtime mscorlib (which exposes APIs absent on Windows net48).
Linux: python tools/build_release.py /usr/bin/mcs --framework-refs /path/to/Microsoft/net48/refs
Windows: python tools/build_release.py C:/path/to/Roslyn/csc.exe --framework-refs C:/path/to/v4.8
"""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess
R=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('compiler',nargs='?',default=shutil.which('mcs') or 'csc.exe')
parser.add_argument('--framework-refs',default=os.environ.get('WD1_NET48_REFS'))
parser.add_argument('--mono',action='store_true',help='Run Windows Roslyn csc.exe under Mono')
args=parser.parse_args()
if not args.framework_refs:parser.error('Specify Microsoft .NET Framework 4.8 reference assemblies with --framework-refs; Mono runtime references are not supported.')
compiler=Path(args.compiler);refs=Path(args.framework_refs).resolve()
reference_names=['mscorlib','System','System.Core','System.Drawing','System.Windows.Forms','System.Web.Extensions']
for n in reference_names:
 if not (refs/(n+'.dll')).is_file():parser.error('Missing required framework reference: '+n+'.dll')
if not (refs/'RedistList/FrameworkList.xml').is_file():parser.error('Expected the Microsoft net48 reference pack with RedistList/FrameworkList.xml, not a runtime directory.')
for name in ['WD1-Achievements.exe','WD1-Achievements.exe.config','WD1.SteamBridge.dll']:(R/name).unlink(missing_ok=True)
# Desktop hotfix only: Lua payload remains 0.3.0 and does not need reinstallation.
for mode in ['campaign','dlc_solo']:
 module='wd1kit_'+mode;dst=R/'payload'/module
 if dst.exists():shutil.rmtree(dst)
 scripts=dst/'workspace'/module;scripts.mkdir(parents=True)
 for f in ['core.lua','menu.lua','catalog.lua']:shutil.copyfile(R/'src/Plugin'/f,scripts/f)
 (scripts/'receipt.lua').write_text('-- Disabled source template; activated only after a verified local backup.\nreturn {format=1,product="WD1KIT",mode="'+mode+'",allow_persistent=false}\n')
 (scripts/'entrypoint.lua').write_text('''-- Game-only WD1KIT v0.3. No automatic enable on load.
local mode="%s"
local folder="%s/"
if WD1KIT_ACTIVE and WD1KIT_ACTIVE.alive then
 if WD1KIT_ACTIVE.mode==mode then return end
 WD1KIT_ACTIVE:shutdown("MODE_SWITCH_REQUIRES_RESTART")
 if WD1KIT_ACTIVE.script then pcall(function() WD1KIT_ACTIVE.script:Remove() end) end
end
local c=dofile(folder.."core.lua")(_G,dofile(folder.."catalog.lua"),dofile(folder.."receipt.lua"),mode)
WD1KIT_ACTIVE=c
local ok=pcall(function() dofile(folder.."menu.lua")(c,dofile(folder.."catalog.lua"),mode) end)
if not ok then c:shutdown("MENU_INIT_ERROR"); c:message("WD1KIT: menu init failed. No cheats enabled.") end
'''%(mode,module))
 (dst/'toolkit-owner.json').write_text(json.dumps({'Product':'WD1KIT','Module':module,'Version':'0.3.0-alpha'},indent=2)+'\n')
 (dst/'modconfig.json').write_text(json.dumps({'friendlyId':module,'name':'WD1 中文工具箱 '+('本体' if mode=='campaign' else 'Bad Blood')+' Alpha','author':'WD1 Toolkit project','priority':10,'description':'Original game-only test plugin; not runtime certified.','packs':[],'enabled':True,'version':'0.3.0','configVersion':1,'luaAutoStart':[module+'/entrypoint.lua'],'dominoAutoStart':[],'minTntVersion':'1.1.12','compatibleGameModes':[mode]},ensure_ascii=False,indent=2)+'\n')
mcs=compiler.name in ['mcs','mono-csc','dmcs']
cmd=[str(compiler)] if mcs or not args.mono else ['mono',str(compiler)]
cmd+=['-noconfig','-nostdlib+','-target:winexe','-platform:x64','-langversion:7.2','-optimize+','-out:'+str(R/'WD1-Toolkit.exe'),'-win32manifest:'+str(R/'src/app.manifest')]
if not mcs:cmd+=['-nologo','-deterministic+']
cmd+=['-r:'+str(refs/(n+'.dll')) for n in reference_names]
for part in ['Shared','Native','Companion']:cmd+=sorted(str(p) for p in (R/'src'/part).glob('*.cs'))
subprocess.run(cmd,check=True)
(R/'WD1-Toolkit.exe.config').write_text('<?xml version="1.0" encoding="utf-8"?><configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>\n')
(R/'release-tests').mkdir(exist_ok=True)
(R/'release-tests/build-info.json').write_text(json.dumps({'version':'0.3.3-alpha','target_framework':'.NETFramework,Version=v4.8','reference_pack':'Microsoft.NETFramework.ReferenceAssemblies.net48 / 1.0.3 (or an equivalent Microsoft net48 SDK reference directory)','compiler_driver':compiler.name,'no_default_framework_references':True,'references':{n:hashlib.sha256((refs/(n+'.dll')).read_bytes()).hexdigest() for n in reference_names},'game_runtime_verified':False},indent=2)+'\n')
print('Built WD1-Toolkit.exe 0.3.3 x64 against explicit Microsoft net48 references; Lua payload unchanged.')
