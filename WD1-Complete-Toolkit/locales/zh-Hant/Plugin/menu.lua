-- Original host adapter. Only documented SH_* interfaces are used.
return function(c, catalog, mode)
    local required={"Script","SH_Menu_RegisterMenu","SH_Menu_RegisterCategory","SH_Commands_Register", "SH_Commands_RegisterBool","SH_Commands_RegisterInt","SH_Commands_RegisterCallback", "SH_Commands_GetStateBool","SH_Commands_GetStateInt","SH_Commands_SetStateBool"}
    for _,name in ipairs(required) do
        if type(_G[name])~="function" then c:log("HOST_API_MISSING",name); c:shutdown("INCOMPATIBLE_HOST"); return false end
    end
    local prefix="wd1kit_"..mode.."_"
    local menu=SH_Menu_RegisterMenu(mode=="campaign" and "WD1 KIT - 本體 [TEST]" or "WD1 KIT - Bad Blood [TEST]")
    local toggleIds={}
    local function resetWidgets()
        for _,id in ipairs(toggleIds) do pcall(SH_Commands_SetStateBool,id,false) end
    end
    local function command(id,label,fn)
        id=prefix..id
        local guarded=function() if c.alive then fn() end end
        SH_Commands_Register(id,label,"WD1KIT 0.3 alpha：遊戲行爲尚未在你的構建實測。",menu,guarded)
        SH_Commands_RegisterCallback(id,guarded)
        return id
    end
    local function number(id,label,value,min,max)
        id=prefix..id
        SH_Commands_RegisterInt(id,label,"只設置本工具輸入值；點擊對應按鈕才執行。",menu,value,min,max)
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
        SH_Commands_RegisterBool(cid,label,"須先在自由探索、斷開聯機後手動 ARM；重載/暫停會關閉。",menu,false,changed)
        SH_Commands_RegisterCallback(cid,changed)
        toggleIds[#toggleIds+1]=cid; pcall(SH_Commands_SetStateBool,cid,false)
        return cid
    end
    local arm=command("arm","[ARM] 我已斷開聯機，且正在單機自由探索",function() resetWidgets(); c:arm() end)
    local stop=command("stop","[STOP] 關閉持續效果並取消待執行請求",function() c:stop("USER_STOP"); resetWidgets() end)
    local confirm=command("confirm","[CONFIRM] 確認上一筆物品 / 現金請求",function() c:confirm() end)
    local cancel=command("cancel","[CANCEL] 取消物品 / 現金隊列",function() c:cancel() end)
    local probe=command("probe","[REPORT] 導出只讀接口能力到宿主日誌",function() c:probe() end)
    local god=bool("god","God mode / 持續無敵")
    local ammo=bool("ammo","Ammo / 無限彈藥（持續補給）")
    local ammoOnce=command("ammo_once","[ADD AMMO] 只補給彈藥一次",function() c:ammoOnce() end)
    local itemQuantity=number("item_quantity","增加材料/消耗品的數量（與無限開關獨立）",1,1,100)
    local focus=bool("focus","Focus / 持續專注補充")
    local police=bool("police","Police / 暫停通緝系統")
    local heat=number("heat_value","通緝熱度輸入 0–100",0,0,100)
    local heatApply=command("heat_apply","應用通緝熱度輸入",function() c:heat(SH_Commands_GetStateInt(heat)) end)
    local money=number("cash_value","現金增加量（默認 1000，最大 100 萬）",1000,1,1000000)
    local moneyPrepare=command("cash_prepare","準備增加現金 → 再點 CONFIRM",function() c:prepareCash(SH_Commands_GetStateInt(money)) end)
    local points=number("point_value","技能點獎勵數量 1–100（先測 +1）",1,1,100)
    local pointPrepare=command("point_prepare","準備技能點獎勵 → 再點 CONFIRM",function() c:prepareItems({"item_2023158576"},SH_Commands_GetStateInt(points)) end)
    local hour=number("hour","小時",12,0,23)
    local minute=number("minute","分鐘",0,0,59)
    local timeApply=command("time_apply","應用時刻（重啓遊戲解除腳本時鐘）",function() c:setTime(SH_Commands_GetStateInt(hour),SH_Commands_GetStateInt(minute)) end)
    local function category(title,fn)
        local cat=SH_Menu_RegisterCategory(title,menu)
        cat:Layout(function(root)
            root:Text("0.2 ALPHA — 調用完成 ≠ 已解鎖 / 已保存",{size=18,bold=true})
            root:CommandWidget(stop)
            fn(root)
        end)
    end
    category("01 / 安全與報告",function(r)
        r:Text("只在單機自由探索測試；不要在在線合約、入侵、比賽、合作或任務演出中啓用。",{size=16})
        r:Text("沒有真實的聯機狀態回讀。本插件依靠你的單機確認 + 宿主 OnPause 通知；該通知在本機尚待驗證。",{size=15})
        r:Text("物品、現金、技能獎勵需要桌面工具生成的兩小時備份回執。回執不是遊戲存檔識別器。",{size=15})
        r:CommandWidget(arm); r:CommandWidget(probe)
        r:Text("主線、調查、收集計數、線上合約次數與 Ubisoft 服務端記錄：本版沒有改寫。遊戲內進度計數接口仍待適配。",{size=15})
    end)
    category("02 / 玩家與通緝",function(r)
        r:CommandWidget(arm); r:CommandWidget(god); r:CommandWidget(ammo); r:CommandWidget(ammoOnce); r:CommandWidget(focus); r:CommandWidget(police)
        r:Divider(); r:CommandWidget(heat); r:CommandWidget(heatApply)
    end)
    category("03 / 點數與現金",function(r)
        r:CommandWidget(arm); r:Text("先備份，再一次只測一項。技能點通過真實 Skillpoint 獎勵鍵，不是虛構 SetSkillPoints。",{size=15})
        r:CommandWidget(points); r:CommandWidget(pointPrepare)
        r:CommandWidget(money); r:CommandWidget(moneyPrepare)
        for _,item in ipairs(catalog) do if item.group=="xp" then
            local id=item.id; r:Button(item.label.." → 準備",function() c:prepareItems({id},1) end)
        end end
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end)
    if mode=="campaign" then category("04 / 線上門檻的本地獎勵",function(r)
        r:Text("這些是本地物品請求，不增加入侵 / 尾隨 / 比賽次數，也不增加遊戲內對應活動計數。",{size=15})
        r:Text("先測試單件；拿到後正常存檔並重啓，才可確認持久性。",{size=15})
        for _,id0 in ipairs({"item_2207476061","item_4099987261","item_770883049","item_309961700","item_678076169"}) do
            local id=id0; local item=c.entries[id]
            r:Button(item.label.." → 準備",function() c:prepareItems({id},1) end)
        end
        r:Button("準備四件線上獎勵武器（不包含車輛）",function() c:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
        r:Text("解密戰的 Chicago Way / Firepower / Heavy Duty 配裝仍未接入；不能用單機槍械冒充。",{size=15})
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end) end
    local groups={{"weapons","常規與特殊武器"},{"dlc_weapons","已擁有的 ULC 武器"},{"bb_weapons","Bad Blood 武器"}, {"supplies","消耗品與材料"},{"clothes","艾登商店服裝"},{"dlc_clothes","已擁有的 ULC 服裝"},{"trip_clothes","數字之旅獎勵服裝"},{"bb_clothes","T-Bone 服裝"},{"cars","本體叫車獎勵候選"},{"songs","22 首曲目獎勵候選"}}
    category("05 / 白名單物品目錄",function(r)
        r:Text("全武器 / 全服裝 / 全物品爲當前模式白名單批次；實際擁有與持久解鎖仍須核對。",{size=15})
        r:Text("不含任務令牌、AccessIds、NPC/聯機武器或 MOD 項。增加資源不會打開無限開關。",{size=15})
        r:Button("[ALL WEAPONS] 準備全部武器候選",function() c:prepareAll("weapons") end)
        r:Button("[ALL CLOTHES] 準備全部服裝候選",function() c:prepareAll("clothes") end)
        r:Button("[ALL ITEMS] 準備全部可用物品候選",function() c:prepareAll("items") end)
        r:CommandWidget(confirm); r:CommandWidget(cancel); r:CommandWidget(itemQuantity)
        for _,g in ipairs(groups) do
            local list={}; for _,item in ipairs(catalog) do if item.group==g[1] and (item.mode=="both" or item.mode==mode) then list[#list+1]=item end end
            if #list>0 then
                local title=g[2].." ("..#list..")"
                r:CollapsingHeader(title,false,function(h)
                    h:Button("準備本組（每項 1 件）",function() local ids={}; for _,v in ipairs(list) do ids[#ids+1]=v.id end; c:prepareItems(ids,1) end)
                    for _,item in ipairs(list) do local id=item.id; local isSupply=item.group=="supplies"; h:Button(item.label,function() c:prepareItems({id},isSupply and SH_Commands_GetStateInt(itemQuantity) or 1) end) end
                end)
            end
        end
        r:Text("歌曲只有 22 個明確對應的鍵；Wake Up Sunshine 的映射未定，因此未僞裝成 23/23。",{size=15})
    end)
    category("06 / 車輛與世界",function(r)
        r:CommandWidget(arm)
        r:Text("生成車輛僅供本次世界使用，最多 5 輛；不自動入座、不刪除世界實體，不等於叫車解鎖。",{size=15})
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
