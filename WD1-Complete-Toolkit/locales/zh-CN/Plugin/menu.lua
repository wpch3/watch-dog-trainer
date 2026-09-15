-- Original host adapter. Only documented SH_* interfaces are used.
return function(c, catalog, mode)
    local required={"Script","SH_Menu_RegisterMenu","SH_Menu_RegisterCategory","SH_Commands_Register", "SH_Commands_RegisterBool","SH_Commands_RegisterInt","SH_Commands_RegisterCallback", "SH_Commands_GetStateBool","SH_Commands_GetStateInt","SH_Commands_SetStateBool"}
    for _,name in ipairs(required) do
        if type(_G[name])~="function" then c:log("HOST_API_MISSING",name); c:shutdown("INCOMPATIBLE_HOST"); return false end
    end
    local prefix="wd1kit_"..mode.."_"
    local menu=SH_Menu_RegisterMenu(mode=="campaign" and "WD1 KIT - 本体 [TEST]" or "WD1 KIT - Bad Blood [TEST]")
    local toggleIds={}
    local function resetWidgets()
        for _,id in ipairs(toggleIds) do pcall(SH_Commands_SetStateBool,id,false) end
    end
    local function command(id,label,fn)
        id=prefix..id
        local guarded=function() if c.alive then fn() end end
        SH_Commands_Register(id,label,"WD1KIT 0.3 alpha：游戏行为尚未在你的构建实测。",menu,guarded)
        SH_Commands_RegisterCallback(id,guarded)
        return id
    end
    local function number(id,label,value,min,max)
        id=prefix..id
        SH_Commands_RegisterInt(id,label,"只设置本工具输入值；点击对应按钮才执行。",menu,value,min,max)
        return id
    end
    local function bool(id,label)
        local cid=prefix..id
        local function changed()
            if not c.alive then return end
            local desired=SH_Commands_GetStateBool(cid)
            if desired and not c:toggle(id,true) then pcall(SH_Commands_SetStateBool,cid,false)
            elseif not desired then c:toggle(id,false) end
        end
        SH_Commands_RegisterBool(cid,label,"须先在自由探索、断开联机后手动 ARM；重载/暂停会关闭。",menu,false,changed)
        SH_Commands_RegisterCallback(cid,changed)
        toggleIds[#toggleIds+1]=cid; pcall(SH_Commands_SetStateBool,cid,false)
        return cid
    end
    local arm=command("arm","[ARM] 我已断开联机，且正在单机自由探索",function() resetWidgets(); c:arm() end)
    local stop=command("stop","[STOP] 关闭持续效果并取消待执行请求",function() c:stop("USER_STOP"); resetWidgets() end)
    local confirm=command("confirm","[CONFIRM] 确认上一笔物品 / 现金请求",function() c:confirm() end)
    local cancel=command("cancel","[CANCEL] 取消物品 / 现金队列",function() c:cancel() end)
    local probe=command("probe","[REPORT] 导出只读接口能力到宿主日志",function() c:probe() end)
    local god=bool("god","God mode / 持续无敌")
    local ammo=bool("ammo","Ammo / 无限弹药（持续补给）")
    local ammoOnce=command("ammo_once","[ADD AMMO] 只补给弹药一次",function() c:ammoOnce() end)
    local itemQuantity=number("item_quantity","增加材料/消耗品的数量（与无限开关独立）",1,1,100)
    local focus=bool("focus","Focus / 持续专注补充")
    local police=bool("police","Police / 暂停通缉系统")
    local heat=number("heat_value","通缉热度输入 0–100",0,0,100)
    local heatApply=command("heat_apply","应用通缉热度输入",function() c:heat(SH_Commands_GetStateInt(heat)) end)
    local money=number("cash_value","现金增加量（默认 1000，最大 100 万）",1000,1,1000000)
    local moneyPrepare=command("cash_prepare","准备增加现金 → 再点 CONFIRM",function() c:prepareCash(SH_Commands_GetStateInt(money)) end)
    local points=number("point_value","技能点奖励数量 1–100（先测 +1）",1,1,100)
    local pointPrepare=command("point_prepare","准备技能点奖励 → 再点 CONFIRM",function() c:prepareItems({"item_2023158576"},SH_Commands_GetStateInt(points)) end)
    local hour=number("hour","小时",12,0,23)
    local minute=number("minute","分钟",0,0,59)
    local timeApply=command("time_apply","应用时刻（重启游戏解除脚本时钟）",function() c:setTime(SH_Commands_GetStateInt(hour),SH_Commands_GetStateInt(minute)) end)
    local function category(title,fn)
        local cat=SH_Menu_RegisterCategory(title,menu)
        cat:Layout(function(root)
            root:Text("0.2 ALPHA — 调用完成 ≠ 已解锁 / 已保存",{size=18,bold=true})
            root:CommandWidget(stop)
            fn(root)
        end)
    end
    category("01 / 安全与报告",function(r)
        r:Text("只在单机自由探索测试；不要在在线合约、入侵、比赛、合作或任务演出中启用。",{size=16})
        r:Text("没有真实的联机状态回读。本插件依靠你的单机确认 + 宿主 OnPause 通知；该通知在本机尚待验证。",{size=15})
        r:Text("物品、现金、技能奖励需要桌面工具生成的两小时备份回执。回执不是游戏存档识别器。",{size=15})
        r:CommandWidget(arm); r:CommandWidget(probe)
        r:Text("主线、调查、收集计数、线上合约次数与 Ubisoft 服务端记录：本版没有改写。游戏内进度计数接口仍待适配。",{size=15})
    end)
    category("02 / 玩家与通缉",function(r)
        r:CommandWidget(arm); r:CommandWidget(god); r:CommandWidget(ammo); r:CommandWidget(ammoOnce); r:CommandWidget(focus); r:CommandWidget(police)
        r:Divider(); r:CommandWidget(heat); r:CommandWidget(heatApply)
    end)
    category("03 / 点数与现金",function(r)
        r:CommandWidget(arm); r:Text("先备份，再一次只测一项。技能点通过真实 Skillpoint 奖励键，不是虚构 SetSkillPoints。",{size=15})
        r:CommandWidget(points); r:CommandWidget(pointPrepare)
        r:CommandWidget(money); r:CommandWidget(moneyPrepare)
        for _,item in ipairs(catalog) do if item.group=="xp" then
            local id=item.id; r:Button(item.label.." → 准备",function() c:prepareItems({id},1) end)
        end end
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end)
    if mode=="campaign" then category("04 / 线上门槛的本地奖励",function(r)
        r:Text("这些是本地物品请求，不增加入侵 / 尾随 / 比赛次数，也不增加游戏内对应活动计数。",{size=15})
        r:Text("先测试单件；拿到后正常存档并重启，才可确认持久性。",{size=15})
        for _,id0 in ipairs({"item_2207476061","item_4099987261","item_770883049","item_309961700","item_678076169"}) do
            local id=id0; local item=c.entries[id]
            r:Button(item.label.." → 准备",function() c:prepareItems({id},1) end)
        end
        r:Button("准备四件线上奖励武器（不包含车辆）",function() c:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
        r:Text("解密战的 Chicago Way / Firepower / Heavy Duty 配装仍未接入；不能用单机枪械冒充。",{size=15})
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end) end
    local groups={{"weapons","常规与特殊武器"},{"dlc_weapons","已拥有的 ULC 武器"},{"bb_weapons","Bad Blood 武器"}, {"supplies","消耗品与材料"},{"clothes","艾登商店服装"},{"dlc_clothes","已拥有的 ULC 服装"},{"trip_clothes","数字之旅奖励服装"},{"bb_clothes","T-Bone 服装"},{"cars","本体叫车奖励候选"},{"songs","22 首曲目奖励候选"}}
    category("05 / 白名单物品目录",function(r)
        r:Text("全武器 / 全服装 / 全物品为当前模式白名单批次；实际拥有与持久解锁仍须核对。",{size=15})
        r:Text("不含任务令牌、AccessIds、NPC/联机武器或 MOD 项。增加资源不会打开无限开关。",{size=15})
        r:Button("[ALL WEAPONS] 准备全部武器候选",function() c:prepareAll("weapons") end)
        r:Button("[ALL CLOTHES] 准备全部服装候选",function() c:prepareAll("clothes") end)
        r:Button("[ALL ITEMS] 准备全部可用物品候选",function() c:prepareAll("items") end)
        r:CommandWidget(confirm); r:CommandWidget(cancel); r:CommandWidget(itemQuantity)
        for _,g in ipairs(groups) do
            local list={}; for _,item in ipairs(catalog) do if item.group==g[1] and (item.mode=="both" or item.mode==mode) then list[#list+1]=item end end
            if #list>0 then
                local title=g[2].." ("..#list..")"
                r:CollapsingHeader(title,false,function(h)
                    h:Button("准备本组（每项 1 件）",function() local ids={}; for _,v in ipairs(list) do ids[#ids+1]=v.id end; c:prepareItems(ids,1) end)
                    for _,item in ipairs(list) do local id=item.id; local isSupply=item.group=="supplies"; h:Button(item.label,function() c:prepareItems({id},isSupply and SH_Commands_GetStateInt(itemQuantity) or 1) end) end
                end)
            end
        end
        r:Text("歌曲只有 22 个明确对应的键；Wake Up Sunshine 的映射未定，因此未伪装成 23/23。",{size=15})
    end)
    category("06 / 车辆与世界",function(r)
        r:CommandWidget(arm)
        r:Text("生成车辆仅供本次世界使用，最多 5 辆；不自动入座、不删除世界实体，不等于叫车解锁。",{size=15})
        for i,v in ipairs(c.vehicles) do local index=i; r:Button("Spawn "..v.label,function() c:spawn(index) end) end
        r:Divider(); r:CommandWidget(hour); r:CommandWidget(minute); r:CommandWidget(timeApply)
    end)
    local script=Script("wd1kit_"..mode)
    function script:OnUpdate() c:tick() end
    function script:OnPause() c:pause(); resetWidgets() end
    function script:OnResume() c:resume(); resetWidgets() end
    function script:OnPlayerEntityChange() c:entityChange(); resetWidgets() end
    function script:OnUnload() c:shutdown("SCRIPT_UNLOADED"); resetWidgets() end
    function menu:OnRemove() c:shutdown("MENU_REMOVED"); pcall(function() script:Remove() end) end
    c.script=script
    c:log("PLUGIN_LOADED","version=0.3.0-alpha mode="..mode.." game_runtime_verified=false")
    c:probe()
    return true
end
