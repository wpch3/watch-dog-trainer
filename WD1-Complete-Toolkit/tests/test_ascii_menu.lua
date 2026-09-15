-- UI text only. All menu/notification strings must be ASCII; no real host/game calls.
local passed=0
local function check(ok,name)if not ok then error('FAIL '..name,2)end;passed=passed+1 end
local function ascii(s)check(type(s)=='string' and not s:find('[\128-\255]'),'ASCII UI string')end
local original=dofile('locales/zh-CN/Plugin/catalog.lua')
local catalog=dofile('src/Plugin/catalog.lua')
check(#original==#catalog,'same item count')
for i,v in ipairs(catalog)do
 for _,key in ipairs({'id','key','name','group','mode'})do check(v[key]==original[i][key],'unchanged catalog field '..key)end
 ascii(v.label)
end
for _,mode in ipairs({'campaign','dlc_solo'})do
 local states,callbacks,scripts,labels={}, {}, {}, {}
 local calls=0
 local env={os={time=function()return 10000 end},GetLocalPlayerEntityId=function()return 42 end,GetInvalidEntityId=function()return 0 end,
  SH_LOG=function(s)ascii(s)end,SH_Notifications_PushNotification=function(s)ascii(s)end,
  ActivateInvincibility=function()calls=calls+1 end,RemoveInvincibility=function()calls=calls+1 end}
 env._G=env;setmetatable(env,{__index=_G})
 env.SH_Commands_Register=function(id,label,desc,menu,cb)ascii(id);ascii(label);ascii(desc);labels[id]=label;callbacks[id]=cb end
 env.SH_Commands_RegisterCallback=function(id,cb)callbacks[id]=cb end
 env.SH_Commands_RegisterBool=function(id,label,desc,menu,default,cb)ascii(label);ascii(desc);states[id]=default;labels[id]=label;callbacks[id]=cb end
 env.SH_Commands_RegisterInt=function(id,label,desc,menu,default,min,max)ascii(label);ascii(desc);states[id]=default end
 env.SH_Commands_GetStateInt=function(id)return states[id]end;env.SH_Commands_GetStateBool=env.SH_Commands_GetStateInt
 env.SH_Commands_SetStateBool=function(id,v)states[id]=v;if callbacks[id]then callbacks[id]()end end
 env.SH_Menu_RegisterMenu=function(title)ascii(title);return{}end
 local root={Text=function(self,t)ascii(t)end,CommandWidget=function(self,id)ascii(id)end,Divider=function()end,Button=function(self,label,fn)ascii(label)end,CollapsingHeader=function(self,title,open,fn)ascii(title);fn(self)end}
 env.SH_Menu_RegisterCategory=function(title,m)ascii(title);return{Layout=function(self,fn)fn(root)end}end
 env.Script=function(name)local script={Remove=function(self)if self.OnUnload then self:OnUnload()end end};scripts[name]=script;return script end
 local create=dofile('src/Plugin/core.lua');local c=create(env,catalog,{format=1,product='WD1KIT',mode=mode,allow_persistent=false},mode)
 local adapter=dofile('src/Plugin/menu.lua');setfenv(adapter,env);check(adapter(c,catalog,mode),'menu registers')
 local prefix='wd1kit_'..mode..'_'
 check(labels[prefix..'god']=='God Mode','God Mode label')
 check(labels[prefix..'arm']=='[ARM] I am offline and in single-player free roam','ARM translation')
 check(calls==0,'load has no native effects')
 callbacks[prefix..'arm']();states[prefix..'god']=true;callbacks[prefix..'god']();c:tick();check(calls==1,'same god callback works')
 callbacks[prefix..'stop']();check(not c.flags.god,'STOP unchanged')
 check(not c:prepareCash(1000),'backup guard not weakened by localization')
end
print('ASCII_MENU_ASSERTIONS='..passed)
