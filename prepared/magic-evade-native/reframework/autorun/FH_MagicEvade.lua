-- Companion for fh_sorc Magic Evade; does not modify the VSB or DragonCore modules.
local native=require("FH_MagicEvade.native")
local bridge=require("FH_MagicEvade.bridge")
local OUTPUT="VSB/diagnostics/magic_evade_native_status.json"
local status={version=4,variant="native buff with scoped equipment-expiry bypass",events={}}

local function report(event,detail)
    detail=detail or {}
    detail.event,detail.at=event,os.date("!%Y-%m-%dT%H:%M:%SZ")
    status.events[#status.events+1]=detail
    while #status.events>24 do table.remove(status.events,1) end
    status.last=detail
    pcall(json.dump_file,OUTPUT,status)
    log.info("[FH Magic Evade] "..event..": "..tostring(detail.reason or detail.confirmed or detail.detail))
end

local controller=bridge.new(native,report)
local failed=false
re.on_frame(function()
    if failed then return end
    local ok,err=pcall(function()
        native.prepare()
        local api=rawget(_G,"VSB_API")
        local bus=api and api.app and api.app.bus
        if bus then controller:attach(bus) end
        controller:tick()
    end)
    if not ok then
        failed=true
        pcall(controller.shutdown,controller)
        report("companion_error",{reason=tostring(err)})
    end
end)
re.on_script_reset(function() controller:shutdown() end)
report("loaded",{awaiting_cast=true})
