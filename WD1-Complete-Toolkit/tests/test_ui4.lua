-- UI4 contracts: hot-reload rebinding, poll fallback, momentary actions, full unlock categories.
local factory=dofile('src/Plugin/core.lua')
local catalog=dofile('src/Plugin/catalog.lua')
local checks=0
local function check(ok,label) if not ok then error('FAIL '..label,2) end;checks=checks+1 end

-- Shared fixture. options.duplicateRegister makes SH_Commands_Register* throw, which is
-- what a persisted command table across restarts can do; the UI must still rebind callbacks.
local function fixture(options)
  options=options or {}
  local e={os={time=function()return 10000 end}};e._G=e;setmetatable(e,{__index=_G})
  local pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds={},{},{},{},{},{},{},{},0
  e.GetLocalPlayerEntityId=function()return 42 end;e.GetInvalidEntityId=function()return 0 end
  e.ActivateInvincibility=function()calls[#calls+1]='god_on' end;e.RemoveInvincibility=function()calls[#calls+1]='god_off' end
  e.AddItem=function()return true end;e.GiveCash=function()return true end
  e.SH_LOG=function(msg)logs[#logs+1]=msg end;e.SH_Notifications_PushNotification=function(msg)notifications[#notifications+1]=msg end
  e.SH_Menu_RegisterMenu=function(title)return{title=title}end
  e.SH_Menu_RegisterCategory=function(title)local page={title=title};pages[title]=page;function page:Layout(fn)self.fn=fn end;return page end
  e.SH_Menu_AddButton_CB=function(label,menu,cat,fn)legacy[label]=fn end
  local function refuse() if options.duplicateRegister then error('command already registered') end end
  e.SH_Commands_RegisterBool=function(id,label,desc,menu,value,fn)refuse();states[id]=true;commands[id]=fn end
  e.SH_Commands_RegisterInt=function(id,label,desc,menu,value)refuse();states[id]=value end
  e.SH_Commands_RegisterCallback=function(id,fn)rebinds=rebinds+1;commands[id]=fn end
  e.SH_Commands_GetStateBool=function(id)return states[id]end;e.SH_Commands_GetStateInt=e.SH_Commands_GetStateBool
  e.SH_Commands_SetStateBool=function(id,v)states[id]=v end
  e.Script=function(name)local s={};scripts[name]=s;function s:Remove()if self.OnUnload then self:OnUnload()end end;return s end
  local receipt={format=1,product='WD1KIT',mode=options.mode or 'campaign',allow_persistent=true,backup_id='fixture',created_unix=9000,expires_unix=16200}
  local c=factory(e,catalog,receipt,options.mode or 'campaign')
  local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,e)
  check(adapter(c,catalog,options.mode or 'campaign'),'UI4 adapter loads ('..tostring(options.duplicateRegister)..')')
  local function render(page)
    page.buttons={};page.text={};page.widgets={}
    local root={}
    function root:Text(t)page.text[#page.text+1]=t end
    function root:Button(label,fn)page.buttons[label]=fn end
    function root:CommandWidget(id)page.widgets[#page.widgets+1]=id end
    function root:CollapsingHeader(_,__,fn)fn(self)end
    function root:Rerender()page.text={};page.fn(self)end
    page.fn(root);return page
  end
  return c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render
end

local prefix='wd1kit_campaign_'

-- 1) Menu identity and categories.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture()
  check(e.WD1KIT_UI4 and e.WD1KIT_UI4==e.WD1KIT_UI2,'UI4 global state aliases UI2 for older diagnostics')
  check(pages['07 / Progression Rewards']~=nil,'progression rewards category exists')
  check(pages['08 / Mission Tokens (advanced)']~=nil,'mission token category exists')
  local r=render(pages['01 / Safety and Report'])
  check(table.concat(r.text,' '):find('Polls=')~=nil,'poll counter visible in panel')
  check(r.buttons['[PING] Test this button - no game changes']~=nil,'PING available')
  local p2=render(pages['02 / Player and Police'])
  check(p2.buttons['God Mode ON']~=nil and p2.widgets[#p2.widgets]~=nil,'player page renders')
end

-- 2) Callbacks are ALWAYS rebound, even when host refuses duplicate registration.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture({duplicateRegister=true})
  check(rebinds==9,'unconditional SH_Commands_RegisterCallback after failed registration: '..rebinds)
  check(commands[prefix..'arm']~=nil and commands[prefix..'god']~=nil,'callbacks bound despite refused registration')
  states[prefix..'arm']=true;commands[prefix..'arm']()
  check(c.armed,'moment callback arms through rebind path')
end

-- 3) Dead callbacks: poll must fully drive continuous effects from checkbox state alone.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture()
  for k in pairs(commands) do commands[k]=nil end -- simulate a host that never invokes callbacks
  local script=scripts.wd1kit_campaign
  script:OnLoad();script:OnUpdate()
  states[prefix..'arm']=true;script:OnUpdate()           -- tick ARM checkbox
  check(c.armed,'ARM works via poll with zero working callbacks')
  check(states[prefix..'arm']==false,'momentary ARM checkbox auto-resets')
  states[prefix..'god']=true;script:OnUpdate()           -- tick God checkbox
  check(c.flags.god,'God flag set via poll with zero working callbacks')
  script:OnUpdate()                                      -- next tick applies the game call
  check(calls[#calls]=='god_on','God Mode applies via poll with zero working callbacks')
  script:OnUpdate();script:OnUpdate()
  check(#calls>=2,'continuous god reapplies every update like the official trainer')
  states[prefix..'god']=false;script:OnUpdate()
  check(calls[#calls]=='god_off' and not c.flags.god,'untick disables god via poll')
  states[prefix..'stop']=true;script:OnUpdate()
  check(not c.armed,'STOP moment resets armed state via poll')
  check(table.concat(logs,' '):find('UI4_ENTER')~=nil,'poll executions are logged with UI4_ENTER')
end

-- 4) Callback and poll on the same edge must execute exactly once.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture()
  local script=scripts.wd1kit_campaign;script:OnLoad();script:OnUpdate()
  states[prefix..'arm']=true
  commands[prefix..'arm']()                              -- host delivers the callback...
  script:OnUpdate()                                      -- ...and the poller sees the same tick
  check(c.armed,'armed once')
  local before=logs and #logs or 0
  script:OnUpdate()
  check(c.armed,'no double execution from poll after callback consumed the edge')
  local enters=0;for _,l in ipairs(logs) do if l:find('UI4_ENTER',1,true) then enters=enters+1 end end
  check(enters==1,'exactly one dispatch for one user action: '..enters)
end

-- 5) Progression reward batches: notoriety included, growth-free ALL ITEMS preserved.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture()
  c:arm()
  check(c:prepareAll('progression'),'progression batch prepares')
  local groupsSeen={}
  for _,j in ipairs(c.pending) do groupsSeen[c.entries[j.id].group]=true end
  check(groupsSeen['notoriety'],'notoriety and online rewards inside progression batch')
  check(groupsSeen['mission_xp_main'] and groupsSeen['mission_xp_side'] and groupsSeen['mission_xp_family'],'mission XP rewards inside progression batch')
  check(groupsSeen['ctos_rewards'] and groupsSeen['activity_rewards'],'ctOS and mini-game rewards inside progression batch')
  check(groupsSeen['skill'],'skill point rewards inside progression batch')
  c:cancel()
  check(c:prepareGroup('cars',1),'per-group car unlock batch prepares')
  check(#c.pending==74,'full Car On Demand reward group: '..#c.pending)
  c:cancel()
  check(c:prepareAll('items'),'large ALL ITEMS batch prepares')
  for _,j in ipairs(c.pending) do
    local g=c.entries[j.id].group
    check(g~='skill' and g~='mission_tokens','ALL ITEMS stays growth-free and token-free')
  end
  c:cancel()
end

-- 6) Menu still loads when the sandbox has no loadstring (closure fallback, never fatal).
do
  local e={os={time=function()return 10000 end}};e._G=e;setmetatable(e,{__index=_G})
  local pages,commands,states,scripts,logs,calls,rebinds={},{},{},{},{},{},0
  e.GetLocalPlayerEntityId=function()return 42 end;e.GetInvalidEntityId=function()return 0 end
  e.ActivateInvincibility=function()calls[#calls+1]='god_on' end;e.RemoveInvincibility=function()calls[#calls+1]='god_off' end
  e.AddItem=function()return true end;e.GiveCash=function()return true end
  e.SH_LOG=function(msg)logs[#logs+1]=msg end;e.SH_Notifications_PushNotification=function()end
  e.SH_Menu_RegisterMenu=function()return{}end
  e.SH_Menu_RegisterCategory=function(title)local page={title=title};pages[title]=page;function page:Layout(fn)self.fn=fn end;return page end
  e.SH_Menu_AddButton_CB=function()end
  e.SH_Commands_RegisterBool=function(id,label,desc,menu,value,fn)states[id]=value;commands[id]=fn end
  e.SH_Commands_RegisterInt=function(id,label,desc,menu,value)states[id]=value end
  e.SH_Commands_RegisterCallback=function(id,fn)rebinds=rebinds+1;commands[id]=fn end
  e.SH_Commands_GetStateBool=function(id)return states[id]end;e.SH_Commands_GetStateInt=e.SH_Commands_GetStateBool
  e.SH_Commands_SetStateBool=function(id,v)states[id]=v end
  e.Script=function(name)local s={};scripts[name]=s;return s end
  e.loadstring=false -- sandbox without a usable loadstring
  local c=factory(e,catalog,{format=1,product='WD1KIT',mode='campaign',allow_persistent=false},'campaign')
  local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,e)
  check(adapter(c,catalog,'campaign'),'adapter survives missing loadstring')
  check(table.concat(logs,' '):find('UI4_THUNK_FALLBACK')~=nil,'fallback is logged, not fatal')
  local script=scripts.wd1kit_campaign;script:OnLoad();script:OnUpdate()
  states[prefix..'arm']=true;commands[prefix..'arm']()
  states[prefix..'god']=true;commands[prefix..'god']()
  check(c.armed,'closure fallback still arms via the dispatcher')
  check(c.flags.god,'closure fallback still toggles god')
  check(e.WD1KIT_UI4.clicks>=1,'fallback closures route through the dispatcher')
end

-- 7) DLC isolation on the expanded catalog.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture({mode='dlc_solo'})
  c:arm()
  check(c:prepareAll('clothes'),'DLC clothes batch prepares')
  check(#c.pending==11,'DLC clothes stay T-Bone only: '..#c.pending)
  c:cancel()
  local bb=0
  for _,v in ipairs(catalog) do
    if v.label:find('dlc01',1,true) or v.label:find('Bad Blood',1,true) or v.group=='bb_items' then
      check(v.mode=='dlc_solo','DLC item is DLC-only: '..v.label)
      bb=bb+1
    end
  end
  check(bb>=20,'dlc01 items present and isolated: '..bb)
end

-- 8) Refusals explain what to do next; STATUS/PING carry counters through notifications.
do
  local c,e,pages,legacy,commands,states,scripts,logs,notifications,calls,rebinds,render=fixture()
  c.alive=true;c.armed=false
  states[prefix..'god']=true;commands[prefix..'god']() -- not armed: refused with a hint
  local joined=table.concat(notifications,' ')
  check(joined:find('NOT_ARMED',1,true)~=nil and joined:find('the [ARM] checkbox',1,true)~=nil,'NOT_ARMED refusal tells the user to tick [ARM]: '..joined)
  c.receipt.allow_persistent=false;check(c:arm(),'rearm for receipt check')
  c:prepareItems({'item_2023158576'},1)
  joined=table.concat(notifications,' ')
  check(joined:find('BACKUP_TICKET_INVALID',1,true)~=nil and joined:find('game mode',1,true)~=nil,'missing receipt refusal names the offline remedy')
  local s=e.WD1KIT_UI4_REGISTRY and e.WD1KIT_UI4_REGISTRY.campaign
  if s then s:state() end
  joined=table.concat(notifications,' ')
  check(joined:find('polls=',1,true)~=nil,'STATUS notification carries click/poll counters')
end

print('UI4_ASSERTIONS='..checks)
