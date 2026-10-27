-- Manual ScriptRunner diagnostic, run while the game is paused.
-- Temporarily acquires only an inactive buff, reads its configuration, then clears it synchronously.
local runtime=require("DragonCore.game.runtime")
local output="VSB/diagnostics/magic_evade_parameters.json"
local report={version=5,generated=os.date("!%Y-%m-%dT%H:%M:%SZ"),errors={}}
local actor=runtime.player()
assert(actor and actor:valid(),"Load a player first")
local manager=actor.human:get_field("SpecialBuffManager")
local start="startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)"
local active="get_IsActiveJob04AbsoluteAvoidance()"
local clear="clearBuff_Job04AbsoluteAvoidance()"
local owned=false
local visited={}
local function describe(obj,depth)
    if obj==nil then return {missing=true} end
    if type(obj)~="userdata" and type(obj)~="table" then return obj end
    local td=obj:get_type_definition()
    local name=td:get_full_name()
    local key=tostring(obj:get_address())
    if visited[key] then return {type=name,already_seen=true} end
    visited[key]=true
    local result={type=name,fields={}}
    local parent=td
    for _=1,8 do
        if not parent then break end
        for _,field in ipairs(parent:get_fields() or {}) do
            if not field:is_static() then
                local entry={name=parent:get_full_name().."."..field:get_name(),type=field:get_type():get_full_name()}
                local ok,value=pcall(obj.get_field,obj,field:get_name())
                if not ok then entry.error=tostring(value)
                elseif value==nil then entry.missing=true
                elseif type(value)=="number" or type(value)=="boolean" or type(value)=="string" then entry.value=value
                elseif depth>0 and (entry.type:find("^app%.") or entry.type:find("^System%.Nullable")) and not entry.type:find("%[") then
                    local got,child=pcall(describe,value,depth-1)
                    if got then entry.value=child else entry.error=tostring(child) end
                end
                result.fields[#result.fields+1]=entry
            end
        end
        parent=parent:get_parent_type()
    end
    return result
end
local function read(name,fn)
    local ok,value=pcall(fn)
    if ok then report[name]=value else report.errors[#report.errors+1]=name..": "..tostring(value) end
end
local ok,err=pcall(function()
    report.preexisting=manager:call(active)==true
    read("level_enum",function()
        local values={}
        local td=sdk.find_type_definition("app.HumanCustomSkillLevelNo")
        for _,field in ipairs(td and td:get_fields() or {}) do
            if field:is_static() then values[field:get_name()]=field:get_data(nil) end
        end
        return values
    end)
    if not report.preexisting then
        owned=true
        manager:call(start,1,nil)
    end
    report.active_after_start=manager:call(active)==true
    local buff=manager:get_field("Job04AbsoluteAvoidance")
    read("timer_over_at_start",function() return buff:call("isTimerOver()") end)
    read("timer_at_start",function() return buff:call("get_SecTimer()") end)
    read("timer_code",function()
        local result={}
        for _,name in ipairs({"app.HumanSpecialBuffManager.Job04AbsoluteAvoidanceBuff","app.HumanSpecialBuffManager.CustomSkillBuff"}) do
            local method=sdk.find_type_definition(name):get_method("isTimerOver()")
            local address=sdk.to_int64(method:get_function())
            local bytes={}
            for i=0,511 do
                local byte=sdk.to_valuetype(address+i,"System.Byte")
                bytes[#bytes+1]=string.format("%02x",byte:read_byte(0))
            end
            result[#result+1]={type=name,address=address,hex=table.concat(bytes)}
        end
        return result
    end)
    read("specific_parameter",function() return describe(buff:call("get_AbsoluteAvoidanceParam()"),2) end)
    read("parameter",function() return describe(buff:call("get_Param()"),2) end)
    read("buff",function() return describe(buff,2) end)
    read("timer_implementations",function()
        local entries={}
        local td=buff:get_type_definition()
        for _=1,8 do
            if not td then break end
            local method=td:get_method("isTimerOver()")
            if method then
                local entry={type=td:get_full_name()}
                local success,result=pcall(method.call,method,buff)
                if success then entry.result=result else entry.error=tostring(result) end
                entries[#entries+1]=entry
            end
            td=td:get_parent_type()
        end
        return entries
    end)
    -- Compare the same getter against a disposable context bound only to this buff.
    -- Never change the player's job/context or run a game update with the temporary reference.
    if owned then read("job_comparison",function()
        local field="<JobContext>k__BackingField"
        local original=buff:get_field(field)
        local temporary=sdk.create_instance("app.JobContext"):add_ref()
        local entries={original_job=original:get_field("CurrentJob"),results={}}
        local worked,failure=pcall(function()
            buff:set_field(field,temporary)
            for _,job in ipairs({6,4,10}) do
                temporary:set_field("CurrentJob",job)
                entries.results[#entries.results+1]={job=job,timer_over=buff:call("isTimerOver()")}
            end
        end)
        buff:set_field(field,original)
        entries.restored=buff:get_field(field):get_address()==original:get_address()
        if not worked then error(failure) end
        return entries
    end) end
    if owned then read("equipment_comparison",function()
        local key="FHMagicEvadeParameterTrace"
        local holder=_G[key]
        if not holder then
            holder={}
            _G[key]=holder
            local method=sdk.find_type_definition("app.HumanSkillContext"):get_method("hasEquipedSkill(app.Character.JobEnum, app.HumanCustomSkillID)")
            sdk.hook(method,function(args)
                local storage=thread.get_hook_storage()
                storage[key]=nil
                local context=sdk.to_managed_object(args[2])
                if holder.current and context and context:get_address()==holder.current.address then
                    local entry={job=sdk.to_int64(args[3]) & 0xFFFFFFFF,skill=sdk.to_int64(args[4]) & 0xFFFFFFFF}
                    holder.current.queries[#holder.current.queries+1]=entry
                    storage[key]={entry=entry,force=holder.current.force}
                end
            end,function(retval)
                local match=thread.get_hook_storage()[key]
                thread.get_hook_storage()[key]=nil
                if match then
                    match.entry.original=(sdk.to_int64(retval) & 0xFF)~=0
                    if match.force then return sdk.to_ptr(1) end
                end
                return retval
            end)
        end
        local results={}
        local context=actor.human:get_SkillContext()
        for _,force in ipairs({false,true}) do
            local entry={address=context:get_address(),force=force,queries={}}
            holder.current=entry
            local success,result=pcall(buff.call,buff,"isTimerOver()")
            holder.current=nil
            if not success then error(result) end
            entry.timer_over=result
            results[#results+1]=entry
        end
        return results
    end) end
end)
if not ok then report.errors[#report.errors+1]=tostring(err) end
if owned then
    local cleared,failure=pcall(manager.call,manager,clear)
    report.cleared=cleared
    if not cleared then report.errors[#report.errors+1]="cleanup: "..tostring(failure) end
end
report.active_after_cleanup=manager:call(active)==true
json.dump_file(output,report)
log.info("[FH Magic Evade inspect] Saved "..output)
