require "DT_Shared"

if not isServer() then
    return
end

local DT_Server = {}

DT_Server.TELEMETRY_QUEUE_FILE = "doomtelemetry_queue.jsonl"
DT_Server.LastPlayerStateByUsername = {}
DT_Server.OnlinePlayersBySteamID = {}
DT_Server.OnlinePlayersByUsername = {}
DT_Server.LastHeartbeatRealAt = 0
DT_Server.HEARTBEAT_EVERY_REAL_SECONDS = 15
DT_Server.ServerStartedAt = os.time()
DT_Server.LastInitEventByPlayer = {}
DT_Server.INIT_DEDUPE_WINDOW_SECONDS = 3

print("==========================================")
print("[DoomTelemetry] DT_Server.lua CARREGADO")
print("[DoomTelemetry] TELEMETRY_QUEUE_FILE=" .. tostring(DT_Server.TELEMETRY_QUEUE_FILE))
print("==========================================")

function DT_Server.CopyTable(src)
    local out = {}
    if type(src) ~= "table" then
        return out
    end
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

function DT_Server.BuildPlayerBlockFromData(data)
    if not data then return nil end

    if (not data.steam_id or data.steam_id == "") and
       (not data.username or data.username == "") and
       (not data.character_name or data.character_name == "") then
        return nil
    end

    return {
        steam_id = data.steam_id or "",
        username = data.username or "",
        display_name = data.display_name or "",
        character_name = data.character_name or "",
        online_id = data.online_id or -1,
        player_id = data.player_id or -1
    }
end

function DT_Server.MakeEvent(eventType, rootData, payloadData)
    local event = DT_Server.CopyTable(rootData or {})
    event.event_id = DT.NextEventId()
    event.event_type = eventType
    event.schema_version = DT.SCHEMA_VERSION
    event.source = DT.SOURCE
    event.server_id = DT.SERVER_ID
    event.mod_version = DT.MOD_VERSION
    event.timestamp = event.timestamp or os.time()
    event.server_timestamp = os.time()
    event.player = DT_Server.BuildPlayerBlockFromData(rootData or {})
    event.payload = payloadData or {}
    return event
end

function DT_Server.WriteEvent(data)
    if not data then return false end

    data.event_id = data.event_id or DT.NextEventId()
    data.schema_version = data.schema_version or DT.SCHEMA_VERSION
    data.source = data.source or DT.SOURCE
    data.server_id = data.server_id or DT.SERVER_ID
    data.mod_version = data.mod_version or DT.MOD_VERSION
    data.server_timestamp = os.time()

    local writer = getFileWriter(DT_Server.TELEMETRY_QUEUE_FILE, true, true)
    if not writer then return false end

    local line = DT.EncodeJson(data)
    if not line or line == "" then
        writer:close()
        return false
    end

    writer:write(line)
    writer:write("\n")
    writer:close()
    return true
end

function DT_Server.GetPlayerSteamIDServer(player)
    if not player then return "" end
    
    local sid = ""
    
    if player.getUsername and getSteamIDFromUsername then
        local uname = player:getUsername()
        if uname and uname ~= "" then
            local raw2 = getSteamIDFromUsername(uname)
            if raw2 then sid = tostring(raw2) end
        end
    end

    if sid == "" and player.getSteamID then
        local raw = player:getSteamID()
        if raw then sid = tostring(raw) end
    end

    return sid:gsub("^%s+", ""):gsub("%s+$", "")
end

function DT_Server.ApplyAuthoritativeSteamID(player, args)
    args = args or {}
    local serverSteamID = DT_Server.GetPlayerSteamIDServer(player)
    if serverSteamID ~= "" then
        args.steam_id = serverSteamID
    end
    return args
end

function DT_Server.TrackOnlinePlayer(player, preferredSteamID)
    if not player then return end

    local username = player.getUsername and tostring(player:getUsername() or "") or ""
    local steamID = DT_Server.GetPlayerSteamIDServer(player)

    if steamID ~= "" then DT_Server.OnlinePlayersBySteamID[steamID] = player end
    if username ~= "" then DT_Server.OnlinePlayersByUsername[username] = player end
end

