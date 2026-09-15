#!/usr/bin/env python3
"""Optional ASCII-only in-game menu, without changing command IDs, game calls or guards.
The Chinese desktop and plan remain unchanged. Saved zh-CN source is kept for restoration.
"""
from pathlib import Path
import json,re,shutil,csv,zipfile,hashlib
R=Path(__file__).resolve().parents[1]
if 'WD1KIT_UI2' in (R/'src/Plugin/menu.lua').read_text():
 print('UI2 menu already ASCII; do not regenerate the archived UI1 layout.')
 raise SystemExit(0)
original=R/'locales/zh-CN/Plugin';original.mkdir(parents=True,exist_ok=True)
for name in ['menu.lua','core.lua','catalog.lua']:
 if not (original/name).exists():shutil.copyfile(R/'src/Plugin'/name,original/name)
translations={
'WD1 KIT - 本体 [TEST]':'WD1 KIT - Main [TEST]',
'WD1KIT 0.3 alpha：游戏行为尚未在你的构建实测。':'WD1KIT ALPHA: game behavior is not yet verified on your build.',
'只设置本工具输入值；点击对应按钮才执行。':'Input only. Use the separate action button to apply.',
'须先在自由探索、断开联机后手动 ARM；重载/暂停会关闭。':'ARM in offline free roam first. Reload or host pause disables effects.',
'[ARM] 我已断开联机，且正在单机自由探索':'[ARM] I am offline and in single-player free roam',
'[STOP] 关闭持续效果并取消待执行请求':'[STOP] Disable effects and cancel pending requests',
'[CONFIRM] 确认上一笔物品 / 现金请求':'[CONFIRM] Apply the prepared item or cash request',
'[CANCEL] 取消物品 / 现金队列':'[CANCEL] Cancel item or cash queue',
'[REPORT] 导出只读接口能力到宿主日志':'[REPORT] Write read-only capabilities to host log',
'God mode / 持续无敌':'God Mode',
'Ammo / 无限弹药（持续补给）':'Infinite Ammo - continuous refill',
'[ADD AMMO] 只补给弹药一次':'[ADD AMMO] Refill ammo once',
'增加材料/消耗品的数量（与无限开关独立）':'Item / material quantity to add - separate from infinite',
'Focus / 持续专注补充':'Infinite Focus - continuous refill',
'Police / 暂停通缉系统':'Disable Wanted System',
'通缉热度输入 0–100':'Wanted Heat input 0-100',
'应用通缉热度输入':'Apply Wanted Heat',
'现金增加量（默认 1000，最大 100 万）':'Cash to add - default 1000, maximum 1000000',
'准备增加现金 → 再点 CONFIRM':'Prepare Cash - then CONFIRM',
'技能点奖励数量 1–100（先测 +1）':'Normal Skill Point rewards 1-100 - test +1 first',
'准备技能点奖励 → 再点 CONFIRM':'Prepare Skill Point reward - then CONFIRM',
'小时':'Hour','分钟':'Minute',
'应用时刻（重启游戏解除脚本时钟）':'Apply Time - restart the game to release scripted clock',
'0.2 ALPHA — 调用完成 ≠ 已解锁 / 已保存':'ASCII MENU - ALPHA: request sent is NOT verified unlock or persistence',
'01 / 安全与报告':'01 / Safety and Report',
'只在单机自由探索测试；不要在在线合约、入侵、比赛、合作或任务演出中启用。':'Offline free roam only. No online contracts, invasions, races, co-op or cutscenes.',
'没有真实的联机状态回读。本插件依靠你的单机确认 + 宿主 OnPause 通知；该通知在本机尚待验证。':'No reliable session-state readback. Manual offline confirmation and host pause callback are required.',
'物品、现金、技能奖励需要桌面工具生成的两小时备份回执。回执不是游戏存档识别器。':'Persistent grants need the companion backup receipt. It lasts two hours and does not identify the active save.',
'主线、调查、收集计数、线上合约次数与 Ubisoft 服务端记录：本版没有改写。游戏内进度计数接口仍待适配。':'Story, investigations, collectible counters and online records are not rewritten. Progress adapters remain pending.',
'02 / 玩家与通缉':'02 / Player and Police',
'03 / 点数与现金':'03 / Skill Points and Cash',
'先备份，再一次只测一项。技能点通过真实 Skillpoint 奖励键，不是虚构 SetSkillPoints。':'Back up and test one item at a time. Skill points use the actual Skillpoint reward key, not an invented API.',
' → 准备':' - prepare',
'04 / 线上门槛的本地奖励':'04 / Local Rewards Behind Online Requirements',
'这些是本地物品请求，不增加入侵 / 尾随 / 比赛次数，也不增加游戏内对应活动计数。':'These are local item requests. They do not complete online hacking, tailing, races or activity counters.',
'先测试单件；拿到后正常存档并重启，才可确认持久性。':'Test one item first. Save normally and restart to verify persistence.',
'准备四件线上奖励武器（不包含车辆）':'Prepare the four online-reward weapons - no vehicle',
'解密战的 Chicago Way / Firepower / Heavy Duty 配装仍未接入；不能用单机枪械冒充。':'Decryption loadouts are not implemented. Single-player weapons do not replace those records.',
'常规与特殊武器':'Standard and Special Weapons',
'已拥有的 ULC 武器':'Owned ULC Weapon Candidates',
'Bad Blood 武器':'Bad Blood Weapon Candidates',
'消耗品与材料':'Consumables and Materials',
'艾登商店服装':'Aiden Shop Outfits',
'已拥有的 ULC 服装':'Owned ULC Outfit Candidates',
'数字之旅奖励服装':'Digital Trip Reward Outfits',
'T-Bone 服装':'T-Bone Outfits',
'本体叫车奖励候选':'Main Campaign Car On Demand Reward Candidates',
'22 首曲目奖励候选':'22 Song Reward Candidates',
'05 / 白名单物品目录':'05 / Item Whitelist',
'全武器 / 全服装 / 全物品为当前模式白名单批次；实际拥有与持久解锁仍须核对。':'ALL batches mean the current-mode whitelist. Actual ownership and persistent unlocks need verification.',
'不含任务令牌、AccessIds、NPC/联机武器或 MOD 项。增加资源不会打开无限开关。':'No mission tokens, AccessIds, NPC/MP weapons or mod items. Adding resources does not enable infinite effects.',
'[ALL WEAPONS] 准备全部武器候选':'[ALL WEAPONS] Prepare all weapon candidates',
'[ALL CLOTHES] 准备全部服装候选':'[ALL CLOTHES] Prepare all outfit candidates',
'[ALL ITEMS] 准备全部可用物品候选':'[ALL ITEMS] Prepare all current-mode item candidates',
'准备本组（每项 1 件）':'Prepare this group - one of each',
'歌曲只有 22 个明确对应的键；Wake Up Sunshine 的映射未定，因此未伪装成 23/23。':'Only 22 song keys are mapped. Wake Up Sunshine remains unresolved; this is not a claim of 23/23.',
'06 / 车辆与世界':'06 / Vehicles and World',
'生成车辆仅供本次世界使用，最多 5 辆；不自动入座、不删除世界实体，不等于叫车解锁。':'Spawn at most five vehicles per session. No auto-seat or entity deletion. Spawning is not a delivery unlock.',
'已激活本次单机测试；所有持续开关仍为关闭。':'Single-player test armed. All continuous effects remain OFF.',
'待确认：':'Prepared: ',
' 项，每项 ':' entries, each ',
'。点击 [CONFIRM] 才会给予；[CANCEL] 取消。':'. Press [CONFIRM] to grant, or [CANCEL] to cancel.',
'待确认：现金 +':'Prepared: cash +',
'。点击 [CONFIRM] 执行。':'. Press [CONFIRM] to apply.',
'已请求生成车辆；这不是叫车解锁，也不增加线上比赛次数。':'Vehicle spawn requested. This is not a delivery unlock or an online race completion.',
'本批调用已提交，未回读。请核对物品/点数，再正常存档、重启验证。':'Batch submitted without readback. Check items or points, save normally, then restart to verify.',
'只读能力报告已写入宿主日志，仅列函数名，不扫描内存或读取账号。':'Read-only capability names logged. No memory scan or account data is exported.'
}
strings=re.compile(r'"(?:[^"\\]|\\.)*"')
def translate_source(name):
 text=(original/name).read_text(encoding='utf8')
 def replace(m):
  literal=m.group(0);v=literal[1:-1]
  if any(ord(c)>127 for c in v):
   if v not in translations:raise ValueError('Missing UI translation: '+v)
   return json.dumps(translations[v],ensure_ascii=True)
  return literal
 result=strings.sub(replace,text)
 assert result.isascii(),name
 # Ignore only string constants: code structure and callbacks must match exactly.
 assert strings.sub('"<TEXT>"',text)==strings.sub('"<TEXT>"',result)
 return result
