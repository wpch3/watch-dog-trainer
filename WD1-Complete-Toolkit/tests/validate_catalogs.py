"""v0.3 static release contracts. No game, native process API, or network calls."""
from pathlib import Path
import json,re,csv,struct,hashlib
R=Path(__file__).resolve().parents[1]
load=lambda n:json.loads((R/n).read_text(encoding='utf-8-sig'))
p=load('project.json');plan=load('data/complete_plan.json');rows=plan['items'];items=load('data/runtime_items.json')['items']
assert p['version']=='0.3.3-alpha' and not p['is_finished_trainer'] and not p['runtime_game_tests_completed']
assert not p['platform_achievement_module']['included']
for name in ['WD1-Achievements.exe','WD1-Achievements.exe.config','WD1.SteamBridge.dll','src/Steam','third_party','data/achievements.json','data/achievement_hints.json']:assert not (R/name).exists(),name
source='\n'.join(f.read_text() for f in (R/'src').rglob('*.cs'))
assert not re.search(r'SAM\.|SetAchievement\(|GetAchievement\(|steamclient\.dll|StoreStats\(',source)
assert plan['meaning_of_achievement']=='IN_GAME_PROGRESSION_ONLY'
assert plan['infinite_is_not_replaced_by_add'] and p['infinite_and_add_are_independent']
assert len(rows)==169 and len({x['id'] for x in rows})==169
assert all(not x['runtime_verified'] for x in rows)
assert len([x for x in rows if x['backend']=='NATIVE_CANDIDATE'])==24
assert sum(x['backend']=='UNBOUND' for x in rows)==112
ids={x['id']:x for x in rows}
for resource in ['electronic','chemical','explosive','hardware','medicine']:
 assert ids['resource.'+resource+'.infinite']['control']=='TOGGLE'
 assert ids['resource.'+resource+'.add']['control']=='ACTION'
for mode in ['spider','madness','alone','dlc_solo']:
 assert ids['growth.'+mode+'.skill_infinite']['control']=='TOGGLE'
 assert ids['growth.'+mode+'.skill_add']['control']=='ACTION'
for seat in range(1,5):
 assert 'player.'+str(seat)+'.infinite' in ids and 'player.'+str(seat)+'.add' in ids
for timer in ['timer.drinking_cursor','timer.cashrun','timer.vehicle_20min','timer.racing','timer.nvzn','native.hack_timer','native.drink_timer','native.spider_timer','native.madness_timer']:assert timer in ids,timer
for unlock in ['lua.all_weapons','lua.all_clothes','lua.all_items']:assert ids[unlock]['control']=='ACTION'
assert len(load('plan/original_gameplay_requirements.json')['items'])==142
assert len(items)==218 and len({i['key'] for i in items})==218
assert all(i['db_path']=='Items.'+i['key'] and re.fullmatch(r'\d+',i['key']) for i in items)
assert sum(i['group'] in ['weapons','dlc_weapons','bb_weapons'] for i in items)==49
assert sum(i['group'] in ['clothes','bb_clothes','dlc_clothes','trip_clothes'] for i in items)==74
for i in items:
 assert i['source_category'] not in {'AccessIds','custom_Weapon','MainMissionXP','SideMissionXP','MissionSpecific'}
 if i['source_category']=='Weapon':assert not any(x in i['db_name'] for x in ['.Empty','_MP','.NPC','.07_','ARReplicaWeapon','ChopperSniper','ClaraGun'])
for name,n in [('complete_plan.csv',169),('runtime_items.csv',218),('online_rewards.csv',8)]:
 with (R/'data'/name).open(encoding='utf-8-sig',newline='') as h:a=list(csv.DictReader(h))
 assert len(a)==n and all(None not in row for row in a)
 assert all(not str(v).startswith(('=','+','@')) for row in a for v in row.values())
core=(R/'src/Plugin/core.lua').read_text();menu=(R/'src/Plugin/menu.lua').read_text()
assert 'self:invoke("AddItem",job.name,job.quantity)' in core
assert 'function c:prepareAll(kind)' in core and 'function c:ammoOnce()' in core
assert 'groups[kind][item.group]' in core and '#ids>256' in core
assert '[ALL WEAPONS]' in menu and '[ALL CLOTHES]' in menu and '[ALL ITEMS]' in menu
assert 'local ammo=bool(' in menu and 'local ammoOnce=command(' in menu
for mode in ['campaign','dlc_solo']:
 module='wd1kit_'+mode;d=R/'payload'/module;m=json.loads((d/'modconfig.json').read_text())
 assert m['version']=='0.3.0' and m['compatibleGameModes']==[mode] and m['minTntVersion']=='1.1.12'
 for name in ['core.lua','menu.lua','catalog.lua']:assert (d/'workspace'/module/name).read_bytes()==(R/'src/Plugin'/name).read_bytes()
 assert 'allow_persistent=false' in (d/'workspace'/module/'receipt.lua').read_text()
