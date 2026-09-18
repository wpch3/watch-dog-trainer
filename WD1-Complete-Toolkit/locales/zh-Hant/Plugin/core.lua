-- WD1 Complete Toolkit 0.3.0-alpha. Original MIT-licensed control logic.
-- Game calls use signatures evidenced in NexusTools.Trainer @ a20b61b.
-- Successful calls are REQUESTS, never evidence of an unlock or save persistence.
return function(env, catalog, receipt, mode)
    local c = { alive=true, armed=false, paused=false, mode=mode, flags={},
        queue={}, pending=nil, frames=0, spawned=0, appliedGod=nil, appliedPolice=false,
        submitted=0, lastCode="LOCKED", receipt=receipt or {}, entries={} }
    for _, item in ipairs(catalog) do c.entries[item.id] = item end
    local function has(name) return type(env[name]) == "function" end
    function c:log(code, detail)
        self.lastCode=code
        local msg="[WD1KIT] "..code..(detail and (" "..detail) or "")
        if has("SH_LOG") then pcall(env.SH_LOG, msg) end
    end
    function c:message(text)
        if has("SH_Notifications_PushNotification") then pcall(env.SH_Notifications_PushNotification, text) end
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
        if self.receipt.format~=1 or self.receipt.product~="WD1KIT" or self.receipt.mode~=self.mode or
           self.receipt.allow_persistent~=true or type(self.receipt.expires_unix)~="number" or
           type(self.receipt.created_unix)~="number" or type(self.receipt.backup_id)~="string" or
           self.receipt.backup_id=="" or self.receipt.expires_unix<self.receipt.created_unix or self.receipt.expires_unix-self.receipt.created_unix>7200 then return false end
        if not env.os or type(env.os.time)~="function" then return false end
        local ok,now=pcall(env.os.time)
        return ok and type(now)=="number" and now>=self.receipt.created_unix-60 and now<=self.receipt.expires_unix
    end
    function c:can(persistent, quiet)
        local code
        if not self.alive then code="UNLOADED"
        elseif self.paused then code="PAUSED"
        elseif not self.armed then code="NOT_ARMED"
        elseif not self:player() then code="NO_PLAYER"
        elseif self:player()~=self.activePlayer then code="ENTITY_CHANGED"
        elseif persistent and not self:ticketValid() then code="BACKUP_TICKET_INVALID" end
        if code then if not quiet then self:log(code); self:message("WD1KIT: "..code) end; return false end
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
        self.queue={}; self:undo(); self.activePlayer=nil; self:log(reason or "STOPPED")
    end
    function c:shutdown(reason) self:stop(reason or "UNLOADED"); self.alive=false end
    function c:arm()
        if not self.alive or self.paused or not self:player() then self:log("ARM_REFUSED"); return false end
        -- Explicit user confirmation is necessary. This is NOT network-session detection.
        self:stop("ARM_RESET"); self.activePlayer=self:player(); self.armed=true; self:log("ARMED_MANUAL_SINGLEPLAYER", self.mode)
        self:message("已激活本次單機測試；所有持續開關仍爲關閉。")
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
        if not self:can(true) then return false end
        if #self.queue>0 or self.pending then self:log("BUSY_CANCEL_FIRST"); return false end
        if type(ids)~="table" or #ids==0 or #ids>256 or not integer(quantity,1,100) or #ids*quantity>512 then self:log("INVALID_BATCH_SIZE"); return false end
        local jobs={}; local seen={}
        for _,id in ipairs(ids) do
            local item=self.entries[id]
            if not item or seen[id] or (item.mode~="both" and item.mode~=self.mode) then self:log("ITEM_NOT_ALLOWED"); return false end
            seen[id]=true
            jobs[#jobs+1]={kind="item",id=id,name=item.name,quantity=quantity}
        end
        if not has("AddItem") then self:log("API_MISSING","AddItem"); return false end
        self.pending=jobs; self:log("PREPARED_ITEMS","entries="..#jobs.." quantity="..quantity)
        self:message("待確認："..#jobs.." 項，每項 "..quantity.."。點擊 [CONFIRM] 才會給予；[CANCEL] 取消。")
        return true
    end
    function c:prepareAll(kind)
        local groups={weapons={weapons=true,dlc_weapons=true,bb_weapons=true},clothes={clothes=true,dlc_clothes=true,bb_clothes=true,trip_clothes=true},items={weapons=true,dlc_weapons=true,bb_weapons=true,clothes=true,dlc_clothes=true,bb_clothes=true,trip_clothes=true,supplies=true,cars=true,songs=true}}
        if not groups[kind] then self:log("INVALID_ALL_GROUP"); return false end
        local ids={}; for _,item in ipairs(catalog) do if groups[kind][item.group] and (item.mode=="both" or item.mode==self.mode) then ids[#ids+1]=item.id end end
        return self:prepareItems(ids,1)
    end
    function c:prepareCash(amount)
        if not self:can(true) then return false end
        if #self.queue>0 or self.pending or not integer(amount,1,1000000) then self:log("CASH_REFUSED"); return false end
        if not has("GiveCash") then self:log("API_MISSING","GiveCash"); return false end
        self.pending={{kind="cash",quantity=amount}}
        self:log("PREPARED_CASH","amount="..amount); self:message("待確認：現金 +"..amount.."。點擊 [CONFIRM] 執行。")
        return true
    end
    function c:confirm()
        if not self:can(true) or not self.pending or #self.queue>0 then return false end
        self.queue=self.pending; self.pending=nil; self:log("BATCH_STARTED","entries="..#self.queue)
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
        self:message("已請求生成車輛；這不是叫車解鎖，也不增加線上比賽次數。")
        return true
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
        if #self.queue>0 and self.frames%4==0 then
            if not self:can(true,true) then self:stop("BATCH_GUARD_FAILED"); return end
            local job=table.remove(self.queue,1); local ok,result
            if job.kind=="cash" then ok,result=self:invoke("GiveCash",0,job.quantity)
            else ok,result=self:invoke("AddItem",job.name,job.quantity) end
            if not ok or result==false then self:stop("BATCH_CALL_FAILED"); return end
            self.submitted=self.submitted+1
            self:log("REQUEST_SUBMITTED",(job.id or "cash").." quantity="..job.quantity.." readback=UNAVAILABLE")
            if #self.queue==0 then self:log("BATCH_SUBMITTED_NOT_VERIFIED"); self:message("本批調用已提交，未回讀。請核對物品/點數，再正常存檔、重啓驗證。") end
        end
    end
    function c:probe()
        self:log("PROBE","version=0.3.0-alpha mode="..self.mode.." persistent_ticket="..tostring(self:ticketValid()))
        local names={}
        for k,v in pairs(env) do
            if type(k)=="string" and type(v)=="function" and #k<100 and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
                local s=k:lower()
                if s:find("skill") or s:find("progress") or s:find("achiev") or s:find("invent") or s:find("item") or s:find("battery") or s:find("online") or s:find("session") or s:find("experience") or s:find("network") then names[#names+1]=k end
            end
        end
        table.sort(names)
        for n=1,math.min(#names,300),15 do
            local part={}; for j=n,math.min(n+14,#names,300) do part[#part+1]=names[j] end
            self:log("CAP",table.concat(part,","))
        end
        self:log("PROBE_DONE","player_available="..tostring(self:player()~=nil).." native_function_names="..#names)
        self:message("只讀能力報告已寫入宿主日誌，僅列函數名，不掃描內存或讀取賬號。")
    end
    return c
end
