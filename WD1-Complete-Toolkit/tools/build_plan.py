#!/usr/bin/env python3
"""Canonical user scope. Never delete an unimplemented feature to improve completion counts."""
from pathlib import Path
import json,csv,re,html
R=Path(__file__).resolve().parents[1]
rows=[]
def add(id,name,group,control,scope='campaign',backend='UNBOUND',note=''):
 rows.append(dict(id=id,name=name,group=group,control=control,scope=scope,backend=backend,implementation='UNBOUND' if backend=='UNBOUND' else 'IMPLEMENTED_CANDIDATE_NOT_GAME_VERIFIED',runtime_verified=False,note=note))
# Everything in the native contract is an individual control, not a claimed game-verified feature.
s=(R/'src/Native/Contracts.cs').read_text()
for x in re.findall(r'new Option\{(.*?)\}',s,re.S):
 get=lambda k:re.search(k+r'="([^"]*)"',x)
 if not get('Id'):continue
 d={k:get(k).group(1) if get(k) else '' for k in ['Id','Name','Group','Scope','Kind','Note']}
 add('native.'+d['Id'],d['Name'],d['Group'],'ACTION' if d['Kind'].startswith(('add_','once_')) else 'TOGGLE',d['Scope'],'NATIVE_CANDIDATE',d['Note'])
for id,name,group,control,scope in [
 ('god','上帝模式 / 无敌','玩家 / 资源','TOGGLE','campaign+dlc_solo'),('focus','无限专注','玩家 / 资源','TOGGLE','campaign+dlc_solo'),
 ('ammo','无限弹药（持续补给）','玩家 / 资源','TOGGLE','campaign+dlc_solo'),('ammo_once','单次补给弹药','玩家 / 资源','ACTION','campaign+dlc_solo'),
 ('police','暂停通缉系统','声誉 / 警察','TOGGLE','campaign+dlc_solo'),('cash','增加金钱（奖励接口）','金钱 / 成长','ACTION','campaign+dlc_solo'),
 ('skill','增加普通技能点（奖励接口）','金钱 / 成长','ACTION','campaign+dlc_solo'),('xp','增加经验（奖励接口）','金钱 / 成长','ACTION','campaign+dlc_solo'),
 ('all_weapons','全武器解锁 / 给予候选','物品 / 解锁','ACTION','mode-whitelist'),('all_clothes','全衣服解锁 / 给予候选','物品 / 解锁','ACTION','mode-whitelist'),
 ('all_items','全物品解锁 / 给予候选','物品 / 解锁','ACTION','mode-whitelist'),('item_select','按名称单件选择 / 增加数量','物品 / 解锁','ACTION','mode-whitelist'),
 ('vehicles','六类车辆生成','载具','ACTION','campaign+dlc_solo'),('clock','世界时刻设置','世界','ACTION','campaign+dlc_solo')]:
 add('lua.'+id,name,group,control,scope,'LUA_CANDIDATE','物品仅限已分类白名单；不等同进度完成、全库安全或持久拥有。' if group=='物品 / 解锁' else '')
# Unlimited and add are separate permanent requirements even when one backend is unbound.
materials=[('electronic','电子零件','3108044763'),('chemical','化学材料','673371641'),('explosive','爆炸材料','4088031736'),('hardware','回收零件','1125886109'),('medicine','药物材料','4292418427')]
for id,name,key in materials:
 add('resource.'+id+'.infinite','无限'+name,'材料 / 资源','TOGGLE',note='必须保留。尚未确认按物品分类的不扣减/锁定路径，不用增加按钮替代。')
 add('resource.'+id+'.add','增加'+name,'材料 / 资源','ACTION','campaign+dlc_solo','LUA_CANDIDATE','独立数量输入；Items.'+key)
for id,name in [('blackout','停电道具'),('jam','通讯干扰'),('ctos','ctOS 扫描'),('lure','诱饵'),('grenade','手榴弹'),('ied','IED'),('proximity','感应 IED'),('focuspill','专注恢复道具')]:
 add('consumable.'+id+'.infinite','无限'+name,'消耗品','TOGGLE',note='持续不扣减功能独立保留；不能用批量给予冒充。')
 add('consumable.'+id+'.add','增加'+name,'消耗品','ACTION','campaign+dlc_solo','LUA_CANDIDATE','使用白名单物品键，与无限开关无联动。')
for id,name,control in [('materials_infinite','无限全部材料','TOGGLE'),('resources_infinite_selective','各材料无限效果单独选择','TOGGLE'),('money_set','金钱设值','ACTION'),('money_sub','减少金钱','ACTION'),('item_readback','拥有状态 / 数量 / 解锁条件回读','READ'),('recipes','全制作配方解锁','ACTION'),('ownership_unlock','物品永久拥有与商店可购状态','ACTION')]:add('extra.'+id,name,'材料 / 资源' if 'infinite' in id else '物品 / 解锁',control,note='完整计划保留，未绑定项不允许假启用。')
for mode,label in [('spider','蜘蛛坦克'),('madness','疯狂'),('alone','孤独'),('dlc_solo','T-Bone 独立技能树')]:
 for part,title,control in [('skill_add','技能点增加','ACTION'),('skill_infinite','无限技能点','TOGGLE'),('xp_add','经验增加','ACTION'),('xp_multiplier','经验倍率','TOGGLE'),('unlock_tree','全技能 / 前置解锁','ACTION')]:
  add('growth.'+mode+'.'+part,label+'：'+title,'各模式成长',control,mode,note='各模式独立记录；不复用本体 Skillpoint 键伪装已实现。')
