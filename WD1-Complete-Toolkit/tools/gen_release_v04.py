#!/usr/bin/env python3
"""v0.4.0 release generator: full unlock catalog from the public NexusTools.Trainer item DB.

Reproduces, filters and regroups the public item list so every unlockable progression
reward (mission XP, notoriety/online rewards, ctOS towers, mini-game progression,
skill points, cash, cars, weapons incl. special variants, outfits, upgrades, tokens)
is available as a single-player AddItem candidate. No game or process calls here.
"""
from pathlib import Path
import json, re, csv, html, collections

R = Path(__file__).resolve().parents[1]
TRAINER_DB = Path('/tmp/nxtrainer/workspace/trainer/data/Items.lua')
if not TRAINER_DB.exists():
    TRAINER_DB = Path('/tmp/nxtrainer/workspace/trainer/data/Items.lua')

# ---------------------------------------------------------------- parse curated 218
CURATED = []
for m in re.finditer(r'\{ id="(item_\d+)", key="(\d+)", name="([^"]+)", label="([^"]*)", group="([^"]+)", mode="([^"]+)" \}',
                     (R/'src/Plugin/catalog.lua').read_text(encoding='utf-8')):
    CURATED.append(dict(id=m.group(1), key=m.group(2), name=m.group(3), label=m.group(4),
                        group=m.group(5), mode=m.group(6)))
assert len(CURATED) == 218, len(CURATED)
curated_zh = {}
with (R/'data/runtime_items.csv').open(encoding='utf-8-sig', newline='') as h:
    for row in csv.DictReader(h):
        curated_zh[row['id']] = row['label_zh']

# ---------------------------------------------------------------- parse trainer DB
text = TRAINER_DB.read_text(encoding='utf-8', errors='replace')
trainer = []
pat = re.compile(r'\{\s*key\s*=\s*"(\d+)"\s*,\s*name\s*=\s*"([^"]*)"\s*,\s*prefix\s*=\s*"([^"]*)"\s*,\s*category\s*=\s*"([^"]*)"\s*\}')
for m in pat.finditer(text):
    trainer.append(dict(key=m.group(1), name=m.group(2), prefix=m.group(3), category=m.group(4)))
assert len(trainer) == 2753, len(trainer)

EXCLUDED_CATEGORIES = {'E3_2012', 'E3_2013', 'Cloths_DEPRECATED', '_DUMMY_ITEMS'}

GROUP = {
    'Weapon': 'weapons', 'custom_Weapon': 'custom_weapons',
    'Clothing_SP': 'clothes', 'Clothing_MOD': 'clothes_mod', 'Clothing_ULC': 'dlc_clothes',
    'CarHackingRewards': 'cars', 'Song': 'songs',
    'ProgressionBonus': 'xp', 'SkillPointReward': 'skill',
    'MainMissionXP': 'mission_xp_main', 'SideMissionXP': 'mission_xp_side', 'FamilyMissionXP': 'mission_xp_family',
    'VigilanteHackingReward': 'notoriety', 'VigilanteHackingRewardMissions': 'notoriety', 'Vigilante': 'notoriety',
    'ctOSTower_GenericRewards': 'ctos_rewards',
    'ActivityProgressionScreen': 'activity_rewards', 'DLC_ActivityProgressionScreen': 'activity_rewards',
    'Cash': 'cash_items', 'Upgrades': 'upgrades',
    'Tech': 'tech', 'Projectiles': 'projectiles', 'Explosives': 'explosives',
    'Bullet': 'ammo', 'MP_AmmoBags': 'ammo',
    'Meds': 'meds', 'Food': 'food',
    'Application': 'apps', 'IllegalAppMP': 'apps',
    'Collectibles': 'collectibles', 'AudioDrops': 'audio_drops', 'MauricePhoneAudio': 'audio_drops',
    'VideoLogs': 'video_logs', 'SurvivalGuide': 'survival_guide', 'GangWarsGuide': 'survival_guide',
    'jeans02': 'special_perks',
    'Convoy20': 'progress_misc', 'BrandWeek': 'progress_misc', 'FoundBagEvent': 'progress_misc',
    'NarrativeMoment': 'progress_misc', 'MainMissionsFelonyProgression': 'progress_misc',
    'Missions': 'progress_misc', 'FoundbagsHackingrewards': 'progress_misc',
    'Valuable': 'misc_items', 'General': 'misc_items', 'Misc': 'misc_items', 'ToyCar': 'misc_items',
    'Custom': 'misc_items', 'DLC': 'bb_items', 'dlc01_MainMission': 'bb_items',
    'dlc01_DrivingCashRewards': 'bb_items',
    'AccessIds': 'mission_tokens', 'AccessIds_EventManagerDiffUnlocks': 'mission_tokens',
    'OneTimeContractBurnAccessIDs': 'mission_tokens', 'OneTimeContractBurnAccessIDs_DrivingJobs': 'mission_tokens',
    'IoP': 'mission_tokens', 'IoP_ICs': 'mission_tokens', 'IoP_MapIcons': 'mission_tokens',
    'IoP_VRAccess': 'mission_tokens', 'HackableNPC': 'mission_tokens', 'HumanTraffic': 'mission_tokens',
    'MissionSpecific': 'mission_tokens', 'MissionSpecificSMS': 'mission_tokens',
    'MissionSpecificICs': 'mission_tokens', 'MissionSpecificEmails': 'mission_tokens',
    'SideInvestigationMissions': 'mission_tokens', 'EventMananger': 'mission_tokens', 'Email': 'mission_tokens',
}

