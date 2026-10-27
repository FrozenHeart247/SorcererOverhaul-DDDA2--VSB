-- Real installed VSB modules. Actor state, effects and time are simulated.
package.path = arg[1] .. '/?.lua;' .. package.path
local docs = dofile(arg[2])
local executor = require('VSB.exec.executor')
local scripting = require('VSB.exec.scripting')
local sandbox = require('VSB.core.sandbox')
local rules = require('VSB.exec.rules')
local schema = require('VSB.core.schema')
local defs = require('VSB.core.schema_defs')
local util = require('DragonCore.core.util')
local count = 0
local function check(ok, label)
    assert(ok, label)
    count = count + 1
    print('PASS: ' .. label)
end
local function create(doc, delay, initial)
    local a = { actions={[0]='Strafe',[1]=initial or 'UpperBodyDefault'}, now=0,time=0,shells={} }
    function a:key() return 'test_actor' end
    function a:valid() return true end
    function a:weapon_drawn() return true end
    function a:stamina() return 1000 end
    function a:current_action(layer) return self.actions[layer or 0] end
    function a:is_staggered() return self.staggered == true end
    function a:request_action(name, layer)
        if delay and delay > 0 then self.pending={at=self.now+delay,name=name,layer=layer or 0}
        else self.actions[layer or 0]=name end
        return true
    end
    function a:spawn_shell(n)
        self.shells[#self.shells+1]={node=util.deep_copy(n),at=self.now}
        return true
    end
    local box=sandbox.new({clock=function() return a.time end})
    box:env_for('fh_sorc').os.clock=function() return a.time end
    local runner=scripting.new({box=box})
    local ex=executor.new({nodes=executor.default_nodes(),clock=function() return a.time end,extensions={rules.new(),runner}})
    local entry={pack_id='fh_sorc',doc=util.deep_copy(doc)}
    local cast,why=ex:cast(a,entry,{free=true})
    assert(cast,why)
    local function step(frames,update)
        for _=1,frames do
            a.now=a.now+1
            a.time=a.time+1/60
            if a.pending and a.now>=a.pending.at then
                a.actions[a.pending.layer]=a.pending.name
                a.pending=nil
            end
            if update then update(a) end
            ex:update(1/60)
        end
    end
    local function clean()
        if #ex.warnings>0 then error(ex.warnings[1].msg) end
        assert(#runner:problems()==0 and #runner:failing()==0,'Sandbox script failure')
    end
    return a,ex,cast,step,entry,clean
end
local issues,errors=schema.validate(defs.SKILL,docs.prepared)
check(errors==0 and #issues==0,'Skill validates without errors or warnings')
local before,after=util.deep_copy(docs.original),util.deep_copy(docs.prepared)
before.scripts,after.scripts=nil,nil
check(util.deep_equal(before,after),'Only scripts added: timeline, shell settings, IDs and costs are unchanged')
do
    local a,ex,cast,step,entry,clean=create(docs.original)
    step(60)
    a.actions[1]='DefaultCancelAction'
    step(400,function(actor)
        if actor.now==65 then actor.actions[1]='UpperBodyDefault' end
    end)
    check(#a.shells==3 and a.shells[1].at==78 and a.shells[2].at==325 and a.shells[3].at==416,
        'Original reproduces all scheduled custom shells after cancellation at one second')
    clean()
end
for _,cancelAction in ipairs({'DefaultCancelAction','UpperBodyDefault'}) do
    local a,ex,cast,step,entry,clean=create(docs.prepared)
    step(60)
    a.actions[1]=cancelAction
    step(10)
    check(cast.finished and ex:active(a:key())==nil,'One-second cancellation releases executor: '..cancelAction)
    step(400)
    check(#a.shells==0,'No custom shells launch after cancellation at one second: '..cancelAction)
    local retry=ex:cast(a,entry,{free=true})
    check(retry~=nil,'Armagedon can start again after cancellation: '..cancelAction)
    clean()
end
do
    local a,ex,cast,step,entry,clean=create(docs.prepared)
    step(100)
    check(#a.shells==1 and a.shells[1].at==78,'First preparation shell retains frame 78')
    a.actions[1]='DefaultCancelAction'
    step(400)
    check(cast.finished and #a.shells==1,'Cancellation after first shell prevents frames 325 and 416')
    clean()
end
for _,releaseAt in ipairs({300,350}) do
    local a,ex,cast,step,entry,clean=create(docs.prepared)
    step(460,function(actor)
        if actor.now==100 then actor.actions[1]='UpperBodyDefault' end
        if actor.now==102 then actor.actions[1]='Job06_ReadyMeteorFall' end
        if actor.now==200 then actor.actions[1]='Job06_ReadyMeteorFallSpellStock' end
        if actor.now==releaseAt then actor.actions[0],actor.actions[1]='Job06_CastMeteorFall','UpperBodyDefault' end
        if actor.now==releaseAt+20 then actor.actions[0]='Strafe' end
    end)
    check(#a.shells==3 and a.shells[1].at==78 and a.shells[2].at==325 and a.shells[3].at==416,
        'Normal cast preserves exact 78/325/416 timing after short gaps and Cast ending early: release '..releaseAt)
    check(cast.finished and cast.script_api.vars.armagedon_released,'Released spell completes its sequence')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create(docs.prepared,6,'DefaultCancelAction')
    step(60)
    check(not cast.finished and cast.script_api.vars.vsb_cancel_seen,'Asynchronous startup survives previous cancel action')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create(docs.prepared)
    step(30)
    a.actions[1]=nil
    step(15)
    a.actions[1]='Job06_ReadyMeteorFall'
    step(10)
    check(not cast.finished,'Missing layer data does not falsely cancel preparation')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create(docs.prepared)
    step(60)
    a.staggered=true
    step(400)
    check(cast.finished and cast.end_reason=='interrupted (hit)' and #a.shells==0,'Hit interruption still prevents all later shells')
    clean()
end
print(('Completed %d assertions. Actual cancellation and shell visuals require an in-game test.'):format(count))
