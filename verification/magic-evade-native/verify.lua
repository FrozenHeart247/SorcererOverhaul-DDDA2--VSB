-- Real VSB executor + sandbox + events, and the actual companion/native adapter.
-- Native SDK calls are mocked with exact signatures from the live metadata report.
package.path=arg[3]..'/?.lua;'..arg[1]..'/?.lua;'..package.path
local docs=dofile(arg[2])
local executor=require('VSB.exec.executor')
local scripting=require('VSB.exec.scripting')
local sandbox=require('VSB.core.sandbox')
local events=require('VSB.core.events')
local schema=require('VSB.core.schema')
local defs=require('VSB.core.schema_defs')
local util=require('DragonCore.core.util')
local native=require('FH_MagicEvade.native')
local bridge=require('FH_MagicEvade.bridge')
local START='startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)'
local CLEAR='clearBuff_Job04AbsoluteAvoidance()'
local ACTIVE='get_IsActiveJob04AbsoluteAvoidance()'
local LEVEL='getCustomSkillLevel(app.HumanCustomSkillID)'
local ENABLED='isCustomSkillEnable(app.HumanCustomSkillID)'
local REACHED='isCustomSkillReachLevel(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)'
local signatures={[START]=true,[CLEAR]=true,[ACTIVE]=true}
local unsupported=false
local hooks,hook_storage={},nil
local buff_serial=2000
thread={get_hook_storage=function() assert(hook_storage,'Hook storage outside a native call'); return hook_storage end}
sdk={find_type_definition=function(name)
    if name=='app.HumanCustomSkillID' then
        return {get_field=function(_,field)
            assert(field=='Job04_AbsoluteAvoidance')
            return {get_data=function() return 99 end}
        end}
    end
    if name=='app.Job04ActionController' then return nil end
    if name=='app.HumanSpecialBuffManager.Job04AbsoluteAvoidanceBuff' then
        return {get_method=function(_,signature)
            assert(signature=='isTimerOver()'); return {signature=signature}
        end}
    end
    if name=='app.HumanSpecialBuffManager.CustomSkillBuff' then
        return {get_method=function(_,signature)
            assert(signature=='isTimerOver()')
            return {call=function(_,buff) return buff.actor.expired or not buff.actor.buff or buff.actor.time>=1000 end}
        end}
    end
    assert(name=='app.HumanSpecialBuffManager','Unexpected native type lookup')
    return {get_method=function(_,signature) return not unsupported and signatures[signature] and {} or nil end}
end,hook=function(method,pre,post) hooks[method.signature]={pre=pre,post=post} end,
to_managed_object=function(value) return value end,
to_int64=function(value) if type(value)=='boolean' then return value and 1 or 0 end; return value end,
to_ptr=function(value) return value end,PreHookResult={SKIP_ORIGINAL=1}}
local assertions=0
local function check(ok,label)
    assert(ok,label)
    assertions=assertions+1
    print('PASS: '..label)
end

