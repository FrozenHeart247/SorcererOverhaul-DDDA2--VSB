-- Native lock-on initialization missing when VSB bypasses processCustomSkill.
-- Exact signatures and managed field types checked against the live TDB 83 probe.
local module={}
local Controller={}
Controller.__index=Controller
local UUID="3c0b8528-94e6-431a-bd46-a2be7e2c6501"
local OPTION="app.LockOnController.Option"
local REQUEST="app.LockOnRangeParameter.RequestParameterInfo"
local UPDATE="updateLockOn(app.LockOnController.Option)"
local INFO="<ParameterInfo>k__BackingField"
local KEY="fh_levin_targeting_option"
local PROFILE_JOB=6 -- Sorcerer's existing Levin range table; not the character's actual vocation.
local function matches(cast)
    return cast and cast.entry and cast.entry.pack_id=="fh_sorc" and cast.doc and cast.doc.uuid==UUID
end
local function copy_value(source,td)
    -- Both Option and RequestParameterInfo are reference types in DD2.
    local copy=assert(sdk.create_instance(td:get_full_name()),"Cannot allocate targeting copy"):add_ref()
    for _,field in ipairs(td:get_fields()) do
        if not field:is_static() then copy:set_field(field:get_name(),source:get_field(field:get_name())) end
    end
    return copy
end
local function describe_info(info)
    local result={}
    for _,name in ipairs({"Job","ActionType","ActionID","CustomSkillID","IsUseOnAir","IsUseForChangeTarget"}) do
        result[name]=info:get_field("<"..name..">k__BackingField")
    end
    return result
end
function module.new(report)
    return setmetatable({report=report or function() end,unsub={},stopped=false},Controller)
end
function Controller:prepare()
    if self.prepared or self.stopped then return end
    local td=sdk.find_type_definition("app.LockOnController")
    local method=td and td:get_method(UPDATE)
    self.option_td=sdk.find_type_definition(OPTION)
    self.request_td=sdk.find_type_definition(REQUEST)
    local ids=sdk.find_type_definition("app.HumanCustomSkillID")
    local field=ids and ids:get_field("Job03_Levin")
    self.levin_id=field and field:get_data(nil)
    assert(method and self.option_td and self.request_td and type(self.levin_id)=="number","Levin targeting API unavailable")
    assert(not self.option_td:is_value_type() and not self.request_td:is_value_type(),"Unexpected targeting value types")
    sdk.hook(method,function(args)
        local storage=thread.get_hook_storage()
        storage[KEY]=nil
        local record=self.active
        if self.stopped or not record or record.cast.finished then return end
        local ctrl=sdk.to_managed_object(args[2])
        if not ctrl or ctrl:get_address()~=record.address then return end
        local ok,err=pcall(function()
            if not record.actor:valid() then self.active=nil; return end
            -- Copy both managed objects; never write the caller's shared request.
            local incoming=assert(sdk.to_managed_object(args[3]),"Targeting Option unavailable")
            local option=copy_value(incoming,self.option_td)
            local info=copy_value(incoming:get_field(INFO),self.request_td)
            local before=not record.first and describe_info(info) or nil
            -- Before any vanilla spell, the game's shared request can still have Job=0.
            -- A native skill ID alone cannot select Levin from that default job table.
            info:set_field("<Job>k__BackingField",PROFILE_JOB)
            info:set_field("<ActionType>k__BackingField",3) -- CustomSkill
            info:set_field("<ActionID>k__BackingField",0) -- initial Levin profile
            info:set_field("<CustomSkillID>k__BackingField",self.levin_id)
            option:set_field(INFO,info)
            option:set_field("<IsUseLockOnUI>k__BackingField",true)
            if not record.first then
                local list=ctrl:get_field("<ParamList>k__BackingField")
                local param=list:call("getTypeParameter(app.LockOnRangeParameter.RequestParameterInfo)",info)
                record.first={before=before,after=describe_info(info),update_type=option:get_field("UpdateType2"),
                    profile={skill=param.CustomSkillID,action_type=param.ActionType,max_distance=param.MaxDistance,
                        based_on_camera=param.IsBasedOnCamera,lock_on_ui=param.IsUseLockOnUI}}
            end
            record.updates=record.updates+1
            storage[KEY]={option=option,info=info} -- retain both through the original native call
            args[3]=sdk.to_ptr(option)
        end)
        if not ok then
            self.active=nil
            self.report("hook_error",{error=tostring(err)})
        end
    end,function(retval)
        thread.get_hook_storage()[KEY]=nil
        return retval
    end)
    self.prepared=true
    self.report("ready",{native_skill_id=self.levin_id})
end
function Controller:started(cast)
    if self.stopped or not matches(cast) then return end
    if not cast.actor:valid() then return end
    local player=cast.actor.game_object:call("getComponent(System.Type)",sdk.typeof("app.Player"))
    local ctrl=player and player:call("get_LockOnCtrl()")
    assert(ctrl,"Player lock-on controller unavailable")
    self.active={cast=cast,actor=cast.actor,address=ctrl:get_address(),updates=0}
    self.report("start",{level=cast.level})
end
function Controller:ended(cast,reason)
    local record=self.active
    if not record or record.cast~=cast then return end
    self.active=nil
    self.report("stop",{reason=reason,updates=record.updates,first=record.first})
end
function Controller:detach()
    for _,unsubscribe in ipairs(self.unsub) do unsubscribe() end
    self.unsub={}
    if self.active then self:ended(self.active.cast,"detached") end
    self.bus=nil
end
function Controller:attach(bus)
    if self.bus==bus or self.stopped then return end
    self:detach()
    self.bus=bus
    self.unsub={bus:on("cast_start",function(cast) self:started(cast) end),
        bus:on("cast_end",function(cast,reason) self:ended(cast,reason) end)}
end
function Controller:tick()
    local record=self.active
    if record and (record.cast.finished or not record.actor:valid()) then self:ended(record.cast,"cast or character ended") end
end
function Controller:shutdown()
    self:detach()
    self.stopped=true -- installed callbacks become neutral, including a hot reload
end
return module
