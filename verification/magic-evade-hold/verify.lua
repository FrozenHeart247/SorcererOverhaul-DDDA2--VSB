-- Actual VSB executor, scripts, sandbox and schema. Input/action execution is simulated.
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
local START, END = 'Job04_AbsoluteAvoidanceStart', 'Job04_AbsoluteAvoidanceEnd'
local function check(ok, label)
    assert(ok, label)
    count = count + 1
    print('PASS: ' .. label)
end
local function create(buttons)
    local a = {actions={[0]='Idle',[1]='UpperBodyDefault'},buttons=buttons or {},requests={},now=0,time=0}
    function a:key() return 'player' end
    function a:valid() return true end
    function a:weapon_drawn() return true end
    function a:stamina() return 1000 end
    function a:current_action(layer) return self.actions[layer or 0] end
    function a:is_staggered() return false end
    function a:button_down(name) return self.buttons[name] == true end
    function a:request_action(name,layer)
        self.requests[#self.requests+1]={name=name,layer=layer or 0,at=self.now}
        self.actions[layer or 0]=name
        return true
    end
    local box=sandbox.new({clock=function() return a.time end})
    local runner=scripting.new({box=box})
    local ex=executor.new({nodes=executor.default_nodes(),clock=function() return a.time end,extensions={rules.new(),runner}})
    local entry={pack_id='fh_sorc',doc=util.deep_copy(docs.prepared)}
    local cast,why=ex:cast(a,entry,{free=true})
    assert(cast,why)
    local function step(n,update)
        for _=1,n do
            a.now=a.now+1
            a.time=a.time+1/60
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
check(errors==0 and #issues==0,'Prepared Magic Evade validates without warnings')
local before,after=util.deep_copy(docs.original),util.deep_copy(docs.prepared)
before.timeline,after.timeline=nil,nil
after.scripts,after['end']=nil,nil
check(util.deep_equal(before,after),'Identity, conditions, presentation, levels and configured costs are preserved')
check(docs.prepared.timeline[1].action==START and docs.prepared['end'].exit_action==END,
    'Native Start and End actions replace the direct Avoid request')
for i=2,#docs.original.timeline do
    assert(util.deep_equal(docs.original.timeline[i],docs.prepared.timeline[i]),'Disabled node changed')
end
check(true,'Existing disabled editor nodes are preserved')
for slot=1,6 do
    local button='Skill'..slot
    local a,ex,cast,step,entry,clean=create({[button]=true})
    check(not cast.finished and #a.requests==1 and a.requests[1].name==START,'Slot '..slot..': starts while held')
    step(120,function(actor)
        if actor.now==10 then actor.actions[0]='Strafe' end
        if actor.now==50 then actor.actions[0]='Job04_AbsoluteAvoidanceAvoid' end
        if actor.now==55 then actor.actions[0]='Strafe' end
    end)
    check(not cast.finished and #a.requests==1,'Slot '..slot..': natural action changes do not switch it off')
    a.buttons[button]=false
    step(1)
    check(cast.finished and ex:active(a:key())==nil and #a.requests==2 and a.requests[2].name==END,
        'Slot '..slot..': release requests End once and frees the next cast')
    step(10)
    check(#a.requests==2,'Slot '..slot..': release does not repeatedly request End')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({Skill3=true})
    step(1200,function(actor) actor.actions[0]='Strafe' end)
    check(not cast.finished and #a.requests==1,'Holding longer than the default 10-second tail remains active')
    a.buttons.Skill3=false
    step(1)
    check(cast.finished and a.requests[2].name==END,'Long hold still releases normally')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({Skill2=true})
    a.buttons.Skill5=true
    step(10)
    a.buttons.Skill2=false
    step(1)
    check(cast.finished and a.requests[2].name==END,'Another held skill button cannot take over the original hold')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({Skill1=true,Skill4=true})
    a.buttons.Skill4=false
    step(1)
    check(cast.finished,'Ambiguous initial chord ends when either captured skill input is released')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({Skill1=true})
    a.buttons.Skill1=false
    step(1)
    a.buttons.Skill1=true
    local retry,why=ex:cast(a,entry,{free=true})
    check(retry~=nil and not retry.finished and a.requests[3].name==START,'A new press after release starts a new hold')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({})
    check(cast.finished and #a.requests==2 and a.requests[2].name==END,'Missing held input ends safely instead of leaving the toggle active')
    clean()
end
do
    local a,ex,cast,step,entry,clean=create({Skill6=true})
    local retry,why=ex:cast(a,entry,{free=true})
    check(retry==nil and why=='already using a skill' and #a.requests==1,'Held-input retries cannot toggle Start repeatedly')
    clean()
end
print(('Completed %d assertions. Real input flag mapping and native ability activation/deactivation require an in-game test.'):format(count))
