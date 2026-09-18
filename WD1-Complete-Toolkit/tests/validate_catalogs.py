"""v0.4.0 static release contracts. No game, native process API, or network calls."""
from pathlib import Path
import json,re,csv,struct,hashlib
R=Path(__file__).resolve().parents[1]
load=lambda n:json.loads((R/n).read_text(encoding='utf-8-sig'))
p=load('project.json');plan=load('data/complete_plan.json');rows=plan['items'];items=load('data/runtime_items.json')['items']
assert p['version']=='0.4.21-alpha' and not p['is_finished_trainer'] and not p['runtime_game_tests_completed']
assert not p['platform_achievement_module']['included']
for name in ['WD1-Achievements.exe','WD1-Achievements.exe.config','WD1.SteamBridge.dll','src/Steam','third_party','data/achievements.json','data/achievement_hints.json']:assert not (R/name).exists(),name
source='\n'.join(f.read_text() for f in (R/'src').rglob('*.cs'))
assert not re.search(r'SAM\.|SetAchievement\(|GetAchievement\(|steamclient\.dll|StoreStats\(',source)
assert plan['meaning_of_achievement']=='IN_GAME_PROGRESSION_ONLY'
assert plan['infinite_is_not_replaced_by_add'] and p['infinite_and_add_are_independent']
assert len(rows)==187 and len({x['id'] for x in rows})==187
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
for unlock in ['lua.unlock.progression_all','lua.unlock.mission_xp','lua.unlock.notoriety_rewards','lua.unlock.ctos_rewards','lua.unlock.activity_rewards','lua.unlock.cash_items','lua.unlock.upgrades','lua.unlock.gear_all','lua.unlock.cars_all','lua.unlock.songs_all','lua.unlock.custom_weapons','lua.unlock.mission_tokens']:
 assert ids[unlock]['control']=='ACTION' and ids[unlock]['backend']=='LUA_CANDIDATE',unlock
for pid in ['progress.notoriety','progress.online','progress.ctos','progress.minigames','progress.collectibles','progress.convoy']:
 assert ids[pid]['backend']=='LUA_CANDIDATE',pid
assert len(load('plan/original_gameplay_requirements.json')['items'])==142
assert len(items)==2709 and len({i['key'] for i in items})==2709
assert all(i['db_path']=='Items.'+i['key'] and re.fullmatch(r'\d+',i['key']) for i in items)
assert sum(i['group'] in ['weapons','dlc_weapons','bb_weapons','custom_weapons'] for i in items)==152
assert sum(i['group'] in ['clothes','bb_clothes','dlc_clothes','trip_clothes','clothes_mod'] for i in items)==84
assert sum(i['group']=='mission_tokens' for i in items)==1003
assert sum(i['group']=='notoriety' for i in items)==32
assert sum(i['group']=='cars' for i in items)==74
assert sum(i['group'] in ['mission_xp_main','mission_xp_side','mission_xp_family'] for i in items)==170
assert sum(i['group'] in ['activity_rewards','ctos_rewards'] for i in items)==56
for i in items:
 assert i['source_category'] not in {'E3_2012','E3_2013','Cloths_DEPRECATED','_DUMMY_ITEMS'}
 assert not i['db_name'].endswith('.Empty')
 if i['source_category']=='Weapon':assert not any(x in i['db_name'] for x in ['.Empty','.NPC'])
 if i['label_zh']=='' :assert False,'empty label'
for name,n in [('complete_plan.csv',187),('runtime_items.csv',2709),('online_rewards.csv',8)]:
 with (R/'data'/name).open(encoding='utf-8-sig',newline='') as h:a=list(csv.DictReader(h))
 assert len(a)==n and all(None not in row for row in a)
 assert all(not str(v).startswith(('=','+','@')) for row in a for v in row.values())
core=(R/'src/Plugin/core.lua').read_text();menu=(R/'src/Plugin/menu.lua').read_text();catalog=(R/'src/Plugin/catalog.lua').read_text()
assert 'self:invoke("AddItem",job.name,job.quantity)' in core
assert 'function c:prepareAll(kind)' in core and 'function c:ammoOnce()' in core
assert 'function c:prepareGroup(group, quantity)' in core
assert 'groups[kind][item.group]' in core and '#ids>4096' in core
assert 'progression={' in core and 'notoriety=true' in core
assert '[ALL WEAPONS]' in menu and '[ALL CLOTHES]' in menu and '[ALL ITEMS]' in menu
assert '[ALL PROGRESSION] Prepare every progression reward' in menu
assert 'WD1KIT_UI4_MOMENT' in menu and 'SH_Commands_RegisterCallback' in menu
assert 'WD1 KIT - Main [UI4]' in menu
# catalog entries are ASCII-safe and well-formed
for m in re.finditer(r'\{ id="(item_\d+)", key="(\d+)", name="([^"]+)", label="([^"]*)", group="([a-z_]+)", mode="(both|campaign|dlc_solo)" \}',catalog):
 pass
assert len(re.findall(r'\{ id="item_',catalog))==2709
assert not re.search(r'[\x80-\xff]',catalog),'catalog must stay ASCII'
for mode in ['campaign','dlc_solo']:
 module='wd1kit_'+mode;d=R/'payload'/module;m=json.loads((d/'modconfig.json').read_text())
 assert m['version']=='0.4.21' and m['compatibleGameModes']==[mode] and m['minTntVersion']=='1.1.12'
 for name in ['core.lua','menu.lua','catalog.lua']:assert (d/'workspace'/module/name).read_bytes()==(R/'src/Plugin'/name).read_bytes()
entry=re.compile(r'\{ id="(item_\d+)", key="(\d+)", name="([^"]+)", label="([^"]*)", group="([a-z_]+)", mode="(both|campaign|dlc_solo)" \}')
zh=entry.findall((R/'locales/zh-CN/Plugin/catalog.lua').read_text(encoding='utf-8'))
en=entry.findall((R/'locales/en-ASCII/catalog.lua').read_text(encoding='utf-8'))
src=entry.findall(catalog)
assert len(zh)==len(en)==len(src)==2709
for a,b,c in zip(zh,en,src):
 assert a[:3]==b[:3]==c[:3] and a[4:]==b[4:]==c[4:]
print('VALIDATOR_OK v0.4.21: 187 plan rows, 2709 catalog entries, payload==src, UI4 contracts present')
