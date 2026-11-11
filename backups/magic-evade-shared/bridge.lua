-- VSB event integration; native calls are injected so lifecycle behavior can be verified outside the game.
local bridge = {}
local Bridge = {}
Bridge.__index = Bridge
local UUID = "3f67be32-a628-4ec1-8e8a-0f13b70725cc"

function bridge.new(native, report)
    return setmetatable({native=native, report=report or function() end, records={}, pending={}, unsub={}},Bridge)
end

function Bridge:snapshot(token)
    if not token or not self.native.describe then return nil end
    local ok,result=pcall(self.native.describe,token)
    return ok and result or {error=tostring(result)}
end

local function mark_stop(cast, reason)
    cast.magic_evade_native_stop = reason
    if cast.script_api then cast.script_api.vars.magic_evade_native_stop = reason end
end

function Bridge:release(record, reason)
    if not record.token or not record.token.owned then return true end
    local ok, released, detail, active = pcall(self.native.release,record.token)
    if ok and released then
        self.report("stop",{reason=reason,detail=detail,confirmed=active==false,active=active})
        return true
    end
    self.report("clear_failed",{reason=reason,detail=tostring(ok and detail or released),confirmed=false})
    return false
end

function Bridge:started(cast)
    if cast.entry.pack_id ~= "fh_sorc" or cast.doc.uuid ~= UUID then return end
    local record = {cast=cast,actor=cast.actor,buttons={}}
    self.records[cast] = record
    for i=1,6 do
        local name = "Skill"..i
        if cast.actor:button_down(name) then record.buttons[#record.buttons+1]=name end
    end
    if #record.buttons==0 then
        mark_stop(cast,"no held skill input")
        self.report("start_failed",{reason="no held Skill1..Skill6 input"})
        return
    end
    -- Without an animation request, observe the real current action for VSB's normal hit checks.
    local has_action=false
    for _,node in ipairs(cast.doc.timeline or {}) do
        if node.type=="action" and node.enabled~=false then has_action=true; break end
    end
    if not has_action and cast.ctx then
        local current=cast.actor:current_action(0)
        if current and current~="" then cast.ctx:mark_action(current,0) end
    end
    local ok, token, why = pcall(self.native.acquire,cast.actor,cast.level)
    if ok then record.token=token end
    if not ok or not token or why then
        local reason = tostring(ok and why or token)
        mark_stop(cast,reason)
        self.report("start_failed",{reason=reason})
        return
    end
    self.report("start",{confirmed=true,active=true,owned=token.owned,buttons=record.buttons,
        level=cast.level,snapshot=self:snapshot(token)})
end

function Bridge:ended(cast, reason)
    local record = self.records[cast]
    if not record then return end
    self.records[cast] = nil
    if not self:release(record,reason) then
        record.reason,record.attempts=reason,0
        self.pending[#self.pending+1]=record
    end
end

function Bridge:tick()
    for cast,record in pairs(self.records) do
        if not record.actor:valid() then
            mark_stop(cast,"character changed")
            self:release(record,"character changed")
        elseif cast.magic_evade_native_stop then
            mark_stop(cast,cast.magic_evade_native_stop)
            if record.token and record.token.owned then self:release(record,"activation failed") end
        else
            local released = false
            for _,button in ipairs(record.buttons) do
                if not record.actor:button_down(button) then released=true; break end
            end
            if released then
                self:release(record,"button released")
                mark_stop(cast,"button released")
            elseif record.token then
                local ok, active, why=pcall(self.native.active,record.token)
                if not ok or active~=true then
                    mark_stop(cast,tostring(ok and (why or "native buff ended") or active))
                    self.report("native_ended",{reason=cast.magic_evade_native_stop,snapshot=self:snapshot(record.token)})
                    self:release(record,"native buff ended")
                end
            end
        end
    end
    for i=#self.pending,1,-1 do
        local record=self.pending[i]
        record.attempts=record.attempts+1
        if self:release(record,record.reason) or record.attempts>=3 then table.remove(self.pending,i) end
    end
end

function Bridge:attach(bus)
    if self.bus==bus then return end
    self:shutdown()
    self.bus=bus
    self.unsub={
        bus:on("cast_start",function(cast) self:started(cast) end),
        bus:on("cast_end",function(cast,reason) self:ended(cast,reason) end),
    }
end

function Bridge:shutdown()
    for _,unsub in ipairs(self.unsub) do unsub() end
    self.unsub={}
    for cast,record in pairs(self.records) do
        self:release(record,"companion shutdown")
        mark_stop(cast,"companion shutdown")
    end
    for _,record in ipairs(self.pending) do self:release(record,"companion shutdown") end
    if self.native.shutdown then self.native.shutdown() end
    self.records,self.pending,self.bus={},{},nil
end

return bridge