function DT_Server.RebuildOnlinePlayersMap()
    local currentOnline = {}
    local players = getOnlinePlayers()
    
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p.getUsername then
                currentOnline[tostring(p:getUsername() or "")] = p
            end
        end
    end

    -- DETECTOR DE LOGOUT (Agora roda imune ao pause do servidor)
    for username, playerObj in pairs(DT_Server.OnlinePlayersByUsername) do
        if not currentOnline[username] then
            print("[DoomTelemetry] Detectado Logout Automatico: " .. tostring(username))
            
            local cachedArgs = DT_Server.LastPlayerStateByUsername[username] or {}
            
            local event = DT_Server.MakeEvent("player_session_end", cachedArgs, {
                reason = "logout",
                steam_id = cachedArgs.steam_id or "",
                username = cachedArgs.username or username,
                x = cachedArgs.x or 0,
                y = cachedArgs.y or 0,
                z = cachedArgs.z or 0,
                is_alive = cachedArgs.is_alive and true or false,
                hours_survived = cachedArgs.hours_survived or 0,
                zombie_kills = cachedArgs.zombie_kills or 0,
                survivor_kills = cachedArgs.survivor_kills or 0,
                inventory_weight = cachedArgs.inventory_weight or 0,
                carry_capacity = cachedArgs.carry_capacity or 0,
                is_in_vehicle = cachedArgs.is_in_vehicle and true or false,
                is_asleep = cachedArgs.is_asleep and true or false,
                is_outdoors = cachedArgs.is_outdoors and true or false,
                building_name = cachedArgs.building_name or "",
                vehicle_id = cachedArgs.vehicle_id or "",
                vehicle_script = cachedArgs.vehicle_script or "",
                vehicle_speed = cachedArgs.vehicle_speed or 0,
                bleeding = cachedArgs.bleeding and true or false,
                overall_body_damage = cachedArgs.overall_body_damage or 0
            })
            DT_Server.WriteEvent(event)
        end
    end

    DT_Server.OnlinePlayersBySteamID = {}
    DT_Server.OnlinePlayersByUsername = {}

    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                local username = p.getUsername and tostring(p:getUsername() or "") or ""
                local steamID = DT_Server.GetPlayerSteamIDServer(p)

                if steamID ~= "" then DT_Server.OnlinePlayersBySteamID[steamID] = p end
                if username ~= "" then DT_Server.OnlinePlayersByUsername[username] = p end
            end
        end
    end
end

function DT_Server.RememberSnapshot(data)
    if not data or not data.username or data.username == "" then return end
    local existing = DT_Server.LastPlayerStateByUsername[data.username] or {}

    DT_Server.LastPlayerStateByUsername[data.username] = {
        steam_id = data.steam_id or existing.steam_id or "",
        username = data.username or existing.username or "",
        display_name = data.display_name or existing.display_name or "",
        character_name = data.character_name or existing.character_name or "",
        online_id = data.online_id or existing.online_id or -1,
        player_id = data.player_id or existing.player_id or -1,
        x = data.x or existing.x or 0,
        y = data.y or existing.y or 0,
        z = data.z or existing.z or 0,
        is_alive = data.is_alive,
        hours_survived = data.hours_survived or existing.hours_survived or 0,
        zombie_kills = data.zombie_kills or existing.zombie_kills or 0,
        survivor_kills = data.survivor_kills or existing.survivor_kills or 0,
        profession = data.profession or existing.profession or "",
        traits = data.traits or existing.traits or "",
        traits_array = data.traits_array or existing.traits_array or {},
        perks = data.perks or existing.perks or {},
        faction_name = data.faction_name or existing.faction_name or "",
        faction_tag = data.faction_tag or existing.faction_tag or "",
        faction_owner = data.faction_owner or existing.faction_owner or "",
        faction_members = data.faction_members or existing.faction_members or {},
        inventory_weight = data.inventory_weight or existing.inventory_weight or 0,
        carry_capacity = data.carry_capacity or existing.carry_capacity or 0,
        is_in_vehicle = data.is_in_vehicle,
        is_asleep = data.is_asleep,
        is_outdoors = data.is_outdoors,
        building_name = data.building_name or existing.building_name or "",
        vehicle_id = data.vehicle_id or existing.vehicle_id or "",
        vehicle_script = data.vehicle_script or existing.vehicle_script or "",
        vehicle_speed = data.vehicle_speed or existing.vehicle_speed or 0,
        bleeding = data.bleeding,
        overall_body_damage = data.overall_body_damage or existing.overall_body_damage or 0,
        timestamp = data.timestamp or os.time()
    }
end

function DT_Server.EnrichWithLastSnapshot(data)
    if not data or not data.username then return data end
    local cached = DT_Server.LastPlayerStateByUsername[data.username]
    if not cached then return data end

    if not data.steam_id or data.steam_id == "" then data.steam_id = cached.steam_id end
    if not data.display_name or data.display_name == "" then data.display_name = cached.display_name end
    if not data.character_name or data.character_name == "" then data.character_name = cached.character_name end
    if data.online_id == nil then data.online_id = cached.online_id end
    if data.player_id == nil then data.player_id = cached.player_id end
    return data