local function create(opts)
    opts=opts or {}
    local a={actions={[0]='Strafe',[1]='UpperBodyDefault'},buttons=opts.buttons or {Skill3=true},
        now=0,time=0,ready=true,buff=opts.preexisting or false,starts=0,clears=0,requests={},clear_failures=opts.clear_failures or 0,
        native_level=opts.native_level or 0}
    function a:key() return 'player' end
    function a:valid() return self.ready end
    function a:stamina() return self.stamina_value or 1000 end
    function a:weapon_drawn() return true end
    function a:current_action(layer) return self.actions[layer or 0] end
    function a:is_staggered() return self.staggered==true end
    function a:button_down(name) assert(self.ready,'Input read on previous player'); return self.buttons[name]==true end
    function a:request_action(name,layer)
        self.requests[#self.requests+1]=name
        self.actions[layer or 0]=name
        if opts.clear_on_start and name=='Job04_AbsoluteAvoidanceStart' then self.buff=false end
        return true
    end
    local manager={get_address=function() return 42 end}
    buff_serial=buff_serial+1
    local buff_address=buff_serial
    local buff={actor=a,get_address=function() return buff_address end}
    a.native_buff=buff
    function buff:call(signature)
        if signature=='get_SecTimer()' then return a.time end
        if signature=='get_Param()' then return a.buff and {} or nil end
        assert(signature=='isTimerOver()')
        local value=not opts.preexisting or a.expired==true or a.time>=1000
        local hook=hooks[signature]
        if hook then
            local previous=hook_storage; hook_storage={}
            local skip=hook.pre({[2]=self})
            if skip~=sdk.PreHookResult.SKIP_ORIGINAL then a.original_expiry_calls=(a.original_expiry_calls or 0)+1 end
            value=hook.post(value)
            hook_storage=previous
        end
        return value==true or value==1
    end
    function manager:get_field(name)
        assert(name=='Job04AbsoluteAvoidance'); return buff
    end
    function manager:call(signature,...)
        assert(a.ready,'Native call on previous player')
        assert(signatures[signature],'Unexpected native call: '..tostring(signature))
        local args=table.pack(...)
        if signature==START then
            assert(args.n==2 and args[1]==1 and args[2]==nil,'Wrong start signature/arguments')
            a.starts=a.starts+1
            a.buff=true
            if opts.start_throws then error('Start failed after changing state') end
            if opts.no_activation then a.buff=false end
        elseif signature==CLEAR then
            assert(args.n==0,'Wrong clear arguments')
            a.clears=a.clears+1
            if a.clear_failures>0 then a.clear_failures=a.clear_failures-1; error('Transient clear failure') end
            a.buff=false
        else
            assert(args.n==0,'Wrong active-check arguments')
            return a.buff
        end
    end
    local function skill_context(address,source)
        local context={get_address=function() return address end}
        function context:call(signature,id,required)
            assert(signature==LEVEL or signature==ENABLED or signature==REACHED)
            local actual=id==99 and source.native_level or 7
            local value=signature==LEVEL and actual or (signature==ENABLED and actual>0 or signature==REACHED and actual>=required)
            local hook=hooks[signature]
            if hook then
                hook_storage={}
                hook.pre({[2]=self,[3]=id,[4]=required})
                value=hook.post(value)
                hook_storage=nil
            end
            if signature~=LEVEL and type(value)=='number' then return value~=0 end
            return value
        end
        return context
    end
    local context=skill_context(1001,a)
    a.test_context=context
    a.other_context=skill_context(1002,{native_level=0})
    a.human={get_field=function(_,name)
        assert(a.ready,'Human field read on previous player')
        if name=='SpecialBuffContext' then return {get_field=function(_,field)
            assert(field=='Job04AbsoluteAvoidanceTimer'); return a.time
        end} end
        assert(name=='SpecialBuffManager','Unexpected Human field')
        return manager
    end,get_SkillContext=function() return context end}
    local bus=events.new(function(event,err) error(event..': '..tostring(err)) end)
    local reports={}
    local controller=bridge.new(native,function(event,detail) reports[#reports+1]={event=event,detail=detail} end)
    controller:attach(bus)
    local runner=scripting.new({box=sandbox.new({clock=function() return a.time end})})
    local ex=executor.new({nodes=executor.default_nodes(),bus=bus,clock=function() return a.time end,extensions={runner}})
    local doc=util.deep_copy(docs.prepared)
    if opts.with_start then doc.timeline[1].enabled=true end
    if opts.other_uuid then doc.uuid='unrelated-skill' end
    local entry={pack_id='fh_sorc',doc=doc}
    local cast,why=ex:cast(a,entry,{free=true})
    assert(cast,why)
    controller:tick()
    local function step(n,update)
        for _=1,n do
            a.now=a.now+1; a.time=a.time+1/60
            if update then update(a) end
            if a.buff and buff:call('isTimerOver()') then a.buff=false end
            ex:update(1/60)
            controller:tick()
        end
    end
    local function clean()
        if #ex.warnings>0 then error(ex.warnings[1].msg) end
        assert(#runner:problems()==0 and #runner:failing()==0,'Sandbox script failure')
    end
    return a,ex,cast,step,controller,entry,reports,clean
end

local issues,errors=schema.validate(defs.SKILL,docs.prepared)
check(errors==0 and #issues==0,'Native hold JSON validates without warnings')
local before,after=util.deep_copy(docs.original),util.deep_copy(docs.prepared)
before.timeline,after.timeline=nil,nil; after.scripts,after['end']=nil,nil
check(util.deep_equal(before,after),'Configured costs, identity, conditions and presentation are preserved')
check(docs.prepared.timeline[1].enabled==false and docs.prepared['end'].exit_action==nil,
    'Native-only hold does not force Start or End animations')
do
    local a,ex,cast,step,controller,entry,reports,clean=create({with_start=true,clear_on_start=true})
    step(1)
    check(cast.finished and not a.buff,'Regression scenario: Start resetting the buff reproduces immediate native expiry')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({clear_on_start=true})
    step(60)
    check(not cast.finished and a.buff and #a.requests==0,'Native-only variant avoids the animation-reset path')
    check(reports[1].detail.snapshot.native_skill_level_original==0 and reports[1].detail.snapshot.native_skill_level==0 and
        reports[1].detail.snapshot.parameter_present==true,'Activation reports the unchanged learned level and native parameter presence')
    a.buttons.Skill3=false; step(1)
    check(cast.finished and not a.buff and #a.requests==0,'Release clears the native buff without any action request')
    clean()
end
for slot=1,6 do
    local a,ex,cast,step,controller,entry,reports,clean=create({buttons={['Skill'..slot]=true}})
    check(a.buff and a.starts==1,'Slot '..slot..': exact native start call activates the mocked buff')
    step(1200,function(actor)
        if actor.now==20 then actor.actions[0]='Strafe' end
        if actor.now==60 then actor.actions[0]='Job04_AbsoluteAvoidanceAvoid' end
        if actor.now==65 then actor.actions[0]='Strafe' end
    end)
    check(a.buff and a.starts==1 and not cast.finished,'Slot '..slot..': long hold does not restart or refresh native buff')
    a.buttons['Skill'..slot]=false
    step(1)
    check(cast.finished and not a.buff and a.clears==1 and ex:active(a:key())==nil,'Slot '..slot..': release clears buff and frees VSB')
    check(reports[#reports].event=='stop' and reports[#reports].detail.active==false,'Slot '..slot..': off-state readback is recorded')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    step(20); a.staggered=true; step(1)
    check(cast.finished and not a.buff and a.clears==1,'Hit interruption clears the owned native buff')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    local other={pack_id='fh_sorc',doc=util.deep_copy(docs.prepared)}
    other.doc.uuid='other'; other.doc.scripts=nil; other.doc['end']=nil
    local replacement,why=ex:cast(a,other,{free=true,force=true})
    check(replacement~=nil and cast.finished and not a.buff and a.clears==1,'Forced replacement clears Magic Evade before the next skill')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    ex:cancel_all('skill disabled or reloaded')
    check(not a.buff and a.clears==1,'Pack reload/cancellation clears the native buff')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    controller:shutdown()
    check(not a.buff and a.clears==1,'Companion shutdown clears the owned buff')
    step(1)
    check(cast.finished,'Shutdown requests the hold controller to finish')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({preexisting=true})
    a.buttons.Skill3=false; step(1)
    check(a.buff and a.starts==0 and a.clears==0,'A pre-existing native buff is preserved instead of being stolen or cleared')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({other_uuid=true})
    check(not a.buff and a.starts==0,'Other skill UUIDs never enable this native buff')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({buttons={}})
    check(cast.finished and not a.buff and a.starts==0,'Editor Test/no held skill input cannot leave native avoidance on')
    clean()
end
for _,failure in ipairs({'no_activation','start_throws'}) do
    local a,ex,cast,step,controller,entry,reports,clean=create({[failure]=true})
    step(1)
    check(cast.finished and not a.buff and a.clears==1,'Failed native activation is cleaned up: '..failure)
    clean()
end
do
    unsupported=true
    local a,ex,cast,step,controller,entry,reports,clean=create()
    step(1)
    check(cast.finished and a.starts==0,'Missing exact native signatures fail without invoking a substitute method')
    unsupported=false
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    a.buff=false; step(2)
    check(cast.finished and a.starts==1,'Native expiry/stamina stop is not repeatedly re-enabled')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({clear_failures=1})
    a.buttons.Skill3=false; step(1)
    check(cast.finished and not a.buff and a.clears==2,'A transient native-clear error gets a bounded cleanup retry')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    a.ready=false; step(1)
    check(cast.finished and a.clears==0,'Character replacement causes no input reads or native writes through the previous player')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    a.buttons.Skill5=true; a.buttons.Skill3=false; step(1)
    check(cast.finished and not a.buff,'Another held button cannot take over the original hold')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    check(not a.native_buff:call('isTimerOver()') and a.original_expiry_calls==nil,
        'Owned buff skips only the derived equipment scan and uses the real base method')
    local other={get_address=function() return -1 end}
    check(a.test_context:call(LEVEL,99)==0 and a.other_context:call(LEVEL,99)==0,
        'Learned-level reads remain unchanged for this and other characters')
    local previous=hook_storage; hook_storage={}
    local hook=hooks['isTimerOver()']
    local skip=hook.pre({[2]=other})
    local unchanged=hook.post(true)
    hook_storage=previous
    check(skip==nil and unchanged==true,'Unowned buffs keep the original equipment expiry result')
    step(120)
    check(a.buff and not cast.finished,'A missing equipped native skill no longer expires the modeled buff')
    a.expired=true; step(2)
    check(cast.finished and not a.buff and a.starts==1,'Base duration/parameter expiry is preserved without reactivation')
    check(a.native_buff:call('isTimerOver()'),'After release, original equipment expiry applies again')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create({native_level=2})
    check(a.test_context:call(LEVEL,99)==2,'An already learned higher native level is preserved')
    a.buttons.Skill3=false; step(1)
    check(a.native_level==2 and a.test_context:call(LEVEL,99)==2,'Original higher skill level remains after release')
    clean()
end
do
    local a,ex,cast,step,controller,entry,reports,clean=create()
    controller:shutdown()
    check(a.native_buff:call('isTimerOver()'),'Companion shutdown drops the equipment-check bypass')
    clean()
end
print(('Completed %d assertions. Native method execution and real automatic avoidance still require an in-game test.'):format(assertions))
