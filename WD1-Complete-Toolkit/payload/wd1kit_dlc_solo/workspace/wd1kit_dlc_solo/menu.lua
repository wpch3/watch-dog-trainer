-- WD1KIT UI2: ASCII, global builder references, guarded widgets and plain-button fallback.
-- UI repair only. Game actions still go through the original guarded core.
return function(c, catalog, mode)
    local U={core=c,catalog=catalog,mode=mode,ids={},callbacks={},labels={},kinds={},defaults={},toggles={},errors={},builds={},actions={}}
    WD1KIT_UI2=U
    local function log(code, detail) c:log(code,detail) end
    local function uiError(stage,err)
        U.errors[#U.errors+1]=stage
        log("UI2_ERROR",stage)
        -- Details stay local to the host log; the companion only exports its restricted format.
        if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT-UI-DETAIL] "..stage..": "..tostring(err)) end
    end
    local required={"Script","SH_Menu_RegisterMenu","SH_Menu_RegisterCategory"}
    for _,name in ipairs(required) do if type(_G[name])~="function" then log("HOST_API_MISSING",name);c:shutdown("INCOMPATIBLE_HOST");return false end end
    local menu=SH_Menu_RegisterMenu(mode=="campaign" and "WD1 KIT - Main [UI2]" or "WD1 KIT - Bad Blood [UI2]")
    U.menu=menu
    local prefix="wd1kit_"..mode.."_"
    function U:bind(action,stage)
        local index=#self.actions+1;self.actions[index]=action
        return function()
            local state=WD1KIT_UI2
            if not state or not state.core.alive then return end
            local fn=state.actions[index]
            if type(fn)~="function" then state.core:log("UI2_ERROR","callback_missing");return end
            local ok,err=pcall(fn)
            if not ok then
                state.errors[#state.errors+1]=stage or "callback"
                state.core:log("UI2_ERROR",stage or "callback")
                if type(SH_LOG)=="function" then pcall(SH_LOG,"[WD1KIT-UI-DETAIL] "..tostring(err)) end
                state.core:message("UI2 action failed. Use REPORT.")
            end
        end
    end
    function U:resetWidgets()
        if type(SH_Commands_SetStateBool)=="function" then for _,id in ipairs(self.toggles) do pcall(SH_Commands_SetStateBool,id,false) end end
    end
    function U:arm() self:resetWidgets();self.core:arm() end
    function U:stop() self.core:stop("USER_STOP");self:resetWidgets() end
    function U:setToggle(id,on)
        if not self.core.alive then return end
        local ok=self.core:toggle(id,on)
        if type(SH_Commands_SetStateBool)=="function" and self.ids[id] then pcall(SH_Commands_SetStateBool,self.ids[id],ok and on or false) end
        self.core:message(id..(ok and (on and " ON requested" or " OFF") or " refused - check ARM/API/backup"))
    end
    function U:state()
        local t=self.core
        t:message("UI2 state: armed="..tostring(t.armed)..", god="..tostring(t.flags.god==true)..", script="..tostring(t.script~=nil)..", ui_errors="..#self.errors)
        log("UI2_STATUS","armed="..tostring(t.armed).." god="..tostring(t.flags.god==true).." script="..tostring(t.script~=nil).." errors="..#self.errors)
    end
    function U:integer(key)
        local id=self.ids[key]
        if id and type(SH_Commands_GetStateInt)=="function" then local ok,v=pcall(SH_Commands_GetStateInt,id);if ok and type(v)=="number" then return v end end
        return self.defaults[key]
    end
    -- Register lifecycle before constructing any optional GUI content.
    local script=Script("wd1kit_"..mode)
    c.script=script
    function script:OnUpdate() if WD1KIT_UI2 then WD1KIT_UI2.core:tick() end end
    function script:OnPause() if WD1KIT_UI2 then WD1KIT_UI2.core:pause();WD1KIT_UI2:resetWidgets() end end
    function script:OnResume() if WD1KIT_UI2 then WD1KIT_UI2.core:resume();WD1KIT_UI2:resetWidgets() end end
    function script:OnPlayerEntityChange() if WD1KIT_UI2 then WD1KIT_UI2.core:entityChange();WD1KIT_UI2:resetWidgets() end end
    function script:OnUnload() if WD1KIT_UI2 then WD1KIT_UI2.core:shutdown("SCRIPT_UNLOADED");WD1KIT_UI2:resetWidgets() end end
    function menu:OnRemove() c:shutdown("MENU_REMOVED");pcall(function() script:Remove() end) end
    local function register(kind,key,label,default,min,max,action)
        local id=prefix..key;U.ids[key]=id;U.labels[key]=label;U.kinds[key]=kind;U.defaults[key]=default
        local callback=function()
            if not c.alive then return end
            if kind=="bool" then
                local ok,value=pcall(SH_Commands_GetStateBool,id)
                if not ok then uiError("read_"..key,value);return end
                if not c:toggle(key,value) and type(SH_Commands_SetStateBool)=="function" then pcall(SH_Commands_SetStateBool,id,false) end
            elseif action then action() end
        end
        callback=U:bind(callback,"command_"..key)
        U.callbacks[key]=callback
        local ok,err=pcall(function()
            if kind=="bool" then SH_Commands_RegisterBool(id,label,"UI2: explicit offline ARM required.",menu,false,callback)
            elseif kind=="int" then SH_Commands_RegisterInt(id,label,"Input only; use the separate action to apply.",menu,default,min,max)
            else SH_Commands_Register(id,label,"UI2 guarded action.",menu,callback) end
            if type(SH_Commands_RegisterCallback)=="function" then SH_Commands_RegisterCallback(id,callback) end
        end)
        if not ok then U.ids[key]=nil;uiError("register_"..key,err) end
        if kind=="bool" then U.toggles[#U.toggles+1]=id;if type(SH_Commands_SetStateBool)=="function" then pcall(SH_Commands_SetStateBool,id,false) end end
        return id
    end
    register("action","arm","[ARM] I am offline and in single-player free roam",nil,nil,nil,function() U:arm() end)
    register("action","stop","[STOP] Disable effects and cancel pending requests",nil,nil,nil,function() U:stop() end)
    register("action","confirm","[CONFIRM] Apply the prepared item or cash request",nil,nil,nil,function() c:confirm() end)
    register("action","cancel","[CANCEL] Cancel item or cash queue",nil,nil,nil,function() c:cancel() end)
    register("action","probe","[REPORT] Write capabilities and UI state to host log",nil,nil,nil,function() c:probe();U:state() end)
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
    function U:widget(root,key)
        local id=self.ids[key]
        if not id then self:text(root,"[UNAVAILABLE] "..(self.labels[key] or key));return false end
        local ok,err=pcall(function() root:CommandWidget(id) end)
        if not ok then uiError("widget_"..key,err);self:text(root,"[UI ERROR: "..key.."] Other buttons remain available.") end
        return ok
    end
    function U:header(root)
        self:text(root,"WD1 KIT UI2 - ASCII compatibility menu",{size=18,bold=true})
        self:button(root,"[ARM] Enable this offline test session",function() WD1KIT_UI2:arm() end)
        self:button(root,"[STOP] Disable all tool effects",function() WD1KIT_UI2:stop() end)
    end
    function U:confirmButtons(root)
        self:button(root,"[CONFIRM] Apply prepared request",function() WD1KIT_UI2.core:confirm() end)
        self:button(root,"[CANCEL] Cancel pending request",function() WD1KIT_UI2.core:cancel() end)
    end
    -- Independent emergency/diagnostic path; does not depend on Layout or CommandWidget.
    if type(SH_Menu_AddButton_CB)=="function" then
        local quick=SH_Menu_RegisterCategory("00 / Quick Controls",menu)
        local function quickButton(label,fn)
            local ok,err=pcall(SH_Menu_AddButton_CB,label,menu,quick,U:bind(fn,"legacy_action"))
            if not ok then uiError("legacy_button",err) end
        end
        quickButton("[ARM] Offline free-roam test",function() WD1KIT_UI2:arm() end)
        quickButton("God Mode ON",function() WD1KIT_UI2:setToggle("god",true) end)
        quickButton("God Mode OFF",function() WD1KIT_UI2:setToggle("god",false) end)
        quickButton("[STATUS] Show armed / god / script",function() WD1KIT_UI2:state() end)
        quickButton("[STOP] Disable tool effects",function() WD1KIT_UI2:stop() end)
        quickButton("[REPORT] Log capabilities and UI status",function() WD1KIT_UI2.core:probe();WD1KIT_UI2:state() end)
    else log("UI2_LEGACY_UNAVAILABLE") end
    -- Each callback below has no captured builder-function upvalue. It looks up the live UI state globally.
    local safety=SH_Menu_RegisterCategory("01 / Safety and Report",menu)
    safety:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        ui:text(root,"Offline free roam only. No online contracts, invasions, races, co-op or cutscenes.")
        ui:text(root,"Game calls, ownership and persistent saves remain unverified until tested.")
        ui:text(root,"Persistent grants need a valid backup receipt. Adding resources does not enable infinite effects.")
        ui:button(root,"[STATUS] Show tool state",function() WD1KIT_UI2:state() end)
        ui:button(root,"[REPORT] Log capabilities and UI status",function() WD1KIT_UI2.core:probe();WD1KIT_UI2:state() end)
        ui:text(root,"Story, investigations, collectibles and online progression are not rewritten here.")
    end)
    local player=SH_Menu_RegisterCategory("02 / Player and Police",menu)
    player:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        -- Plain buttons appear before any optional typed command widget.
        ui:button(root,"God Mode ON",function() WD1KIT_UI2:setToggle("god",true) end)
        ui:button(root,"God Mode OFF",function() WD1KIT_UI2:setToggle("god",false) end)
        ui:button(root,"[STATUS] Show armed / god / script",function() WD1KIT_UI2:state() end)
        ui:text(root,"You may also use the checkbox below. If a widget fails, use the separate ON/OFF buttons.")
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
        ui:button(root,"Prepare normal Skill Point reward",function() local u=WD1KIT_UI2;u.core:prepareItems({"item_2023158576"},u:integer("point_value")) end)
        ui:widget(root,"cash_value")
        ui:button(root,"Prepare Cash - then CONFIRM",function() local u=WD1KIT_UI2;u.core:prepareCash(u:integer("cash_value")) end)
        for _,v in ipairs(ui.catalog) do if v.group=="xp" then local id=v.id;ui:button(root,v.label.." - prepare",function() WD1KIT_UI2.core:prepareItems({id},1) end) end end
        ui:text(root,"These are normal growth rewards, not all Digital Trip skill trees.")
    end)
    if mode=="campaign" then
        local rewards=SH_Menu_RegisterCategory("04 / Local Online-Gated Rewards",menu)
        rewards:Layout(function(root)
            local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
            ui:text(root,"Local item requests do not complete online activity counters.")
            for _,id0 in ipairs({"item_2207476061","item_4099987261","item_770883049","item_309961700","item_678076169"}) do
                local id=id0;ui:button(root,ui.core.entries[id].label.." - prepare",function() WD1KIT_UI2.core:prepareItems({id},1) end)
            end
            ui:button(root,"Prepare all four online-reward weapons",function() WD1KIT_UI2.core:prepareItems({"item_2207476061","item_4099987261","item_770883049","item_309961700"},1) end)
        end)
    end
    local items=SH_Menu_RegisterCategory("05 / Item Whitelist",menu)
    items:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root);ui:confirmButtons(root)
        ui:text(root,"ALL means the current-mode whitelist. No mission tokens, NPC/MP items or unverified full completion.")
        ui:button(root,"[ALL WEAPONS] Prepare weapon candidates",function() WD1KIT_UI2.core:prepareAll("weapons") end)
        ui:button(root,"[ALL CLOTHES] Prepare outfit candidates",function() WD1KIT_UI2.core:prepareAll("clothes") end)
        ui:button(root,"[ALL ITEMS] Prepare current-mode items",function() WD1KIT_UI2.core:prepareAll("items") end)
        ui:widget(root,"item_quantity")
        local groups={{"weapons","Weapons"},{"dlc_weapons","Owned ULC Weapons"},{"bb_weapons","Bad Blood Weapons"},{"supplies","Consumables and Materials"},{"clothes","Aiden Outfits"},{"dlc_clothes","Owned ULC Outfits"},{"trip_clothes","Trip Reward Outfits"},{"bb_clothes","T-Bone Outfits"},{"cars","Delivery Reward Candidates"},{"songs","22 Song Reward Candidates"}}
        for _,g in ipairs(groups) do
            local list={};for _,v in ipairs(ui.catalog) do if v.group==g[1] and (v.mode=="both" or v.mode==ui.mode) then list[#list+1]=v end end
            if #list>0 then
                local ok,err=pcall(function() root:CollapsingHeader(g[2].." ("..#list..")",false,function(h)
                    local u=WD1KIT_UI2
                    u:button(h,"Prepare this group - one of each",function() local ids={};for _,v in ipairs(list) do ids[#ids+1]=v.id end;WD1KIT_UI2.core:prepareItems(ids,1) end)
                    for _,v in ipairs(list) do local id=v.id;local supply=v.group=="supplies";u:button(h,v.label,function() local state=WD1KIT_UI2;state.core:prepareItems({id},supply and state:integer("item_quantity") or 1) end) end
                end) end)
                if not ok then ui.errors[#ui.errors+1]="item_group";ui.core:log("UI2_ERROR","item_group");ui:text(root,"[UI ERROR: item group] Full batch buttons above remain available.") end
            end
        end
    end)
    local world=SH_Menu_RegisterCategory("06 / Vehicles and World",menu)
    world:Layout(function(root)
        local ui=WD1KIT_UI2;ui:header(root)
        ui:text(root,"At most five spawns per session. Spawning is not a persistent delivery unlock.")
        for i,v in ipairs(ui.core.vehicles) do local index=i;ui:button(root,"Spawn "..v.label,function() WD1KIT_UI2.core:spawn(index) end) end
        ui:widget(root,"hour");ui:widget(root,"minute")
        ui:button(root,"Apply Time - restart to release scripted clock",function() local u=WD1KIT_UI2;u.core:setTime(u:integer("hour"),u:integer("minute")) end)
    end)
    c:log("PLUGIN_LOADED","version=0.3.0-ui2 mode="..mode.." game_runtime_verified=false")
    c:log("UI2_READY","legacy="..tostring(type(SH_Menu_AddButton_CB)=="function").." errors="..#U.errors)
    c:probe()
    return true
end
