-- Signatures obtained from the user's live TDB 83 metadata report.
local native = {}
local MANAGER = "app.HumanSpecialBuffManager"
local START = "startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)"
local CLEAR = "clearBuff_Job04AbsoluteAvoidance()"
local ACTIVE = "get_IsActiveJob04AbsoluteAvoidance()"
local CONTEXT = "app.HumanSkillContext"
local LEVEL = "getCustomSkillLevel(app.HumanCustomSkillID)"
local ENABLED = "isCustomSkillEnable(app.HumanCustomSkillID)"
local REACHED = "isCustomSkillReachLevel(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)"
local leases, hooks_ready = {}, false

local function skill_id()
    local td=sdk.find_type_definition("app.HumanCustomSkillID")
    local field=td and td:get_field("Job04_AbsoluteAvoidance")
    local id=field and field:get_data(nil)
    if type(id)~="number" then error("AbsoluteAvoidance skill ID is unavailable") end
    return id
end

-- Scope read overrides to this native skill and the exact current player's context.
-- No learned-level list, equipment slot or saved context field is written.
local function install_hooks(id)
    if hooks_ready then return end
    local td=sdk.find_type_definition(CONTEXT)
    if not td then error("HumanSkillContext is unavailable") end
    local methods={}
    for _,signature in ipairs({LEVEL,ENABLED,REACHED}) do
        methods[signature]=td:get_method(signature)
        if not methods[signature] then error("Missing native method: "..signature) end
    end
    for _,signature in ipairs({LEVEL,ENABLED,REACHED}) do
        local key="fh_magic_evade_"..signature
        sdk.hook(methods[signature],function(args)
            local storage=thread.get_hook_storage()
            storage[key]=nil
            if (sdk.to_int64(args[3]) & 0xFFFFFFFF)~=id then return end
            local context=sdk.to_managed_object(args[2])
            local token=context and leases[context:get_address()]
            if token and token.owned and token.actor:valid() then
                storage[key]={token=token,required=signature==REACHED and (sdk.to_int64(args[4]) & 0xFFFFFFFF) or nil}
            end
        end,function(retval)
            local storage=thread.get_hook_storage()
            local match=storage[key]
            storage[key]=nil
            if not match or not match.token.owned then return retval end
            local token=match.token
            token.override_queries[signature]=(token.override_queries[signature] or 0)+1
            local effective=math.max(token.original_level,token.level)
            if signature==LEVEL then
                return sdk.to_ptr(math.max(sdk.to_int64(retval) & 0xFFFFFFFF,effective))
            elseif signature==ENABLED then
                return effective>0 and sdk.to_ptr(1) or retval
            end
            return effective>=match.required and sdk.to_ptr(1) or retval
        end)
    end
    hooks_ready=true
end

local function remove_lease(token)
    if token.context_address and leases[token.context_address]==token then leases[token.context_address]=nil end
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
    out.availability_override_queries={}
    for key,value in pairs(token.override_queries or {}) do out.availability_override_queries[key]=value end
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
    local context=actor.human:get_SkillContext()
    if not context then return nil,"player skill context is unavailable" end
    local id=skill_id()
    token.context_address=context:get_address()
    token.original_level=tonumber(context:call(LEVEL,id)) or 0
    token.level=math.max(1,math.min(2,tonumber(level) or 1))
    token.override_queries={}
    install_hooks(id)
    token.owned = true -- retain ownership even if the following call or readback fails
    leases[token.context_address]=token
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
    -- Even a failed cleanup must not leave an availability override after a script reset.
    leases={}
end

return native
