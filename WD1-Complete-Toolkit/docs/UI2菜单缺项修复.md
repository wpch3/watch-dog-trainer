# UI2：修复只显示标题和 STOP 的菜单路径

## 用户实际看到的情况

ASCII文字已可读；但“02 / Player and Police”只显示公共标题和STOP，缺少ARM和God Mode。

这表明原分类没有完整显示。**没有取得宿主Lua异常日志，不能断定具体是哪一个API或上值处理出错。** 不能把本补丁的防护设计当成已证实的唯一根因，也不要求用户改游戏版本、站位或重装宿主。

## 修复方式

- 去掉分类布局中调用捕获的 `fn(root)` 的通用嵌套构建方式。每页显式定义Layout回调，回调不捕获外部构建函数，从全局强引用UI状态取数据。
- 关键操作使用普通回调按钮。ARM、STOP、God Mode ON、God Mode OFF在任何可选CommandWidget之前创建。
- 布尔复选框仍保留；若某个CommandWidget失败，显示 `UI ERROR` 并记录 `UI2_ERROR`，不中断后续控件。
- 普通按钮的行为通过全局动作表按基本类型编号分发，不捕获函数/表作为宿主按钮回调的上值。
- Script/OnUpdate/暂停/卸载生命周期在可选UI创建前注册，避免UI中段失败导致无更新回调。
- 若宿主提供文档中的 `SH_Menu_AddButton_CB`，另建 **00 / Quick Controls**：不依赖Layout/CommandWidget，提供ARM、God Mode ON/OFF、STATUS、STOP、REPORT。
- 保留物品、服装、武器、独立增量、无限与其余既有菜单。未接通项目没有伪装成已实现。

准确API依据仍是作者文档和公开Trainer：
https://www.kaverti.com/en/TroploNexusTools/Lua/SH_Menu
https://www.kaverti.com/en/TroploNexusTools/Lua/SH_Commands
https://github.com/Troplo/NexusTools.Trainer

## 不变的部分

- 桌面EXE不换，原生加钱路线和金钱存档不变。
- 游戏逻辑仍走原有core；物品键、备份/单机门槛与默认关闭不变。
- 命令ID保留；UI文本继续ASCII。
- 中文目标与完整功能计划保留，不把ON/OFF备用按钮解释成永久删除独立复选框。

## 安装与首次操作

1. 正常退出游戏，原生面板若有捕获/补丁先安全断开。
2. 将补丁里的payload合并覆盖到WD1-Toolkit.exe所在的工具目录。
3. 在原工具“01 安装与启动”点击“安装 / 更新游戏插件”，使用有效备份；不需要重装宿主。
4. 完整重启游戏。菜单应带版本标识 **WD1 KIT - Main [UI2]**。
5. 优先进入 **00 / Quick Controls**：先ARM，再God Mode ON；用STATUS查看armed/god/script；God Mode OFF或STOP关闭。
6. 若没有00，则看 **02 / Player and Police** 中的普通ARM、God Mode ON/OFF按钮。这些按钮不依赖复选框。

若仍只看到旧的“ASCII MENU - ALPHA...”标题，说明新的menu.lua没有载入，先不要做伤害测试。若看到了UI2但仍缺按钮，请只说明00是否出现及任何 `UI ERROR`；也可提供宿主日志里的 `[WD1KIT] UI2_...` 行，不需要截图或完整日志。

## 测试边界

335项原Lua断言、1884项ASCII文本/目录/回调断言、106项新增UI2延迟布局/异常/备用控制断言通过。新增测试刻意延迟Layout执行，模拟CommandWidget失败、重复限制、无命令注册API、无Legacy API、分组失败，并验证关键按钮仍可注册且默认零游戏写入。

这些是模拟宿主测试，不是用户NexusTools中的实测。尤其没有实际宿主错误日志，不能声称已确认根因或无敌游戏效果。