for name in ['menu.lua','core.lua']:(R/'src/Plugin'/name).write_text(translate_source(name),encoding='ascii')
items=json.loads((R/'data/runtime_items.json').read_text())['items']
label_map={
'item_2546636026':'Blackout device','item_2559303206':'Jam Comms','item_1174431968':'ctOS Scan','item_416387092':'Lure',
'item_3651876853':'Frag Grenade','item_2840708499':'IED','item_2987530112':'Proximity IED','item_901132570':'Focus recovery pill',
'item_3108044763':'Electronic parts','item_673371641':'Chemical components','item_4088031736':'Explosive components','item_1125886109':'Recycled hardware','item_4292418427':'Pharmaceutical components','item_2257375190':'Battery reward - experimental',
'item_3623566901':'Alone reward outfit','item_3816380433':'Madness reward outfit','item_1815691869':'Spider-Tank reward outfit','item_2804586448':'Psychedelic reward outfit','item_389492496':'Conspiracy reward outfit'}
def item_label(item):
 if item['id'] in label_map:return label_map[item['id']]
 s=item['label_zh'];g=item['group'];db=item['db_name'].removeprefix('Items.')
 if s.isascii():return s
 if g=='skill':return 'Normal Skill Point reward +1'
 if g=='xp':return 'XP reward +'+db.removeprefix('XP_')
 if g=='clothes':return 'Aiden shop outfit '+db[-2:]
 if g=='bb_clothes':return 'T-Bone shop outfit '+db[-2:]
 if g=='dlc_clothes':return db+' outfit candidate'
 if g=='cars':return s.split('（')[0].strip()+' - delivery reward candidate'
 # Preserve the real database name if the explanatory Chinese display name has no exact English mapping.
 return db+' - candidate'
