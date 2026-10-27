local skill = ...
local state = skill.vars
local now = os.clock()
state.vsb_cancel_started = state.vsb_cancel_started or now

local full, upper = skill.action(0), skill.action(1)
local function contains(name, part)
    return type(name) == "string" and name:lower():find(part, 1, true) ~= nil
end

-- FAMILY is replaced per spell. Covers Prepare, Ready, SpellStock, Cast and follow-ups.
local active = contains(full, "__FAMILY__") or contains(upper, "__FAMILY__")
if active then
    state.vsb_cancel_seen = true
    state.vsb_cancel_left = nil
    return
end

-- Missing game data does not establish cancellation.
if full == nil or upper == nil then return end
-- Let an asynchronous request take effect, including an immediate retry after cancellation.
if not state.vsb_cancel_seen and now - state.vsb_cancel_started < 0.25 then return end

if state.vsb_cancel_seen and (contains(full, "cancel") or contains(upper, "cancel")) then
    skill.finish()
    return
end

-- Brief gaps between layers/actions must not end a normal spell transition.
state.vsb_cancel_left = state.vsb_cancel_left or now
if now - state.vsb_cancel_left >= 0.10 then skill.finish() end
