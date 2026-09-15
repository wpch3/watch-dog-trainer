#!/usr/bin/env python3
"""Build the original curated WD1 catalog from an explicitly pinned upstream checkout.
No third-party trainer logic is copied. IDs/names are factual interoperability data.
Usage: python tools/build_catalog.py /path/to/NexusTools.Trainer
"""
import csv, json, re, sys, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
UP = Path(sys.argv[1])
COMMIT = 'a20b61be0e2e00258ccb10ccfeb1be78c9b60450'
assert subprocess.check_output(['git','-C',str(UP),'rev-parse','HEAD'],text=True).strip() == COMMIT
text=(UP/'workspace/trainer/data/Items.lua').read_text(encoding='utf-8-sig')
raw=[dict(zip(['key','name','prefix','category'],x)) for x in re.findall(r'key = "([^"]+)", name = "([^"]+)", prefix = "([^"]+)", category = "([^"]+)"',text)]
idx={(i['category'],i['name']):i for i in raw}
rows=[]
def add(cat,name,label,group,mode='both',note=''):
 i=idx[cat,name]
 rows.append(dict(id='item_'+i['key'],key=i['key'],db_path=i['prefix']+i['key'],db_name=i['prefix']+name,label_zh=label,group=group,mode=mode,source_category=cat,status='IMPLEMENTED_UNVERIFIED',note=note))
add('SkillPointReward','Skillpoint','技能点奖励 +1','skill')
for name in ['XP_500','XP_1000','XP_2000','XP_5000']:
 add('ProgressionBonus',name,name.replace('XP_','经验奖励 +'),'xp')
weapons={
'Pistols.P9mm':'P-9mm','Pistols.1911':'1911','Pistols.1911.SpecOps':'Spec Ops 1911',
'Pistols.357REX':'.357 REX','Pistols.D50':'D50','Pistols.M8M':'M8-M','Pistols.R33':'R-33',
'SMGs.MP9mm':'MP-9mm','SMGs.SMG11':'SMG-11','SMGs.SMG11.SpecOps':'Spec Ops SMG-11',
'SMGs.MP5':'MP5','SMGs.Vector45ACP':'Vector .45 ACP','SMGs.Vector45ACP.SpecOps':'Spec Ops Vector .45 ACP',
'SMGs.R2000':'R-2000','AssaultRifles.416':'416','AssaultRifles.417':'417','AssaultRifles.AK47':'AK-47',
'AssaultRifles.Goblin':'Goblin','AssaultRifles.Goblin.SpecOps':'Spec Ops Goblin','AssaultRifles.ACR':'ACR',
'AssaultRifles.U100':'U100','AssaultRifles.OCP11':'OCP-11','Shotguns.SG590':'SG-90',
'Shotguns.RSG12':'SGR-12','Shotguns.M1014':'M1014','Shotguns.D12':'D12',
'SniperRifles.SVD':'SVD','SniperRifles.SR25':'SR-25','SniperRifles.M107':'M107',
'SniperRifles.ACE':'AC-AR','GrenadeLauncher.G106':'G106',
'Pistols.M8M.Sig_Chrome':'Chrome','Shotguns.SG590.Sig_Piledriver':'Piledriver',
'AssaultRifles.416.Sig_Sprayer':'Wildfire','SniperRifles.M107.Sig_Destroyer':'Destroyer',
'SMGs.M1SMG':'M1 SMG','SMGs.M1SMG.Sig_Gold':'Gangster'}
for name,label in weapons.items(): add('Weapon',name,label,'weapons')
for name,label in {'Pistols.M8M.ULC_Cyberpunk':'Cyberpunk 手枪','AssaultRifles.ACR.ULC_Biometric':'Biometric ACR','Pistols.R33.ULC_R33b':'R-33B'}.items():
 add('Weapon',name,label,'dlc_weapons','campaign','仅测试你已拥有的 Complete Edition 内容，不授予 DLC 所有权。')
