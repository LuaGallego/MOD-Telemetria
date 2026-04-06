require "DT_Shared"
require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"

if isServer() then
    return
end

print("[DT_Link_Client] UI FINAL CARREGADA")

if type(DT_Link_Client) ~= "table" then
    DT_Link_Client = {}
end

-- evita resetar e registrar tudo duas vezes se o arquivo for carregado novamente
if DT_Link_Client._bootstrapped then
    print("[DT_Link_Client] ja inicializado, ignorando carga duplicada")
    return
end
DT_Link_Client._bootstrapped = true

DT_Link_Client._registered = false
DT_Link_Client._prompt = nil
DT_Link_Client._window = nil
DT_Link_Client._createdOnce = false
DT_Link_Client._dismissed = false
DT_Link_Client._sessionPromptShown = false

DT_Link_Client._state = "checking"
DT_Link_Client._checkingSince = 0
DT_Link_Client._lastStatusRequestAt = 0
DT_Link_Client._statusRequestCooldown = 3
DT_Link_Client._checkingTimeoutSeconds = 8
DT_Link_Client._promptShownThisSession = false
DT_Link_Client._statusResolvedThisSession = false

local function safePlayer()
    return getPlayer()
end

local function hasPlayer()
    return safePlayer() ~= nil
end

local function trim(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function removePrompt()
    local ref = DT_Link_Client._prompt
    if ref then
        pcall(function()
            ref:setVisible(false)
            ref:removeFromUIManager()
        end)
        DT_Link_Client._prompt = nil
    end
end

local function removeWindow()
    local ref = DT_Link_Client._window
    if ref then
        pcall(function()
            ref:setVisible(false)
            ref:removeFromUIManager()
        end)
        DT_Link_Client._window = nil
    end
end

local function removePrompt()
    local ref = DT_Link_Client._prompt
    if ref then
        pcall(function()
            ref:setVisible(false)
            ref:removeFromUIManager()
        end)
        DT_Link_Client._prompt = nil
    end
end

local function requestLinkStatus(force)
    local player = safePlayer()
    if not player then
        return false
    end

    local nowTs = os.time()
    if not force and (nowTs - (DT_Link_Client._lastStatusRequestAt or 0)) < DT_Link_Client._statusRequestCooldown then
        return false
    end

    DT_Link_Client._lastStatusRequestAt = nowTs

    local payload = {
        event_type = "link_status_request",
        steam_id = DT.GetPlayerSteamID(player),
        username = player.getUsername and (player:getUsername() or "") or "",
        display_name = player.getDisplayName and (player:getDisplayName() or "") or "",
        character_name = DT.GetCharacterName(player),
        online_id = player.getOnlineID and player:getOnlineID() or -1,
        player_id = DT.GetPlayerRuntimeId(player),
        timestamp = os.time(),
    }

    print("[DT_Link_Client] enviando LinkStatusRequest state=" .. tostring(DT_Link_Client._state))
    sendClientCommand(player, DT.MOD_ID, "LinkStatusRequest", payload)
    return true
end

local function sendCodeToServer(code)
    local player = safePlayer()
    if not player then
        return false, "Jogador ainda nao disponivel."
    end

    local payload = {
        event_type = "link_code_submit",
        code = trim(code),
        steam_id = DT.GetPlayerSteamID(player),
        username = player.getUsername and (player:getUsername() or "") or "",
        display_name = player.getDisplayName and (player:getDisplayName() or "") or "",
        character_name = DT.GetCharacterName(player),
        online_id = player.getOnlineID and player:getOnlineID() or -1,
        player_id = DT.GetPlayerRuntimeId(player),
        timestamp = os.time(),
    }

    sendClientCommand(player, DT.MOD_ID, "LinkCodeSubmit", payload)
    return true, "Codigo enviado. Aguarde a confirmacao."
end

local function styleButton(btn)
    if not btn then
        return
    end
    btn.backgroundColor = { r = 0.16, g = 0.16, b = 0.16, a = 0.95 }
    btn.backgroundColorMouseOver = { r = 0.24, g = 0.24, b = 0.24, a = 1.0 }
    btn.borderColor = { r = 0.85, g = 0.20, b = 0.20, a = 1.0 }
    btn.enable = true
end

local LinkPrompt = ISPanel:derive("DTLinkPrompt")

function LinkPrompt:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.88 }
    o.borderColor = { r = 0.85, g = 0.20, b = 0.20, a = 1.0 }
    o.moveWithMouse = false
    o.anchorBottom = true
    o.anchorRight = true
    return o
