-- Lightning Strike/Burst targeting companion. Does not edit VSB, DragonCore or skill JSON.
local previous=rawget(_G,"FH_LevinTargeting")
if previous then previous:shutdown() end
package.loaded["FH_LevinTargeting.controller"]=nil
local core=require("FH_LevinTargeting.controller")
local status={version=3,events={}}
local function report(event,detail)
    detail=detail or {}
    detail.event,detail.at=event,os.date("!%Y-%m-%dT%H:%M:%SZ")
    status.events[#status.events+1]=detail
    while #status.events>20 do table.remove(status.events,1) end
    status.last=detail
    pcall(json.dump_file,"VSB/diagnostics/levin_targeting_status.json",status)
    log.info("[FH Levin targeting] "..event)
end
local controller=core.new(report)
_G.FH_LevinTargeting=controller
re.on_frame(function()
    if controller.stopped then return end
    local ok,err=pcall(function()
        controller:prepare() -- install before the first cast; hooks are committed after this callback
        local api=rawget(_G,"VSB_API")
        local bus=api and api.app and api.app.bus
        if bus then controller:attach(bus) end
        controller:tick()
    end)
    if not ok then controller:shutdown(); report("error",{error=tostring(err)}) end
end)
re.on_script_reset(function() controller:shutdown() end)
report("loaded")