text='-- ASCII display labels only; IDs, modes and groups are unchanged.\nreturn {\n'
labels=[]
for i in items:
 label=item_label(i);assert label.isascii();labels.append({'id':i['id'],'zh_CN':i['label_zh'],'en_ASCII':label})
 values=[i['id'],i['key'],i['db_path'],label,i['group'],i['mode']]
 text+='  { id=%s, key=%s, name=%s, label=%s, group=%s, mode=%s },\n'%tuple(json.dumps(v,ensure_ascii=True) for v in values)
text+='}\n';(R/'src/Plugin/catalog.lua').write_text(text,encoding='ascii')
locale=R/'locales/en-ASCII';locale.mkdir(parents=True,exist_ok=True)
for name in ['menu.lua','core.lua','catalog.lua']:shutil.copyfile(R/'src/Plugin'/name,locale/name)
(R/'data/menu_localization.json').write_text(json.dumps({'active_game_menu':'en-ASCII','chinese_desktop_unchanged':True,'reason':'User reports question marks in custom game menu; source UTF-8 is valid. Exact host font/conversion cause not yet isolated.','strings':[{'zh_CN':k,'en_ASCII':v} for k,v in translations.items()],'item_labels':labels},ensure_ascii=False,indent=2)+'\n')
# Existing payload: patch only three display files, never reset receipt or native state.
for mode in ['campaign','dlc_solo']:
 dest=R/'payload'/('wd1kit_'+mode)/'workspace'/('wd1kit_'+mode)
 for name in ['menu.lua','core.lua','catalog.lua']:shutil.copyfile(R/'src/Plugin'/name,dest/name)
print('ASCII menu generated:',len(translations),'UI strings;',len(labels),'item labels. Game logic and command IDs unchanged.')