for id,name,scope in [('super_health','超级健康 / 生命上限','freeroam'),('heal','生命补满','freeroam'),('fall','坠落保护','freeroam'),('damage','玩家伤害倍率 / 一击','freeroam'),('move','移动速度倍率','freeroam'),('recoil','无后坐力','freeroam'),('spread','散布 / 稳定性','freeroam'),('firerate','射速','freeroam'),('spider_god','蜘蛛坦克上帝模式 / 无限生命','spider'),('spider_ammo','蜘蛛坦克无限弹药 / 导弹','spider'),('spider_cooldown','蜘蛛坦克技能冷却','spider'),('madness_soul','疯狂：无限灵力','madness'),('madness_god','疯狂：上帝模式 / 车辆生命','madness'),('madness_combo','疯狂：连击 / 分数','madness'),('alone_god','孤独：上帝模式','alone'),('alone_stealth','孤独：无探查','alone'),('nvzn_lives','NVZN 无限生命 / 次数','nvzn'),('nvzn_score','NVZN 分数 / 波次','nvzn'),('psychedelic_score','迷幻：分数 / 连击','psychedelic'),('conspiracy_detector','阴谋：无限探测器','conspiracy')]:add('mode.'+id,name,'人物 / 数字之旅','ACTION' if id=='heal' else 'TOGGLE',scope)
for id,name,scope,control in [('drinking_cursor','冻结饮酒游戏光标','drinking','TOGGLE'),('cashrun','冻结 Cash Run 计时器','cashrun','TOGGLE'),('vehicle_20min','将车辆计时器设置为 20 分钟','vehicle_activity','ACTION'),('racing','无限赛车计时器（不减少）','racing','TOGGLE'),('nvzn','冻结 NVZN 计时器','nvzn','TOGGLE')]:add('timer.'+id,name,'独立小游戏计时器',control,scope,note='不冻结整个游戏；饮酒光标不锁操作系统鼠标。没有证据时不复用其他模式计时器。')
for seat in range(1,5):
 for part,name,control in [('add','金钱 / 筹码增加','ACTION'),('set','金钱 / 筹码设值','ACTION'),('infinite','金钱 / 筹码无限','TOGGLE'),('target','其他资源/生命目标绑定','READ')]:
  add('player.'+str(seat)+'.'+part,'玩家 '+str(seat)+'：'+name,'玩家 1–4',control,'unresolved_target',note='保留四个独立目标。公开同名功能很可能指扑克三名 NPC 与玩家席位，尚未确认对象，不复制同一钱包四遍。')
for id,name,control in [('repair','当前载具修复','ACTION'),('tires','轮胎不爆','TOGGLE'),('handling','刹车 / 抓地 / 转向参数','TOGGLE'),('speed','车辆加速度 / 极速','TOGGLE'),('escort','任务护送车辆保护','TOGGLE'),('teleport','地图标记传送','ACTION'),('position','保存 / 返回坐标','ACTION'),('noclip','穿墙 / 自由移动','TOGGLE'),('fov','视野调整','TOGGLE'),('time_scale','游戏速度','TOGGLE'),('blackout','全城停电与持续时间','ACTION'),('hacking_cooldown','黑客冷却 / 范围','TOGGLE'),('chess','国际象棋挑战辅助','ACTION'),('poker','扑克小游戏辅助','ACTION'),('cups','猜杯辅助','ACTION')]:add('advanced.'+id,name,'载具 / 世界 / 小游戏',control)
for id,name in [('story','主任务 / 主线依赖'),('side','支线任务 / 中间人合约'),('investigation','调查线索与最终任务'),('collectibles','收集品 / 音频 / 歌曲 / 热点'),('minigames','小游戏挑战与奖励'),('online','游戏内在线合约计数与奖励'),('hideout','帮派据点'),('convoy','犯罪车队'),('crimes','犯罪侦测'),('ctos','ctOS 控制中心 / 塔 / 入侵'),('privacy','隐私入侵'),('notoriety','Notoriety / 恶名及本地奖励'),('coop','Bad Blood 合作与合约进度'),('rc','Eugene 升级链 / 冷却 / 电击 / C4'),('achievements','游戏内完成项 / 进度轮（不是平台成就）')]:
 add('progress.'+id,name,'游戏内进度','READ+ACTION','campaign+dlc_solo',note='先读取当前状态和依赖、备份，再针对性修改；不把给予武器视为任务完成。')