for name,label in {'Pistols.1911.dlc01_With_Light':'1911（手电）','Pistols.D50.dlc01_with_Light':'D50（手电）','SMGs.R2000.dlc01_With_Light':'R-2000（手电）','Shotguns.SG590.dlc01_with_Light':'SG-90（手电）','Shotguns.RSG12.dlc01_with_Light':'SGR-12（手电）','AssaultRifles.AK47.dlc01__withLight':'AK-47（手电）','AssaultRifles.U100.dlc01_with_Light':'U100（手电）','SniperRifles.M107.DLC01_SpecOps':'Spec Ops M107'}.items():
 add('Weapon',name,label,'bb_weapons','dlc_solo')
for cat,name,label in [('Tech','BlackOutCC','停电道具'),('Tech','DisruptCommCC','通讯干扰'),('Tech','ctOSScanCC','ctOS 扫描'),('Projectiles','Attractor_IED','诱饵'),('Projectiles','FragGrenade','破片手榴弹'),('Projectiles','IED','简易爆炸装置'),('Projectiles','Proximity_IED','感应式 IED'),('Meds','Focus_InsS_Pill','专注恢复道具'),('Tech','Code_Comp','电子零件'),('Explosives','Chem_Comp','化学材料'),('Explosives','Exp_Comp','爆炸材料'),('Explosives','RecycledHardware_Comp','回收零件'),('Meds','Drug2_Comp','药物材料'),('General','Battery','电池补充（奖励项实验）')]:
 add(cat,name,label,'supplies')
for i in sorted(raw,key=lambda x:x['name']):
 if i['category']=='Clothing_SP' and re.fullmatch(r'DefaultSkin\.SP_Cloth_Store_Aiden_\d{2}',i['name']):
  add(i['category'],i['name'],'艾登商店服装 '+i['name'][-2:],'clothes','campaign')
 if i['category']=='DLC' and re.fullmatch(r'dlc01_Cloth_DefaultSkin\.dlc01_SP_Cloth_Store_TBone_\d{2}',i['name']):
  add(i['category'],i['name'],'T-Bone 商店服装 '+i['name'][-2:],'bb_clothes','dlc_solo')
for name,label in [('DefaultSkin.Pills.Alone','孤独奖励服装'),('DefaultSkin.Pills.Madness','疯狂奖励服装'),('DefaultSkin.Pills.SpiderTank','蜘蛛坦克奖励服装'),('DefaultSkin.Pills.Psychedelic','迷幻奖励服装'),('DefaultSkin.Pills.Conspiracy','阴谋奖励服装')]:
 add('Clothing_SP',name,label,'trip_clothes','campaign','给予候选；不伪造数字之旅通关计数。')
add('Weapon','Pistols.D50.Uplay_Gold','Golden D50（本地物品候选）','dlc_weapons','campaign')
for name in ['Dedsec','ChicagoClub','Whitehat','Retro','Cyberpunk','Glitch','Blume','Viceroys']:
 add('Clothing_ULC',name,name+' 服装','dlc_clothes','campaign','仅物品项；不绕过 DLC 授权。')
