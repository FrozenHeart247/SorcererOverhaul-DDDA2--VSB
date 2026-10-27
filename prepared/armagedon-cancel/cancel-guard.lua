local skill = ...
local state = skill.vars
local now = os.clock()
state.vsb_cancel_started = state.vsb_cancel_started or now

local full, upper = skill.action(0), skill.action(1)
local function contains(name, part)
    return type(name) == "string" and name:lower():find(part, 1, true) ~= nil
end

-- A released spell owns its remaining sequence, even after the cast animation ends.
if contains(full, "job06_castmeteorfall") or contains(upper, "job06_castmeteorfall") then
    state.armagedon_released = true
end
if state.armagedon_released then return end

-- Includes PrepareMeteorFall, ReadyMeteorFall and its SpellStock variants.
local active = contains(full, "meteorfall") or contains(upper, "meteorfall")
if active then
    state.vsb_cancel_seen = true
    state.vsb_cancel_left = nil
    return
end

if full == nil or upper == nil then return end
if not state.vsb_cancel_seen and now - state.vsb_cancel_started < 0.25 then return end

if state.vsb_cancel_seen and (contains(full, "cancel") or contains(upper, "cancel")) then
    skill.finish()
    return
end

state.vsb_cancel_left = state.vsb_cancel_left or now
if now - state.vsb_cancel_left >= 0.10 then skill.finish() end
