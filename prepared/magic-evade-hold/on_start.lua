local skill = ...
local buttons = {}
for i = 1, 6 do
    local button = "Skill" .. i
    if skill.button(button) then buttons[#buttons + 1] = button end
end
-- Capture once: another skill button must not take over this hold later.
skill.vars.magic_evade_buttons = buttons
