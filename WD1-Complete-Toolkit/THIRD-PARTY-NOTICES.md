# 依赖与来源声明 · v0.3

原创 C#、Lua、控制器、界面、安全流程与测试采用 MIT。没有 Ubisoft、Valve、NexusTools 或公开表作者背书。

## 独立宿主
NexusTools / Troplo 只作为 Lua 插件宿主，用户自行安装；本包不捆绑 ASI、代理 DLL、安装器或完整自带 Trainer。Lua 函数/数据参考公开 Trainer 提交 a20b61be0e2e00258ccb10ccfeb1be78c9b60450：https://github.com/Troplo/NexusTools.Trainer 。原始事实键保持来源，本项目未换皮上游 Trainer。

## 原生候选证据
公开 WD-Trainer v1.0 / Vortex Prime（2026，https://fearlessrevolution.com/viewtopic.php?t=30038 ）提供 v1.06.329 候选的指令和字段事实。
Daijobu 汇总表及 gir489 / NanoByte / redleouf / HiSaZuL（https://fearlessrevolution.com/viewtopic.php?t=2310 ）提供旧版饮酒/库存等事实。未运行或捆绑 CT，不重打包商业工具，只引用有限互操作事实；控制/捕获/生成/检查代码原创。

旧版平台成就模块及第三方桥接源码/二进制已从新版本移除。不包含该模块的依赖，也不触碰平台账号状态。Steam仅用于本游戏安装定位、版本身份和用户主动启动。

没有游戏 EXE/引擎、原生客户端 DLL、存档、账号文件或内存转储。构建工具 Mono/Python/Lua/Xvfb 不打包。Windows运行依赖 .NET Framework 4.8 系列。所有自编译二进制未签名。
