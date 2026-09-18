-- Lua 5.1 fixture tests; zero real game calls. Run from project root.
local factory=dofile('src/Plugin/core.lua')
local catalog=dofile('src/Plugin/catalog.lua')
local passed=0
local function check(ok,name) if not ok then error('FAIL: '..name,2) end; passed=passed+1; print('PASS '..name) end
local function equal(a,b,name) check(a==b,name..' expected='..tostring(b)..' actual='..tostring(a)) end
local function fixture(mode)
 local state={player=42,now=10000,calls={},logs={}}
 local e={os={time=function()return state.now end},SH_LOG=function(x)state.logs[#state.logs+1]=x end,SH_Notifications_PushNotification=function()end,
 GetLocalPlayerEntityId=function()return state.player end,GetInvalidEntityId=function()return 0 end,GetEntityPosition=function(p,axis)return axis*10 end}
 local names={'ActivateInvincibility','RemoveInvincibility','ModifyBulletsInClip','RefillAdrenaline','GiveCash','AddItem','FelonySystemEnable','FelonySetHeat'}
 for _,name0 in ipairs(names) do local name=name0; e[name]=function(...)state.calls[#state.calls+1]={name=name,n=select('#',...),args={...}} end end
 e.SH_Entities_Spawn=function(spec)state.calls[#state.calls+1]={name='spawn',args={spec}};return 123 end
 e.CDynamicEnvironmentManager_GetInstance=function()return {SetScriptedTimeOfDay=function(self,h,m)state.calls[#state.calls+1]={name='time',args={h,m}} end} end
 local r={format=1,product='WD1KIT',mode=mode or 'campaign',allow_persistent=true,backup_id='fixture-only',created_unix=9000,expires_unix=16200}
 local c=factory(e,catalog,r,mode or 'campaign')
 local function count(name)local n=0; for _,call in ipairs(state.calls)do if call.name==name then n=n+1 end end;return n end
 local function tick(n)for i=1,n do c:tick() end end
 return c,e,state,count,tick
end
local point='item_2023158576'
do local c,e,s,count,tick=fixture();tick(20);equal(#s.calls,0,'startup makes no writes');check(not c:prepareItems({point},1),'not armed blocks items');check(not c:toggle('god',true),'not armed blocks god');equal(#s.calls,0,'refused commands make no writes');end
do local c,e,s,count,tick=fixture();s.player=0;check(not c:arm(),'invalid player refuses arm');e.GetInvalidEntityId=nil;s.player=42;check(not c:arm(),'missing invalid-ID getter fails closed');end
do local c,e,s,count,tick=fixture();check(c:arm(),'valid player explicit arm');tick(8);equal(#s.calls,0,'arm alone changes no gameplay');check(c:toggle('god',true),'enable god');tick(1);equal(count('ActivateInvincibility'),1,'god API called');c:toggle('god',false);equal(count('RemoveInvincibility'),1,'god undone');tick(2);equal(count('ActivateInvincibility'),1,'disabled god not reapplied');end
do local c,e,s,count,tick=fixture();c:arm();tick(6);equal(count('RefillAdrenaline'),0,'fix upstream unconditional-focus bug');c:toggle('focus',true);tick(2);equal(count('RefillAdrenaline'),2,'focus only when enabled');c:toggle('focus',false);tick(2);equal(count('RefillAdrenaline'),2,'focus off stays off');end
do local c,e,s,count,tick=fixture();c:arm();c:toggle('ammo',true);tick(1);equal(count('ModifyBulletsInClip'),6,'ammo slots 0 through 5');for i=1,6 do equal(s.calls[i].args[2],i-1,'ammo slot signature '..i);equal(s.calls[i].n,4,'ammo argument count '..i)end;c:stop();tick(2);equal(count('ModifyBulletsInClip'),6,'stop disables ammo');end
do local c,e,s,count,tick=fixture();c:arm();c:toggle('police',true);tick(4);equal(count('FelonySystemEnable'),1,'police disable only once');equal(s.calls[1].args[1],0,'police disable integer');c:pause();equal(s.calls[2].args[1],1,'pause restores police');check(not c.armed,'pause disarms');c:resume();check(not c.armed,'resume requires rearm');end
do local c,e,s,count,tick=fixture();c:arm();check(c:prepareItems({point},1),'stage skill reward');equal(count('AddItem'),0,'prepare is not a write');check(c:confirm(),'explicit confirmation queues');check(not c:confirm(),'second confirmation does not duplicate');tick(4);equal(count('AddItem'),1,'single skill item request');local call=s.calls[1];equal(call.n,2,'WD1 AddItem takes TWO args (not WD2 entity API)');equal(call.args[1],'Items.2023158576','numeric Items DB key (not display name)');equal(call.args[2],1,'skill delta one');check(table.concat(s.logs,'\n'):find('NOT_VERIFIED')~=nil,'does not label request as verified unlock');end
do local c,e,s,count,tick=fixture();c:arm();check(not c:prepareItems({'fake_key'},1),'unknown item rejected');check(not c:prepareItems({point},0),'zero quantity rejected');check(not c:prepareItems({point},101),'large quantity rejected');check(not c:prepareItems({point},1.5),'fraction quantity rejected');check(not c:prepareItems({point,point},1),'duplicate item rejected');check(not c:prepareCash(-1),'negative cash rejected');check(not c:prepareCash(1000001),'cash upper bound');equal(#s.calls,0,'bad input produces zero calls');end
do local c,e,s,count,tick=fixture();c:arm();check(c:prepareCash(1000),'prepare cash');equal(#s.calls,0,'cash staged');c:confirm();tick(4);equal(s.calls[1].name,'GiveCash','cash API name');equal(s.calls[1].n,2,'cash arg count');equal(s.calls[1].args[1],0,'cash index zero');equal(s.calls[1].args[2],1000,'cash amount');end
for _,mutate in ipairs({function(r)r.allow_persistent=false end,function(r)r.format=2 end,function(r)r.mode='dlc_solo' end,function(r)r.backup_id='' end,function(r)r.product='other' end}) do
 local c,e,s,count,tick=fixture();mutate(c.receipt);c:arm();check(not c:prepareItems({point},1),'invalid backup receipt refuses write');equal(#s.calls,0,'invalid receipt no calls')
end
do local c,e,s,count,tick=fixture();e.os=nil;c:arm();check(c:prepareItems({point},1),'no clock still allows persistent writes (0.4.15)');check(c:toggle('god',true),'temporary god independent of receipt');end
do local c,e,s,count,tick=fixture();c:arm();c:prepareItems({point},1);c:confirm();s.now=17000;tick(4);equal(count('AddItem'),1,'0.4.15 window ignored: expired-time queue still executes');check(c.armed,'no time-based disarm');end
do local c,e,s,count,tick=fixture();c:arm();c:prepareItems({point},1);c:cancel();check(not c:confirm(),'cancel clears pending confirmation');tick(8);equal(count('AddItem'),0,'cancel no calls');end
do local c,e,s,count,tick=fixture();c:arm();local ids={'item_2207476061','item_4099987261','item_770883049','item_309961700'};c:prepareItems(ids,1);c:confirm();equal(count('AddItem'),4,'0.4.18: confirm delivers the whole batch inline');c:pause();tick(30);equal(count('AddItem'),4,'pause adds nothing after delivery');check(not c.armed,'pause disarms');c:resume();c:arm();tick(8);equal(count('AddItem'),4,'delivered queue never restarts');end
do local c,e,s,count,tick=fixture();c:arm();c:toggle('god',true);tick(1);s.player=43;tick(1);equal(count('ActivateInvincibility'),1,'silent player change disarms without host event');check(not c.armed,'silent player change stops state');equal(count('RemoveInvincibility'),0,'does not touch stale entity handle');end
do local c,e,s,count,tick=fixture();c:arm();c:prepareItems({point},1);s.player=43;check(not c:confirm(),'entity change immediately before confirm guarded');end
do local c,e,s,count,tick=fixture();c:arm();c:toggle('god',true);tick(1);c:arm();check(not c.flags.god,'rearm resets toggles');end
do local c,e,s,count,tick=fixture();c:arm();e.AddItem=nil;check(not c:prepareItems({point},1),'missing item API rejects');e.ActivateInvincibility=nil;check(not c:toggle('god',true),'missing god API rejects');end
do local c,e,s,count,tick=fixture();c:arm();e.AddItem=function()error('fixture')end;c:prepareItems({point},1);c:confirm();tick(4);check(c.armed,'native exception skips entry, batch continues');equal(c.submitted,0,'failed call not counted submitted');equal(#c.batchFail,1,'call error counted in batchFail');end
do local c,e,s,count,tick=fixture();c:arm();e.AddItem=function()return false end;c:prepareItems({point},1);c:confirm();tick(4);equal(c.submitted,0,'explicit false native result not counted');equal(#c.batchFail,1,'false result counted in batchFail');check(c.armed,'false result does not halt batch');end
do local c,e,s,count,tick=fixture('dlc_solo');c:arm();check(not c:prepareItems({'item_678076169'},1),'campaign-only car grant unavailable in DLC');check(c:prepareItems({point},1),'shared skill reward available in DLC');end
do local c,e,s,count,tick=fixture();c:arm();for i=1,5 do check(c:spawn(1),'bounded vehicle spawn '..i)end;check(not c:spawn(1),'sixth spawn rejected');equal(count('AddItem'),0,'spawn is not an inventory unlock');check(not c:spawn(100),'arbitrary spawn index rejected');end
do local c,e,s,count,tick=fixture();c:arm();check(c:heat(0),'clear heat request');equal(s.calls[1].n,2,'FelonySetHeat two args');check(not c:heat(101),'heat range enforced');check(c:setTime(12,30),'time call');check(not c:setTime(24,0),'hour bounds');check(not c:setTime(12,60),'minute bounds');end
do local c,e,s,count,tick=fixture();e.AddSkillPoints_UNPROVEN=function()error('must never invoke')end;e.password='PRIVATE_TOKEN';e.steam_account='PRIVATE_ACCOUNT';c:probe();equal(#s.calls,0,'capability probe no gameplay writes');local logs=table.concat(s.logs,'\n');check(logs:find('AddSkillPoints_UNPROVEN')~=nil,'probe lists function names without calling');check(not logs:find('PRIVATE_'),'probe does not export globals or account data');end
-- Host adapter mock: persisted command state must not enable anything on load.
do
 local c,e,s,count,tick=fixture();e._G=e;setmetatable(e,{__index=_G});local states,callbacks,scripts={}, {}, {}
 e.SH_Commands_Register=function(id,label,desc,menu,cb)callbacks[id]=cb end
 e.SH_Commands_RegisterCallback=function(id,cb)callbacks[id]=cb end
 e.SH_Commands_RegisterBool=function(id,label,desc,menu,default,cb)states[id]=true;callbacks[id]=cb end
 e.SH_Commands_RegisterInt=function(id,label,desc,menu,default,min,max)states[id]=default end
 e.SH_Commands_GetStateInt=function(id)return states[id]end;e.SH_Commands_GetStateBool=e.SH_Commands_GetStateInt
 e.SH_Commands_SetStateBool=function(id,value)states[id]=value;if callbacks[id]then callbacks[id]()end end
 local root={Text=function()end,CommandWidget=function()end,Divider=function()end,Button=function()end,CollapsingHeader=function(self,title,open,fn)fn(self)end}
 e.SH_Menu_RegisterMenu=function()return{}end;e.SH_Menu_RegisterCategory=function()return{Layout=function(self,fn)fn(root)end}end
 e.Script=function(name)local script={Remove=function(self)if self.OnUnload then self:OnUnload()end end};scripts[name]=script;return script end
 local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,e);check(adapter(c,catalog,'campaign'),'host adapter registers with mock contracts')
 for _,name in ipairs({'god','ammo','focus','police'})do equal(states['wd1kit_campaign_'..name],false,'persisted '..name..' reset')end
 tick(10);equal(#s.calls,0,'menu load no native writes');check(scripts.wd1kit_campaign.OnPause~=nil,'OnPause callback wired');check(scripts.wd1kit_campaign.OnResume~=nil,'OnResume callback wired');scripts.wd1kit_campaign:OnUnload();check(not c.alive,'unload disables old callbacks');callbacks.wd1kit_campaign_arm();check(not c.armed,'old command callback cannot rearm unloaded script')
end
do local c,e,s,count,tick=fixture();c.receipt.allow_persistent=false;c:arm();check(not c:toggle('ammo',true),'ammo needs backup because inventory may persist');tick(4);equal(count('ModifyBulletsInClip'),0,'temporary-only mode does not write ammo');c.receipt.allow_persistent=true;c:toggle('ammo',true);tick(1);s.now=17000;tick(1);equal(count('ModifyBulletsInClip'),12,'0.4.15 window ignored: ammo keeps writing');check(c.armed,'ammo not disarmed by clock');end
-- All inventory requests and continuous/increase controls remain distinct.
do local c,e,s,count,tick=fixture();c:arm();check(c:prepareAll('weapons'),'all weapons creates bounded current-mode batch');check(#c.pending>35,'all weapons includes standard and ULC candidates');equal(count('AddItem'),0,'all weapons waits for explicit confirmation');c:cancel();check(c:prepareAll('clothes'),'all clothes stages independently');check(#c.pending>=60,'all clothes includes shop ULC and trip rewards');c:cancel();check(c:prepareAll('items'),'all safe items stage beyond old 100 row cap');check(#c.pending<=4096,'all items remain bounded for the v0.4 unlock catalog');for _,j in ipairs(c.pending)do check(j.id~='item_2023158576','all items do not silently add skill points')end;c:cancel();check(not c:prepareAll('fake'),'unknown full group rejected');end
do local c,e,s,count,tick=fixture();c:arm();check(c:ammoOnce(),'one-time ammo supply works independently');equal(count('ModifyBulletsInClip'),6,'one-time supplies six known slots');check(not c.flags.ammo,'one-time ammo does not enable infinite');tick(4);equal(count('ModifyBulletsInClip'),6,'one-time ammo not repeated');c:toggle('ammo',true);tick(1);equal(count('ModifyBulletsInClip'),12,'infinite ammo still retained');end
do local c,e,s,count,tick=fixture('dlc_solo');c:arm();check(c:prepareAll('clothes'),'DLC all clothes supported by separate whitelist');equal(#c.pending,11,'DLC batch does not write Aiden clothing');end
print('LUA_FIXTURE_CHECKS='..passed)
