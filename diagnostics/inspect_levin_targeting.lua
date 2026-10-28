-- Manual read-only ScriptRunner probe: no actions, shells, target writes or saved-data changes.
local runtime=require("DragonCore.game.runtime")
local actor=assert(runtime.player(),"Load a player first")
assert(actor:valid(),"Player unavailable")
local report={version=1,generated=os.date("!%Y-%m-%dT%H:%M:%SZ"),types={},errors={}}
local function read(key,fn)
    local ok,value=pcall(fn)
    if ok then report[key]=value else report.errors[#report.errors+1]=key..": "..tostring(value) end
end
local function plain(obj,depth)
    if obj==nil then return nil end
    if type(obj)=="number" or type(obj)=="boolean" or type(obj)=="string" then return obj end
    local out={fields={}}
    local td=obj:get_type_definition()
    out.type=td:get_full_name()
    for _=1,6 do
        if not td then break end
        for _,field in ipairs(td:get_fields() or {}) do
            if not field:is_static() then
                local name=field:get_name()
                local ok,value=pcall(obj.get_field,obj,name)
                if ok and value~=nil then
                    local ft=field:get_type():get_full_name()
                    if type(value)=="number" or type(value)=="boolean" or type(value)=="string" then out.fields[name]=value
                    elseif depth>0 and (ft:find("Option",1,true) or ft:find("Nullable",1,true) or ft:find("RequestParameterInfo",1,true)) then
                        local worked,child=pcall(plain,value,depth-1)
                        out.fields[name]=worked and child or tostring(child)
                    else out.fields[name]={type=ft} end
                end
            end
        end
        td=td:get_parent_type()
    end
    return out
end
local function metadata(name)
    local td=sdk.find_type_definition(name)
    if not td then return {missing=true} end
    local out={fields={},methods={}}
    pcall(function() out.size=td:get_valuetype_size() end)
    for _,field in ipairs(td:get_fields() or {}) do
        local entry={name=field:get_name(),type=field:get_type():get_full_name()}
        if field:is_static() then
            local ok,value=pcall(field.get_data,field,nil)
            if ok and (type(value)=="number" or type(value)=="boolean" or type(value)=="string") then entry.value=value end
        end
        out.fields[#out.fields+1]=entry
    end
    for _,method in ipairs(td:get_methods() or {}) do
        local params={}
        for _,pt in ipairs(method:get_param_types() or {}) do params[#params+1]=pt:get_full_name() end
        out.methods[#out.methods+1]={signature=method:get_name().."("..table.concat(params,", ")..")",
            returns=method:get_return_type():get_full_name(),parameters=method:get_param_names()}
    end
    return out
end
for _,name in ipairs({"app.LockOnController","app.LockOnController.Option","app.LockOnRangeParameter",
    "app.LockOnRangeParameter.RequestParameterInfo","app.LockOnRangeParameterList","app.PlayerInputProcessorDetail",
    "app.LockOnRangeParameter.ActionTypeEnum","app.JobMagicUserInputProcessor","app.HumanReadySpell",
    "app.JobMagicUserActionContext"}) do
    read("metadata_"..name,function() report.types[name]=metadata(name); return true end)
end
read("levin_ids",function()
    local out={}
    for _,field in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if field:is_static() and field:get_name():lower():find("levin",1,true) then out[field:get_name()]=field:get_data(nil) end
    end
    return out
end)
local player=actor.game_object:call("getComponent(System.Type)",sdk.typeof("app.Player"))
local ctrl=player:call("get_LockOnCtrl()")
read("controller",function() return plain(ctrl,2) end)
read("range_parameters",function()
    local out={}
    local params=ctrl:get_field("<ParamList>k__BackingField").Parameters
    for i=0,params:get_size()-1 do
        local p=params[i]
        if p and (p.Job==3 or p.Job==6) then
            local row={job=p.Job,parameters={}}
            for j=0,p.Parameters:get_size()-1 do
                local sub=p.Parameters[j]
                local entry=plain(sub,0)
                entry.ranges={}
                if sub.Ranges then for k=0,sub.Ranges:get_size()-1 do entry.ranges[#entry.ranges+1]=plain(sub.Ranges[k],0) end end
                row.parameters[#row.parameters+1]=entry
                local name=sub:get_type_definition():get_full_name()
                if not report.types[name] then report.types[name]=metadata(name) end
            end
            out[#out+1]=row
        end
    end
    return out
end)
read("current_actions",function() return {full=actor:current_action(0),upper=actor:current_action(1)} end)
read("lookup_comparison",function()
    local uuid="3c0b8528-94e6-431a-bd46-a2be7e2c6501"
    local api=assert(_G.VSB_API)
    local id
    for _,entry in ipairs(api.app.loaded.registry:entries("skill")) do
        if entry.doc.uuid==uuid and entry.pack_id=="fh_sorc" then id=entry.game_id end
    end
    assert(id,"Lightning Strike not registered")
    local list=ctrl:get_field("<ParamList>k__BackingField")
    local out={custom_skill_id=id,results={}}
    for _,sample in ipairs({{id=id,kind=3},{id=25,kind=3},{id=id,kind=4},{id=25,kind=4}}) do
        local request=sdk.create_instance("app.LockOnRangeParameter.RequestParameterInfo"):add_ref()
        request:set_field("<Job>k__BackingField",6)
        request:set_field("<ActionType>k__BackingField",sample.kind)
        request:set_field("<ActionID>k__BackingField",0)
        request:set_field("<CustomSkillID>k__BackingField",sample.id)
        request:set_field("<IsUseOnAir>k__BackingField",false)
        request:set_field("<IsUseForChangeTarget>k__BackingField",false)
        local param=list:call("getTypeParameter(app.LockOnRangeParameter.RequestParameterInfo)",request)
        out.results[#out.results+1]={id=sample.id,kind=sample.kind,parameter=plain(param,0)}
    end
    return out
end)
json.dump_file("VSB/diagnostics/levin_targeting_probe.json",report)
log.info("[FH Levin targeting] Read-only probe saved")