for id,name in [('search','搜索 / 分类 / 收藏'),('hotkey','每项快捷键与冲突提示'),('presets','按模式预设（载入不自动启用）'),('stop','总停止 + 单项停止'),('backup','备份 / 校验 / 恢复'),('profile','构建指纹与未知版本拒绝'),('logs','逐项错误与脱敏反馈')]:add('tool.'+id,name,'便利 / 保护','UI','all','TOOL_IMPLEMENTED' if id in ['search','hotkey','stop','backup','profile','logs'] else 'UNBOUND')
# Retain every original game-play acceptance requirement, excluding removed platform-achievement scope.
old_path=R/'data/feature_requirements.json'
if old_path.exists():
 old=json.loads(old_path.read_text())['items']
 retained=[x for x in old if int(x['id'].split('-')[1]) not in {140,141,142,144,145,146,147,150}]
 (R/'plan/original_gameplay_requirements.json').write_text(json.dumps({'note':'Historical gameplay acceptance requirements; platform-achievement-only entries removed by user correction. Current status is in complete_plan.json.','items':retained},ensure_ascii=False,indent=2)+'\n')
assert len({x['id'] for x in rows})==len(rows)
record={'plan_version':'2026-09-14-v3','user_confirmed':True,'game':'Watch Dogs 1 / Steam Complete Edition','meaning_of_achievement':'IN_GAME_PROGRESSION_ONLY','platform_achievement_module_removed':True,'infinite_is_not_replaced_by_add':True,'all_prior_gameplay_scope_retained':True,'items':rows}
(R/'data/complete_plan.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
with (R/'data/complete_plan.csv').open('w',encoding='utf-8-sig',newline='') as h:w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
text='# 用户确认的完整计划 — 永久保留，不随当前完成率删项\n\n版本：2026-09-14-v3。用户最新补充已合并。这里的“成就”始终指**游戏内进度/完成系统**；平台成就模块已经移除。\n\n## 不可丢失的规则\n\n1. 无限资源与增加资源都要做，独立开关/操作；绝不以后者替代前者。\n2. 全武器、全衣服、全物品解锁/给予均保留；还要区分当前背包、永久拥有与解锁进度。\n3. 本体、Bad Blood、蜘蛛坦克、疯狂、孤独等成长记录不混用。\n4. 九类计时/光标请求逐项保留；不能用冻结整个游戏充数。\n5. 玩家1–4必须是四个已识别目标，不能复制同一钱包。\n6. 所有功能可单独选择；一键预设不能代替单项控制。\n7. 不给未知地址/未绑定项目一个能亮起的假开关，不以模拟测试声称游戏通过。\n8. 继续保留主线/支线/调查/收集/线上合约/小游戏/RC/世界参数等既有范围；原逐项验收保存在 plan/original_gameplay_requirements.json，不能仅保留大类而丢失细项。\n\n'
for group in dict.fromkeys(x['group'] for x in rows):
 text+='## '+group+'\n\n| 编号 | 功能 | 独立控件 | 当前实现 |\n|---|---|---|---|\n'
 for x in rows:
  if x['group']==group:text+='| '+x['id']+' | '+x['name']+' | '+x['control']+' | '+x['backend']+' |\n'
 text+='\n'
text+='所有 IMPLEMENTED_CANDIDATE 都未经过用户真实游戏验证；UNBOUND 是保留但未接通，不是被删除。详细备注见 data/complete_plan.json。\n'
(R/'plan/用户确认的完整计划.md').write_text(text)
body=''.join('<tr><td>'+html.escape(x['group'])+'</td><td>'+html.escape(x['name'])+'</td><td>'+x['control']+'</td><td>'+('待绑定，仍在计划中' if x['backend']=='UNBOUND' else '代码已接入，待实测')+'</td><td>'+html.escape(x['note'])+'</td></tr>' for x in rows)
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WD1 完整计划</title><style>body{background:#0d1625;color:#e6f0fa;font:15px/1.65 system-ui,"Microsoft YaHei UI";margin:32px}h1{color:#50d5b4}p{max-width:1000px;color:#bfd1e5}input{width:90%;padding:14px;background:#17263d;color:white;border:1px solid #53708d;margin:20px 0}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:12px;border:1px solid #31465f;text-align:left;vertical-align:top}th{color:#50d5b4}small{color:#eac983}</style><h1>完整计划：无限与增加都保留</h1><p>用户确认范围 · 2026-09-14-v3。成就=游戏内进度系统；无平台成就模块。全武器、全衣服、全物品、各模式成长、所有计时器、玩家1–4与此前游戏玩法范围一并保留。</p><small>UNBOUND 项暂不能修改游戏，未被删除。候选实现不等于真实游戏验证。</small><br><input id="q" placeholder="筛选，例如：无限、增加、蜘蛛、进度、玩家 4"><table><thead><tr><th>分类</th><th>功能</th><th>独立控件</th><th>状态</th><th>说明</th></tr></thead><tbody>'''+body+'''</tbody></table><script>document.getElementById('q').oninput=function(){let q=this.value.toLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.style.display=r.textContent.toLowerCase().includes(q)?'':'none')}</script></html>'''
(R/'完整计划.html').write_text(page)
print('Canonical independent plan records:',len(rows),'unbound:',sum(x['backend']=='UNBOUND' for x in rows))