end

function DT_Server.GetInitDedupeKey(args)
    return tostring(args and args.steam_id or "") .. "|" .. tostring(args and args.username or "") .. "|" .. tostring(args and args.character_name or "")
end

function DT_Server.ShouldSkipDuplicatedInitEvent(args, eventType)
    local key = DT_Server.GetInitDedupeKey(args)
    if key == "||" then return false end

    local nowTs = os.time()
    local slotKey = tostring(eventType) .. "|" .. key
    local lastTs = DT_Server.LastInitEventByPlayer[slotKey]

    if lastTs and (nowTs - lastTs) < DT_Server.INIT_DEDUPE_WINDOW_SECONDS then return true end
    DT_Server.LastInitEventByPlayer[slotKey] = nowTs
    return false
end

function DT_Server.OnClientCommand(module, command, player, args)
    if module ~= DT.MOD_ID or not args then return end

    if (not args.username or args.username == "") and player and player.getUsername then
        args.username = player:getUsername()
    end

    args = DT_Server.ApplyAuthoritativeSteamID(player, args)
    DT_Server.TrackOnlinePlayer(player, args.steam_id)

    if command == "LinkStatusRequest" then
        args.event_type = "link_status_request"
        args = DT_Server.EnrichWithLastSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("link_status_request", args, {
            steam_id = args.steam_id or "", username = args.username or "",
            display_name = args.display_name or "", character_name = args.character_name or "",
            online_id = args.online_id or -1, player_id = args.player_id or -1
        }))
        return
    end

    if command == "LinkCodeSubmit" then
        args.event_type = "link_code_submit"
        args = DT_Server.EnrichWithLastSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("link_code_submit", args, {
            code = tostring(args.code or ""), steam_id = args.steam_id or "",
            username = args.username or "", display_name = args.display_name or "",
            character_name = args.character_name or "", online_id = args.online_id or -1,
            player_id = args.player_id or -1
        }))
        sendServerCommand(player, DT.MOD_ID, "LinkCodeSubmitAck", { ok = true, linked = false, message = "Codigo recebido." })
        return
    end

    if command == "LinkUnlink" then
        args.event_type = "link_unlink"
        args = DT_Server.EnrichWithLastSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("link_unlink", args, {
            steam_id = args.steam_id or "", username = args.username or "",
            display_name = args.display_name or "", character_name = args.character_name or "",
            online_id = args.online_id or -1, player_id = args.player_id or -1
        }))
        return
    end

    if command == "PlayerSessionStart" then
        args.event_type = "player_session_start"
        args = DT_Server.EnrichWithLastSnapshot(args)
        if DT_Server.ShouldSkipDuplicatedInitEvent(args, "player_session_start") then return end
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_session_start", args, { reason = tostring(args.reason or "login"), steam_id = args.steam_id or "" }))
        return
    end

    if command == "PlayerSessionEnd" then
        args.event_type = "player_session_end"
        args = DT_Server.EnrichWithLastSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_session_end", args, {
            reason = tostring(args.reason or "unknown"), steam_id = args.steam_id or "",
            x = args.x or 0, y = args.y or 0, z = args.z or 0, is_alive = args.is_alive and true or false,
            hours_survived = args.hours_survived or 0, zombie_kills = args.zombie_kills or 0,
            survivor_kills = args.survivor_kills or 0, inventory_weight = args.inventory_weight or 0,
            carry_capacity = args.carry_capacity or 0, is_in_vehicle = args.is_in_vehicle and true or false,
            is_asleep = args.is_asleep and true or false, is_outdoors = args.is_outdoors and true or false,
            building_name = args.building_name or "", vehicle_id = args.vehicle_id or "",
            vehicle_script = args.vehicle_script or "", vehicle_speed = args.vehicle_speed or 0,
            bleeding = args.bleeding and true or false, overall_body_damage = args.overall_body_damage or 0
        }))
        return
    end

    if command == "PlayerIdentity" then
        args.event_type = "player_identity"
        DT_Server.RememberSnapshot(args)
        if DT_Server.ShouldSkipDuplicatedInitEvent(args, "player_identity") then return end
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_identity", args, {}))
        return
    end

    if command == "PlayerProfile" then
        args.event_type = "player_profile"
        DT_Server.RememberSnapshot(args)
        if DT_Server.ShouldSkipDuplicatedInitEvent(args, "player_profile") then return end
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_profile", args, {
            is_alive = args.is_alive and true or false, hours_survived = args.hours_survived or 0,
            zombie_kills = args.zombie_kills or 0, survivor_kills = args.survivor_kills or 0,
            profession = args.profession or "", traits = args.traits_array or {},
            traits_string = args.traits or "", perks = args.perks or {},
            inventory_weight = args.inventory_weight or 0, carry_capacity = args.carry_capacity or 0,
            is_in_vehicle = args.is_in_vehicle and true or false, is_asleep = args.is_asleep and true or false,
            is_outdoors = args.is_outdoors and true or false, building_name = args.building_name or "",
            vehicle_id = args.vehicle_id or "", vehicle_script = args.vehicle_script or "",
            vehicle_speed = args.vehicle_speed or 0, bleeding = args.bleeding and true or false,
            overall_body_damage = args.overall_body_damage or 0,
            faction = { name = args.faction_name or "", tag = args.faction_tag or "", owner = args.faction_owner or "", members = args.faction_members or {} }
        }))
        DT_Server.WriteEvent(DT_Server.MakeEvent("faction_snapshot", { steam_id = args.steam_id or "", username = args.username or "", display_name = args.display_name or "", character_name = args.character_name or "", online_id = args.online_id or -1, player_id = args.player_id or -1, timestamp = os.time() }, {
            faction_name = args.faction_name or "", faction_tag = args.faction_tag or "",
            faction_owner = args.faction_owner or "", faction_members = args.faction_members or {}
        }))
        return
    end

    if command == "PlayerState" then
        args.event_type = "player_state"
        DT_Server.RememberSnapshot(args)
        if DT_Server.ShouldSkipDuplicatedInitEvent(args, "player_state") then return end
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_state", args, {
            x = args.x or 0, y = args.y or 0, z = args.z or 0, is_alive = args.is_alive and true or false,
            hours_survived = args.hours_survived or 0, zombie_kills = args.zombie_kills or 0,
            survivor_kills = args.survivor_kills or 0, inventory_weight = args.inventory_weight or 0,
            carry_capacity = args.carry_capacity or 0, is_in_vehicle = args.is_in_vehicle and true or false,
            is_asleep = args.is_asleep and true or false, is_outdoors = args.is_outdoors and true or false,
            building_name = args.building_name or "", vehicle_id = args.vehicle_id or "",
            vehicle_script = args.vehicle_script or "", vehicle_speed = args.vehicle_speed or 0,
            bleeding = args.bleeding and true or false, overall_body_damage = args.overall_body_damage or 0
        }))
        return
    end

    if command == "PlayerDeath" then
        args.event_type = "player_death"
        DT_Server.RememberSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_death", args, {
            x = args.x or 0, y = args.y or 0, z = args.z or 0, is_alive = args.is_alive and true or false,
            hours_survived = args.hours_survived or 0, zombie_kills = args.zombie_kills or 0,
            survivor_kills = args.survivor_kills or 0, inventory_weight = args.inventory_weight or 0,
            carry_capacity = args.carry_capacity or 0, is_in_vehicle = args.is_in_vehicle and true or false,
            is_asleep = args.is_asleep and true or false, is_outdoors = args.is_outdoors and true or false,
            building_name = args.building_name or "", vehicle_id = args.vehicle_id or "",
            vehicle_script = args.vehicle_script or "", vehicle_speed = args.vehicle_speed or 0,
            bleeding = args.bleeding and true or false, overall_body_damage = args.overall_body_damage or 0
        }))
        return
    end

    if command == "PlayerKillDelta" then
        args.event_type = "player_kill_delta"
        args = DT_Server.EnrichWithLastSnapshot(args)
        DT_Server.WriteEvent(DT_Server.MakeEvent("player_kill_delta", args, {
            zombie_kills_total = args.zombie_kills_total or 0, survivor_kills_total = args.survivor_kills_total or 0,
            zombie_kills_delta = args.zombie_kills_delta or 0, survivor_kills_delta = args.survivor_kills_delta or 0
        }))
        return
    end
