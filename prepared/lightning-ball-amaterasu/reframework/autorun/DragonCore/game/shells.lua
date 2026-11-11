-- VSB/game/shells.lua — every shell VSB spawns, followed until it is gone (sdk).
--
-- Skill Maker's methods (SkillMaker.lua):
--   find the shell      ShellManager.<InstantiatedShellDict>[request id].<Shell> (L5407-5417)
--   child shells        hashes from the param's _ShellAdditionalParameter (L5434-5450), then shells in
--                       ShellManager.ShellList with that <ShellParamId> and a later <RequestId> (L5550-5567)
--   speed / damage      app.WorkRate NextRateValue / NextApplyRate, HitCtrl.<AttackRate>, every frame (L5499-5501)
--   follow              set the shell's transform from the joint / character / previous shell (L5518-5548)
--   position / hit      last child (else the shell): position, rotation, HitSubstance / <TerrainHitResult> (L5339-5348)
--   sound off           stop the WwiseContainer's triggers (L5460-5467)
--   cosmetic            <ColliderStep> = 99999, request collider off (L5469-5472)
--   size / lifetime /   timed edit of the SHARED ShellBaseParam, restored 0.1 s later (change_shell_udata L1554).
--   omen / ground       VSB saves only the 7 fields it changes and restores them on script reset too.
--   keep alive          app.Shell.checkFinish returns false until the lifetime is up (L6436-6446);
--                       hooked only when a skill first uses it.
-- Cost: nothing while no VSB shell lives; the checkFinish hook returns at once without keep-alive shells.
local shellopts = require("DragonCore.core.shellopts")
local mathx = require("DragonCore.game.mathx")
local hooks = require("DragonCore.game.hooks")
local hits = require("DragonCore.game.hits")
local enums = require("DragonCore.game.enums")

local shells = {}

local DAMAGE_TYPES = "app.AttackUserData.DamageTypeEnum"

shells.cap = 120          -- seconds a VSB shell may live (0 = no cap); set from the config
shells.last_error = nil

local RESTORE_AFTER = 0.1 -- seconds before a shared ShellBaseParam gets its own values back
local FIND_TIMEOUT = 3    -- seconds to wait for a requested shell to appear
local BASE_FIELDS = { "UseScale", "Scale", "UseLifeTime", "LifeTime", "UseOmenPhase", "OmenTime", "UseSetLand" }

local records = {}    -- tracked spawns
local claimed = {}    -- shell address -> true (each shell belongs to one record)
local keep_alive = {} -- shell address -> record
local pending = {}    -- ShellBaseParam address -> { base, saved, at }
local hooked = false

local function now() return os.clock() end

---------------------------------------------------------------------------
-- Timed edit of a shared ShellBaseParam
---------------------------------------------------------------------------
function shells.override_base(base, overrides)
    local key = base:get_address()
    local p = pending[key]
    if not p then -- the first edit saves the shell's own values; later ones only extend the timer
        local saved = {}
        for _, f in ipairs(BASE_FIELDS) do saved[f] = base[f] end
        p = { base = base, saved = saved }
        pending[key] = p
    end
    p.at = now()
    -- Field by field: a kind of shell that lacks one of them (no ground setting, say) still gets
    -- the others and still spawns; before, that one error stopped the whole shell.
    for f, v in pairs(overrides) do
        local ok = pcall(function() base[f] = (f == "Scale") and mathx.vec3(v) or v end)
        if not ok then shells.last_error = ("this shell has no '%s' setting; left as it is"):format(f) end
    end
end

function shells.restore_bases(force)
    local t = now()
    for key, p in pairs(pending) do
        if force or t - p.at > RESTORE_AFTER then
            for f, v in pairs(p.saved) do pcall(function() p.base[f] = v end) end
            pending[key] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Keep alive (checkFinish)
