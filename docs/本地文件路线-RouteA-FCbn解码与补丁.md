# 本地文件路线（Route A）· FCbn/FAT3 解码与补丁构建 · 2026-09-17

## 结果
- **vanilla patch.dat（949 条）+ patch1.dat（234 条）100% 解码成功**（XMem-LZX）。
- **UCOD 解锁载体确认**：其 patch.dat 内 `81165196` 号条目（FCbn 对象库，948,429 B）
  即全部解锁内容；其余 45 条与解锁无关。
- 已产出**自建超集补丁**：`WD1-CarUnlock-RouteA-v1.zip`（patch2.dat/fat，591,981 B）。
  覆盖 74/74 目录车 + 隐藏槽 0x0FFFFF29/2A/2B/2C + 新增 Speed_08 记录。

## FAT3 v8 条目版式（16 B，官方 WD1，flags=0x00320504 = plat4|CV5|NHV50）
```
a u32 nameHash（升序）
b u32 (uncompressedSize29 << 3) | scheme3      # CV5: 0=None 1=LZO1x 2=Zlib 3=XMemCompress
c u32 ((offset & 7) << 29) | compressedSize29  # offset = (d<<3) | (c>>29)
d u32 offset >> 3
```
- scheme 0 且 uncSize=0 时按 compressedSize 读（UCOD 条目即如此）。
- CV5 scheme 3 的块 = **XMemCompress（微软 LZX，window=32768=15 bits）**：
  - 块头 48 B 大端：magic 0x0FF512EE、ver 0x01030000、0、0、window、chunk、
    u64 uncSize、u64 compSize、u32 largestUnc、u32 largestComp；
  - 之后每块：u32 BE 压缩长 + 载荷；载荷 = 子块序列
    （`FF + u16 未压长 + u16 压缩长 + 数据` 或 `u16 压缩长 + 数据`），
    子块数据 = 标准 LZX 位流（每块独立上下文，reset_interval=0）。
  - 解码器：`tools/xmemlzx`（libmspack lzxd 移植，源码 `tools/lzxd_src/`）。
  - 旧假设废除：`0f f5 12 ee` 不是"每文件都有的流头"，仅 scheme3 文件有；
    LZO 假设全错，vanilla 用的不是 LZO。
- 404 个 scheme3 条目 + 545 个 stored 条目（patch）；patch1 同版式。

## FCbn（BinaryObjectFile v3）
```
u32 'FCbn'(字节序 6e 62 43 46) u16 ver=3 u16 flags=0 u32 objCount u32 valCount + 递归对象
对象: childCount(u8<0xFE 内联 / 0xFE+u32 对象引用 / 0xFF+u32 内联)
      u32 nameHash; valueCount(内联); 每个 field: u32 hash + 大小(可反向引用) + bytes; 然后 children
```
- 关键 field hash：0x9d8873f8=记录名、0x43fb7444=类名(ItemDescriptorCar)、
  0x94fc20c4=规则类名、0xb9295cc7/0x389f6da7=车辆 item key(u32 LE)、
  0x8bc20820=可用性规则容器、0xa90f3bcc=**车辆奖励池容器**。
- vanilla 8,979 对象（大量 DAG 共享+反向引用）；UCOD 39,395 对象（纯内联展开）。
- Python 解析/重建：`tools/bof.py`（UCOD 文件往返字节一致；vanilla 展开重建语义等价）。

## UCOD 的真实机制（字节级确认）
- 车辆池内 73 条 `CarHackingRewards.Generic.*` 记录两侧相同；
- UCOD 向池内追加 45 条记录副本：每副本把 item key 换成隐藏槽
  0x0FFFFF29(警)/2A(疯狂)/2B/2C(Muscle_05)，且 child 的 0xe69fad16 置 false；
- 即：**隐藏车 = 同名记录绑隐藏 item key 的新增记录**（新增驱动，非删除/改字段）。
- UCOD 直接替换整个 81165196 文件会丢 vanilla 808 个实例（含 DLC.dlc01_SteadyAim 等）。

## 超集补丁构造（tools/build_car_patch.py）
1. vanilla 树不动；定位 0xa90f3bcc 池（vanilla 2622 children / UCOD 2457）；
2. 追加 UCOD-only 45 条（内容多重集差，逐实例深拷贝）；
3. 克隆 Speed_01 模板生成 `CarHackingRewards.Generic.Speed.Speed_08`
   （key 3870519146=0xE6B36F6A，双方原库均无此车）；
4. 重建 FCbn（591,981 B）→ patch2.dat（stored）+ patch2.fat（1 条目，36 B）。
   验证：自解码往返一致；74/74 key 命中；4 隐藏槽各 1 条。

## 待用户验证
- patch2 级联槽是否生效（未证实）。若无效 → 用同内容重打 patch.dat/patch1.dat
  替换式交付（全部格式已可写，`build_car_patch.py` 扩展即可）。

## 工具链（本仓库 tools/）
- `dunia_fat.py`：FAT3 v8 提取器（scheme 0/3）。
- `bof.py`：FCbn 解析/重建。
- `build_car_patch.py`：超集补丁构建器（输入 vanilla 对 + UCOD 对 + 74 车 csv）。
- `lzxd_src/` + `build_xmemlzx.sh`：XMem-LZX 解码器（libmspack lzxd，LGPL——
  仅本地构建运行，未随补丁分发）。
- 复现：
  `gcc -O2 -o tools/xmemlzx tools/lzxd_src/xmemlzx.c tools/lzxd_src/lzxd.c -Itools/lzxd_src`
  `python3 tools/build_car_patch.py <van.dat> <van.fat> <ucod.dat> <ucod.fat> <outdir>`