end

function DT_Server.Heartbeat()
    local gt = getGameTime()

    local players = getOnlinePlayers()
    local count = 0
    local usernames = {}
    local online_details = {}

    if players then
        count = players:size()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p.getUsername then
                local uname = tostring(p:getUsername() or "")
                table.insert(usernames, uname)
                table.insert(online_details, {
                    username = uname,
                    steam_id = DT_Server.GetPlayerSteamIDServer(p),
                    character_name = DT.GetCharacterName(p)
                })
            end
        end
    end

    local world = getWorld()
    local climate = getClimateManager()
    local uptime_seconds = os.time() - (DT_Server.ServerStartedAt or os.time())

    local game_time_str = "desconhecido"
    local world_age_days = 0
    local global_temperature = 0
    local night_value = 0

    if gt then
        game_time_str =
            tostring(gt:getDay() + 1) .. "." ..
            tostring(gt:getMonth() + 1) .. "." ..
            tostring(gt:getYear()) .. " " ..
            tostring(gt:getHour()) .. ":" ..
            string.format("%02d", gt:getMinutes())

        night_value = tonumber(string.format("%.1f", gt:getNight())) or 0
    end

    if world then
        world_age_days = math.floor(world:getWorldAgeDays() or 0)
        global_temperature = tonumber(string.format("%.1f", world:getGlobalTemperature() or 0)) or 0
    end

    local root = {
        event_type = "server_heartbeat",
        online_count = count,
        online_players = usernames,
        timestamp = os.time(),
        game_time = game_time_str,
        world_age_days = world_age_days,
        global_temperature = global_temperature,
        is_game_paused = isGamePaused and isGamePaused() or false,
        night = night_value,
        weather = {
            cloud_intensity = climate and climate:getCloudIntensity() or 0,
            is_raining = (RainManager and RainManager.isRaining()) and true or false
        },
        uptime_seconds = uptime_seconds,
        mod_version = DT.MOD_VERSION,
        debug_enabled = DT.DEBUG and true or false
    }

    print("[DoomTelemetry] Heartbeat escreveu no queue | players=" .. tostring(count))
    DT_Server.WriteEvent(DT_Server.MakeEvent("server_heartbeat", root, { online_details = online_details }))
