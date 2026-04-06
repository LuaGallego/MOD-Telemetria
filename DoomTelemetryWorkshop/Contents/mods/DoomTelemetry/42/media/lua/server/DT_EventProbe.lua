require "DT_Shared"

if not isServer() then
    return
end

print("[DT_PROBE] arquivo carregado")

local lastTick = 0
local lastMinute = 0
local lastTenMinutes = 0

local function ProbeOnTick()
    local now = os.time()
    if (now - lastTick) >= 5 then
        lastTick = now
        print("[DT_PROBE] OnTick vivo em " .. tostring(now))
    end
end

local function ProbeEveryOneMinute()
    local now = os.time()
    if now ~= lastMinute then
        lastMinute = now
        print("[DT_PROBE] EveryOneMinute vivo em " .. tostring(now))
    end
end

local function ProbeEveryTenMinutes()
    local now = os.time()
    if now ~= lastTenMinutes then
        lastTenMinutes = now
        print("[DT_PROBE] EveryTenMinutes vivo em " .. tostring(now))
    end
end

Events.OnTick.Add(ProbeOnTick)
Events.EveryOneMinute.Add(ProbeEveryOneMinute)
Events.EveryTenMinutes.Add(ProbeEveryTenMinutes)