## v2 合并式整包（2026-09-17，用户实测 patch2 无效后）
- **patch2 级联槽确认死亡**：用户实装 patch2 对，能正常进存档但车单无变化。
  与 Nexus Mod Installer（mod 15，"merge many mods in patch.dat/fat"）的
  社区流程互相印证：WD1 只认 patch.dat/patch1.dat，安装=合并进本体。
- `tools/build_replacement_patch.py`：vanilla patch 对基础上仅替换
  81165196 条目为超集库，其余 948 条压缩流逐字节原样重排 + fat 重建
  （同 hash 同顺序同 flags 0x00320504）；patch1 对用原版原样。
- 自验：949/949 条目解压结果与 vanilla 逐字节一致（目标条目=超集库）；
  端到端 74/74 key + 4 隐藏槽。产物 `WD1-CarUnlock-RouteA-v2.zip`
  （patch.dat 24,741,421 B / patch.fat 15,204 B / patch1 对原版）。
- patch1 与 patch 的 nameHash 交集 57 个，但都不含 81165196 → 无论
  级联方向如何，patch.dat 中的车辆库都生效。
- superset 构建已重构为 `build_car_patch.superset_blob()`（确定性，
  重建字节一致 591,981 B）。

## NGM 整合套件（2026-09-17）
用户计划安装 NextGen Merge 1.0（Nexus mod 437，3.0GB 全家桶，Xbox/PS 手柄两版；
官方 INSTALL=拖拽进游戏主目录；279 项 shader fixes 为 3DMigoto 可选件）。
用户只要玩法部分、不要光影。NGM 含 Drive On Demand expansion——
有动车辆库（81165196）的可能，禁止盲目拼接。
- `tools/ngm_splice/` + `WD1-NGM-CarMerge-v1.zip`：PowerShell 拼接器。
  逻辑=读 data_win64 现有 patch 对 → 目标条目存在则替换 / 缺失则按
  nameHash 升序插入 → 顺序重排 offset → 重建 fat → 重读自验 →
  .carbak 备份 → 生成 ngm_diff_manifest.txt（相对 vanilla 清单的
  EXTRA/DIFF 审计）；若 NGM 自带 81165196 且压缩 → 导出
  ngm_81165196_payload.bin 供我方 XMem-LZX 解码做对象级深合并。
- 算法已 Python 等价验证：替换路径产物与 v2 整包逐字节一致；
  插入路径（目标缺失）偏移/条目/端到端解码全部通过。
- 等价算法注意点（PS 版已按此实现）：srcOff（旧偏移）与 newOff 分离，
  遍历写入用 srcOff、写表用 newOff；hashtable 键访问 dot 语法 PS5.1 可用。
- 深合并路径：ngm_81165196_payload.bin → xmemlzx 解码 → bof.parse →
  find_pool → 与 superset 池做内容多重集并 → bof.build → 新 car_db blob
  （工具同款拼接器直接吃）。

## 2026-09-17 晚间结论汇总
### 中文问题定论（用户实测：简体=空白，繁体=完全正常）
- WD1 官方字体图集只内置**繁体**中文字形；简体专有字形（发/门/见等）不在图集
  → 简体模式=空白。繁体模式=字形齐全 → **用户以繁體中文游玩为正解**。
- NGM 与繁体模式兼容；此前"文字全消失"=当初选择性安装损坏，完整重装后不复存在。
- 工具包已生成 locales/zh-Hant/Plugin/{catalog,core,menu}.lua（zhconv 简转繁，
  LuaJIT loadfile 语法验证通过）。0.4.22 发布时切换 payload 至 zh-Hant
  （繁体模式下菜单原生中文显示；en-ASCII 保留为兜底）。

### NGM exports 判读（用户已传 500 文件 + manifest 至 main）
- NGM diff=4651 条：EXTRA 4244（NGM 新增，不动）+ DIFF 407（NGM 覆盖的原版条目）。
- DIFF∩CJK=395（cjk_damage_list.csv 已存 tools/ngm_splice/）。
- 抽样深查：多数 nbCF 内容与原版逐字节一致（仅重打包），仅个别浮点微调
  → **无需大规模恢复；简体空白根因在字体不支持，不在档案损坏**。

### 路线 B 日志（uploads/WD1KIT_log.txt，0.4.21 DUMP API）
- 2649 函数 → 去重 1382 唯一名（tools/ngm_splice/api_functions_unique.txt）。
- 关键确认：ForceSetCash/GiveCash/RemoveCash、ForceSetXP、ForceSetSkillPoint、
  Felony 族 30+（SetHeat/MaxHeat/ResetMaxHeat/SystemEnable/StartChase...）、
  AddPerkWithDbObj/RemovePerkWithDbObj/GetMadnessMasteryPerkValue。
- **GiveCash(0,n) 已由用户 0.4.20 实测验证**（project.json 记录；0=本地玩家索引）。
- UnlockAndBuyCarOnDemand 运行时形状已穷尽（负结论），文件路线已解决车辆。

### 0.4.22 修改器发布计划
1. 现金地板 100 万：GiveCash(0,n) 差额补足（已验证签名）。
2. 技能点/经验/通缉清除：[SIG PROBE] 模式——对 13 个目标函数做
   0 参 + 垃圾类型（全"?"字符串/nil）pcall 探测，错误信息暴露 arity/类型；
   探测永不让调用成功（零数据变更），[SIGPROBE] 行落盘日志，用户跑一次回传。
3. zh-Hant payload 切换 + 版本戳 0.4.22 + 验证器更新 + 全量发布。