---------------------------------------------------------------------------
local function install_finish_hook()
    if hooked then return end
    hooked = true
    hooks.install("app.Shell", "checkFinish", function(args)
        local st = thread.get_hook_storage()
        st.vsb_keep = nil
        if next(keep_alive) == nil then return end
        local shell = sdk.to_managed_object(args[2])
        local r = shell and keep_alive[shell:get_address()]
        if not r or #r.children > 0 or shell["<TerrainHitResult>k__BackingField"] then return end
        local timer = shell["<LiveTimer>k__BackingField"]
        if timer and timer._FinishFrame ~= math.huge and timer._ElapsedFrame < timer._FinishFrame then
            st.vsb_keep = true
        end
    end, function(ret)
        local st = thread.get_hook_storage()
        if st.vsb_keep then
            st.vsb_keep = nil
            return sdk.to_ptr(false)
        end
        return ret
    end)
end

---------------------------------------------------------------------------
-- Shell parts (the shell and its children)
---------------------------------------------------------------------------
local function get_component(go, type_name)
    return go:call("getComponent(System.Type)", sdk.typeof(type_name))
end

local function mute(shell, go)
    local wwise = shell["<WwiseContainer>k__BackingField"]
    if not wwise then return end
    local list = wwise._TriggerInfoList
    local items, size = list and list._items, list and list._size or 0
    for i = 0, size - 1 do
        local e = items[i]
        if e then wwise:call("stopTriggered(System.UInt32, via.GameObject, System.UInt32)", e._TriggerId, go, 0) end
    end
    wwise:call(".cctor()")
    wwise:call(".ctor()")
end

local function make_cosmetic(shell)
    shell["<ColliderStep>k__BackingField"] = 99999
    shell:get_HitCtrl():get_CachedRequestSetCollider():set_Enabled(false)
end

