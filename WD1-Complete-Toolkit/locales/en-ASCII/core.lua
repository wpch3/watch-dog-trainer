-- WD1 Complete Toolkit 0.4.0-alpha. Original MIT-licensed control logic.
-- Game calls use signatures evidenced in NexusTools.Trainer @ a20b61b.
-- Successful calls are REQUESTS, never evidence of an unlock or save persistence.
return function(env, catalog, receipt, mode)
    local c = { alive=true, armed=false, paused=false, mode=mode, flags={},
        queue={}, pending=nil, frames=0, spawned=0, appliedGod=nil, appliedPolice=false,
        submitted=0, batchTotal=0, batchFail={}, lastCode="LOCKED", lastMessage="(none)", lastLog="(none)", receipt=receipt or {}, entries={} }
    for _, item in ipairs(catalog) do c.entries[item.id] = item end
    -- v0.4.17: embedded unlock lists. Live evidence: the toolkit boots TWO modules
    -- (campaign + Bad Blood); the Bad Blood module receives a catalog with NO cars
    -- rows (INVALID_ALL_GROUP cars) and both modules can get unloaded by the host.
    -- Embedded ids + soft-revive make every button work from any module, any state.
    local EMBED_CARS={"730021862",
"3557513446",
"1248841029",
"1552158576",
"2532287513",
"2735499376",
"481845842",
"1783601268",
"3546717439",
"3167546579",
"1691143800",
"3932242273",
"633716073",
"2307007173",
"4072014718",
"2340694032",
"416758670",
"4118631699",
"3406370800",
"1738746352",
"716422723",
"2645593131",
"1178972921",
"1949862906",
"1034230765",
"83356222",
"1828875930",
"2344867287",
"3879782244",
"1659528633",
"268435244",
"3870792963",
"1604598506",
"384753930",
"3870519146",
"3790115983",
"2863852732",
"581466480",
"1946539202",
"754876024",
"50521172",
"4019596953",
"1990164259",
"4257587138",
"1807700676",
"1030290899",
"678076169",
"3825529972",
"2331463550",
"2757864553",
"4189416026",
"3754247527",
"1444405640",
"346438391",
"1181940009",
"3419135045",
"2584458734",
"217841595",
"973421002",
"757138070",
"143339962",
"3088679076",
"1512452608",
"1437551078",
"1912201071",
"3474894898",
"645731591",
"2028062005",
"3314376394",
"3863106483",
"2328014676",
"1671498337",
"3274662842",
"1718896871"}
    local EMBED_WEAPONS4={"2207476061","4099987261","770883049","309961700"}
    local EMBED_TEST7={"678076169","2584458734","217841595","1783601268","3546717439","2757864553","4189416026"}
    local EMBED_CAR_IDS={}; local EMBED_OK={}
    for i,k in ipairs(EMBED_CARS) do EMBED_CAR_IDS[i]="item_"..k; EMBED_OK["item_"..k]=true end
    for _,k in ipairs(EMBED_WEAPONS4) do EMBED_OK["item_"..k]=true end
    for _,k in ipairs(EMBED_TEST7) do EMBED_OK["item_"..k]=true end
    local function embedEntry(id) return {id=id,name="Items."..tostring(id):sub(6),group="cars",mode="both",embedded=true} end
    function c:softRevive(why)
        if not self.alive then
            self.alive=true; self.paused=false; self.flags={}; self.queue={}; self.pending=nil
            self:log("SOFT_REVIVE",why or "button")
        end
        return self.alive
    end
    local function has(name) return type(env[name]) == "function" end
    -- v0.4.14: disk log (user request). Results survive without on-screen notifications.
    local fileLog=false
    local function fileStamp()
        local ok,t=pcall(function() return env.os and env.os.time and env.os.time() or 0 end)
        return ok and t or 0
    end
    local function initFileLog()
        local ok,ioenv=pcall(function() return env.io end)
        if not ok or type(ioenv)~="table" or type(ioenv.open)~="function" then return end
        local paths={}
        local ok3,up=pcall(function() return env.os.getenv and env.os.getenv("USERPROFILE") or nil end)
        if ok3 and type(up)=="string" and #up>0 then paths[#paths+1]=up.."\\Desktop\\WD1KIT_log.txt" end
        paths[#paths+1]="WD1KIT_log.txt"
        local ok2,tmp=pcall(function() return env.os.getenv and env.os.getenv("TEMP") or nil end)
        if ok2 and type(tmp)=="string" and #tmp>0 then paths[#paths+1]=tmp.."\\WD1KIT_log.txt" end
        for _,p in ipairs(paths) do
            local opened=false
            pcall(function() local f=ioenv.open(p,"a") if f then f:write(string.format("==== WD1KIT 0.4.21 session mode=%s t=%d ====",tostring(mode),fileStamp())) f:close() opened=true end end)
            if opened then fileLog=p return end
        end
    end
    initFileLog()
    c.bootNote="(prev batch: none in log)"
    pcall(function()
        local f=env.io.open(fileLog,"r")
        if f then
            local all=f:read("*a") or ""; f:close()
            local acc,ref=all:match("BATCH_RESULT accepted=(%d+) refused=(%d+)")
            if acc then c.bootNote="prev batch: accepted="..acc.." refused="..ref end
        end
    end)
    local function fileLine(s)
        if fileLog==false then return end
        pcall(function() local f=env.io.open(fileLog,"a") if f then f:write(fileStamp().." "..s.."\n") f:close() end end)
    end
    function c:log(code, detail)
        self.lastCode=code
        local msg="[WD1KIT] "..code..(detail and (" "..detail) or "")
        self.lastLog=msg
        fileLine(msg)
        if has("SH_LOG") then pcall(env.SH_LOG, msg) end
    end
    function c:message(text)
        self.lastMessage=text
        fileLine("MSG "..tostring(text))
        if has("SH_Notifications_PushNotification") then
            pcall(env.SH_Notifications_PushNotification, text)
            pcall(env.SH_Notifications_PushNotification, "WD1KIT", text)
        end
    end
    function c:invoke(name, ...)
        if not has(name) then self:log("API_MISSING", name); return false end
        local ok, result=pcall(env[name], ...)
        if not ok then self:log("CALL_ERROR", name); return false end
        return true, result
    end
    function c:player()
        if not has("GetLocalPlayerEntityId") or not has("GetInvalidEntityId") then return nil end
        local ok,p=pcall(env.GetLocalPlayerEntityId)
        local ok2,invalid=pcall(env.GetInvalidEntityId)
        if not ok or not ok2 or p==nil or p==invalid or p==0 or p=="0" or p=="" then return nil end
        return p
    end
    function c:ticketValid()
        -- v0.4.15 ROOT FIX: structural checks only. The old 2-hour wall-clock window
        -- (minted with the backup/install receipt) silently refused EVERY persistent
        -- write once expired (BACKUP_TICKET_INVALID), so batches never started and
        -- submitted stayed 0. Offline tool: no session clock gate. If the old window
        -- would have refused, log it once so the disk log proves the diagnosis.
        if self.receipt.format~=1 or self.receipt.product~="WD1KIT" or self.receipt.mode~=self.mode or
           self.receipt.allow_persistent~=true or type(self.receipt.backup_id)~="string" or
           self.receipt.backup_id=="" then return false end
        if not self.windowNoteDone then
            self.windowNoteDone=true
            local ok,now=pcall(function() return env.os and env.os.time and env.os.time() or nil end)
            local t=ok and now or nil
            if type(t)=="number" and type(self.receipt.expires_unix)=="number" and t>self.receipt.expires_unix then
                self:log("TICKET_WINDOW_IGNORED","old 2h window would have refused this session; no longer enforced since 0.4.15")
            end
        end
        return true
    end
    -- Refusal hints: the notification must say what to DO, not only the code.
    local HINTS={
        UNLOADED="plugin stopped - reload it",
        PAUSED="game paused - close menus and tick [ARM] again",
        NOT_ARMED="tick the [ARM] checkbox first",
        NO_PLAYER="spawn into the game world first",
        ENTITY_CHANGED="player changed - tick [ARM] again",
        BACKUP_TICKET_INVALID="offline write gate refused this command: tick [ARM] again and stay in the same game mode (Main vs Bad Blood)"
    }
    function c:can(persistent, quiet)
        local code
        if not self.alive then code="UNLOADED"
        elseif self.paused then code="PAUSED"
        elseif not self.armed then code="NOT_ARMED"
        elseif not self:player() then code="NO_PLAYER"
        elseif self:player()~=self.activePlayer then code="ENTITY_CHANGED"
        elseif persistent and not self:ticketValid() then code="BACKUP_TICKET_INVALID" end
        if code then if not quiet then self:log(code); self:message("WD1KIT: "..code..(HINTS[code] and (" - "..HINTS[code]) or "")) end; return false end
        return true
    end
    function c:undo()
        local p=self:player()
        if self.appliedGod and p==self.appliedGod then self:invoke("RemoveInvincibility",p) end
        if self.appliedPolice then self:invoke("FelonySystemEnable",1) end
        self.appliedGod=nil; self.appliedPolice=false
    end
    function c:stop(reason)
        self.armed=false; self.flags={}; self.pending=nil
        if #self.queue>0 then self:log("BATCH_CANCELLED","remaining="..#self.queue) end
        if (self.pending and #self.pending>0) or #self.queue>0 then self:message("STOP: a prepared batch was discarded ("..tostring(reason or "stop").."). Re-arm and press CONFIRM again.") end
        self.queue={}; self:undo(); self.activePlayer=nil; self:log(reason or "STOPPED")
    end
    function c:shutdown(reason) self:stop(reason or "UNLOADED"); self.alive=false end
    function c:arm()
        self:softRevive("arm")
        if self.paused or not self:player() then self:log("ARM_REFUSED"); self:message("ARM refused: stay in the game world (not main menu) and press ARM again."); return false end
        -- Explicit user confirmation is necessary. This is NOT network-session detection.
        -- v0.4.18: re-arming resets TOGGLES only; it must NEVER destroy a prepared or
        -- queued batch (live log: BATCH_CANCELLED remaining=74 right after BATCH_STARTED
        -- because another press re-armed). stop() stays for explicit STOP/CANCEL only.
        self:undo(); self.flags={}; self.appliedGod=nil; self.appliedPolice=false
        self.activePlayer=self:player(); self.armed=true; self:log("ARMED_MANUAL_SINGLEPLAYER", self.mode)
        self:message("Single-player test armed. All continuous effects remain OFF.")
        return true
    end
    function c:pause() self.paused=true; self:stop("HOST_PAUSED") end
    function c:resume() self.paused=false; self:stop("RESUME_REQUIRES_REARM") end
    function c:entityChange() self:stop("ENTITY_CHANGED_REQUIRES_REARM") end
    function c:toggle(name, value)
        local apis={god={"ActivateInvincibility","RemoveInvincibility"},ammo={"ModifyBulletsInClip"},focus={"RefillAdrenaline"},police={"FelonySystemEnable"}}
        if not apis[name] then return false end
        if value then
            if not self:can(name=="ammo") then return false end
            for _,api in ipairs(apis[name]) do if not has(api) then self:log("API_MISSING",api); return false end end
        end
        self.flags[name]=value==true
        if name=="god" and not value and self.appliedGod then
            local p=self:player(); if p==self.appliedGod then self:invoke("RemoveInvincibility",p) end; self.appliedGod=nil
        elseif name=="police" and not value and self.appliedPolice then
            self:invoke("FelonySystemEnable",1); self.appliedPolice=false
        end
        self:log("TOGGLE_"..name,value and "ON_REQUESTED" or "OFF")
        return true
    end
    local function integer(n,lo,hi) return type(n)=="number" and n==math.floor(n) and n>=lo and n<=hi end
    function c:prepareItems(ids, quantity)
        self:softRevive("prepare")
        if not self:can(true) then return false end
        if #self.queue>0 or self.pending then self:log("BUSY_CANCEL_FIRST"); self:message("STILL BUSY: a previous request is queued. Press CONFIRM or CANCEL first."); return false end
        -- v0.4.0: the full progression-reward path needs bounded but larger batches.
        if type(ids)~="table" or #ids==0 or #ids>4096 or not integer(quantity,1,100) or #ids*quantity>8192 then self:log("INVALID_BATCH_SIZE"); return false end
        local jobs={}; local seen={}
        for _,id in ipairs(ids) do
            local item=self.entries[id]
            if not item and EMBED_OK[id] then item=embedEntry(id) end
            if not item or seen[id] or (item.mode~="both" and item.mode~=self.mode) then self:log("ITEM_NOT_ALLOWED",id); self:message("PREPARE REFUSED: item not available in this game mode ("..id..")"); return false end
            seen[id]=true
            jobs[#jobs+1]={kind="item",id=id,name=item.name,quantity=quantity}
        end
        if not has("AddItem") then self:log("API_MISSING","AddItem"); self:message("PREPARE REFUSED: AddItem function missing in this host."); return false end
        self.pending=jobs; self:log(string.format("PREPARED_ITEMS entries=%d quantity=%d",#jobs,quantity))
        self:message(string.format("Prepared: %d entries, each %d. NOTHING granted yet. NEXT press [STEP 2] CONFIRM.",#jobs,quantity))
        return true
    end
    function c:prepareAll(kind)
        -- v0.4.0 unlock groups. "items" stays growth-free: no skill/XP/notoriety entries.
        local groups={
            weapons={weapons=true,custom_weapons=true,dlc_weapons=true,bb_weapons=true},
            clothes={clothes=true,clothes_mod=true,dlc_clothes=true,trip_clothes=true,bb_clothes=true},
            cars={cars=true}, songs={songs=true},
            progression={xp=true,skill=true,mission_xp_main=true,mission_xp_side=true,mission_xp_family=true,
                notoriety=true,ctos_rewards=true,activity_rewards=true,progress_misc=true,cash_items=true,special_perks=true},
            gear={supplies=true,upgrades=true,tech=true,projectiles=true,explosives=true,ammo=true,meds=true,food=true,misc_items=true},
            items={weapons=true,custom_weapons=true,dlc_weapons=true,bb_weapons=true,clothes=true,clothes_mod=true,
                dlc_clothes=true,trip_clothes=true,bb_clothes=true,cars=true,songs=true,supplies=true,upgrades=true,
                tech=true,projectiles=true,explosives=true,ammo=true,meds=true,food=true,misc_items=true,
                special_perks=true,collectibles=true,audio_drops=true,video_logs=true,bb_items=true,
                progress_misc=true,activity_rewards=true,ctos_rewards=true,cash_items=true,xp=true,notoriety=true}}
        if not groups[kind] then self:log("INVALID_ALL_GROUP"); return false end
        local ids={}; for _,item in ipairs(catalog) do if groups[kind][item.group] and (item.mode=="both" or item.mode==self.mode) then ids[#ids+1]=item.id end end
        return self:prepareItems(ids,1)
    end
    -- v0.4.19 NATIVE CRAWL. Verdict from live disk log: AddItem item grants were
    -- accepted 148/148 with 0 refusals and did NOT unlock any Car On Demand vehicle.
    -- Item path is dead for cars. The host exposes UnlockAndBuyCarOnDemand and
    -- SetItem as native functions; the game itself calls them for Car On Demand
    -- ownership. Crawl every plausible calling convention on ONE test car, log
    -- every result to the disk log, and let the restart check deliver the verdict.
    -- v0.4.20 CRAWL 2. Round-1 intel (live log): UnlockAndBuyCarOnDemand EXISTS and
    -- runs (returns nil = void), GetItemId("Items.X") = 4294967296 = 2^32 "not found"
    -- sentinel (upstream Items.NNNN names do not resolve in this host), and the only
    -- native signature we ever verified is GiveCash(0, n) - leading player index 0.
    -- So: probe id formats, probe (0, .) signatures, then sweep Car On Demand list
    -- index 0..127. No silent cash: one logged 1M budget for possible "Buy" costs.
    -- v0.4.21 FULL API DUMP. The capability probe listed only 57 names, yet god mode
    -- uses ActivateInvincibility which is NOT in that list -> the probe is a filtered
    -- view, not the real surface. Blind-guessing names is over: dump EVERY function
    -- reachable from the plugin environment (direct table, _G, metatable __index)
    -- into the disk log, and flag car/vehicle/unlock-related names explicitly.
    function c:dumpApiEnv()
        self:softRevive("dump")
        local seen={}; local count=0; local hits={}; local guard=0
        local function walk(tbl,tag,depth)
            if depth>2 or type(tbl)~="table" or guard>4000 then return end
            for k,v in pairs(tbl) do
                guard=guard+1
                if guard>4000 then self:log("APIENV_TRUNCATED",tag); return end
                local key=tostring(k)
                local t=type(v)
                if t=="function" then
                    local full=tag.."."..key
                    if not seen[full] then
                        seen[full]=true; count=count+1
                        self:log("APIENV",full)
                        local low=key:lower()
                        if low:find("car") or low:find("veh") or low:find("garage") or low:find("unlock") or low:find("own") or low:find("spawn") then
                            hits[#hits+1]=full
                        end
                    end
                elseif t=="table" then
                    local tk=tag.."."..key
                    if not seen[tk..":t"] then seen[tk..":t"]=true; walk(v,tk,depth+1) end
                end
            end
        end
        self:log("APIENV_BEGIN","dumping every reachable function")
        walk(env,"env",0)
        if env._G and env._G~=env then walk(env._G,"_G",0) end
        pcall(function()
            local mt=getmetatable(env)
            if mt and type(mt.__index)=="table" then walk(mt.__index,"env.mt",0) end
        end)
        self:log("APIENV_END","functions="..count.." car_related="..#hits)
        for _,h in ipairs(hits) do self:log("APIENV_CARHIT",h) end
        self:message("API dump done: "..count.." functions, "..#hits.." car-related. Send WD1KIT_log.txt.")
        return true
    end
    function c:crawlCarUnlock2()
        self:softRevive("crawl2")
        if not self.armed then if not self:arm() then return false end end
        local p=self:player() or 0
        local key=1783601268
        local function try(label,fn)
            local ok,res=pcall(fn)
            self:log("CRAWLB_"..label,tostring(res))
            return ok
        end
        try("BUDGET_1M",function() return env.GiveCash(0,1000000) end)
        local idfmt={}
        try("ID_PLAIN",function() idfmt.plain=(env.GetItemId and env.GetItemId(tostring(key)) or "missing") return idfmt.plain end)
        try("ID_ITEMSTR",function() idfmt.itemstr=(env.GetItemId and env.GetItemId("Items."..key) or "missing") return idfmt.itemstr end)
        try("ID_PREFIXED",function() idfmt.pref=(env.GetItemId and env.GetItemId("item_"..key) or "missing") return idfmt.pref end)
        try("ID_NUMERIC",function() idfmt.num=(env.GetItemId and env.GetItemId(key) or "missing") return idfmt.num end)
        local canonical
        for _,v in pairs(idfmt) do if type(v)=="number" and v~=4294967296 and v>0 and v<4294967296 then canonical=v break end end
        self:log("CRAWLB_CANONICAL",tostring(canonical))
        try("UB_0_KEY",function() return env.UnlockAndBuyCarOnDemand(0,key) end)
        try("UB_0_ITEMSTR",function() return env.UnlockAndBuyCarOnDemand(0,"Items."..key) end)
        try("UB_0_KEY_TRUE",function() return env.UnlockAndBuyCarOnDemand(0,key,true) end)
        if canonical then try("UB_0_CANON",function() return env.UnlockAndBuyCarOnDemand(0,canonical) end) end
        try("UB_P_KEY",function() return env.UnlockAndBuyCarOnDemand(p,key) end)
        try("SETITEM_0_ITEMSTR",function() return env.SetItem(0,"Items."..key,1) end)
        local nonnil=0
        if env.UnlockAndBuyCarOnDemand then
            for i=0,127 do
                local ok,res=pcall(function() return env.UnlockAndBuyCarOnDemand(0,i) end)
                if ok and res~=nil then nonnil=nonnil+1; self:log("CRAWLB_IDX",i.." -> "..tostring(res)) end
            end
        end
        self:log("CRAWLB_SWEEP_DONE","total=128 non_nil="..nonnil)
        self:log("CRAWL_DONE","save, FULL quit to desktop, restart, count NEW cars in Car On Demand")
        self:message("CRAWL2 done. Save, FULL quit to desktop, restart, then count NEW cars in Car On Demand.")
        return true
    end
    function c:prepareGroup(group, quantity)
        self:softRevive("prepareGroup")
        if not integer(quantity,1,100) then quantity=1 end
        if group=="cars" then return self:prepareItems(EMBED_CAR_IDS,quantity) end
        local ids={}; for _,item in ipairs(catalog) do if item.group==group and (item.mode=="both" or item.mode==self.mode) then ids[#ids+1]=item.id end end
        if #ids==0 then self:log("INVALID_ALL_GROUP",group); self:message("PREPARE REFUSED: group "..tostring(group).." is empty in this module ("..tostring(self.mode)..")"); return false end
        return self:prepareItems(ids,quantity)
    end
    function c:prepareCash(amount)
        if not self:can(true) then return false end
        if #self.queue>0 or self.pending or not integer(amount,1,1000000) then self:log("CASH_REFUSED"); return false end
        if not has("GiveCash") then self:log("API_MISSING","GiveCash"); return false end
        self.pending={{kind="cash",quantity=amount}}
        self:log("PREPARED_CASH","amount="..amount); self:message(string.format("Prepared: cash +%d. Press [CONFIRM] to apply.",amount))
        return true
    end
    function c:confirm()
        if not self:can(true) then return false end
        if not self.pending then
            if #self.queue>0 then
                -- v0.4.18: live log ended with pending=nil queue=74 and nothing draining.
                -- A queued batch must be deliverable by the next CONFIRM press.
                return self:drainAll()
            end
            self:log("CONFIRM_NOTHING_PENDING","queue="..#self.queue)
            self:message("CONFIRM: nothing was prepared. Press CONFIRM again - it now auto-prepares the cars.")
            return false
        end
        self.queue=self.pending; self.pending=nil; self.batchTotal=#self.queue; self.batchFail={}
        self:log("BATCH_STARTED","entries="..#self.queue)
        -- v0.4.18: deliver NOW, inside this click. No frames, no renders, no watcher:
        -- this host may never tick or re-render, and re-presses killed queued batches.
        -- One click = fully delivered.
        return self:drainAll()
    end
    function c:drainAll()
        self:softRevive("drain")
        local guard=0
        while #self.queue>0 and guard<4096 do
            guard=guard+1
            local job=table.remove(self.queue,1); local ok,result
            if job.kind=="cash" then ok,result=self:invoke("GiveCash",0,job.quantity)
            else ok,result=self:invoke("AddItem",job.name,job.quantity) end
            if not ok then
                self.batchFail[#self.batchFail+1]=(job.id or "cash").."(call_error)"
                self:log("REQUEST_CALL_ERROR",job.id or "cash")
            elseif result==false then
                self.batchFail[#self.batchFail+1]=(job.id or "cash").."(rejected)"
                self:log("REQUEST_REJECTED",job.id or "cash")
            else
                self.submitted=self.submitted+1
                self:log("REQUEST_SUBMITTED",(job.id or "cash").." quantity="..job.quantity.." readback=UNAVAILABLE")
            end
        end
        self:log("BATCH_SUBMITTED_NOT_VERIFIED","submitted="..self.submitted.." rejected="..#self.batchFail)
        self:log("BATCH_RESULT","accepted="..self.submitted.." refused="..#self.batchFail)
        local msg=string.format("BATCH RESULT: %d accepted, %d refused by game.",self.submitted,#self.batchFail)
        if #self.batchFail>0 and #self.batchFail<=8 then msg=msg.." Refused: "..table.concat(self.batchFail,", ") end
        msg=msg.." Save normally, then restart to verify."
        self:message(msg)
        return true
    end
    function c:cancel() self.pending=nil; self.queue={}; self:log("BATCH_CANCELLED_BY_USER") end
    function c:ammoOnce()
        if not self:can(true) then return false end
        local p=self:player()
        for slot=0,5 do if not self:invoke("ModifyBulletsInClip",p,slot,999,9999) then self:log("AMMO_ONCE_FAILED"); return false end end
        self:log("AMMO_ONCE_SUBMITTED"); return true
    end
    function c:heat(n)
        if not integer(n,0,100) or not self:can(false) then return false end
        local ok=self:invoke("FelonySetHeat",self:player(),n)
        if ok then self:log("HEAT_REQUESTED","value="..n) end; return ok
    end
    function c:setTime(hour,minute)
        if not integer(hour,0,23) or not integer(minute,0,59) or not self:can(false) then return false end
        local ok,mgr=self:invoke("CDynamicEnvironmentManager_GetInstance")
        if not ok or not mgr then return false end
        local success=pcall(function() mgr:SetScriptedTimeOfDay(hour,minute) end)
        self:log(success and "TIME_REQUESTED" or "TIME_CALL_ERROR"); return success
    end
    c.vehicles={
        {name="Vehicle_Speed.Speed.Speed_05LE",label="Livraga LE"},
        {name="Vehicle_Speed.Speed.Speed_06",label="Papavero"},
        {name="Vehicle_Speed.Speed.Speed_07_Reward",label="Boxberg LE"},
        {name="Vehicle_Bike.Bike.Bike_01",label="Sayonara"},
        {name="Vehicle_Offroad.Offroad.Offroad_01",label="Polar"},
        {name="Vehicle_Muscle.Muscle.Muscle_01",label="Vespid 5.2"}
    }
    function c:spawn(index)
        if not integer(index,1,#self.vehicles) or not self:can(false) or self.spawned>=5 then self:log("SPAWN_REFUSED"); return false end
        local p=self:player(); local xyz={}
        for axis=0,2 do
            local ok,v=self:invoke("GetEntityPosition",p,axis)
            if not ok or type(v)~="number" or v~=v or math.abs(v)>1000000 then return false end; xyz[axis+1]=v
        end
        local ok,id=self:invoke("SH_Entities_Spawn",{name=self.vehicles[index].name,position={x=xyz[1]+4,y=xyz[2],z=xyz[3]}})
        if not ok or id==nil or id==0 or id=="0" or type(id)=="boolean" or id==env.GetInvalidEntityId() then self:log("SPAWN_NO_ENTITY"); return false end
        self.spawned=self.spawned+1; self:log("SPAWN_REQUESTED",self.vehicles[index].name)
        self:message("Vehicle spawn requested. This is not a delivery unlock or an online race completion.")
        return true
    end
    -- v0.4.16: one queue job per call. The MENU RENDER calls service() every frame,
    -- so the batch advances while the user can literally watch the numbers - this
    -- host wipes plugin state on hot-reload, so nothing may depend on the watcher.
    function c:drainOne()
        if #self.queue==0 then return false end
        if not self:can(true,true) then return false end
        local job=table.remove(self.queue,1); local ok,result
        if job.kind=="cash" then ok,result=self:invoke("GiveCash",0,job.quantity)
        else ok,result=self:invoke("AddItem",job.name,job.quantity) end
        if not ok then
            self.batchFail[#self.batchFail+1]=(job.id or "cash").."(call_error)"
            self:log("REQUEST_CALL_ERROR",job.id or "cash")
        elseif result==false then
            self.batchFail[#self.batchFail+1]=(job.id or "cash").."(rejected)"
            self:log("REQUEST_REJECTED",job.id or "cash")
        else
            self.submitted=self.submitted+1
            self:log("REQUEST_SUBMITTED",(job.id or "cash").." quantity="..job.quantity.." readback=UNAVAILABLE")
        end
        if self.batchTotal>0 and #self.queue>0 and (self.submitted+#self.batchFail)%20==0 then
            self:message(string.format("Batch progress %d/%d...",self.batchTotal-#self.queue,self.batchTotal))
        end
        if #self.queue==0 then
            self:log("BATCH_SUBMITTED_NOT_VERIFIED","submitted="..self.submitted.." rejected="..#self.batchFail)
            self:log("BATCH_RESULT","accepted="..self.submitted.." refused="..#self.batchFail)
            local msg=string.format("BATCH RESULT: %d accepted, %d refused by game.",self.submitted,#self.batchFail)
            if #self.batchFail>0 and #self.batchFail<=8 then msg=msg.." Refused: "..table.concat(self.batchFail,", ") end
            msg=msg.." Save normally, then restart to verify."
            self:message(msg)
        end
        return true
    end
    function c:service(n)
        if not self.alive or not self.armed or self.paused then return end
        for _=1,tonumber(n) or 4 do
            if #self.queue==0 then return end
            if not self:drainOne() then return end
        end
    end
    function c:tick()
        if not self.alive or self.paused or not self.armed then return end
        if not self:player() then self:stop("PLAYER_LOST"); return end
        if self.flags.ammo and not self:ticketValid() then self:stop("AMMO_TICKET_INVALID"); return end
        local p=self:player(); if p~=self.activePlayer then self:stop("ENTITY_CHANGED_REQUIRES_REARM"); return end; self.frames=self.frames+1
        if self.flags.god then
            if not self:invoke("ActivateInvincibility",p) then self:stop("GOD_CALL_FAILED"); return end
            self.appliedGod=p
        end
        if self.flags.focus then
            if not self:invoke("RefillAdrenaline",p) then self:stop("FOCUS_CALL_FAILED"); return end
        end
        if self.flags.ammo then
            for slot=0,5 do if not self:invoke("ModifyBulletsInClip",p,slot,999,9999) then self:stop("AMMO_CALL_FAILED"); return end end
        end
        if self.flags.police and not self.appliedPolice then
            if not self:invoke("FelonySystemEnable",0) then self:stop("POLICE_CALL_FAILED"); return end
            self.appliedPolice=true
        end
        if #self.queue>0 and self.frames%4==0 then self:drainOne() end
    end
    function c:probe()
        self:log("PROBE","version=0.4.21-alpha mode="..self.mode.." persistent_ticket="..tostring(self:ticketValid()))
        local names={}
        for k,v in pairs(env) do
            if type(k)=="string" and type(v)=="function" and #k<100 and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
                local s=k:lower()
                if s:find("skill") or s:find("progress") or s:find("achiev") or s:find("invent") or s:find("item") or s:find("battery") or s:find("online") or s:find("session") or s:find("experience") or s:find("network") or s:find("notoriety") or s:find("unlock") then names[#names+1]=k end
            end
        end
        table.sort(names)
        for n=1,math.min(#names,300),15 do
            local part={}; for j=n,math.min(n+14,#names,300) do part[#part+1]=names[j] end
            self:log("CAP",table.concat(part,","))
        end
        self:log("PROBE_DONE","player_available="..tostring(self:player()~=nil).." native_function_names="..#names)
        self:message("Read-only capability names logged. No memory scan or account data is exported.")
    end
    return c
end
