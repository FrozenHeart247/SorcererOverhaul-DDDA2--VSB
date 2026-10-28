-- Bounded live hook check: one KeepLockOn update, no cast/action/shell or VSB event emitted.
local controller=assert(_G.FH_LevinTargeting,"Load FH_LevinTargeting first")
assert(controller.prepared and not controller.stopped,"Companion not ready")
assert(not controller.active,"Do not probe during a real cast")
local report={version=2,scenario="cold request: Job=0, action=0, skill=0",at=os.date("!%Y-%m-%dT%H:%M:%SZ"),errors={}}
local actor=assert(require("DragonCore.game.runtime").player())
local ctrl=actor.game_object:call("getComponent(System.Type)",sdk.typeof("app.Player")):call("get_LockOnCtrl()")
local cast={entry={pack_id="fh_sorc"},doc={uuid="3c0b8528-94e6-431a-bd46-a2be7e2c6501"},actor=actor,level=1}
local function identity(target) return target and tostring(target:get_address()) or "none" end
local function fields(value,td)
    local result={}
    for _,field in ipairs(td:get_fields()) do
        if not field:is_static() then
            local name=field:get_name()
            local v=value:get_field(name)
            if type(v)=="boolean" or type(v)=="number" or type(v)=="string" then result[name]=v
            elseif name=="<ParameterInfo>k__BackingField" then result[name]=fields(v,controller.request_td)
            else result[name]=tostring(v) end
        end
    end
    return result
end
local ok,err=pcall(function()
    report.stage="allocate_option"
    local option=sdk.create_instance("app.LockOnController.Option"):add_ref()
    option:call(".ctor()")
    report.stage="keep_lock_on"
    option:call("setToKeepLockOn()")
    report.stage="request_info"
    local info=sdk.create_instance("app.LockOnRangeParameter.RequestParameterInfo"):add_ref()
    report.layout={}
    for _,td in ipairs({controller.option_td,controller.request_td}) do
        local row={name=td:get_full_name(),size=td:get_valuetype_size(),is_value_type=td:is_value_type(),fields={}}
        for _,field in ipairs(td:get_fields()) do if not field:is_static() then row.fields[#row.fields+1]={name=field:get_name(),offset=field:get_offset_from_base()} end end
        report.layout[#report.layout+1]=row
    end
    report.stage="request_job"
    info:set_field("<Job>k__BackingField",0)
    report.stage="request_action_type"
    info:set_field("<ActionType>k__BackingField",0)
    report.stage="request_action_id"
    info:set_field("<ActionID>k__BackingField",0)
    report.stage="request_skill_id"
    info:set_field("<CustomSkillID>k__BackingField",0)
    report.stage="request_air"
    info:set_field("<IsUseOnAir>k__BackingField",false)
    report.stage="request_change"
    info:set_field("<IsUseForChangeTarget>k__BackingField",false)
    report.stage="option_parameter"
    option:set_field("<ParameterInfo>k__BackingField",info)
    report.stage="read_option_before"
    report.option_before=fields(option,controller.option_td)
    local list=ctrl:get_field("<ParamList>k__BackingField")
    local initial=list:call("getTypeParameter(app.LockOnRangeParameter.RequestParameterInfo)",info)
    report.initial_profile={skill=initial.CustomSkillID,max_distance=initial.MaxDistance,based_on_camera=initial.IsBasedOnCamera}
    report.stage="target_before"
    report.target_before=identity(ctrl:call("get_Target()"))
    report.stage="start"
    controller:started(cast)
    report.stage="native_update"
    ctrl:call("updateLockOn(app.LockOnController.Option)",option)
    report.stage="validate"
    local record=assert(controller.active,"Hook rejected update; see targeting status")
    report.updates,report.first=record.updates,record.first
    report.option_after=fields(option,controller.option_td)
    report.target_after=identity(ctrl:call("get_Target()"))
    assert(record.updates==1 and record.first,"Native hook did not process the test update")
    assert(record.first.after.CustomSkillID==25,"Levin ID not selected")
    assert(record.first.after.Job==6,"Cold job not initialized to the Levin profile")
    assert(record.first.profile.skill==25 and record.first.profile.based_on_camera,"Native Levin profile not resolved")
    assert(option:get_field("<ParameterInfo>k__BackingField"):get_field("<CustomSkillID>k__BackingField")==0,"Caller's skill changed")
    assert(info:get_field("<Job>k__BackingField")==0,"Caller's job changed")
    assert(report.target_before==report.target_after,"KeepLockOn target changed")
    report.passed=true
end)
controller:ended(cast,"bounded live verification")
if not ok then report.errors[#report.errors+1]=tostring(err) end
report.inactive_after=controller.active==nil
json.dump_file("VSB/diagnostics/levin_targeting_verification.json",report)
log.info("[FH Levin targeting] Live verification "..(report.passed and "passed" or "failed"))