end

function LinkPrompt:initialise()
    ISPanel.initialise(self)
end

function LinkPrompt:prerender()
    ISPanel.prerender(self)
    self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.95, 0.28, 0.28)
    self:drawText("Conta nao vinculada", 12, 10, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Clique aqui para fazer sua ativacao", 12, 28, 1, 0.85, 0.85, 1, UIFont.Small)
end

function LinkPrompt:onMouseDown(x, y)
    DT_Link_Client._dismissed = false
    DT_Link_Client.openWindow()
    return true
end

local LinkWindow = ISPanel:derive("DTLinkWindow")

function LinkWindow:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self

    o.background = true
    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.96 }
    o.borderColor = { r = 0.85, g = 0.20, b = 0.20, a = 1.0 }
    o.moveWithMouse = true
    o.statusMessage = ""
    o.codeText = ""

    o.inputX = 18
    o.inputY = 220
    o.inputW = w - 36
    o.inputH = 32

    o.pasteX = 18
    o.pasteY = 266
    o.pasteW = 120
    o.pasteH = 28

    o.sendX = 150
    o.sendY = 266
    o.sendW = 110
    o.sendH = 28

    o.closeW = 70
    o.closeH = 28
    o.closeX = w - 88
    o.closeY = 266

    o.entry = nil
    o.btnPaste = nil
    o.btnSend = nil
    o.btnClose = nil
    o.childrenBuilt = false

    return o
end

function LinkWindow:initialise()
    ISPanel.initialise(self)
end

function LinkWindow:createChildren()
    ISPanel.createChildren(self)

    if self.childrenBuilt then
        return
    end
    self.childrenBuilt = true

    self.entry = ISTextEntryBox:new("", self.inputX, self.inputY, self.inputW, self.inputH)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry:setOnlyNumbers(false)
    self.entry:setMaxTextLength(64)
    self.entry.backgroundColor = { r = 0.02, g = 0.02, b = 0.02, a = 0.98 }
    self.entry.borderColor = { r = 0.35, g = 0.35, b = 0.35, a = 1.0 }
    self.entry.textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
    self.entry:setText("")
    self:addChild(self.entry)

    self.btnPaste = ISButton:new(self.pasteX, self.pasteY, self.pasteW, self.pasteH, "Colar codigo", self, LinkWindow.onPasteClicked)
    self.btnPaste:initialise()
    self.btnPaste:instantiate()
    styleButton(self.btnPaste)
    self:addChild(self.btnPaste)

    self.btnSend = ISButton:new(self.sendX, self.sendY, self.sendW, self.sendH, "Enviar", self, LinkWindow.onConfirm)
    self.btnSend:initialise()
    self.btnSend:instantiate()
    styleButton(self.btnSend)
    self:addChild(self.btnSend)

    self.btnClose = ISButton:new(self.closeX, self.closeY, self.closeW, self.closeH, "Fechar", self, LinkWindow.onClose)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    styleButton(self.btnClose)
    self:addChild(self.btnClose)
end

function LinkWindow:syncEntryToCodeText()
    if self.entry and self.entry.getInternalText then
        self.codeText = trim(self.entry:getInternalText() or "")
    elseif self.entry and self.entry.getText then
        self.codeText = trim(self.entry:getText() or "")
    else
        self.codeText = ""
    end
end

function LinkWindow:focusEntry()
    if not self.entry then
        return
    end

    if self.entry.setEditable then
        self.entry:setEditable(true)
    end

    if self.entry.javaObject and self.entry.javaObject.setFocused then
        self.entry.javaObject:setFocused(true)
    end
end

