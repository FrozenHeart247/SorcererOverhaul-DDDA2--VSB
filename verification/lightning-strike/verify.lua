-- Uses installed VSB logic. Only the game actor/actions and shell creation are mocked.
package.path = arg[1] .. '/?.lua;' .. package.path
local docs = dofile(arg[2])
local executor = require('VSB.exec.executor')
local schema = require('VSB.core.schema')
local defs = require('VSB.core.schema_defs')
local levels = require('VSB.exec.levels')
local util = require('DragonCore.core.util')
local checks = 0
local function check(ok, label)
    assert(ok, label)
    checks = checks + 1
    print('PASS: ' .. label)
end
local function node(doc, id)
    for _, n in ipairs(doc.timeline) do if n.id == id then return n end end
end
local function create(doc, level)
    local a = { actions = { [0]='Idle', [1]='UpperBodyDefault' }, shells={}, now=0 }
    function a:key() return 'test' end
    function a:valid() return true end
    function a:weapon_drawn() return true end
    function a:stamina() return 1000 end
    function a:current_action(layer) return self.actions[layer or 0] end
    function a:request_action(name, layer) self.actions[layer or 0]=name; return true end
    function a:is_staggered() return self.staggered == true end
    function a:spawn_shell(n)
        self.shells[#self.shells+1] = {id=n.id, at=self.now, shell_id=n.shell_id}
        return true
    end
    local ex = executor.new({nodes=executor.default_nodes(),clock=function() return a.now/60 end})
    local cast, why = ex:cast(a, {pack_id='fh_sorc',doc=util.deep_copy(doc)}, {free=true,level=level or 1})
    assert(cast, why)
    local function step(frames, update)
        for _=1,frames do
            a.now=a.now+1
            if update then update(a) end
            ex:update(1/60)
        end
    end
    return a,ex,cast,step
end

for level=1,2 do
    local doc,warnings = levels.apply(docs.prepared,level)
    local issues,errors = schema.validate(defs.SKILL,doc)
    for _,i in ipairs(issues) do print(i.severity .. ': ' .. i.path .. ' ' .. i.msg) end
    check(errors==0 and #issues==0 and #warnings==0, 'Level '..level..' validates without warnings')
end
local original,prepared = util.deep_copy(docs.original),util.deep_copy(docs.prepared)
original.timeline,prepared.timeline=nil,nil
check(util.deep_equal(original,prepared),'Metadata, identities and both levels are unchanged')
check(util.deep_equal(node(docs.original,'n1'),node(docs.prepared,'n1')),'Prepare action is unchanged')
check(util.deep_equal(node(docs.original,'n2'),node(docs.prepared,'n2')),'Wight remains at frame 70 with all original settings')
local before,after=util.deep_copy(node(docs.original,'n4')),util.deep_copy(node(docs.prepared,'n4'))
before.frame,after.frame=nil,nil
check(util.deep_equal(before,after),'Thunder Rain settings unchanged except frame')
for _,n in ipairs(docs.prepared.timeline) do
    if n.else_target then assert(node(docs.prepared,n.else_target),'Missing flow target') end
end
check(true,'Timeout target resolves to the end node')
do
    local a,ex,cast,step=create(docs.original)
    step(90)
    check(#a.shells==2 and a.shells[2].id=='n4' and a.actions[1]=='JobMagicUser_PrepareLevin',
        'Original reproduces Thunder Rain while still preparing')
end
for _,castAt in ipairs({140,216,400}) do
    for level=1,2 do
        local a,ex,cast,step=create(docs.prepared,level)
        step(70)
        check(#a.shells==1 and a.shells[1].id=='n2' and a.shells[1].at==70,
            'Wight fires once at 70 (Cast at '..castAt..', level '..level..')')
        step(castAt-71,function(actor)
            if actor.now==100 then actor.actions[1]='JobMagicUser_ReadyLevin' end
        end)
        check(#a.shells==1 and not cast.finished,'Thunder Rain stays blocked through Prepare/Ready')
        a.actions[0],a.actions[1]='JobMagicUser_CastLevin','UpperBodyDefault'
        step(1)
        check(#a.shells==2 and a.shells[2].id=='n4' and a.shells[2].at==castAt,
            'Thunder Rain follows the actual Cast tick')
        step(100)
        check(#a.shells==2 and cast.finished and #ex.warnings==0,'No repeated shells or executor warnings')
    end
end
do
    local a,ex,cast,step=create(docs.prepared)
    step(670)
    check(#a.shells==1 and cast.finished and #ex.warnings==0,'Timeout after 70+600 frames skips Thunder Rain')
end
do
    local a,ex,cast,step=create(docs.prepared)
    step(100)
    a.staggered=true
    step(1)
    check(#a.shells==1 and cast.finished and cast.end_reason=='interrupted (hit)',
        'A hit during the wait prevents Thunder Rain')
end
print(('Completed %d checks; game animation and effects still require an in-game test.'):format(checks))