---------------------------------------------------------------------------
-- Colour (node.color = { r, g, b, a }, 0-255). A port of Skill Maker's change_efx2_color
-- (SkillMaker.lua L1489-1544, by alphaZomega): the shell's EffectManager2.CreatedEffectDataList holds
-- the effects it created; each new one gets the colour on its effect players (set_Color) and as its
-- root colour (setRootColor), once. Run every frame while the shell lives, so effects that appear
-- later (the omen phase, Skill Maker's requestOmenEffect hook) are coloured too.
---------------------------------------------------------------------------
-- Counters for VSB's Dev panel: shell parts with a colour, effects coloured, the last error.
shells.color_info = { parts = 0, effects = 0, last_error = nil }

-- The elements of a game list or array (after _ScriptCore's lua_get_array, Skill Maker's helper):
-- _items (or the object itself); an array gives get_elements(); else get_Count and indexing.
-- In game (2026-10-25) the inner list had get_Count but no callable get_Item.
local function elements(obj)
    if not obj then return {} end
    local src = obj._items or obj.mItems or obj
    if src.get_elements then
        local ok, els = pcall(src.get_elements, src)
        if ok and type(els) == "table" then return els end
    end
    local out = {}
    local ok, n = pcall(src.call, src, "get_Count")
    for i = 0, (ok and tonumber(n) or 0) - 1 do out[#out + 1] = src[i] end
    return out
end

-- The shell's effect manager: its EffectManager2 field (Skill Maker), else the component on its game
-- object. In game (2026-10-25) the field was still empty on the frame the shell was found, so it is
-- looked for again every frame until it is there.
local function effect_manager_of(p)
    local m = p.shell["<EffectManager2>k__BackingField"]
    if m then return m end
    return p.go:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
end

local function make_color(rgba)
    local c = ValueType.new(sdk.find_type_definition("via.Color"))
    c:call(".ctor(via.vec4)", Vector4f.new((rgba[1] or 255) / 255, (rgba[2] or 255) / 255, (rgba[3] or 255) / 255,
        (rgba[4] or 255) / 255))
    return c
end

-- Skill Maker L1512-1524: the effect players of each created effect, then its root colour.
local function color_effect(c_effect, coloring)
    local dict = c_effect.CreatedEffects
    for _, e in pairs(dict and dict._entries or {}) do
        local players = e and e.value
        if players and players._items then
            for _, player in pairs(players._items) do
                if not player then break end
                pcall(player.set_Color, player, coloring)
            end
        end
    end
    c_effect:setRootColor(coloring)
end

-- Skill Maker L1506-1511: pairs over CreatedEffectDataList._items, then each entry's list.
local function color_pass(r, p)
    local list = p.efx2.CreatedEffectDataList
    if not list then return end
    for _, data in pairs(list._items) do
        if not data then break end
        for _, c_effect in pairs(elements(data.list)) do
            if not c_effect then break end
            if not c_effect.IsFinished then
                local addr = c_effect:get_address()
                if not p.colored[addr] then
                    p.colored[addr] = true
                    local ok, err = pcall(color_effect, c_effect, r.coloring)
                    if ok then shells.color_info.effects = shells.color_info.effects + 1
                    else shells.color_info.last_error = tostring(err) end
                end
            end
        end
    end
end

local function add_part(r, shell, is_child)
    local addr = shell:get_address()
    if claimed[addr] then return end
    claimed[addr] = true
    local go = shell:get_GameObject()
    local part = { shell = shell, go = go, xform = go:get_Transform(), addr = addr, child = is_child }
    local ok, wr = pcall(get_component, go, "app.WorkRate")
    part.work_rate = ok and wr or nil
    r.parts[#r.parts + 1] = part
    if is_child then r.children[#r.children + 1] = part end
    local node = r.node
    if node.mute then pcall(mute, shell, go) end
    if node.cosmetic then pcall(make_cosmetic, shell) end
    if type(node.color) == "table" then
        local ok, err = pcall(function() r.coloring = r.coloring or make_color(node.color) end)
        if ok then part.want_color = true else shells.color_info.last_error = tostring(err) end
    end
    if node.keep_alive and (node.lifetime or 0) > 0 then
        keep_alive[addr] = r
        install_finish_hook()
    end
    -- Damage type: the shell's own Hit controller is the attacker of its hits (Skill Maker L5478).
    if node.damage_type and node.damage_type ~= "" then
        local value = enums.value(DAMAGE_TYPES, node.damage_type)
        if value ~= nil then
            local ok, token = pcall(function() return hits.damage_type_start(shell:get_HitCtrl(), value) end)
            part.damage_token = ok and token or nil
        end
    end
    -- Damage multiplier of the shell's hits: on the final damage (game/hits.lua), the same attacker rule.
    if r.attack and r.attack ~= 1 then
        local ok, token = pcall(function() return hits.damage_scale_start(shell:get_HitCtrl(), r.attack) end)
        part.scale_token = ok and token or nil
    end
    -- Element and status of the shell's hits (the same attacker rule).
    local spec = hits.effect_spec(node)
    if spec then
        local ok, token = pcall(function() return hits.effect_start(shell:get_HitCtrl(), spec) end)
        part.effect_token = ok and token or nil
    end
end

local function release_part(p)
    p.dead = true
    claimed[p.addr] = nil
    keep_alive[p.addr] = nil
    if p.effect_token then
        hits.effect_stop(p.effect_token)
        p.effect_token = nil
    end
    if p.damage_token then
        hits.damage_type_stop(p.damage_token)
        p.damage_token = nil
    end
    if p.scale_token then
        hits.damage_scale_stop(p.scale_token)
        p.scale_token = nil
    end
end

local function valid(p)
    local ok, v = pcall(function() return p.shell:get_Valid() and p.xform:get_Valid() end)
    return ok and v == true
end

local function hit_something(shell)
    local ok, hit = pcall(function()
        return shell.HitSubstance or shell["<TerrainHitResult>k__BackingField"]
    end)
    return ok and hit ~= nil and hit ~= false and hit ~= 0
end

---------------------------------------------------------------------------
-- Child shells
---------------------------------------------------------------------------
local function as_hash(h)
    if type(h) == "number" then return h end
    local ok, v = pcall(function() return h._HasValue and h._Value end)
    return ok and type(v) == "number" and v or nil
end

local function child_hashes(param)
    local out = {}
    local list = param._ShellAdditionalParameter
    for _, ap in pairs(list and list._items or {}) do
        if ap then
            out[#out + 1] = as_hash(ap._ShellParamIDHash)
            local arr = ap._ShellGeneratorConditionInfos or ap._ShellGeneratorTimerInfos or ap._GenerationDatas
            arr = arr and (arr._items or arr)
            for _, el in pairs(arr or {}) do
                if el then out[#out + 1] = as_hash(el._ShellIDHash) or as_hash(el._ShellParamIDHash) end
            end
        end
    end
    local set = {}
    for _, h in ipairs(out) do if h then set[h] = true end end
    return set
end

-- Child params get the same size / lifetime edit as the shell (L5443-5447).
local function override_children(r)
    local items = r.udata.ShellParams
    local size = items._size or 0
    for i = 0, size - 1 do
        local p = items._items[i]
        if p and r.hashes[p._ShellParamIdHash] then
            shells.override_base(p._ShellParameterBase.ShellBaseParam, r.overrides)
        end
    end
end

local function scan_children(r, mgr)
    local list = mgr.ShellList
    local items, size = list and list._items, list and list._size or 0
    for i = 0, size - 1 do
        local s = items[i]
        if s and r.hashes[s["<ShellParamId>k__BackingField"]] and s["<RequestId>k__BackingField"] > r.req_id
            and not claimed[s:get_address()] then
            add_part(r, s, true)
        end
    end
end

---------------------------------------------------------------------------
-- Follow (joint / character / previous shell)
---------------------------------------------------------------------------
-- Returns pos, rotation to apply, rotation for the offset; nil when there is nothing to follow.
local function anchor(r)
    if r.follow == "none" then return nil end
    if r.follow == "until_hit" and (r.hit or (r.from and r.from.hit)) then return nil end
    local cast = r.node.cast or {}
    if cast.mode == "previous" then
        local f = r.from
        if not (f and f.pos) then return nil end
        return f.pos, f.rot, f.rot
    end
    if not r.actor:valid() then return nil end
    local tr = r.actor.game_object:get_Transform()
    local joint = cast.joint and tr:getJointByName(cast.joint) or nil
    local at = (cast.mode == "joint" and joint) or tr
    local facing = (cast.face == "joint" and joint) or tr
    return at:get_Position(), facing:get_Rotation(), tr:get_Rotation()
end

local function apply_follow(r, p, pos, rot, offset_rot)
    local cast = r.node.cast or {}
    local at = pos
    if cast.offset then at = at + mathx.rotate(mathx.vec3(cast.offset), offset_rot) end
    p.xform:set_Position(at)
    if cast.follow_rotation ~= false and cast.face ~= "crosshair" and rot then
        p.xform:set_Rotation(cast.rotation and (rot * mathx.degrees_quat(cast.rotation)) or rot)
    end
end

---------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------
local function find_instance(mgr, req_id)
    local dict = mgr["<InstantiatedShellDict>k__BackingField"]
    if dict and dict:ContainsKey(req_id) then
        local entry = dict[req_id]
        return entry and entry["<Shell>k__BackingField"] or nil
    end
    return nil
end

local function on_found(r, shell)
    add_part(r, shell, false)
    local ok, set = pcall(child_hashes, r.param)
    r.hashes = ok and set or {}
    if r.overrides and next(r.hashes) then pcall(override_children, r) end
end

local function update_parts(r, t)
    local alive, final = 0, nil
    -- Some native shells ignore ShellBaseParam.LifeTime. Bound this tracked spawn and
    -- its children by an explicit node lifetime as well as the global safety cap.
    local age = t - r.born
    local expired = shellopts.expired(age, shells.cap) or shellopts.expired(age, r.node.lifetime)
    local pos, rot, offset_rot = anchor(r)
    for _, p in ipairs(r.parts) do
        if not p.dead then
            if not valid(p) then
                release_part(p)
            elseif expired then
                pcall(function() p.go:destroy(p.go) end)
                release_part(p)
            else
                alive, final = alive + 1, p
                if r.speed and p.work_rate then
                    p.work_rate.NextRateValue = r.speed
                    p.work_rate.NextApplyRate = r.speed
                end
                if pos and (not p.child or (r.node.cast or {}).follow_children) then apply_follow(r, p, pos, rot, offset_rot) end
                if p.want_color and not p.efx2 then
                    local okm, m = pcall(effect_manager_of, p)
                    if okm and m then
                        p.efx2, p.colored = m, {}
                        shells.color_info.parts = shells.color_info.parts + 1
                    end
                end
                if p.efx2 then -- every frame: effects that appeared since (omen, trails)
                    local okc, cerr = pcall(color_pass, r, p)
                    if not okc then shells.color_info.last_error = tostring(cerr) end
                end
                if keep_alive[p.addr] and t - r.born > (r.node.lifetime or 0) then keep_alive[p.addr] = nil end
            end
        end
    end
    return alive, final
end

-- Returns true while the record should stay tracked.
local function update_record(r, mgr, t)
    if not r.found then
        local shell = r.req_id and find_instance(mgr, r.req_id)
        if not shell then return t - r.born < FIND_TIMEOUT end
        r.found = true
        on_found(r, shell)
    end
    if next(r.hashes) then scan_children(r, mgr) end
    local alive, final = update_parts(r, t)
    if final then
        r.pos, r.rot = final.xform:get_Position(), final.xform:get_Rotation()
        r.hit = r.hit or hit_something(final.shell)
    end
    return alive > 0
end

local function release(r)
    for _, p in ipairs(r.parts) do if not p.dead then release_part(p) end end
end

-- Registers a requested shell. spawn: { req_id, node, actor, udata, param, overrides, pos, rot, from }.
-- pos / rot start as the spawn position, so "spawn at the previous shell" works before it appears.
function shells.track(spawn)
    local r = spawn
    r.born, r.parts, r.children, r.hashes = now(), {}, {}, {}
    r.speed, r.attack = shellopts.rates(r.node)
    r.follow = shellopts.follow_mode(r.node.cast)
    records[#records + 1] = r
    return r
end

-- Once per frame, after the animation update (LateUpdateBehavior). cap: lifetime cap in seconds.
function shells.update(cap)
    if cap then shells.cap = cap end
    if next(pending) then shells.restore_bases(false) end
    if #records == 0 then return end
    local mgr = sdk.get_managed_singleton("app.ShellManager")
    if not mgr then return end
    local t = now()
    local kept = {}
    for _, r in ipairs(records) do
        local ok, keep = pcall(update_record, r, mgr, t)
        if ok and keep then
            kept[#kept + 1] = r
        else
            if not ok then shells.last_error = tostring(keep) end
            release(r)
        end
    end
    records = kept
end

function shells.count() return #records end

-- Destroys every shell VSB is tracking (editor "Destroy shells"). Returns how many.
function shells.destroy_tracked()
    local n = 0
    for _, r in ipairs(records) do
        for _, p in ipairs(r.parts or {}) do
            if not p.dead and pcall(function() p.go:destroy(p.go) end) then n = n + 1 end
        end
    end
    return n
end

-- Script reset: give every shared ShellBaseParam its own values back, stop tracking.
function shells.shutdown()
    shells.restore_bases(true)
    for _, r in ipairs(records) do release(r) end
    records, keep_alive = {}, {}
end

return shells
