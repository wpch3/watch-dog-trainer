-- Host-bound callbacks must work without ANY captured upvalues, not merely function upvalues.
local create=dofile('src/Plugin/core.lua')
local catalog=dofile('src/Plugin/catalog.lua')
local checks=0
local function check(ok,label) if not ok then error('FAIL '..label,2) end;checks=checks+1 end
local function fixture(mode)
 local e={};e._G=e;setmetatable(e,{__index=_G})
 local pages,legacy,commands,states,scripts,logs,notifications,calls={},{},{},{},{},{},{},{}
 e.GetLocalPlayerEntityId=function()return 42 end;e.GetInvalidEntityId=function()return 0 end
 e.ActivateInvincibility=function()calls[#calls+1]='god_on' end;e.RemoveInvincibility=function()calls[#calls+1]='god_off' end
 e.SH_LOG=function(msg)logs[#logs+1]=msg end;e.SH_Notifications_PushNotification=function(msg)notifications[#notifications+1]=msg end
 e.SH_Menu_RegisterMenu=function()return{}end
 e.SH_Menu_RegisterCategory=function(title)local page={title=title};pages[title]=page;function page:Layout(fn)self.fn=fn end;return page end
 e.SH_Menu_AddButton_CB=function(label,menu,cat,fn)legacy[label]=fn end
 e.SH_Commands_Register=function(id,label,desc,menu,fn)commands[id]=fn end
 e.SH_Commands_RegisterCallback=function(id,fn)commands[id]=fn end
 e.SH_Commands_RegisterBool=function(id,label,desc,menu,value,fn)states[id]=true;commands[id]=fn end
 e.SH_Commands_RegisterInt=function(id,label,desc,menu,value)states[id]=value end
 e.SH_Commands_GetStateBool=function(id)return states[id]end;e.SH_Commands_GetStateInt=e.SH_Commands_GetStateBool
 e.SH_Commands_SetStateBool=function(id,v)states[id]=v;if commands[id]then commands[id]()end end
 e.Script=function(name)local s={};scripts[name]=s;function s:Remove()if self.OnUnload then self:OnUnload()end end;return s end
 local c=create(e,catalog,{allow_persistent=false},mode)
 local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,e);check(adapter(c,catalog,mode),'UI3 adapter loads')
 local function render(page)
  page.buttons={};page.text={}
  local root={}
  function root:Text(t)page.text[#page.text+1]=t end
  function root:Button(label,fn)page.buttons[label]=fn end
  function root:CommandWidget()end
  function root:CollapsingHeader(_,__,fn)fn(self)end
  function root:Rerender()page.text={};page.fn(self)end
  page.fn(root);return root
 end
 return c,e,pages,legacy,commands,scripts,logs,notifications,calls,render
end
for _,mode in ipairs({'campaign','dlc_solo'}) do
 local c,e,pages,legacy,commands,scripts,logs,notifications,calls,render=fixture(mode)
 local page=pages['02 / Player and Police'];render(page)
 for label,fn in pairs(page.buttons)do check(debug.getupvalue(fn,1)==nil,'button has zero upvalues: '..label)end
 for label,fn in pairs(legacy)do check(debug.getupvalue(fn,1)==nil,'legacy callback has zero upvalues: '..label)end
 for id,fn in pairs(commands)do check(debug.getupvalue(fn,1)==nil,'command callback has zero upvalues: '..id)end
 local script=scripts['wd1kit_'..mode]
 for _,field in ipairs({'OnLoad','OnUpdate','OnPause','OnResume','OnPlayerEntityChange','OnUnload'})do check(debug.getupvalue(script[field],1)==nil,'lifecycle callback has zero upvalues: '..field)end
 check(#calls==0,'menu registration invokes no game changes')
 script:OnLoad();script:OnUpdate();check(e.WD1KIT_UI2.loads==1 and e.WD1KIT_UI2.updates==1,'lifecycle counters advance while effects off')
 local before=e.WD1KIT_UI2.clicks
 page.buttons['[PING] Test this button - no game changes']()
 check(e.WD1KIT_UI2.clicks>before and #calls==0,'PING records callback without game writes')
 check(table.concat(logs,'\n'):find('UI4_ENTER')~=nil and table.concat(logs,'\n'):find('UI4_ACK')~=nil,'event entry and completion visible in logs')
 check(table.concat(page.text,'\n'):find('Clicks=')~=nil,'status displayed inside panel')
 page.buttons['[ARM] Enable this offline test session']();page.buttons['God Mode ON']();script:OnUpdate()
 check(c.armed and c.flags.god and calls[#calls]=='god_on','ARM/God/OnUpdate reach original guarded native call')
 page.buttons['God Mode OFF']();check(calls[#calls]=='god_off','OFF restores original game effect')
 script:OnPause();check(c.paused and not c.armed,'pause guard retained')
 script:OnResume();check(not c.paused and not c.armed,'resume does not auto-enable cheats')
 script:OnUnload();local n=e.WD1KIT_UI2.clicks;legacy['[STATUS] Show armed / god / script']()
 check(e.WD1KIT_UI2.clicks>n,'STATUS not silently discarded when core is dead')
 check(table.concat(logs,'\n'):find('alive=false')~=nil,'dead core is explicit in status')
 local registry=e.WD1KIT_UI4_REGISTRY;e.WD1KIT_UI4_REGISTRY=nil;legacy['[PING] Test callback only']()
 check(table.concat(logs,'\n'):find('STATE_MISSING')~=nil,'missing callback-context state yields explicit error')
 e.WD1KIT_UI4_REGISTRY=registry;local dispatch=e.WD1KIT_UI4_DISPATCH;e.WD1KIT_UI4_DISPATCH=nil;legacy['[PING] Test callback only']()
 check(table.concat(logs,'\n'):find("UI4_DISPATCH_MISSING")~=nil,'missing global dispatcher yields direct host log')
 e.WD1KIT_UI4_DISPATCH=dispatch
end
print('UI4_ASSERTIONS='..checks)
