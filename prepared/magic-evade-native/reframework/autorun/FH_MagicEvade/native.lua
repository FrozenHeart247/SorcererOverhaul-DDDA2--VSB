-- Signatures obtained from the user's live TDB 83 metadata report.
local native = {}
local MANAGER = "app.HumanSpecialBuffManager"
local START = "startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)"
local CLEAR = "clearBuff_Job04AbsoluteAvoidance()"
local ACTIVE = "get_IsActiveJob04AbsoluteAvoidance()"
local LEVEL = "getCustomSkillLevel(app.HumanCustomSkillID)"
local BUFF = "app.HumanSpecialBuffManager.Job04AbsoluteAvoidanceBuff"
local BASE_BUFF = "app.HumanSpecialBuffManager.CustomSkillBuff"
local leases, hooks_ready = {}, false

local function skill_id()
    local td=sdk.find_type_definition("app.HumanCustomSkillID")
    local field=td and td:get_field("Job04_AbsoluteAvoidance")
    local id=field and field:get_data(nil)
    if type(id)~="number" then error("AbsoluteAvoidance skill ID is unavailable") end
    return id
end

-- Live TDB 83 code: the derived expiry method scans equipped skills for ID 42,
-- returns true if absent, otherwise tail-calls CustomSkillBuff.isTimerOver.
-- Use that same base method only for the buff this companion currently owns.
-- Native duration, parameter checks and updateStamina remain in effect.
local function install_hooks()
    if hooks_ready then return end
    local td=sdk.find_type_definition(BUFF)
    local base=sdk.find_type_definition(BASE_BUFF)
    local method=td and td:get_method("isTimerOver()")
    local base_method=base and base:get_method("isTimerOver()")
    if not method or not base_method then error("AbsoluteAvoidance expiry methods are unavailable") end
    local key="fh_magic_evade_expiry"
    sdk.hook(method,function(args)
        local storage=thread.get_hook_storage()
        storage[key]=nil
        local buff=sdk.to_managed_object(args[2])
        local token=buff and leases[buff:get_address()]
        if token and token.owned and native.current(token) then
            storage[key]={token=token,buff=buff}
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,function(retval)
        local storage=thread.get_hook_storage()
        local match=storage[key]
        storage[key]=nil
        if not match then return retval end
        local token=match.token
        local ok,expired=pcall(base_method.call,base_method,match.buff)
        token.expiry_checks=token.expiry_checks+1
        token.last_base_expired=not ok or expired==true
        if not ok then token.expiry_error=tostring(expired) end
        return sdk.to_ptr(token.last_base_expired and 1 or 0)
    end)
    hooks_ready=true
end

local function remove_lease(token)
    if token.buff_address and leases[token.buff_address]==token then leases[token.buff_address]=nil end
end

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

function native.prepare()
    -- REFramework commits newly registered hooks after the current Lua callback.
    -- Register before the player's first cast, rather than inside that cast.
    if hooks_ready then return end
    local supported,why=native.supported()
    if not supported then error(why) end
    install_hooks()
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

-- Read-only evidence taken before cleanup, to distinguish animation resets from native expiry.
function native.describe(token)
    local out={}
    local function read(key,fn)
        local ok,value=pcall(fn)
        if ok then out[key]=value else out[key.."_error"]=tostring(value) end
    end
    local manager,why=native.current(token)
    if not manager then return {unavailable=why} end
    read("active",function() return manager:call(ACTIVE)==true end)
    read("full_action",function() return token.actor:current_action(0) end)
    read("upper_action",function() return token.actor:current_action(1) end)
    read("stamina",function() return token.actor:stamina() end)
    local buff=manager:get_field("Job04AbsoluteAvoidance")
    if buff then
        read("timer",function() return buff:call("get_SecTimer()") end)
        read("parameter_present",function() return buff:call("get_Param()")~=nil end)
    end
    read("context_timer",function()
        local context=token.actor.human:get_field("SpecialBuffContext")
        return context and context:get_field("Job04AbsoluteAvoidanceTimer")
    end)
    read("native_skill_level",function()
        local td=sdk.find_type_definition("app.HumanCustomSkillID")
        local field=td and td:get_field("Job04_AbsoluteAvoidance")
        if not field then return nil end
        local id=field:get_data(nil)
        local context=token.actor.human:get_SkillContext()
        return context and context:call("getCustomSkillLevel(app.HumanCustomSkillID)",id)
    end)
    out.native_skill_level_original=token.original_level
    out.adapter_version=4
    out.expiry_checks=token.expiry_checks
    out.last_base_expired=token.last_base_expired
    out.expiry_error=token.expiry_error
    read("job04_controller",function()
        local info={methods={},fields={},values={}}
        local td=sdk.find_type_definition("app.Job04ActionController")
        if not td then return {unavailable=true} end
        local controller=token.actor.human:call("get_Job04ActionCtrl()")
        info.present=controller~=nil
        for _,field in ipairs(td:get_fields() or {}) do
            local name=field:get_name()
            local ft=field:get_type():get_full_name()
            info.fields[#info.fields+1]=name.." : "..ft
            if controller and name:lower():find("avoid",1,true) and
                (ft=="System.Boolean" or ft=="System.Int32" or ft=="System.Single") then
                local ok,value=pcall(controller.get_field,controller,name)
                if ok then info.values[name]=value end
            end
        end
        for _,method in ipairs(td:get_methods() or {}) do
            local name=method:get_name()
            if name:lower():find("avoid",1,true) then
                local params={}
                for _,pt in ipairs(method:get_param_types() or {}) do params[#params+1]=pt:get_full_name() end
                info.methods[#info.methods+1]=name.."("..table.concat(params,", ")..") -> "..method:get_return_type():get_full_name()
            end
        end
        return info
    end)
    return out
end

function native.acquire(actor, level)
    local supported, why = native.supported()
    if not supported then return nil, why end
    local manager = manager_for(actor)
    if not manager then return nil, "player buff manager is unavailable" end
    local token = {actor=actor, address=manager:get_address(), owned=false}
    if manager:call(ACTIVE) == true then return token end -- preserve a pre-existing native buff
    local buff=manager:get_field("Job04AbsoluteAvoidance")
    if not buff then return nil,"player avoidance buff is unavailable" end
    token.buff_address=buff:get_address()
    local context=actor.human:get_SkillContext()
    token.original_level=context and tonumber(context:call(LEVEL,skill_id())) or nil
    token.level=math.max(1,math.min(2,tonumber(level) or 1))
    token.expiry_checks=0
    native.prepare()
    token.owned = true -- retain ownership even if the following call or readback fails
    leases[token.buff_address]=token
    local ok, err = pcall(function()
        manager:call(START,token.level,nil)
        if manager:call(ACTIVE) ~= true then error("native buff did not become active") end
    end)
    if not ok then return token, tostring(err) end
    return token
end

function native.release(token)
    if not token.owned then return true, "pre-existing buff preserved" end
    local manager, why = native.current(token)
    if not manager then
        remove_lease(token)
        token.owned=false
        return true,why
    end -- never touch a previous character
    manager:call(CLEAR)
    if manager:call(ACTIVE) == true then return false, "native buff is still active after clear" end
    remove_lease(token)
    token.owned = false
    return true, "native buff inactive", false
end

function native.shutdown()
    -- Stop bypassing the equipment check even if native cleanup failed.
    leases={}
end

return native