function LinkWindow:prerender()
    ISPanel.prerender(self)

    self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.95, 0.28, 0.28)

    self:drawText("Vincular conta ao Discord", 18, 12, 1, 1, 1, 1, UIFont.Medium)
    self:drawText("Conecte seu personagem do jogo ao seu perfil do Discord.", 18, 48, 0.95, 0.95, 0.95, 1, UIFont.Small)
    self:drawText("Isso sera usado para loja, recompensas, VIP e futuras integracoes.", 18, 68, 0.95, 0.95, 0.95, 1, UIFont.Small)
    self:drawText("Como fazer:", 18, 104, 1, 1, 1, 1, UIFont.Small)
    self:drawText("1. Entre no Discord do servidor", 18, 126, 1, 0.90, 0.90, 1, UIFont.Small)
    self:drawText("2. Gere seu codigo pessoal no painel de vinculo", 18, 146, 1, 0.90, 0.90, 1, UIFont.Small)
    self:drawText("3. Cole ou digite o codigo abaixo e clique em Enviar", 18, 166, 1, 0.90, 0.90, 1, UIFont.Small)
    self:drawText("Codigo de vinculo:", 18, 198, 1, 1, 1, 1, UIFont.Small)

    if self.statusMessage ~= "" then
        self:drawText(self.statusMessage, 18, 304, 0.95, 0.90, 0.90, 1, UIFont.Small)
    end
end

function LinkWindow:onGainFocus()
    self:focusEntry()
end

function LinkWindow:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    self:bringToTop()
    return true
end

function LinkWindow:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    return true
end

function LinkWindow:onPasteClicked()
    self:focusEntry()
    self.statusMessage = "Cole o codigo no campo acima e clique em Enviar."
end

function LinkWindow:onConfirm()
    self:syncEntryToCodeText()

    local code = trim(self.codeText)
    if code == "" then
        self.statusMessage = "Informe um codigo valido."
        self:focusEntry()
        return
    end

    local ok, msg = sendCodeToServer(code)
    self.statusMessage = msg or ""

    if ok then
        DT_Link_Client._state = "pending"
        DT_Link_Client._dismissed = false
        DT_Link_Client.refreshPrompt()
        self.statusMessage = "Codigo enviado para validacao. Aguarde..."
    else
        self:focusEntry()
    end
end

function LinkWindow:onClose()
    DT_Link_Client._dismissed = true
    removeWindow()
    DT_Link_Client.refreshPrompt()
end

function DT_Link_Client.refreshPrompt()
    if DT_Link_Client._prompt then
        DT_Link_Client._prompt:setVisible(
            DT_Link_Client._state == "unlinked"
            and not DT_Link_Client._dismissed
            and DT_Link_Client._sessionPromptShown
        )
    end
end

function DT_Link_Client.ensurePrompt()
    if not hasPlayer() then
        return
    end

    if DT_Link_Client._state ~= "unlinked" then
        removePrompt()
        return
    end

    if DT_Link_Client._dismissed then
        DT_Link_Client.refreshPrompt()
        return
    end

    if DT_Link_Client._sessionPromptShown then
        DT_Link_Client.refreshPrompt()
        return
    end

    local core = getCore()
    if not core then
        return
    end

    local sw = core:getScreenWidth()
    local sh = core:getScreenHeight()
    local w = 250
    local h = 56
    local marginX = 18
    local marginY = 110

    local x = sw - w - marginX
    local y = sh - h - marginY

    local prompt = LinkPrompt:new(x, y, w, h)
    prompt:initialise()
    prompt:instantiate()
    prompt:addToUIManager()

    DT_Link_Client._prompt = prompt
    DT_Link_Client._sessionPromptShown = true
    DT_Link_Client.refreshPrompt()
end

function DT_Link_Client.openWindow()
    DT_Link_Client._dismissed = false

    if DT_Link_Client._window then
        DT_Link_Client._window:setVisible(true)
        DT_Link_Client._window:bringToTop()
        DT_Link_Client._window:focusEntry()
        return
    end

    local core = getCore()
    if not core then
        return
    end

    local sw = core:getScreenWidth()
    local sh = core:getScreenHeight()
    local w = 500
    local h = 340

    local win = LinkWindow:new((sw - w) / 2, (sh - h) / 2, w, h)
    win:initialise()
    win:instantiate()
    win:addToUIManager()
    win:bringToTop()
    win:focusEntry()

    DT_Link_Client._window = win
end

