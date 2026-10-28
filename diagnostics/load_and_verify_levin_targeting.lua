-- Hot-load the authored companion without resetting VSB or the editor.
package.preload["FH_LevinTargeting.controller"]=function()
    return dofile("F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun/FH_LevinTargeting/controller.lua")
end
dofile("F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun/FH_LevinTargeting.lua")
local frames=0
re.on_frame(function()
    if frames>=10 then return end
    frames=frames+1
    if frames==10 then dofile("E:/Downloads/Mods/DDDA2/CustomClassAndSkills/SorcererOverhaul(DDDA2)-VSB/diagnostics/verify_levin_targeting.lua") end
end)
