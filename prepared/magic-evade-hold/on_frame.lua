local skill = ...
local buttons = skill.vars.magic_evade_buttons or {}
if #buttons == 0 then
    skill.log("Magic Evade: no held Skill1..Skill6 input detected; ending safely")
    skill.finish()
    return
end
for _, button in ipairs(buttons) do
    if not skill.button(button) then
        -- end.exit_action requests Job04_AbsoluteAvoidanceEnd on normal finish.
        skill.finish()
        return
    end
end