contracts=(R/'src/Native/Contracts.cs').read_text();memory=(R/'src/Native/Memory.cs').read_text();engine=(R/'src/Native/Engine.cs').read_text()
assert '2B C6 89 42 0C B0 01 EB' in contracts and 'inventory_infinite' in contracts
assert 'Kind="once_u16"' in contracts and 'BitConverter.ToUInt16' in engine
assert 'InstructionPointers()' in memory and 'NtResumeProcess' in memory and 'FlushInstructionCache' in memory
assert 'c.Pointer!=v.Pointer' in engine and 'Fresh(c)' in engine
assert 'Active = true' not in source
assert 'WD1KIT_FIXTURES' not in (R/'tools/build_release.py').read_text()
for digest in load('profiles/steam-11241563-observed.json')['binary_sha256'].values():assert digest in (R/'src/Shared/Files.cs').read_text()
b=(R/'WD1-Toolkit.exe').read_bytes();o=struct.unpack_from('<I',b,0x3c)[0];assert b[:2]==b'MZ' and b[o:o+4]==b'PE\0\0' and struct.unpack_from('<H',b,o+4)[0]==0x8664
assert hashlib.sha256((R/'tools/Collect-WD1Info.ps1').read_bytes()).hexdigest()=='e95e7fd4e12b1adaba077e13a21a6fdbd11287ec9f1f00507ef6dcacf4f03ece'
result=load('release-tests/results.json');assert result['lua_checks']==335 and result['core_checks']==47 and result['native_checks']==51 and not result['real_game_test']
for path in R.rglob('*.json'):json.loads(path.read_text(encoding='utf-8-sig'))
print('PASS: platform-achievement code/dependencies removed; one Windows x64 executable.')
print('PASS: complete 169-entry plan + 142 retained gameplay requirements; infinite/add independent.')
print('PASS: 218 whitelist keys; three distinct all-item batches; per-mode payload parity.')
print('PASS: native candidate/byte/thread/object guards, fake-process tests, no real-game certification claims.')

assert load('release-tests/build-info.json')['no_default_framework_references']
assert '-nostdlib+' in (R/'tools/build_release.py').read_text() and '--framework-refs' in (R/'tools/build_release.py').read_text()
assert not re.search(r"\.Split\(\s*'",source), 'Use explicit char[] overloads on net48'
assert 'NET48_MISSING=0' in (R/'release-tests/net48-member-audit.log').read_text()
assert 'TFM .NETFramework,Version=v4.8' in (R/'release-tests/net48-member-audit.log').read_text()
print('PASS: explicit Microsoft net48 build contract; no single-char Split calls; framework MemberRefs resolved.')

scan_source=(R/'src/Native/ImageScan.cs').read_text()
assert 'VirtualQueryEx' in memory and 'RequireScannedCode' in memory
assert 'ImageScanSession' in memory and 'module+moduleSize' not in memory
assert 'ScanComplete' in engine and 'HashSet<long>' in engine
assert 'DefaultChunkBytes=2*1024*1024' in scan_source
assert 'INCOMPLETE_READONLY_SNAPSHOT' in scan_source
assert 'ExportPayload' in (R/'src/Native/NativeForm.cs').read_text()
assert result['image_scan_checks']==48
print('PASS: stream/image-page bounds, partial-scan write refusal, and failed-connection export regression checks.')

capture_source=(R/'src/Native/CaptureState.cs').read_text()
assert 'CACHED_PAUSED_OR_STALE' in capture_source and 'HOOK_NOT_HIT' in capture_source
assert 'QueueOnce' in capture_source and 'CancelQueued' in capture_source
assert 'q.Generation!=c.Generation' in capture_source and 'c.Sequence==q.Sequence' in capture_source
assert 'FreshSeconds=2' in capture_source
assert 'RefreshDetail();' in (R/'src/Native/NativeForm.cs').read_text()
assert result['capture_checks']==39
print('PASS: actionable capture states, cached-only preview, same-object next-heartbeat queue, cancellation tests.')