function DT_Link_Client.onServerCommand(module, command, args)
    if module ~= DT.MOD_ID then
        return
    end

    if command == "LinkStatusSync" then
        print("[DT_Link_Client] recebeu LinkStatusSync linked=" .. tostring(args and args.linked) .. " message=" .. tostring(args and args.message or ""))

        if args and args.linked then
            DT_Link_Client._state = "linked"
            DT_Link_Client._dismissed = true
            removePrompt()
            removeWindow()
            return
        end

        if DT_Link_Client._state ~= "linked" then
            DT_Link_Client._state = "unlinked"
            if DT_Link_Client._window then
                DT_Link_Client._window.statusMessage = tostring((args and args.message) or "Conta nao vinculada.")
                DT_Link_Client._window:focusEntry()
            end
            DT_Link_Client.ensurePrompt()
        end
        return
    end

    if command == "LinkCodeSubmitAck" then
        if args and args.ok then
            DT_Link_Client._state = "pending"
            DT_Link_Client._dismissed = false
            removePrompt()

            if not DT_Link_Client._window then
                DT_Link_Client.openWindow()
            end

            if DT_Link_Client._window then
                DT_Link_Client._window.statusMessage = tostring(args.message or "Codigo enviado para validacao.")
            end
        else
            DT_Link_Client._state = "unlinked"
            DT_Link_Client._dismissed = false

            if not DT_Link_Client._window then
                DT_Link_Client.openWindow()
            end

            if DT_Link_Client._window then
                DT_Link_Client._window.statusMessage = tostring((args and args.message) or "Falha ao enviar o codigo.")
                DT_Link_Client._window:focusEntry()
            end
        end
        return
    end

    if command == "LinkCodeFinalResult" then
        print("[DT_Link_Client] recebeu LinkCodeFinalResult linked=" .. tostring(args and args.linked) .. " message=" .. tostring(args and args.message or ""))

        if args and args.linked then
            DT_Link_Client._state = "linked"
            DT_Link_Client._dismissed = true
            removePrompt()
            removeWindow()
        else
            if DT_Link_Client._state == "linked" then
                print("[DT_Link_Client] ignorando LinkCodeFinalResult false porque ja esta linked")
                return
            end

            DT_Link_Client._state = "unlinked"
            DT_Link_Client._dismissed = false

            if not DT_Link_Client._window then
                DT_Link_Client.openWindow()
            end

            if DT_Link_Client._window then
                DT_Link_Client._window.statusMessage = tostring((args and args.message) or "Codigo invalido ou expirado.")
                DT_Link_Client._window:focusEntry()
            end
        end
        return
    end
end

function DT_Link_Client.onCreatePlayer(playerIndex, playerObj)
    if DT_Link_Client._createdOnce then
        return
    end

    DT_Link_Client._createdOnce = true
    DT_Link_Client._dismissed = false
    DT_Link_Client._sessionPromptShown = false
    DT_Link_Client._state = "checking"
    DT_Link_Client._checkingSince = os.time()
    DT_Link_Client._lastStatusRequestAt = 0

    print("[DT_Link_Client] onCreatePlayer -> entrando em checking")
    requestLinkStatus(true)
end

function DT_Link_Client.onTick()
    if not hasPlayer() then
        return
    end

    if DT_Link_Client._state == "checking" then
        requestLinkStatus()

        local nowTs = os.time()
        local sinceTs = tonumber(DT_Link_Client._checkingSince or nowTs) or nowTs

        if (not DT_Link_Client._statusResolvedThisSession)
            and (not DT_Link_Client._promptShownThisSession)
            and (not DT_Link_Client._dismissed)
            and ((nowTs - sinceTs) >= DT_Link_Client._checkingTimeoutSeconds) then
            print("[DT_Link_Client] checking expirou -> fallback unlinked UMA vez na sessao")
            DT_Link_Client._state = "unlinked"
            DT_Link_Client.refreshPrompt()
            DT_Link_Client.ensurePrompt()
        end

        return
    end

    if DT_Link_Client._state == "unlinked" then
        if (not DT_Link_Client._dismissed) and (not DT_Link_Client._promptShownThisSession) then
            DT_Link_Client.ensurePrompt()
        else
            DT_Link_Client.refreshPrompt()
        end
    end
end

function DT_Link_Client.tryRegister()
    if DT_Link_Client._registered then
        return
    end

    DT_Link_Client._registered = true
    Events.OnCreatePlayer.Add(DT_Link_Client.onCreatePlayer)
    Events.OnServerCommand.Add(DT_Link_Client.onServerCommand)
    Events.OnTick.Add(DT_Link_Client.onTick)
end

DT_Link_Client.tryRegister()
