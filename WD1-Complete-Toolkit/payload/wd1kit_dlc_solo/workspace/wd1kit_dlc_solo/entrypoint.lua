-- Game-only WD1KIT v0.3. No automatic enable on load.
local mode="dlc_solo"
local folder="wd1kit_dlc_solo/"
if WD1KIT_ACTIVE and WD1KIT_ACTIVE.alive then
 if WD1KIT_ACTIVE.mode==mode then return end
 WD1KIT_ACTIVE:shutdown("MODE_SWITCH_REQUIRES_RESTART")
 if WD1KIT_ACTIVE.script then pcall(function() WD1KIT_ACTIVE.script:Remove() end) end
end
local c=dofile(folder.."core.lua")(_G,dofile(folder.."catalog.lua"),dofile(folder.."receipt.lua"),mode)
WD1KIT_ACTIVE=c
local ok=pcall(function() dofile(folder.."menu.lua")(c,dofile(folder.."catalog.lua"),mode) end)
if not ok then c:shutdown("MENU_INIT_ERROR"); c:message("WD1KIT: menu init failed. No cheats enabled.") end
