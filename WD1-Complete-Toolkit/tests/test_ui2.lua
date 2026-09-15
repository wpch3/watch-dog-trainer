-- Deferred host-layout tests: do not model all callbacks as immediate successes.
local factory=dofile('src/Plugin/core.lua')
local catalog=dofile('src/Plugin/catalog.lua')
local total=0
local function check(ok,label)if not ok then error('FAIL '..label,2)end;total=total+1 end
local function has(t,s)for _,v in ipairs(t)do if v==s then return true end end;return false end
local function fixture(options)
 options=options or {}
 local states,callbacks,scriptMap,pages,legacy={}, {}, {}, {}, {}
 local nativeCalls,logs={},{}
 local e={os={time=function()return 10000 end},GetLocalPlayerEntityId=function()return 42 end,GetInvalidEntityId=function()return 0 end,
 SH_LOG=function(x)logs[#logs+1]=x end,SH_Notifications_PushNotification=function()end,
 ActivateInvincibility=function(p)nativeCalls[#nativeCalls+1]='god_on' end,
 RemoveInvincibility=function(p)nativeCalls[#nativeCalls+1]='god_off' end}
 e._G=e;setmetatable(e,{__index=_G})
 e.SH_Menu_RegisterMenu=function(name)return{}end
 e.SH_Menu_RegisterCategory=function(title,menu)
  local page={title=title,text={},buttons={},widgets={},order={}}
  pages[title]=page
  function page:Layout(fn)self.layout=fn end -- Deliberately deferred until after the adapter returns.
  return page
 end
 if not options.noLegacy then e.SH_Menu_AddButton_CB=function(label,menu,cat,fn)legacy[label]=fn end end
 e.Script=function(name)local s={Remove=function(self)if self.OnUnload then self:OnUnload()end end};scriptMap[name]=s;return s end
 if not options.noCommands then
  e.SH_Commands_Register=function(id,label,desc,menu,fn)callbacks[id]=fn end
  e.SH_Commands_RegisterCallback=function(id,fn)callbacks[id]=fn end
  e.SH_Commands_RegisterBool=function(id,label,desc,menu,value,fn)states[id]=true;callbacks[id]=fn end
  e.SH_Commands_RegisterInt=function(id,label,desc,menu,value,min,max)states[id]=value end
  e.SH_Commands_GetStateBool=function(id)return states[id]end;e.SH_Commands_GetStateInt=e.SH_Commands_GetStateBool
  e.SH_Commands_SetStateBool=function(id,value)states[id]=value;if callbacks[id]then callbacks[id]()end end
 end
 local c=factory(e,catalog,{allow_persistent=false},'campaign')
 local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,e)
 check(adapter(c,catalog,'campaign'),'adapter loads')
 local function render(page)
  local root={}
  function root:Text(t)check(not t:find('[\128-\255]'),'text ASCII');page.text[#page.text+1]=t end
  function root:Button(label,fn)check(not label:find('[\128-\255]'),'button ASCII');page.buttons[label]=fn;page.order[#page.order+1]=label end
  function root:CommandWidget(id)
   if options.failWidgets then error('fixture: typed widget rejected')end
   if options.rejectDuplicate and options.seen and options.seen[id]then error('fixture: duplicate command widget')end
   options.seen=options.seen or {};options.seen[id]=true;page.widgets[#page.widgets+1]=id
  end
  function root:CollapsingHeader(title,expanded,fn)if options.failGroups then error('fixture: group rejected')end;fn(self)end
  page.layout(root)
 end
 return c,e,pages,legacy,nativeCalls,scriptMap,render,logs
end
local function keyButtons(page)
 check(page.buttons['[ARM] Enable this offline test session']~=nil,'ARM plain button exists')
 check(page.buttons['God Mode ON']~=nil,'God ON plain button exists')
 check(page.buttons['God Mode OFF']~=nil,'God OFF plain button exists')
 check(page.buttons['[STOP] Disable all tool effects']~=nil,'STOP plain button exists')
end
-- Ordinary delayed rendering, after all lexical builder calls have returned.
do
 local c,e,pages,legacy,calls,scripts,render=fixture({rejectDuplicate=true})
 check(c.script==scripts.wd1kit_campaign,'lifecycle registered before deferred GUI')
 local p=pages['02 / Player and Police']
 check(debug.getupvalue(p.layout,1)==nil,'Player layout has no captured builder/upvalue')
 collectgarbage('collect');render(p);keyButtons(p)
 check(has(p.widgets,'wd1kit_campaign_god'),'God checkbox still available')
 check(#calls==0,'menu build and GC do not enable god')
 p.buttons['[ARM] Enable this offline test session']();p.buttons['God Mode ON']();scripts.wd1kit_campaign:OnUpdate()
 check(#calls==1 and calls[1]=='god_on','plain ON reaches guarded core and tick')
 p.buttons['God Mode OFF']();check(calls[2]=='god_off','plain OFF removes god effect')
 check(not c.flags.god,'god flag off')
 check(type(legacy['God Mode ON'])=='function','legacy Quick Controls registered separately')
 for i=1,20 do local k,v=debug.getupvalue(p.buttons['God Mode ON'],i);if not k then break end;check(type(v)~='function' and type(v)~='table' and type(v)~='userdata','button dispatch closure captures only primitive keys')end
 scripts.wd1kit_campaign:OnUnload();p.buttons['God Mode ON']();check(not c.alive and not c.flags.god,'old buttons cannot reactivate unloaded core')
end
-- A rejected typed widget must not leave only a header and STOP.
do
 local c,e,pages,legacy,calls,scripts,render,logs=fixture({failWidgets=true})
 local p=pages['02 / Player and Police'];render(p);keyButtons(p)
 check(p.buttons['Infinite Focus ON']~=nil and p.buttons['[ADD AMMO] Refill ammo once']~=nil,'later controls survive widget failure')
 check(#e.WD1KIT_UI2.errors>=4,'widget failures retained')
 check(table.concat(p.text,'\n'):find('UI ERROR')~=nil,'widget failure is visible instead of silent truncation')
 check(c.alive and c.script~=nil,'optional GUI failure does not destroy fallback lifecycle')
end
-- Quick Controls functions even before any Layout callback executes.
do
 local c,e,pages,legacy,calls,scripts,render=fixture({failWidgets=true,noCommands=true})
 check(#calls==0,'missing command API still starts disabled')
 legacy['[ARM] Offline free-roam test']();legacy['God Mode ON']();scripts.wd1kit_campaign:OnUpdate()
 check(calls[1]=='god_on','legacy fallback independent of command system and layouts')
 legacy['God Mode OFF']();check(calls[2]=='god_off','legacy OFF works')
 check(not c:prepareCash(1000),'fallback preserves backup requirement')
end
-- No legacy API: ordinary layout direct buttons remain usable.
do
 local c,e,pages,legacy,calls,scripts,render=fixture({noLegacy=true,failWidgets=true})
 render(pages['02 / Player and Police']);keyButtons(pages['02 / Player and Police'])
end
-- Full inventory controls remain; failure of a group cannot delete the top-level batch buttons.
do
 local c,e,pages,legacy,calls,scripts,render=fixture({failGroups=true})
 local p=pages['05 / Item Whitelist'];render(p)
 for _,name in ipairs({'[ALL WEAPONS] Prepare weapon candidates','[ALL CLOTHES] Prepare outfit candidates','[ALL ITEMS] Prepare current-mode items'})do check(p.buttons[name]~=nil,'full batch preserved '..name)end
 check(#calls==0,'inventory rendering never grants items')
end
print('UI2_ASSERTIONS='..total)
