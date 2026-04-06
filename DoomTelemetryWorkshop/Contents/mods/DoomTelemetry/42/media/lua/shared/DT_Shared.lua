DT = DT or {}

DT.MOD_ID = "DoomTelemetry"
DT.QUEUE_FILE = "doomtelemetry_queue.jsonl"
DT.DEBUG = true
DT.SCHEMA_VERSION = 1
DT.SOURCE = "doomtelemetry_mod"
DT.SERVER_ID = "doom_project_main"
DT.MOD_VERSION = "1.0.0"

DT._event_seq = DT._event_seq or 0

function DT.NormalizeSteamID(value)
    if value == nil then
        return ""
    end

    local s = tostring(value)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^steam:", "")
    s = s:gsub("^Steam:", "")
    s = s:gsub("^STEAM:", "")

    -- IMPORTANTE:
    -- SteamID64 deve ser tratado como string.
    -- Não usar tonumber() aqui para evitar perda de precisão.
    return s
end

function DT.Log(msg)
    if DT.DEBUG then
        print("[DoomTelemetry] " .. tostring(msg))
    end
end

function DT.Now()
    return os.time()
end

function DT.NextEventId()
    DT._event_seq = (DT._event_seq or 0) + 1
    if DT._event_seq > 999999 then
        DT._event_seq = 1
    end

    local rand = 0
    if ZombRand then
        rand = ZombRand(100000, 999999)
    else
        rand = math.random(100000, 999999)
    end

    return tostring(DT.SERVER_ID)
        .. "_"
        .. tostring(os.time())
        .. "_"
        .. tostring(rand)
        .. "_"
        .. tostring(DT._event_seq)
end

function DT.SafeCall(fn, default)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return default
end

function DT.EscapeString(s)
    if s == nil then return "" end
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return s
end

