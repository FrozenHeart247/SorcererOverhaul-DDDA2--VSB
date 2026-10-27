-- Actual installed VSB executor, conditions, flow and shell handlers; mocked game actor only.
-- This verifies timeline behavior, not the game's FSM, button handling or rendered shells.
package.path = arg[1] .. '/?.lua;' .. package.path
local docs = dofile(arg[2])
local executor = require('VSB.exec.executor')
local schema = require('VSB.core.schema')
local defs = require('VSB.core.schema_defs')
local util = require('DragonCore.core.util')
local conditions = require('VSB.exec.conditions')
local checks = 0
local function check(ok, label)
    assert(ok, label)
    checks = checks + 1
    print('PASS: ' .. label)
end

local function create(doc)
    local actor = { actions = { [0] = 'Idle', [1] = 'UpperBodyDefault' }, shells = {}, now = 0 }
    function actor:key() return 'test_actor' end
    function actor:valid() return true end
    function actor:weapon_drawn() return true end
    function actor:stamina() return 1000 end
    function actor:current_action(layer) return self.actions[layer or 0] end
    function actor:request_action(name, layer) self.actions[layer or 0] = name; return true end
    function actor:is_staggered() return self.staggered == true end
    function actor:spawn_shell(node)
        self.shells[#self.shells + 1] = { node = node, at = self.now }
        return true
    end
    local ex = executor.new({ nodes = executor.default_nodes(), clock = function() return actor.now / 60 end })
    local cast, why = ex:cast(actor, { pack_id = 'fh_sorc', doc = util.deep_copy(doc) }, { free = true })
    assert(cast, why)
    local function step(frames, update)
        for _ = 1, frames do
            actor.now = actor.now + 1
            if update then update(actor) end
            ex:update(1 / 60)
        end
    end
    return actor, ex, cast, step
end

local issues, errors = schema.validate(defs.SKILL, docs.prepared)
for _, issue in ipairs(issues) do print(issue.severity .. ': ' .. issue.path .. ' ' .. issue.msg) end
check(errors == 0 and #issues == 0, 'Prepared document passes VSB schema without warnings')
local oldMeta, newMeta = util.deep_copy(docs.original), util.deep_copy(docs.prepared)
oldMeta.timeline, newMeta.timeline = nil, nil
check(util.deep_equal(oldMeta, newMeta), 'Identity, availability, conditions and costs are unchanged')
local function node(doc, id)
    for _, n in ipairs(doc.timeline) do if n.id == id then return n end end
end
local oldShell, newShell = util.deep_copy(node(docs.original, 'n1')), util.deep_copy(node(docs.prepared, 'n1'))
oldShell.frame, newShell.frame = nil, nil
check(util.deep_equal(oldShell, newShell), 'Shell settings unchanged except timeline frame')
check(util.deep_equal(node(docs.original, 'n2'), node(docs.prepared, 'n2')), 'Prepare action unchanged')
for _, n in ipairs(docs.prepared.timeline) do
    for _, key in ipairs({ 'target', 'else_target' }) do
        if n[key] then assert(node(docs.prepared, n[key]), 'Missing target: ' .. n[key]) end
    end
end
check(true, 'All flow targets resolve')

do
    local actor, ex, cast, step = create(docs.original)
    step(73)
    check(#actor.shells == 1 and actor.shells[1].at == 68, 'Original reproduces shell before branch, while still preparing')
    check(cast.finished and cast.end_reason == 'runaway', 'Latest original self-branch n3 reproduces endless-loop protection')
end
do
    local firstRead = util.deep_copy(docs.original)
    node(firstRead, 'n3').target = 'n4' -- target seen in the first read, before the user changed it
    local actor, ex, cast, step = create(firstRead)
    step(73)
    check(#ex.warnings == 1 and ex.warnings[1].msg:find("unknown node 'n4'", 1, true), 'First-read n4 target reproduces missing-node warning')
end
do
    local actor, ex, cast, step = create(docs.original)
    step(95, function(a)
        if a.now == 70 then a.actions[1] = 'Job06_ReadySalamander' end
    end)
    check(#actor.shells > 1, 'Original false branch repeats shell after jumping backwards')
end
do
    local actor, ex, cast, step = create(docs.prepared)
    check(conditions.eval({ state = 'in_action', arg = 'PrepareSalamander', layer = 0 }, actor), 'in_action checks both layers even when layer is 0')
    step(149)
    check(#actor.shells == 0 and not cast.finished, 'Prepare never fires the shell')
    actor.actions[1] = 'Job06_ReadySalamander'
    step(66)
    check(#actor.shells == 0 and not cast.finished, 'Ready never fires the shell')
    actor.actions[0], actor.actions[1] = 'Job06_CastSalamander', 'UpperBodyDefault'
    step(1)
    check(#actor.shells == 1 and actor.shells[1].at == 216, 'First observed Cast tick fires exactly one shell')
    step(100)
    check(#actor.shells == 1 and cast.finished and #ex.warnings == 0, 'Cast completes without repeated shells or executor warnings')
end
do
    local actor, ex, cast, step = create(docs.prepared)
    step(600)
    check(#actor.shells == 0 and cast.finished and #ex.warnings == 0, '600-frame timeout skips shell and finishes')
end
do
    local actor, ex, cast, step = create(docs.prepared)
    step(30)
    actor.actions[0], actor.actions[1] = 'Idle', 'UpperBodyDefault'
    step(570)
    check(#actor.shells == 0 and cast.finished, 'Cancelled preparation returning to idle never fires shell')
end
do
    local actor, ex, cast, step = create(docs.prepared)
    step(30)
    actor.staggered = true
    step(1)
    check(#actor.shells == 0 and cast.finished and cast.end_reason == 'interrupted (hit)', 'Hit interruption ends waiting without a shell')
end
do
    local actor, ex, cast, step = create(docs.prepared)
    step(20)
    actor.actions[0], actor.actions[1] = 'Job06_CastSalamander', 'UpperBodyDefault'
    actor.now = 21
    ex:update(1 / 120)
    check(#actor.shells == 0, 'At 120 Hz the gate advances by half a timeline frame')
    ex:update(1 / 120)
    check(#actor.shells == 1, 'At 120 Hz the shell follows within one 60 Hz timeline frame')
end
print(('Completed %d assertions. Game FSM, input and visual behavior require an in-game test.'):format(checks))
