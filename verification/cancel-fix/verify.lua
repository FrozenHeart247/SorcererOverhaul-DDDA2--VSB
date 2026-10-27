-- Actual installed executor, scripting extension, sandbox, schema and node modules.
-- Game actions are simulated. The sandbox clock is deterministic; no game process is touched.
package.path = arg[1] .. '/?.lua;' .. package.path
local docs = dofile(arg[2])
local executor = require('VSB.exec.executor')
local scripting = require('VSB.exec.scripting')
local sandbox = require('VSB.core.sandbox')
local rules = require('VSB.exec.rules')
local schema = require('VSB.core.schema')
local defs = require('VSB.core.schema_defs')
local levels = require('VSB.exec.levels')
local util = require('DragonCore.core.util')
local count = 0
local function check(ok, label)
    assert(ok, label)
    count = count + 1
    print('PASS: ' .. label)
end
local specs = {
    salamander = { prepare='Job06_PrepareSalamander', ready='Job06_ReadySalamander', stock='Job06_ReadySalamanderSpellStock', cast='Job06_CastSalamander', total=1 },
    levin = { prepare='JobMagicUser_PrepareLevin', ready='JobMagicUser_ReadyLevin', stock='JobMagicUser_ReadyLevinSpellStock', cast='JobMagicUser_CastLevin', total=2 },
}
local function create(doc, level, delay, initial)
    local a = { actions={[0]='Strafe',[1]=initial or 'UpperBodyDefault'}, now=0, time=0, shells={} }
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
    function a:spawn_shell(n) self.shells[#self.shells+1]={id=n.id,at=self.now}; return true end
    local box = sandbox.new({clock=function() return a.time end})
    box:env_for('fh_sorc').os.clock=function() return a.time end
    local runner = scripting.new({box=box})
    local ex = executor.new({nodes=executor.default_nodes(),clock=function() return a.time end,extensions={rules.new(),runner}})
    local entry = {pack_id='fh_sorc',doc=util.deep_copy(doc)}
    local cast,why = ex:cast(a,entry,{free=true,level=level or 1})
    assert(cast,why)
    local function step(frames,update,dt)
        for _=1,frames do
            a.now=a.now+1
            a.time=a.time+(dt or 1/60)
            if a.pending and a.now>=a.pending.at then
                a.actions[a.pending.layer]=a.pending.name
                a.pending=nil
            end
            if update then update(a) end
            ex:update(dt or 1/60)
        end
    end
    local function clean()
        if #ex.warnings>0 then error(ex.warnings[1].msg) end
        assert(#runner:problems()==0 and #runner:failing()==0,'Sandbox script failure')
    end
    return a,ex,cast,step,entry,clean
end

for family,spec in pairs(specs) do
    local old,new=docs.original[family],docs.prepared[family]
    local before,after=util.deep_copy(old),util.deep_copy(new)
    before.scripts,after.scripts=nil,nil
    check(util.deep_equal(before,after),family..': only per-skill scripts added, timeline and shell settings preserved')
    for level=1,2 do
        local effective,warnings=levels.apply(new,level)
        local issues,errors=schema.validate(defs.SKILL,effective)
        check(errors==0 and #issues==0 and #warnings==0,family..': level '..level..' schema and level patch valid')
    end
    do
        local a,ex,cast,step,entry=create(old)
        step(100)
        a.actions[0],a.actions[1]='Strafe','UpperBodyDefault'
        step(20)
        local retry,why=ex:cast(a,entry,{free=true})
        check(not cast.finished and retry==nil and why=='already using a skill',family..': old JSON reproduces lock after native cancel')
    end
    for level=1,2 do
        -- Early native cancellation must also suppress the frame-70 Wight.
        local a,ex,cast,step,entry,clean=create(new,level)
        step(30)
        a.actions[1]='DefaultCancelAction'
        step(1)
        check(cast.finished and ex:active(a:key())==nil and #a.shells==0,family..': early explicit cancel releases executor immediately')
        local retry=ex:cast(a,entry,{free=true,level=level})
        check(retry~=nil,family..': same spell can immediately start again, level '..level)
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new)
        step(100)
        local shellsBefore=#a.shells
        a.actions[0],a.actions[1]='Strafe','UpperBodyDefault'
        step(1)
        check(not cast.finished,family..': short action gap gets a grace interval')
        step(8)
        check(cast.finished and ex:active(a:key())==nil and #a.shells==shellsBefore,family..': idle cancellation releases executor within 150ms without final shell')
        local retry=ex:cast(a,entry,{free=true})
        check(retry~=nil,family..': retry after idle cancellation is accepted')
        clean()
    end
    for level=1,2 do
        local a,ex,cast,step,entry,clean=create(new,level)
        step(99)
        if family=='levin' then check(#a.shells==1 and a.shells[1].at==70,'levin: Wight still fires at frame 70') end
        -- Two-frame layer gap, then the normal Ready and SpellStock variants.
        a.actions[1]='UpperBodyDefault'
        step(2)
        a.actions[1]=spec.ready
        step(90)
        a.actions[1]=spec.stock
        step(20)
        check(not cast.finished,family..': normal Prepare / gap / Ready / SpellStock chain remains active')
        a.actions[0],a.actions[1]=spec.cast,'UpperBodyDefault'
        step(3)
        check(cast.finished and #a.shells==spec.total,family..': normal Cast still fires correct shells exactly once, level '..level)
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new,1,6,'DefaultCancelAction')
        step(30)
        check(not cast.finished and cast.script_api.vars.vsb_cancel_seen,family..': asynchronous startup and old cancel action do not cancel a fresh cast')
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new,1,math.huge)
        step(30)
        check(cast.finished and #a.shells==0,family..': never-entered preparation exits without a long timeout')
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new)
        step(30)
        a.actions[1]=nil
        step(20)
        check(not cast.finished,family..': missing action data is not treated as cancellation')
        a.actions[1]=spec.ready
        step(10)
        check(not cast.finished,family..': state query recovery preserves the spell')
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new)
        step(100)
        a.staggered=true
        step(1)
        check(cast.finished and cast.end_reason=='interrupted (hit)',family..': standard hit interruption remains intact')
        clean()
    end
    do
        local a,ex,cast,step,entry,clean=create(new)
        step(700)
        check(cast.finished and #a.shells==(family=='levin' and 1 or 0),family..': normal 600-frame wait timeout still skips the final shell')
        clean()
    end
end
print(('Completed %d assertions. Native cancel action and final behavior still require an in-game check.'):format(count))