function DT.IsArray(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    local maxIndex = 0
    local count = 0

    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k > maxIndex then
            maxIndex = k
        end
        count = count + 1
    end

    if count == 0 then
        return true
    end

    return maxIndex == count
end

function DT.JsonValue(v)
    local t = type(v)

    if v == nil then
        return "null"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "0"
        end
        return string.format("%.0f", v) == tostring(v) and string.format("%.0f", v) or tostring(v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        return DT.EncodeJson(v)
    else
        return "\"" .. DT.EscapeString(v) .. "\""
    end
end

function DT.EncodeJson(tbl)
    if type(tbl) ~= "table" then
        return DT.JsonValue(tbl)
    end

    local parts = {}

    if DT.IsArray(tbl) then
        table.insert(parts, "[")
        for i = 1, #tbl do
            if i > 1 then table.insert(parts, ",") end
            table.insert(parts, DT.JsonValue(tbl[i]))
        end
        table.insert(parts, "]")
    else
        table.insert(parts, "{")
        local first = true
        for k, v in pairs(tbl) do
            if not first then table.insert(parts, ",") end
            first = false
            table.insert(parts, "\"" .. DT.EscapeString(k) .. "\":" .. DT.JsonValue(v))
        end
        table.insert(parts, "}")
    end

    return table.concat(parts)
end

function DT.AppendJsonLine(filename, data)
    local writer = getFileWriter(filename, true, true)
    if not writer then
        DT.Log("Falha ao abrir arquivo: " .. tostring(filename))
        return false
    end

    writer:write(DT.EncodeJson(data))
    writer:write("\n")
    writer:close()
    return true
end

function DT.BuildEventEnvelope(eventType, rootData, payloadData)
    local root = {}

    if type(rootData) == "table" then
        for k, v in pairs(rootData) do
            root[k] = v
        end
    end

    root.event_id = DT.NextEventId()
    root.event_type = tostring(eventType or "unknown")
    root.schema_version = DT.SCHEMA_VERSION
    root.source = DT.SOURCE
    root.server_id = DT.SERVER_ID
    root.mod_version = DT.MOD_VERSION
    root.timestamp = root.timestamp or os.time()
    root.server_timestamp = os.time()
    root.payload = payloadData or {}

    return root
end

function DT.GetPlayerSteamID(player)
    local steamID = ""

    if player and player.getSteamID then
        local sid = player:getSteamID()
        if sid then
            steamID = DT.NormalizeSteamID(sid)
        end
    end

    if steamID == "" and player and player.getUsername and getSteamIDFromUsername then
        local username = player:getUsername()
        if username and username ~= "" then
            local sid = getSteamIDFromUsername(username)
            if sid then
                steamID = DT.NormalizeSteamID(sid)
            end
        end
    end

    if steamID == "" and getCurrentUserSteamID then
        local sid = getCurrentUserSteamID()
        if sid then
            steamID = DT.NormalizeSteamID(sid)
        end
    end

    return steamID
end

function DT.GetPlayerRuntimeId(player)
    if not player then
        return -1
    end

    local runtimeId = DT.SafeCall(function()
        if player.getPlayerNum then
            return tonumber(player:getPlayerNum())
        end
        return nil
    end, nil)

    if runtimeId ~= nil then
        return runtimeId
    end

    runtimeId = DT.SafeCall(function()
        if player.getOnlineID then
            return tonumber(player:getOnlineID())
        end
        return nil
    end, nil)

    return runtimeId or -1
end

function DT.GetCharacterName(player)
    if not player then return "" end

    local username = player.getUsername and (player:getUsername() or "") or ""
    local descriptor = player.getDescriptor and player:getDescriptor() or nil
    if not descriptor then
        return username
    end

    local forename = descriptor.getForename and (descriptor:getForename() or "") or ""
    local surname = descriptor.getSurname and (descriptor:getSurname() or "") or ""
    local full = (forename .. " " .. surname):gsub("^%s+", ""):gsub("%s+$", "")

    if full == "" then
        return username
    end
    return full
end

function DT.GetProfession(player)
    if not player then return "" end

    local descriptor = player.getDescriptor and player:getDescriptor() or nil
    if descriptor then
        if descriptor.getProfession then
            local p = descriptor:getProfession()
            if p then return tostring(p) end
        end
        if descriptor.getCharacterProfession then
            local p = descriptor:getCharacterProfession()
            if p then return tostring(p) end
        end
    end

    return ""
end

function DT.GetTraitsArray(player)
    local out = {}

    if not player then
        return out
    end

    if player.getTraits then
        local traits = player:getTraits()
        if traits and traits.size then
            for i = 0, traits:size() - 1 do
                table.insert(out, tostring(traits:get(i)))
            end
        end
    end

    return out
end

function DT.GetTraitsString(player)
    local arr = DT.GetTraitsArray(player)
    return table.concat(arr, ",")
end

function DT.GetInventoryWeight(player)
    if not player or not player.getInventory then
        return 0
    end

    local inv = player:getInventory()
    if not inv then
        return 0
    end

    local weight = DT.SafeCall(function()
        if inv.getCapacityWeight then
            return tonumber(inv:getCapacityWeight())
        end
        return nil
    end, nil)

    if weight ~= nil then
        return tonumber(string.format("%.2f", weight))
    end

    weight = DT.SafeCall(function()
        if inv.getContentsWeight then
            return tonumber(inv:getContentsWeight())
        end
        return nil
    end, nil)

    if weight ~= nil then
        return tonumber(string.format("%.2f", weight))
    end

    return 0
end

function DT.GetCarryCapacity(player)
    if not player then
        return 0
    end

    local cap = DT.SafeCall(function()
        if player.getMaxWeight then
            return tonumber(player:getMaxWeight())
        end
        return nil
    end, nil)

    if cap ~= nil then
        return tonumber(string.format("%.2f", cap))
    end

    cap = DT.SafeCall(function()
        if player.getMaxWeightBase then
            return tonumber(player:getMaxWeightBase())
        end
        return nil
    end, nil)

    if cap ~= nil then
        return tonumber(string.format("%.2f", cap))
    end

    return 0
end

function DT.GetIsInVehicle(player)
    if not player then
        return false
    end

    return DT.SafeCall(function()
        if player.getVehicle then
            return player:getVehicle() ~= nil
        end
        return false
    end, false)
end

function DT.GetIsAsleep(player)
    if not player then
        return false
    end

    return DT.SafeCall(function()
        if player.isAsleep then
            return player:isAsleep() and true or false
        end
        return false
    end, false)
end

function DT.GetIsOutdoors(player)
    if not player then
        return false
    end

    return DT.SafeCall(function()
        local sq = player:getSquare()
        if not sq then
            return false
        end
        return sq:getBuilding() == nil
    end, false)
end

function DT.GetBuildingName(player)
    if not player then
        return ""
    end

    return DT.SafeCall(function()
        local sq = player:getSquare()
        if not sq then
            return ""
        end

        local building = sq:getBuilding()
        if not building then
            return ""
        end

        local def = building:getDef()
        if def and def.getName then
            return tostring(def:getName() or "")
        end

        return ""
    end, "")
end

function DT.GetVehicleData(player)
    local out = {
        is_in_vehicle = false,
        vehicle_id = "",
        vehicle_script = "",
        vehicle_speed = 0
    }

    if not player then
        return out
    end

    local vehicle = DT.SafeCall(function()
        if player.getVehicle then
            return player:getVehicle()
        end
        return nil
    end, nil)

    if not vehicle then
        return out
    end

    out.is_in_vehicle = true

    out.vehicle_id = DT.SafeCall(function()
        if vehicle.getId then
            return tostring(vehicle:getId())
        end
        return ""
    end, "")

    out.vehicle_script = DT.SafeCall(function()
        if vehicle.getScriptName then
            return tostring(vehicle:getScriptName() or "")
        end
        return ""
    end, "")

    out.vehicle_speed = DT.SafeCall(function()
        if vehicle.getCurrentSpeedKmHour then
            return tonumber(string.format("%.2f", vehicle:getCurrentSpeedKmHour()))
        end
        return 0
    end, 0)

    return out
end