end

local bootEvent = DT_Server.MakeEvent("server_boot", { timestamp = os.time(), mod_version = DT.MOD_VERSION }, {
    reason = "startup", mod_version = DT.MOD_VERSION, schema_version = DT.SCHEMA_VERSION,
    server_id = DT.SERVER_ID, debug_enabled = DT.DEBUG and true or false
})
DT_Server.WriteEvent(bootEvent)

-- =========================================================================
-- RELÓGIO DO MUNDO REAL (Verifica Logout, Heartbeat e Inbox mesmo se o jogo pausar)
-- =========================================================================
DT_Server.INBOX_FILE = "doomtelemetry_inbox.txt"
DT_Server.LastRealTimeCheck = os.time()

function DT_Server.RealTimeTick()
    local now = os.time()
    print("[DoomTelemetry] RealTimeTick rodou em " .. tostring(now))

    if (now - DT_Server.LastRealTimeCheck) < 3 then return end
    DT_Server.LastRealTimeCheck = now

    if (now - (DT_Server.LastHeartbeatRealAt or 0)) >= DT_Server.HEARTBEAT_EVERY_REAL_SECONDS then
        DT_Server.LastHeartbeatRealAt = now
        print("[DoomTelemetry] disparando heartbeat em " .. tostring(now))
        DT_Server.Heartbeat()
    end

    DT_Server.RebuildOnlinePlayersMap()

    local reader = getFileReader(DT_Server.INBOX_FILE, false)
    if not reader then return end

    local lines = {}
    local line = reader:readLine()
    while line do
        table.insert(lines, line)
        line = reader:readLine()
    end
    reader:close()

    if #lines > 0 then
        local writer = getFileWriter(DT_Server.INBOX_FILE, true, false)
        if writer then writer:close() end

        for _, l in ipairs(lines) do
            local sep1 = string.find(l, "|", 1, true)
            if sep1 then
                local sep2 = string.find(l, "|", sep1 + 1, true)
                if sep2 then
                    local username = string.sub(l, 1, sep1 - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local statusStr = string.sub(l, sep1 + 1, sep2 - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local message = string.sub(l, sep2 + 1):gsub("^%s+", ""):gsub("%s+$", "")

                    local isLinked = (statusStr == "1")
                    DT_RCON_LinkResult(username, isLinked, message)
                end
            end
        end
    end
end

function DT_RCON_LinkResult(username, isLinked, messageStr)
    local player = DT_Server.OnlinePlayersByUsername[username]
    if player then
        sendServerCommand(player, DT.MOD_ID, "LinkCodeFinalResult", {
            linked = isLinked,
            message = tostring(messageStr or "")
        })
    end
end

Events.OnClientCommand.Add(DT_Server.OnClientCommand)
Events.OnTick.Add(DT_Server.RealTimeTick)