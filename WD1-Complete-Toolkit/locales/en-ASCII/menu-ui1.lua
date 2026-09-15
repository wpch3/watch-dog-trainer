-- Original host adapter. Only documented SH_* interfaces are used.
return function(c, catalog, mode)
    local required={"Script","SH_Menu_RegisterMenu","SH_Menu_RegisterCategory","SH_Commands_Register", "SH_Commands_RegisterBool","SH_Commands_RegisterInt","SH_Commands_RegisterCallback", "SH_Commands_GetStateBool","SH_Commands_GetStateInt","SH_Commands_SetStateBool"}
    for _,name in ipairs(required) do
        if type(_G[name])~="function" then c:log("HOST_API_MISSING",name); c:shutdown("INCOMPATIBLE_HOST"); return false end
    end
    local prefix="wd1kit_"..mode.."_"
    local menu=SH_Menu_RegisterMenu(mode=="campaign" and "WD1 KIT - Main [TEST]" or "WD1 KIT - Bad Blood [TEST]")
    local toggleIds={}
    local function resetWidgets()
        for _,id in ipairs(toggleIds) do pcall(SH_Commands_SetStateBool,id,false) end
    end
    local function command(id,label,fn)
        id=prefix..id
        local guarded=function() if c.alive then fn() end end
        SH_Commands_Register(id,label,"WD1KIT ALPHA: game behavior is not yet verified on your build.",menu,guarded)
        SH_Commands_RegisterCallback(id,guarded)
        return id
    end
    local function number(id,label,value,min,max)
        id=prefix..id
        SH_Commands_RegisterInt(id,label,"Input only. Use the separate action button to apply.",menu,value,min,max)
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
        SH_Commands_RegisterBool(cid,label,"ARM in offline free roam first. Reload or host pause disables effects.",menu,false,changed)
        SH_Commands_RegisterCallback(cid,changed)
        toggleIds[#toggleIds+1]=cid; pcall(SH_Commands_SetStateBool,cid,false)
        return cid
    end
    local arm=command("arm","[ARM] I am offline and in single-player free roam",function() resetWidgets(); c:arm() end)
    local stop=command("stop","[STOP] Disable effects and cancel pending requests",function() c:stop("USER_STOP"); resetWidgets() end)
    local confirm=command("confirm","[CONFIRM] Apply the prepared item or cash request",function() c:confirm() end)
    local cancel=command("cancel","[CANCEL] Cancel item or cash queue",function() c:cancel() end)
    local probe=command("probe","[REPORT] Write read-only capabilities to host log",function() c:probe() end)
    local god=bool("god","God Mode")
    local ammo=bool("ammo","Infinite Ammo - continuous refill")
    local ammoOnce=command("ammo_once","[ADD AMMO] Refill ammo once",function() c:ammoOnce() end)
    local itemQuantity=number("item_quantity","Item / material quantity to add - separate from infinite",1,1,100)
    local focus=bool("focus","Infinite Focus - continuous refill")
    local police=bool("police","Disable Wanted System")
    local heat=number("heat_value","Wanted Heat input 0-100",0,0,100)
    local heatApply=command("heat_apply","Apply Wanted Heat",function() c:heat(SH_Commands_GetStateInt(heat)) end)
    local money=number("cash_value","Cash to add - default 1000, maximum 1000000",1000,1,1000000)
    local moneyPrepare=command("cash_prepare","Prepare Cash - then CONFIRM",function() c:prepareCash(SH_Commands_GetStateInt(money)) end)
    local points=number("point_value","Normal Skill Point rewards 1-100 - test +1 first",1,1,100)
    local pointPrepare=command("point_prepare","Prepare Skill Point reward - then CONFIRM",function() c:prepareItems({"item_2023158576"},SH_Commands_GetStateInt(points)) end)
    local hour=number("hour","Hour",12,0,23)
    local minute=number("minute","Minute",0,0,59)
    local timeApply=command("time_apply","Apply Time - restart the game to release scripted clock",function() c:setTime(SH_Commands_GetStateInt(hour),SH_Commands_GetStateInt(minute)) end)
    local function category(title,fn)
        local cat=SH_Menu_RegisterCategory(title,menu)
        cat:Layout(function(root)
            root:Text("ASCII MENU - ALPHA: request sent is NOT verified unlock or persistence",{size=18,bold=true})
            root:CommandWidget(stop)
            fn(root)
        end)
    end
    category("01 / Safety and Report",function(r)
        r:Text("Offline free roam only. No online contracts, invasions, races, co-op or cutscenes.",{size=16})
        r:Text("No reliable session-state readback. Manual offline confirmation and host pause callback are required.",{size=15})
        r:Text("Persistent grants need the companion backup receipt. It lasts two hours and does not identify the active save.",{size=15})
        r:CommandWidget(arm); r:CommandWidget(probe)
        r:Text("Story, investigations, collectible counters and online records are not rewritten. Progress adapters remain pending.",{size=15})
    end)
    category("02 / Player and Police",function(r)
        r:CommandWidget(arm); r:CommandWidget(god); r:CommandWidget(ammo); r:CommandWidget(ammoOnce); r:CommandWidget(focus); r:CommandWidget(police)
        r:Divider(); r:CommandWidget(heat); r:CommandWidget(heatApply)
    end)
    category("03 / Skill Points and Cash",function(r)
        r:CommandWidget(arm); r:Text("Back up and test one item at a time. Skill points use the actual Skillpoint reward key, not an invented API.",{size=15})
        r:CommandWidget(points); r:CommandWidget(pointPrepare)
        r:CommandWidget(money); r:CommandWidget(moneyPrepare)
        for _,item in ipairs(catalog) do if item.group=="xp" then
            local id=item.id; r:Button(item.label.." - prepare",function() c:prepareItems({id},1) end)
        end end
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end)
    if mode=="campaign" then category("04 / Local Rewards Behind Online Requirements",function(r)
        r:Text("These are local item requests. They do not complete online hacking, tailing, races or activity counters.",{size=15})
        r:Text("Test one item first. Save normally and restart to verify persistence.",{size=15})
        for _,id0 in ipairs({"item_2207476061","item_4099987261","item_770883049","item_309961700","item_678076169"}) do
            local id=id0; local item=c.entries[id]
            r:Button(item.label.." - prepare",function() c:prepareItems({id},1) end)
        end
        r:Button("Prepare the four online-reward weapons - no vehicle",function() c:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
        r:Text("Decryption loadouts are not implemented. Single-player weapons do not replace those records.",{size=15})
        r:CommandWidget(confirm); r:CommandWidget(cancel)
    end) end
    local groups={{"weapons","Standard and Special Weapons"},{"dlc_weapons","Owned ULC Weapon Candidates"},{"bb_weapons","Bad Blood Weapon Candidates"}, {"supplies","Consumables and Materials"},{"clothes","Aiden Shop Outfits"},{"dlc_clothes","Owned ULC Outfit Candidates"},{"trip_clothes","Digital Trip Reward Outfits"},{"bb_clothes","T-Bone Outfits"},{"cars","Main Campaign Car On Demand Reward Candidates"},{"songs","22 Song Reward Candidates"}}
    category("05 / Item Whitelist",function(r)
        r:Text("ALL batches mean the current-mode whitelist. Actual ownership and persistent unlocks need verification.",{size=15})
        r:Text("No mission tokens, AccessIds, NPC/MP weapons or mod items. Adding resources does not enable infinite effects.",{size=15})
        r:Button("[ALL WEAPONS] Prepare all weapon candidates",function() c:prepareAll("weapons") end)
        r:Button("[ALL CLOTHES] Prepare all outfit candidates",function() c:prepareAll("clothes") end)
        r:Button("[ALL ITEMS] Prepare all current-mode item candidates",function() c:prepareAll("items") end)
        r:CommandWidget(confirm); r:CommandWidget(cancel); r:CommandWidget(itemQuantity)
        for _,g in ipairs(groups) do
            local list={}; for _,item in ipairs(catalog) do if item.group==g[1] and (item.mode=="both" or item.mode==mode) then list[#list+1]=item end end
            if #list>0 then
                local title=g[2].." ("..#list..")"
                r:CollapsingHeader(title,false,function(h)
                    h:Button("Prepare this group - one of each",function() local ids={}; for _,v in ipairs(list) do ids[#ids+1]=v.id end; c:prepareItems(ids,1) end)
                    for _,item in ipairs(list) do local id=item.id; local isSupply=item.group=="supplies"; h:Button(item.label,function() c:prepareItems({id},isSupply and SH_Commands_GetStateInt(itemQuantity) or 1) end) end
                end)
            end
        end
        r:Text("Only 22 song keys are mapped. Wake Up Sunshine remains unresolved; this is not a claim of 23/23.",{size=15})
    end)
    category("06 / Vehicles and World",function(r)
        r:CommandWidget(arm)
        r:Text("Spawn at most five vehicles per session. No auto-seat or entity deletion. Spawning is not a delivery unlock.",{size=15})
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
