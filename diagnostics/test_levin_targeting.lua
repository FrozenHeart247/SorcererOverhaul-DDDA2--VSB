-- Standalone behavioral checks. No game process or live player is used.
local root=assert(arg[1],"repo root required"):gsub("\\","/")
package.path=root.."/prepared/levin-targeting/reframework/autorun/?.lua;"..
    "F:/SteamLibrary/steamapps/common/Dragons Dogma 2/reframework/autorun/?.lua;"..package.path
local checks=0
local function check(value,label) assert(value,label); checks=checks+1 end
local INFO="<ParameterInfo>k__BackingField"
local function backing(name) return "<"..name..">k__BackingField" end
local value_mt={}
value_mt.__index={get_field=function(self,k) return self.fields[k] end,
    set_field=function(self,k,v) if self.fail==k then error("mock write failed") end; self.fields[k]=v end,
    address=function(self) return self end,add_ref=function(self) return self end}
local function value(fields) return setmetatable({fields=fields or {}},value_mt) end
local function td(names,is_value_type)
    local fields={}
    for _,name in ipairs(names) do fields[#fields+1]={get_name=function() return name end,is_static=function() return false end} end
    return {get_fields=function() return fields end,is_value_type=function() return is_value_type end,
        get_full_name=function() return "mock.RequestParameterInfo" end}
end
local request_names={}
for _,name in ipairs({"Job","ActionType","ActionID","CustomSkillID","IsUseOnAir","IsUseForChangeTarget"}) do request_names[#request_names+1]=backing(name) end
local option_names={INFO,backing("IsUseLockOnUI"),"UpdateType2","RateRadiusScale","AdditionalOptionFlag",backing("TargetObject"),backing("CustomBasePos")}
local types={["app.LockOnController.Option"]=td(option_names,false),["app.LockOnRangeParameter.RequestParameterInfo"]=td(request_names,false),
    ["app.LockOnController"]={get_method=function() return "updateLockOn" end},
    ["app.HumanCustomSkillID"]={get_field=function() return {get_data=function() return 25 end} end}}
local hooks,storage={},{}
sdk={create_instance=function() return value() end,find_type_definition=function(name) return types[name] end,hook=function(_,pre,post) hooks[#hooks+1]={pre=pre,post=post} end,
    to_managed_object=function(x) return x end,to_ptr=function(x) return x end,typeof=function(x) return x end}
ValueType={new=function() return value() end}
thread={get_hook_storage=function() return storage end}
local list={call=function(_,_,info)
    local native=info:get_field(backing("Job"))==6 and info:get_field(backing("CustomSkillID"))==25
    return {CustomSkillID=native and 25 or 0,ActionType=native and 3 or 0,MaxDistance=native and 32 or -1,
        IsBasedOnCamera=native,IsUseLockOnUI=native}
end}
local ctrl={get_address=function() return 123 end,get_field=function() return list end}
local player={call=function() return ctrl end}
local valid=true
local actor={valid=function() return valid end,game_object={call=function() return player end}}
local function cast(level) return {entry={pack_id="fh_sorc"},doc={uuid="3c0b8528-94e6-431a-bd46-a2be7e2c6501"},actor=actor,level=level} end
local function option()
    local info=value()
    for i,name in ipairs(request_names) do info:set_field(name,i) end
    info:set_field(backing("CustomSkillID"),141)
    return value({[INFO]=info,[backing("IsUseLockOnUI")]=false,UpdateType2=7,RateRadiusScale=1.7,
        AdditionalOptionFlag=1234,[backing("TargetObject")]={target=true},[backing("CustomBasePos")]={x=1,y=2,z=3}})
end
local events={}
local controller=require("FH_LevinTargeting.controller").new(function(event,detail) events[#events+1]={event=event,detail=detail} end)
controller:prepare(); controller:prepare()
check(#hooks==1,"prepare idempotent")
local hook=hooks[1]
local function invoke(source,target)
    local args={[2]=target or ctrl,[3]=source}
    hook.pre(args)
    return args
end
local source=option()
check(invoke(source)[3]==source,"inactive is neutral")
local bus=require("VSB.core.events").new(function(_,err) error(err) end)
controller:attach(bus); controller:attach(bus)
check(#bus.listeners.cast_start==1,"one subscription")
local wrong=cast(1); wrong.doc.uuid="other"; bus:emit("cast_start",wrong)
check(not controller.active,"other UUID ignored")
wrong=cast(1); wrong.entry.pack_id="other"; bus:emit("cast_start",wrong)
check(not controller.active,"other pack ignored")
local first=cast(1); bus:emit("cast_start",first)
check(controller.active and controller.active.cast==first,"level one active")
local other={get_address=function() return 456 end}
check(invoke(source,other)[3]==source,"other controller untouched")
local args=invoke(source)
local copied=args[3]
check(copied~=source,"option independently copied")
check(copied:get_field(INFO)~=source:get_field(INFO),"request independently copied")
for _,name in ipairs(option_names) do
    if name~=INFO and name~=backing("IsUseLockOnUI") then check(copied:get_field(name)==source:get_field(name),"preserve "..name) end
end
for _,name in ipairs({"IsUseOnAir","IsUseForChangeTarget"}) do
    check(copied:get_field(INFO):get_field(backing(name))==source:get_field(INFO):get_field(backing(name)),"preserve "..name)
end
check(copied:get_field(INFO):get_field(backing("Job"))==6,"Sorcerer profile job selected")
check(copied:get_field(INFO):get_field(backing("CustomSkillID"))==25,"native Levin ID")
check(copied:get_field(INFO):get_field(backing("ActionType"))==3,"custom skill type")
check(copied:get_field(INFO):get_field(backing("ActionID"))==0,"initial profile")
check(copied:get_field(backing("IsUseLockOnUI"))==true,"UI enabled")
check(source:get_field(INFO):get_field(backing("CustomSkillID"))==141 and not source:get_field(backing("IsUseLockOnUI")),"source unmodified")
check(storage.fh_levin_targeting_option.option==copied and storage.fh_levin_targeting_option.info==copied:get_field(INFO),"copies retained for native call")
check(controller.active.first.profile.max_distance==32,"diagnostic profile captured")
check(hook.post(99)==99 and not storage.fh_levin_targeting_option,"post preserves return and releases copy")
local cold=option()
for _,name in ipairs({"Job","ActionType","ActionID","CustomSkillID"}) do cold:get_field(INFO):set_field(backing(name),0) end
local cold_args=invoke(cold)
check(cold_args[3]:get_field(INFO):get_field(backing("Job"))==6,"cold request gets initialized profile job")
check(list:call("lookup",cold_args[3]:get_field(INFO)).MaxDistance==32,"cold request resolves native range")
check(cold:get_field(INFO):get_field(backing("Job"))==0 and cold:get_field(INFO):get_field(backing("CustomSkillID"))==0,"cold caller remains uninitialized and unmodified")
hook.post(0)
bus:emit("cast_end",wrong,"cancelled"); check(controller.active~=nil,"other cast end ignored")
bus:emit("cast_end",first,"cancelled"); check(not controller.active and invoke(source)[3]==source,"cancellation neutral")
local second=cast(2); bus:emit("cast_start",second)
check(controller.active.cast==second,"level two active")
second.finished=true; check(invoke(source)[3]==source,"finished cast neutral before tick")
controller:tick(); check(not controller.active,"tick cleans finished cast")
second=cast(2); bus:emit("cast_start",second); valid=false
check(invoke(source)[3]==source and not controller.active,"invalid actor neutral")
valid=true; bus:emit("cast_start",second)
local broken=option(); broken.get_field=function() error("mock SDK read failed") end
check(invoke(broken)[3]==broken and not controller.active,"SDK failure leaves args unchanged")
check(events[#events].event=="hook_error","SDK error reported")
bus:emit("cast_start",second); controller:shutdown()
check(not controller.active and #bus.listeners.cast_start==0,"shutdown clears lifecycle")
check(invoke(source)[3]==source,"installed hook neutral after shutdown")
bus:emit("cast_start",first); check(not controller.active,"no restart after shutdown")
print(string.format("PASS: %d Levin targeting behavioral checks (SDK mocked; real VSB event bus)",checks))