# Reward keys, not spawned entities. Title-to-reward mappings are candidates until in-game readback.
car_names={
'Speed.Speed_01':'Scafati GT','Speed.Speed_02':'Amargosa Turbo','Speed.Speed_03':'336-TT','Speed.Speed_04':'550S',
'Speed.Speed_05':'Livraga 350','Speed.Speed_05_Reward':'Livraga LE','Speed.Speed_06':'Papavero','Speed.Speed_06_Stealth':'Papavero Stealth Edition',
'Speed.Speed_07':'Boxberg R1','Speed.Speed_07_Reward':'Boxberg LE',
'Agile.Agile_01':'Zusume R','Agile.Agile_02':'Kirscher','Agile.Agile_03':'Sunrim','Agile.Agile_04':'Rotor','Agile.Agile_05':'Carrozza','Agile.Agile_06':'Core-T',
'Bike.Bike_01':'Sayonara','Bike.Bike_01_Reward':'Sayonara LE','Bike.Bike_02':'Kuruhawa Motorsport 450','Bike.Bike_03':'Kodachi','Bike.Bike_04':'Chopper',
'Offroad.Offroad_01':'Polar','Offroad.Offroad_02':'Tributary 1500','Offroad.Offroad_03':'Steadfast 3000','Offroad.Offroad_04':'Tributary 3500',
'Muscle.Muscle_01':'Vespid 5.2','Muscle.Muscle_02':'Hailkal R','Muscle.Muscle_03':'Adamant S-Series','Muscle.Muscle_04':'Sonarus LX',
'Muscle.Retro_01':'Vespid HMI','Muscle.Retro_01_Reward':'Vespid LE','Muscle.Retro_02':'571','Muscle.Retro_03':'3.9T',
'Muscle.Luxury_02':'Magnate','Muscle.Luxury_02_Reward':'Magnate LE',
'Budget.Compact_01':'Zusume','Budget.Compact_02':'Sumitzu Auto 1.6','Budget.Compact_03':'Sculptor 2.5R',
'Budget.Crossover_01':'Talos','Budget.DeliveryTruck_01':'Relegater','Budget.Large_01':'Cavale','Budget.Large_02':'Leo',
'Budget.Large_03':'Vessel','Budget.Large_04':'Relegate V6','Budget.Large_05':'Woodie','Budget.Luxury_03':'Koln 500S',
'Budget.Minivan_01':'Crosscountry Series','Budget.Subcompact_01':'Fasto','Budget.Subcompact_02':'Lithium SP','Budget.Subcompact_03':'Bogen 200',
'Budget.SUV_01':'Kigan AWD','Budget.Workvan_01':'Landrock Van 2500','Budget.Workvan_02':'Landrock Van 1500','Budget.Limo_01':'Philandra'}
for name,label in car_names.items():
 add('CarHackingRewards','Generic.'+name,label+'（叫车奖励候选）','cars','campaign','Items 键来自上游；显示名与实体命名交叉映射，叫车解锁及持久性未验证。')
songs=['AlarmClocks','blvckandwhite','BrightIdea','ClujNapoca','Conduction','CREAM','Dance','DarkSteering','FuneralSinger','GoingDownHigh','HighClassSlimcamefloatingin','Jesusbuiltmyhotrod','LostBoys','MsCrumby','MyMyMy','NeverAgain','Outtolunch','Simplify','Talk','TheBottom','Wherethesidewalkends','Youburntme']
for s in songs:add('Song','song.'+s,s,'songs','campaign','歌曲物品授予不等于 SongSneak 计数或成就完成。')
# Goodmorningsunshine -> Wake Up Sunshine is not proven: deliberately omit the 23rd mapping.
assert len({r['key'] for r in rows})==len(rows)
(ROOT/'data/runtime_items.json').write_text(json.dumps({'upstream_commit':COMMIT,'items':rows,'excluded':'No access IDs, mission XP, mission tokens, NPC/MP/custom weapons, group placeholders or invented keys.'},ensure_ascii=False,indent=2)+'\n')
with (ROOT/'data/runtime_items.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def q(s):return json.dumps(s,ensure_ascii=False)
lua='-- Original curated interoperability catalog; provenance: data/runtime_items.json.\nreturn {\n'
for i in rows:
 lua+='  { id=%s, key=%s, name=%s, label=%s, group=%s, mode=%s },\n'%tuple(q(i[k]) for k in ['id','key','db_path','label_zh','group','mode'])
lua+='}\n'
(ROOT/'src/Plugin/catalog.lua').write_text(lua)
print('Curated runtime entries:',len(rows))
from collections import Counter
print(dict(Counter(x['group'] for x in rows)))
