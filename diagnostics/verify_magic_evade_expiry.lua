-- Run via ScriptRunner while paused, after loading companion version 4.
-- Synchronous native start/check/update/clear; never leaves the probe buff enabled.
local runtime=require("DragonCore.game.runtime")
local native=require("FH_MagicEvade.native")
local report={version=1,generated=os.date("!%Y-%m-%dT%H:%M:%SZ"),errors={}}
local actor=assert(runtime.player())
assert(actor:valid(),"Load a player first")
local manager=actor.human:get_field("SpecialBuffManager")
local active="get_IsActiveJob04AbsoluteAvoidance()"
local token
local ok,err=pcall(function()
    assert(manager:call(active)~=true,"Pre-existing avoidance buff; probe skipped")
    local why
    token,why=native.acquire(actor,1)
    assert(token and not why,tostring(why))
    local buff=manager:get_field("Job04AbsoluteAvoidance")
    report.before_updates=native.describe(token)
    report.owned_timer_over=buff:call("isTimerOver()")
    for _=1,120 do manager:call("update(System.Single)",1/60) end
    report.after_120_updates=native.describe(token)
    local released,detail=native.release(token)
    report.released,report.released_detail=released,detail
    report.original_timer_over_after_release=buff:call("isTimerOver()")
end)
if not ok then report.errors[#report.errors+1]=tostring(err) end
if token and token.owned then
    local worked,failure=pcall(native.release,token)
    if not worked then report.errors[#report.errors+1]="cleanup: "..tostring(failure) end
end
report.active_after_cleanup=manager:call(active)==true
json.dump_file("VSB/diagnostics/magic_evade_expiry_verification.json",report)