def clean_label(name):
    return name.replace('\t', ' ').strip() or 'Unnamed entry'

def ascii_only(s):
    return ''.join(ch if 32 <= ord(ch) < 127 else ' ' for ch in s).strip()

entries = {}   # id -> dict, curated first (they win)
def add(entry):
    if entry['id'] in entries:
        return
    entries[entry['id']] = entry

for it in CURATED:
    add(it)

skipped = collections.Counter()
for it in trainer:
    if it['category'] in EXCLUDED_CATEGORIES or '.Empty' in it['name'] or not it['name']:
        skipped[it['category'] or 'unknown'] += 1
        continue
    group = GROUP.get(it['category'])
    if group is None:
        skipped['UNMAPPED:' + it['category']] += 1
        continue
    idv = 'item_' + it['key']
    if idv in entries:
        continue
    name = clean_label(it['name'])
    mode = 'both'
    if 'dlc01' in name or it['category'] in ('DLC', 'dlc01_MainMission', 'dlc01_DrivingCashRewards',
                                             'DLC_ActivityProgressionScreen'):
        mode = 'dlc_solo'
    if it['category'] in ('Clothing_SP', 'Clothing_MOD', 'Clothing_ULC'):
        mode = 'campaign'
    add(dict(id=idv, key=it['key'], name='Items.' + it['key'],
             label=ascii_only(name), group=group, mode=mode))

order = ['skill', 'xp', 'mission_xp_main', 'mission_xp_side', 'mission_xp_family',
         'notoriety', 'ctos_rewards', 'activity_rewards', 'progress_misc', 'cash_items', 'special_perks',
         'weapons', 'custom_weapons', 'dlc_weapons', 'bb_weapons', 'supplies', 'upgrades', 'tech',
         'projectiles', 'explosives', 'ammo', 'meds', 'food', 'misc_items', 'bb_items',
         'clothes', 'clothes_mod', 'dlc_clothes', 'trip_clothes', 'bb_clothes',
         'cars', 'songs', 'collectibles', 'audio_drops', 'video_logs', 'survival_guide',
         'apps', 'mission_tokens']
assert set(order) == {e['group'] for e in entries.values()}, (
    set(order) ^ {e['group'] for e in entries.values()})
rank = {g: i for i, g in enumerate(order)}
final = sorted(entries.values(), key=lambda e: (rank[e['group']], e['label'], e['key']))

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def write_catalog(path, labels):
    out = ['-- ASCII-safe generated unlock catalog v0.4.0 (full progression reward path).',
           '-- Sources: project runtime_items curation + public NexusTools.Trainer Items DB.',
           'return {']
    for e in final:
        label = labels(e)
        out.append('  { id=%s, key=%s, name=%s, label=%s, group=%s, mode=%s },' % (
            lua_str(e['id']), lua_str(e['key']), lua_str(e['name']),
            lua_str(label), lua_str(e['group']), lua_str(e['mode'])))
    out.append('}')
    path.write_text('\n'.join(out) + '\n', encoding='utf-8')

write_catalog(R/'src/Plugin/catalog.lua', lambda e: e['label'])
write_catalog(R/'locales/en-ASCII/catalog.lua', lambda e: e['label'])

