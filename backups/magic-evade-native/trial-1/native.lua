-- Signatures obtained from the user's live TDB 83 metadata report.
local native = {}
local MANAGER = "app.HumanSpecialBuffManager"
local START = "startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)"
local CLEAR = "clearBuff_Job04AbsoluteAvoidance()"
local ACTIVE = "get_IsActiveJob04AbsoluteAvoidance()"

local function manager_for(actor)
    if not actor or not actor:valid() then return nil end
    return actor.human and actor.human:get_field("SpecialBuffManager")
end

function native.supported()
    local td = sdk.find_type_definition(MANAGER)
    if not td then return false, "HumanSpecialBuffManager is unavailable" end
    for _, signature in ipairs({START, CLEAR, ACTIVE}) do
        if not td:get_method(signature) then return false, "Missing native method: " .. signature end
    end
    return true
end

function native.current(token)
    local manager = manager_for(token.actor)
    if not manager or manager:get_address() ~= token.address then return nil, "character or buff manager changed" end
    return manager
end

function native.active(token)
    local manager, why = native.current(token)
    if not manager then return nil, why end
    return manager:call(ACTIVE) == true
end

function native.acquire(actor, level)
    local supported, why = native.supported()
    if not supported then return nil, why end
    local manager = manager_for(actor)
    if not manager then return nil, "player buff manager is unavailable" end
    local token = {actor=actor, address=manager:get_address(), owned=false}
    if manager:call(ACTIVE) == true then return token end -- preserve a pre-existing native buff
    token.owned = true -- retain ownership even if the following call or readback fails
    local ok, err = pcall(function()
        manager:call(START, math.max(1, math.min(2, tonumber(level) or 1)), nil)
        if manager:call(ACTIVE) ~= true then error("native buff did not become active") end
    end)
    if not ok then return token, tostring(err) end
    return token
end

function native.release(token)
    if not token.owned then return true, "pre-existing buff preserved" end
    local manager, why = native.current(token)
    if not manager then token.owned=false; return true, why end -- never touch a previous character
    manager:call(CLEAR)
    if manager:call(ACTIVE) == true then return false, "native buff is still active after clear" end
    token.owned = false
    return true, "native buff inactive", false
end

return native
