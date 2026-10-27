-- One-shot, read-only metadata probe. Does not enable avoidance or change game state.
-- Output: reframework/data/VSB/diagnostics/magic_evade_probe.json
local runtime = require("DragonCore.game.runtime")
local OUTPUT = "VSB/diagnostics/magic_evade_probe.json"
local MAX_TYPES, MAX_PENDING, MAX_DEPTH = 160, 600, 3
local report = { probe_version=1, types={}, matches={}, errors={} }
local queue, known = {}, {}
local started, done, ticks, processed = false, false, 0, 0

local function interesting(s)
    s = tostring(s):lower()
    return s:find("avoid",1,true) or s:find("absolute",1,true) or s:find("feint",1,true)
end

local function enqueue(td, depth, root)
    if not td or depth > MAX_DEPTH or #queue >= MAX_PENDING then return end
    local name = td:get_full_name()
    if known[name] or not name:find("^app%.") then return end
    known[name] = true
    local lower = name:lower()
    local priority = root and 100 or (interesting(name) and 90 or (lower:find("human",1,true) and 50 or 0))
    queue[#queue+1] = { td=td, name=name, depth=depth, priority=priority }
end

local function seed(name)
    local ok, td = pcall(sdk.find_type_definition, name)
    if ok and td then enqueue(td, 0, true) end
end

local function describe(item)
    local out = { depth=item.depth, fields={}, methods={} }
    report.types[item.name] = out
    local td = item.td
    for _, field in ipairs(td:get_fields() or {}) do
        local ok, err = pcall(function()
            local ft = field:get_type()
            local text = field:get_name() .. " : " .. (ft and ft:get_full_name() or "?")
            out.fields[#out.fields+1] = text
            if interesting(text) then report.matches[#report.matches+1] = item.name .. "." .. text end
            enqueue(ft, item.depth+1)
        end)
        if not ok then report.errors[#report.errors+1] = item.name .. " field: " .. tostring(err) end
    end
    for _, method in ipairs(td:get_methods() or {}) do
        local ok, err = pcall(function()
            local params = {}
            for _, pt in ipairs(method:get_param_types() or {}) do params[#params+1] = pt:get_full_name() end
            local rt = method:get_return_type()
            local name = method:get_name()
            local text = name .. "(" .. table.concat(params, ", ") .. ") -> " .. (rt and rt:get_full_name() or "?")
            out.methods[#out.methods+1] = text
            if interesting(text) then report.matches[#report.matches+1] = item.name .. "." .. text end
            -- Inspect return-type metadata only. No listed getter or setter is invoked.
            if name:find("^get_") then enqueue(rt, item.depth+1) end
        end)
        if not ok then report.errors[#report.errors+1] = item.name .. " method: " .. tostring(err) end
    end
    table.sort(out.fields)
    table.sort(out.methods)
    enqueue(td:get_parent_type(), item.depth+1)
end

local function begin(actor)
    report.generated = os.date("!%Y-%m-%dT%H:%M:%SZ")
    report.tdb_version = sdk.get_tdb_version()
    report.current_actions = { full=actor:current_action(0), upper=actor:current_action(1) }
    report.held_skill_inputs = {}
    for i=1,6 do report.held_skill_inputs["Skill"..i] = actor:button_down("Skill"..i) end
    for _, name in ipairs({
        "app.Human", "app.Character", "app.PlayerInputProcessorDetail", "app.ActionManager",
        "app.HumanSkillContext", "app.HumanActionParameter", "app.HumanJobContext", "app.CharacterInput.Flag",
    }) do seed(name) end
    for _, obj in pairs({actor.human,actor.character,actor.action_manager,actor.hit}) do
        if obj and obj.get_type_definition then enqueue(obj:get_type_definition(),0,true) end
    end
    started = true
end

local function save()
    table.sort(report.matches)
    report.types_inspected = processed
    report.truncated = #queue > 0
    local ok, result = pcall(json.dump_file, OUTPUT, report)
    done = true
    if ok and result ~= false then log.info("[FH Magic Evade probe] Saved " .. OUTPUT)
    else log.error("[FH Magic Evade probe] Could not save report: " .. tostring(result)) end
end

re.on_frame(function()
    if done then return end
    local ok, err = pcall(function()
        ticks = ticks+1
        if not started then
            if ticks % 60 ~= 0 then return end
            local actor = runtime.player()
            if not actor or not actor:valid() then return end
            begin(actor)
        end
        for _=1,4 do
            if #queue == 0 or processed >= MAX_TYPES then save(); return end
            table.sort(queue,function(a,b) return a.priority > b.priority end)
            local item = table.remove(queue,1)
            processed = processed+1
            local got, failure = pcall(describe,item)
            if not got then report.errors[#report.errors+1] = item.name .. ": " .. tostring(failure) end
        end
    end)
    if not ok then
        report.errors[#report.errors+1] = tostring(err)
        save()
    end
end)
