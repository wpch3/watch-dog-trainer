-- WD1KIT UI4: hot-reload callbacks, poll-executed commands, full unlock categories.
-- Patterns verified against the public NexusTools.Trainer: every command re-binds its
-- callback via SH_Commands_RegisterCallback, and continuous effects are driven by an
-- OnUpdate poll of command state, so a dead button callback can no longer silence a switch.
return function(c, catalog, mode)
    local U={clicks=0,updates=0,loads=0,pauses=0,resumes=0,polls=0,lastAction="none",lastError="none",views={},
        core=c,catalog=catalog,mode=mode,ids={},callbacks={},labels={},kinds={},defaults={},toggles={},
        errors={},builds={},actions={},poll={toggles={},moments={},index={}}}
    WD1KIT_UI4=U
    WD1KIT_UI2=U -- compatibility for older diagnostics and page bodies
    WD1KIT_UI4_REGISTRY=WD1KIT_UI4_REGISTRY or {}
    WD1KIT_UI4_REGISTRY[mode]=U
    function WD1KIT_UI4_LOG(code,detail)
        if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT] "..code..(detail and (" "..detail) or "")) end
    end
    function WD1KIT_UI4_ERROR(state,code,err)
        if state then state.lastError=code;state.errors[#state.errors+1]=code end
        WD1KIT_UI4_LOG("UI4_ERROR",code)
        if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT-UI-DETAIL] "..code..": "..tostring(err)) end
        if type(SH_Notifications_PushNotification)=="function" then pcall(SH_Notifications_PushNotification,"UI4 error: "..code..". See status panel / log.") end
    end
    function WD1KIT_UI4_DISPATCH(modeKey,index,stage)
        -- Deliberately log before any state/alive/permission guard. STATUS and PING must never be silent.
        WD1KIT_UI4_LOG("UI4_ENTER","mode="..modeKey.." action="..tostring(index).." stage="..stage)
        local registry=WD1KIT_UI4_REGISTRY or WD1KIT_UI3_REGISTRY
        local state=registry and registry[modeKey]
        if not state then WD1KIT_UI4_ERROR(nil,"STATE_MISSING",modeKey);return end
        WD1KIT_UI4=state;WD1KIT_UI2=state
        state.clicks=state.clicks+1;state.lastAction=stage..":"..tostring(index)
        local fn=state.actions[index]
        if type(fn)~="function" then WD1KIT_UI4_ERROR(state,"ACTION_MISSING",index)
        else
            local ok,err=pcall(fn)
            if not ok then WD1KIT_UI4_ERROR(state,"ACTION_FAILED",err) end
        end
        -- Visible in-panel status is independent of transient host notifications.
        local snapshot={};for i=1,math.min(#state.views,16) do snapshot[#snapshot+1]=state.views[i] end
        for _,view in ipairs(snapshot) do pcall(function() view:Rerender() end) end
        WD1KIT_UI4_LOG("UI4_ACK","clicks="..state.clicks.." updates="..state.updates.." polls="..state.polls.." alive="..tostring(state.core.alive).." armed="..tostring(state.core.armed).." god="..tostring(state.core.flags.god==true))
    end
    function WD1KIT_UI4_EVENT(modeKey,event,self)
        local registry=WD1KIT_UI4_REGISTRY or WD1KIT_UI3_REGISTRY
        local state=registry and registry[modeKey]
        if not state then WD1KIT_UI4_ERROR(nil,"EVENT_STATE_MISSING",event);return end
        WD1KIT_UI4=state;WD1KIT_UI2=state
        if self then self.WD1KitState=state end
        if event=="load" then state.loads=state.loads+1;WD1KIT_UI4_LOG("UI4_LOAD","mode="..modeKey)
        elseif event=="update" then
            state.updates=state.updates+1
            if state.updates==1 then WD1KIT_UI4_LOG("UI4_FIRST_UPDATE","mode="..modeKey) end
            local ok,err=pcall(state.core.tick,state.core)
            if not ok then state.core:stop("UPDATE_ERROR");WD1KIT_UI4_ERROR(state,"UPDATE_FAILED",err) end
            local okPoll,errPoll=pcall(state.runPoll,state)
            if not okPoll then WD1KIT_UI4_ERROR(state,"POLL_FAILED",errPoll) end
        elseif event=="pause" then state.pauses=state.pauses+1;state.core:pause();state:resetWidgets();WD1KIT_UI4_LOG("UI4_PAUSE","mode="..modeKey)
        elseif event=="resume" then state.resumes=state.resumes+1;state.core:resume();state:resetWidgets();WD1KIT_UI4_LOG("UI4_RESUME","mode="..modeKey)
        elseif event=="player" then state.core:entityChange();state:resetWidgets();WD1KIT_UI4_LOG("UI4_PLAYER_CHANGE","mode="..modeKey)
        elseif event=="unload" then state.core:shutdown("SCRIPT_UNLOADED");state:resetWidgets();WD1KIT_UI4_LOG("UI4_UNLOAD","mode="..modeKey) end
    end
    -- Single gated entry for momentary actions. Host callback, checkbox tick and the
    -- OnUpdate poll all converge here; the fired flag guarantees one execution per tick.
    function WD1KIT_UI4_MOMENT(modeKey,key)
        local registry=WD1KIT_UI4_REGISTRY or WD1KIT_UI3_REGISTRY
        local state=registry and registry[modeKey]
        if not state then WD1KIT_UI4_ERROR(nil,"STATE_MISSING",modeKey);return end
        local entry=state.poll.index[key]
        if not entry or entry.fired then return end
        local ok,v=pcall(SH_Commands_GetStateBool,entry.id)
        if ok and v~=true then return end -- host invoked the callback without an actual tick
        if not state.core.alive then WD1KIT_UI4_LOG("UI4_MOMENT_DEAD_CORE",key);pcall(SH_Commands_SetStateBool,entry.id,false);return end
        entry.fired=true
        WD1KIT_UI4_DISPATCH(modeKey,entry.action,"moment_"..key)
        pcall(SH_Commands_SetStateBool,entry.id,false)
    end
    -- Page registry: Layout thunks stay ZERO-upvalue (globals + constants only), and each
    -- page body runs inside pcall. A mid-page error now PRINTS on the page instead of
    -- silently truncating the rest (this is how 04 lost its buttons without any UI ERROR).
    WD1KIT_UI4_PAGES={}
    function WD1KIT_UI4_PAGE_DISPATCH(name,root)
        local body=WD1KIT_UI4_PAGES and WD1KIT_UI4_PAGES[name]
        if not body then
            if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT] UI4_PAGE_MISSING "..name) end
            return
        end
        local ok,err=pcall(body,root)
        if not ok then
            WD1KIT_UI4_LOG("UI4_PAGE_ERROR",name.." "..tostring(err))
            pcall(function() root:Text("[UI ERROR: page "..name.." stopped partway: "..tostring(err).."] Report this exact line.") end)
        end
    end
    local function log(code, detail) c:log(code,detail) end
    local function uiError(stage,err)
        U.errors[#U.errors+1]=stage
        log("UI4_ERROR",stage)
        -- Details stay local to the host log; the companion only exports its restricted format.
        if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT-UI-DETAIL] "..stage..": "..tostring(err)) end
    end
    local required={"Script","SH_Menu_RegisterMenu","SH_Menu_RegisterCategory"}
    for _,name in ipairs(required) do if type(_G[name])~="function" then log("HOST_API_MISSING",name);c:shutdown("INCOMPATIBLE_HOST");return false end end
    local menu=SH_Menu_RegisterMenu(mode=="campaign" and "WD1 KIT - Main [UI4]" or "WD1 KIT - Bad Blood [UI4]")
    U.menu=menu
    local prefix="wd1kit_"..mode.."_"
    function U:bind(action,stage)
        local index=#self.actions+1;self.actions[index]=action
        -- Prefer a compiled literal thunk: ZERO upvalues, so a host that drops or
        -- serializes closures still gets a callable. Fixed project values only.
        if type(loadstring)=="function" then
            local source=string.format("return function() if type(WD1KIT_UI4_DISPATCH)=='function' then WD1KIT_UI4_DISPATCH(%q,%d,%q) else if type(SH_LOG)=='function' then pcall(SH_LOG,'[WD1KIT] UI4_DISPATCH_MISSING') end end end",self.mode,index,stage or "callback")
            local chunk,err=loadstring(source,"WD1KIT_UI4_callback")
            if chunk then
                if type(setfenv)=="function" and type(getfenv)=="function" then pcall(setfenv,chunk,getfenv(1)) end
                local ok,fn=pcall(chunk)
                if ok and type(fn)=="function" then return fn end
            else
                uiError("bind_"..stage,err)
            end
        end
        -- Fallback: plain closure. Worse if the host loses upvalues, but never fatal.
        log("UI4_THUNK_FALLBACK",stage)
        return function()
            local registry=WD1KIT_UI4_REGISTRY or WD1KIT_UI3_REGISTRY
            local state=registry and registry[self.mode]
            if not state then return end
            WD1KIT_UI4_DISPATCH(self.mode,index,stage or "callback")
        end
    end
    -- Momentary command thunks call the gated MOMENT entry directly; the raw action is
    -- dispatched exactly once from inside WD1KIT_UI4_MOMENT after the fired-flag check.
    function U:bindMoment(key)
        if type(loadstring)=="function" then
            local source=string.format("return function() if type(WD1KIT_UI4_MOMENT)=='function' then WD1KIT_UI4_MOMENT(%q,%q) elseif type(SH_LOG)=='function' then pcall(SH_LOG,'[WD1KIT] UI4_MOMENT_MISSING') end end",self.mode,key)
            local chunk,err=loadstring(source,"WD1KIT_UI4_moment")
            if chunk then
                if type(setfenv)=="function" and type(getfenv)=="function" then pcall(setfenv,chunk,getfenv(1)) end
                local ok,fn=pcall(chunk)
                if ok and type(fn)=="function" then return fn end
            else
                uiError("bindMoment_"..key,err)
            end
        end
        log("UI4_THUNK_FALLBACK","moment_"..key)
        return function() WD1KIT_UI4_MOMENT(self.mode,key) end
    end
    function U:resetWidgets()
        if type(SH_Commands_SetStateBool)=="function" then for _,id in ipairs(self.toggles) do pcall(SH_Commands_SetStateBool,id,false) end end
    end
    function U:arm()
        self:resetWidgets()
        local ok=self.core:arm()
        if not ok then self.core:message("ARM refused: alive="..tostring(self.core.alive).." paused="..tostring(self.core.paused).." player="..tostring(self.core:player()~=nil));WD1KIT_UI4_LOG("UI4_ARM_REFUSED","alive="..tostring(self.core.alive).." paused="..tostring(self.core.paused).." player="..tostring(self.core:player()~=nil)) end
    end
    function U:stop() self.core:stop("USER_STOP");self:resetWidgets() end
    function U:setToggle(id,on)
        if not self.core.alive then WD1KIT_UI4_ERROR(self,"CORE_UNLOADED",self.core.lastCode);return end
        local ok=self.core:toggle(id,on)
        if type(SH_Commands_SetStateBool)=="function" and self.ids[id] then pcall(SH_Commands_SetStateBool,self.ids[id],ok and on or false) end
        self.core:message(id..(ok and (on and " ON requested" or " OFF") or " refused - check ARM/API/backup"))
    end
    function U:state()
        local t=self.core
        t:message("UI4 state: armed="..tostring(t.armed)..", god="..tostring(t.flags.god==true)..", clicks="..self.clicks..", polls="..self.polls..", updates="..self.updates..", last="..self.lastAction..", core="..tostring(t.lastCode)..", errors="..#self.errors)
        WD1KIT_UI4_LOG("UI4_STATUS","armed="..tostring(t.armed).." god="..tostring(t.flags.god==true).." script="..tostring(t.script~=nil).." errors="..#self.errors.." clicks="..self.clicks.." updates="..self.updates.." polls="..self.polls.." alive="..tostring(t.alive).." paused="..tostring(t.paused))
        local snapshot={};for i=1,math.min(#self.views,16) do snapshot[#snapshot+1]=self.views[i] end
        for _,view in ipairs(snapshot) do pcall(function() view:Rerender() end) end
    end
    function U:integer(key)
        local id=self.ids[key]
        if id and type(SH_Commands_GetStateInt)=="function" then local ok,v=pcall(SH_Commands_GetStateInt,id);if ok and type(v)=="number" then return v end end
        return self.defaults[key]
    end
    -- Unified poll edge handling. Both the host callback path and the OnUpdate poll
    -- converge here, so a command can never be executed twice by one user action.
    function U:pollEdge(entry,on)
        on=(on==true)
        if on==entry.last then return end
        entry.last=on
        if not on then self.core:toggle(entry.key,false) return end
        if not self.core.alive then pcall(SH_Commands_SetStateBool,entry.id,false);entry.last=false;return end
        if not self.core:toggle(entry.key,true) then
            pcall(SH_Commands_SetStateBool,entry.id,false);entry.last=false
        end
    end
    function U:fireMoment(key)
        WD1KIT_UI4_MOMENT(self.mode,key)
    end
    function U:runPoll()
        self.polls=self.polls+1
        if type(SH_Commands_GetStateBool)~="function" then return end
        for _,entry in ipairs(self.poll.toggles) do
            local ok,v=pcall(SH_Commands_GetStateBool,entry.id)
            if ok then self:pollEdge(entry,v) end
        end
        for _,entry in ipairs(self.poll.moments) do
            local ok,v=pcall(SH_Commands_GetStateBool,entry.id)
            if ok then
                if v==true then self:fireMoment(entry.key)
                else entry.fired=false end
            end
        end
    end
    -- Register lifecycle before constructing any optional GUI content.
    local script=Script("wd1kit_"..mode)
    c.script=script
    local function eventThunk(event)
        if type(loadstring)=="function" then
            local chunk,err=loadstring(string.format("return function(self) if type(WD1KIT_UI4_EVENT)=='function' then WD1KIT_UI4_EVENT(%q,%q,self) elseif type(SH_LOG)=='function' then pcall(SH_LOG,'[WD1KIT] UI4_EVENT_DISPATCH_MISSING') end end",mode,event),"WD1KIT_UI4_event")
            if chunk then
                if type(setfenv)=="function" and type(getfenv)=="function" then pcall(setfenv,chunk,getfenv(1)) end
                local ok,fn=pcall(chunk)
                if ok and type(fn)=="function" then return fn end
            else
                uiError("event_"..event,err)
            end
        end
        log("UI4_THUNK_FALLBACK","event_"..event)
        return function(self) WD1KIT_UI4_EVENT(mode,event,self) end
    end
    script.OnLoad=eventThunk("load")
    script.OnUpdate=eventThunk("update")
    script.OnPause=eventThunk("pause")
    script.OnResume=eventThunk("resume")
    script.OnPlayerEntityChange=eventThunk("player")
    script.OnUnload=eventThunk("unload")
    function menu:OnRemove() c:shutdown("MENU_REMOVED");pcall(function() script:Remove() end) end
    -- kind "bool"  : continuous switch, poll-applied (checkbox alone is enough, callback optional).
    -- kind "moment": momentary action switch; ticking it runs the action once, then resets.
    -- kind "int"   : input only, applied by an explicit moment action.
    local function register(kind,key,label,default,min,max,action)
        local id=prefix..key;U.ids[key]=id;U.labels[key]=label;U.kinds[key]=kind;U.defaults[key]=default
        local callback
        if kind=="bool" then
            callback=U:bind(function()
                if not c.alive then WD1KIT_UI4_ERROR(U,"CORE_UNLOADED",c.lastCode);return end
                local ok,value=pcall(SH_Commands_GetStateBool,id)
                if not ok then uiError("read_"..key,value);return end
                U:pollEdge(U.poll.index[key],value)
            end,"command_"..key)
        elseif kind=="moment" then
            local index=#U.actions+1;U.actions[index]=action
            callback=U:bindMoment(key)
            U.poll.index[key]={key=key,id=id,action=index,fired=false}
            U.poll.moments[#U.poll.moments+1]=U.poll.index[key]
        else
            callback=nil
        end
        U.callbacks[key]=callback
        local ok,err=pcall(function()
            if kind=="int" then SH_Commands_RegisterInt(id,label,"Input only; use the separate action to apply.",menu,default,min,max)
            else SH_Commands_RegisterBool(id,label,kind=="moment" and "Tick once: runs the action and resets itself." or "Tick to enable, untick to disable. Poll-applied.",menu,false,callback) end
        end)
        -- Registration may legitimately fail when an older session already owns the id
        -- (command state persists across restarts). The callback rebind below is what
        -- actually attaches this session's handler, so it runs unconditionally.
        if not ok then uiError("register_"..key,err) end
        if callback and type(SH_Commands_RegisterCallback)=="function" then
            local okCB,errCB=pcall(SH_Commands_RegisterCallback,id,callback)
            if not okCB then uiError("rebind_"..key,errCB) end
        end
        if kind=="bool" then
            U.toggles[#U.toggles+1]=id
            U.poll.index[key]={key=key,id=id,last=false}
            U.poll.toggles[#U.poll.toggles+1]=U.poll.index[key]
        end
        if kind~="int" and type(SH_Commands_SetStateBool)=="function" then pcall(SH_Commands_SetStateBool,id,false) end
        return id
    end
    register("moment","arm","[ARM] I am offline and in single-player free roam",nil,nil,nil,function() WD1KIT_UI2:arm() end)
    register("moment","stop","[STOP] Disable effects and cancel pending requests",nil,nil,nil,function() WD1KIT_UI2:stop() end)
    register("moment","confirm","[CONFIRM] Apply the prepared item or cash request",nil,nil,nil,function() c:confirm() end)
    register("moment","cancel","[CANCEL] Cancel item or cash queue",nil,nil,nil,function() c:cancel() end)
    register("moment","probe","[REPORT] Write capabilities and UI state to host log",nil,nil,nil,function() c:probe();WD1KIT_UI2:state() end)
    register("bool","god","God Mode",false)
    register("bool","ammo","Infinite Ammo - continuous refill",false)
    register("bool","focus","Infinite Focus - continuous refill",false)
    register("bool","police","Disable Wanted System",false)
    register("int","item_quantity","Item / material quantity to add",1,1,100)
    register("int","heat_value","Wanted Heat input 0-100",0,0,100)
    register("int","cash_value","Cash to add",1000,1,1000000)
    register("int","point_value","Normal Skill Point rewards - test +1 first",1,1,100)
    register("int","hour","Hour",12,0,23)
    register("int","minute","Minute",0,0,59)
    -- UI boundary helpers: a failed widget must not silently discard the remainder of a page.
    function U:text(root,text,style)
        local ok,err=pcall(function() root:Text(text,style or {size=15}) end);if not ok then uiError("text",err) end
    end
    function U:button(root,label,action)
        local guarded=self:bind(action,"button_action")
        local ok,err=pcall(function() root:Button(label,guarded) end)
        if not ok then uiError("button",err);self:text(root,"[UI ERROR: button] Use 00 / Quick Controls or host log.") end
    end
    function U:labelFor(id,fallback)
        local e=self.core.entries[id]
        if e and type(e.label)=="string" then return e.label end
        return fallback or id
    end
    function U:widget(root,key)
        local id=self.ids[key]
        if not id then self:text(root,"[UNAVAILABLE] "..(self.labels[key] or key));return false end
        local ok,err=pcall(function() root:CommandWidget(id) end)
        if not ok then uiError("widget_"..key,err);self:text(root,"[UI ERROR: "..key.."] Other buttons remain available.") end
        return ok
    end
    function U:diagnostic(root)
        if self.core and self.core.service then pcall(self.core.service,self.core,6) end
        local seen=false;for _,v in ipairs(self.views) do if v==root then seen=true;break end end;if not seen then if #self.views>=16 then table.remove(self.views,1) end;self.views[#self.views+1]=root end
        self:text(root,"Clicks="..self.clicks.." | Updates="..self.updates.." | Loads="..self.loads.." | Polls="..self.polls,{size=16,bold=true})
        self:text(root,"Alive="..tostring(self.core.alive).." | Paused="..tostring(self.core.paused).." | Armed="..tostring(self.core.armed).." | God="..tostring(self.core.flags.god==true))
        self:text(root,"Ammo="..tostring(self.core.flags.ammo==true).." | Focus="..tostring(self.core.flags.focus==true).." | Police="..tostring(self.core.flags.police==true))
        self:text(root,"MSG="..tostring(self.core.lastMessage))
        self:text(root,"LOG="..tostring(self.core.lastLog))
        self:text(root,"PREV="..tostring(self.core.bootNote))
        self:text(root,"BATCH(0.4.21): submitted="..tostring(self.core.submitted).." refused="..tostring(self.core.batchFail and #self.core.batchFail or 0).." left="..tostring(self.core.queue and #self.core.queue or 0).." pending="..tostring(self.core.pending and #self.core.pending or 0))
        self:text(root,"Last="..self.lastAction.." | Core="..tostring(self.core.lastCode).." | Error="..self.lastError)
    end
    function U:header(root)
        self:text(root,"WD1 KIT v0.4.21 [UI4] - full host API dump, no more guessing",{size=18,bold=true})
        self:text(root,"Plugin file version 0.4.21. If this line does not say 0.4.21, the game is running an OLD plugin: reinstall the payload and run Install in the desktop tool with the game CLOSED.")
        self:diagnostic(root)
        self:button(root,"[PING] Test this button - no game changes",function() local s=WD1KIT_UI4_REGISTRY and WD1KIT_UI4_REGISTRY[mode];WD1KIT_UI4_LOG("UI4_PING");if type(SH_Notifications_PushNotification)=="function" then pcall(SH_Notifications_PushNotification,"UI4 PING received. THIS notification proves buttons work. clicks="..(s and s.clicks or -1).." polls="..(s and s.polls or -1).." armed="..(s and tostring(s.core.armed) or "?")) end end)
        self:button(root,"[ARM] Enable this offline test session",function() WD1KIT_UI2:arm() end)
        self:button(root,"[STOP] Disable all tool effects",function() WD1KIT_UI2:stop() end)
    end
    function U:confirmButtons(root)
        self:button(root,"[CONFIRM] Apply prepared request",function() WD1KIT_UI2.core:confirm() end)
        self:button(root,"[CANCEL] Cancel pending request",function() WD1KIT_UI2.core:cancel() end)
        self:text(root,"CONFIRM/CANCEL also exist as checkboxes: tick once, they run and reset. Watch the MSG= and BATCH: lines above for results.")
    end
    -- Independent emergency/diagnostic path; does not depend on Layout or CommandWidget.
    if type(SH_Menu_AddButton_CB)=="function" then
        local quick=SH_Menu_RegisterCategory("00 / Quick Controls",menu)
        local function quickButton(label,fn)
            local ok,err=pcall(SH_Menu_AddButton_CB,label,menu,quick,U:bind(fn,"legacy_action"))
            if not ok then uiError("legacy_button",err) end
        end
        quickButton("[PING] Test callback only",function() local s=WD1KIT_UI4_REGISTRY and WD1KIT_UI4_REGISTRY[mode];WD1KIT_UI4_LOG("UI4_PING");if type(SH_Notifications_PushNotification)=="function" then pcall(SH_Notifications_PushNotification,"UI4 PING received. THIS notification proves buttons work. clicks="..(s and s.clicks or -1).." polls="..(s and s.polls or -1).." armed="..(s and tostring(s.core.armed) or "?")) end end)
        quickButton("[ARM] Offline free-roam test ["..(mode=="campaign" and "MAIN" or "BADBLOOD").."]",function() WD1KIT_UI2:arm() end)
        quickButton("God Mode ON",function() WD1KIT_UI2:setToggle("god",true) end)
        quickButton("God Mode OFF",function() WD1KIT_UI2:setToggle("god",false) end)
        quickButton("[DUMP API] List EVERY host function into the log (car functions hunt)",function() WD1KIT_UI2.core:dumpApiEnv() end)
        quickButton("[STEP 2] CONFIRM ["..(mode=="campaign" and "MAIN" or "BADBLOOD").."] (auto-prepares 74 cars)",function() local k=WD1KIT_UI2.core;k:softRevive("step2");if not k.armed then k:arm() end;if not k.pending then k:prepareGroup("cars",1) end;k:confirm() end)
        quickButton("[CANCEL] Cancel pending request",function() WD1KIT_UI2.core:cancel() end)
        quickButton("[UNLOCK] Prepare 4 online-reward weapons",function() WD1KIT_UI2.core:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
        quickButton("[UNLOCK TEST] Prepare 7 named cars (Livraga LE, Sayonara LE, Boxberg LE, Papavero Stealth...)",function() WD1KIT_UI2.core:prepareItems({"item_678076169","item_2584458734","item_217841595","item_1783601268","item_3546717439","item_2757864553","item_4189416026"},1) end)
        quickButton("[STEP 1] Prepare ALL 74 delivery cars ["..(mode=="campaign" and "MAIN" or "BADBLOOD").."]",function() WD1KIT_UI2.core:prepareGroup("cars",1) end)
        quickButton("[STATUS] Show armed / god / script",function() WD1KIT_UI2:state() end)
        quickButton("[STOP] Disable tool effects",function() WD1KIT_UI2:stop() end)
        quickButton("[REPORT] Log capabilities and UI status",function() WD1KIT_UI2.core:probe();WD1KIT_UI2:state() end)
    else log("UI4_LEGACY_UNAVAILABLE") end
    -- Shared renderer for catalog groups. Global on purpose: Layout callbacks must own
    -- zero upvalues, so every helper is resolved from the global state at run time.
    function WD1KIT_UI4_RENDER_GROUP(root,group,title,batch,supply)
        local ui=WD1KIT_UI2;if not ui then return end
        local list={}
        for _,v in ipairs(ui.catalog) do if v.group==group and (v.mode=="both" or v.mode==ui.mode) then list[#list+1]=v end end
        if #list==0 then return end
        local ok,err=pcall(function()
            root:CollapsingHeader(title.." ("..#list..")",false,function(h)
                local u=WD1KIT_UI2
                if batch then u:button(h,"[PREPARE ALL] "..title.." ("..#list..")",function() WD1KIT_UI2.core:prepareGroup(group,1) end) end
                for _,v in ipairs(list) do
                    local id=v.id
                    local okItem,errItem=pcall(function()
                        h:Button(v.label,function()
                            local state=WD1KIT_UI2
                            state.core:prepareItems({id},supply and state:integer("item_quantity") or 1)
                        end)
                    end)
                    if not okItem then u:text(h,"[UI ERROR: item] "..tostring(errItem)) end
                end
            end)
        end)
        if not ok then ui.errors[#ui.errors+1]="group_"..group;ui.core:log("UI4_ERROR","group_"..group);ui:text(root,"[UI ERROR: "..group.."] batch buttons above remain available.") end
    end
    -- Each callback below has no captured builder-function upvalue. It looks up the live UI state globally.
    local safety=SH_Menu_RegisterCategory("01 / Safety and Report",menu)
    safety:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        ui:text(root,"Offline free roam only. No online contracts, invasions, races, co-op or cutscenes.")
        ui:text(root,"Game calls, ownership and persistent saves remain unverified until tested.")
        ui:text(root,"Persistent grants need a valid backup receipt. Adding resources does not enable infinite effects.")
        ui:text(root,"Checkboxes below work even if button callbacks fail: poll-applied on tick.")
        ui:button(root,"[STATUS] Show tool state",function() WD1KIT_UI2:state() end)
        ui:button(root,"[REPORT] Log capabilities and UI status",function() WD1KIT_UI2.core:probe();WD1KIT_UI2:state() end)
        ui:widget(root,"arm");ui:widget(root,"stop");ui:widget(root,"confirm");ui:widget(root,"cancel");ui:widget(root,"probe")
        ui:text(root,"ARM/STOP/CONFIRM/CANCEL/REPORT checkboxes are momentary: they run once and reset.")
        ui:text(root,"Story, investigations, collectibles and online progression are not rewritten here.")
        ui:text(root,"PAGE MAP Main: 00 Quick / 01 Safety / 02 Player / 03 Skill+Cash / 04 Online Rewards / 05 Items+CARS / 06 Vehicles+World / 07 Progression / 08 Tokens.")
        ui:text(root,"PAGE MAP Bad Blood: same but NO 04 (campaign rewards) and DLC-filtered items. Page order matches numbers in v0.4.9.")
    end)
    local player=SH_Menu_RegisterCategory("02 / Player and Police",menu)
    player:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        -- Plain buttons appear before any optional typed command widget.
        ui:button(root,"God Mode ON",function() WD1KIT_UI2:setToggle("god",true) end)
        ui:button(root,"God Mode OFF",function() WD1KIT_UI2:setToggle("god",false) end)
        ui:button(root,"[STATUS] Show armed / god / script",function() WD1KIT_UI2:state() end)
        ui:text(root,"You may also tick the checkbox below. It is poll-applied and needs no callback.")
        ui:widget(root,"god")
        ui:button(root,"Infinite Ammo ON",function() WD1KIT_UI2:setToggle("ammo",true) end)
        ui:button(root,"Infinite Ammo OFF",function() WD1KIT_UI2:setToggle("ammo",false) end)
        ui:button(root,"[ADD AMMO] Refill ammo once",function() WD1KIT_UI2.core:ammoOnce() end)
        ui:widget(root,"ammo")
        ui:button(root,"Infinite Focus ON",function() WD1KIT_UI2:setToggle("focus",true) end)
        ui:button(root,"Infinite Focus OFF",function() WD1KIT_UI2:setToggle("focus",false) end)
        ui:widget(root,"focus")
        ui:widget(root,"police");ui:widget(root,"heat_value")
        ui:button(root,"Apply Wanted Heat",function() local u=WD1KIT_UI2;u.core:heat(u:integer("heat_value")) end)
    end)
    local growth=SH_Menu_RegisterCategory("03 / Skill Points and Cash",menu)
    growth:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
        ui:widget(root,"point_value")
        ui:button(root,"[ITEM ONLY] Skill Point bag item - the COUNTER is changed in the DESKTOP tool, not here",function() local u=WD1KIT_UI2;u.core:prepareItems({"item_2023158576"},u:integer("point_value")) end)
        ui:widget(root,"cash_value")
        ui:button(root,"Prepare Cash - then CONFIRM",function() local u=WD1KIT_UI2;u.core:prepareCash(u:integer("cash_value")) end)
        ui:text(root,"Skill and XP reward items also live in 07 / Progression Rewards.")
        ui:text(root,"These are normal growth rewards, not all Digital Trip skill trees.")
    end)
    if mode=="campaign" then
        local rewards=SH_Menu_RegisterCategory("04 / Local Online-Gated Rewards",menu)
        rewards:Layout(function(root)
            local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
            ui:text(root,"VERIFIED by user 2026-09-16: the four online-reward weapons unlock locally.")
            ui:button(root,"Prepare all four online-reward weapons",function() WD1KIT_UI2.core:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
            ui:button(root,"[CAR UNLOCK TEST] Grant 7 named cars: Livraga LE / Sayonara / Sayonara LE / Boxberg LE / Boxberg R1 / Papavero / Papavero Stealth Edition",function() WD1KIT_UI2.core:prepareItems({"item_678076169","item_2584458734","item_217841595","item_1783601268","item_3546717439","item_2757864553","item_4189416026"},1) end)
            ui:text(root,"CAR UNLOCK HOW TO: press CONFIRM -> SAVE normally -> FULLY QUIT to desktop -> start the game again -> check Car On Demand. Spawning (06) is not an unlock and the game refuses locked cars.")
            ui:text(root,"For ALL 74 mission/hidden/reward cars use 05 / Item Whitelist -> [ALL CARS].")
            ui:text(root,"Notoriety perk tree and decryption loadouts are NOT items (native path pending). APS tokens: see the note on 07.")
            for _,id0 in ipairs({"item_2207476061","item_4099987261","item_770883049","item_309961700","item_678076169"}) do
                local id=id0;ui:button(root,ui:labelFor(id,"Unknown reward item").." - prepare",function() WD1KIT_UI2.core:prepareItems({id},1) end)
            end
        end)
    end
    local items=SH_Menu_RegisterCategory("05 / Item Whitelist",menu)
    items:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
        ui:text(root,"Every batch waits for [CONFIRM]. Single items grant immediately on prepare.")
        ui:button(root,"[ALL WEAPONS] Prepare weapon candidates",function() WD1KIT_UI2.core:prepareAll("weapons") end)
        ui:button(root,"[ALL CLOTHES] Prepare outfit candidates",function() WD1KIT_UI2.core:prepareAll("clothes") end)
        ui:button(root,"[ALL ITEMS] Prepare current-mode items",function() WD1KIT_UI2.core:prepareAll("items") end)
        ui:button(root,"[ALL GEAR] Prepare materials and upgrades",function() WD1KIT_UI2.core:prepareAll("gear") end)
        ui:button(root,"[ALL CARS] Prepare the FULL delivery-car catalog (74): mission, hidden and reward cars",function() WD1KIT_UI2.core:prepareGroup("cars",1) end)
        ui:widget(root,"item_quantity")
        WD1KIT_UI4_RENDER_GROUP(root,"weapons","Weapons",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"custom_weapons","Special weapon variants",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"dlc_weapons","Owned ULC Weapons",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"bb_weapons","Bad Blood Weapons",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"supplies","Consumables and Materials",true,true)
        WD1KIT_UI4_RENDER_GROUP(root,"upgrades","Crafting and Upgrades",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"tech","Tech and Schematics",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"projectiles","Projectiles",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"explosives","Explosives",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"ammo","Ammunition",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"meds","Medicine",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"food","Food",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"misc_items","Miscellaneous Items",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"bb_items","Bad Blood Items",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"clothes","Aiden Outfits",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"clothes_mod","Outfit Appearance Mods",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"dlc_clothes","Owned ULC Outfits",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"trip_clothes","Digital Trip Reward Outfits",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"bb_clothes","T-Bone Outfits",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"cars","Car Unlock Rewards (Car On Demand)",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"songs","Song Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"collectibles","Collectibles",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"audio_drops","Audio Logs",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"video_logs","Video Logs",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"survival_guide","Survival Guide Pages",false,false)
        WD1KIT_UI4_RENDER_GROUP(root,"apps","Phone Applications (some are MP items)",false,false)
        ui:text(root,"ALL means the current-mode whitelist of this catalog. Not a 100 percent completion claim.")
    end)
    local world=SH_Menu_RegisterCategory("06 / Vehicles and World",menu)
    world:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        ui:text(root,"At most five spawns per session. Spawning is NOT an unlock.")
        ui:text(root,"USER TESTED 2026-09-16: locked/LE cars REFUSE to spawn (game ownership gate); only owned cars spawn.")
        ui:text(root,"TO UNLOCK PERMANENTLY: 05 / Item Whitelist -> [ALL CARS] (74) -> CONFIRM -> SAVE -> FULLY RESTART the game -> check Car On Demand.")
        ui:text(root,"After the restart-unlock, spawning those cars should also work.")
        for i,v in ipairs(ui.core.vehicles) do local index=i;ui:button(root,"Spawn "..v.label,function() WD1KIT_UI2.core:spawn(index) end) end
        ui:widget(root,"hour");ui:widget(root,"minute")
        ui:button(root,"Apply Time - restart to release scripted clock",function() local u=WD1KIT_UI2;u.core:setTime(u:integer("hour"),u:integer("minute")) end)
    end)
    local progression=SH_Menu_RegisterCategory("07 / Progression Rewards",menu)
    progression:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
        ui:text(root,"HOW TO, step by step: 1) tick [ARM] in 01.  2) click ONE reward below.  3) click [CONFIRM] above.  4) watch for Prepared/BATCH notifications.")
        ui:text(root,"ONLINE progression: grant the APS tokens below (OnlineRaces, HackingInvasion, TailingInvasion, Decryption, Vigilante), then open that activity screen in game.")
        ui:text(root,"Counters, leaderboards and server-side completion are NOT rewritten by these items.")
        ui:text(root,"VERIFIED: inventory unlocks (weapons etc). Skill/XP are counters, NOT items: use the DESKTOP native panel - capture the wallet once, then use Add Skill Points / Add XP on the same capture.")
        ui:button(root,"[ALL PROGRESSION] Prepare every progression reward",function() WD1KIT_UI2.core:prepareAll("progression") end)
        ui:widget(root,"item_quantity")
        WD1KIT_UI4_RENDER_GROUP(root,"skill","Skill Point Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"xp","XP Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"mission_xp_main","Main Mission XP Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"mission_xp_side","Side Mission XP Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"mission_xp_family","Family Mission XP Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"notoriety","Vigilante Event Items and XP Tests",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"ctos_rewards","ctOS Tower Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"activity_rewards","Mini-game Progression Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"progress_misc","Other Progression Rewards",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"cash_items","Cash Reward Items",true,false)
        WD1KIT_UI4_RENDER_GROUP(root,"special_perks","Special Perks",true,false)
    end)
    local tokens=SH_Menu_RegisterCategory("08 / Mission Tokens (advanced)",menu)
    tokens:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        ui:text(root,"AccessIds, mission tokens and one-time contract items. Individual buttons only, NO batch.")
        ui:text(root,"These can skip mission steps or do nothing. Use one item at a time and verify.")
        WD1KIT_UI4_RENDER_GROUP(root,"mission_tokens","Mission Tokens and Access IDs",false,false)
    end)
    c:log("PLUGIN_LOADED","version=0.4.21-ui4 mode="..mode.." game_runtime_verified=false")
    c:log("UI4_READY","legacy="..tostring(type(SH_Menu_AddButton_CB)=="function").." thunks="..tostring(type(loadstring)=="function").." errors="..#U.errors)
    c:probe()
    return true
end