zh_map = curated_zh
def zh_label(e):
    return zh_map.get(e['id'], e['label'])
write_catalog(R/'locales/zh-CN/Plugin/catalog.lua', zh_label)

# ---------------------------------------------------------------- runtime_items csv/json
with (R/'data/runtime_items.csv').open(encoding='utf-8-sig', newline='') as h:
    old_rows = {row['id']: row for row in csv.DictReader(h)}
rows = []
for e in final:
    old = old_rows.get(e['id'])
    rows.append({
        'id': e['id'], 'key': e['key'], 'db_path': e['name'], 'db_name': e['name'],
        'label_zh': zh_label(e), 'group': e['group'], 'mode': e['mode'],
        'source_category': old['source_category'] if old else 'TrainerItemDB',
        'status': old['status'] if old else 'REWARD_ITEM_CANDIDATE',
        'note': old['note'] if old else 'single-player AddItem path; persistence unverified',
    })
with (R/'data/runtime_items.csv').open('w', encoding='utf-8-sig', newline='') as h:
    w = csv.DictWriter(h, fieldnames=['id','key','db_path','db_name','label_zh','group','mode',
                                      'source_category','status','note'])
    w.writeheader(); w.writerows(rows)
(R/'data/runtime_items.json').write_text(json.dumps(
    {'project': 'WD1KIT', 'version': '0.4.0-alpha', 'count': len(rows), 'items': rows},
    ensure_ascii=False, indent=1), encoding='utf-8')

# ---------------------------------------------------------------- counts summary
groups = collections.Counter(e['group'] for e in final)
modes = collections.Counter(e['mode'] for e in final)
print('TOTAL', len(final))
for g in order:
    print(' ', g, groups[g])
print('modes', dict(modes))
print('skipped', dict(skipped))

# ---------------------------------------------------------------- Chinese reference HTML
group_zh = {
    'skill': '技能点奖励', 'xp': '经验奖励', 'mission_xp_main': '主线任务经验奖励',
    'mission_xp_side': '支线任务经验奖励', 'mission_xp_family': '家族任务经验奖励',
    'notoriety': '罪恶值 / 线上进度奖励（本地授予）', 'ctos_rewards': 'ctOS 控制中心奖励',
    'activity_rewards': '小游戏进度奖励', 'progress_misc': '其他进度奖励',
    'cash_items': '现金奖励物品', 'special_perks': '特殊加成',
    'weapons': '武器', 'custom_weapons': '特殊武器变体', 'dlc_weapons': '已拥有的ULC武器',
    'bb_weapons': 'Bad Blood 武器', 'supplies': '材料与消耗品', 'upgrades': '制作与升级',
    'tech': '科技与图纸', 'projectiles': '投掷物', 'explosives': '爆炸物', 'ammo': '弹药',
    'meds': '药品', 'food': '食物', 'misc_items': '杂项物品', 'bb_items': 'Bad Blood 物品',
    'clothes': 'Aiden 服装', 'clothes_mod': '服装外观', 'dlc_clothes': '已拥有的ULC服装',
    'trip_clothes': '数字之旅奖励服装', 'bb_clothes': 'T-Bone 服装',
    'cars': '车辆解锁奖励（叫车目录）', 'songs': '歌曲奖励', 'collectibles': '收集品',
    'audio_drops': '音频记录', 'video_logs': '视频日志', 'survival_guide': '生存指南页面',
    'apps': '手机应用（部分为多人标记）', 'mission_tokens': '任务令牌 / AccessId（仅逐项，不提供批量）',
}
ui_zh = [
    ('WD1 KIT - Main [UI4]', '工具箱主菜单（看到 [UI4] 才说明新插件已装上）'),
    ('00 / Quick Controls', '00 / 快速控制（不依赖面板布局的应急按钮）'),
    ('[PING] Test this button - no game changes', '[PING] 测试回调（不改动游戏）'),
    ('[ARM] I am offline and in single-player free roam', '[ARM] 确认：我处于单机自由探索（激活授权）'),
    ('[ARM] Enable this offline test session', '[ARM] 启用本次离线测试会话'),
    ('[CONFIRM] Apply the prepared item or cash request', '[CONFIRM] 确认执行已准备的物品/金钱请求'),
    ('[CONFIRM] Apply prepared request', '[CONFIRM] 应用已准备的请求'),
    ('[CANCEL] Cancel item or cash queue', '[CANCEL] 取消队列'),
    ('[STATUS] Show armed / god / script', '[STATUS] 查看状态（授权/无敌/脚本）'),
    ('[STOP] Disable effects and cancel pending requests', '[STOP] 关闭全部效果并取消请求'),
    ('[STOP] Disable all tool effects', '[STOP] 关闭本工具全部效果'),
    ('[REPORT] Write capabilities and UI state to host log', '[REPORT] 把能力与界面状态写入宿主日志'),
    ('[REPORT] Log capabilities and UI status', '[REPORT] 记录能力与UI状态'),
    ('God Mode', '无敌（上帝模式）'),
    ('God Mode ON', '无敌 开'), ('God Mode OFF', '无敌 关'),
    ('Infinite Ammo - continuous refill', '无限弹药（持续补满）'),
    ('Infinite Ammo ON / OFF', '无限弹药 开 / 关'),
    ('[ADD AMMO] Refill ammo once', '[补弹一次] 立即补满弹药'),
    ('Infinite Focus - continuous refill', '无限专注（持续）'),
    ('Infinite Focus ON / OFF', '无限专注 开 / 关'),
    ('Disable Wanted System', '关闭通缉（警察）系统'),
    ('Wanted Heat input 0-100', '通缉热度输入 0-100'),
    ('Apply Wanted Heat', '应用通缉热度'),
    ('Item / material quantity to add', '物品/材料数量'),
    ('Cash to add', '增加金钱数额'),
    ('Normal Skill Point rewards - test +1 first', '普通技能点奖励（先测试 +1）'),
    ('Prepare normal Skill Point reward', '准备普通技能点奖励'),
    ('Prepare Cash - then CONFIRM', '准备金钱 → 再按 CONFIRM'),
    ('Hour / Minute', '小时 / 分钟'),
    ('Apply Time - restart to release scripted clock', '应用时间（重启游戏解除锁定）'),
    ('Clicks / Updates / Loads / Polls', '点击数 / 更新数 / 载入数 / 轮询数（诊断面板）'),
    ('Armed / God / Alive / Paused', '已授权 / 无敌 / 存活 / 暂停'),
    ('Spawn ...', '生成载具（非永久解锁）'),
    ('Prepare this group - one of each', '准备本组各 1 个（之后按 CONFIRM）'),
    ('Prepare ALL ...', '准备整组（之后按 CONFIRM）'),
    ('Tick the checkbox once: it executes and resets itself', '点动式开关：勾一次执行一次并自动复位'),
]
by_group = collections.OrderedDict((g, []) for g in order)
for e in final:
    by_group[e['group']].append(e)
h = ['<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">',
     '<title>WD1 KIT UI4 菜单中文对照</title>',
     '<style>body{font-family:sans-serif;margin:24px}table{border-collapse:collapse;margin:8px 0 24px}',
     'td,th{border:1px solid #bbb;padding:3px 10px;font-size:14px}h2{margin:18px 0 4px}',
     '.note{background:#fff7e0;border:1px solid #e0c060;padding:8px 12px}</style></head><body>',
     '<h1>WD1 KIT UI4 菜单中文对照（v0.4.0）</h1>',
     '<div class="note">游戏内菜单为 ASCII 英文（宿主字体限制）。此页为人工人读对照；条目总数 %d。' % len(final),
     '武器/服装/车辆等新条目为游戏内部英文名，官方未提供中文的条目保持英文原名。</div>',
     '<h2>固定界面文字</h2><table><tr><th>英文</th><th>中文</th></tr>']
for en, zh in ui_zh:
    h.append('<tr><td>%s</td><td>%s</td></tr>' % (html.escape(en), html.escape(zh)))
h.append('</table>')
for g in order:
    h.append('<h2>%s (%d)</h2><table><tr><th>游戏内显示</th><th>中文说明</th></tr>' %
             (html.escape(group_zh[g]), len(by_group[g])))
    for e in by_group[g]:
        zh = curated_zh.get(e['id'])
        h.append('<tr><td>%s</td><td>%s</td></tr>' % (
            html.escape(e['label']),
            html.escape(zh if zh else '（内部条目名，功能以英文名为准）')))
    h.append('</table>')
h.append('</body></html>')
(R/'UI4菜单中文对照.html').write_text('\n'.join(h), encoding='utf-8')
print('files written')
