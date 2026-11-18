-- SessionLab Token Checks. Install the generated ASCII Main file as a separate mod.
local URL = "https://sessionlab.up.railway.app"
local TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"
-- Inlined into each installable Main.lua. All four mods share one local preference.
local connection = rawget(_G, "SessionLabConnectionV1")
if not connection then
    local setting = "sessionlab_personal_connection_v1"
    local endpoint = "/api/integrations/dmhub/sheets/"
    local listeners = {}
    local window
    connection = {}
    rawset(_G, "SessionLabConnectionV1", connection)

    if type(dmhub.RegisterSetting) == "function" then
        pcall(dmhub.RegisterSetting, {id = setting, storage = "pergamepreference", default = {}})
    end

    function connection.scope(url)
        local game, user = dmhub.gameid, dmhub.userid
        if type(game) == "string" and game ~= "" and type(user) == "string" and user ~= "" then
            return url .. "|" .. game .. "|" .. user
        end
    end

    local function validKey(key)
        return type(key) == "string" and #key >= 24 and #key <= 128
            and key:match("^[A-Za-z0-9_%-]+$") and not key:find("^PASTE_")
    end

    function connection.get(url, fallback)
        local scope = connection.scope(url)
        local saved = scope and type(dmhub.GetSettingValue) == "function" and dmhub.GetSettingValue(setting)
        local key = type(saved) == "table" and saved[scope]
        if validKey(key) then return key end
        if validKey(fallback) then return fallback end
    end

    function connection.onChange(name, url, callback)
        listeners[name] = {url = url, callback = callback}
    end

    function connection.open(url)
        local scope = connection.scope(url)
        local gameHudType = rawget(_G, "GameHud")
        local hud = rawget(_G, "gamehud") or (gameHudType and gameHudType.instance)
        local host = hud and hud.dialogWorldPanel
        if not scope or not host or host.valid == false or not gui or not gui.Input then return end
        if window and window.scope == scope and window.panel.valid then return end
        if window and window.panel.valid then window.panel:DestroySelf() end
        local width = 360
        local input = gui.Input{width = width, height = 32, halign = "center", text = "",
            placeholderText = "\208\155\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 SessionLab", fontSize = 13, color = "#f5ecff",
            bgimage = "panels/square.png", bgcolor = "#262a3a", swallowPress = true}
        local function label(text, size)
            return gui.Label{text = text, width = width, height = "auto", fontSize = size,
                halign = "center", textWrap = true, color = "#f5ecff", interactable = false}
        end
        local status = label(connection.get(url) and "\208\154\208\187\209\142\209\135 \209\131\208\182\208\181 \209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189. \208\156\208\190\208\182\208\189\208\190 \208\178\208\178\208\181\209\129\209\130\208\184 \208\189\208\190\208\178\209\139\208\185." or "", 13)
        local panel, busy
        local function current()
            return window and window.panel == panel and panel.valid and connection.scope(url) == scope
        end
        local function close()
            if panel and panel.valid then
                input.text = ""
                panel:DestroySelf()
            end
        end
        local function save()
            if busy or not current() then return end
            local key = tostring(input.text or ""):match("^%s*(.-)%s*$")
            if not validKey(key) then
                status.text = "\208\146\209\129\209\130\208\176\208\178\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \208\187\208\184\209\129\209\130\208\176 \208\184\208\183 \208\191\209\128\208\190\209\132\208\184\208\187\209\143 SessionLab."
                return
            end
            input.text = ""
            busy = true
            status.text = "\208\159\209\128\208\190\208\178\208\181\209\128\209\143\209\142 \208\186\208\187\209\142\209\135\226\128\166"
            local function fail(message)
                if not busy or not current() then return end
                busy = false
                status.text = message
            end
            local function success(raw)
                if not busy or not current() then return end
                local ok, response = pcall(function()
                    return type(raw) == "table" and raw or dmhub.FromJson(raw)
                end)
                if not ok or type(response) ~= "table" or type(response.data) ~= "table"
                    or type(response.data.characters) ~= "table" then
                    fail("\208\154\208\187\209\142\209\135 \208\189\208\181 \208\191\209\128\208\184\208\189\209\143\209\130. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \208\184 \208\186\208\176\208\188\208\191\208\176\208\189\208\184\209\142.")
                    return
                end
                local previous = connection.get(url)
                local saved = dmhub.GetSettingValue(setting)
                local keys = {}
                if type(saved) == "table" then
                    for name, value in pairs(saved) do keys[name] = value end
                end
                keys[scope] = key
                local written = pcall(dmhub.SetSettingValue, setting, keys)
                if not written or connection.get(url) ~= key then
                    fail("DMHub \208\189\208\181 \209\129\208\190\209\133\209\128\208\176\208\189\208\184\208\187 \208\186\208\187\209\142\209\135. \208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\208\181 \208\191\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181.")
                    return
                end
                busy = false
                status.text = "\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\190. \208\155\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189 \208\180\208\187\209\143 \208\178\209\129\208\181\209\133 \208\188\208\190\208\180\208\190\208\178 SessionLab."
                if previous ~= key then
                    for _, listener in pairs(listeners) do
                        if listener.url == url then pcall(listener.callback) end
                    end
                end
            end
            local function failure()
                fail("\208\154\208\187\209\142\209\135 \208\189\208\181 \208\191\209\128\208\184\208\189\209\143\209\130 \208\184\208\187\208\184 SessionLab \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189. \208\159\208\190\208\191\209\128\208\190\208\177\209\131\208\185\209\130\208\181 \208\181\209\137\209\145 \209\128\208\176\208\183.")
            end
            local ok = pcall(function()
                net.Get{url = url .. endpoint, headers = {Authorization = "Bearer " .. key, Accept = "application/json"},
                    success = success, error = failure, failure = failure}
            end)
            if not ok then failure() end
            dmhub.Schedule(15, function() fail("SessionLab \208\189\208\181 \208\190\209\130\208\178\208\181\209\130\208\184\208\187 \208\178\208\190\208\178\209\128\208\181\208\188\209\143.") end)
        end
        local function button(text, press, color)
            return gui.Button{text = text, width = width, height = 30, halign = "center",
                color = "#f5ecff", bgcolor = color, bgimage = "panels/square.png",
                cornerRadius = 5, swallowPress = true, press = press}
        end
        panel = gui.Panel{
            width = width + 20, height = "auto", flow = "vertical", halign = "center", valign = "center",
            floating = true, swallowPress = true, captureEscape = true, escape = close,
            bgimage = "panels/square.png", bgcolor = "#17192b", cornerRadius = 9, vpad = 6,
            thinkTime = 0.5, think = function() if not current() then close() end end,
            destroy = function() if window and window.panel == panel then window = nil end end,
            children = {label("\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181 SessionLab", 16),
                label("\208\161\208\186\208\190\208\191\208\184\209\128\209\131\208\185\209\130\208\181 \208\186\208\187\209\142\209\135 \208\184\208\183 \194\171\208\156\208\190\208\185 \208\191\209\128\208\190\209\132\208\184\208\187\209\140 \226\134\146 \208\156\208\190\208\185 \208\187\208\184\209\129\209\130 \208\178 DMHub\194\187 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\208\190\208\185 \208\186\208\176\208\188\208\191\208\176\208\189\208\184\208\184.", 13),
                input, status, button("\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\184\209\130\209\140", save, "#514479"), button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140", close, "#262a3a")},
        }
        window = {panel = panel, scope = scope}
        host:AddChild(panel)
    end

    local function open()
        connection.open(URL)
    end
    if type(Commands.RegisterMacro) == "function" then
        Commands.RegisterMacro{name = "slconnect", summary = "Open the SessionLab personal connection dialog", command = open}
    else
        Commands.slconnect = open
    end
end


local SHEETS = "/api/integrations/dmhub/sheets/"
local SETTING = "sessionlab_token_sheets_v1"
local POSITION = "sessionlab_token_window_v1"
local HUD_PREFERENCES = "sessionlab_vitals_v1"
local HIDE_ACTION_BAR = "sessionlab_hide_builtin_actions_v1"
local BUILTIN_ACTION_BAR = "hideactionbar"
local COMMAND = "sltoken"
local ENROLL_COMMAND = "slenroll"
local INITIATIVE_COMMAND = "slinitiative"
local RUNTIME = "SessionLabTokenChecks"
local skills = {
    {"athletics", "\208\144\209\130\208\187\208\181\209\130\208\184\208\186\208\176"}, {"acrobatics", "\208\144\208\186\209\128\208\190\208\177\208\176\209\130\208\184\208\186\208\176"},
    {"perception", "\208\146\208\189\208\184\208\188\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"}, {"stealth", "\208\161\208\186\209\128\209\139\209\130\208\189\208\190\209\129\209\130\209\140"},
    {"investigation", "\208\144\208\189\208\176\208\187\208\184\208\183"}, {"survival", "\208\146\209\139\208\182\208\184\208\178\208\176\208\189\208\184\208\181"},
    {"animal_handling", "\208\163\209\133\208\190\208\180 \208\183\208\176 \208\182\208\184\208\178\208\190\209\130\208\189\209\139\208\188\208\184"}, {"insight", "\208\159\209\128\208\190\208\189\208\184\209\134\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"},
    {"arcana", "\208\156\208\176\208\179\208\184\209\143"}, {"history", "\208\152\209\129\209\130\208\190\209\128\208\184\209\143"},
    {"medicine", "\208\156\208\181\208\180\208\184\209\134\208\184\208\189\208\176"}, {"nature", "\208\159\209\128\208\184\209\128\208\190\208\180\208\176"},
    {"religion", "\208\160\208\181\208\187\208\184\208\179\208\184\209\143"}, {"sleight_of_hand", "\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140 \209\128\209\131\208\186"},
    {"deception", "\208\158\208\177\208\188\208\176\208\189"}, {"intimidation", "\208\151\208\176\208\191\209\131\208\179\208\184\208\178\208\176\208\189\208\184\208\181"},
    {"performance", "\208\146\209\139\209\129\209\130\209\131\208\191\208\187\208\181\208\189\208\184\208\181"}, {"persuasion", "\208\163\208\177\208\181\208\182\208\180\208\181\208\189\208\184\208\181"},
}

local state = {menu = nil, pending = nil}
rawset(_G, RUNTIME, state)

local function report(message)
    dmhub.Log("SessionLab: " .. message)
end

local function id(value)
    local n = tonumber(value)
    if n and n >= 1 and n <= 9007199254740991 and n % 1 == 0 then
        return string.format("%.0f", n)
    end
end

local function safeText(value)
    return tostring(value or ""):gsub("[<>\r\n]", " ")
end

local function context()
    return connection.scope(URL)
end

local function bindingKey(menu)
    return menu.context .. "|" .. menu.token
end

local function personalKey()
    return connection.get(URL, TOKEN)
end

local function allBindings()
    local value = dmhub.GetSettingValue(SETTING)
    return type(value) == "table" and value or {}
end

local function writeBinding(menu, binding)
    local copy = {}
    for key, value in pairs(allBindings()) do copy[key] = value end
    copy[bindingKey(menu)] = binding
    dmhub.SetSettingValue(SETTING, copy)
end

local function controlled(token)
    if not token or not token.valid then return false end
    local ok, allowed = pcall(function() return token.canControlAsUser end)
    if ok and allowed ~= nil then return allowed end
    return token.canControl == true
end

local function active(menu)
    return rawget(_G, RUNTIME) == state and state.menu == menu and context() == menu.context
end

local function tokenStillControlled(menu)
    local token = dmhub.GetTokenById(menu.token)
    return controlled(token) and token.onBoard ~= false and (not menu.map or token.mapid == menu.map)
end

local function clearSpellRange(menu)
    if menu.spellRange then
        menu.spellRange:Destroy()
        menu.spellRange = nil
    end
end

local function close(menu)
    if state.menu ~= menu then return end
    state.menu = nil
    clearSpellRange(menu)
    if menu.panel and menu.panel.valid then menu.panel:DestroySelf() end
end

local function request(path, body, key, success, failure)
    local token = personalKey()
    if not token then failure("\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\184\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 SessionLab \209\135\208\181\209\128\208\181\208\183 /slconnect.") return end
    local headers = {Authorization = "Bearer " .. token, Accept = "application/json"}
    local finished = false
    local function fail(message)
        if finished then return end
        finished = true
        failure(message)
    end
    local options = {url = URL .. path, headers = headers}
    options.success = function(raw)
        if finished then return end
        local ok, result = pcall(function()
            return type(raw) == "table" and raw or dmhub.FromJson(raw)
        end)
        if not ok or type(result) ~= "table" or type(result.data) ~= "table" then
            local detail = ok and type(result) == "table" and result.error
            if type(detail) == "table" then detail = detail.detail end
            fail(type(detail) == "string" and safeText(detail) or "SessionLab \208\189\208\181 \208\191\209\128\208\184\208\189\209\143\208\187 \208\183\208\176\208\191\209\128\208\190\209\129.")
            return
        end
        finished = true
        success(result.data)
    end
    options.error = function(message)
        local status = type(message) == "string" and tonumber(message:match("%f[%d]([45]%d%d)%f[%D]"))
        if status == 401 or status == 403 then
            fail("\208\157\208\181\209\130 \208\180\208\190\209\129\209\130\209\131\208\191\208\176 \208\178 SessionLab. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \208\184 \208\191\209\128\208\176\208\178\208\176 \208\189\208\176 \208\187\208\184\209\129\209\130.")
        elseif status == 404 and not body and path:find("/token-scene/", 1, true) then
            fail("\208\161\208\181\209\128\208\178\208\181\209\128 SessionLab \208\189\208\181 \208\191\208\190\208\180\208\180\208\181\209\128\208\182\208\184\208\178\208\176\208\181\209\130 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131 \209\130\208\190\208\186\208\181\208\189\208\190\208\178. \208\157\209\131\208\182\208\189\208\190 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\209\140 \209\129\208\181\209\128\208\178\208\181\209\128.")
        elseif status == 404 then
            fail("\208\155\208\184\209\129\209\130 \208\184\208\187\208\184 \209\134\208\181\208\187\209\140 \208\177\208\190\208\187\209\140\209\136\208\181 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131.")
        elseif status == 429 then
            fail("\208\161\208\187\208\184\209\136\208\186\208\190\208\188 \208\188\208\189\208\190\208\179\208\190 \208\183\208\176\208\191\209\128\208\190\209\129\208\190\208\178 \208\186 SessionLab. \208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\208\181 \209\135\209\131\209\130\209\140 \208\191\208\190\208\183\208\182\208\181.")
        else
            fail("SessionLab \208\189\208\181 \208\191\209\128\208\184\208\189\209\143\208\187 \208\183\208\176\208\191\209\128\208\190\209\129. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\191\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181, \208\187\208\184\209\129\209\130 \208\184 \208\176\208\186\209\130\208\184\208\178\208\189\209\131\209\142 \209\129\208\181\209\129\209\129\208\184\209\142.")
        end
    end
    options.failure = options.error
    local method
    if body then method = net.Post else method = net.Get end
    if body then
        headers["Content-Type"] = "application/json"
        headers["Idempotency-Key"] = key
        options.data = body
    end
    if type(method) ~= "function" then options.error() return end
    local ok = pcall(method, options)
    if not ok then options.error() end
    if not finished then
        dmhub.Schedule(15, function() fail("SessionLab \208\189\208\181 \208\190\209\130\208\178\208\181\209\130\208\184\208\187 \208\178\208\190\208\178\209\128\208\181\208\188\209\143.") end)
    end
end

local WIDTH = 360
local function label(value, size, color)
    return gui.Label{
        text = value, width = WIDTH - 20, height = "auto", textWrap = true,
        fontSize = size, color = color, halign = "center", vmargin = 3, interactable = false,
    }
end

local function button(text, width, press, accent)
    return gui.Button{
        text = text, width = width, height = 27, fontSize = 13, hmargin = 2, vmargin = 2,
        classes = {"sessionlab-button"}, color = "#f5ecff",
        halign = "center", bgcolor = accent or "#262a3a", bgimage = "panels/square.png", cornerRadius = 5,
        styles = {
            {selectors = {"label", "button", "sessionlab-button", "hover"}, priority = 5,
                bgcolor = "#4b3a78", color = "#ffffff", borderColor = "#c3a8ed"},
            {selectors = {"label", "button", "sessionlab-button", "press"}, priority = 6,
                color = "#ffffff", brightness = 1},
        },
        press = press, swallowPress = true,
    }
end

local openSkills, chooseSheet, sendRoll, openPopup, openMenuForToken, getHud, refreshVitals
local openActions, openTokenMenu, tokenClick, menuRows

local function show(menu, title, content)
    if not active(menu) then return end
    clearSpellRange(menu)
    menu.page = (menu.page or 0) + 1
    local page = {label(title, 13, "#c4b9ed")}
    for _, child in ipairs(content) do page[#page + 1] = child end
    menu.content.children = page
end

local function rollStatus(menu, pending)
    if pending.sending then
        show(menu, pending.label, {label("\208\158\209\130\208\191\209\128\208\176\208\178\208\187\209\143\209\142 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\181\226\128\166", 13, "#bfb2f4")})
    else
        show(menu, pending.label, {
            label(pending.error .. " \208\159\208\181\209\128\208\181\208\180 \208\189\208\190\208\178\209\139\208\188 \208\177\209\128\208\190\209\129\208\186\208\190\208\188 \208\191\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\182\209\131\209\128\208\189\208\176\208\187.", 13, "#f5c592"),
            button("\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \209\141\209\130\208\190\209\130 \208\183\208\176\208\191\209\128\208\190\209\129", WIDTH - 20, function() sendRoll(menu, pending) end),
            button("\208\146\208\181\209\128\208\189\209\131\209\130\209\140\209\129\209\143 \208\186 \208\191\209\128\208\190\208\178\208\181\209\128\208\186\208\176\208\188", WIDTH - 20, function()
                if not active(menu) or state.pending ~= pending then return end
                state.pending = nil
                openSkills(menu)
            end),
        })
    end
end

sendRoll = function(menu, pending)
    if not active(menu) or pending.sending or state.pending ~= pending then return end
    if not tokenStillControlled(menu) then
        pending.error = "\208\162\208\190\208\186\208\181\208\189 \208\177\208\190\208\187\209\140\209\136\208\181 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189."
        rollStatus(menu, pending)
        return
    end
    pending.sending = true
    rollStatus(menu, pending)
    request(pending.path, pending.body, pending.key, function(result)
        local event = result.event or result
        if rawget(_G, RUNTIME) ~= state or state.pending ~= pending then return end
        state.pending = nil
        local payload = event.payload or {}
        local total = payload.roll and tonumber(payload.roll.total)
        local message = "\208\159\209\128\208\190\208\178\208\181\209\128\208\186\208\176 \208\183\208\176\208\191\208\184\209\129\208\176\208\189\208\176 \208\178 \208\182\209\131\209\128\208\189\208\176\208\187 SessionLab"
        if total then message = pending.label .. ": " .. tostring(total) .. " \194\183 \208\190\209\130\208\191\209\128\208\176\208\178\208\187\208\181\208\189\208\190 \208\178 \208\182\209\131\209\128\208\189\208\176\208\187" end
        if pending.animate then
            local ok, err = pcall(pending.animate, payload)
            if not ok then report("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\209\142: " .. safeText(err)) end
        end
        local results, chatResults = {}, {}
        local targets = payload.token_targets or (payload.token_target and {payload.token_target})
        if targets then
            local passed, failed = 0, 0
            for _, target in ipairs(targets) do
                local name = safeText(target.name)
                local outcomes, saves, effectLines = {}, {}, {}
                local parts = target.parts or {}
                for index, part in ipairs(parts) do
                    local outcome = part.save_outcome
                    if outcome == "success" or outcome == "failure" then
                        local save = "\209\129\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 " .. (outcome == "success" and "\208\191\209\128\208\190\208\185\208\180\208\181\208\189" or "\208\191\209\128\208\190\208\178\208\176\208\187\208\181\208\189")
                        if outcome == "success" then passed = passed + 1 else failed = failed + 1 end
                        if tonumber(part.save_total) and tonumber(part.save_dc) then
                            save = save .. " (" .. part.save_total .. " \208\191\209\128\208\190\209\130\208\184\208\178 \208\161\208\155 " .. part.save_dc .. ")"
                        end
                        outcomes[#outcomes + 1] = save
                        saves[#saves + 1] = save
                    else
                        outcomes[#outcomes + 1] = part.hit == false and "\208\191\209\128\208\190\208\188\208\176\209\133"
                            or part.hit == true and "\208\191\208\190\208\191\208\176\208\180\208\176\208\189\208\184\208\181" or "\208\191\209\128\208\184\208\188\208\181\208\189\208\181\208\189\208\190"
                    end
                    local effects = {}
                    for _, effect in ipairs(part.effect_damage or {}) do
                        local damage = tonumber(effect.damage)
                        if damage then
                            effects[#effects + 1] = safeText(effect.name) .. " \226\128\148 " .. damage .. " \209\131\209\128\208\190\208\189\208\176"
                        end
                    end
                    if #effects > 0 then
                        local strike = #parts > 1 and (" \194\183 \208\177\209\128\208\190\209\129\208\190\208\186 " .. index) or ""
                        effectLines[#effectLines + 1] = name .. strike .. " \194\183 " .. table.concat(effects, " / ")
                    end
                end
                if #saves > 0 then
                    local line = name .. " \194\183 " .. table.concat(saves, " / ")
                    chatResults[#chatResults + 1] = line
                    if payload.token_targets then
                        results[#results + 1] = gui.Label{
                            text = line,
                            width = WIDTH - 40, height = 31, halign = "center",
                            fontSize = 12, color = "#f5ecff", textWrap = true, interactable = false,
                        }
                    end
                end
                for _, line in ipairs(effectLines) do
                    chatResults[#chatResults + 1] = line
                    results[#results + 1] = gui.Label{
                        text = line, width = WIDTH - 40, height = 31, halign = "center",
                        fontSize = 12, color = "#f5ecff", textWrap = true, interactable = false,
                    }
                end
                if payload.token_target then
                    message = name .. " \194\183 " ..
                        (target.resolved and table.concat(outcomes, " \194\183 ") or "\209\141\209\132\209\132\208\181\208\186\209\130 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\209\143\208\181\209\130\209\129\209\143 \208\191\208\190 \208\190\208\191\208\184\209\129\208\176\208\189\208\184\209\142")
                end
            end
            if payload.token_targets then
                message = pending.label .. " \194\183 \209\134\208\181\208\187\208\181\208\185 " .. #targets
                if passed + failed > 0 then message = message .. " \194\183 \208\191\209\128\208\190\208\185\208\180\208\181\208\189\208\190 " .. passed .. " \194\183 \208\191\209\128\208\190\208\178\208\176\208\187\208\181\208\189\208\190 " .. failed end
            end
            if #chatResults > 0 and event.visibility == "public" and context() == pending.context and chat and chat.Send then
                pcall(chat.Send, "[SessionLab] " .. pending.label .. "\n" .. table.concat(chatResults, "\n"))
            end
            refreshVitals()
        end
        local shown = state.menu
        if shown and bindingKey(shown) == pending.binding and active(shown) then
            local content = {}
            if #results > 0 then content[#content + 1] = menuRows(results) end
            content[#content + 1] = button(pending.actionKind and "\208\154 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\209\143\208\188" or "\208\149\209\137\209\145 \208\191\209\128\208\190\208\178\208\181\209\128\208\186\208\176", WIDTH - 20, function()
                if pending.actionKind then openActions(shown, pending.sheet, pending.actionKind)
                else openSkills(shown, shown.section) end
            end)
            show(shown, message, content)
        elseif context() == pending.context then
            report(message)
        end
    end, function(message)
        if rawget(_G, RUNTIME) ~= state or state.pending ~= pending then return end
        pending.sending, pending.error = false, message
        local shown = state.menu
        if shown and bindingKey(shown) == pending.binding and active(shown) then
            rollStatus(shown, pending)
        elseif context() == pending.context then
            report(message)
        end
    end)
end

local TOKEN_SCENE = "/api/integrations/dmhub/token-scene/"
local abilities = {
    {"str", "\208\161\208\184\208\187\208\176"}, {"dex", "\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140"}, {"con", "\208\162\208\181\208\187\208\190\209\129\208\187\208\190\208\182\208\181\208\189\208\184\208\181"},
    {"int", "\208\152\208\189\209\130\208\181\208\187\208\187\208\181\208\186\209\130"}, {"wis", "\208\156\209\131\208\180\209\128\208\190\209\129\209\130\209\140"}, {"cha", "\208\165\208\176\209\128\208\184\208\183\208\188\208\176"},
}

local function tokenScene(success, failure, query)
    local game = dmhub.gameid
    if type(game) ~= "string" or not game:match("^[%w_.:%-]+$") then
        failure("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\208\184\209\130\209\140 \208\184\208\179\209\128\209\131 DMHub.")
        return
    end
    request(TOKEN_SCENE .. "?game=" .. game .. (query or ""), nil, nil, success, failure)
end

local function mappedTarget(scene, token)
    for _, row in ipairs(scene and scene.targets or {}) do
        if row.token == token then return row end
    end
end

local function sheetBinding(menu)
    local row = mappedTarget(menu.scene, menu.token)
    if row and id(row.sheet) then return {sheet = row.sheet, name = row.name} end
    return (menu.scene and menu.scene.binding) or allBindings()[bindingKey(menu)]
end

local function scrollList(entries, width, height, contentHeight)
    local scrollable = contentHeight > height
    local shown, goal, writing = 1, nil, false
    local function position(element, value)
        shown = value
        writing = true
        element.vscrollPosition = value
        writing = false
    end
    return gui.Panel{
        width = width, height = height, flow = "vertical", halign = "center",
        children = entries, vscroll = scrollable, vscrollPosition = 1,
        scroll = function(element)
            if writing or not scrollable then return end
            local nextPosition = element.vscrollPosition
            if type(nextPosition) ~= "number" then return end
            local delta = nextPosition - shown
            if math.abs(delta) < 0.0001 then return end
            -- DMHub reports the native scroll position first. Ease wheel movement
            -- from the last visible position, but keep the scrollbar drag direct.
            if (tonumber(dmhub.mouseWheel) or 0) == 0 then
                shown, goal = nextPosition, nil
                element.thinkTime = nil
                return
            end
            goal = math.max(0, math.min(1, (goal or shown) + delta))
            position(element, shown)
            element.thinkTime = 0.016
        end,
        think = function(element)
            if not goal then return end
            local remaining = goal - shown
            if math.abs(remaining) < 0.001 then
                position(element, goal)
                goal = nil
                element.thinkTime = nil
                return
            end
            position(element, shown + remaining * 0.32)
        end,
    }
end

menuRows = function(entries, maxHeight)
    local height = #entries * 31
    return scrollList(entries, WIDTH - 20, math.min(maxHeight or 186, height), height)
end

local function sceneBinding(menu)
    if not active(menu) then return end
    menu.section = "settings"
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\190\208\178 \209\129\209\134\208\181\208\189\209\139\226\128\166", {})
    local page = menu.page
    tokenScene(function(scene)
        if not active(menu) or menu.page ~= page then return end
        if not scene.is_dm or not scene.session then
            show(menu, "\208\159\209\128\208\184\208\178\209\143\208\183\208\186\208\176 \208\186 \209\129\209\134\208\181\208\189\208\181 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\176 \208\188\208\176\209\129\209\130\208\181\209\128\209\131 \208\178 \208\176\208\186\209\130\208\184\208\178\208\189\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184.", {
                button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
            })
            return
        end
        local rows = {}
        local function bind(target)
            if not active(menu) or not tokenStillControlled(menu) then return end
            show(menu, "\208\161\208\190\209\133\209\128\208\176\208\189\209\143\209\142 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131\226\128\166", {})
            request(TOKEN_SCENE, {
                command = "link", session = scene.session, game = dmhub.gameid,
                token = menu.token, target = target,
            }, "sl-link-" .. dmhub.GenerateGuid(), function()
                refreshVitals()
                if active(menu) then openMenuForToken(menu) end
            end, function(message)
                show(menu, message, {button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)})
            end)
        end
        for _, row in ipairs(scene.targets or {}) do
            if id(row.sheet) then
                local target = row.id
                rows[#rows + 1] = button(safeText(row.name) .. " \194\183 #" .. id(target), WIDTH - 40,
                    function() bind(target) end)
            end
        end
        local content = {}
        if #rows > 0 then content[#content + 1] = menuRows(rows) end
        if mappedTarget(scene, menu.token) then
            content[#content + 1] = button("\208\158\209\130\208\178\209\143\208\183\208\176\209\130\209\140 \208\190\209\130 \209\129\209\134\208\181\208\189\209\139", WIDTH - 20, function() bind(0) end)
        end
        content[#content + 1] = button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)
        show(menu, #rows > 0 and "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\176 \209\129\209\134\208\181\208\189\209\139" or "\208\148\208\190\208\177\208\176\208\178\209\140\209\130\208\181 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\190\208\178 \208\178 \208\186\208\190\208\188\208\189\208\176\209\130\208\181 SessionLab.", content)
    end, function(message)
        if active(menu) and menu.page == page then
            show(menu, message, {button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)})
        end
    end)
end

local icons = {
    skill = "ui-icons/d20.png",
    ability = "ui-icons/ph-info-fill.png",
    save = "ui-icons/module-checkmark.png",
    attack = "ui-icons/skills/melee-attack-icon.png",
    settings = "ui-icons/heartclicked.png",
}

local spellIcons = {
    magic = {nil, "#d3b6ff"}, fire = {nil, "#ff9b52"},
    frost = {nil, "#9be0ff"}, healing = {icons.settings, "#88e9b6"},
    lightning = {"ui-icons/ph-arrows-split-fill.png", "#ffdc76"},
    weapon = {icons.attack, "#f1d2a2"},
}

-- Use the exact registered IDs, including compatibility with the older website catalog.
-- Exact image IDs from ImageManager in the supplied DMHub level0.
-- Verified through each registered Sprite to the preview Texture2D.
-- Compatibility aliases for values saved by the earlier website catalog.
local builtinImageIds = {
    ["ui-icons/d20.png"] = "f5e035fd-f702-47d0-afea-d702ce380ca3",
    ["ui-icons/heartclicked.png"] = "6d487bf8-a136-45dd-82b3-04e69d83a643",
    ["ui-icons/module-checkmark.png"] = "423abe11-6570-4656-ae05-f14a4b5788f5",
    ["ui-icons/skills/01_fire_arrow.png"] = "f3b2cf4c-a24e-4aa1-8edd-e7673ee24471",
    ["ui-icons/skills/01_fire_arrow_nobg.png"] = "b9a8a3bd-94d2-4534-accb-6b0ae13c40c5",
    ["ui-icons/skills/02_Big_fire_arrow.png"] = "fa8738bc-3859-4bb1-b1e8-398277e8b267",
    ["ui-icons/skills/02_Big_fire_arrow_nobg.png"] = "5c7d6e81-b7a4-4f82-8aa7-00dcfb6f1ccd",
    ["ui-icons/skills/03_fireball.png"] = "34f5879e-2b82-4f47-8a68-7112a2df6baa",
    ["ui-icons/skills/03_fireball_nobg.png"] = "ec7c0829-cd28-4a38-9d8d-b1e975332f95",
    ["ui-icons/skills/04_fire_rain.png"] = "cca13c82-30d8-4ede-a38a-5cf0275795da",
    ["ui-icons/skills/04_fire_rain_nobg.png"] = "208c2667-78f8-41c3-a8d8-f5933b402efd",
    ["ui-icons/skills/05_Death_blow.png"] = "39a0135f-9913-4a10-9ebf-6a5b2904dd91",
    ["ui-icons/skills/05_Death_blow_nobg.png"] = "c07550b8-f68b-4cbf-94f1-820c74ba977b",
    ["ui-icons/skills/06_Death_blow2.png"] = "b6c2e0f0-1d3c-4215-9917-0ea7934268d5",
    ["ui-icons/skills/06_Death_blow2_nobg.png"] = "c451291d-df72-4ba0-92c6-195e2d7f9136",
    ["ui-icons/skills/07_Death_blow3.png"] = "93530a26-50dd-4129-aa0e-93f2fbacd8d3",
    ["ui-icons/skills/07_Death_blow3_nobg.png"] = "03b9a3e5-1cbf-46fb-8658-9c8cb7a8fee7",
    ["ui-icons/skills/08_Death.png"] = "c9c76ddb-293c-4629-9133-f272d8b4f7a2",
    ["ui-icons/skills/08_Death_nobg.png"] = "d3b2d020-bd03-4b38-a29d-12480b7721c4",
    ["ui-icons/skills/09_Magic_bolt_nobg.png"] = "3c27ae3c-3567-4f53-981e-a36ba7eb5892",
    ["ui-icons/skills/09_magic_bolt.png"] = "02a0e29e-6842-45ee-a5d4-095c3216b4de",
    ["ui-icons/skills/1.png"] = "14e3c9b2-fe24-499e-9cb3-b563ba05cb8b",
    ["ui-icons/skills/10_Magic_bolt2_nobg.png"] = "254b9b30-c241-463d-b196-c81d605fd769",
    ["ui-icons/skills/10_magic_bolt2.png"] = "9596b5e4-1752-45fa-be6b-eddebc4b394d",
    ["ui-icons/skills/11_Magic_bolt3_nobg.png"] = "d1de83f2-9cd4-4c7e-a67c-7268e3ee5e3e",
    ["ui-icons/skills/11_magic_bolt3.png"] = "809ce422-71cb-44d3-bf32-04c33c32da4a",
    ["ui-icons/skills/12_Magic_rain_nobg.png"] = "2247cc5a-b427-42b3-9165-439d8542992f",
    ["ui-icons/skills/12_magic_rain.png"] = "1c3f5728-6f3d-4c4c-add0-73f2ac1f1f4a",
    ["ui-icons/skills/13_Frost_arrow_nobg.png"] = "49e35438-3ad2-4ddf-a11d-88342f6980c2",
    ["ui-icons/skills/13_frost_arrow.png"] = "fab18ef0-eea4-40eb-9d44-7c7c25b1aaa6",
    ["ui-icons/skills/14_Big_frost_arrow_nobg.png"] = "0c976c25-8f76-4052-b1e2-882b27cfa1d2",
    ["ui-icons/skills/14_big_frost_arrow.png"] = "33b57980-7aa6-45f4-836a-5b97fb8638c5",
    ["ui-icons/skills/15_Ice_block.png"] = "566362b8-c3bc-492d-86d0-f78474369645",
    ["ui-icons/skills/15_Ice_block_nobg.png"] = "0701eed9-397f-404c-bf86-2a8535bb3e73",
    ["ui-icons/skills/16_blizzard.png"] = "e111fefb-0ad0-4546-b5ce-2b15f8a04b2e",
    ["ui-icons/skills/16_blizzard_nobg.png"] = "5a9fe4e4-7cd4-46ce-a1df-2f2a7ddb1d53",
    ["ui-icons/skills/17_Shadow_bolt.png"] = "85b13247-0f74-462b-8a5b-739b6c42a65e",
    ["ui-icons/skills/17_shadow_bolt_nobg.png"] = "45cf3cff-39b0-46f1-979a-dd0fdceb1a61",
    ["ui-icons/skills/18_Shadow_bolt2.png"] = "81fed717-97ae-4c4b-893d-397ed603a4af",
    ["ui-icons/skills/18_shadow_bolt2_nobg.png"] = "292e2c43-85f0-4b72-ae5e-1558e004642f",
    ["ui-icons/skills/19_Shadow_bomb.png"] = "d2b2546a-a176-433a-9a8f-ad8fbbd90a67",
    ["ui-icons/skills/19_shadow_bomb_nobg.png"] = "c5a56e25-56ed-4e9b-80a7-a3d3b32b56ea",
    ["ui-icons/skills/20_Shadow_rain.png"] = "b4555b5c-a8b4-4514-8867-f26b5e2f0540",
    ["ui-icons/skills/20_shadow_rain_nobg.png"] = "5f78e724-fc4e-4e5f-a58a-dd4e30bd92e3",
    ["ui-icons/skills/21_Light_arrow.png"] = "0412d92f-3bca-4bb5-af88-f06d6bd12417",
    ["ui-icons/skills/21_Light_arrow_nobg.png"] = "d5bfbbfa-aa93-41c6-bfc2-1775db3bdc6f",
    ["ui-icons/skills/22_Big_Light_arrow.png"] = "08cbf70c-f959-4f21-9075-f1211dd72708",
    ["ui-icons/skills/22_Big_Light_arrow_nobg.png"] = "5eefd60a-1d4a-4ce1-93d6-d56156e093d7",
    ["ui-icons/skills/23_Light_blow.png"] = "e7247530-55a2-4612-b9d9-465aaeddb9b5",
    ["ui-icons/skills/23_Light_blow_nobg.png"] = "0600b8cd-18b8-4c83-b4ea-58b8f22a9bc9",
    ["ui-icons/skills/24_Holy_rain.png"] = "3efeec13-0688-4ace-b00a-087b498a93c7",
    ["ui-icons/skills/24_Holy_rain_nobg.png"] = "74086fe5-dddc-482c-86ce-2202643a01eb",
    ["ui-icons/skills/25_Lightning.png"] = "2eda8f22-413b-4f2c-aab7-65320b926c7b",
    ["ui-icons/skills/25_Lightning_nobg.png"] = "bd1daf2f-3685-4bd7-8e34-f62e347e4ebb",
    ["ui-icons/skills/26_Big_Lightning.png"] = "d623d3a4-5cbb-4221-b33e-14458b22b1a0",
    ["ui-icons/skills/26_Big_Lightning_nobg.png"] = "38c7a2ca-bbe9-45f4-a9f2-6baa48522d68",
    ["ui-icons/skills/27_Storm.png"] = "9d9e27a2-c152-4224-a093-d2081b5c0ffb",
    ["ui-icons/skills/27_Storm_nobg.png"] = "44f0370d-3c9d-4785-9a47-fd6d19b07ec1",
    ["ui-icons/skills/28_Storm2.png"] = "09bafbd8-16a4-4cf0-b044-153f7ff14345",
    ["ui-icons/skills/28_Storm2_nobg.png"] = "b09864a6-c727-493d-8de0-f4cdf2297939",
    ["ui-icons/skills/29_Wave_of_evil.png"] = "01e0e5d4-5c0f-4b14-9f3e-a5c72b55aada",
    ["ui-icons/skills/29_Wave_of_evil_nobg.png"] = "1a0325f6-defa-4b4d-a2cf-368610f0e2fd",
    ["ui-icons/skills/30_Wave_of_evil2.png"] = "654862fa-38dd-47dc-a67e-002e66a648ef",
    ["ui-icons/skills/30_Wave_of_evil2_nobg.png"] = "7a4efb90-6c52-4ad2-adc5-0b7a17f32466",
    ["ui-icons/skills/31_Wave_of_evil3.png"] = "382dc2df-89cb-4660-a0b7-de81970cf6bb",
    ["ui-icons/skills/31_Wave_of_evil3_nobg.png"] = "dc730f19-03ce-4d7d-9007-13fcd9241122",
    ["ui-icons/skills/32_Evil.png"] = "8c28de1f-e1ae-4a09-ad00-2917750ae8b2",
    ["ui-icons/skills/32_Evil_nobg.png"] = "02c2baa0-62fd-4556-8010-a8282e8a96c3",
    ["ui-icons/skills/33_Critical_strike.png"] = "609bb71f-22bb-4f15-abbc-4626ad484e53",
    ["ui-icons/skills/33_Critical_strike_nobg.png"] = "50ee3515-a71c-458c-bb06-20b6bef4d605",
    ["ui-icons/skills/34_Critical_strike2.png"] = "285fc1b9-cb33-471b-bde1-f0373102b998",
    ["ui-icons/skills/34_Critical_strike2_nobg.png"] = "9d6e6bd7-18ae-4d86-bc56-160e5a270df8",
    ["ui-icons/skills/35_Critical_strike3.png"] = "989d9b6e-48ac-491f-b4ef-66b8261c5438",
    ["ui-icons/skills/35_Critical_strike3_nobg.png"] = "df5f3b8f-d6a2-45f3-b86f-b5369207962b",
    ["ui-icons/skills/36_Critical_strike4.png"] = "ea604c00-2717-4b66-b80b-8888182e5cfb",
    ["ui-icons/skills/36_Critical_strike4_nobg.png"] = "ee91cec8-1c4b-463b-b002-4fdbc9039a3f",
    ["ui-icons/skills/98.png"] = "26621f3e-9f6d-435d-9a9f-b4483b1489ed",
    ["ui-icons/skills/Archerskill_01.png"] = "f9e550a2-daef-4472-a52d-7392adf8ca78",
    ["ui-icons/skills/Archerskill_01_nobg.png"] = "99de899d-aaf5-4856-9d2a-86f71af0d08d",
    ["ui-icons/skills/Archerskill_02.png"] = "fd85f3e6-7e7e-4c6c-ae72-c5670f002ac6",
    ["ui-icons/skills/Archerskill_02_nobg.png"] = "e39d565e-1e2d-4629-8098-ce8174005506",
    ["ui-icons/skills/Archerskill_03.png"] = "b3d439c4-d56a-4a7a-b88f-97bb9a7f49a4",
    ["ui-icons/skills/Archerskill_03_nobg.png"] = "00350a01-834d-4230-b097-9fd3fdf1331f",
    ["ui-icons/skills/Archerskill_04.png"] = "3a234b86-0898-470d-b032-72770ab44cbd",
    ["ui-icons/skills/Archerskill_04_nobg.png"] = "2c3ff75c-4149-4f89-810c-2639d391166f",
    ["ui-icons/skills/Archerskill_05.png"] = "71ada33f-431c-46a8-86bc-75b4cc034a95",
    ["ui-icons/skills/Archerskill_05_nobg.png"] = "4e309793-da30-49cd-ba3f-56247e9442ad",
    ["ui-icons/skills/Archerskill_06.png"] = "419a308a-98c5-4872-a12b-5b6a3c5d9188",
    ["ui-icons/skills/Archerskill_06_nobg.png"] = "e0f9943a-fbde-477e-9b14-3071cdb66f38",
    ["ui-icons/skills/Archerskill_07.png"] = "947f7dc6-e7cc-4829-88f2-1aed4f729c57",
    ["ui-icons/skills/Archerskill_07_nobg.png"] = "dbcb0452-c5b1-4fda-abad-098447ac70aa",
    ["ui-icons/skills/Archerskill_08.png"] = "00ef24fa-b2f2-434c-a21f-d04d867918b1",
    ["ui-icons/skills/Archerskill_08_nobg.png"] = "5d9b46ba-9ec5-4584-842f-15a6f075a712",
    ["ui-icons/skills/Archerskill_09.png"] = "749f9e06-a0a9-40d1-91c5-b7f05124d4b1",
    ["ui-icons/skills/Archerskill_09_nobg.png"] = "13f939ea-8718-4ca8-89b5-0d8d6f8c5b78",
    ["ui-icons/skills/Archerskill_10.png"] = "141d1472-5042-42f7-847e-579ea228cd51",
    ["ui-icons/skills/Archerskill_10_nobg.png"] = "aad42024-415d-4ab6-bd50-2b96f97c9c3e",
    ["ui-icons/skills/Archerskill_11.png"] = "5ca5fb64-9aba-4946-8bd2-c7405c082831",
    ["ui-icons/skills/Archerskill_11_nobg.png"] = "0409a700-bd94-4f1f-8877-aa9cca91cd4c",
    ["ui-icons/skills/Archerskill_12.png"] = "e45f938f-47e2-4e3d-a6f4-80596f1f9127",
    ["ui-icons/skills/Archerskill_12_nobg.png"] = "d33c5a35-9c65-4252-af79-8fc521210c50",
    ["ui-icons/skills/Archerskill_13.png"] = "a5bf9d21-936b-4d68-9055-0557f22711e2",
    ["ui-icons/skills/Archerskill_13_nobg.png"] = "f0173912-02da-4a95-953c-25961ed3af20",
    ["ui-icons/skills/Archerskill_14.png"] = "c4613d13-ab89-4c4a-8c3f-4779c5ed1d5d",
    ["ui-icons/skills/Archerskill_14_nobg.png"] = "e2d1e838-b04f-4089-a71a-8c1d3c1c8ac6",
    ["ui-icons/skills/Archerskill_15.png"] = "d2e4a0fc-e07a-41e1-93c2-52c20f934c22",
    ["ui-icons/skills/Archerskill_15_nobg.png"] = "b4a31c43-cf8c-4f52-9867-ebd4e2b5d31d",
    ["ui-icons/skills/Archerskill_16.png"] = "02b6c263-1ec1-404c-92d8-bd4f0495ee68",
    ["ui-icons/skills/Archerskill_16_nobg.png"] = "e23084f6-db54-4258-9662-88cc5649d144",
    ["ui-icons/skills/Archerskill_17.png"] = "3f67a04d-0767-42c7-a066-bbaaeeb034d9",
    ["ui-icons/skills/Archerskill_17_nobg.png"] = "935f9e00-58f3-4923-a5e2-99cfaa6e00b1",
    ["ui-icons/skills/Archerskill_18.png"] = "2f30f5d2-a555-40fc-a9cd-593ef560fcd9",
    ["ui-icons/skills/Archerskill_18_nobg.png"] = "27b00406-5e88-4e35-a445-0832d93cccbb",
    ["ui-icons/skills/Archerskill_19.png"] = "7700b89e-5149-4099-a8a2-9fa457e884b5",
    ["ui-icons/skills/Archerskill_19_nobg.png"] = "8b62f3ed-f6bc-4a1b-91ee-46903aea9471",
    ["ui-icons/skills/Archerskill_20.png"] = "21726121-e3f9-42ae-8b8a-198580807ab7",
    ["ui-icons/skills/Archerskill_20_nobg.png"] = "0f474a60-fa5f-4a79-8a78-83f5de9bcd4d",
    ["ui-icons/skills/Archerskill_21.png"] = "c3b100cd-02fc-4d32-9455-f3a4d71aee7f",
    ["ui-icons/skills/Archerskill_21_nobg.png"] = "c4a4684e-cc9c-4298-a397-edcb788db6e0",
    ["ui-icons/skills/Archerskill_22.png"] = "7ce42b74-f1d8-424c-a30e-c066ddb26f56",
    ["ui-icons/skills/Archerskill_22_nobg.png"] = "1da85e52-3959-4074-bfe7-989cfb3edcd2",
    ["ui-icons/skills/Archerskill_23.png"] = "3eca0078-e632-498f-a22a-26cd4d5abfc9",
    ["ui-icons/skills/Archerskill_23_nobg.png"] = "d8233827-169b-4bb3-9e77-9e4e5ee95638",
    ["ui-icons/skills/Archerskill_24.png"] = "9fcbad6b-fe36-43b5-b2ed-bb7445f4270a",
    ["ui-icons/skills/Archerskill_24_nobg.png"] = "73318d80-9086-48c6-9e2a-d95662193b55",
    ["ui-icons/skills/Archerskill_25.png"] = "e6f45672-186d-4034-8018-41789d5c11cc",
    ["ui-icons/skills/Archerskill_25_nobg.png"] = "c64315ed-1b26-4af9-a691-e45d0f2fdfa0",
    ["ui-icons/skills/Archerskill_26.png"] = "235388d4-f03d-439c-9edc-e77952677a36",
    ["ui-icons/skills/Archerskill_26_nobg.png"] = "33910e8f-07a9-4ce8-a6c8-c061419acae7",
    ["ui-icons/skills/Archerskill_27.png"] = "375fb658-1eb1-4475-9864-a9be7b4e4192",
    ["ui-icons/skills/Archerskill_27_nobg.png"] = "e8e59ada-e82b-418f-9023-1ef944ce6d0a",
    ["ui-icons/skills/Archerskill_28.png"] = "09b86246-79d2-41f3-aa7a-227fd9bef473",
    ["ui-icons/skills/Archerskill_28_nobg.png"] = "37fac9ff-1477-4acd-b37b-7d1d934dbf17",
    ["ui-icons/skills/Archerskill_29.png"] = "8047f3d9-af07-4ffd-84aa-f29edf1480d1",
    ["ui-icons/skills/Archerskill_29_nobg.png"] = "c07b6150-28a7-4a2b-8443-beef5b2eddb9",
    ["ui-icons/skills/Archerskill_30.png"] = "fafe1df5-a666-42c4-a236-a84e73946964",
    ["ui-icons/skills/Archerskill_30_nobg.png"] = "18987061-2119-45cb-ba52-b68f3950929c",
    ["ui-icons/skills/Archerskill_31.png"] = "ff31f21b-e5d8-4593-a199-ffa201deebcc",
    ["ui-icons/skills/Archerskill_31_nobg.png"] = "a29754e4-46e0-457e-8daf-dc5e57c0dceb",
    ["ui-icons/skills/Archerskill_32.png"] = "2e79b5c3-e934-4e12-9ba1-15e082c8c22d",
    ["ui-icons/skills/Archerskill_32_nobg.png"] = "55f374d9-8933-4762-8481-0c390656ca3f",
    ["ui-icons/skills/Archerskill_33.png"] = "8ebd2591-b031-4179-be6c-d53fb85ef78a",
    ["ui-icons/skills/Archerskill_33_nobg.png"] = "f07d12ee-d801-4efd-8251-41a9efb56908",
    ["ui-icons/skills/Archerskill_34.png"] = "075c059f-08d1-4395-83fb-bbcbdacf8df8",
    ["ui-icons/skills/Archerskill_34_nobg.png"] = "b734f0b1-8ddf-4d97-b1e9-04e39af955c3",
    ["ui-icons/skills/Archerskill_35.png"] = "b2b1f747-2c9d-4db0-9866-f94623d286a1",
    ["ui-icons/skills/Archerskill_35_nobg.png"] = "2c20b4a3-9bab-4910-8437-c979b0f9b299",
    ["ui-icons/skills/Archerskill_36.png"] = "c1c46245-6e6c-4b45-b246-78490d2e149b",
    ["ui-icons/skills/Archerskill_36_nobg.png"] = "13128eb1-ed55-4329-87ca-612c14905447",
    ["ui-icons/skills/Archerskill_37.png"] = "90b9ea10-cd63-40e6-a103-6aac89fa7a76",
    ["ui-icons/skills/Archerskill_37_nobg.png"] = "d78be499-f575-4c1a-84ad-45fd9e1f2e6f",
    ["ui-icons/skills/Archerskill_38.png"] = "c55f6e68-b797-491a-9a69-1e23d932f0d1",
    ["ui-icons/skills/Archerskill_38_nobg.png"] = "cca6e192-d534-4fa2-be5e-0d512c9f0d5e",
    ["ui-icons/skills/Archerskill_39.png"] = "9e602f34-69d1-42f9-9527-d57697851464",
    ["ui-icons/skills/Archerskill_39_nobg.png"] = "84b5b527-7204-435a-8607-5c9f3e8c84a2",
    ["ui-icons/skills/Archerskill_40.png"] = "81571f72-a5a6-4c11-b823-016bdbb440b6",
    ["ui-icons/skills/Archerskill_40_nobg.png"] = "b1bc781b-a6a8-4d8d-9652-a530903d95b8",
    ["ui-icons/skills/Archerskill_41.png"] = "b051a163-81c2-4520-ad97-4d7cd7b39809",
    ["ui-icons/skills/Archerskill_41_nobg.png"] = "ae2734fa-24d5-4fe3-87f2-44e762f757cb",
    ["ui-icons/skills/Archerskill_42.png"] = "f79c9ae0-79fd-4452-9d75-1b187870630a",
    ["ui-icons/skills/Archerskill_42_nobg.png"] = "5f460ba4-f6e5-4252-a626-979cfb7f8cd7",
    ["ui-icons/skills/Archerskill_43.png"] = "fcb8df32-ae4c-4372-a123-02dce64d4e37",
    ["ui-icons/skills/Archerskill_43_nobg.png"] = "882660f6-674c-4ad4-ab89-77dbf98c9482",
    ["ui-icons/skills/Archerskill_44.png"] = "7f893546-aa8b-4755-a3db-d5e442d3a6f2",
    ["ui-icons/skills/Archerskill_44_nobg.png"] = "b7f9900d-b5b1-4ea6-8985-9baee76e9860",
    ["ui-icons/skills/Archerskill_45.png"] = "7feb345c-040c-4dd6-8a1e-32c39db6ce6b",
    ["ui-icons/skills/Archerskill_45_nobg.png"] = "8c9c9dd1-1af2-49c1-bb57-2642ffa210ac",
    ["ui-icons/skills/Archerskill_46.png"] = "043edcab-e4e2-4719-ab9d-7f6a9fed957b",
    ["ui-icons/skills/Archerskill_46_nobg.png"] = "02b4e3e3-3dc5-4a87-b96f-89ae716e4160",
    ["ui-icons/skills/Archerskill_47.png"] = "3b56becc-f3ea-4b2c-bf9d-7a2ece3072f2",
    ["ui-icons/skills/Archerskill_47_nobg.png"] = "59b8c5f5-ebb7-4bdb-8bf6-d0b8f849cec7",
    ["ui-icons/skills/Archerskill_48.png"] = "fd6f3f35-41da-4bc7-9f25-229392d033d8",
    ["ui-icons/skills/Archerskill_48_nobg.png"] = "a5ee8d25-0db9-4020-8a6b-d857e285b687",
    ["ui-icons/skills/Archerskill_49.png"] = "0ab3ac0c-34d9-4751-9809-4a21d87671d8",
    ["ui-icons/skills/Archerskill_49_nobg.png"] = "4276c070-812c-4b96-895c-32f27837dd20",
    ["ui-icons/skills/Archerskill_50.png"] = "ee0d7d45-0864-426c-917d-7e06f475f234",
    ["ui-icons/skills/Archerskill_50_nobg.png"] = "6a61be33-aec6-415a-8969-747d60e58b3d",
    ["ui-icons/skills/Assassinskill_01.png"] = "159d6d3b-b9c6-4854-9b55-967e2b690664",
    ["ui-icons/skills/Assassinskill_01_nobg.png"] = "08809b56-e2de-459f-a3dc-2de6e5d3417b",
    ["ui-icons/skills/Assassinskill_02.png"] = "196d3f33-c46e-4a0c-9841-a576068901e1",
    ["ui-icons/skills/Assassinskill_02_nobg.png"] = "234c19c6-39d5-4dd6-8963-678b7e541a36",
    ["ui-icons/skills/Assassinskill_03.png"] = "7a2fd595-7721-43b4-8f98-94bd86b80cc8",
    ["ui-icons/skills/Assassinskill_03_nobg.png"] = "a8052602-68dc-4122-a11d-c9964ca6291b",
    ["ui-icons/skills/Assassinskill_04.png"] = "0083c95b-7065-4d85-b394-8d32a23c6280",
    ["ui-icons/skills/Assassinskill_04_nobg.png"] = "c9843be3-0f5d-4670-b454-fcd29b44a212",
    ["ui-icons/skills/Assassinskill_05.png"] = "b7ea454e-f230-4a0d-9fec-fd7a07291ded",
    ["ui-icons/skills/Assassinskill_05_nobg.png"] = "fc32364f-6538-4eb3-82df-2071dde07f77",
    ["ui-icons/skills/Assassinskill_06.png"] = "a7dc1a88-1d81-4a5e-bf24-f26f822af1ee",
    ["ui-icons/skills/Assassinskill_06_nobg.png"] = "7721f7fa-0360-4763-9587-6ce0b3cfa236",
    ["ui-icons/skills/Assassinskill_07.png"] = "273ac396-16f0-4a84-b71e-3c951ead292b",
    ["ui-icons/skills/Assassinskill_07_nobg.png"] = "11f216f6-5bff-4df3-a9b0-2265da22bd4d",
    ["ui-icons/skills/Assassinskill_08.png"] = "77fb29ce-0e03-4590-a951-e12b0574b345",
    ["ui-icons/skills/Assassinskill_08_nobg.png"] = "0aca50b3-f54c-46a4-b04c-40685f048b02",
    ["ui-icons/skills/Assassinskill_09.png"] = "071efca2-f263-4a34-a6de-302c0fcce9af",
    ["ui-icons/skills/Assassinskill_09_nobg.png"] = "dc8881a9-9155-42c2-a6af-56d3f1e37e2a",
    ["ui-icons/skills/Assassinskill_10.png"] = "b4235aea-7eec-441b-afe0-73bf7b9b44bc",
    ["ui-icons/skills/Assassinskill_10_nobg.png"] = "26bf5c0c-9fe2-498f-9b08-af3ceba67aea",
    ["ui-icons/skills/Assassinskill_11.png"] = "e74149d8-2835-4c73-95c0-6526758bed23",
    ["ui-icons/skills/Assassinskill_11_nobg.png"] = "c93d4996-8e27-4bee-82fe-61ec49eda3ae",
    ["ui-icons/skills/Assassinskill_12.png"] = "3edee95d-29c3-43e8-8df2-7d73261df23b",
    ["ui-icons/skills/Assassinskill_12_nobg.png"] = "8e296ae0-8eea-45e2-9dd6-bdc98e0caf76",
    ["ui-icons/skills/Assassinskill_13.png"] = "693e255d-1e88-491d-a014-3b7a5a8c0f2d",
    ["ui-icons/skills/Assassinskill_13_nobg.png"] = "836da09a-6a6a-436c-a583-9c9531204f42",
    ["ui-icons/skills/Assassinskill_14.png"] = "415cdf7c-9d84-4da0-9bf6-42f81bf645d8",
    ["ui-icons/skills/Assassinskill_14_nobg.png"] = "f4e25467-f7d3-45de-bc4c-ea1836b1555d",
    ["ui-icons/skills/Assassinskill_15.png"] = "f555959c-9df5-491d-9226-cac742bd7bde",
    ["ui-icons/skills/Assassinskill_15_nobg.png"] = "c9082d48-5e8e-463b-a5f9-429007905ff5",
    ["ui-icons/skills/Assassinskill_16.png"] = "0601cc49-bc83-4d5e-b355-7c797c79f65e",
    ["ui-icons/skills/Assassinskill_16_nobg.png"] = "54109b96-8c4b-4b33-be93-481a2b1b3e47",
    ["ui-icons/skills/Assassinskill_17.png"] = "7944b917-14d4-4135-96e0-5517932ea5d7",
    ["ui-icons/skills/Assassinskill_17_nobg.png"] = "77b95de6-5d44-45c9-8f95-43ee2b64cc09",
    ["ui-icons/skills/Assassinskill_18.png"] = "b0ecd07f-85eb-4398-813c-0dbbf8a3a8e7",
    ["ui-icons/skills/Assassinskill_18_nobg.png"] = "9257a659-7cbb-4a69-bbf6-1ae0606db275",
    ["ui-icons/skills/Assassinskill_19.png"] = "0cf7c87b-afbe-400e-9ab8-2f2fe549c939",
    ["ui-icons/skills/Assassinskill_19_nobg.png"] = "4cb67f52-e275-4eda-a707-d7d9ec2cee46",
    ["ui-icons/skills/Assassinskill_20.png"] = "ce44ba94-c578-4dc5-9350-093d65c17169",
    ["ui-icons/skills/Assassinskill_20_nobg.png"] = "214b0a90-af75-4410-800d-096ebbf508df",
    ["ui-icons/skills/Assassinskill_21.png"] = "aedd3862-aa8c-43c4-8043-62d701938001",
    ["ui-icons/skills/Assassinskill_21_nobg.png"] = "69c66460-0a79-48c8-8591-052738b85150",
    ["ui-icons/skills/Assassinskill_22.png"] = "55808e5a-28f3-4a05-99d2-f38a1c6a1ceb",
    ["ui-icons/skills/Assassinskill_22_nobg.png"] = "06c14ac3-3378-4682-b80d-637d6dd3e4fb",
    ["ui-icons/skills/Assassinskill_23.png"] = "c073d110-2867-4422-bf1a-0290d58363fe",
    ["ui-icons/skills/Assassinskill_23_nobg.png"] = "aa5e01d5-5fba-498b-97f5-50c69c2d17c4",
    ["ui-icons/skills/Assassinskill_24.png"] = "2f861968-fdf8-4ddd-995d-c36e06e933e8",
    ["ui-icons/skills/Assassinskill_24_nobg.png"] = "de8726de-e659-4320-a4cf-c474a9a2921e",
    ["ui-icons/skills/Assassinskill_25.png"] = "dd9872bc-d404-445d-a592-b37bba70ee8d",
    ["ui-icons/skills/Assassinskill_25_nobg.png"] = "7aab2e50-0782-4d9b-8d25-e412f2f21f67",
    ["ui-icons/skills/Assassinskill_26.png"] = "8e0fc07b-9b3f-4d7a-a9e2-b3bb7473e4af",
    ["ui-icons/skills/Assassinskill_26_nobg.png"] = "db7b6da6-5100-4ec5-8e30-16c5f223fb09",
    ["ui-icons/skills/Assassinskill_27.png"] = "3b1b8ea6-6619-4fd8-8efd-fd86b7b5a250",
    ["ui-icons/skills/Assassinskill_27_nobg.png"] = "cb60386f-ef25-4579-b27b-76a6b3db4dc9",
    ["ui-icons/skills/Assassinskill_28.png"] = "26f76380-0c1b-45bd-a8e7-d33e1a4a05ca",
    ["ui-icons/skills/Assassinskill_28_nobg.png"] = "31c79e93-7e0a-4a12-be64-d2ba46288a94",
    ["ui-icons/skills/Assassinskill_29.png"] = "c1bd426c-7d61-450e-9f52-d6470716d3a1",
    ["ui-icons/skills/Assassinskill_29_nobg.png"] = "c6549fd6-315e-4072-b704-58ffc09011ec",
    ["ui-icons/skills/Assassinskill_30.png"] = "900eb85d-dfe0-4e38-ba69-20b478cc9e20",
    ["ui-icons/skills/Assassinskill_30_nobg.png"] = "dd487cb2-750b-4242-b4c6-a8cb7d5ab206",
    ["ui-icons/skills/Assassinskill_31.png"] = "dea4d5c6-db65-407a-a832-2bcd12da0205",
    ["ui-icons/skills/Assassinskill_31_nobg.png"] = "80230f4b-4328-44a3-b591-bc546910809a",
    ["ui-icons/skills/Assassinskill_32.png"] = "f2e339d3-5de7-439b-aac8-390207b74626",
    ["ui-icons/skills/Assassinskill_32_nobg.png"] = "8848ce4b-eaf2-4ad2-b961-b4e41008978e",
    ["ui-icons/skills/Assassinskill_33.png"] = "9f43bfbf-40be-46f8-a5ed-910f2d24b3fc",
    ["ui-icons/skills/Assassinskill_33_nobg.png"] = "aca0c55d-aebc-460c-b0b2-f4ec3b51b952",
    ["ui-icons/skills/Assassinskill_34.png"] = "39620150-aad2-4ad8-a2b3-81a8a70da62b",
    ["ui-icons/skills/Assassinskill_34_nobg.png"] = "68cebbe9-8563-4973-962e-945b4863069c",
    ["ui-icons/skills/Assassinskill_35.png"] = "9d96f559-6e88-4629-8269-a193f4b724d2",
    ["ui-icons/skills/Assassinskill_35_nobg.png"] = "fee0e863-5b3f-40ef-a309-51eb6540933f",
    ["ui-icons/skills/Assassinskill_36.png"] = "16daecec-1e6c-4d47-a8e3-1eb3ae9f7351",
    ["ui-icons/skills/Assassinskill_36_nobg.png"] = "948b9a3e-0d21-4fc0-9e5d-dd89f86aa568",
    ["ui-icons/skills/Assassinskill_37.png"] = "8b5c1213-dc28-4180-ac42-5cef36585905",
    ["ui-icons/skills/Assassinskill_37_nobg.png"] = "239bf5f9-5c36-4308-a92d-4339b807b5d4",
    ["ui-icons/skills/Assassinskill_38.png"] = "a2973181-cbea-4976-832e-2a47865eaf24",
    ["ui-icons/skills/Assassinskill_38_nobg.png"] = "4eec30bb-d380-478a-bc5b-10409765cd13",
    ["ui-icons/skills/Assassinskill_39.png"] = "d712f24e-0a5b-4be2-a4e9-dac1de013091",
    ["ui-icons/skills/Assassinskill_39_nobg.png"] = "42baa064-93e3-4261-bf0b-c716c4762dfe",
    ["ui-icons/skills/Assassinskill_40.png"] = "2825a69a-c152-4514-8f4d-819cba6b2fd7",
    ["ui-icons/skills/Assassinskill_40_nobg.png"] = "30f48747-6fae-4853-8284-5c368ac27680",
    ["ui-icons/skills/Assassinskill_41.png"] = "7f858a00-20f4-452c-a59e-9f939d7200fb",
    ["ui-icons/skills/Assassinskill_41_nobg.png"] = "0a8a0a56-2efb-404c-98ef-8fb153965f40",
    ["ui-icons/skills/Assassinskill_42.png"] = "3624b93c-4885-40f7-9a1e-a736e0399068",
    ["ui-icons/skills/Assassinskill_42_nobg.png"] = "b7d76c8c-be2f-44ab-a94a-8f728ccf0fae",
    ["ui-icons/skills/Assassinskill_43.png"] = "d1b0ac80-8ef3-47e8-9893-8d2984fd8f9a",
    ["ui-icons/skills/Assassinskill_43_nobg.png"] = "9415197d-3102-4590-aca0-874cff309136",
    ["ui-icons/skills/Assassinskill_44.png"] = "45633c16-099d-4ebd-91d8-47e203ab76d3",
    ["ui-icons/skills/Assassinskill_44_nobg.png"] = "665024d7-0eef-4fbe-af7f-12b2d2f21bba",
    ["ui-icons/skills/Assassinskill_45.png"] = "122203cb-374d-40f5-8076-9fc42f7e3279",
    ["ui-icons/skills/Assassinskill_45_nobg.png"] = "509fe8bc-0a6b-4eb4-8395-1be604dd3539",
    ["ui-icons/skills/Assassinskill_46.png"] = "ce2a0ebd-7e9a-4703-9811-2cbe6a697710",
    ["ui-icons/skills/Assassinskill_46_nobg.png"] = "b0e12cec-f10f-4be3-9053-76709ed7a322",
    ["ui-icons/skills/Assassinskill_47.png"] = "65366034-1005-4cf4-a97a-6edce76de822",
    ["ui-icons/skills/Assassinskill_47_nobg.png"] = "cf0d21d5-adb9-4ea1-a78a-ff12758d3d3a",
    ["ui-icons/skills/Assassinskill_48.png"] = "8a4277e9-962b-47b5-8d30-8acfc43f29c1",
    ["ui-icons/skills/Assassinskill_48_nobg.png"] = "4793bd06-e59e-4cde-a945-a12ffc1ca052",
    ["ui-icons/skills/Assassinskill_49.png"] = "602d7d21-e243-488a-a3dd-3c6fbfe7dcd8",
    ["ui-icons/skills/Assassinskill_49_nobg.png"] = "51bb0c2e-bebe-4a00-bbe4-e2548f4c1718",
    ["ui-icons/skills/Assassinskill_50.png"] = "794378c8-b24b-402b-a92c-ee461b9f96f3",
    ["ui-icons/skills/Assassinskill_50_nobg.png"] = "9ea94c4f-0ea2-4c5d-946d-b3ae1522aef8",
    ["ui-icons/skills/Bringer_of_death.png"] = "29f58d62-610a-4cb7-8008-f640eeb6585b",
    ["ui-icons/skills/Druideskill_01.png"] = "7ded2593-0881-49f8-8326-0c7046652916",
    ["ui-icons/skills/Druideskill_01_nobg.png"] = "db27fa3a-0a91-4dd8-814c-fe1f1cf1d1cf",
    ["ui-icons/skills/Druideskill_02.png"] = "ed116883-31be-4569-85fe-4162b4aea4f5",
    ["ui-icons/skills/Druideskill_02_nobg.png"] = "965bc506-16f0-430e-a769-8b416974d4e1",
    ["ui-icons/skills/Druideskill_03.png"] = "61042b17-45ca-429d-b1dd-74f2cd772c4f",
    ["ui-icons/skills/Druideskill_03_nobg.png"] = "ed4e9a08-b6b2-4135-b2f0-8d5b5fd90428",
    ["ui-icons/skills/Druideskill_04.png"] = "6bc013f2-381e-4d43-b412-c3cbc177d245",
    ["ui-icons/skills/Druideskill_04_nobg.png"] = "8d497c1c-3645-4728-98ef-61a4e62b20a3",
    ["ui-icons/skills/Druideskill_05.png"] = "5ec57047-b55b-408c-b073-58e06e42f637",
    ["ui-icons/skills/Druideskill_05_nobg.png"] = "e53dc17a-f2a1-4aa0-892c-d2ca913f0bff",
    ["ui-icons/skills/Druideskill_06.png"] = "a884f0d8-1373-424d-b247-e0f421ac3e24",
    ["ui-icons/skills/Druideskill_06_nobg.png"] = "8e51429d-c11a-4c37-b422-7ef6611fba33",
    ["ui-icons/skills/Druideskill_07.png"] = "3820a797-722d-4d88-853b-724d2ee50b5a",
    ["ui-icons/skills/Druideskill_07_nobg.png"] = "4212b874-5082-4f9d-a59f-9be348ade229",
    ["ui-icons/skills/Druideskill_08.png"] = "bba4727c-9098-4046-9710-35038268698d",
    ["ui-icons/skills/Druideskill_08_nobg.png"] = "58240b08-ca6c-4aed-b842-5561797bd484",
    ["ui-icons/skills/Druideskill_09.png"] = "93c33f4a-2d8b-4f11-aa7a-247ae0fcda55",
    ["ui-icons/skills/Druideskill_09_nobg.png"] = "5fab5909-2d54-42cf-ab17-8eb11f16bd42",
    ["ui-icons/skills/Druideskill_10.png"] = "7d13c5b2-393c-4892-97d7-32f01e9a3639",
    ["ui-icons/skills/Druideskill_10_nobg.png"] = "d074b015-fc6f-4859-9dd7-fc40fe421b87",
    ["ui-icons/skills/Druideskill_11.png"] = "6c6fe5c3-6256-4b19-a53c-59ff351e60ea",
    ["ui-icons/skills/Druideskill_11_nobg.png"] = "8ca04383-e05b-455b-98ce-a7900a3cec86",
    ["ui-icons/skills/Druideskill_12.png"] = "626650bf-998d-4334-8d76-856cfc7641fa",
    ["ui-icons/skills/Druideskill_12_nobg.png"] = "46271773-60d7-447b-9514-fcf76d7c136c",
    ["ui-icons/skills/Druideskill_13.png"] = "7940ad82-43a0-4330-a0df-c30bb9899136",
    ["ui-icons/skills/Druideskill_13_nobg.png"] = "d9c66f70-34ce-456c-8953-0ddf50eeb848",
    ["ui-icons/skills/Druideskill_14.png"] = "3c9a6ab2-c9ab-4716-8126-a1db7b3fc81a",
    ["ui-icons/skills/Druideskill_14_nobg.png"] = "8b3550a2-1b43-4697-a6d3-3bad9980ad9b",
    ["ui-icons/skills/Druideskill_15.png"] = "a8573997-9a59-4397-8223-68ff13ee2b86",
    ["ui-icons/skills/Druideskill_15_nobg.png"] = "33775c89-46ba-421b-8b81-b345332fba66",
    ["ui-icons/skills/Druideskill_16.png"] = "2bd10059-309b-48a8-b7b7-53c48252063b",
    ["ui-icons/skills/Druideskill_16_nobg.png"] = "2e4ef50d-3145-4bce-86d5-4399e64fd198",
    ["ui-icons/skills/Druideskill_17.png"] = "2636d21a-d17a-4415-818c-ecc57e7eef59",
    ["ui-icons/skills/Druideskill_17_nobg.png"] = "561678de-eda3-43be-b089-bc342b2b6ff9",
    ["ui-icons/skills/Druideskill_18.png"] = "3ecc4419-32fd-4b56-ba20-a2f53259be85",
    ["ui-icons/skills/Druideskill_18_nobg.png"] = "fafc8008-9070-4e32-afde-d46e6b9f3473",
    ["ui-icons/skills/Druideskill_19.png"] = "c4239fdf-8b56-4cef-83d3-0e38da82d013",
    ["ui-icons/skills/Druideskill_19_nobg.png"] = "e634150c-bfa5-496d-ae50-c68129d71e77",
    ["ui-icons/skills/Druideskill_20.png"] = "dc4023cf-e0b5-4731-be22-12bf1df58b2e",
    ["ui-icons/skills/Druideskill_20_nobg.png"] = "2f737150-8c95-490e-9e46-175cc8767144",
    ["ui-icons/skills/Druideskill_21.png"] = "3e247240-639a-430f-a3dc-abf1952a7960",
    ["ui-icons/skills/Druideskill_21_nobg.png"] = "1b5342b0-726a-41b0-9995-c1452ac42c37",
    ["ui-icons/skills/Druideskill_22.png"] = "66e17dde-214b-406c-adfc-f3ab18082f15",
    ["ui-icons/skills/Druideskill_22_nobg.png"] = "f949fe71-a49b-4b12-b681-fb6a7d16ffb6",
    ["ui-icons/skills/Druideskill_23.png"] = "bc586bdc-8809-4ec5-9972-02abe14d9e18",
    ["ui-icons/skills/Druideskill_23_nobg.png"] = "273b3ae3-9a69-4618-af60-b072e71d0231",
    ["ui-icons/skills/Druideskill_24.png"] = "4e5c4e7b-12fe-448d-8828-a6eeb56a0002",
    ["ui-icons/skills/Druideskill_24_nobg.png"] = "8bd90a50-fcf3-42fe-86ea-81dc687f5542",
    ["ui-icons/skills/Druideskill_25.png"] = "c1073f37-1ce1-40e6-9d8b-bce0e56f7746",
    ["ui-icons/skills/Druideskill_25_nobg.png"] = "fd73d817-c7e7-4d64-b32b-5263b4640883",
    ["ui-icons/skills/Druideskill_26.png"] = "a38acdc9-ab65-4afa-9e90-f7f808d9405a",
    ["ui-icons/skills/Druideskill_26_nobg.png"] = "259288ca-e681-4f8b-a67e-1714a8f23b4b",
    ["ui-icons/skills/Druideskill_27.png"] = "8fa4105a-aa3e-4780-b489-0c282aa5ec76",
    ["ui-icons/skills/Druideskill_27_nobg.png"] = "30353d67-d73a-4b88-b521-932c1ff3e0c9",
    ["ui-icons/skills/Druideskill_28.png"] = "e4240433-08a1-4488-a080-9f2e85dead00",
    ["ui-icons/skills/Druideskill_28_nobg.png"] = "4466f0f2-3768-46ff-8ec0-50992f8ad673",
    ["ui-icons/skills/Druideskill_29.png"] = "4637b298-5a2a-4420-8871-57a2c0385b7f",
    ["ui-icons/skills/Druideskill_29_nobg.png"] = "133d2745-a0fe-4a1f-b2d8-144e2007a9c2",
    ["ui-icons/skills/Druideskill_30.png"] = "dfe85789-d359-4709-9c21-8ba2022f2b97",
    ["ui-icons/skills/Druideskill_30_nobg.png"] = "12b7021e-5fba-43de-96d0-f66f1ef5ed34",
    ["ui-icons/skills/Druideskill_31.png"] = "97647141-05dc-4401-b1e2-0bf56c92985b",
    ["ui-icons/skills/Druideskill_31_nobg.png"] = "9002c087-1e36-4f1b-9fde-854d531044b5",
    ["ui-icons/skills/Druideskill_32.png"] = "568062fb-e042-4c31-a788-b9e0b58c4c75",
    ["ui-icons/skills/Druideskill_32_nobg.png"] = "ebb86458-eaf8-4e48-8945-f39036f1a681",
    ["ui-icons/skills/Druideskill_33.png"] = "937d63be-97ba-436d-9e24-e118b33663c4",
    ["ui-icons/skills/Druideskill_33_nobg.png"] = "b69595cd-52ee-4d20-9aaf-851e32fcd7e5",
    ["ui-icons/skills/Druideskill_34.png"] = "7675271e-45b1-4042-8b20-cfcea61ed492",
    ["ui-icons/skills/Druideskill_34_nobg.png"] = "14133fc7-1505-4c31-a67e-b8684a81aa39",
    ["ui-icons/skills/Druideskill_35.png"] = "d185b144-8bf4-4890-8f8b-d7da075612ae",
    ["ui-icons/skills/Druideskill_35_nobg.png"] = "81c26a2e-ed3a-48ef-97a6-be1f22fd1231",
    ["ui-icons/skills/Druideskill_36.png"] = "67bc7d03-1e90-4d15-94a6-a4af24b818d5",
    ["ui-icons/skills/Druideskill_36_nobg.png"] = "baeac236-ef7a-4398-b744-6084d3c7f28f",
    ["ui-icons/skills/Druideskill_37.png"] = "71858398-4a43-409d-9c44-e01cc8106e62",
    ["ui-icons/skills/Druideskill_37_nobg.png"] = "56a430c8-a37b-4c30-8f61-5f934f6d697f",
    ["ui-icons/skills/Druideskill_38.png"] = "02e61e1d-8597-447a-9db9-318da2c09fb9",
    ["ui-icons/skills/Druideskill_38_nobg.png"] = "d3aea40e-1b71-4871-9499-480c6264dc6b",
    ["ui-icons/skills/Druideskill_39.png"] = "5de05acc-4ea9-423e-b7f4-788da2fd01b0",
    ["ui-icons/skills/Druideskill_39_nobg.png"] = "b0d420a5-dd25-480b-9091-c0b51858c06f",
    ["ui-icons/skills/Druideskill_40.png"] = "1bd13f27-4366-49c9-b51c-5186691ad7fa",
    ["ui-icons/skills/Druideskill_40_nobg.png"] = "6775a35a-5607-48da-83eb-9bdb2ca530af",
    ["ui-icons/skills/Druideskill_41.png"] = "9132431a-964b-4789-a716-55519debe98b",
    ["ui-icons/skills/Druideskill_41_nobg.png"] = "f4ccf88f-fbf6-423d-ac4b-f99f0a0a0632",
    ["ui-icons/skills/Druideskill_42.png"] = "b23c9de6-3762-4122-9614-1b1b7774b7b9",
    ["ui-icons/skills/Druideskill_42_nobg.png"] = "3b462416-a0ef-4401-9430-117ab4c71c1d",
    ["ui-icons/skills/Druideskill_43.png"] = "47fa163f-a75f-4b21-9e93-ee647d19a249",
    ["ui-icons/skills/Druideskill_43_nobg.png"] = "8d8caa4f-7f71-46ad-8233-87451f8dd70c",
    ["ui-icons/skills/Druideskill_44.png"] = "2b29ccde-6ede-4781-9267-518e61cfc0ee",
    ["ui-icons/skills/Druideskill_44_nobg.png"] = "052e86b5-ef47-460e-9c13-14ad169ca7cd",
    ["ui-icons/skills/Druideskill_45.png"] = "a77f20ac-2108-4d94-8b2c-df2a0faa202d",
    ["ui-icons/skills/Druideskill_45_nobg.png"] = "899c8668-b40c-499e-8b83-240b0fc32682",
    ["ui-icons/skills/Druideskill_46.png"] = "36bf8678-a22c-4162-b596-414722ae097e",
    ["ui-icons/skills/Druideskill_46_nobg.png"] = "6a273d10-efc2-47f8-b672-b46062cd07d2",
    ["ui-icons/skills/Druideskill_47.png"] = "a3fd2b87-7cdb-4fc8-b761-a44760badc3b",
    ["ui-icons/skills/Druideskill_47_nobg.png"] = "bda966ab-d4da-4802-a756-fa0e7ce0bad9",
    ["ui-icons/skills/Druideskill_48.png"] = "63667a38-f1ce-40c7-9399-7a6ab60caf10",
    ["ui-icons/skills/Druideskill_48_nobg.png"] = "6fa4a99f-0e73-4fbc-8b24-456cbb4db544",
    ["ui-icons/skills/Druideskill_49.png"] = "c31fd5ef-0cf8-4822-b6b6-025d37790a42",
    ["ui-icons/skills/Druideskill_49_nobg.png"] = "c11f5691-1126-48a2-b85a-da7f03d3869c",
    ["ui-icons/skills/Druideskill_50.png"] = "e8e6eb19-5c45-4a9b-b1ac-ed8e2c3a8c0c",
    ["ui-icons/skills/Druideskill_50_nobg.png"] = "40bc9dd4-e2f8-4689-9beb-cc6b2af9998e",
    ["ui-icons/skills/Engineerskill_01.png"] = "f2bc4dd8-d8b2-4f5d-8e86-d412b077126f",
    ["ui-icons/skills/Engineerskill_01_nobg.png"] = "e81a7307-24c5-4407-b721-58f50113ede2",
    ["ui-icons/skills/Engineerskill_02.png"] = "3e9b012a-0f2f-4fd7-beb5-39f38f70258c",
    ["ui-icons/skills/Engineerskill_02_nobg.png"] = "2d5f1525-4b1c-416f-9b59-4e298a50c85e",
    ["ui-icons/skills/Engineerskill_03.png"] = "da990813-bedb-408a-8269-2d74c4d2642c",
    ["ui-icons/skills/Engineerskill_03_nobg.png"] = "63678094-0180-4259-915b-c55bea28c3f9",
    ["ui-icons/skills/Engineerskill_04.png"] = "65a53346-c371-4ec3-951f-fe4819ff4f14",
    ["ui-icons/skills/Engineerskill_04_nobg.png"] = "6e36a5cd-318c-4354-b841-f5eb3fee7144",
    ["ui-icons/skills/Engineerskill_05.png"] = "a523685e-f368-4774-96d9-f4c59f4527b8",
    ["ui-icons/skills/Engineerskill_05_nobg.png"] = "4fc7070e-bd22-4055-9e51-2af6f3ff034a",
    ["ui-icons/skills/Engineerskill_06.png"] = "54d00db7-f65b-48b8-aeee-65bdc3fc7a99",
    ["ui-icons/skills/Engineerskill_06_nobg.png"] = "23cc68f4-d1bd-46c0-98be-056228c5ddd3",
    ["ui-icons/skills/Engineerskill_07.png"] = "9e420124-f6fb-4391-843d-375368f3edc2",
    ["ui-icons/skills/Engineerskill_07_nobg.png"] = "c950096f-d522-408d-b1c4-24b952b48a51",
    ["ui-icons/skills/Engineerskill_08.png"] = "061ced0d-ebfa-4385-b2cd-4254f0f9be49",
    ["ui-icons/skills/Engineerskill_08_nobg.png"] = "455ee27e-e536-45fc-96c1-da11a1e323ab",
    ["ui-icons/skills/Engineerskill_09.png"] = "c739f435-13eb-4a58-a431-05ca936848a2",
    ["ui-icons/skills/Engineerskill_09_nobg.png"] = "feda842f-72c4-42d2-a6e4-2a8b93aefa64",
    ["ui-icons/skills/Engineerskill_10.png"] = "e16cd2de-599b-44b1-9978-fb83e80ce98a",
    ["ui-icons/skills/Engineerskill_10_nobg.png"] = "3d3cc2d4-77bf-4058-bdeb-48e94409e40d",
    ["ui-icons/skills/Engineerskill_11.png"] = "2b7a66e8-b3b4-49bf-a807-eef6722c8848",
    ["ui-icons/skills/Engineerskill_11_nobg.png"] = "4c4df431-3317-41d7-9559-e182fb1ed76b",
    ["ui-icons/skills/Engineerskill_12.png"] = "f70af544-1bd5-488c-a8ac-08369c268658",
    ["ui-icons/skills/Engineerskill_12_nobg.png"] = "5080b0df-f46b-49c4-ac24-bff57547fc29",
    ["ui-icons/skills/Engineerskill_13.png"] = "d04cdb98-3cf0-402e-a2fc-dfaa5371325d",
    ["ui-icons/skills/Engineerskill_13_nobg.png"] = "ae8b3aaf-1868-4398-b90a-e51e60b3272e",
    ["ui-icons/skills/Engineerskill_14.png"] = "88fc10df-2bc6-41b1-843b-3cd10ffd69f6",
    ["ui-icons/skills/Engineerskill_14_nobg.png"] = "b0bdc60f-d5e8-48eb-b15e-7b1f7c69da0c",
    ["ui-icons/skills/Engineerskill_15.png"] = "27badc8c-728e-4220-b63e-14d2d6221aa6",
    ["ui-icons/skills/Engineerskill_15_nobg.png"] = "4ca7c32e-3739-4776-9aa1-e1c246181c45",
    ["ui-icons/skills/Engineerskill_16.png"] = "28b79fdc-c3e5-41e5-a138-58e0bb59643e",
    ["ui-icons/skills/Engineerskill_16_nobg.png"] = "6ad4d32b-ce81-4a86-8087-bf1222e97461",
    ["ui-icons/skills/Engineerskill_17.png"] = "7be78453-b98f-46af-8bad-3dfd7b4b3f01",
    ["ui-icons/skills/Engineerskill_17_nobg.png"] = "2f2a6e70-f0f2-449f-8e5b-0c191bfeb16f",
    ["ui-icons/skills/Engineerskill_18.png"] = "244cef8e-ada0-4e5a-b189-a93a938914d8",
    ["ui-icons/skills/Engineerskill_18_nobg.png"] = "9f7b7e9b-5990-40aa-9c92-f74cdb846f53",
    ["ui-icons/skills/Engineerskill_19.png"] = "5b206db2-eeb2-4ca7-bfb8-064b5ce8e52a",
    ["ui-icons/skills/Engineerskill_19_nobg.png"] = "d846c9c9-9f12-4370-a539-3989f5a42be9",
    ["ui-icons/skills/Engineerskill_20.png"] = "4e38dd99-16e2-43fb-8d70-3c7085187597",
    ["ui-icons/skills/Engineerskill_20_nobg.png"] = "f7793280-7297-4b35-9086-f1884b8a950e",
    ["ui-icons/skills/Engineerskill_21.png"] = "76002b45-bbf8-408d-bb22-bc5330b1b0c0",
    ["ui-icons/skills/Engineerskill_21_nobg.png"] = "a7ba7358-cb9b-49f2-826c-1bcf29528e8b",
    ["ui-icons/skills/Engineerskill_22.png"] = "adf13665-a440-49b0-8897-f920904c8e65",
    ["ui-icons/skills/Engineerskill_22_nobg.png"] = "0df738a7-25e0-4dff-b6d3-2f35399b5e28",
    ["ui-icons/skills/Engineerskill_23.png"] = "30ebe5ac-3d93-4e1d-8b0e-e0fa35078e55",
    ["ui-icons/skills/Engineerskill_23_nobg.png"] = "9f0a18f6-2fee-443e-bedd-4a67f5137e94",
    ["ui-icons/skills/Engineerskill_24.png"] = "b8d0cd23-b497-4263-b965-2d18b4b7781e",
    ["ui-icons/skills/Engineerskill_24_nobg.png"] = "a5b701c9-adc6-45ad-bad6-5728384bf3a6",
    ["ui-icons/skills/Engineerskill_25.png"] = "1bf153a5-a11c-42f7-b842-62f86be63e71",
    ["ui-icons/skills/Engineerskill_25_nobg.png"] = "983d34bf-a299-4def-9131-ff374f8e0da8",
    ["ui-icons/skills/Engineerskill_26.png"] = "af7ade31-70b4-4a50-b328-2ce125f222fe",
    ["ui-icons/skills/Engineerskill_26_nobg.png"] = "b341867c-de98-43db-9561-881474b015e4",
    ["ui-icons/skills/Engineerskill_27.png"] = "a04cee68-00ef-4c29-a965-ca01156dd296",
    ["ui-icons/skills/Engineerskill_27_nobg.png"] = "97e2777a-1045-4fcd-a56c-8eaf43aec4dd",
    ["ui-icons/skills/Engineerskill_28.png"] = "73d8b0b8-b3da-47ce-a5dd-076dc94824a8",
    ["ui-icons/skills/Engineerskill_28_nobg.png"] = "77dba3d9-e60d-40f4-a0cb-4b866ef34e31",
    ["ui-icons/skills/Engineerskill_29.png"] = "ddf567ff-e29b-4aa2-936c-298044afc9e5",
    ["ui-icons/skills/Engineerskill_29_nobg.png"] = "b2424b8d-8017-4ace-8c3c-620d04d8075b",
    ["ui-icons/skills/Engineerskill_30.png"] = "8dbd4433-1c30-4b5f-ba00-4bb5fe67afe1",
    ["ui-icons/skills/Engineerskill_30_nobg.png"] = "972884f8-3ea5-4b1d-9979-c232b704fb04",
    ["ui-icons/skills/Engineerskill_31.png"] = "989572ab-adb4-4e3d-96dc-b4f935dd5251",
    ["ui-icons/skills/Engineerskill_31_nobg.png"] = "0d3f9594-d36f-415d-9bb1-b7e627f0a312",
    ["ui-icons/skills/Engineerskill_32.png"] = "3aa9b8ce-e263-4968-8a93-c3148bc2f6fa",
    ["ui-icons/skills/Engineerskill_32_nobg.png"] = "2872c9d0-7ea4-4813-9820-2e62f4d4177a",
    ["ui-icons/skills/Engineerskill_33.png"] = "f6a69650-c8c8-4a1f-94ad-0efca6237c1c",
    ["ui-icons/skills/Engineerskill_33_nobg.png"] = "668fc443-f7ae-4ef7-8116-d34870c6389e",
    ["ui-icons/skills/Engineerskill_34.png"] = "7d86a299-2081-492b-8abd-06d6243d95b4",
    ["ui-icons/skills/Engineerskill_34_nobg.png"] = "22b38dc8-3e97-4760-800d-d43ccfd9d8dc",
    ["ui-icons/skills/Engineerskill_35.png"] = "fea4b686-9119-4e78-a968-18203f8219ee",
    ["ui-icons/skills/Engineerskill_35_nobg.png"] = "e8608ee7-b3c9-4f0c-9aae-7013e5223f6b",
    ["ui-icons/skills/Engineerskill_36.png"] = "db7c6745-02d1-4a61-9dd5-591d8d57c28b",
    ["ui-icons/skills/Engineerskill_36_nobg.png"] = "505a95de-4928-4d0c-9e9d-585102f66a3e",
    ["ui-icons/skills/Engineerskill_37.png"] = "b41129dc-6250-47bb-a388-e27235e33a6f",
    ["ui-icons/skills/Engineerskill_37_nobg.png"] = "bc7e9e1a-b0a5-44a7-b225-8141ada0c867",
    ["ui-icons/skills/Engineerskill_38.png"] = "2dab44f9-a732-4d9d-ac8a-301df0eb7323",
    ["ui-icons/skills/Engineerskill_38_nobg.png"] = "efb6a550-9b68-4f42-b519-31377d8a88df",
    ["ui-icons/skills/Engineerskill_39.png"] = "f356120b-cf63-4b58-9847-e597b170db3d",
    ["ui-icons/skills/Engineerskill_39_nobg.png"] = "899be7ec-d799-46bd-9b45-2fe6d4ab86f0",
    ["ui-icons/skills/Engineerskill_40.png"] = "c4234622-47cb-4544-8ea2-8216e37b6380",
    ["ui-icons/skills/Engineerskill_40_nobg.png"] = "e660a499-15bd-4a77-b7e2-8a7b1ab1606e",
    ["ui-icons/skills/Engineerskill_41.png"] = "1ff21a5f-7c9b-4b23-a2da-3cd1158b1e2d",
    ["ui-icons/skills/Engineerskill_41_nobg.png"] = "35ad0bd8-7ee9-48d0-80f8-581a37d73f9f",
    ["ui-icons/skills/Engineerskill_42.png"] = "6f8f7df3-2b6b-4254-9c94-f2c8e899fb44",
    ["ui-icons/skills/Engineerskill_42_nobg.png"] = "2c6ef6e2-117d-469f-9069-ac22b2a45570",
    ["ui-icons/skills/Engineerskill_43.png"] = "d8dd67df-a0eb-4e58-9933-a48d1652e95c",
    ["ui-icons/skills/Engineerskill_43_nobg.png"] = "d62e70c4-1857-4b5e-95be-53283f1da096",
    ["ui-icons/skills/Engineerskill_44.png"] = "935948b4-e23f-4931-a364-7632bee39c39",
    ["ui-icons/skills/Engineerskill_44_nobg.png"] = "7a83eb1d-93ec-4017-9552-342fc92cd4e0",
    ["ui-icons/skills/Engineerskill_45.png"] = "8e2e5d6b-240c-4748-948b-9a1baaac290b",
    ["ui-icons/skills/Engineerskill_45_nobg.png"] = "f012cde6-0052-426c-a8a8-dae7571280fe",
    ["ui-icons/skills/Engineerskill_46.png"] = "a4d1b728-4220-4984-8227-08c947096613",
    ["ui-icons/skills/Engineerskill_46_nobg.png"] = "7b8b0df9-160c-44ab-9881-a98911b14bc0",
    ["ui-icons/skills/Engineerskill_47.png"] = "a0efebb1-1b5c-4542-ad0e-14cb816d698d",
    ["ui-icons/skills/Engineerskill_47_nobg.png"] = "812339b7-1ce9-43be-ade0-70b215e45680",
    ["ui-icons/skills/Engineerskill_48.png"] = "edb94c59-c808-449f-98ae-ad138410cbb5",
    ["ui-icons/skills/Engineerskill_48_nobg.png"] = "7c932c45-0fa1-4a40-a420-60a980120f03",
    ["ui-icons/skills/Engineerskill_49.png"] = "ec1f5c44-0ffa-4284-93ec-68b991603ccf",
    ["ui-icons/skills/Engineerskill_49_nobg.png"] = "229b0fc3-da90-4405-9e58-efc5542496e4",
    ["ui-icons/skills/Engineerskill_50.png"] = "5d7e6088-f30a-4b6f-8e41-8dc2ca06e4a6",
    ["ui-icons/skills/Engineerskill_50_nobg.png"] = "13cff362-8671-40ad-a9d9-2deefe7d713b",
    ["ui-icons/skills/Fire_ray.png"] = "c2d6e02d-146d-4dcb-ac10-84d03cd9e8ff",
    ["ui-icons/skills/Frost_arrow.png"] = "9940add8-c819-4caf-9df0-695b51478b99",
    ["ui-icons/skills/Mageskill_01.png"] = "fd4ca4a8-63ea-4f3a-8d64-d7e3caf8fee8",
    ["ui-icons/skills/Mageskill_01_Nobg.png"] = "67f35e96-23b9-4bc6-8ba3-8889610d5c83",
    ["ui-icons/skills/Mageskill_02.png"] = "005ef424-0099-4fcd-8139-df2b97156cfd",
    ["ui-icons/skills/Mageskill_02_nobg.png"] = "28764437-3020-49bb-bf47-60e2030febec",
    ["ui-icons/skills/Mageskill_03.png"] = "45755dba-286f-4a54-8995-7f4566f59316",
    ["ui-icons/skills/Mageskill_03_nobg.png"] = "30f530d3-4ba9-48b3-93bf-83c9307c949a",
    ["ui-icons/skills/Mageskill_04.png"] = "bb2fe463-0b6f-43e5-a130-5a8a13e30d20",
    ["ui-icons/skills/Mageskill_04_nobg.png"] = "649970cd-8485-4e62-b08b-30e3b5c3f2e0",
    ["ui-icons/skills/Mageskill_05.png"] = "9867bd27-a209-4a4d-8747-8efc083ab27c",
    ["ui-icons/skills/Mageskill_05_nobg.png"] = "27146e5e-7739-4537-a4dd-4fac131de0ab",
    ["ui-icons/skills/Mageskill_06.png"] = "81c50977-74f4-47d0-9e8b-8667345dcfd2",
    ["ui-icons/skills/Mageskill_06_nobg.png"] = "bf63589a-622f-419a-bdc9-cdbe70555264",
    ["ui-icons/skills/Mageskill_07.png"] = "4d7ecb86-ca32-46b0-8c80-727e5b899c70",
    ["ui-icons/skills/Mageskill_07_nobg.png"] = "28975981-db79-49a0-a986-8f010dfd81d0",
    ["ui-icons/skills/Mageskill_08.png"] = "b2922a78-e6d7-4ffe-ae32-fd3d8be1eba7",
    ["ui-icons/skills/Mageskill_08_nobg.png"] = "6b14d938-a5eb-4d11-918e-f6b14c806bb7",
    ["ui-icons/skills/Mageskill_09.png"] = "b3be2296-ed68-41a4-a9d7-128cf2e17ae4",
    ["ui-icons/skills/Mageskill_09_nobg.png"] = "476ecc7e-4645-4a98-8719-85a4a100f421",
    ["ui-icons/skills/Mageskill_10.png"] = "20745cfa-00cd-4414-bea8-f8d1d5611463",
    ["ui-icons/skills/Mageskill_10_nobg.png"] = "7d663876-ba96-4b51-bde1-0f2eb5e4c505",
    ["ui-icons/skills/Mageskill_11.png"] = "4fe34c40-c884-4edf-969a-5480f0ac8baf",
    ["ui-icons/skills/Mageskill_11_nobg.png"] = "e8ffc0a5-f881-4ed1-8bc5-ac8d27f5c091",
    ["ui-icons/skills/Mageskill_12.png"] = "11005490-8fd8-4723-8b2a-df9236fabfc5",
    ["ui-icons/skills/Mageskill_12_nobg.png"] = "0c24e231-8908-4599-982e-593dfde4c7d1",
    ["ui-icons/skills/Mageskill_13.png"] = "4cff5357-7521-4d6a-ab1a-eceda12b13a1",
    ["ui-icons/skills/Mageskill_13_nobg.png"] = "650397b5-b142-4cfc-a760-3f417f96e4d7",
    ["ui-icons/skills/Mageskill_14.png"] = "ad075ff3-7753-4e71-b097-ae6704a4121b",
    ["ui-icons/skills/Mageskill_14_nobg.png"] = "4e0ebae3-c7e2-4d7a-9525-6b4d2b53bfe7",
    ["ui-icons/skills/Mageskill_15.png"] = "0247e90e-62da-47bc-ae05-7de6f2e49f97",
    ["ui-icons/skills/Mageskill_15_nobg.png"] = "40f8f4c2-e4f1-455d-8245-e306d6e61000",
    ["ui-icons/skills/Mageskill_16.png"] = "de4053bb-6e34-4214-8adc-bed2ef1a5ed5",
    ["ui-icons/skills/Mageskill_16_nobg.png"] = "617a4309-85c0-4c45-bc76-d280ed7b9d12",
    ["ui-icons/skills/Mageskill_17.png"] = "dbff62d7-d185-4bb3-bbd1-d82287addf52",
    ["ui-icons/skills/Mageskill_17_nobg.png"] = "94522497-01a6-464e-ac41-f5489191d6e7",
    ["ui-icons/skills/Mageskill_18.png"] = "3a7d0a98-61e7-47fb-a9a3-dffe8a767909",
    ["ui-icons/skills/Mageskill_18_nobg.png"] = "c1d2dbd6-e203-49bc-9905-61c7da29a5de",
    ["ui-icons/skills/Mageskill_19.png"] = "4d036015-f593-46b8-842b-ba2f70424914",
    ["ui-icons/skills/Mageskill_19_nobg.png"] = "48ec3547-72d2-4b13-adbc-b6d8f2c384cd",
    ["ui-icons/skills/Mageskill_20.png"] = "0a08dca1-20bc-44a8-b33d-41f932890064",
    ["ui-icons/skills/Mageskill_20_nobg.png"] = "40754140-d20b-4ee9-b9d6-480e9233d912",
    ["ui-icons/skills/Mageskill_21.png"] = "43f0ec64-3983-4388-a3f3-2e9cdc27b239",
    ["ui-icons/skills/Mageskill_21_nobg.png"] = "f2693203-54e8-4a68-b2da-c16a930955d3",
    ["ui-icons/skills/Mageskill_22.png"] = "9d8ddee9-240e-4125-be96-7677e0482c80",
    ["ui-icons/skills/Mageskill_22_nobg.png"] = "27757bbe-467e-41d1-aba5-5a57ec2b08c4",
    ["ui-icons/skills/Mageskill_23.png"] = "6bcac510-a651-46ec-8838-fb9819727c00",
    ["ui-icons/skills/Mageskill_23_nobg.png"] = "de20aa28-3a0a-43e0-8bbd-cd82a936d4fd",
    ["ui-icons/skills/Mageskill_24.png"] = "51d85188-9b69-4247-80d2-bca0d3433aac",
    ["ui-icons/skills/Mageskill_24_nobg.png"] = "0e9dbce8-8056-4408-b5f6-6d8e1c350b7e",
    ["ui-icons/skills/Mageskill_25.png"] = "54d42ec3-6313-47c9-acc8-895d97f8895f",
    ["ui-icons/skills/Mageskill_25_nobg.png"] = "460a9ee7-331a-40c1-b199-02371304e1b4",
    ["ui-icons/skills/Mageskill_26.png"] = "ba698dfb-0682-41c0-9d61-5aa8ce06829f",
    ["ui-icons/skills/Mageskill_26_nobg.png"] = "a5b321a2-80e2-41f1-9f6c-bd67b8f7e578",
    ["ui-icons/skills/Mageskill_27.png"] = "04a4b1a7-614e-4bea-bf90-47f89f8eae66",
    ["ui-icons/skills/Mageskill_27_nobg.png"] = "d6b5f121-667c-4e7e-9ca0-64d0a35aa421",
    ["ui-icons/skills/Mageskill_28.png"] = "5591a38c-1e75-462c-b0a0-8640c1e6f4a7",
    ["ui-icons/skills/Mageskill_28_nobg.png"] = "1677069b-693f-4460-98a3-fc0f17df9d1a",
    ["ui-icons/skills/Mageskill_29.png"] = "af7b517c-dfa9-46c2-9e2f-242d991d56cc",
    ["ui-icons/skills/Mageskill_29_nobg.png"] = "1f055cd4-a710-441d-9a02-8ba324e09364",
    ["ui-icons/skills/Mageskill_30.png"] = "f7832d77-ad80-4eb4-b534-4d2d21c47f11",
    ["ui-icons/skills/Mageskill_30_nobg.png"] = "8f77462a-98b1-42eb-bf53-8725971c858f",
    ["ui-icons/skills/Mageskill_31.png"] = "2521a2db-11a8-4096-9150-a979f9dcac0b",
    ["ui-icons/skills/Mageskill_31_nobg.png"] = "ba381d56-c145-4361-bad5-b7c939026805",
    ["ui-icons/skills/Mageskill_32.png"] = "34bd987b-fbfe-4a78-a730-a7e7b16bfd62",
    ["ui-icons/skills/Mageskill_32_nobg.png"] = "9d3f6e61-1d02-42f9-884e-97afb9a2a945",
    ["ui-icons/skills/Mageskill_33.png"] = "8b8548bd-8f97-4121-a73f-784c064cc7ae",
    ["ui-icons/skills/Mageskill_33_nobg.png"] = "d8513de7-c130-4f23-a069-acd0349b994b",
    ["ui-icons/skills/Mageskill_34.png"] = "33de259f-d4b2-4133-a229-eedd6b35c0c1",
    ["ui-icons/skills/Mageskill_34_nobg.png"] = "7abd697a-c873-41aa-8cc4-e443e6918448",
    ["ui-icons/skills/Mageskill_35.png"] = "91b3c784-d476-494f-a28b-e9bab4eb4c96",
    ["ui-icons/skills/Mageskill_35_nobg.png"] = "982cd4e3-079d-4d12-bdd9-3453a8595f09",
    ["ui-icons/skills/Mageskill_36.png"] = "25234114-b020-4774-a816-7a4b365b3095",
    ["ui-icons/skills/Mageskill_36_nobg.png"] = "4ea7e0dc-a806-4d01-8670-51bd48a2bdbe",
    ["ui-icons/skills/Mageskill_37.png"] = "0cdd8d68-5715-4e12-b662-9dd5dcb3ff25",
    ["ui-icons/skills/Mageskill_37_nobg.png"] = "db306f5d-108e-46e7-bac5-5521221420f7",
    ["ui-icons/skills/Mageskill_38.png"] = "e0eb5a7e-4c92-4b55-aac1-0c9742402d52",
    ["ui-icons/skills/Mageskill_38_nobg.png"] = "0f9b93b4-c80c-436f-a48d-7267872d07f9",
    ["ui-icons/skills/Mageskill_39.png"] = "f93bddb5-ae55-4ab2-9644-f9f4461ab603",
    ["ui-icons/skills/Mageskill_39_nobg.png"] = "3c1e36ff-3769-4880-bced-a8626672c15e",
    ["ui-icons/skills/Mageskill_40.png"] = "99361f17-a348-48a0-8a55-972fd9071790",
    ["ui-icons/skills/Mageskill_40_nobg.png"] = "efc51168-ca52-4ab8-ae91-060e0322227f",
    ["ui-icons/skills/Mageskill_41.png"] = "a05a0d70-ce56-4977-a6ae-0e67c90b427b",
    ["ui-icons/skills/Mageskill_41_nobg.png"] = "7d43c722-94dc-4bce-bc01-6c34d8e8a4ac",
    ["ui-icons/skills/Mageskill_42.png"] = "894eca1a-cdf2-4bcd-883f-882dd5288419",
    ["ui-icons/skills/Mageskill_42_nobg.png"] = "e1300e0d-8833-410c-a895-805104675c15",
    ["ui-icons/skills/Mageskill_43.png"] = "dc686213-e7df-42da-95a6-2b278c36c50e",
    ["ui-icons/skills/Mageskill_43_nobg.png"] = "fd474a7b-05b5-4404-af3c-3cf3f89b816f",
    ["ui-icons/skills/Mageskill_44.png"] = "146740b1-b09a-4da1-b13b-3956958110cc",
    ["ui-icons/skills/Mageskill_44_nobg.png"] = "6243a2f7-75b3-46a3-a803-f4493a5d93fc",
    ["ui-icons/skills/Mageskill_45.png"] = "6dca355c-017b-4cd5-a8ca-4142eb464064",
    ["ui-icons/skills/Mageskill_45_nobg.png"] = "07060116-e52c-4150-833f-817dd5ecf3e0",
    ["ui-icons/skills/Mageskill_46.png"] = "54fd41ea-b292-4fc6-934a-16d004ccd502",
    ["ui-icons/skills/Mageskill_46_nobg.png"] = "9acc05c4-0d76-4754-9552-bf5d6852c8af",
    ["ui-icons/skills/Mageskill_47.png"] = "f3f6947a-674b-41ea-b7a6-4d1f731151da",
    ["ui-icons/skills/Mageskill_47_nobg.png"] = "fe60ebb0-c358-4077-a354-e2002e882d48",
    ["ui-icons/skills/Mageskill_48.png"] = "ea184959-b45b-4859-9b4b-a6ec9af30e77",
    ["ui-icons/skills/Mageskill_48_nobg.png"] = "3c74134d-6632-4e25-a434-7974fef3cd6a",
    ["ui-icons/skills/Mageskill_49.png"] = "a078522d-cc0e-4123-bc4e-bb952f270487",
    ["ui-icons/skills/Mageskill_49_nobg.png"] = "c2860bb0-5d31-4940-86d4-153752fcd7cb",
    ["ui-icons/skills/Mageskill_50.png"] = "99fbe419-5c7e-4ec6-93ed-1f309aa00ce2",
    ["ui-icons/skills/Mageskill_50_nobg.png"] = "6804faad-1669-46c8-b8ab-8be1a77520ce",
    ["ui-icons/skills/Paladinskill_01.png"] = "c12a60e3-9a18-43a7-a6ad-228834cc5fc2",
    ["ui-icons/skills/Paladinskill_01_nobg.png"] = "c32e1721-f27b-4952-9c9d-8e3f29f0b962",
    ["ui-icons/skills/Paladinskill_02.png"] = "acff8736-72b5-49e1-802f-759123231589",
    ["ui-icons/skills/Paladinskill_02_nobg.png"] = "993542a9-729a-4a50-b017-717777e02ef8",
    ["ui-icons/skills/Paladinskill_03.png"] = "14025287-065b-4c54-85f3-f375d1c4e89e",
    ["ui-icons/skills/Paladinskill_03_nobg.png"] = "a7351356-f733-4c76-a649-1604dbf8a64e",
    ["ui-icons/skills/Paladinskill_04.png"] = "db2cbfdd-23fd-45e2-bd9f-ec116cd608d0",
    ["ui-icons/skills/Paladinskill_04_nobg.png"] = "14abf606-0f5a-4ca7-8997-d748ed8284a6",
    ["ui-icons/skills/Paladinskill_05.png"] = "2f878b52-1c24-4f55-82b3-cfddcb1bb95d",
    ["ui-icons/skills/Paladinskill_05_nobg.png"] = "4d41f833-7e08-4c2b-9cdd-435ec14b8774",
    ["ui-icons/skills/Paladinskill_06.png"] = "a9b3647b-f41f-42c3-bfae-5766bf08ed9a",
    ["ui-icons/skills/Paladinskill_06_nobg.png"] = "c239b8bc-79d3-41c1-bd3e-2f78d7cbaf4d",
    ["ui-icons/skills/Paladinskill_07.png"] = "04e876bc-7e23-4176-87e8-060ee138eb55",
    ["ui-icons/skills/Paladinskill_07_nobg.png"] = "22371de9-6aeb-4e63-b37a-43963cc80b95",
    ["ui-icons/skills/Paladinskill_08.png"] = "d6d8ef65-c1d8-4e55-8063-29acd977350a",
    ["ui-icons/skills/Paladinskill_08_nobg.png"] = "1cd7beff-21d5-4d3b-9ea6-98631c8acfab",
    ["ui-icons/skills/Paladinskill_09.png"] = "e952c994-7f3b-43aa-b4d8-d56e9cf8f9d3",
    ["ui-icons/skills/Paladinskill_09_nobg.png"] = "64365ff4-ac82-49f9-947b-c53b06e410bf",
    ["ui-icons/skills/Paladinskill_10.png"] = "c3447113-3551-4fbf-a4ec-4963c3da6907",
    ["ui-icons/skills/Paladinskill_10_nobg.png"] = "c67ad3e5-353e-42d1-9843-7bc665ac7bf8",
    ["ui-icons/skills/Paladinskill_11.png"] = "26e1e457-066e-451e-b5d3-a3f048743138",
    ["ui-icons/skills/Paladinskill_11_nobg.png"] = "6df4e1d9-e4ce-4e23-885a-20b91fa1c1eb",
    ["ui-icons/skills/Paladinskill_12.png"] = "75db26ae-5c0c-4db0-8e6b-243a912d3d10",
    ["ui-icons/skills/Paladinskill_12_nobg.png"] = "d09418b5-0c94-4247-bfd2-a0d4a5d85b7a",
    ["ui-icons/skills/Paladinskill_13.png"] = "d4b6f1c1-e690-459b-b3a9-ddf9ab6644cd",
    ["ui-icons/skills/Paladinskill_13_nobg.png"] = "978dc2d6-3fa4-4fd5-9d2c-38890c82f1bd",
    ["ui-icons/skills/Paladinskill_14.png"] = "5158fa6b-32e0-45c1-8c19-67a9ee9afc1d",
    ["ui-icons/skills/Paladinskill_14_nobg.png"] = "3a637a7b-40d1-432c-88f3-a59b6d408ce8",
    ["ui-icons/skills/Paladinskill_15.png"] = "c8d2c4b2-55d2-4f11-98d4-87ad4199c36b",
    ["ui-icons/skills/Paladinskill_15_nobg.png"] = "92a88f1f-d50e-4405-ab4a-ff95cde538ba",
    ["ui-icons/skills/Paladinskill_16.png"] = "f0d9a070-053a-48bb-8e46-f63536b69e4e",
    ["ui-icons/skills/Paladinskill_16_nobg.png"] = "50682f5a-fd42-499e-b632-57467163ca89",
    ["ui-icons/skills/Paladinskill_17.png"] = "0a008dff-23a1-4d67-9d10-68045ad264fe",
    ["ui-icons/skills/Paladinskill_17_nobg.png"] = "ae32a2d9-97f4-470e-a80f-d449ceb5a79c",
    ["ui-icons/skills/Paladinskill_18.png"] = "c0604ee4-dac3-47c1-8c4a-d316b156d877",
    ["ui-icons/skills/Paladinskill_18_nobg.png"] = "867c8cec-d9f0-4af9-909e-0ccf7022bb3e",
    ["ui-icons/skills/Paladinskill_19.png"] = "ddf6ed68-4920-4c2a-957a-619a688ffcae",
    ["ui-icons/skills/Paladinskill_19_nobg.png"] = "8e55790f-9478-4da4-af21-c16b9041ea2d",
    ["ui-icons/skills/Paladinskill_20.png"] = "f950619e-7226-4b04-83f1-7bb19967926b",
    ["ui-icons/skills/Paladinskill_20_nobg.png"] = "97ca900e-9f5e-4435-a5af-429f5da4a33b",
    ["ui-icons/skills/Paladinskill_21.png"] = "5aea8d99-7529-4762-b04e-13b9b14849eb",
    ["ui-icons/skills/Paladinskill_21_nobg.png"] = "3406b4e2-8ff3-492c-974b-cdd103127cc5",
    ["ui-icons/skills/Paladinskill_22.png"] = "40496100-41bf-49b6-b7b8-affe18fec86c",
    ["ui-icons/skills/Paladinskill_22_nobg.png"] = "f1804778-9304-4b7c-aa38-c21226b1602f",
    ["ui-icons/skills/Paladinskill_23.png"] = "53b7bf29-bfd7-4ed8-beeb-65428173a2bc",
    ["ui-icons/skills/Paladinskill_23_nobg.png"] = "ea41b9df-61bb-48f9-96b5-653872fbbaf2",
    ["ui-icons/skills/Paladinskill_24.png"] = "489c19f4-5553-4511-a743-667a7bf5cc57",
    ["ui-icons/skills/Paladinskill_24_nobg.png"] = "9a72637b-5197-480e-b756-cf9e9bca6c9c",
    ["ui-icons/skills/Paladinskill_25.png"] = "f28559b4-2b7b-431e-b5da-e6d4f02e3d4e",
    ["ui-icons/skills/Paladinskill_25_nobg.png"] = "12afce84-c134-4314-9ff2-8270e64feb1a",
    ["ui-icons/skills/Paladinskill_26.png"] = "7b91071d-7dad-49ca-9c4f-8c6e21d75f56",
    ["ui-icons/skills/Paladinskill_26_nobg.png"] = "94a5027f-2d1b-4739-9e71-63e1057f9997",
    ["ui-icons/skills/Paladinskill_27.png"] = "c9defaef-f6ff-40ab-a0f0-cb747ed52e51",
    ["ui-icons/skills/Paladinskill_27_nobg.png"] = "d3b8e0dd-5379-44f4-8d3e-ec0437a2b85c",
    ["ui-icons/skills/Paladinskill_28.png"] = "5916757b-8d78-49e4-8f86-046e736f4770",
    ["ui-icons/skills/Paladinskill_28_nobg.png"] = "3a1f0f9a-3355-4991-a6d2-4884f51297c6",
    ["ui-icons/skills/Paladinskill_29.png"] = "8b757b77-9020-4489-9316-14eedb71bbe4",
    ["ui-icons/skills/Paladinskill_29_nobg.png"] = "f6398826-be6f-4a31-b83f-a2229842d759",
    ["ui-icons/skills/Paladinskill_30.png"] = "068c85ca-ed21-423a-91d9-2dca2b7e5d1b",
    ["ui-icons/skills/Paladinskill_30_nobg.png"] = "90021fef-fd59-474b-9ed1-27313548db12",
    ["ui-icons/skills/Paladinskill_31.png"] = "aea9ba1a-ebe6-4886-82c5-962ab45d0a06",
    ["ui-icons/skills/Paladinskill_31_nobg.png"] = "ad94e4dc-7243-45ec-b108-5dba5d27013b",
    ["ui-icons/skills/Paladinskill_32.png"] = "c03bf66d-48da-4fc9-b78f-d1a93e26a2f8",
    ["ui-icons/skills/Paladinskill_32_nobg.png"] = "c3f10882-9497-4777-8d70-2def7fce77c0",
    ["ui-icons/skills/Paladinskill_33.png"] = "a32381a8-a74c-438a-b329-2c098aefbb4d",
    ["ui-icons/skills/Paladinskill_33_nobg.png"] = "21c4c19c-02da-4ee5-9320-5f08fbfadacb",
    ["ui-icons/skills/Paladinskill_34.png"] = "b59f6ca5-6951-469c-881f-260650d5578e",
    ["ui-icons/skills/Paladinskill_34_nobg.png"] = "65056bec-f4e0-4490-9c3f-1d8103bee802",
    ["ui-icons/skills/Paladinskill_35.png"] = "88d5e9ab-d550-4be8-9133-c81f4f220040",
    ["ui-icons/skills/Paladinskill_35_nobg.png"] = "a891c72b-93c5-42db-a1c7-925454848f08",
    ["ui-icons/skills/Paladinskill_36.png"] = "abfa1031-52f2-4a48-a7ad-9c487a2acc0e",
    ["ui-icons/skills/Paladinskill_36_nobg.png"] = "5788706f-d909-4a53-8501-8cfbb8e742e0",
    ["ui-icons/skills/Paladinskill_37.png"] = "d459960c-eebb-4c96-9d5c-163bbe9e1bbe",
    ["ui-icons/skills/Paladinskill_37_nobg.png"] = "3c65d6e8-cc5f-4e1a-ac33-bad28d031cab",
    ["ui-icons/skills/Paladinskill_38.png"] = "569f9338-110b-4b03-855f-4408d0a820a2",
    ["ui-icons/skills/Paladinskill_38_nobg.png"] = "5c860678-b869-4d36-ad6e-1977f8cb3d12",
    ["ui-icons/skills/Paladinskill_39.png"] = "6673d3df-b7c8-4d44-ae81-776298bd06d4",
    ["ui-icons/skills/Paladinskill_39_nobg.png"] = "4cd0bfd8-f2bf-415a-b0b2-9ad3992579e9",
    ["ui-icons/skills/Paladinskill_40.png"] = "89865acc-b199-461d-bc56-89db93daf2c5",
    ["ui-icons/skills/Paladinskill_40_nobg.png"] = "fb696557-364a-4f7d-832a-88d126131785",
    ["ui-icons/skills/Paladinskill_41.png"] = "efefc1bc-42c5-48bb-969e-6d5b9792650a",
    ["ui-icons/skills/Paladinskill_41_nobg.png"] = "b491fadb-8a69-473e-979c-083f836f9266",
    ["ui-icons/skills/Paladinskill_42.png"] = "69fb1842-e5f0-4ed3-b391-9b7cba78102d",
    ["ui-icons/skills/Paladinskill_42_nobg.png"] = "3821d494-d0b8-4fc8-91b1-514fe2fa1df2",
    ["ui-icons/skills/Paladinskill_43.png"] = "b2602514-c9df-4b57-b267-23a7d7c5f114",
    ["ui-icons/skills/Paladinskill_43_nobg.png"] = "7acd6948-7317-4c13-833d-cbd859cac720",
    ["ui-icons/skills/Paladinskill_44.png"] = "90521349-9624-44e6-818c-2f725eb0921a",
    ["ui-icons/skills/Paladinskill_44_nobg.png"] = "2f07fa9c-531c-4ea6-8d64-dc7c44be5c62",
    ["ui-icons/skills/Paladinskill_45.png"] = "b47f70e5-aa28-48e8-bf1a-76b64279d5d0",
    ["ui-icons/skills/Paladinskill_45_nobg.png"] = "9192d7e7-a412-4414-9d3d-ff8a5784706f",
    ["ui-icons/skills/Paladinskill_46.png"] = "9f99f99e-1ca8-4509-8f27-b83e0d327d29",
    ["ui-icons/skills/Paladinskill_46_nobg.png"] = "9f0014b3-97ad-4aa0-810d-6edea0bab44b",
    ["ui-icons/skills/Paladinskill_47.png"] = "fcbbd098-c482-412b-9e67-be34b531702a",
    ["ui-icons/skills/Paladinskill_47_nobg.png"] = "d7c1b3dd-f8a3-4cff-82b7-8e7bab7a19ca",
    ["ui-icons/skills/Paladinskill_48.png"] = "fd4ebbd1-9c6c-4ee0-ba78-522b605d8c80",
    ["ui-icons/skills/Paladinskill_48_nobg.png"] = "d02edf72-2d3a-4122-8459-65b4e8768c7b",
    ["ui-icons/skills/Paladinskill_49.png"] = "ea494dff-1653-4922-90f9-44434b31e3a8",
    ["ui-icons/skills/Paladinskill_49_nobg.png"] = "113289c2-9c5c-42ea-b28b-0e0692f8627a",
    ["ui-icons/skills/Paladinskill_50.png"] = "06a9bf2d-5d3b-42df-8aba-f70f81243933",
    ["ui-icons/skills/Paladinskill_50_nobg.png"] = "787f6105-d4ba-44b6-8547-055add16c791",
    ["ui-icons/skills/Priestskill_01.png"] = "61a06901-c5e1-4d74-8ec1-5f9a803a3699",
    ["ui-icons/skills/Priestskill_01_nobg.png"] = "695607e8-5bdc-4e98-8240-8ac731548d5c",
    ["ui-icons/skills/Priestskill_02.png"] = "94716f1c-a850-4271-ac7f-507764a9f094",
    ["ui-icons/skills/Priestskill_02_nobg.png"] = "0e7ebd0a-8f5b-4d44-b586-bf86f13bb6aa",
    ["ui-icons/skills/Priestskill_03.png"] = "dd94545b-d5ef-480d-a485-1d308667655f",
    ["ui-icons/skills/Priestskill_03_nobg.png"] = "7f81b1b6-8f35-4531-82db-27876c4a51ab",
    ["ui-icons/skills/Priestskill_04.png"] = "82e88bb4-83f3-470f-8ce9-9ac2b0aed8b7",
    ["ui-icons/skills/Priestskill_04_nobg.png"] = "6fbc6207-a76e-4a6b-82a2-4a57df94846f",
    ["ui-icons/skills/Priestskill_05.png"] = "8f5557f6-0ffe-4e93-a6f0-eb63d1059cf8",
    ["ui-icons/skills/Priestskill_05_nobg.png"] = "359fdf4e-d5b6-446c-8066-4a41813abd8f",
    ["ui-icons/skills/Priestskill_06.png"] = "52eca302-ed65-46dd-9aaa-96842800e204",
    ["ui-icons/skills/Priestskill_06_nobg.png"] = "74da115c-f1ec-475f-bd95-b4945ae1f8f5",
    ["ui-icons/skills/Priestskill_07.png"] = "a0e206f7-219f-4dce-ac30-677a9ec52a2a",
    ["ui-icons/skills/Priestskill_07_nobg.png"] = "7ace205f-7d4e-4887-88ae-b264f7b9aacf",
    ["ui-icons/skills/Priestskill_08.png"] = "32b8bec0-fc16-4432-89b3-06b3ef349218",
    ["ui-icons/skills/Priestskill_08_nobg.png"] = "d16bd3f7-10cb-4e65-826a-acc59d0d6e81",
    ["ui-icons/skills/Priestskill_09.png"] = "6b02ff1f-f5d2-4986-8c1a-4153fae7aa76",
    ["ui-icons/skills/Priestskill_09_nobg.png"] = "56bf8728-b16c-4088-a3cc-5b1069852c0c",
    ["ui-icons/skills/Priestskill_10.png"] = "71ee4c04-f4ba-4feb-9428-8457222aed5b",
    ["ui-icons/skills/Priestskill_10_nobg.png"] = "086322ef-89cb-4c70-aabd-67ea15c25a60",
    ["ui-icons/skills/Priestskill_11.png"] = "0382298c-b28a-469a-88a1-173e570a804d",
    ["ui-icons/skills/Priestskill_11_nobg.png"] = "ecbf7928-fb22-4b11-964b-dc55e212a641",
    ["ui-icons/skills/Priestskill_12.png"] = "e22aea46-149b-480e-9896-4dd06a4c5ed6",
    ["ui-icons/skills/Priestskill_12_nobg.png"] = "86eeeedc-fb39-4fb6-aad5-61f1d2169bdc",
    ["ui-icons/skills/Priestskill_13.png"] = "63ab9e58-a317-494d-8348-82df4cc16077",
    ["ui-icons/skills/Priestskill_13_nobg.png"] = "09bc8e97-c4bd-45cd-a1a8-78e542a26e27",
    ["ui-icons/skills/Priestskill_14.png"] = "9bfd5dea-7c2e-49da-8931-06621c06ab11",
    ["ui-icons/skills/Priestskill_14_nobg.png"] = "d65109ed-8d33-4206-afcf-31f9ab2f3c41",
    ["ui-icons/skills/Priestskill_15.png"] = "c3369254-93f1-4904-a241-0dfde27e981f",
    ["ui-icons/skills/Priestskill_15_nobg.png"] = "d6e47dcb-2e4a-48e2-b51c-48cbf1ea7ebd",
    ["ui-icons/skills/Priestskill_16.png"] = "ea74714b-f198-4ce8-91e3-c362e5b0ec7e",
    ["ui-icons/skills/Priestskill_16_nobg.png"] = "5557e3ad-e98f-4f7b-abbc-63949c1dfcf1",
    ["ui-icons/skills/Priestskill_17.png"] = "a76fb4a9-b8db-43bc-aa03-89705f1e105f",
    ["ui-icons/skills/Priestskill_17_nobg.png"] = "5fe96917-7fec-4685-b950-7f26677613f8",
    ["ui-icons/skills/Priestskill_18.png"] = "589e82f0-5a53-43d9-9e7d-bbf825897d35",
    ["ui-icons/skills/Priestskill_18_nobg.png"] = "9f6a511e-df6b-45dd-a8af-ec7be15ccce7",
    ["ui-icons/skills/Priestskill_19.png"] = "380f2db4-a037-47ec-ae8a-05a751fb30d0",
    ["ui-icons/skills/Priestskill_19_nobg.png"] = "35c92439-c1fe-4f2a-a014-28d969887011",
    ["ui-icons/skills/Priestskill_20.png"] = "1ab8c750-d52a-4e92-b394-9cfd565160aa",
    ["ui-icons/skills/Priestskill_20_nobg.png"] = "3e8c67d7-1560-4871-9654-f7ab268e9ed0",
    ["ui-icons/skills/Priestskill_21.png"] = "0dcf74b7-bfa3-4e85-82cc-c67e0c5d6d52",
    ["ui-icons/skills/Priestskill_21_nobg.png"] = "6f215943-e52d-4362-b8df-ad570df6d34f",
    ["ui-icons/skills/Priestskill_22.png"] = "9c7f1f6a-c132-4219-99aa-dd709e62119f",
    ["ui-icons/skills/Priestskill_22_nobg.png"] = "607b306f-eacb-47a1-9238-90ff4c283a70",
    ["ui-icons/skills/Priestskill_23.png"] = "f2ad30ef-ee19-4515-97dc-12c7e3e63598",
    ["ui-icons/skills/Priestskill_23_nobg.png"] = "60743e5d-f85e-4825-962a-fcababadcb3a",
    ["ui-icons/skills/Priestskill_24.png"] = "909c0cea-4adf-47ca-9b20-8ba1ab21a364",
    ["ui-icons/skills/Priestskill_24_nobg.png"] = "979c4d0d-d563-4a8f-8173-edf6d373a67c",
    ["ui-icons/skills/Priestskill_25.png"] = "705418c4-b938-42d3-a9ea-9f76dd8662d7",
    ["ui-icons/skills/Priestskill_25_nobg.png"] = "ace3765b-e5a9-4d58-96d7-5bdbc1a6c096",
    ["ui-icons/skills/Priestskill_26.png"] = "9859e71b-eee7-4320-b991-4ea5603d8c05",
    ["ui-icons/skills/Priestskill_26_nobg.png"] = "fb9ba6b7-3cbe-4d60-9104-4d72cb0c8ef2",
    ["ui-icons/skills/Priestskill_27.png"] = "c672d7b2-525a-40a4-886b-72748fd42b85",
    ["ui-icons/skills/Priestskill_27_nobg.png"] = "9973d0ac-f358-4241-9c92-04e5a165be09",
    ["ui-icons/skills/Priestskill_28.png"] = "11943df8-dbeb-4863-bef9-8974c14d2303",
    ["ui-icons/skills/Priestskill_28_nobg.png"] = "7496ee60-7554-467d-ad91-e61c846e1334",
    ["ui-icons/skills/Priestskill_29.png"] = "8c5e6801-d447-4aaf-abc2-426ff5a51838",
    ["ui-icons/skills/Priestskill_29_nobg.png"] = "9bc23226-3b8c-460b-bb8b-8e41fe74cbed",
    ["ui-icons/skills/Priestskill_30.png"] = "40fbcd92-db97-496b-8dc5-49dd5aea91ed",
    ["ui-icons/skills/Priestskill_30_nobg.png"] = "85329220-d804-416f-8d94-0b97b00453d9",
    ["ui-icons/skills/Priestskill_31.png"] = "bd27cd0f-09c1-488c-a717-8f4512926e39",
    ["ui-icons/skills/Priestskill_31_nobg.png"] = "c7346b17-51d2-492b-8d3c-db792337a578",
    ["ui-icons/skills/Priestskill_32.png"] = "d76f531f-7fb0-488f-8b89-9f2eb044e451",
    ["ui-icons/skills/Priestskill_32_nobg.png"] = "322849b7-1ba7-4dd0-94cb-f4fb78a0438c",
    ["ui-icons/skills/Priestskill_33.png"] = "10e7311d-ba43-4c37-9ac4-87472e10d7c4",
    ["ui-icons/skills/Priestskill_33_nobg.png"] = "32273559-deba-4127-b8e5-cfe2b0bbbed4",
    ["ui-icons/skills/Priestskill_34.png"] = "11b47e78-db3e-4e73-abf3-c2608ebb538f",
    ["ui-icons/skills/Priestskill_34_nobg.png"] = "938c1f05-eec3-44a0-9384-af57d38e5b93",
    ["ui-icons/skills/Priestskill_35.png"] = "c20ca23b-12ca-4ba7-aa06-6178c805eba4",
    ["ui-icons/skills/Priestskill_35_nobg.png"] = "354ac2e7-b310-4679-a395-f3a54cd9d09f",
    ["ui-icons/skills/Priestskill_36.png"] = "4f7b74fc-a963-4b85-887c-68749481e85c",
    ["ui-icons/skills/Priestskill_36_nobg.png"] = "35dad2aa-7e3f-4c02-997e-3a47b429515b",
    ["ui-icons/skills/Priestskill_37.png"] = "74a4a46c-7f10-43b8-902f-ca72e6563c40",
    ["ui-icons/skills/Priestskill_37_nobg.png"] = "97d0dae9-89f9-4b4f-8d4b-ee9687818c10",
    ["ui-icons/skills/Priestskill_38.png"] = "4a7bf718-0dab-4d18-94c8-ad183917d8e4",
    ["ui-icons/skills/Priestskill_38_nobg.png"] = "8c509c5b-d5c0-4d1e-83e8-b52a8f4fa59a",
    ["ui-icons/skills/Priestskill_39.png"] = "060be5ec-d25b-4c72-bc26-cee7aea686e2",
    ["ui-icons/skills/Priestskill_39_nobg.png"] = "6ccf2483-6795-4f1e-b1a5-5e8fd2ffcfb1",
    ["ui-icons/skills/Priestskill_40.png"] = "835a588f-18bb-44b2-bc30-2ad1e1d32547",
    ["ui-icons/skills/Priestskill_40_nobg.png"] = "2fac1f36-c436-41e7-975a-d65e15be3324",
    ["ui-icons/skills/Priestskill_41.png"] = "2ef27944-c188-42ef-9e39-7754ccdd5712",
    ["ui-icons/skills/Priestskill_41_nobg.png"] = "824213a0-ed31-4c26-b799-69deb95ab7ec",
    ["ui-icons/skills/Priestskill_42.png"] = "87a78852-b53c-4b78-9e4f-0c4b48939b15",
    ["ui-icons/skills/Priestskill_42_nobg.png"] = "f3debab7-5ba2-4694-8887-dd4d3fb6516b",
    ["ui-icons/skills/Priestskill_43.png"] = "6ff76a1a-4164-46de-ab8a-e88341ec386b",
    ["ui-icons/skills/Priestskill_43_nobg.png"] = "2610fdce-6f6b-434d-86b4-a004f056b1d7",
    ["ui-icons/skills/Priestskill_44.png"] = "8b6ee9dc-6fc6-402b-97db-4a9ad14bb091",
    ["ui-icons/skills/Priestskill_44_nobg.png"] = "bbde2dc5-73d0-453c-80d0-c96e76bd3102",
    ["ui-icons/skills/Priestskill_45.png"] = "37d03e08-2114-4391-8559-26d83f753569",
    ["ui-icons/skills/Priestskill_45_nobg.png"] = "ee3beeee-35ec-4f7b-befc-53cf7a581900",
    ["ui-icons/skills/Priestskill_46.png"] = "87d01eeb-9689-4828-ab1f-cefb175a542a",
    ["ui-icons/skills/Priestskill_46_nobg.png"] = "3f540bbe-b61f-416c-83f4-5a89b1646377",
    ["ui-icons/skills/Priestskill_47.png"] = "6082a264-8c92-43c0-b7e7-aec475a0917e",
    ["ui-icons/skills/Priestskill_47_nobg.png"] = "0c170b76-428f-4500-8eba-1bb5f94104af",
    ["ui-icons/skills/Priestskill_48.png"] = "de8a1025-4d99-4f3d-b8ee-3f157e083cda",
    ["ui-icons/skills/Priestskill_48_nobg.png"] = "f7b24356-0fcb-4cd5-b3c5-b00832cd8494",
    ["ui-icons/skills/Priestskill_49.png"] = "8c3e455f-e835-4bcb-a09d-afbc3f83d98f",
    ["ui-icons/skills/Priestskill_49_nobg.png"] = "d885ff5d-aa17-4bc9-bda3-aef61d596e4d",
    ["ui-icons/skills/Priestskill_50.png"] = "1b9f3d0d-10ad-4c97-8db8-da6b566b3df2",
    ["ui-icons/skills/Priestskill_50_nobg.png"] = "aabe466f-588b-4938-858d-fb943aaa0173",
    ["ui-icons/skills/Shamanskill_01.png"] = "be610f68-da3b-4067-9d83-b7c56cf006b7",
    ["ui-icons/skills/Shamanskill_01_nobg.png"] = "e272ccd7-7a2f-4eb2-87c7-b9541a15768d",
    ["ui-icons/skills/Shamanskill_02.png"] = "f6a024ec-e794-4390-a069-b21acb1731c5",
    ["ui-icons/skills/Shamanskill_02_nobg.png"] = "fe3c958f-ba8a-485f-accb-1f4bcc6fba43",
    ["ui-icons/skills/Shamanskill_03.png"] = "ec6bc428-544e-4e8d-b479-a08a6845f14b",
    ["ui-icons/skills/Shamanskill_03_nobg.png"] = "852266c1-91cb-4ebc-a027-458bd231ffbb",
    ["ui-icons/skills/Shamanskill_04.png"] = "a4916b20-c910-4015-aa58-8a7da84e5bbd",
    ["ui-icons/skills/Shamanskill_04_nobg.png"] = "b17c011d-62fd-4c6b-aeec-e24beb6f4a2b",
    ["ui-icons/skills/Shamanskill_05.png"] = "53aa0ec8-bed8-429d-b5ef-f06ba28ae260",
    ["ui-icons/skills/Shamanskill_05_nobg.png"] = "c2a9a7dc-53f5-4b9b-a837-63d9bd3d95bc",
    ["ui-icons/skills/Shamanskill_06.png"] = "dbca2308-a138-440c-a298-3b5e2c0ba71a",
    ["ui-icons/skills/Shamanskill_06_nobg.png"] = "d9b75b3b-52aa-45ab-a8b2-d348623ea25b",
    ["ui-icons/skills/Shamanskill_07.png"] = "1f1b48e1-0fc3-4462-a643-98df54a48c66",
    ["ui-icons/skills/Shamanskill_07_nobg.png"] = "a1790f8f-d342-4dc8-adc7-a0dc2b165800",
    ["ui-icons/skills/Shamanskill_08.png"] = "4332652b-ada6-4814-91fb-d47cfc943b12",
    ["ui-icons/skills/Shamanskill_08_nobg.png"] = "1c51e050-cf9f-4a65-a14b-c669f462b15f",
    ["ui-icons/skills/Shamanskill_09.png"] = "8d1d4a7f-ec94-478e-9321-58f730a1aa9a",
    ["ui-icons/skills/Shamanskill_09_nobg.png"] = "40cb60ba-4bff-456f-8c2f-95627123889d",
    ["ui-icons/skills/Shamanskill_10.png"] = "181daec2-55bc-4e14-9df6-ee6fd62cec5e",
    ["ui-icons/skills/Shamanskill_10_nobg.png"] = "a00c040e-a67a-49b0-a25b-2959a77ec40b",
    ["ui-icons/skills/Shamanskill_11.png"] = "bc8e5890-cc56-44b2-ab65-97dda118b32e",
    ["ui-icons/skills/Shamanskill_11_nobg.png"] = "d256cf55-aa2b-4c07-ad7a-bd706ac6802d",
    ["ui-icons/skills/Shamanskill_12.png"] = "e98334e0-d3e6-470d-8ac9-b016834fde3c",
    ["ui-icons/skills/Shamanskill_12_nobg.png"] = "57c1c978-3658-489d-8918-205e6766125a",
    ["ui-icons/skills/Shamanskill_13.png"] = "6c0a6154-ce47-4b96-aad8-8ea56ea74950",
    ["ui-icons/skills/Shamanskill_13_nobg.png"] = "52e1db2d-f76a-4f9f-b152-2647acb32b20",
    ["ui-icons/skills/Shamanskill_14.png"] = "b12de162-7fb7-4234-9e64-43331ed1832a",
    ["ui-icons/skills/Shamanskill_14_nobg.png"] = "40635fe0-8742-4593-9a40-dea3058f9333",
    ["ui-icons/skills/Shamanskill_15.png"] = "e93d5ea5-edb1-4439-b50a-a3631f76622e",
    ["ui-icons/skills/Shamanskill_15_nobg.png"] = "53cbc10a-4f44-4f50-be95-d789abcc4ba7",
    ["ui-icons/skills/Shamanskill_16.png"] = "fa06db47-b712-4825-b54f-8b2cdd6a993b",
    ["ui-icons/skills/Shamanskill_16_nobg.png"] = "562f3d01-7f21-48a2-9dab-843d8e0f77ec",
    ["ui-icons/skills/Shamanskill_17.png"] = "8157aba9-a9f7-418c-9798-417d282ae9b6",
    ["ui-icons/skills/Shamanskill_17_nobg.png"] = "80885701-d480-4b48-86a5-52fcdef74946",
    ["ui-icons/skills/Shamanskill_18.png"] = "f1876ee2-54f6-4b19-b907-e12ccd48805a",
    ["ui-icons/skills/Shamanskill_18_nobg.png"] = "5e743f54-a8cd-4290-91ab-41cb7990dd79",
    ["ui-icons/skills/Shamanskill_19.png"] = "a8a28776-9321-4bbe-b8b7-a0d2106584a0",
    ["ui-icons/skills/Shamanskill_19_nobg.png"] = "8e9d1900-11b0-4818-b2a8-b5ba9e134838",
    ["ui-icons/skills/Shamanskill_20.png"] = "d46e732a-5a48-4897-bbcc-3a49e1515d9d",
    ["ui-icons/skills/Shamanskill_20_nobg.png"] = "2fc8b949-6ef2-4f52-81c1-cb51432f7bf8",
    ["ui-icons/skills/Shamanskill_21.png"] = "933ce8f4-41d8-4a7a-941d-b98f2c5e71e4",
    ["ui-icons/skills/Shamanskill_21_nobg.png"] = "1a83be84-15cf-4486-a46e-a999cdb64169",
    ["ui-icons/skills/Shamanskill_22.png"] = "1c083976-0de4-491c-ae99-66f72f2ca311",
    ["ui-icons/skills/Shamanskill_22_nobg.png"] = "95ee2635-5356-4ac0-87e7-8d1133cda8c7",
    ["ui-icons/skills/Shamanskill_23.png"] = "641a5798-eb24-47e5-a35c-480b7510b3b4",
    ["ui-icons/skills/Shamanskill_23_nobg.png"] = "dde2ae69-449a-41a0-b234-e4a9a7fc13e3",
    ["ui-icons/skills/Shamanskill_24.png"] = "09658f44-a7da-4785-bc44-c75cb4a44475",
    ["ui-icons/skills/Shamanskill_24_nobg.png"] = "6f4c0f14-e305-4c7d-b54b-22dc08c78b01",
    ["ui-icons/skills/Shamanskill_25.png"] = "bf926985-026f-4c27-9ecf-9e5d2eb73154",
    ["ui-icons/skills/Shamanskill_25_nobg.png"] = "09eb73ce-5fc6-4184-b26f-741619805a5d",
    ["ui-icons/skills/Shamanskill_26.png"] = "93841f4e-91ce-45bb-84b9-7fe64091c925",
    ["ui-icons/skills/Shamanskill_26_nobg.png"] = "ddd671f0-6912-421a-ae4e-de5cf714f927",
    ["ui-icons/skills/Shamanskill_27.png"] = "2292a64b-990e-4f01-9015-0c95e6fe3294",
    ["ui-icons/skills/Shamanskill_27_nobg.png"] = "d8e67dd9-0ec7-4ba7-b545-34cb1afa5871",
    ["ui-icons/skills/Shamanskill_28.png"] = "af94fe97-9930-4300-b374-8a8928346315",
    ["ui-icons/skills/Shamanskill_28_nobg.png"] = "967933f7-37b1-4298-a2d3-071d88411adf",
    ["ui-icons/skills/Shamanskill_29.png"] = "527a1c12-73fb-4178-9ae3-84e95edec13a",
    ["ui-icons/skills/Shamanskill_29_nobg.png"] = "48193614-0202-4a0c-9c3d-e4f2b62f1eea",
    ["ui-icons/skills/Shamanskill_30.png"] = "7da9c599-4973-4b19-97fe-a4a4bdfb90fd",
    ["ui-icons/skills/Shamanskill_30_nobg.png"] = "15caf087-bf44-4d7a-9d25-4f7a4f0d4afc",
    ["ui-icons/skills/Shamanskill_31.png"] = "056010a4-b0de-49b8-94db-0aa34dfb34a4",
    ["ui-icons/skills/Shamanskill_31_nobg.png"] = "0e105b6d-d321-4c32-bc0c-b1d7c8dffe94",
    ["ui-icons/skills/Shamanskill_32.png"] = "a3242dc1-d806-4040-8c5a-41a9edf200f9",
    ["ui-icons/skills/Shamanskill_32_nobg.png"] = "1349dc4e-948a-498d-8ec6-0362af049b22",
    ["ui-icons/skills/Shamanskill_33.png"] = "62561ec3-2e62-475c-9501-dc4443f9c4c6",
    ["ui-icons/skills/Shamanskill_33_nobg.png"] = "016644b9-6703-4c4a-860c-d9fc8da54f0f",
    ["ui-icons/skills/Shamanskill_34.png"] = "761f01e8-3615-466a-a138-f8ea5bce1ad5",
    ["ui-icons/skills/Shamanskill_34_nobg.png"] = "eb7d6449-90da-4e06-b2c0-2be5686183f1",
    ["ui-icons/skills/Shamanskill_35.png"] = "c10b0e9c-3513-429f-9700-4902531f35d3",
    ["ui-icons/skills/Shamanskill_35_nobg.png"] = "21a2c3c3-d733-475e-a11f-bcb12e1df7ce",
    ["ui-icons/skills/Shamanskill_36.png"] = "4b9af10b-0098-45aa-80ce-e1213b7e5a85",
    ["ui-icons/skills/Shamanskill_36_nobg.png"] = "f324ebe1-92fb-49e2-aeb1-0358ac434236",
    ["ui-icons/skills/Shamanskill_37.png"] = "83d2a900-c857-4536-af5b-c9f8a757c70a",
    ["ui-icons/skills/Shamanskill_37_nobg.png"] = "a4343a88-3d7b-4748-a72e-4fdc3e280582",
    ["ui-icons/skills/Shamanskill_38.png"] = "f7fc1eb8-1084-4094-81dd-eda005f1ec28",
    ["ui-icons/skills/Shamanskill_38_nobg.png"] = "de21b9b3-b2f5-4b51-9acd-f337b6d2614b",
    ["ui-icons/skills/Shamanskill_39.png"] = "652a9094-69fc-4749-856e-bb97192efd8b",
    ["ui-icons/skills/Shamanskill_39_nobg.png"] = "981d88ab-139e-46bf-a43b-97debabcbba0",
    ["ui-icons/skills/Shamanskill_40.png"] = "4edf9efc-513b-4df0-83be-4aa353315098",
    ["ui-icons/skills/Shamanskill_40_nobg.png"] = "d40bdfaf-e47f-41c4-8009-2d0ef2da7131",
    ["ui-icons/skills/Shamanskill_41.png"] = "4315db00-8df1-49dc-8b0c-8ee76be559b6",
    ["ui-icons/skills/Shamanskill_41_nobg.png"] = "6f538843-7dab-46ad-904e-e099607244dd",
    ["ui-icons/skills/Shamanskill_42.png"] = "1919628d-acce-4b8f-9934-eb5220f0ddbe",
    ["ui-icons/skills/Shamanskill_42_nobg.png"] = "10e02029-d7ca-49d2-a060-872a135bcaed",
    ["ui-icons/skills/Shamanskill_43.png"] = "001fc73b-dba2-482d-a634-1cdef9e850b5",
    ["ui-icons/skills/Shamanskill_43_nobg.png"] = "0ebdd405-bb75-44eb-8de8-b11b082bcf95",
    ["ui-icons/skills/Shamanskill_44.png"] = "098e5df8-8006-4d23-9cfb-62d529e3e656",
    ["ui-icons/skills/Shamanskill_44_nobg.png"] = "939ccd30-a815-4b77-9b56-6508674549c4",
    ["ui-icons/skills/Shamanskill_45.png"] = "be808b00-7a33-4fdd-97c6-86231b9d4e63",
    ["ui-icons/skills/Shamanskill_45_nobg.png"] = "89b34c2f-917a-47c0-a007-e4f2a0be1da9",
    ["ui-icons/skills/Shamanskill_46.png"] = "11000154-891d-4752-b53f-81ac9b374945",
    ["ui-icons/skills/Shamanskill_46_nobg.png"] = "f24d1340-5cd3-4e34-ad4a-5d7ee5e39431",
    ["ui-icons/skills/Shamanskill_47.png"] = "8ce09bc3-dcc8-4e53-a3fe-430b2dcbae85",
    ["ui-icons/skills/Shamanskill_47_nobg.png"] = "da2110c8-0a48-485b-9357-cb4eb874a00c",
    ["ui-icons/skills/Shamanskill_48.png"] = "531f9c95-61e5-4fb9-afbd-668a21a569f6",
    ["ui-icons/skills/Shamanskill_48_nobg.png"] = "cc8d65ac-6535-496a-b8a8-75037203e10d",
    ["ui-icons/skills/Shamanskill_49.png"] = "dac03929-466a-45fc-bc8f-f9597030f467",
    ["ui-icons/skills/Shamanskill_49_nobg.png"] = "a2e6080c-2824-4980-b980-18c13b0d3b77",
    ["ui-icons/skills/Shamanskill_50.png"] = "4e106962-5646-4d3d-9748-30d3dfb5ed0c",
    ["ui-icons/skills/Shamanskill_50_nobg.png"] = "b9c40fb3-105d-47d7-b3fa-eff16d5df831",
    ["ui-icons/skills/Shock.png"] = "8ef82792-0287-4119-8265-ea0c263a7339",
    ["ui-icons/skills/Skill_201.png"] = "1cce2d43-f587-44ed-a5cd-604eb02383a5",
    ["ui-icons/skills/Skill_202.png"] = "be2daabe-e803-4e5c-9f59-209ccf96f8d5",
    ["ui-icons/skills/Skill_203.png"] = "527d06cf-a0c6-4e1a-8791-655ddc3ec7cf",
    ["ui-icons/skills/Skill_204.png"] = "43eb43b8-52cf-41e0-9785-2b9314adf69e",
    ["ui-icons/skills/Skill_205.png"] = "0d0df375-213e-44fa-bae1-442e9b8181e9",
    ["ui-icons/skills/Skill_206.png"] = "3cc03f1c-1e3c-43ae-b895-101272daa3eb",
    ["ui-icons/skills/Skill_207.png"] = "b4dabd4d-e285-4654-b5de-d13866a2da9e",
    ["ui-icons/skills/Skill_208.png"] = "1e4e2f12-15a4-4ed0-88a9-c8c184c5f4d4",
    ["ui-icons/skills/Skill_209.png"] = "a30bb5a3-bea5-4507-8e4c-fa39da99137a",
    ["ui-icons/skills/Skill_212.png"] = "5c63590a-5f22-4c0f-8c58-f04a67af6d73",
    ["ui-icons/skills/Skill_213.png"] = "4e7010e5-799c-4b3c-b552-da22fcfa9868",
    ["ui-icons/skills/Skill_214.png"] = "5e04eece-f86e-4911-9804-92a5883fd7b4",
    ["ui-icons/skills/Skill_215.png"] = "2208fcb8-266d-47a1-a96e-578106f5450e",
    ["ui-icons/skills/Skill_216.png"] = "1292d6a8-fb6d-4ad1-90f2-902962f7b9f4",
    ["ui-icons/skills/Skill_217.png"] = "8cc55149-19ea-4b37-9b98-5e307985cb2a",
    ["ui-icons/skills/Skill_218.png"] = "57fe4611-012e-45ec-a7eb-09464596d451",
    ["ui-icons/skills/Skill_219.png"] = "519a734e-d85a-499f-80d2-83b9931ac59e",
    ["ui-icons/skills/Skill_220.png"] = "4212ccd5-4ea0-4c78-a618-1261deffc2b8",
    ["ui-icons/skills/Skill_221.png"] = "aaa9aa77-5b25-4292-b851-dedcb4f03cb9",
    ["ui-icons/skills/Skill_222.png"] = "01e8e7f1-f373-4d72-90bf-d0b4784f0c7b",
    ["ui-icons/skills/Skill_223.png"] = "8513b4df-c7ed-4ecf-8235-3825ed99ff5d",
    ["ui-icons/skills/Skill_224.png"] = "ec477599-30df-4062-a3c7-444684ac3911",
    ["ui-icons/skills/Skill_225.png"] = "66c243e8-10bd-471e-85d0-5848a1a1b237",
    ["ui-icons/skills/Skill_225_noBG.png"] = "1a5fa551-8cc4-428a-84da-3cd8243f5887",
    ["ui-icons/skills/Skill_227.png"] = "e9ef28c1-d076-40b1-9907-e83eb9856c1f",
    ["ui-icons/skills/Skill_228.png"] = "27ca7cb9-8fc5-4ac5-b95c-ff681d5dacf7",
    ["ui-icons/skills/Skill_229.png"] = "892ae202-b237-4ae3-872a-ed83a13d96b0",
    ["ui-icons/skills/Skill_231.png"] = "01337c58-e3b0-4dc8-8c0d-c39be759c8db",
    ["ui-icons/skills/Skill_231_noBG.png"] = "fd613c21-9ad4-4537-bdb8-937897452862",
    ["ui-icons/skills/Skill_232.png"] = "21ae5247-59fe-4ca3-9389-0983f7f43c70",
    ["ui-icons/skills/Skill_233.png"] = "84fe73eb-aebc-49bb-9f6a-f2e4b9527c17",
    ["ui-icons/skills/Skill_234.png"] = "927225ad-96e2-4d4e-b736-f2a6549934f9",
    ["ui-icons/skills/Skill_235.png"] = "8223780f-6ff4-4825-8ead-44e36fd191f1",
    ["ui-icons/skills/Skill_236.png"] = "b3d3a964-653d-4013-897a-d2c5cbaf4190",
    ["ui-icons/skills/Skill_237.png"] = "e1cc59aa-8943-4185-88d6-de598beb0d5e",
    ["ui-icons/skills/Skill_238.png"] = "3d00da4f-92de-4ab4-a065-097683533b55",
    ["ui-icons/skills/Skill_239.png"] = "aa13c5a5-d912-4aeb-ba5a-5491785db905",
    ["ui-icons/skills/Skill_240.png"] = "5d1c3927-4e7d-49d7-bdbb-227df73be99a",
    ["ui-icons/skills/Skill_241.png"] = "18bd25cf-68a8-43d3-aac6-adff23301595",
    ["ui-icons/skills/Skill_242.png"] = "94bf6e92-d1c1-4d85-9d44-e05eca4d9ea1",
    ["ui-icons/skills/Skill_243.png"] = "34f747aa-b625-431a-be1f-a32d1543593f",
    ["ui-icons/skills/Skill_246.png"] = "a54b4e8c-de1b-4cd4-9fdb-73b5fc601026",
    ["ui-icons/skills/Skill_246_noBG.png"] = "ecd0486a-5d0f-487b-b4ee-5f3f8c8ae6a2",
    ["ui-icons/skills/Skill_247.png"] = "8d207d28-79fb-49cf-a038-41cac43d176f",
    ["ui-icons/skills/Skill_248.png"] = "9bb2d07e-c35f-44a9-8483-fb898804b3ba",
    ["ui-icons/skills/Skill_249.png"] = "9a7e600d-16d8-4960-9c29-d0f34772edb6",
    ["ui-icons/skills/Skill_250.png"] = "318f1699-354c-4e1d-95d1-61da2f3bf7ce",
    ["ui-icons/skills/Skill_251.png"] = "162a71ed-c1b0-421e-8f23-d432ba6cd1b6",
    ["ui-icons/skills/Skill_252.png"] = "2e07b3b2-3697-4724-b526-d28ad3e19080",
    ["ui-icons/skills/Skill_253.png"] = "4473c774-2ebe-49a9-8168-77d10f70be59",
    ["ui-icons/skills/Skill_255.png"] = "fce10d85-2237-4b67-a6f4-889336a00422",
    ["ui-icons/skills/Skill_255_noBG.png"] = "ac1f00d8-d46e-453e-b928-c0a09a01041b",
    ["ui-icons/skills/Skill_256.png"] = "d95554f2-cb1b-4765-98f9-642cb8a8b7a2",
    ["ui-icons/skills/Skill_257.png"] = "57b3359e-13b6-40b8-8252-48cd016d1ed5",
    ["ui-icons/skills/Skill_258.png"] = "19810c22-760f-4e7a-afa9-bef68839019c",
    ["ui-icons/skills/Skill_259.png"] = "846d9ab0-d03e-4418-99c8-6f1fca6752f4",
    ["ui-icons/skills/Skill_260.png"] = "3b79c52f-b217-48a5-be36-bcda4086c12f",
    ["ui-icons/skills/Skill_261.png"] = "72ea177a-7864-41c8-915d-5d8c34c5b9e1",
    ["ui-icons/skills/Skill_262.png"] = "1621d0bf-a0b4-4c7d-8dfb-4593e2d97399",
    ["ui-icons/skills/Skill_263.png"] = "7daf7f83-a7b6-4949-af38-1a9f392d26c4",
    ["ui-icons/skills/Skill_264.png"] = "d994ae37-9327-4984-880e-0addb07e580b",
    ["ui-icons/skills/Skill_265.png"] = "cacdd46e-c16f-44a5-8a8d-02bf4445a445",
    ["ui-icons/skills/Skill_266.png"] = "5544408a-004b-42f8-a706-864b7c96ce78",
    ["ui-icons/skills/Skill_267.png"] = "392e8090-34b7-4003-b8cf-888135e8c17f",
    ["ui-icons/skills/Skill_268.png"] = "e535f9a1-91dc-4b8f-a4ea-4d6303feb042",
    ["ui-icons/skills/Skill_269.png"] = "ddd8dd66-da33-4964-8a05-7a417d87a1e3",
    ["ui-icons/skills/Skill_270.png"] = "bf943f3b-3b82-4b64-bb27-a186d967d08f",
    ["ui-icons/skills/Skill_271.png"] = "8ed969f2-1349-41ff-89cc-a34268fdc236",
    ["ui-icons/skills/Skill_272.png"] = "75b2c17b-6901-4d57-8b21-fca28a37fb7c",
    ["ui-icons/skills/Skill_273.png"] = "5e8af082-ed48-4c5e-a008-b78a8a8e423a",
    ["ui-icons/skills/Skill_274.png"] = "c7c45961-b05e-4a12-a7fe-a965ace4805d",
    ["ui-icons/skills/Skill_275.png"] = "c90e0180-2841-406a-a0d3-ca38a0daed1c",
    ["ui-icons/skills/Skill_276.png"] = "e8675627-f052-4cc0-a9f4-65db504fa096",
    ["ui-icons/skills/Skill_277.png"] = "3c6ae738-f50e-4c61-bedb-6cef1da397d4",
    ["ui-icons/skills/Skill_278.png"] = "fdbd6356-8d0a-4f8d-8151-5bbbeb33c037",
    ["ui-icons/skills/Skill_278_noBG.png"] = "d396dbeb-4987-4af2-b137-42816d5e028e",
    ["ui-icons/skills/Skill_279.png"] = "9f1c4ebf-20cc-46d1-b85e-9d4f298ec771",
    ["ui-icons/skills/Skill_280.png"] = "91ce53f8-902c-4b86-96ec-a5b06f636fcc",
    ["ui-icons/skills/Skill_281.png"] = "a0bea004-2f43-4ab4-9cc6-6d7f6f9d1bc6",
    ["ui-icons/skills/Skill_282.png"] = "ba6f17b6-dc82-4257-bf5e-ebd943cd33b9",
    ["ui-icons/skills/Skill_283.png"] = "7027c3d8-9bed-462d-b4cb-bc74af291cc8",
    ["ui-icons/skills/Skill_284.png"] = "b2331baf-3464-40ef-8464-2c272ffa1ee1",
    ["ui-icons/skills/Skill_285.png"] = "0a029175-8093-47cb-97cc-caffc47a9002",
    ["ui-icons/skills/Skill_286.png"] = "51c07bd5-0ea3-4c37-b744-b197e0884724",
    ["ui-icons/skills/Skill_287.png"] = "170f2e95-6cea-4461-bd5c-480f74835698",
    ["ui-icons/skills/Skill_288.png"] = "ffb28f8c-5dc8-4c03-9099-41379a286ed2",
    ["ui-icons/skills/Skill_289.png"] = "3a00061a-ab53-4988-bc0c-49a72317e38e",
    ["ui-icons/skills/Skill_290.png"] = "d11c4f74-d0ff-4494-a7d1-6e7fb1f80b18",
    ["ui-icons/skills/Skill_291.png"] = "8c53491b-22a0-4c4e-b14d-c880a7ae3d39",
    ["ui-icons/skills/Skill_292.png"] = "9ae56705-072c-4f69-8768-83f607206fd1",
    ["ui-icons/skills/Skill_293.png"] = "c15c61f2-25d8-4a9f-abaf-612e03c7aa5e",
    ["ui-icons/skills/Skill_294.png"] = "be9ec63a-3b34-48dc-9716-71fc013a98b8",
    ["ui-icons/skills/Skill_295.png"] = "9fc4d8df-6cf2-4d7f-a360-8902c93b952d",
    ["ui-icons/skills/Skill_296.png"] = "77966e85-ee8f-44ef-9c92-8ab0c2c183f7",
    ["ui-icons/skills/Skill_297.png"] = "0511e0fc-bd17-4547-a748-0f725259a8db",
    ["ui-icons/skills/Skill_298.png"] = "5e35fe34-4f36-454c-a4d0-b3dd5aee8e82",
    ["ui-icons/skills/Skill_299.png"] = "78778adc-11d6-4056-aea7-e420426ee8c4",
    ["ui-icons/skills/Skill_300.png"] = "8ae717ef-8a82-4e9f-8359-f4a593f6913e",
    ["ui-icons/skills/Skill_301.png"] = "de9609bb-0e4c-485d-9d4a-f25e690812bf",
    ["ui-icons/skills/Skill_302.png"] = "1294ca81-33a8-40d1-b9bb-77aea0935cf9",
    ["ui-icons/skills/Skill_302_noBG.png"] = "9e9949a3-c406-4d9f-8840-0e74bac3ee1e",
    ["ui-icons/skills/Skill_303.png"] = "e5613641-2742-4924-aa95-e32053e98bcc",
    ["ui-icons/skills/Skill_304.png"] = "7979c0a5-f663-44f3-bf1c-216174b98c8a",
    ["ui-icons/skills/Skill_305.png"] = "87e94e4c-bbc6-4a62-b524-ee16f45cf7a8",
    ["ui-icons/skills/Skill_306.png"] = "c94d1b1d-3cd0-41d8-9f64-9f429589b64a",
    ["ui-icons/skills/Skill_307.png"] = "5633ab46-ad1c-4fb8-b530-1639e72c9e5f",
    ["ui-icons/skills/Skill_308.png"] = "166ba41c-2a8f-498a-8f25-264957c88e52",
    ["ui-icons/skills/Skill_309.png"] = "41078616-468f-488d-ac53-6bffd99b219d",
    ["ui-icons/skills/Skill_310.png"] = "3c4432e1-5c0e-45de-83cd-f536315e5fb0",
    ["ui-icons/skills/Skill_311.png"] = "faf80d7f-78eb-4990-9685-a9eb7767f474",
    ["ui-icons/skills/Skill_312.png"] = "d5314445-cd8b-495b-82ca-b90ee29d7677",
    ["ui-icons/skills/Skill_313.png"] = "5ee9ae68-6f2f-4b51-b4fd-7058ff47eefe",
    ["ui-icons/skills/Skill_314.png"] = "ee2ffcd5-1067-496d-b275-52942795bc25",
    ["ui-icons/skills/Skill_315.png"] = "eb7b599b-708c-4c1a-a149-5a4c69910197",
    ["ui-icons/skills/Skill_316.png"] = "8dfffe2c-229e-4484-a80d-338d075e4e81",
    ["ui-icons/skills/Skill_317.png"] = "5b80b6fd-7533-4a76-b699-3dc2e910bfaa",
    ["ui-icons/skills/Skill_318.png"] = "62b7fd9e-3111-4fea-8dd2-6011e9774fe1",
    ["ui-icons/skills/Skill_319.png"] = "f82593c3-746d-4e03-ae6f-bd4d5e26b2ef",
    ["ui-icons/skills/Skill_320.png"] = "e941369b-0a85-4b40-9b8d-6c765a56916a",
    ["ui-icons/skills/Skill_321.png"] = "83f5e3ae-25ed-4fb1-b656-b79fafd3d290",
    ["ui-icons/skills/Skill_321_noBG.png"] = "4db058a6-ca1f-4c0e-95e2-9fc66f340045",
    ["ui-icons/skills/Skill_322.png"] = "5ef8e58f-9204-4b4a-afe3-5b4128f3f607",
    ["ui-icons/skills/Skill_323.png"] = "ac5f4af9-b7b9-456a-bd24-ae4375c8ce6e",
    ["ui-icons/skills/Skill_323_noBG.png"] = "ceed7684-5227-4d4e-9c69-f419f241b1fe",
    ["ui-icons/skills/Skill_324.png"] = "36c205a1-853b-4f11-b61f-c9a050cb727b",
    ["ui-icons/skills/Skill_324_noBG.png"] = "1c6f370d-41f2-4e70-9846-0ece525acc00",
    ["ui-icons/skills/Skill_325.png"] = "9501602d-c1b5-4f33-b860-3e3a6b63aee3",
    ["ui-icons/skills/Skill_327.png"] = "4da79007-415a-4120-af17-9d290f553219",
    ["ui-icons/skills/Skill_328.png"] = "f69c6391-8af9-496b-9cd4-24543d8db359",
    ["ui-icons/skills/Skill_329.png"] = "e9e74544-b187-48b5-b5c7-983d241bb869",
    ["ui-icons/skills/Skill_330.png"] = "7fe47afd-b393-4cf1-b0d2-5090455554ce",
    ["ui-icons/skills/Skill_331.png"] = "a961b6e3-acaa-4134-819e-a4c2b82f4cc5",
    ["ui-icons/skills/Skill_332.png"] = "636a8d3e-117b-443c-bd8a-1d4fe60cb1a6",
    ["ui-icons/skills/Skill_333.png"] = "f9e270ed-4f2c-4dfb-bb57-0d7d0d2d2724",
    ["ui-icons/skills/Skill_334.png"] = "b67316a6-61ac-4a1e-a493-4d64ae838db7",
    ["ui-icons/skills/Skill_335.png"] = "da0b52e8-c2b5-4e82-ae6e-1469707f8884",
    ["ui-icons/skills/Skill_336.png"] = "ce48be91-d880-4c5d-9064-ccfc8e266032",
    ["ui-icons/skills/Skill_337.png"] = "11989454-d811-40e0-9ce5-2e6fc87761c6",
    ["ui-icons/skills/Skill_338.png"] = "edcc917b-523c-4c38-8af9-7ac1e005cc53",
    ["ui-icons/skills/Skill_339.png"] = "032a58af-490f-454c-bdcb-02b02b285846",
    ["ui-icons/skills/Skill_340.png"] = "1067bcb5-f47d-40ba-9910-125f27ad2355",
    ["ui-icons/skills/Skill_341.png"] = "58c61507-3931-4813-9c1a-d19e05706b90",
    ["ui-icons/skills/Skill_342.png"] = "a71579e8-4960-47e6-b441-4d01aa06b4ab",
    ["ui-icons/skills/Skill_343.png"] = "cb3f4af5-5cff-4712-ba9c-f4f5d11f9c66",
    ["ui-icons/skills/Skill_344.png"] = "92e2264d-9b2f-470f-b3e0-8c7e0687d808",
    ["ui-icons/skills/Skill_345.png"] = "e2b0bc71-e541-40ed-8242-50030dbff15a",
    ["ui-icons/skills/Skill_346.png"] = "b1fef7fc-e276-479d-888e-613c24508a11",
    ["ui-icons/skills/Skill_347.png"] = "d20cd617-3515-481d-baec-0b71b43144b8",
    ["ui-icons/skills/Skill_348.png"] = "d2862eff-4edb-4b70-b6af-6eec7f532081",
    ["ui-icons/skills/Skill_349.png"] = "de98ac50-64ee-4b08-8ad2-919b63612b13",
    ["ui-icons/skills/Skill_350.png"] = "99bf9da3-94f3-4664-87e4-f04d1744216c",
    ["ui-icons/skills/Skill_351.png"] = "e19fcc77-c39c-410b-a389-c6c07068c258",
    ["ui-icons/skills/Skill_352.png"] = "aaf9b7a7-fea8-4c38-b634-129ca865c372",
    ["ui-icons/skills/Skill_353.png"] = "867bc4e6-6698-4ac7-90c8-b8eec78d07f1",
    ["ui-icons/skills/Skill_354.png"] = "7d5d6a5b-d668-48f8-ba2b-4d3bc9a5054c",
    ["ui-icons/skills/Skill_355.png"] = "08c9aab7-88c5-4220-81aa-93cd99557271",
    ["ui-icons/skills/Skill_356.png"] = "48e135ad-3cb1-4b27-b428-e40a9d98308a",
    ["ui-icons/skills/Skill_357.png"] = "571e0e73-52ba-49c8-ac70-5d71f47384b4",
    ["ui-icons/skills/Skill_358.png"] = "17da28fd-9c6f-47aa-b793-92f513a50d7d",
    ["ui-icons/skills/Skill_359.png"] = "7eea879d-4d84-45ff-ab19-ba1eddb020d3",
    ["ui-icons/skills/Skill_360.png"] = "f4e480f8-a76d-4bdd-b61c-e9f6e5311e7c",
    ["ui-icons/skills/Skill_361.png"] = "4d6cd69a-dd1f-463b-b3ce-ce4495afa4dc",
    ["ui-icons/skills/Skill_362.png"] = "e3709fdc-cb9d-4205-8986-2b08a0995a35",
    ["ui-icons/skills/Skill_363.png"] = "54d9f515-fd94-4f98-8064-e697a97e27e9",
    ["ui-icons/skills/Skill_364.png"] = "3fd9a061-5428-4426-9037-20e8e94673dc",
    ["ui-icons/skills/Skill_365.png"] = "ce34283a-6c8c-4550-970a-97784bb48c46",
    ["ui-icons/skills/Skill_366.png"] = "bf321876-3fc5-4f81-a497-1446cbdda70e",
    ["ui-icons/skills/Skill_368.png"] = "5aed622e-8524-4b3a-ac31-03fe89b09d92",
    ["ui-icons/skills/Skill_369.png"] = "41f6b51a-ff35-4c2e-b633-a9e4ed9bfe0d",
    ["ui-icons/skills/Skill_370.png"] = "08704235-88dc-4e2f-97bb-58374437c652",
    ["ui-icons/skills/Skill_371.png"] = "af2721f8-68e5-4d57-baaa-15a6db64fa39",
    ["ui-icons/skills/Skill_372.png"] = "90b6d046-a7f7-467b-993f-6013b528588e",
    ["ui-icons/skills/Skill_373.png"] = "66e5f994-0af2-4a29-a708-3c6d8643b5cd",
    ["ui-icons/skills/Skill_374.png"] = "7ff69509-6ed5-4b2a-863c-05b1e6cb48b1",
    ["ui-icons/skills/Skill_375.png"] = "e3df6fc7-635c-4af9-99db-e0b89bfbfe5e",
    ["ui-icons/skills/Skill_376.png"] = "bcbdc572-610b-4830-9e84-c48cdb987dc4",
    ["ui-icons/skills/Skill_377.png"] = "6e3c97dc-237b-4b88-8676-74578181c0e0",
    ["ui-icons/skills/Skill_380.png"] = "6f87309e-1d3b-4af6-b5d5-fa187c112899",
    ["ui-icons/skills/Skill_381.png"] = "6e4b74ab-b382-49ac-b2c2-bbc8dc629f04",
    ["ui-icons/skills/Skill_382.png"] = "fc39e35b-0800-4871-a4ad-ab93182e92c9",
    ["ui-icons/skills/Skill_383.png"] = "57ab270e-7714-4380-84a8-756454c390eb",
    ["ui-icons/skills/Skill_384.png"] = "f15577c6-4d53-4b5a-b35d-e57b84038f23",
    ["ui-icons/skills/Skill_385.png"] = "52529f70-5710-42a2-b167-43710306380b",
    ["ui-icons/skills/Skill_386.png"] = "9914b57a-bebb-4dda-9018-591e1224a496",
    ["ui-icons/skills/Skill_387.png"] = "15c8f70d-202e-4b61-a494-7eae9fe7561b",
    ["ui-icons/skills/Skill_388.png"] = "31c0c115-5929-41ef-b214-9842acb9dc72",
    ["ui-icons/skills/Skill_389.png"] = "fddde6e5-e0d4-408a-ac6c-99e6e4ff73c6",
    ["ui-icons/skills/Skill_390.png"] = "41e7904b-efc6-4e31-8188-db39e9b2349c",
    ["ui-icons/skills/Skill_391.png"] = "c294fda3-11b8-4316-83fa-bd9c83b761c8",
    ["ui-icons/skills/Skill_392.png"] = "3b374f99-72c1-4e5c-bde2-5a6f14d6664a",
    ["ui-icons/skills/Skill_393.png"] = "6653473e-5fe7-4a69-92ca-febdd9ee5b73",
    ["ui-icons/skills/Skill_394.png"] = "6dc5fa35-5cd4-4f21-8a10-cd4316a8d415",
    ["ui-icons/skills/Skill_395.png"] = "94e818f9-5769-4ce4-9ffa-8209f13aeb30",
    ["ui-icons/skills/Skill_396.png"] = "ddb4eb42-19cf-47e1-9fd5-1cf2eb0e7b8a",
    ["ui-icons/skills/Skill_397.png"] = "0894bbcc-2b02-45ef-9917-bc0c051a8df9",
    ["ui-icons/skills/Skill_398.png"] = "b0b43268-00eb-4eb8-b337-66056014a522",
    ["ui-icons/skills/Skill_399.png"] = "6ab772fe-1576-4822-a68a-0fbb91b627e8",
    ["ui-icons/skills/Skill_400.png"] = "1141ce86-7017-4ea5-9f53-66a6c92e73ba",
    ["ui-icons/skills/Skill_401.png"] = "efdea2f7-05a5-434b-9903-835a1d2f5ea4",
    ["ui-icons/skills/Skill_402.png"] = "94b475a8-3656-4acf-a6ce-63530ae11653",
    ["ui-icons/skills/Skill_404.png"] = "d10b2746-1f26-47ee-a25f-edd66e368c9a",
    ["ui-icons/skills/Skill_405.png"] = "645bad35-8c14-4472-9da6-3ed88bbc3948",
    ["ui-icons/skills/Skill_406.png"] = "97e5acb9-e64f-435a-96ab-be7661f2c7db",
    ["ui-icons/skills/Skill_407.png"] = "2e4fb446-5e04-42b8-8014-9c86973036a4",
    ["ui-icons/skills/Skill_408.png"] = "6cdf4e1b-c41a-42ca-8978-8abae804ccfb",
    ["ui-icons/skills/Skill_409.png"] = "efaf5105-5700-4a59-85ef-91d26cd021c2",
    ["ui-icons/skills/Skill_410.png"] = "8da0f381-e75a-4eed-a034-e13c6be575cf",
    ["ui-icons/skills/Skill_411.png"] = "c5777a63-b905-4c34-978c-3009e725d671",
    ["ui-icons/skills/Skill_412.png"] = "90505beb-de4b-4eca-bfbc-e4cc49077a0e",
    ["ui-icons/skills/Skill_413.png"] = "b9932f1b-c6cd-4787-a67c-08e817693734",
    ["ui-icons/skills/Skill_414.png"] = "af5f38a2-6c0a-42af-9fd5-975c4a4bfa68",
    ["ui-icons/skills/Skill_414_noBG.png"] = "4693f2de-2751-424c-8880-f93a65e774cd",
    ["ui-icons/skills/Skill_415.png"] = "25f54089-80e5-4346-bd7f-d711da2238f8",
    ["ui-icons/skills/Skill_416.png"] = "29b28af5-7ccb-4701-914d-5827bc655078",
    ["ui-icons/skills/Skill_417.png"] = "fab06117-3134-4065-bfb6-2856773f8acd",
    ["ui-icons/skills/Skill_418.png"] = "cbba8e2a-c40b-4322-a953-ef2b395b9f12",
    ["ui-icons/skills/Skill_419.png"] = "0c0112f0-4322-486e-b585-71b5828d5766",
    ["ui-icons/skills/Skill_420.png"] = "42307bd3-65ed-4ae1-8ceb-86e929b8d7cb",
    ["ui-icons/skills/Skill_421.png"] = "865e8264-93db-4f1b-97d0-b7b9e9edbc0f",
    ["ui-icons/skills/Skill_422.png"] = "ad13e0fe-1149-472f-8a12-c3959de40e83",
    ["ui-icons/skills/Skill_423.png"] = "b825f213-99c3-4ef6-b1c6-48ace9eb8168",
    ["ui-icons/skills/Skill_424.png"] = "45bf9261-77ef-4023-a3b7-a72df38ee86f",
    ["ui-icons/skills/Skill_425.png"] = "772440f6-232d-4261-b598-5faa1654fa0c",
    ["ui-icons/skills/Skill_426.png"] = "20c7f607-5eda-4a3e-94ff-3287682cfdc3",
    ["ui-icons/skills/Skill_428.png"] = "7ed5fe74-d7e3-46f4-aa44-ad776baaab1e",
    ["ui-icons/skills/Skill_429.png"] = "aff22660-3511-486c-ae69-36a76ac3132b",
    ["ui-icons/skills/Skill_430.png"] = "af6ab16b-feaf-4cec-80dc-d7cb3774ac0e",
    ["ui-icons/skills/Skill_431.png"] = "6c1c7703-22fe-4250-ba06-a696e41dc1c6",
    ["ui-icons/skills/Skill_431_noBG.png"] = "db02cd3a-d676-434d-81fd-f097e07d82e3",
    ["ui-icons/skills/Skill_433.png"] = "8dbbb2a3-a7fd-4839-8a3d-3b36aaefa9dc",
    ["ui-icons/skills/Skill_433_noBG.png"] = "0aa8d4ee-f4af-4d39-8490-745da2ffb95f",
    ["ui-icons/skills/Skill_435.png"] = "d6f035d1-07d2-44f3-86d8-fa22a5f7ed90",
    ["ui-icons/skills/Skill_436.png"] = "35484a9c-cfc8-446a-9287-8d7fb04a8d78",
    ["ui-icons/skills/Skill_438.png"] = "4ba14f80-9ceb-462c-b71e-e1d7ea4cd0a9",
    ["ui-icons/skills/Skill_439.png"] = "d2fa33f4-cfaf-4f76-a288-d98dfd6e283b",
    ["ui-icons/skills/Skill_440.png"] = "2932f0c3-8748-45aa-b71d-b87a72716d26",
    ["ui-icons/skills/Skill_441.png"] = "863713e1-f98a-4461-9ed9-e55f9086340f",
    ["ui-icons/skills/Skill_442.png"] = "ffe29c8d-d7db-4d0f-ac63-a0d8f9940568",
    ["ui-icons/skills/Skill_443.png"] = "19f07e74-265a-4712-a969-01eeefc5403e",
    ["ui-icons/skills/Skill_444.png"] = "8e6bf598-d030-4624-a96d-5e76e8988afe",
    ["ui-icons/skills/Skill_445.png"] = "3b0eda11-9d1a-43e7-b695-06413b0021ee",
    ["ui-icons/skills/Skill_446.png"] = "8a2f2ebf-87f6-46ad-bfd3-5e9ea40522c3",
    ["ui-icons/skills/Skill_447.png"] = "eac8ad3d-cd25-49c5-8594-f13fef01d9c4",
    ["ui-icons/skills/Skill_448.png"] = "82919d5b-f5a6-4467-bbfd-92c05db88166",
    ["ui-icons/skills/Skill_449.png"] = "afd42674-7a31-4904-a512-77caca9d305f",
    ["ui-icons/skills/Skill_450.png"] = "8442421a-041b-470d-ba70-05656e30c5d8",
    ["ui-icons/skills/Skill_452.png"] = "90e18f11-387a-4a54-85e7-e9edcd847f4f",
    ["ui-icons/skills/Skill_453.png"] = "e9ac813a-76df-47b4-97cb-92883022551e",
    ["ui-icons/skills/Skill_454.png"] = "acab55c0-4e2e-4f3f-a463-1c9c33b42849",
    ["ui-icons/skills/Skill_455.png"] = "7a0c2584-5392-4983-81e9-d2bf77c5fb8f",
    ["ui-icons/skills/Skill_456.png"] = "51f8541d-380e-4e7d-ace8-a5a39c7e45f5",
    ["ui-icons/skills/Skill_458.png"] = "b9352d98-ca7e-47a3-853c-d78ea8dc2e4f",
    ["ui-icons/skills/Skill_459.png"] = "22717fd9-d5c3-4cbd-bab8-1013868976f6",
    ["ui-icons/skills/Skill_460.png"] = "07eb7bf1-e937-4fe3-858e-0a2d0c007b81",
    ["ui-icons/skills/Skill_461.png"] = "c5e873d4-5995-439c-a539-500f078b9584",
    ["ui-icons/skills/Skill_462.png"] = "8910136f-7a42-41c4-bae7-915f3eca8e6e",
    ["ui-icons/skills/Skill_463.png"] = "5ef324c3-e342-4c8c-921c-b866fbb6a47b",
    ["ui-icons/skills/Skill_464.png"] = "facebdd2-cba6-4c6a-8cec-b654de16b312",
    ["ui-icons/skills/Skill_465.png"] = "11c9882b-7f5e-42b2-9611-e679c1daf0d4",
    ["ui-icons/skills/Skill_466.png"] = "8561597a-0087-4027-9f84-3424bd49ed56",
    ["ui-icons/skills/Skill_467.png"] = "f0b2f08c-6994-4253-b069-1997421c6aad",
    ["ui-icons/skills/Skill_468.png"] = "b8a97be4-4568-49d8-be21-b4713477330c",
    ["ui-icons/skills/Skill_469.png"] = "67d440c1-ea7a-4ce3-9e72-039f6acef89c",
    ["ui-icons/skills/Skill_470.png"] = "408ddaf6-bd61-4812-8fa9-49a34ce7acd8",
    ["ui-icons/skills/Skill_471.png"] = "af598e0b-30ba-496a-9ac9-b6d386a8849b",
    ["ui-icons/skills/Skill_472.png"] = "4b2bd7b3-b27f-4885-941c-3a8e5a531eae",
    ["ui-icons/skills/Skill_473.png"] = "c4051b0d-2bd4-4164-a96e-782504889d86",
    ["ui-icons/skills/Skill_474.png"] = "442148d7-a6e1-4c64-81f7-d5c6d72880e7",
    ["ui-icons/skills/Skill_475.png"] = "afab6fda-a938-47e1-b956-bfd43aef3a3a",
    ["ui-icons/skills/Skill_476.png"] = "0229bddc-125d-4ab1-9cf8-c52b352e74f6",
    ["ui-icons/skills/Skill_477.png"] = "6fa27148-7c95-4e59-8c95-05331db3fd4b",
    ["ui-icons/skills/Skill_478.png"] = "86948128-7275-4802-989a-1420448cafbc",
    ["ui-icons/skills/Skill_479.png"] = "b710da1d-73d6-422f-9b7f-08126a352c17",
    ["ui-icons/skills/Skill_480.png"] = "ec456220-a835-4ce8-9719-d8e172ad2792",
    ["ui-icons/skills/Skill_481.png"] = "8909d658-4f5d-4671-8b01-bb0ac1ae84c0",
    ["ui-icons/skills/Skill_482.png"] = "92451972-8129-4ee0-b536-28a79370ec20",
    ["ui-icons/skills/Skill_483.png"] = "f6fcaedb-d052-489f-83dc-107b19c21b49",
    ["ui-icons/skills/Skill_484.png"] = "0c46efd3-becd-4521-a40c-12a7cdc4b09a",
    ["ui-icons/skills/Skill_485.png"] = "90ec9149-4c62-45ff-82ee-680fce05407c",
    ["ui-icons/skills/Skill_486.png"] = "40144f50-cc48-4cc5-8b6c-651c561e8b54",
    ["ui-icons/skills/Skill_487.png"] = "804e8260-8a7c-413e-b49d-5e5a367f58c6",
    ["ui-icons/skills/Skill_489.png"] = "7e278838-f8b2-44a1-abab-98feed9bc34c",
    ["ui-icons/skills/Skill_490.png"] = "80d4b66a-13f7-4a81-8365-c8501fc709ef",
    ["ui-icons/skills/Skill_491.png"] = "1a6afa05-1948-43a5-9f3a-3fa5ea5a7da0",
    ["ui-icons/skills/Skill_492.png"] = "4154deaf-5bbd-42ab-b3e5-0c8640386918",
    ["ui-icons/skills/Skill_493.png"] = "76d1bcfd-d28c-458c-9d22-ad4a7d474330",
    ["ui-icons/skills/Skill_494.png"] = "5f45068f-8b4e-47e7-aef5-7ecd1aaa6e09",
    ["ui-icons/skills/Skill_495.png"] = "e5fac575-95ea-49a0-8965-a621ac73a4df",
    ["ui-icons/skills/Skill_496.png"] = "efaf62b4-243f-483d-9708-b510de397dda",
    ["ui-icons/skills/Skill_497.png"] = "7e81666b-cc24-4cf7-a459-38c2dcace4e7",
    ["ui-icons/skills/Skill_498.png"] = "5f4d19e7-c57a-473f-8904-de81216b6ca8",
    ["ui-icons/skills/Skill_499.png"] = "4d47bdc8-08d0-4402-91b0-9ec1cadbce04",
    ["ui-icons/skills/Skill_500.png"] = "7cb2ed70-7eb7-40ac-9cc7-4ad538fcf05c",
    ["ui-icons/skills/Update_01.png"] = "d9ef9d70-d749-423f-978c-19faf11147ca",
    ["ui-icons/skills/Update_01_nobg.png"] = "26a8786e-4eea-4dd6-a0d8-5bc61e422539",
    ["ui-icons/skills/Update_02.png"] = "e96c72cd-4529-42ed-9bc1-992e4ff47f9d",
    ["ui-icons/skills/Update_02_nobg.png"] = "c3b56add-5864-4eff-b7dd-c3a89592a36b",
    ["ui-icons/skills/Update_03.png"] = "a8c1639a-fdb1-4ea6-991b-27b6ebde0025",
    ["ui-icons/skills/Update_03_nobg.png"] = "b147bd50-c956-4b3b-815f-f5bfd141dbd4",
    ["ui-icons/skills/Update_04.png"] = "a12e7c07-575b-4184-b90d-fa750551b55d",
    ["ui-icons/skills/Update_04_nobg.png"] = "fe269dcb-ab63-4d4d-bd23-f05966663fa9",
    ["ui-icons/skills/Update_05.png"] = "cdfdc83c-4733-41cb-a057-f8d516b8f4b5",
    ["ui-icons/skills/Update_05_nobg.png"] = "7a4ac5dc-784a-4a28-9b11-c0434ec31eb5",
    ["ui-icons/skills/Update_06.png"] = "7f9f2cc4-ffd7-4839-958e-4e67f89ef194",
    ["ui-icons/skills/Update_06_nobg.png"] = "ccba0fea-7dc1-4f09-b7e9-7f7f953a4f5c",
    ["ui-icons/skills/Update_07.png"] = "61e013b6-c580-4630-82d6-c36786104f9b",
    ["ui-icons/skills/Update_07_nobg.png"] = "3014cf21-a57d-427b-ae50-aecd4876e114",
    ["ui-icons/skills/Update_08.png"] = "b4a814fd-4ce8-4f4f-af42-e333465c9cad",
    ["ui-icons/skills/Update_08_nobg.png"] = "44c599ea-4302-42e1-8968-1210ab6f38fa",
    ["ui-icons/skills/Update_09.png"] = "ff949f0a-ec42-49f6-a5ec-4b1645f2a678",
    ["ui-icons/skills/Update_09_nobg.png"] = "c819dbf9-09bd-432a-b07e-d2d54f2ac6c2",
    ["ui-icons/skills/Update_10.png"] = "71e2d091-1fb6-472b-8228-26883c8f8444",
    ["ui-icons/skills/Update_10_nobg.png"] = "81dca9c0-50f7-474a-9354-717b64b204b2",
    ["ui-icons/skills/Warlock_01.png"] = "2f639abd-a986-41c2-95e7-bc87674e24bf",
    ["ui-icons/skills/Warlock_01_nobg.png"] = "9e82db34-a06e-4415-831e-54bc72d2c573",
    ["ui-icons/skills/Warlock_02.png"] = "cc2426b7-7c3e-41d0-bd1e-4579fcae3706",
    ["ui-icons/skills/Warlock_02_nobg.png"] = "4d7dd053-5e20-44e2-8da4-4a83fa820356",
    ["ui-icons/skills/Warlock_03.png"] = "530c5080-2737-4576-844c-e1950351a6e4",
    ["ui-icons/skills/Warlock_03_nobg.png"] = "985339ff-2591-40ea-b6bf-c246583b9abc",
    ["ui-icons/skills/Warlock_04.png"] = "57f36dd0-3536-4bff-a84d-834ece818696",
    ["ui-icons/skills/Warlock_04_nobg.png"] = "7683d913-546b-4329-bbb3-beea9322eeca",
    ["ui-icons/skills/Warlock_05.png"] = "8e5cac6b-4727-4de7-9ac0-ce819117d433",
    ["ui-icons/skills/Warlock_05_nobg.png"] = "8f46eb8c-c9dd-4ff7-b00f-6267ecaa9b95",
    ["ui-icons/skills/Warlock_06.png"] = "05d7cfc6-bed6-4711-92f7-3c28690a0e30",
    ["ui-icons/skills/Warlock_06_nobg.png"] = "a855fa02-f5fd-4424-a415-5f012f389dfb",
    ["ui-icons/skills/Warlock_07.png"] = "d6288df0-a639-4fc6-8138-a694ab894215",
    ["ui-icons/skills/Warlock_07_nobg.png"] = "d078c4a5-53d5-4ec8-96c3-052e40cc72e3",
    ["ui-icons/skills/Warlock_08.png"] = "d393f013-c0c6-49da-bd7c-bb153b469960",
    ["ui-icons/skills/Warlock_08_nobg.png"] = "592698c1-8c10-41d1-84c4-ee4d48e48354",
    ["ui-icons/skills/Warlock_09.png"] = "76ffb96c-ada2-4d82-b3fd-9b8e8ccf2356",
    ["ui-icons/skills/Warlock_09_nobg.png"] = "d226cc22-1128-4a01-8215-f499b6a2e7b7",
    ["ui-icons/skills/Warlock_10.png"] = "1b22ce7c-1a09-40de-a641-095e00943632",
    ["ui-icons/skills/Warlock_10_nobg.png"] = "5c8ee7d2-c0fc-47f5-a30d-5a2f4a7aeb2e",
    ["ui-icons/skills/Warlock_11.png"] = "a9303d2a-9af3-450d-a39e-276da3ef7c58",
    ["ui-icons/skills/Warlock_11_nobg.png"] = "ee8d5b2c-efdb-4310-b8a2-4d10a78a6f79",
    ["ui-icons/skills/Warlock_12.png"] = "a0aa0948-963b-432b-866b-fc7c789bd7bb",
    ["ui-icons/skills/Warlock_12_nobg.png"] = "4f029b66-c472-4096-aeba-385ec6d266cc",
    ["ui-icons/skills/Warlock_13.png"] = "bc916e97-6b61-4abe-9340-6253e2daf2e0",
    ["ui-icons/skills/Warlock_13_nobg.png"] = "b498f83d-c176-44d2-985d-8f6f1e384eec",
    ["ui-icons/skills/Warlock_14.png"] = "488b2057-20a7-4177-a1a2-0b285c0e8fd1",
    ["ui-icons/skills/Warlock_14_nobg.png"] = "75fdc500-b9fc-450c-81c3-314269823960",
    ["ui-icons/skills/Warlock_15.png"] = "03bd1cf4-71a1-4aa6-88a4-34c87df95ae4",
    ["ui-icons/skills/Warlock_15_nobg.png"] = "8690d14e-2416-47ca-b9b8-dbfa0be47c38",
    ["ui-icons/skills/Warlock_16.png"] = "bc85bdb4-d08f-4caa-ab6f-727504bc7f4f",
    ["ui-icons/skills/Warlock_16_nobg.png"] = "60865590-50a5-4df0-bb6d-874a67f781f2",
    ["ui-icons/skills/Warlock_17.png"] = "617f0ae7-6c05-490a-a116-139c92aa4be5",
    ["ui-icons/skills/Warlock_17_nobg.png"] = "523c985a-b400-4169-8786-0ecc0cd01179",
    ["ui-icons/skills/Warlock_18.png"] = "a69a098d-7e40-4e22-a8df-38031a26ca07",
    ["ui-icons/skills/Warlock_18_nobg.png"] = "8c4e3a15-186c-4ea1-8954-53418922ecd8",
    ["ui-icons/skills/Warlock_19.png"] = "4af2392d-cb5c-4afa-a2ae-2db77e79e582",
    ["ui-icons/skills/Warlock_19_nobg.png"] = "35e446b8-7acf-48b7-9618-7b8007a5a2f6",
    ["ui-icons/skills/Warlock_20.png"] = "8a6fe4a8-1816-467a-b781-cf1c698995e0",
    ["ui-icons/skills/Warlock_20_nobg.png"] = "40b9514f-79d7-46c6-8938-e00a5df60f0b",
    ["ui-icons/skills/Warlock_21.png"] = "0506077b-3bd6-4c87-b393-a6d981930cc3",
    ["ui-icons/skills/Warlock_21_nobg.png"] = "4c394d85-1ecf-49ea-8556-7f54826c0f66",
    ["ui-icons/skills/Warlock_22.png"] = "b3c622a0-247c-4b99-a529-1aeb7e32954f",
    ["ui-icons/skills/Warlock_22_nobg.png"] = "1060fe2e-a5ed-49a7-9fd2-c56c1c809e65",
    ["ui-icons/skills/Warlock_23.png"] = "07993350-23b0-41e6-8b2d-f9ad95904b8b",
    ["ui-icons/skills/Warlock_23_nobg.png"] = "a6b56648-3620-47ed-85f4-6592be0803e2",
    ["ui-icons/skills/Warlock_24.png"] = "7ab06019-3280-46e2-ae48-d13781fca329",
    ["ui-icons/skills/Warlock_24_nobg.png"] = "f04f1c2e-d18d-4ffa-86c9-dc0c7537db86",
    ["ui-icons/skills/Warlock_25.png"] = "7b6ab071-8cef-4ac3-a8c8-417f8267cf6b",
    ["ui-icons/skills/Warlock_25_nobg.png"] = "d3e51c56-2cf9-442b-964a-42c1df19c1f6",
    ["ui-icons/skills/Warlock_26.png"] = "e6ea244b-cf51-4818-9247-c6d103e64e33",
    ["ui-icons/skills/Warlock_26_nobg.png"] = "afb68469-a144-4585-a4c9-68779735c700",
    ["ui-icons/skills/Warlock_27.png"] = "29861728-e4da-4c2f-ba7f-e27804136a2a",
    ["ui-icons/skills/Warlock_27_nobg.png"] = "01f96711-b0c8-4d0d-82f2-a91dfce1aca9",
    ["ui-icons/skills/Warlock_28.png"] = "b65f341d-3c90-431f-883b-41fe73df5314",
    ["ui-icons/skills/Warlock_28_nobg.png"] = "823cce09-2531-4b8c-9b75-c8f0b41294ff",
    ["ui-icons/skills/Warlock_29.png"] = "3959c72d-42ff-4960-960f-b97d8d1e3776",
    ["ui-icons/skills/Warlock_29_nobg.png"] = "e28755f0-ad1b-4eb1-a4f6-d772c48fdafd",
    ["ui-icons/skills/Warlock_30.png"] = "ae3c7b80-d464-40db-8c3e-9392e129829b",
    ["ui-icons/skills/Warlock_30_nobg.png"] = "55303e61-34cc-47ea-8d13-775d35160b26",
    ["ui-icons/skills/Warlock_31.png"] = "d4a0aa1c-2faa-4853-9bb5-d7c5cb8d8cd0",
    ["ui-icons/skills/Warlock_31_nobg.png"] = "5cd7e7ee-f068-4bad-be92-2fad1ef05b7f",
    ["ui-icons/skills/Warlock_32.png"] = "8c9ec8c2-703c-48e3-995b-14d7430481a6",
    ["ui-icons/skills/Warlock_32_nobg.png"] = "81785e8c-bf67-4ac1-8038-92ec1501e8ac",
    ["ui-icons/skills/Warlock_33.png"] = "5080e6af-4f6c-44f0-9258-a5be0a498099",
    ["ui-icons/skills/Warlock_33_nobg.png"] = "9c263b66-7ef7-4e2f-8c90-420bad27e295",
    ["ui-icons/skills/Warlock_34.png"] = "ecd14985-06b2-401e-92ff-7c4e8ea6fd48",
    ["ui-icons/skills/Warlock_34_nobg.png"] = "76d0a23f-af33-4a2f-b0bc-27e6977ed5d3",
    ["ui-icons/skills/Warlock_35.png"] = "44a0e7f6-9819-4328-abfd-b0bb22266253",
    ["ui-icons/skills/Warlock_35_nobg.png"] = "9de4d55c-2dba-47e2-99ae-515cd8579237",
    ["ui-icons/skills/Warlock_36.png"] = "e8ec55be-1e96-4d5e-9f51-285b07efc22b",
    ["ui-icons/skills/Warlock_36_nobg.png"] = "9b0f4534-f865-474e-81d4-9536d43de74d",
    ["ui-icons/skills/Warlock_37.png"] = "5e60f043-578c-440d-b1db-ce81642c4d49",
    ["ui-icons/skills/Warlock_37_nobg.png"] = "1d9da517-01d4-4cb2-b48c-868a8036b74f",
    ["ui-icons/skills/Warlock_38.png"] = "bbbc0ca0-7fdb-4920-817a-1cca7591d6d4",
    ["ui-icons/skills/Warlock_38_nobg.png"] = "872c2881-df23-4784-8429-e90dc0a1cb9d",
    ["ui-icons/skills/Warlock_39.png"] = "be12a5c8-7191-4655-a8af-aae267e1a856",
    ["ui-icons/skills/Warlock_39_nobg.png"] = "1c646d16-e4cc-43ee-801a-df7322008751",
    ["ui-icons/skills/Warlock_40.png"] = "58257c62-51fe-4755-a6b9-d1a45f965fef",
    ["ui-icons/skills/Warlock_40_nobg.png"] = "2bd0da04-9ef4-48b2-a8ab-812fbfc5f9e7",
    ["ui-icons/skills/Warlock_41.png"] = "bbf0b84e-f896-4633-a6cf-55a34f703199",
    ["ui-icons/skills/Warlock_41_nobg.png"] = "a6f71276-c56d-4688-99d6-14ae85a9cec1",
    ["ui-icons/skills/Warlock_42.png"] = "c2cfbd13-5cc2-4fce-a1ae-0e8ee471bfdf",
    ["ui-icons/skills/Warlock_42_nobg.png"] = "405c88f0-3bd7-4aa4-bbab-cc96c1a71451",
    ["ui-icons/skills/Warlock_43.png"] = "c12b1836-0b7d-4347-b630-a0f4dd466ab6",
    ["ui-icons/skills/Warlock_43_nobg.png"] = "7882d785-4939-4015-a089-2b1e03351a36",
    ["ui-icons/skills/Warlock_44.png"] = "a1845b35-b3db-436f-803a-735e4839734f",
    ["ui-icons/skills/Warlock_44_nobg.png"] = "ac363ae4-e5ea-4fb8-8fbb-6d386715f402",
    ["ui-icons/skills/Warlock_45.png"] = "c6b5a33f-e41e-4dc0-a176-fabc9e1fa7b9",
    ["ui-icons/skills/Warlock_45_nobg.png"] = "03c847e6-018c-4788-9cdb-e1d6a146ceb1",
    ["ui-icons/skills/Warlock_46.png"] = "53dc1238-ccf5-418d-a4ef-11d57cac6ac5",
    ["ui-icons/skills/Warlock_46_nobg.png"] = "2efd298b-d3ab-4972-96b4-2bc56f35e978",
    ["ui-icons/skills/Warlock_47.png"] = "2d78871b-2ee5-4c0a-901c-caf82d67f41d",
    ["ui-icons/skills/Warlock_47_nobg.png"] = "f1bfc11b-f6ef-4d7f-811e-0a02114fe7aa",
    ["ui-icons/skills/Warlock_48.png"] = "bfb2f4ba-74ff-4e85-b510-a260b4d68321",
    ["ui-icons/skills/Warlock_48_nobg.png"] = "73540f03-438a-438f-a9df-a9a783cdbe56",
    ["ui-icons/skills/Warlock_49.png"] = "78cd04b9-737f-49dd-aac1-f919b5b68367",
    ["ui-icons/skills/Warlock_49_nobg.png"] = "f427553f-be95-44bb-ac8b-91d7560e751f",
    ["ui-icons/skills/Warlock_50.png"] = "25fee67e-3c71-4aae-80ec-b94da4b4ee91",
    ["ui-icons/skills/Warlock_50_nobg.png"] = "72868635-940f-48e4-a335-b360004f715d",
    ["ui-icons/skills/Warriorskill_01.png"] = "40409894-b162-4e7e-af6c-407cefb1a8d2",
    ["ui-icons/skills/Warriorskill_01_nobg.png"] = "6ab27acd-ff5e-4888-a9ff-17253ded06a0",
    ["ui-icons/skills/Warriorskill_02.png"] = "9e5f4315-bc91-4ab5-ade1-7850559c3d76",
    ["ui-icons/skills/Warriorskill_02_nobg.png"] = "70a14ade-4aee-41bc-9f6e-d8b297b70a35",
    ["ui-icons/skills/Warriorskill_03.png"] = "7cfa55b8-386b-4a47-9f2e-475fa9135449",
    ["ui-icons/skills/Warriorskill_03_nobg.png"] = "998621b7-f58c-4181-8c77-1700e49ac075",
    ["ui-icons/skills/Warriorskill_04.png"] = "56448d50-b439-4b7d-ad41-36a6a1cf43b8",
    ["ui-icons/skills/Warriorskill_04_nobg.png"] = "e0af7a4b-79e2-45a2-95a2-2029232214bb",
    ["ui-icons/skills/Warriorskill_05.png"] = "bc3c9338-c37b-4fd3-9cdd-76ebf66a5f04",
    ["ui-icons/skills/Warriorskill_05_nobg.png"] = "aca3d6bd-9af6-41e7-bafb-0d2f74bbff7a",
    ["ui-icons/skills/Warriorskill_06.png"] = "74d83373-45b9-4306-9665-8846ada58321",
    ["ui-icons/skills/Warriorskill_06_nobg.png"] = "3162be79-fa5a-4a32-970e-7027022a653f",
    ["ui-icons/skills/Warriorskill_07.png"] = "ccbae8f0-2ee2-4cad-8fa2-82723ee7dc46",
    ["ui-icons/skills/Warriorskill_07_nobg.png"] = "b4fe92c0-92eb-4635-a94b-b3e37c68bd41",
    ["ui-icons/skills/Warriorskill_08.png"] = "89ea0b21-2d8d-47de-9392-1fbde44e91d0",
    ["ui-icons/skills/Warriorskill_08_nobg.png"] = "de3fe05a-023d-4f81-9559-faba202fd594",
    ["ui-icons/skills/Warriorskill_09.png"] = "3c8c5213-ce07-4f79-97d7-7eff53b6cb47",
    ["ui-icons/skills/Warriorskill_09_nobg.png"] = "2d326e8f-a8ee-44c5-b475-6d29c754d3c3",
    ["ui-icons/skills/Warriorskill_10.png"] = "18fa06a2-db06-4f14-9b28-c267c9790279",
    ["ui-icons/skills/Warriorskill_10_nobg.png"] = "af9d9e02-d70c-4f13-aadf-8e912c73da40",
    ["ui-icons/skills/Warriorskill_11.png"] = "da7719e1-a08b-45fa-bab2-730d6b4beb46",
    ["ui-icons/skills/Warriorskill_11_nobg.png"] = "4ba62ed2-b580-424e-b850-b5d539e789b5",
    ["ui-icons/skills/Warriorskill_12.png"] = "3186ead3-af44-4dba-9003-290bdcbb74bd",
    ["ui-icons/skills/Warriorskill_12_nobg.png"] = "51646e95-55d2-4a3f-8581-f11dba64719d",
    ["ui-icons/skills/Warriorskill_13.png"] = "28a2e00e-3818-4e23-9de5-d128fd4c92ae",
    ["ui-icons/skills/Warriorskill_13_nobg.png"] = "37c76524-0f4f-45f4-8bd5-dafede3d6e01",
    ["ui-icons/skills/Warriorskill_14.png"] = "90b1b520-27fe-4112-a85e-9573695ef025",
    ["ui-icons/skills/Warriorskill_14_nobg.png"] = "1bb4f39b-12bc-4aaa-8d93-064c62586521",
    ["ui-icons/skills/Warriorskill_15.png"] = "fe7bf278-31df-43f1-9d41-c7ce1bb2501c",
    ["ui-icons/skills/Warriorskill_15_nobg.png"] = "7dfbdf79-accb-4993-a307-495619c02d3b",
    ["ui-icons/skills/Warriorskill_16.png"] = "d588e70b-6182-47f0-b23f-d59658ca48d5",
    ["ui-icons/skills/Warriorskill_16_nobg.png"] = "075a7376-9878-4f90-bab6-0b780b7e13a3",
    ["ui-icons/skills/Warriorskill_17.png"] = "e2880dd9-65ff-4608-9bbf-8070c8eb0ff3",
    ["ui-icons/skills/Warriorskill_17_nobg.png"] = "841e4800-1f25-4425-9b9d-e6a9fbbe792e",
    ["ui-icons/skills/Warriorskill_18.png"] = "18918c1a-52e7-46ba-9e08-b5382230ea5d",
    ["ui-icons/skills/Warriorskill_18_nobg.png"] = "dc8e2628-7455-4ba2-961e-8cdd9095a85c",
    ["ui-icons/skills/Warriorskill_19.png"] = "75362704-fb78-4f8e-9513-ee8ee0e3a4d9",
    ["ui-icons/skills/Warriorskill_19_nobg.png"] = "30cdeb38-dc29-45e0-b860-7f8ccf153214",
    ["ui-icons/skills/Warriorskill_20.png"] = "ddf70091-b397-4d9c-8dcf-6c955493a330",
    ["ui-icons/skills/Warriorskill_20_nobg.png"] = "b51dc15b-de80-4004-8499-be861b1e2da6",
    ["ui-icons/skills/Warriorskill_21.png"] = "4541e09d-bd62-407c-8b4c-c9d7efabd990",
    ["ui-icons/skills/Warriorskill_21_nobg.png"] = "4cd0ae7f-56e8-44a1-aa07-ebdd539092d0",
    ["ui-icons/skills/Warriorskill_22.png"] = "efb76dcf-d504-431d-b2fb-70a714540a20",
    ["ui-icons/skills/Warriorskill_22_nobg.png"] = "f12fd3be-e31d-4f0f-ac1e-20f988b6e11e",
    ["ui-icons/skills/Warriorskill_23.png"] = "a17c9a6a-1ca1-4947-8623-2172a921259e",
    ["ui-icons/skills/Warriorskill_23_nobg.png"] = "2db779f8-a498-4fc6-a8e4-4f0f7f609e27",
    ["ui-icons/skills/Warriorskill_24.png"] = "681f1913-df6e-44d9-a07f-543159e7c9c7",
    ["ui-icons/skills/Warriorskill_24_nobg.png"] = "537cb36a-0e02-4263-bf31-711507f62380",
    ["ui-icons/skills/Warriorskill_25.png"] = "a95025f3-c146-4090-a505-a5acf1847a2d",
    ["ui-icons/skills/Warriorskill_25_nobg.png"] = "247018d4-929a-4be2-bdd9-9e398469c78c",
    ["ui-icons/skills/Warriorskill_26.png"] = "cd07713b-a72a-491c-bc53-52ba3c99ef6d",
    ["ui-icons/skills/Warriorskill_26_nobg.png"] = "ec480d53-68e2-462c-b921-c55d324f12d9",
    ["ui-icons/skills/Warriorskill_27.png"] = "bf4ee10b-0ba4-4948-9acb-04475d1eb787",
    ["ui-icons/skills/Warriorskill_27_nobg.png"] = "55aa34e6-4909-4688-b06b-b89a3b910f51",
    ["ui-icons/skills/Warriorskill_28.png"] = "2926a617-1f37-4b97-86e4-06fcf49f1ad7",
    ["ui-icons/skills/Warriorskill_28_nobg.png"] = "66200acc-1f24-4458-9a47-28e0ae32534d",
    ["ui-icons/skills/Warriorskill_29.png"] = "e9e778d3-994c-4d60-97bf-398f8fd687df",
    ["ui-icons/skills/Warriorskill_29_nobg.png"] = "f185c08b-1e62-49f4-92b4-08bc3a7bf9cc",
    ["ui-icons/skills/Warriorskill_30.png"] = "eeb1fe6e-6c87-4f57-8e9a-9c0f469f0974",
    ["ui-icons/skills/Warriorskill_30_nobg.png"] = "1e7634de-ad91-4707-9973-73e59a5c3ac3",
    ["ui-icons/skills/Warriorskill_31.png"] = "b7015676-12d7-4b03-8557-dd8a9aeededa",
    ["ui-icons/skills/Warriorskill_31_nobg.png"] = "5e9e11f6-e1a1-4ba2-a697-2472794d7b89",
    ["ui-icons/skills/Warriorskill_32.png"] = "359c66ca-669b-48b8-a277-2b5fcdff2934",
    ["ui-icons/skills/Warriorskill_32_nobg.png"] = "3e36f2c3-1d80-492a-b50c-3db70850d4c5",
    ["ui-icons/skills/Warriorskill_33.png"] = "75d5253d-6cbf-4e83-a1b9-11cca17be9fa",
    ["ui-icons/skills/Warriorskill_33_nobg.png"] = "b75f274e-7c52-421e-aaa5-35f3032f5ce6",
    ["ui-icons/skills/Warriorskill_34.png"] = "d69bdf58-1258-47a2-a42c-138f1205f882",
    ["ui-icons/skills/Warriorskill_34_nobg.png"] = "eec4c89e-d06d-47b4-9e9f-e77d0e3933a7",
    ["ui-icons/skills/Warriorskill_35.png"] = "81893b2f-c273-4544-90d2-d1cf3f172ef2",
    ["ui-icons/skills/Warriorskill_35_nobg.png"] = "0f0a215a-e768-4bf7-af67-8f399411263a",
    ["ui-icons/skills/Warriorskill_36.png"] = "db62cfe3-25ea-4a7d-9124-03e5fe46ccb1",
    ["ui-icons/skills/Warriorskill_36_nobg.png"] = "f9c9784a-bc77-4015-9f12-3844f46ddac6",
    ["ui-icons/skills/Warriorskill_37.png"] = "a7b5b4fc-dd75-4243-8518-7fdcf35de027",
    ["ui-icons/skills/Warriorskill_37_nobg.png"] = "257fb7fc-7637-4f17-9c42-db0e61d3138f",
    ["ui-icons/skills/Warriorskill_38.png"] = "5034a1db-4d1c-4ae6-8e27-378ac682a5f2",
    ["ui-icons/skills/Warriorskill_38_nobg.png"] = "701ca296-8e89-479e-9808-be28019d88d4",
    ["ui-icons/skills/Warriorskill_39.png"] = "c6bcc2f0-e341-4748-95d7-eac0abc88860",
    ["ui-icons/skills/Warriorskill_39_nobg.png"] = "26a4513b-73b2-4859-bcff-5cf04ad26d82",
    ["ui-icons/skills/Warriorskill_40.png"] = "c619d999-ce57-40bb-8353-374e4bb40417",
    ["ui-icons/skills/Warriorskill_40_nobg.png"] = "f348a841-ffb6-453f-918c-5668a97dc375",
    ["ui-icons/skills/Warriorskill_41.png"] = "938cc9b0-fb2b-4f13-9658-2009f45b3ae3",
    ["ui-icons/skills/Warriorskill_41_nobg.png"] = "63442329-1748-4e50-9690-e5053af50a0d",
    ["ui-icons/skills/Warriorskill_42.png"] = "800edc55-7bac-4749-beec-09c2b8bbe1de",
    ["ui-icons/skills/Warriorskill_42_nobg.png"] = "7fdae295-15c4-46db-be51-a81da84d3dec",
    ["ui-icons/skills/Warriorskill_43.png"] = "9210a0dd-4039-4e5b-9546-3d4788f85785",
    ["ui-icons/skills/Warriorskill_43_nobg.png"] = "422e9a16-bdc7-42a7-986d-dd695b419112",
    ["ui-icons/skills/Warriorskill_44.png"] = "c1af20f2-d8da-4931-890f-34baa1b282b7",
    ["ui-icons/skills/Warriorskill_44_nobg.png"] = "ca6bf534-05c5-488b-b1c0-c9ef56e7edc5",
    ["ui-icons/skills/Warriorskill_45.png"] = "f4fdb9ee-75bc-469d-9ebd-279330f3b8fd",
    ["ui-icons/skills/Warriorskill_45_nobg.png"] = "8b898ffa-d7f8-45d9-bc75-87a9def7671c",
    ["ui-icons/skills/Warriorskill_46.png"] = "0c593e8f-42ac-44bd-9710-6976338476f0",
    ["ui-icons/skills/Warriorskill_46_nobg.png"] = "fcf0c0f3-83c7-492b-9363-30607983494a",
    ["ui-icons/skills/Warriorskill_47.png"] = "e5c7c12d-d214-423f-9ceb-1ce7afe2255f",
    ["ui-icons/skills/Warriorskill_47_nobg.png"] = "6dca6642-2ac7-47b6-9820-d545e74fd2dd",
    ["ui-icons/skills/Warriorskill_48.png"] = "7f12a2af-c926-4074-95e6-725e63edf471",
    ["ui-icons/skills/Warriorskill_48_nobg.png"] = "943000e8-156f-482b-a5de-abfd9b4a4c0c",
    ["ui-icons/skills/Warriorskill_49.png"] = "c7e145c5-6731-48b6-a831-4c22463a8f1f",
    ["ui-icons/skills/Warriorskill_49_nobg.png"] = "60398bbc-9b4f-4c77-9b98-f1c2967c84e0",
    ["ui-icons/skills/Warriorskill_50.png"] = "60b2050a-bcce-408e-be1a-12fa6b5cf7b6",
    ["ui-icons/skills/Warriorskill_50_nobg.png"] = "de6a8c85-45af-4c01-9733-26f1087414e9",
    ["ui-icons/skills/bear_paw.png"] = "3e07d388-b231-4d3f-9480-aef0bcf36a06",
    ["ui-icons/skills/bear_paw_nobg.png"] = "f7fa04e5-d976-470b-8b2c-716c50baa5c0",
    ["ui-icons/skills/claw_strike.png"] = "137e0bac-4824-4cd3-8d4a-740077f85e6e",
    ["ui-icons/skills/claw_strike_nobg.png"] = "d7fe0545-7c6e-4305-a6be-50572d2bbea8",
    ["ui-icons/skills/defiled_leaves.png"] = "72b71da8-a746-4c85-aeda-924b65117d21",
    ["ui-icons/skills/defiled_leaves_nobg.png"] = "17a3721f-4adf-4175-863f-549d12028617",
    ["ui-icons/skills/dragon_coldbreath.png"] = "32d04f9f-a277-4040-8d23-317d91d47694",
    ["ui-icons/skills/dragon_coldbreath_nobg.png"] = "da8b70ac-167a-48f5-9438-1766a12074c4",
    ["ui-icons/skills/dragon_firebreath.png"] = "7c525005-fd0c-4312-aa3c-e53840feea9b",
    ["ui-icons/skills/dragon_firebreath_nobg.png"] = "8aeef91f-fe6e-49ef-a622-16eac3f4478f",
    ["ui-icons/skills/drainlife.png"] = "40ea76df-fed8-431b-b41c-98f9b3aaa91b",
    ["ui-icons/skills/drainlife_nobg.png"] = "71f80cf4-8b3f-4112-b743-034abb371c57",
    ["ui-icons/skills/drunkenness.png"] = "1e632931-399c-4b20-ba3e-315d209993ba",
    ["ui-icons/skills/drunkenness_nobg.png"] = "799c2525-c69b-46e0-8274-65334ebcd9d0",
    ["ui-icons/skills/fel_Cry.png"] = "548f5f71-e4bb-4645-839f-62fb59f0d777",
    ["ui-icons/skills/fell_skin.png"] = "7194aa36-c238-45d9-b85e-ff528cd6bf80",
    ["ui-icons/skills/fell_skin_nobg.png"] = "976a9ebe-0527-4230-9aad-79f5eb8146e9",
    ["ui-icons/skills/fish_speed.png"] = "13d7873a-acff-416a-9de0-f3b9fa56f433",
    ["ui-icons/skills/fish_speed_nobg.png"] = "ad899169-d446-421d-9dfb-e81a2164c564",
    ["ui-icons/skills/fishbite.png"] = "75ad6a30-a7c2-4e12-bc0a-d2eaab713589",
    ["ui-icons/skills/fishbite_nobg.png"] = "cc844e98-34c0-496d-a22b-cdd098b8e745",
    ["ui-icons/skills/flock_of_mice.png"] = "11b9b306-37e6-48e5-8120-8c9927d06eb0",
    ["ui-icons/skills/flock_of_mice_nobg.png"] = "1aa269a1-329e-4580-bce4-6c4ff67fb1ec",
    ["ui-icons/skills/grimhollow-mark.png"] = false,
    ["ui-icons/skills/healing.png"] = "2446d349-cff2-482f-92c1-282a1efdbfd7",
    ["ui-icons/skills/healing_nobg.png"] = "b6f165cd-91c8-4186-bd79-130a8cb97d55",
    ["ui-icons/skills/hit.png"] = "153851d8-652b-4549-a42a-f430b37539e7",
    ["ui-icons/skills/hit_nobg.png"] = "6bc7063f-f482-4d32-b7c2-b661ce0ba066",
    ["ui-icons/skills/hoof_blow.png"] = "a9e24f71-c6a2-4667-adc3-36c1f503c193",
    ["ui-icons/skills/hoof_blow_nobg.png"] = "f97d222f-4070-43de-bdac-db67780f3016",
    ["ui-icons/skills/horns.png"] = "1c1e3ff4-fcb3-4c28-aaa9-5695b549c455",
    ["ui-icons/skills/horns_nobg.png"] = "03d0a842-2c01-4a7d-b702-aed9e7039c9e",
    ["ui-icons/skills/iron_skin.png"] = "016201d3-6718-4f99-8d05-80c04539abfa",
    ["ui-icons/skills/iron_skin_nobg.png"] = "ffe86c5e-7e71-4624-98b0-fc02ac126557",
    ["ui-icons/skills/kick.png"] = "a5a2f275-0fc7-45e7-afd0-fae2d0bb45ca",
    ["ui-icons/skills/kick_nobg.png"] = "c7b096f9-9c85-4adb-9401-343c16abda67",
    ["ui-icons/skills/light_hit.png"] = "b628e354-b135-4a9b-899f-ee6cff91dea3",
    ["ui-icons/skills/light_hit_nobg.png"] = "20852592-6027-4f50-b6c6-2e22d90d29dc",
    ["ui-icons/skills/magic_runes.png"] = "8f9bce30-9a21-4a34-9bf4-4d44ccf07c12",
    ["ui-icons/skills/magic_runes_nobg.png"] = "57444cc2-8fee-430a-8347-6c9febf60a44",
    ["ui-icons/skills/melee-attack-icon.png"] = "8c7e39c4-8599-4722-aa65-266c26e6de1e",
    ["ui-icons/skills/mind_control.png"] = "0eff85ff-753b-4713-8ea7-129fcd6cee37",
    ["ui-icons/skills/mind_control_nobg.png"] = "eb36dde7-7c8b-4e07-b493-8b3e5fcc2617",
    ["ui-icons/skills/poison_claw.png"] = "c6984795-d477-41d0-aa45-325bf0792fa8",
    ["ui-icons/skills/poison_claw_nobg.png"] = "158bdd0d-a8d9-4de3-9413-0d09559ea683",
    ["ui-icons/skills/shadow.png"] = "b146daea-b375-49b8-83e4-b694ffe7e4ea",
    ["ui-icons/skills/shadow_drain.png"] = "467d8000-c5ac-49fb-ab3f-29db70c78f91",
    ["ui-icons/skills/shadow_nobg.png"] = "2a8c2b08-fab3-4a23-a085-0879d0d5ea43",
    ["ui-icons/skills/shadowbolt.png"] = "a1e23493-789a-4996-b773-47d501a2ec60",
    ["ui-icons/skills/shadowbolt_nobg.png"] = "c6810002-23f4-4d4f-871d-0168abdd1928",
    ["ui-icons/skills/skill_1.png"] = "c5c9c4bf-1050-49d9-b7c9-d50c1c59abcd",
    ["ui-icons/skills/skill_10.png"] = "c7e29f6f-6e50-4fc0-9dc0-bcba498d5247",
    ["ui-icons/skills/skill_100.png"] = "d8727e6b-0059-46db-ab69-8aa9b718da81",
    ["ui-icons/skills/skill_100_noBG.png"] = "304a340b-6e8c-4271-afbd-0ce16a16d31f",
    ["ui-icons/skills/skill_101.png"] = "087a3a1a-758d-484f-b268-c833ff051e2d",
    ["ui-icons/skills/skill_101_noBG.png"] = "d3c49be6-fc2e-4d0d-b7fd-8bdb3f80f0b1",
    ["ui-icons/skills/skill_102.png"] = "ed630bb4-eb0a-4d2c-b84a-c935c7e5031c",
    ["ui-icons/skills/skill_102_noBG.png"] = "d6439aeb-7ca0-4c63-94b7-bf1745720cf4",
    ["ui-icons/skills/skill_103.png"] = "e7349677-f899-44da-86ec-cd5f8dd6bbee",
    ["ui-icons/skills/skill_103_noBG.png"] = "1b34d03a-00d5-4546-a475-0a8bc178b149",
    ["ui-icons/skills/skill_104.png"] = "94cbbc6f-ba03-49f5-a3fc-f61c3cc165e1",
    ["ui-icons/skills/skill_104_noBG.png"] = "c825cd94-48b3-42a5-ae54-c7d6941ea6ef",
    ["ui-icons/skills/skill_105.png"] = "6debccf8-19cc-4974-bbc1-34829c145cc5",
    ["ui-icons/skills/skill_105_noBG.png"] = "7ffe4357-445c-4977-975d-ca5dcf0470bc",
    ["ui-icons/skills/skill_106.png"] = "a7349086-de0a-448f-a2fb-512bfca127e1",
    ["ui-icons/skills/skill_106_noBG.png"] = "1270b7c8-b7df-4f80-b9ca-ff723ef5c61f",
    ["ui-icons/skills/skill_107.png"] = "8f4e95a0-3c00-4c3e-8550-5efef10826d0",
    ["ui-icons/skills/skill_107_noBG.png"] = "fbe267e6-2818-407b-9558-68b47d51f096",
    ["ui-icons/skills/skill_108.png"] = "e8acf20d-fdc6-48d1-a611-04d0a3ab415e",
    ["ui-icons/skills/skill_108_noBG.png"] = "efa2c65c-b6cb-4373-a1d8-9532446b0b74",
    ["ui-icons/skills/skill_109.png"] = "b5eeff2c-ecb8-4b03-b5ba-5714ecb8e84a",
    ["ui-icons/skills/skill_109_noBG.png"] = "a2fe7a44-0cf2-4a03-a71a-bb1aa062e507",
    ["ui-icons/skills/skill_10_noBG.png"] = "741818ea-abae-42b0-a9fe-3d731fbb1810",
    ["ui-icons/skills/skill_11.png"] = "a46d459f-3113-4099-84cd-47867c84e3d7",
    ["ui-icons/skills/skill_110.png"] = "e1c2c039-ec23-48db-b9cc-08fb1000f995",
    ["ui-icons/skills/skill_110_noBG.png"] = "b64810d4-ca48-4c83-b70e-c87c3c500c55",
    ["ui-icons/skills/skill_111.png"] = "6b007a46-0c9e-4e59-9668-406022e5a610",
    ["ui-icons/skills/skill_111_noBG.png"] = "69765e23-5ca6-4acd-ba46-6e0aa125c6af",
    ["ui-icons/skills/skill_112.png"] = "968695d6-d095-49fb-b170-e27eaab2fb25",
    ["ui-icons/skills/skill_112_noBG.png"] = "4e5e6b29-d719-434c-8b2e-b3bafbd7be4c",
    ["ui-icons/skills/skill_113.png"] = "d009ecea-777d-4f6b-93a8-cfcafcbda9d4",
    ["ui-icons/skills/skill_113_noBG.png"] = "4c81a569-8f91-41cd-b388-73bbc69923d7",
    ["ui-icons/skills/skill_114.png"] = "afdd9b2e-e8b3-4bf8-84e4-eab96e3a16b6",
    ["ui-icons/skills/skill_114_noBG.png"] = "6c9d70f0-271d-43e9-a6da-3391ffa2b0ac",
    ["ui-icons/skills/skill_115.png"] = "571dd913-9524-4f58-a752-56821a65fcb6",
    ["ui-icons/skills/skill_115_noBG.png"] = "05728e51-a2aa-40ee-9fe7-cee73dacae54",
    ["ui-icons/skills/skill_116.png"] = "43f427dd-a7ee-4e2c-9ac0-371ea61bb7e6",
    ["ui-icons/skills/skill_116_noBG.png"] = "f0bf0289-f991-49de-b923-b2d1ff37497e",
    ["ui-icons/skills/skill_117.png"] = "86a71b10-7bc6-493a-8482-3c99043d29bf",
    ["ui-icons/skills/skill_117_noBG.png"] = "c18af700-1c4e-4e0b-b738-972a8fc096bc",
    ["ui-icons/skills/skill_118.png"] = "bdc079ff-4a2d-459a-a877-df2ba6c07485",
    ["ui-icons/skills/skill_118_noBG.png"] = "4c354ced-b122-4dd5-a20f-d55d5805a184",
    ["ui-icons/skills/skill_119.png"] = "2baf0a49-3264-411f-a6e2-79d0a2b71d8c",
    ["ui-icons/skills/skill_119_noBG.png"] = "6ffff778-ac27-4d0a-8b9b-f44e36b959e5",
    ["ui-icons/skills/skill_11_noBG.png"] = "6981a57d-2f1c-4bde-a482-7cee092feada",
    ["ui-icons/skills/skill_12.png"] = "c18566ce-19d0-4496-b7d8-a859e2382231",
    ["ui-icons/skills/skill_120.png"] = "05c8913d-fcff-49b7-9d7c-47c8aa6c19ee",
    ["ui-icons/skills/skill_120_noBG.png"] = "05d8ff68-4f27-4279-b5db-2ac1d5c70882",
    ["ui-icons/skills/skill_121.png"] = "fd06654c-0d4d-47ef-9cfc-20efb9f9b443",
    ["ui-icons/skills/skill_121_noBG.png"] = "97c3b0ce-2c42-4cdf-8304-ed0fa5d46cd2",
    ["ui-icons/skills/skill_122.png"] = "76b4827f-bd22-4ad6-b304-da2f3887c909",
    ["ui-icons/skills/skill_122_noBG.png"] = "5ad09f79-5f75-4902-b87f-f6d23e341022",
    ["ui-icons/skills/skill_123.png"] = "4e6aacea-afdd-4b85-a2a7-d52618624c90",
    ["ui-icons/skills/skill_124.png"] = "d7ca45fb-58e2-41bf-841a-f759cef5dad9",
    ["ui-icons/skills/skill_124_noBG.png"] = "078adaa4-06b8-4be1-b6a9-1474274068b2",
    ["ui-icons/skills/skill_125.png"] = "f99016b4-a695-4cbf-a5af-3be0f3b8ef90",
    ["ui-icons/skills/skill_125_noBG.png"] = "8187a1c4-a49c-4904-9ec5-2cc96b94a418",
    ["ui-icons/skills/skill_126.png"] = "6749e177-c40d-42e4-9175-82632fe43c60",
    ["ui-icons/skills/skill_126_noBG.png"] = "5b360581-d66a-48c5-9a65-bb4db732a4f5",
    ["ui-icons/skills/skill_127.png"] = "02c3bd48-1afc-4049-97ad-f21d05b0e21d",
    ["ui-icons/skills/skill_127_noBG.png"] = "46390599-f7f9-4b35-9318-ce5f24d31f87",
    ["ui-icons/skills/skill_128.png"] = "a5be38a6-9dca-4faf-8e43-320e0aa7de86",
    ["ui-icons/skills/skill_128_noBG.png"] = "3ba80856-9e75-48cc-8bec-2d0da2a369a2",
    ["ui-icons/skills/skill_129.png"] = "e0f69c4f-3e1c-4c4f-a845-eb1f87934629",
    ["ui-icons/skills/skill_129_noBG.png"] = "146fd5fa-0b01-46ad-ae02-4f6957c7ff56",
    ["ui-icons/skills/skill_12_noBG.png"] = "3b8fd17a-9bd1-4d53-87ca-8d840ccb7c90",
    ["ui-icons/skills/skill_13.png"] = "51458344-452f-4739-8f2c-40bd20a27cf8",
    ["ui-icons/skills/skill_130.png"] = "b96fd492-f66e-4363-b2ca-3a941fd95c46",
    ["ui-icons/skills/skill_130_noBG.png"] = "7acc3607-bcd0-4002-a091-ed3216181658",
    ["ui-icons/skills/skill_131.png"] = "dd00a70f-18ef-434d-a414-65a9a9ec75f9",
    ["ui-icons/skills/skill_131_noBG.png"] = "b0cd2627-e0fb-4426-9d2e-a1005d03e598",
    ["ui-icons/skills/skill_132.png"] = "d6bdeb76-f1e0-4acb-8be0-d0ab8dc15ad2",
    ["ui-icons/skills/skill_132_noBG.png"] = "aa010962-fd4c-4cd7-abe3-4318d67558a7",
    ["ui-icons/skills/skill_133.png"] = "66878827-1e9c-4ed2-8930-4ba75f8a8e4d",
    ["ui-icons/skills/skill_133_noBG.png"] = "4e7911f7-824b-4e92-b73e-b9bfbcc5b24d",
    ["ui-icons/skills/skill_134.png"] = "285155ba-15c8-490c-82da-060e201f5f58",
    ["ui-icons/skills/skill_134_noBG.png"] = "5200646a-6296-4af6-ab12-60f7b5e51271",
    ["ui-icons/skills/skill_135.png"] = "cc2e283e-5a78-4a69-8dee-1bb2645ad305",
    ["ui-icons/skills/skill_135_noBG.png"] = "5293ceb6-8d63-46c1-8d8f-26e8f319a41c",
    ["ui-icons/skills/skill_136.png"] = "8a6b92f1-d8a9-4595-853e-7d2a69abcc97",
    ["ui-icons/skills/skill_136_noBG.png"] = "1ec549f2-9857-43f8-b3ea-8fbfb7ea6dbb",
    ["ui-icons/skills/skill_137.png"] = "cd065811-5296-417e-9952-7c9b946bb895",
    ["ui-icons/skills/skill_137_noBG.png"] = "7a154272-8122-4134-9b4c-b1aa662aec4c",
    ["ui-icons/skills/skill_138.png"] = "307bc479-4d7a-4d56-971a-fb02872c83e5",
    ["ui-icons/skills/skill_138_noBG.png"] = "088479b3-0204-4442-af3f-775128b53971",
    ["ui-icons/skills/skill_139.png"] = "79370da5-89fc-4099-9dde-1bb97c965a98",
    ["ui-icons/skills/skill_139_noBG.png"] = "ddbbd35a-cbfe-439a-9c59-fedafa0f2442",
    ["ui-icons/skills/skill_13_noBG.png"] = "0d0ea12f-7806-4365-95d5-f52a8954f1c2",
    ["ui-icons/skills/skill_14.png"] = "17e47e8a-3fb8-48ba-b76a-9c1f68aea5c4",
    ["ui-icons/skills/skill_140.png"] = "d63c494c-5a1d-4c7d-93f4-5f23b59cc5f2",
    ["ui-icons/skills/skill_140_noBG.png"] = "6ff04204-9d36-4b9c-b7cb-d8b7456c046f",
    ["ui-icons/skills/skill_141.png"] = "e446e9d2-4c0c-4fc5-8a7d-162f37101846",
    ["ui-icons/skills/skill_141_noBG.png"] = "0f038e50-a4b8-4215-8a9e-12530b8f157f",
    ["ui-icons/skills/skill_142.png"] = "3f82bbef-2b65-43d5-a76d-fbc35d278046",
    ["ui-icons/skills/skill_142_noBG.png"] = "ec4c4fb9-b707-4274-a3b6-ca94491be7ac",
    ["ui-icons/skills/skill_143.png"] = "33f04fb1-7bbe-49f5-bb1d-0cc93d065999",
    ["ui-icons/skills/skill_143_noBG.png"] = "be434264-19d5-4af6-8a1a-541c1d2e2fc6",
    ["ui-icons/skills/skill_144.png"] = "79f7661e-9b4e-4e5d-9923-900075bd96cd",
    ["ui-icons/skills/skill_144_noBG.png"] = "63864356-6bf1-4516-8ef1-58a1436a99c1",
    ["ui-icons/skills/skill_145.png"] = "d8ff1628-4a68-4806-8475-36f047979cb5",
    ["ui-icons/skills/skill_145_noBG.png"] = "ca28aa5b-c684-481e-89c2-389cfb52dfba",
    ["ui-icons/skills/skill_146.png"] = "88a1c1b2-be5a-4edf-adb9-964e625ba8a8",
    ["ui-icons/skills/skill_146_noBG.png"] = "632c6632-2527-4fa9-bb62-5a2ab17b57cb",
    ["ui-icons/skills/skill_147.png"] = "68104a19-a21d-440a-a1d0-f310936f329d",
    ["ui-icons/skills/skill_147_noBG.png"] = "be19b0f7-476c-4b23-b832-22cf8a91cb90",
    ["ui-icons/skills/skill_148.png"] = "96cd5c95-17c5-48c5-874b-292b393a5551",
    ["ui-icons/skills/skill_148_noBG.png"] = "27bdf1ad-e034-41b5-bc0b-a3974e753a37",
    ["ui-icons/skills/skill_149.png"] = "3769f853-cac5-4454-be8b-f53b99d5601c",
    ["ui-icons/skills/skill_149_noBG.png"] = "8b978d57-497d-4cc8-ac3c-c0fd43756786",
    ["ui-icons/skills/skill_14_noBG.png"] = "b321a153-37c9-44d8-8b61-17c8b858ef91",
    ["ui-icons/skills/skill_15.png"] = "11d3eb1b-3d5b-4b93-b261-220d94767550",
    ["ui-icons/skills/skill_150.png"] = "66a1d162-e977-4c44-9880-d48554ae9cae",
    ["ui-icons/skills/skill_150_noBG.png"] = "f16141be-cf80-4d28-b197-536529942d0c",
    ["ui-icons/skills/skill_151.png"] = "1ba71be6-29f8-4782-b30c-90bb78a1a141",
    ["ui-icons/skills/skill_151_noBG.png"] = "0acff7ee-b568-44ae-bc8d-b9d40a0166a6",
    ["ui-icons/skills/skill_152.png"] = "701a7a7c-3578-4858-99cc-c07b6200e370",
    ["ui-icons/skills/skill_152_noBG.png"] = "f5b79037-8789-4171-98f6-0da8a10367cc",
    ["ui-icons/skills/skill_153.png"] = "02446d58-16b4-4842-972c-9099e5672c68",
    ["ui-icons/skills/skill_153_noBG.png"] = "750e773e-c92e-4679-9e4f-ce2a2cad0031",
    ["ui-icons/skills/skill_154.png"] = "2e4d475e-233e-4b56-9b1d-e28a49ee756a",
    ["ui-icons/skills/skill_154_noBG.png"] = "7d0f6060-c3a9-4502-bc2f-f41c9f80a8a6",
    ["ui-icons/skills/skill_155.png"] = "cb0c91f8-a62a-4681-9663-322d93045f6e",
    ["ui-icons/skills/skill_155_noBG.png"] = "4eaf3be8-4739-41aa-a22f-24f4f9585f01",
    ["ui-icons/skills/skill_156.png"] = "15e41b54-bb97-45cc-93b3-48eb5fb2bea9",
    ["ui-icons/skills/skill_156_noBG.png"] = "ab51b1cd-1006-484b-bf68-b0f469de6cef",
    ["ui-icons/skills/skill_157.png"] = "20fcc914-ed62-4100-8ca1-8e1e24bbad35",
    ["ui-icons/skills/skill_157_noBG.png"] = "a26528b0-0914-4391-9db7-43597afd0cff",
    ["ui-icons/skills/skill_158.png"] = "9e9937e3-ef88-44e1-9a3a-65753224dda1",
    ["ui-icons/skills/skill_158_noBG.png"] = "e76fe928-d9b1-47b7-9a25-96b3566a6248",
    ["ui-icons/skills/skill_159.png"] = "6df85a67-9a43-4ea8-b343-0856102ec7ce",
    ["ui-icons/skills/skill_159_noBG.png"] = "d7ea988c-4745-4328-98ed-9d185328a3c9",
    ["ui-icons/skills/skill_15_noBG.png"] = "273ee6bc-844a-49da-b2e7-4680cf41aa72",
    ["ui-icons/skills/skill_16.png"] = "3d8b6d74-0da9-48c4-bed7-931718f56b1b",
    ["ui-icons/skills/skill_160.png"] = "fc9d44a6-0eb8-4dde-aa6f-389603931076",
    ["ui-icons/skills/skill_160_noBG.png"] = "e2589613-8a21-405d-8c28-30f9a2a4d8de",
    ["ui-icons/skills/skill_161.png"] = "e12e83d1-6a57-4ea2-9073-b40de87f128c",
    ["ui-icons/skills/skill_161_noBG.png"] = "5fd3cda6-c3e7-4fab-88d7-13a33eb79497",
    ["ui-icons/skills/skill_162.png"] = "0eac5a41-6f48-48a3-aa55-9adf199d0e90",
    ["ui-icons/skills/skill_162_noBG.png"] = "c94ae081-8d4e-4882-bd8e-836dac2b04a6",
    ["ui-icons/skills/skill_163.png"] = "a4d31a83-6053-4126-b9ed-e1452a01eb68",
    ["ui-icons/skills/skill_163_noBG.png"] = "9d6a950d-24fc-43d5-8c5c-dcf5752dca21",
    ["ui-icons/skills/skill_164.png"] = "b00ff60b-d5b8-4737-93cc-29247a2a3dd2",
    ["ui-icons/skills/skill_164_noBG.png"] = "f2fe36c3-324f-4479-8050-a1a0a3cb5942",
    ["ui-icons/skills/skill_165.png"] = "f3793aa9-0375-4bd2-84d3-7432434c2f37",
    ["ui-icons/skills/skill_165_noBG.png"] = "309ff73f-357e-43c3-a137-8aebf814c632",
    ["ui-icons/skills/skill_166.png"] = "95a68c77-1a9b-442d-af08-b88f263408c1",
    ["ui-icons/skills/skill_166_noBG.png"] = "219d9fb2-33bd-4b25-9049-fac0dbd9a23f",
    ["ui-icons/skills/skill_167.png"] = "80bca30c-3cf9-4e52-9953-e1573e6dc298",
    ["ui-icons/skills/skill_167_noBG.png"] = "802c2634-2257-4dbb-88c6-4233cc47012b",
    ["ui-icons/skills/skill_168.png"] = "44f84ef5-252d-4b3d-874d-102fbd110a7b",
    ["ui-icons/skills/skill_168_noBG.png"] = "685fd508-58fa-43bc-ae95-a074950deac1",
    ["ui-icons/skills/skill_169.png"] = "dd577b1a-6edf-45ac-873e-58bbbac42d2b",
    ["ui-icons/skills/skill_169_noBG.png"] = "eafcf7c5-6c94-4407-b0f6-8d7cff43c104",
    ["ui-icons/skills/skill_16_noBG.png"] = "970b2e94-0029-4e4d-836a-21fe799123f8",
    ["ui-icons/skills/skill_17.png"] = "6c2545d2-454e-4b76-b150-4c7913509970",
    ["ui-icons/skills/skill_170.png"] = "c251d524-ec76-4ce4-a0ae-7a87f321f420",
    ["ui-icons/skills/skill_170_noBG.png"] = "1dce7652-06ab-4697-904a-0ec6cc88cc26",
    ["ui-icons/skills/skill_171.png"] = "7f532afc-74a7-469e-a420-32181cac3f96",
    ["ui-icons/skills/skill_171_noBG.png"] = "e2fb06d7-174d-4523-bc7d-509586c71d0b",
    ["ui-icons/skills/skill_172.png"] = "136729a1-b9b0-4530-bf09-682a5fbb02f3",
    ["ui-icons/skills/skill_172_noBG.png"] = "4ab21199-389a-4018-9d46-71400d3c4819",
    ["ui-icons/skills/skill_173.png"] = "5d5219fe-5902-4f1d-95d7-795fde55c9d5",
    ["ui-icons/skills/skill_173_noBG.png"] = "905ca6bb-17ee-405d-948f-d2b40058fe96",
    ["ui-icons/skills/skill_174.png"] = "52eab225-7634-47da-a336-02185c09ed7c",
    ["ui-icons/skills/skill_174_noBG.png"] = "1dca6806-3c7d-479c-aa00-b8de7259fb9e",
    ["ui-icons/skills/skill_175.png"] = "7d268109-b46f-49a7-aa16-0eb81052a1a9",
    ["ui-icons/skills/skill_175_noBG.png"] = "15d1de74-67c8-47b5-b7f8-28df90fc3198",
    ["ui-icons/skills/skill_176.png"] = "e93eecb7-a965-46b7-b5b2-dad4e4a55ce5",
    ["ui-icons/skills/skill_176_noBG.png"] = "35134b4b-71fa-474c-a188-29916f6a650a",
    ["ui-icons/skills/skill_177.png"] = "3d4cd4b4-f26a-4282-a87e-bcec1e6ef293",
    ["ui-icons/skills/skill_177_noBG.png"] = "6cf8f862-f1bc-4cab-871f-524cb16ee003",
    ["ui-icons/skills/skill_178.png"] = "fe346484-fef0-496f-9682-90763438eb8d",
    ["ui-icons/skills/skill_178_noBG.png"] = "6d932456-37bd-4483-8252-a5b1dc792e10",
    ["ui-icons/skills/skill_179.png"] = "4737e3f1-bb27-4630-84b6-09a02b5b8a67",
    ["ui-icons/skills/skill_179_noBG.png"] = "8b509e09-547b-4fb1-bd37-dd17553eeb8e",
    ["ui-icons/skills/skill_17_noBG.png"] = "73801e0e-9280-4866-af39-f07c2576699b",
    ["ui-icons/skills/skill_18.png"] = "638a8dbe-e4ea-4614-a623-ad97cbd7eaed",
    ["ui-icons/skills/skill_180.png"] = "4e3057b2-a13d-4d67-b003-69b808d5a0a1",
    ["ui-icons/skills/skill_180_noBG.png"] = "26e3ec69-3df3-4ff2-a8ea-6f67eb0cdd9f",
    ["ui-icons/skills/skill_181.png"] = "b60792c8-1458-44de-ab0f-ce4c2fe53173",
    ["ui-icons/skills/skill_181_noBG.png"] = "f181bd02-7f7d-466f-a70b-9d80f67e9df6",
    ["ui-icons/skills/skill_182.png"] = "55185ebd-04e5-4c8e-9f21-41ada25474e4",
    ["ui-icons/skills/skill_182_noBG.png"] = "89f4cdc9-16d5-45a8-8a7b-93e6b521100b",
    ["ui-icons/skills/skill_183.png"] = "7256b76a-bc3a-4a62-816f-b517da391773",
    ["ui-icons/skills/skill_183_noBG.png"] = "134a5606-1dbe-49ae-84ca-22e0b68e641e",
    ["ui-icons/skills/skill_184.png"] = "744204da-3124-46b5-99e7-5b8eea07b40b",
    ["ui-icons/skills/skill_184_noBG.png"] = "7ae6edf0-e24a-40e8-9724-7caca8adc53e",
    ["ui-icons/skills/skill_185.png"] = "c57e90d4-ead2-4843-8654-21ec41669810",
    ["ui-icons/skills/skill_185_noBG.png"] = "1debe432-7b74-45a4-b9bc-11d30333e566",
    ["ui-icons/skills/skill_186.png"] = "94fe72ee-2434-4cb8-b1a5-b82f9e23f493",
    ["ui-icons/skills/skill_186_noBG.png"] = "7c24f8f9-acb0-4e54-9e40-b17196eadd3a",
    ["ui-icons/skills/skill_187.png"] = "7fa8b0c0-f5a6-484a-8140-23c9594fed53",
    ["ui-icons/skills/skill_187_noBG.png"] = "71beb29c-96d2-4554-9f39-c0f6e7ace584",
    ["ui-icons/skills/skill_188.png"] = "c26f36a6-3e84-49f1-94bf-a941153ecb2c",
    ["ui-icons/skills/skill_189.png"] = "059553c0-65cf-4bdd-b7fe-228710ffc310",
    ["ui-icons/skills/skill_189_noBG.png"] = "4fcc1b87-081c-4312-92c4-25be088c118a",
    ["ui-icons/skills/skill_18_noBG.png"] = "ea31d2d9-7401-4f45-88c9-1200b0dc4466",
    ["ui-icons/skills/skill_19.png"] = "bc8a683d-ead5-460f-974b-8e6236b63118",
    ["ui-icons/skills/skill_190.png"] = "25bb7106-af08-4c8b-9fee-af919b13b024",
    ["ui-icons/skills/skill_190_noBG.png"] = "ccbf5197-b334-4c1a-9c52-c6289bf025d2",
    ["ui-icons/skills/skill_191.png"] = "ceb64bda-f333-4755-bf9e-d34a775a2676",
    ["ui-icons/skills/skill_191_noBG.png"] = "f2bf3d14-8318-4be5-946d-41348be15476",
    ["ui-icons/skills/skill_192.png"] = "4726d161-4b6b-4ae2-ad87-a03da5984160",
    ["ui-icons/skills/skill_192_noBG.png"] = "bd81a752-8da9-4652-ad3a-f3b430cbfd7d",
    ["ui-icons/skills/skill_193.png"] = "a47fecfd-9d33-4346-8ee3-cb7b29012cb1",
    ["ui-icons/skills/skill_193_noBG.png"] = "9ddcf480-8199-42a2-ba84-07affe72f308",
    ["ui-icons/skills/skill_194.png"] = "15080cf9-638e-429f-be8c-aaad847e0c1b",
    ["ui-icons/skills/skill_194_noBG.png"] = "6c254847-e117-40dd-9258-b1664d293b75",
    ["ui-icons/skills/skill_195.png"] = "3c9dc175-373c-4907-821b-2f85eac4ea17",
    ["ui-icons/skills/skill_195_noBG.png"] = "d9d8493a-7783-437f-a7e7-56e9f7ef9b6a",
    ["ui-icons/skills/skill_196.png"] = "8ae43a27-fcbd-42a6-8b15-1a4941979065",
    ["ui-icons/skills/skill_196_noBG.png"] = "7703f1e2-da54-4436-953b-83758e3fa0e2",
    ["ui-icons/skills/skill_197.png"] = "19a8b80d-320f-408a-9b5f-145a86863f66",
    ["ui-icons/skills/skill_197_noBG.png"] = "82d1d28e-2eb3-4327-bd3b-7d359b12c229",
    ["ui-icons/skills/skill_198.png"] = "c008f551-cf88-4657-bb53-04a5e94a1e34",
    ["ui-icons/skills/skill_198_noBG.png"] = "11b8136c-1bbf-4d74-a1ec-c58f81e66f57",
    ["ui-icons/skills/skill_199.png"] = "c9858b82-741b-4848-af87-205329ac5ed1",
    ["ui-icons/skills/skill_199_noBG.png"] = "dcad1722-24d0-469c-9aa3-55e54c8f3be2",
    ["ui-icons/skills/skill_19_noBG.png"] = "714f8a38-5ee7-4cb2-a8d2-89b7348854ae",
    ["ui-icons/skills/skill_1_noBG.png"] = "6929f97b-0bcb-4824-b52b-b328187339c2",
    ["ui-icons/skills/skill_2.png"] = "b498a7e9-00eb-4fe3-b844-f7d4d54e03d2",
    ["ui-icons/skills/skill_20.png"] = "a2382d34-4a7b-441d-b1f8-6500ad683d9e",
    ["ui-icons/skills/skill_200.png"] = "91f70d00-66df-4224-97c4-4d3d48275860",
    ["ui-icons/skills/skill_200_noBG.png"] = "840866bb-d82c-44fb-8d28-74bd7d41e369",
    ["ui-icons/skills/skill_201.png"] = "17545cbc-91b2-4c50-94f8-6e9ea20e616c",
    ["ui-icons/skills/skill_201_noBG.png"] = "a972d2f7-0a88-4a17-8a33-5ac5eef8fe36",
    ["ui-icons/skills/skill_202_noBG.png"] = "4016f91c-6f24-4aae-922d-477898dae831",
    ["ui-icons/skills/skill_203_noBG.png"] = "c87b673f-a6e4-4bc5-bf90-836d9e97e781",
    ["ui-icons/skills/skill_204_noBG.png"] = "33362ef6-3d13-4b44-abf2-381f95df6114",
    ["ui-icons/skills/skill_205_noBG.png"] = "a5dc736a-0220-4a71-9565-ba3d40221128",
    ["ui-icons/skills/skill_206_noBG.png"] = "5ee6f209-810c-47a0-b2be-53a2f83137b8",
    ["ui-icons/skills/skill_207_noBG.png"] = "ad332939-5bc9-4c77-a1b8-30252f5098d5",
    ["ui-icons/skills/skill_208_noBG.png"] = "59f04b56-4d0c-4e76-88f4-9914918b0375",
    ["ui-icons/skills/skill_209_noBG.png"] = "3c282bf0-186f-4db6-bcfb-5f895f42d03c",
    ["ui-icons/skills/skill_20_noBG.png"] = "69e96018-2911-4798-a802-ebe1eac9494f",
    ["ui-icons/skills/skill_21.png"] = "642d58ae-c390-413e-8b6a-e724bc587267",
    ["ui-icons/skills/skill_210.png"] = "8a85b27f-3325-404a-b273-20442e71ef52",
    ["ui-icons/skills/skill_210_noBG.png"] = "b2340531-3ba2-47d9-978b-5158a4274fe0",
    ["ui-icons/skills/skill_211.png"] = "6886cfe1-56c1-4426-903b-f8eb8c16d6b0",
    ["ui-icons/skills/skill_211_noBG.png"] = "ccaa1446-7600-4000-9a2c-a4cfb5ba109d",
    ["ui-icons/skills/skill_212_noBG.png"] = "8297f151-b2e5-4c93-a3e6-5f44d01348a7",
    ["ui-icons/skills/skill_213_noBG.png"] = "a6e3c749-604b-4c68-8ead-152e7879357a",
    ["ui-icons/skills/skill_214_noBG.png"] = "bf7e5148-f4da-47d2-9d55-6524352be98d",
    ["ui-icons/skills/skill_215_noBG.png"] = "f7443a4b-eefd-44c0-af52-55b397cfcba4",
    ["ui-icons/skills/skill_216_noBG.png"] = "3a0fbc30-ca00-4264-98ab-e681e844f5c2",
    ["ui-icons/skills/skill_217_noBG.png"] = "54d2a7c5-2f19-4b56-b18b-5f76358749e9",
    ["ui-icons/skills/skill_218_noBG.png"] = "df4c7a20-4fa9-406c-9a95-a0c867ca8827",
    ["ui-icons/skills/skill_219_noBG.png"] = "90a7f84d-146d-45d8-86ae-30f3b138ab5b",
    ["ui-icons/skills/skill_21_noBG.png"] = "47bf5673-06b2-4c03-9026-2e279ecf2f3b",
    ["ui-icons/skills/skill_22.png"] = "d2b04795-5b25-408a-9fd7-00beed3e4c2f",
    ["ui-icons/skills/skill_220_noBG.png"] = "b32eeba4-3942-456b-aaa0-b4644c34de18",
    ["ui-icons/skills/skill_221_noBG.png"] = "a8242fa5-de71-4ee0-a4c7-f7b631661a7e",
    ["ui-icons/skills/skill_222_noBG.png"] = "9e9ab422-1ca3-4731-96e8-ca177f8176ca",
    ["ui-icons/skills/skill_223_noBG.png"] = "27e6ec3f-2439-4e52-b52e-1d8da2170735",
    ["ui-icons/skills/skill_224_noBG.png"] = "9815ca39-27f0-472f-938f-58432cb5a70b",
    ["ui-icons/skills/skill_226.png"] = "0b80992e-54be-477e-9106-d0ab796485b2",
    ["ui-icons/skills/skill_226_noBG.png"] = "754d3447-cdf5-4222-8be3-a95a9dc3cb52",
    ["ui-icons/skills/skill_227_noBG.png"] = "e8a6e35d-4aff-40e5-8a91-66ad7c45efb0",
    ["ui-icons/skills/skill_228_noBG.png"] = "a01a4528-1633-4e61-bdd2-35a3f98859b4",
    ["ui-icons/skills/skill_229_noBG.png"] = "415f9a9b-1fb4-45e3-acf7-efb55160f1f1",
    ["ui-icons/skills/skill_22_noBG.png"] = "bd44e33a-fb70-490c-acac-882da0d34642",
    ["ui-icons/skills/skill_23.png"] = "06053050-a0db-46e7-b40f-ca6e824575c6",
    ["ui-icons/skills/skill_230.png"] = "4448f9e3-ad18-48cb-bb07-909981999202",
    ["ui-icons/skills/skill_230_noBG.png"] = "c942de61-5d0d-4c4f-aef3-0cdebfeb51f8",
    ["ui-icons/skills/skill_232_noBG.png"] = "76936e84-d117-4dfd-b0fd-9291eb0a736b",
    ["ui-icons/skills/skill_233_noBG.png"] = "bc38452a-a947-4bdf-b647-c5176623e1dc",
    ["ui-icons/skills/skill_234_noBG.png"] = "c3187372-7bac-4890-a14a-fc6593298c21",
    ["ui-icons/skills/skill_235_noBG.png"] = "25f79099-1987-4cb7-a4f5-85a6cdd4f869",
    ["ui-icons/skills/skill_236_noBG.png"] = "7e1ad5ec-a2d9-461a-9581-401cf46535f2",
    ["ui-icons/skills/skill_237_noBG.png"] = "6fb55862-4058-48ee-9915-ba03ddf5ec28",
    ["ui-icons/skills/skill_238_noBG.png"] = "85d5e640-0dd1-4329-a8b6-567343de8c35",
    ["ui-icons/skills/skill_239_noBG.png"] = "be243844-1518-43c7-a549-56c8e2c24ed5",
    ["ui-icons/skills/skill_23_noBG.png"] = "b30bdabc-7b24-4a0a-98f7-6b9e4ecf6e4d",
    ["ui-icons/skills/skill_24.png"] = "e189659a-e01b-466e-99a7-57040e3c3a2d",
    ["ui-icons/skills/skill_240_noBG.png"] = "e551ff19-9613-46bc-aa9b-d6efef8afba2",
    ["ui-icons/skills/skill_241_noBG.png"] = "a41ebd61-0821-4f34-8a2d-e13287198170",
    ["ui-icons/skills/skill_242_noBG.png"] = "d37c25a3-9aa8-4d34-adea-d06ab949a4f7",
    ["ui-icons/skills/skill_243_noBG.png"] = "5963d2a8-2527-4237-8686-2087c040e678",
    ["ui-icons/skills/skill_244.png"] = "423955a8-e911-404b-b4a3-f29b9bea4428",
    ["ui-icons/skills/skill_244_noBG.png"] = "9477e243-1ad2-4feb-81dd-46a0f49715fd",
    ["ui-icons/skills/skill_245.png"] = "1f776040-e342-43f4-b99d-71111d191e98",
    ["ui-icons/skills/skill_245_noBG.png"] = "4c8cff43-6264-44ee-810b-dfce169f0cbc",
    ["ui-icons/skills/skill_247_noBG.png"] = "c9f5b310-85ba-4bcb-a37b-15f34cad9b61",
    ["ui-icons/skills/skill_248_noBG.png"] = "6934cdce-9aa7-44ee-836c-51e6041c7799",
    ["ui-icons/skills/skill_249_noBG.png"] = "b1e91963-51cf-47cc-9f21-ae1eb54fade7",
    ["ui-icons/skills/skill_24_noBG.png"] = "0353d8cb-6d58-4f7c-af37-379ca0ddd1d6",
    ["ui-icons/skills/skill_25.png"] = "70bbd9fe-2ae7-4da8-99ff-31b706708645",
    ["ui-icons/skills/skill_250_noBG.png"] = "0ad531ce-ae0b-4cec-9d1d-b36830c995c8",
    ["ui-icons/skills/skill_251_noBG.png"] = "699a0850-7e72-4649-9229-be0712e644a8",
    ["ui-icons/skills/skill_252_noBG.png"] = "48c4cd83-cafe-4874-b048-e1e690a8eb85",
    ["ui-icons/skills/skill_253_noBG.png"] = "deb55870-6d1a-40e8-afbe-ae7b62614367",
    ["ui-icons/skills/skill_254.png"] = "ecd0deca-0d80-425f-8106-5a7b5b5abcfc",
    ["ui-icons/skills/skill_254_noBG.png"] = "b2013c30-5cb0-4631-92a8-fd0e35ddd138",
    ["ui-icons/skills/skill_256_noBG.png"] = "e3f945da-dd37-4387-98e1-c118f406a210",
    ["ui-icons/skills/skill_257_noBG.png"] = "3d546364-47a0-4b41-a77f-1dbfe4291b93",
    ["ui-icons/skills/skill_258_noBG.png"] = "2f7ef33c-62ed-496f-a13a-b983465ea6a3",
    ["ui-icons/skills/skill_259_noBG.png"] = "2b28af90-9472-4ca7-8141-9e4d9c935be2",
    ["ui-icons/skills/skill_25_noBG.png"] = "4d1a68ab-0260-448c-a2da-c6747044169f",
    ["ui-icons/skills/skill_26.png"] = "d9032c45-7121-4674-a48d-68c32c60d7f5",
    ["ui-icons/skills/skill_260_noBG.png"] = "c4e20f89-e25a-43e1-b324-61266cd2c363",
    ["ui-icons/skills/skill_261_noBG.png"] = "5ea7c996-1408-4045-8f81-0856e84896b1",
    ["ui-icons/skills/skill_262_noBG.png"] = "97360ec6-c5db-4d63-b6e6-52c047d2a2eb",
    ["ui-icons/skills/skill_263_noBG.png"] = "d82fa29a-83c5-4f6f-b5e9-49d3fb979365",
    ["ui-icons/skills/skill_264_noBG.png"] = "5c11f57e-1f05-4670-8558-82b1bd99325a",
    ["ui-icons/skills/skill_265_noBG.png"] = "c924b377-4036-4e31-b684-ec9856973e58",
    ["ui-icons/skills/skill_266_noBG.png"] = "513ab6c9-bf74-43ff-8691-6e960426aa64",
    ["ui-icons/skills/skill_267_noBG.png"] = "892c21e9-f599-4773-8304-0f3d9f3aa873",
    ["ui-icons/skills/skill_268_noBG.png"] = "30d4e80f-60e4-4ef2-b9ec-05f56003b2c4",
    ["ui-icons/skills/skill_269_noBG.png"] = "6cb59189-c057-4e1c-9704-2ea620f855b3",
    ["ui-icons/skills/skill_26_noBG.png"] = "77ec3c46-ecbc-44da-9fdc-3475ba68dd16",
    ["ui-icons/skills/skill_27.png"] = "6293c78a-ad6c-465e-be17-f9edd63ea1ef",
    ["ui-icons/skills/skill_270_noBG.png"] = "34b04e7a-c0c0-49d9-803c-0cab4d523a78",
    ["ui-icons/skills/skill_271_noBG.png"] = "9afacfa0-597b-4dc6-ab18-018f621cdb55",
    ["ui-icons/skills/skill_272_noBG.png"] = "dc0fe01b-5074-42db-9772-bbc35c76c407",
    ["ui-icons/skills/skill_273_noBG.png"] = "0e6f1c1d-5d64-497c-91c7-f5ea1925ee29",
    ["ui-icons/skills/skill_274_noBG.png"] = "611d90d1-ad5c-4623-9dae-4cca3714ab8f",
    ["ui-icons/skills/skill_275_noBG.png"] = "9bb48f5f-efdf-43e4-9dda-345efd41278c",
    ["ui-icons/skills/skill_276_noBG.png"] = "41b3e11e-c88a-4c09-b841-1ff8eb6c3bfc",
    ["ui-icons/skills/skill_277_noBG.png"] = "af487f92-4c69-4b5a-b078-5ed5edc7e42f",
    ["ui-icons/skills/skill_279_noBG.png"] = "18d2805e-2ebe-4774-b593-573c77829588",
    ["ui-icons/skills/skill_27_noBG.png"] = "11015bc7-d069-4b21-bcf0-d12932783938",
    ["ui-icons/skills/skill_28.png"] = "2e48131a-352c-44c1-9220-800c31c8714b",
    ["ui-icons/skills/skill_280_noBG.png"] = "7f94c219-91ca-4052-8bb3-b886e0fce8a1",
    ["ui-icons/skills/skill_281_noBG.png"] = "9a3a1f0c-03a9-4ea5-9c5a-2480fb79ee58",
    ["ui-icons/skills/skill_282_noBG.png"] = "6876d00e-f95a-4a61-a96c-2ebf708a2cf7",
    ["ui-icons/skills/skill_283_noBG.png"] = "0d5ad2b2-98e5-4cc7-8e34-4a647de563d9",
    ["ui-icons/skills/skill_284_noBG.png"] = "f6c3bf49-6772-457d-a0f7-2e99d18c246b",
    ["ui-icons/skills/skill_285_noBG.png"] = "685fc71e-cd14-44ec-8ba9-bb84eafbb78b",
    ["ui-icons/skills/skill_287_noBG.png"] = "bf6ee765-56cc-4329-b9f9-b21566013646",
    ["ui-icons/skills/skill_288_noBG.png"] = "5ed9598f-a672-4ef5-afe3-30c1fb4e3e18",
    ["ui-icons/skills/skill_289_noBG.png"] = "bad659fa-9bf8-4fd4-9125-937a7602994e",
    ["ui-icons/skills/skill_28_noBG.png"] = "1a346f4b-a6d1-4452-bf45-c884eca37c5e",
    ["ui-icons/skills/skill_29.png"] = "203a4a90-8d38-4e2e-a043-48a113540ca9",
    ["ui-icons/skills/skill_290_noBG.png"] = "4b897a9d-5bb5-4ba0-8027-aeebada91d8a",
    ["ui-icons/skills/skill_291_noBG.png"] = "3829c1c7-7cf9-4757-b767-7a5ea1dc32ca",
    ["ui-icons/skills/skill_292_noBG.png"] = "6cbd20b6-bb75-4629-8e81-a4ffac7a8070",
    ["ui-icons/skills/skill_293_noBG.png"] = "fe52d7e8-538b-4733-a09e-21a8f3150b92",
    ["ui-icons/skills/skill_294_noBG.png"] = "c37bc150-9f6f-4ef4-a4e1-c4dbcdc2476b",
    ["ui-icons/skills/skill_295_noBG.png"] = "f1bbd4dc-5771-455e-868c-fb5cdade6729",
    ["ui-icons/skills/skill_296_noBG.png"] = "67dcf6be-866f-44fc-8434-0103c32ca3f9",
    ["ui-icons/skills/skill_297_noBG.png"] = "ed480f01-6ede-4de8-a64e-e809e8033f81",
    ["ui-icons/skills/skill_298_noBG.png"] = "a13ba291-fded-4f48-855a-0e4ed5e2fd95",
    ["ui-icons/skills/skill_299_noBG.png"] = "d5ec2b96-f811-4bec-85f1-95650ffd8b0b",
    ["ui-icons/skills/skill_29_noBG.png"] = "eeb32554-3c0d-4429-bcac-3f2666c07838",
    ["ui-icons/skills/skill_2_noBG.png"] = "0ce251d7-143f-4530-9f63-57c8a88aa359",
    ["ui-icons/skills/skill_3.png"] = "ee0583da-de11-4e6c-bcf1-c7bffd85ebf1",
    ["ui-icons/skills/skill_30.png"] = "855f3359-2f74-4e2a-847d-786a7b2c3765",
    ["ui-icons/skills/skill_300_noBG.png"] = "19beb363-3a3b-4e8e-8cfe-3086a9a6bc03",
    ["ui-icons/skills/skill_301_noBG.png"] = "32565615-eee0-4e99-b6e7-d13211be7e92",
    ["ui-icons/skills/skill_303_noBG.png"] = "3ff89522-1eba-4052-b79e-6cdf913357f1",
    ["ui-icons/skills/skill_304_noBG.png"] = "925c6a87-214b-4f8d-bc20-83e96b23dd12",
    ["ui-icons/skills/skill_305_noBG.png"] = "37bdb220-e717-4067-b5f2-7f98235783b9",
    ["ui-icons/skills/skill_306_noBG.png"] = "9f385dd3-1726-4091-bf8b-ed1d8ebe1784",
    ["ui-icons/skills/skill_307_noBG.png"] = "cf981aee-0e1d-4e44-8382-9d6a2a95daa7",
    ["ui-icons/skills/skill_308_noBG.png"] = "6551a856-3e5f-4cbf-923b-128bbfe06eac",
    ["ui-icons/skills/skill_309_noBG.png"] = "e70b3307-972e-44a6-a987-da1779114f68",
    ["ui-icons/skills/skill_30_noBG.png"] = "aee246c9-3b2d-423b-b015-d27c83bf971e",
    ["ui-icons/skills/skill_31.png"] = "4bc92d0d-87d6-456c-90c6-c43fa7626865",
    ["ui-icons/skills/skill_310_noBG.png"] = "99d351f9-ac78-4a60-89e7-56f142033a21",
    ["ui-icons/skills/skill_311_noBG.png"] = "c00fac18-8514-4cab-82d0-52f330d061ed",
    ["ui-icons/skills/skill_312_noBG.png"] = "24593715-f915-469d-ab77-a6d47fd75fe0",
    ["ui-icons/skills/skill_313_noBG.png"] = "8e68a202-f529-4509-834b-19a0776cb6f9",
    ["ui-icons/skills/skill_314_noBG.png"] = "1fd6691b-d6d4-41de-8e9a-573a362ca140",
    ["ui-icons/skills/skill_315_noBG.png"] = "94c2948b-83ec-4215-a46c-576107b987a5",
    ["ui-icons/skills/skill_316_noBG.png"] = "86623d73-34f4-406e-8f3a-d13390b8ec9b",
    ["ui-icons/skills/skill_317_noBG.png"] = "caad2575-c12c-4103-9da3-8c21834cb75f",
    ["ui-icons/skills/skill_318_noBG.png"] = "f0222501-e1c7-499f-a218-b6c612617a17",
    ["ui-icons/skills/skill_319_noBG.png"] = "3f7716b7-1c1d-45d9-87d1-175c3696e03e",
    ["ui-icons/skills/skill_31_noBG.png"] = "85e822ac-cd4e-4407-818e-1819cc7ac85d",
    ["ui-icons/skills/skill_32.png"] = "2c90a127-e7ff-4217-9e45-216c53a7d7f9",
    ["ui-icons/skills/skill_320_noBG.png"] = "f196de19-bc79-4803-a253-c8fa8ded3665",
    ["ui-icons/skills/skill_322_noBG.png"] = "4a0cbcd4-fa72-46a0-8cc8-9e67e776ecd4",
    ["ui-icons/skills/skill_325_noBG.png"] = "d8ab71ed-764e-41af-9e21-efda6d9278f4",
    ["ui-icons/skills/skill_326.png"] = "ffaa78ea-44c0-452d-b6c6-0a8e1e8b6b9f",
    ["ui-icons/skills/skill_326_noBG.png"] = "c3d47e7a-310d-44d7-808d-3d0334a03361",
    ["ui-icons/skills/skill_327_noBG.png"] = "901d40da-0263-422f-aeca-264c6d0f07bb",
    ["ui-icons/skills/skill_328_noBG.png"] = "f8c699b4-95fe-4c8c-b164-62dcd0e4166c",
    ["ui-icons/skills/skill_329_noBG.png"] = "af863780-9c70-4a01-8ae1-fd47d48dcd22",
    ["ui-icons/skills/skill_32_noBG.png"] = "f8324c3b-63dd-4658-b12e-0b5a8ce828a1",
    ["ui-icons/skills/skill_33.png"] = "9371061f-1194-4ae2-a3f3-9fa36633b3c2",
    ["ui-icons/skills/skill_330_noBG.png"] = "b05859ee-59ce-43bc-876b-6ed82d36e42b",
    ["ui-icons/skills/skill_331_noBG.png"] = "f770e2ac-e6bd-4f87-8ef4-d608912c6bb8",
    ["ui-icons/skills/skill_332_noBG.png"] = "ce33051d-ce66-44b6-8c49-33bff7d39077",
    ["ui-icons/skills/skill_333_noBG.png"] = "062d4b0c-ecd7-4449-9a8d-490d95fde47d",
    ["ui-icons/skills/skill_334_noBG.png"] = "e8d88082-74cd-42a1-b7b9-d5606512fdce",
    ["ui-icons/skills/skill_335_noBG.png"] = "3382fa43-2324-4db9-976d-690f4c1b3b64",
    ["ui-icons/skills/skill_336_noBG.png"] = "ddc00511-5b1d-4703-ab0f-1c1306e0ad1c",
    ["ui-icons/skills/skill_337_noBG.png"] = "6ff890ce-d463-4eeb-a27c-4e146aecfa9e",
    ["ui-icons/skills/skill_338_noBG.png"] = "97600cdd-996d-46d9-a835-f7e0f38cf63d",
    ["ui-icons/skills/skill_339_noBG.png"] = "7733e956-3d3f-4bf7-90dd-83f1252c266c",
    ["ui-icons/skills/skill_33_noBG.png"] = "00075649-c1a1-4cad-8f65-b0111275f918",
    ["ui-icons/skills/skill_34.png"] = "36315831-d632-4f8c-af00-ce0429c61d19",
    ["ui-icons/skills/skill_340_noBG.png"] = "4bb125e3-bea2-4f89-a8ca-6bd9456e484d",
    ["ui-icons/skills/skill_341_noBG.png"] = "556248d6-38a2-428d-94ef-6b84efdca0c1",
    ["ui-icons/skills/skill_342_noBG.png"] = "d61ad3a5-a0c6-430a-b7a5-b238b86686cd",
    ["ui-icons/skills/skill_343_noBG.png"] = "44151ad0-b333-4c09-a545-6b72de518a09",
    ["ui-icons/skills/skill_344_noBG.png"] = "af70f4dd-54f9-4e98-a92b-71bccf51b50d",
    ["ui-icons/skills/skill_345_noBG.png"] = "1adbe8cc-3689-472c-9ede-0c76105e3332",
    ["ui-icons/skills/skill_346_noBG.png"] = "1e9a9135-fc91-4916-85b0-f6c864d0a20e",
    ["ui-icons/skills/skill_347_noBG.png"] = "ac56402a-17d0-4b2e-b200-486965268a0e",
    ["ui-icons/skills/skill_348_noBG.png"] = "86e79e72-31c9-46ee-9a76-0ee5031b9068",
    ["ui-icons/skills/skill_349_noBG.png"] = "170c7d4e-6333-4eb3-8f04-5b7a92f68f66",
    ["ui-icons/skills/skill_34_noBG.png"] = "2c171b44-efb0-4cad-9cc9-b2be4d276f1f",
    ["ui-icons/skills/skill_35.png"] = "48591ad9-5810-4953-8dfe-2d30ef1b340b",
    ["ui-icons/skills/skill_350_noBG.png"] = "ef013cc9-6f1d-4099-947c-8d016b60566c",
    ["ui-icons/skills/skill_351_noBG.png"] = "9f681862-98ef-4591-8d99-a1bee9616dc3",
    ["ui-icons/skills/skill_352_noBG.png"] = "af60d08d-fbab-4a41-a279-78b1d7494d36",
    ["ui-icons/skills/skill_353_noBG.png"] = "beff3a48-144e-406a-88af-8d229083eb5f",
    ["ui-icons/skills/skill_354_noBG.png"] = "93b7a2cb-a093-4cd0-9102-43da61279603",
    ["ui-icons/skills/skill_355_noBG.png"] = "f326ce2a-96a7-4963-8c9c-f9f919677da8",
    ["ui-icons/skills/skill_356_noBG.png"] = "cf106566-e0bc-4324-a9a7-96a0497295b2",
    ["ui-icons/skills/skill_357_noBG.png"] = "3bc5752b-5e70-4184-b67d-9923682451cc",
    ["ui-icons/skills/skill_358_noBG.png"] = "7170e623-f80a-4aed-8b4d-df7de94fbb58",
    ["ui-icons/skills/skill_359_noBG.png"] = "abaeffbb-d253-418a-8dbb-4dbca8ee746b",
    ["ui-icons/skills/skill_35_noBG.png"] = "51485fe7-7ada-4543-a5a4-6bca7526f306",
    ["ui-icons/skills/skill_36.png"] = "798575d0-f47a-4a5f-96e8-7010971eeb87",
    ["ui-icons/skills/skill_360_noBG.png"] = "a9c2f341-5a9e-4db4-a11c-f58d044d5a03",
    ["ui-icons/skills/skill_361_noBG.png"] = "a18659c6-f227-4606-a503-670d3c4ad2a9",
    ["ui-icons/skills/skill_362_noBG.png"] = "fa265807-1993-4763-88af-ec29eae11e1c",
    ["ui-icons/skills/skill_363_noBG.png"] = "f0c7c728-0d40-4ad6-a5a7-c1f9c2a707bc",
    ["ui-icons/skills/skill_364_noBG.png"] = "c5daf682-0829-400e-9ba1-33f7fa339166",
    ["ui-icons/skills/skill_365_noBG.png"] = "5bb78fbd-ff98-47aa-80b1-0d2b85ccccd2",
    ["ui-icons/skills/skill_366_noBG.png"] = "28c3e622-2024-49de-a90f-a5cc556473ac",
    ["ui-icons/skills/skill_367.png"] = "ce5e40ab-fdb9-4f5c-88f3-c7ec7ee9cf18",
    ["ui-icons/skills/skill_367_noBG.png"] = "5aa498d4-652f-4fe2-becc-bb7002193e85",
    ["ui-icons/skills/skill_368_noBG.png"] = "ca3f46ff-1cf2-4282-8b3d-5c67a0cbc985",
    ["ui-icons/skills/skill_369_noBG.png"] = "0f1860d5-1783-4f9f-b85d-5a8511b0e708",
    ["ui-icons/skills/skill_36_noBG.png"] = "501664d8-f7b9-4590-991f-4d8c145f498a",
    ["ui-icons/skills/skill_37.png"] = "7140d8e5-07ec-4625-b584-4db68478a2cd",
    ["ui-icons/skills/skill_370_noBG.png"] = "ee20f692-bc56-466d-a9bb-beb190a887c4",
    ["ui-icons/skills/skill_371_noBG.png"] = "314d874f-1302-4b42-9e7b-cc709f5ede34",
    ["ui-icons/skills/skill_372_noBG.png"] = "5c7bce52-c7f7-4257-a6bf-fc52137b8b70",
    ["ui-icons/skills/skill_373_noBG.png"] = "d8ccc005-a0ec-4ece-8870-54fceb65a86d",
    ["ui-icons/skills/skill_374_noBG.png"] = "3a44797c-9edd-4dbc-a069-704242f55a45",
    ["ui-icons/skills/skill_375_noBG.png"] = "d2df862c-e6ef-442c-a54d-256e0d23485a",
    ["ui-icons/skills/skill_376_noBG.png"] = "76d2d85c-1626-455c-b3f9-828fdf4a5c87",
    ["ui-icons/skills/skill_377_noBG.png"] = "d55fbf54-807f-48a2-9068-35d9a9f3b6c7",
    ["ui-icons/skills/skill_378.png"] = "9a7e215e-20ce-47a5-bb6c-3f00447148a4",
    ["ui-icons/skills/skill_378_noBG.png"] = "a5a8eff8-7df9-413d-a595-6046a4c457a4",
    ["ui-icons/skills/skill_379.png"] = "92cf2d42-f3e9-4fad-9302-dd97e1692ac5",
    ["ui-icons/skills/skill_379_noBG.png"] = "006d016b-1cbe-490d-8fe4-8ba7d6c2fc21",
    ["ui-icons/skills/skill_37_noBG.png"] = "eefc419c-4731-42e8-a73e-5caaaeb15281",
    ["ui-icons/skills/skill_38.png"] = "928f6fa3-30ba-41d5-bea9-01087976d12f",
    ["ui-icons/skills/skill_380_noBG.png"] = "49483c8c-430b-4af3-a7ca-2edde2b5a2d7",
    ["ui-icons/skills/skill_381_noBG.png"] = "58a02b97-1939-4ac8-93af-842760533872",
    ["ui-icons/skills/skill_382_noBG.png"] = "4fededea-8adb-4663-b92f-d442b15de1f3",
    ["ui-icons/skills/skill_383_noBG.png"] = "1f5ca678-1724-4435-bc15-699dd3424995",
    ["ui-icons/skills/skill_384_noBG.png"] = "003f2ba2-5853-4516-8091-963069d64636",
    ["ui-icons/skills/skill_385_noBG.png"] = "0380ae80-2894-4601-a955-76dd108bf50c",
    ["ui-icons/skills/skill_386_noBG.png"] = "40b40d58-ab7f-4f50-bf0d-16f1fe993aaa",
    ["ui-icons/skills/skill_387_noBG.png"] = "8aa9fdc0-fb73-49d8-8378-3dfeff1594a4",
    ["ui-icons/skills/skill_388_noBG.png"] = "6ab1c237-3db8-4807-b298-bc37609787bb",
    ["ui-icons/skills/skill_389_noBG.png"] = "da35da1f-5548-48b3-b0a8-be9508d0509a",
    ["ui-icons/skills/skill_38_noBG.png"] = "2eba2095-c752-4351-8169-3aa007aca040",
    ["ui-icons/skills/skill_39.png"] = "51782759-5bc0-4362-bbca-ce57afa29660",
    ["ui-icons/skills/skill_390_noBG.png"] = "c4f527b0-4ed9-4248-8507-d6d16f8efe97",
    ["ui-icons/skills/skill_391_noBG.png"] = "7fb8524f-6bf5-41a1-826f-9ae23b24b9ef",
    ["ui-icons/skills/skill_392_noBG.png"] = "223155d6-bfe4-4bd3-819c-bfda3e1b0366",
    ["ui-icons/skills/skill_393_noBG.png"] = "731cb92e-0ab0-4a44-a4f6-d538532e1978",
    ["ui-icons/skills/skill_394_noBG.png"] = "71bc9873-17e9-48c4-b44c-df3c8f50ca4c",
    ["ui-icons/skills/skill_395_noBG.png"] = "294d986a-88a2-406b-9806-6c7a8b9ff8d3",
    ["ui-icons/skills/skill_396_noBG.png"] = "70e6c6a3-71f9-4446-babf-f17b4d11ec03",
    ["ui-icons/skills/skill_397_noBG.png"] = "91d4e6ec-94d4-405c-9a2a-10c874699750",
    ["ui-icons/skills/skill_398_noBG.png"] = "0ccd24c0-8e98-4393-9df8-f3efa010e8d6",
    ["ui-icons/skills/skill_399_noBG.png"] = "34bad6a7-67ff-4777-9418-f457f9f12d56",
    ["ui-icons/skills/skill_39_noBG.png"] = "e3785de9-9f97-4868-a224-e687bd95814a",
    ["ui-icons/skills/skill_3_noBG.png"] = "1d912f94-25e9-41b9-ac2c-afa9f1bb0344",
    ["ui-icons/skills/skill_4.png"] = "9b92a804-95ba-4203-9df0-2094853bab92",
    ["ui-icons/skills/skill_40.png"] = "3b09afa2-5791-43ba-82ae-004fccdf2a09",
    ["ui-icons/skills/skill_400_noBG.png"] = "c6f27794-7409-4aaa-b314-b8f0c4a43097",
    ["ui-icons/skills/skill_401_noBG.png"] = "f1b3d15c-8a35-491d-a671-30e57dccaa61",
    ["ui-icons/skills/skill_402_noBG.png"] = "bbb7537a-5e68-45ac-9de5-7ea7e5945b8a",
    ["ui-icons/skills/skill_403.png"] = "c06e23f6-8f2a-4051-babf-8a13f952d6d6",
    ["ui-icons/skills/skill_404_noBG.png"] = "55b95647-aa04-4348-8b8e-48fdd02a17af",
    ["ui-icons/skills/skill_405_noBG.png"] = "a9f51e50-d8ee-455e-8764-31cd2580ddc3",
    ["ui-icons/skills/skill_406_noBG.png"] = "b3d98c53-a0cb-48fd-9159-146216c27e4d",
    ["ui-icons/skills/skill_407_noBG.png"] = "51454ef8-a013-4d26-9809-236047dc7cc6",
    ["ui-icons/skills/skill_408_noBG.png"] = "86908320-a77f-4d5e-829c-ebcd1af27229",
    ["ui-icons/skills/skill_409_noBG.png"] = "f8849f44-8498-4872-aeb1-02956dbb61ef",
    ["ui-icons/skills/skill_40_noBG.png"] = "24fdd4c1-84d8-4c1a-908e-ae68f108f93e",
    ["ui-icons/skills/skill_41.png"] = "9547c348-9cf2-4c19-8789-72ee3f3da88f",
    ["ui-icons/skills/skill_410_noBG.png"] = "496aa114-fa49-40bc-ae8c-607e84c03da9",
    ["ui-icons/skills/skill_411_noBG.png"] = "963c0332-e281-4e37-b22f-12f6264921b3",
    ["ui-icons/skills/skill_412_noBG.png"] = "2ac12adf-0648-438b-8e51-227a5594ad70",
    ["ui-icons/skills/skill_415_noBG.png"] = "88990524-6cbb-4d7d-8be9-cbe3a2475926",
    ["ui-icons/skills/skill_416_noBG.png"] = "5f95fd17-bf44-4f0b-963b-579acaf0a8c2",
    ["ui-icons/skills/skill_417_noBG.png"] = "23864e2b-af2f-4e83-8803-3c724c804b28",
    ["ui-icons/skills/skill_418_noBG.png"] = "0c0c7725-2f2b-44a0-98d8-f3b78309b368",
    ["ui-icons/skills/skill_419_noBG.png"] = "b144d190-d203-4bc6-b63c-68c4ffcd0427",
    ["ui-icons/skills/skill_41_noBG.png"] = "849868d8-adec-4c58-87dc-54f70264a784",
    ["ui-icons/skills/skill_42.png"] = "042e0919-52b0-4e8a-a36b-a5bd88639819",
    ["ui-icons/skills/skill_420_noBG.png"] = "ec4447c3-b89a-4ae0-9b02-37d21993b497",
    ["ui-icons/skills/skill_421_noBG.png"] = "4944e1db-af06-466e-ad41-4617e3eb0c67",
    ["ui-icons/skills/skill_422_noBG.png"] = "46664da3-a31e-447f-89e0-e4315fda9f5f",
    ["ui-icons/skills/skill_423_noBG.png"] = "318277e5-41c1-459d-ab6c-ac454750f122",
    ["ui-icons/skills/skill_424_noBG.png"] = "ee4ce9e2-b173-4888-b463-63cb22de80c6",
    ["ui-icons/skills/skill_425_noBG.png"] = "d0376f25-9018-418a-940f-ed2b743de1b8",
    ["ui-icons/skills/skill_426_noBG.png"] = "68d69492-312a-44bc-95fc-c6bbc050f5c4",
    ["ui-icons/skills/skill_427.png"] = "25e24c3d-8022-4795-b6d1-38633e6a7f50",
    ["ui-icons/skills/skill_427_noBG.png"] = "f86cf11a-a360-4823-86a6-22124bcc9781",
    ["ui-icons/skills/skill_428_noBG.png"] = "7d8e3de5-e389-4e61-9598-ec8598540a18",
    ["ui-icons/skills/skill_429_noBG.png"] = "904c7953-5721-41a6-bd16-0ab67292f877",
    ["ui-icons/skills/skill_42_noBG.png"] = "46770786-62b2-4877-9ae5-40ddb7116f4d",
    ["ui-icons/skills/skill_43.png"] = "5f91922e-e83d-459c-9dac-f2672c1a233e",
    ["ui-icons/skills/skill_430_noBG.png"] = "b910b493-d4c2-46c4-b41d-d29574f9d323",
    ["ui-icons/skills/skill_432.png"] = "78d46b98-3717-48c4-a429-b400088dbd84",
    ["ui-icons/skills/skill_432_noBG.png"] = "e6e47c64-2eb3-4c85-840d-56bf0ed1e215",
    ["ui-icons/skills/skill_434.png"] = "f7f2e0fa-1286-4e95-8e39-098151283af2",
    ["ui-icons/skills/skill_434_noBG.png"] = "053227a2-ca55-4c80-990c-5d10abb73ef9",
    ["ui-icons/skills/skill_435_noBG.png"] = "ce49ca38-463e-47be-bddd-42ce95f656ce",
    ["ui-icons/skills/skill_436_noBG.png"] = "5c6cdce4-5d3d-41dc-8f51-50660905f343",
    ["ui-icons/skills/skill_437.png"] = "7a655e5c-2d0c-4d3d-811f-67a4533409cb",
    ["ui-icons/skills/skill_437_noBG.png"] = "b1636dfe-292d-4dbb-bad1-3d03890f1150",
    ["ui-icons/skills/skill_438_noBG.png"] = "d14e143d-cec1-46e0-b94a-d25155a1f723",
    ["ui-icons/skills/skill_439_noBG.png"] = "8b541840-9058-4be0-acd0-c73233a5e582",
    ["ui-icons/skills/skill_43_noBG.png"] = "bc856b32-c3e9-48e2-ade4-0a23eb524891",
    ["ui-icons/skills/skill_44.png"] = "b990ddbb-e09f-4f39-98b5-f283adae2dfb",
    ["ui-icons/skills/skill_440_noBG.png"] = "798ba518-e344-45b6-be8c-4d54d9c16243",
    ["ui-icons/skills/skill_441_noBG.png"] = "806e7d7d-ce62-4d50-9e4d-5e4aac2d818d",
    ["ui-icons/skills/skill_442_noBG.png"] = "6410c878-aa94-4ac6-9af1-c96c4a1f62a9",
    ["ui-icons/skills/skill_443_noBG.png"] = "20964351-af82-45cd-9dc5-5487d5f65b1b",
    ["ui-icons/skills/skill_444_noBG.png"] = "86f978b6-f09a-4af1-ba5c-1d0d2e5f61fa",
    ["ui-icons/skills/skill_445_noBG.png"] = "835037bc-36d1-47f2-a56e-f494d128319f",
    ["ui-icons/skills/skill_446_noBG.png"] = "07f4e36f-6245-49d5-b078-73ec49f487c1",
    ["ui-icons/skills/skill_447_noBG.png"] = "6bdf8812-20fb-4790-b0ea-444acd3d0621",
    ["ui-icons/skills/skill_448_noBG.png"] = "6d4de7fc-a8a9-4aaa-b10d-c8d0f9c5962c",
    ["ui-icons/skills/skill_449_noBG.png"] = "1727a391-41cf-4896-b524-d6cbfa267fb8",
    ["ui-icons/skills/skill_44_noBG.png"] = "4af0910b-72ff-4a1b-bb93-c1be5d17c11d",
    ["ui-icons/skills/skill_45.png"] = "f09f0e4a-e7f0-4289-8e2f-449d72938051",
    ["ui-icons/skills/skill_450_noBG.png"] = "b6caecb2-fbb9-46ee-9250-5fb92a793feb",
    ["ui-icons/skills/skill_451.png"] = "f7670a58-bb46-420e-95ea-f2f0c2fa679e",
    ["ui-icons/skills/skill_451_noBG.png"] = "fe456f4a-10fb-41b1-bd29-7eecdd61d9eb",
    ["ui-icons/skills/skill_452_noBG.png"] = "11ac67a0-f661-432e-aa4b-af6a69dec3d1",
    ["ui-icons/skills/skill_453_noBG.png"] = "42471384-7f9a-4085-9a8f-d0d8cdb742db",
    ["ui-icons/skills/skill_454_noBG.png"] = "f4cde26c-4ed1-4d89-b77c-2cd62b7171fd",
    ["ui-icons/skills/skill_455_noBG.png"] = "4ebc71e6-7185-4278-abb7-d7675d7c3d84",
    ["ui-icons/skills/skill_456_noBG.png"] = "fe2c8b4a-179a-4b17-b19b-88c480eaa62f",
    ["ui-icons/skills/skill_457.png"] = "659a59ca-bda1-4264-934c-e898a4c2ad3a",
    ["ui-icons/skills/skill_457_noBG.png"] = "a2a1431b-07cd-4222-8a83-89a9362bb0c7",
    ["ui-icons/skills/skill_458_noBG.png"] = "9b1ac807-a8eb-4d4a-b975-1697341f3e63",
    ["ui-icons/skills/skill_459_noBG.png"] = "66835398-dbc4-4bf6-81e8-8e2f46581c52",
    ["ui-icons/skills/skill_45_noBG.png"] = "b9e47bcb-e55c-453a-a874-54aada00f152",
    ["ui-icons/skills/skill_46.png"] = "c334bed0-0779-45d0-bb93-6087fcadb13e",
    ["ui-icons/skills/skill_460_noBG.png"] = "a20eb428-f466-4e47-83c2-6c63758e9012",
    ["ui-icons/skills/skill_461_noBG.png"] = "403401da-e539-4311-9b02-504bb0af1926",
    ["ui-icons/skills/skill_462_noBG.png"] = "e7d6e159-f077-454e-b531-d288721681b3",
    ["ui-icons/skills/skill_463_noBG.png"] = "1a685851-e333-4f9e-a9ca-3e111990a6a7",
    ["ui-icons/skills/skill_464_noBG.png"] = "79638ce4-ab88-4d4b-babb-6e04d9e992b0",
    ["ui-icons/skills/skill_465_noBG.png"] = "d15ce39b-3dbb-49cc-bfc2-42b8d95f5493",
    ["ui-icons/skills/skill_466_noBG.png"] = "e7a21844-a320-459f-b5bc-58657badc4a0",
    ["ui-icons/skills/skill_467_noBG.png"] = "336e4d5d-c858-47b6-8dcd-98934055945c",
    ["ui-icons/skills/skill_468_noBG.png"] = "10046a72-0ee4-4889-8382-fee9cf5ed397",
    ["ui-icons/skills/skill_469_noBG.png"] = "050b1eaf-254b-492a-aafb-0ec33715301a",
    ["ui-icons/skills/skill_46_noBG.png"] = "d7f3dc68-86b8-46f7-abdd-a83ed9c560e4",
    ["ui-icons/skills/skill_47.png"] = "0ecc6572-c45b-41eb-8563-2f092c02af84",
    ["ui-icons/skills/skill_470_noBG.png"] = "3e752396-3414-4aa4-92b8-1850830a79e8",
    ["ui-icons/skills/skill_471_noBG.png"] = "919b81c6-1045-4769-a6ed-cbc51daac7dc",
    ["ui-icons/skills/skill_472_noBG.png"] = "738e8ec0-ff60-4a97-8851-a833c386625d",
    ["ui-icons/skills/skill_473_noBG.png"] = "ffa4919c-12d5-4c12-aefe-c28d5c8720d5",
    ["ui-icons/skills/skill_474_noBG.png"] = "60e98781-98f1-4dcf-bcd5-c6ca9b63b264",
    ["ui-icons/skills/skill_475_noBG.png"] = "5cd05f8c-177f-4ea7-8781-cb3d05b0901b",
    ["ui-icons/skills/skill_476_noBG.png"] = "85b43fed-6cc5-4290-a17a-7b9f39cbd2d9",
    ["ui-icons/skills/skill_477_noBG.png"] = "bb655692-c4ab-4f74-b872-8c677f8bbbe1",
    ["ui-icons/skills/skill_478_noBG.png"] = "cdc0622d-e45f-44c3-ab62-1140dbce9649",
    ["ui-icons/skills/skill_479_noBG.png"] = "74fd1e55-ce2f-4424-8049-f9b57abb6b21",
    ["ui-icons/skills/skill_47_noBG.png"] = "c85103e5-51f8-40ed-ad3f-364337e07c04",
    ["ui-icons/skills/skill_48.png"] = "11cef164-650b-4561-9efc-098536313e13",
    ["ui-icons/skills/skill_480_noBG.png"] = "52d15fae-cd5e-4d3c-9c26-a2001af263d3",
    ["ui-icons/skills/skill_481_noBG.png"] = "8979d7b9-9377-4c08-9a79-9d88d2f03b99",
    ["ui-icons/skills/skill_482_noBG.png"] = "42d945c1-675f-4fef-b8db-abe98ff07a63",
    ["ui-icons/skills/skill_483_noBG.png"] = "d31b5410-7839-4ea8-aff1-ad9e44934dc8",
    ["ui-icons/skills/skill_484_noBG.png"] = "322ea855-6d85-453c-9c77-3b4c6cfb3f73",
    ["ui-icons/skills/skill_485_noBG.png"] = "3c4a7459-d434-4574-9534-54814fde68e6",
    ["ui-icons/skills/skill_486_noBG.png"] = "9598a963-504b-45ca-a298-4af21db35b43",
    ["ui-icons/skills/skill_487_noBG.png"] = "14774ed7-149a-42b7-8442-38dfcc7846cb",
    ["ui-icons/skills/skill_488.png"] = "1172202d-407a-4088-993b-f64c7525a410",
    ["ui-icons/skills/skill_488_noBG.png"] = "ffd8efb4-4cb8-46c6-af7c-802ae027b95b",
    ["ui-icons/skills/skill_489_noBG.png"] = "e75757d7-de7f-4b74-a785-c52a636f3e06",
    ["ui-icons/skills/skill_48_noBG.png"] = "45ec161a-ddd3-4b3f-a203-8009b358cad5",
    ["ui-icons/skills/skill_49.png"] = "76ad28e5-c389-413b-9e95-432d3eb3d816",
    ["ui-icons/skills/skill_490_noBG.png"] = "52371adb-c02b-4815-a0db-811608100b0f",
    ["ui-icons/skills/skill_491_noBG.png"] = "404b37eb-10e2-4f0f-822c-22b83cbf85a9",
    ["ui-icons/skills/skill_492_noBG.png"] = "6a2581f8-b5e0-4a81-86cd-f619b459866f",
    ["ui-icons/skills/skill_493_noBG.png"] = "761ab66c-3a07-4385-88e9-3bbbc9d7086a",
    ["ui-icons/skills/skill_494_noBG.png"] = "cf1b40e7-3e69-4a26-a0aa-da53b62da47c",
    ["ui-icons/skills/skill_495_noBG.png"] = "4c50f70b-46a6-4d5f-85b5-be94fc98afa2",
    ["ui-icons/skills/skill_496_noBG.png"] = "9d03daa2-90dd-465f-81a0-a2bda49175a8",
    ["ui-icons/skills/skill_497_noBG.png"] = "abcb16c1-e8b2-4235-873b-d789966d94ec",
    ["ui-icons/skills/skill_498_noBG.png"] = "102eb959-6590-4a5a-bc9e-fcc457bcc824",
    ["ui-icons/skills/skill_499_noBG.png"] = "ad6e1252-9f32-4e08-ab4a-2732c755d74b",
    ["ui-icons/skills/skill_49_noBG.png"] = "9193b7aa-7fe6-4b07-b4a7-31f14934b13d",
    ["ui-icons/skills/skill_4_noBG.png"] = "827262ec-3ba1-4096-b723-4196da4c8aed",
    ["ui-icons/skills/skill_5.png"] = "8d363882-a964-467b-a411-9fb1f0c7c03d",
    ["ui-icons/skills/skill_50.png"] = "00bfaf45-3bd6-4add-be61-6dd74b69166e",
    ["ui-icons/skills/skill_50_noBG.png"] = "2cfac3c7-81ea-4227-a0da-fcfa1e84b690",
    ["ui-icons/skills/skill_51.png"] = "f3001129-f11b-4031-a2fb-924038d0aa72",
    ["ui-icons/skills/skill_51_noBG.png"] = "718bd579-1831-425b-8b81-7d2d875af730",
    ["ui-icons/skills/skill_52.png"] = "669c3b6d-0d71-491f-b10f-4b551b996777",
    ["ui-icons/skills/skill_52_noBG.png"] = "f96508d7-675d-484a-b529-f778777d575c",
    ["ui-icons/skills/skill_53.png"] = "790da84b-4276-45b7-b4cf-6b8111d3f42d",
    ["ui-icons/skills/skill_53_noBG.png"] = "b3bad172-def8-4dd7-86ab-98c36707813f",
    ["ui-icons/skills/skill_54.png"] = "789acaea-cbcf-454c-93f9-f12574200f1b",
    ["ui-icons/skills/skill_54_noBG.png"] = "118e4054-adcd-4aca-bce3-dce240ce16e3",
    ["ui-icons/skills/skill_55.png"] = "c845ee3c-b001-4750-89fd-26573a185294",
    ["ui-icons/skills/skill_55_noBG.png"] = "a5e5ba2c-0946-472b-a725-d0ff732de6a2",
    ["ui-icons/skills/skill_56.png"] = "ae3647ff-fa6f-4e00-bc22-3b4d25395b23",
    ["ui-icons/skills/skill_57.png"] = "967891b3-bc20-4bab-a308-4d75d09c28eb",
    ["ui-icons/skills/skill_57_noBG.png"] = "a3fd3a56-e9e9-4165-b474-04126050254f",
    ["ui-icons/skills/skill_58.png"] = "138fa245-427b-47b7-9c26-61a5a3b5de83",
    ["ui-icons/skills/skill_58_noBG.png"] = "6d22f6eb-9bc6-459c-a461-d7eaae220f7c",
    ["ui-icons/skills/skill_59.png"] = "74740427-452b-483b-b8ce-e62490effa9f",
    ["ui-icons/skills/skill_59_noBG.png"] = "7d9ffbde-9fcd-46c1-8da6-e10034c59ffe",
    ["ui-icons/skills/skill_5_noBG.png"] = "b698f4e7-5213-492b-9b3b-c7d4694c7dfe",
    ["ui-icons/skills/skill_6.png"] = "b8aee476-1120-47fa-80a8-44de8c0c32e7",
    ["ui-icons/skills/skill_60.png"] = "8acc343c-8014-49d2-9dd6-a38284ede1f0",
    ["ui-icons/skills/skill_60_noBG.png"] = "e41f0872-2575-4be5-827e-8f9b7011b357",
    ["ui-icons/skills/skill_61.png"] = "6f2ee87e-aeb1-494a-807f-781757cafe27",
    ["ui-icons/skills/skill_61_noBG.png"] = "bf98a54c-69ac-4df2-bb9a-03fb098f4674",
    ["ui-icons/skills/skill_62.png"] = "6a80abfd-dc8a-4556-810e-78e7e4471463",
    ["ui-icons/skills/skill_62_noBG.png"] = "3e0f5736-6453-4795-bf1b-1141fe3613a3",
    ["ui-icons/skills/skill_63.png"] = "88cfdef3-49e6-4fc2-95b1-f06f38a22412",
    ["ui-icons/skills/skill_63_noBG.png"] = "0a809359-fddc-44ed-beee-8e23b3af54ad",
    ["ui-icons/skills/skill_64.png"] = "b69459b6-c7b1-47db-95e9-77aec0dc7c95",
    ["ui-icons/skills/skill_64_noBG.png"] = "f2521882-0fe6-4e8c-b031-db49ac4cbc20",
    ["ui-icons/skills/skill_65.png"] = "7e6a68f6-354d-4458-85e9-b86f51d9c38d",
    ["ui-icons/skills/skill_65_noBG.png"] = "242eb406-3e1d-44d9-975c-b5fb6c3eb168",
    ["ui-icons/skills/skill_66.png"] = "7f8df890-a445-4c65-8f18-ff70880aa9e0",
    ["ui-icons/skills/skill_66_noBG.png"] = "a08c3d53-cb05-4972-9fba-ffe87f5b5be9",
    ["ui-icons/skills/skill_67.png"] = "bbd06170-5c19-4e56-ae09-12d9c27cee82",
    ["ui-icons/skills/skill_67_noBG.png"] = "6c31d9c2-65c0-466a-a24b-39815daacbcf",
    ["ui-icons/skills/skill_68.png"] = "d826fff5-4dc9-44d6-bf53-0803125193f6",
    ["ui-icons/skills/skill_68_noBG.png"] = "2d7c7b89-79ad-4f20-8fa5-77296b4650a9",
    ["ui-icons/skills/skill_69.png"] = "cf2faee5-917a-4d73-953d-6685fd4fd89c",
    ["ui-icons/skills/skill_69_noBG.png"] = "444209fb-220c-47ad-8b68-891b0ed2cb10",
    ["ui-icons/skills/skill_6_noBG.png"] = "c3dba1b5-34ea-45e8-9bda-310c426bc6e1",
    ["ui-icons/skills/skill_7.png"] = "b559e2eb-9446-42b8-8d53-b90db4063a03",
    ["ui-icons/skills/skill_70.png"] = "50d5a30f-d5f5-45b3-a8f1-f0b048f5b39e",
    ["ui-icons/skills/skill_70_noBG.png"] = "c02f5a77-f890-4f38-9aa9-74bc21b327f6",
    ["ui-icons/skills/skill_71.png"] = "14c44d56-efb2-4f99-b932-89cf20c0f89e",
    ["ui-icons/skills/skill_71_noBG.png"] = "bfafb117-73a9-42f7-8c77-606342f029cb",
    ["ui-icons/skills/skill_72.png"] = "dceb5fd2-621d-4537-b09f-e0a4f36c56ff",
    ["ui-icons/skills/skill_72_noBG.png"] = "d34d75a1-50e9-4cf0-b3c3-0e3e2c8d2fa6",
    ["ui-icons/skills/skill_73.png"] = "077132ad-6f10-44a0-ac41-cc022e811912",
    ["ui-icons/skills/skill_73_noBG.png"] = "6f2b2f76-1031-453e-af5e-07d01a4dbbac",
    ["ui-icons/skills/skill_74.png"] = "7afe5f94-d836-4cb2-9f56-1141970654a7",
    ["ui-icons/skills/skill_74_noBG.png"] = "239880fa-27d0-4168-bde9-c4291f47dd5f",
    ["ui-icons/skills/skill_75.png"] = "9b7f9236-a043-48cc-be43-3a8b4737aadd",
    ["ui-icons/skills/skill_75_noBG.png"] = "8a2718e6-9a8c-437e-886b-810da1a694ea",
    ["ui-icons/skills/skill_76.png"] = "5bf8f7fe-ad36-4375-9330-de5527e38245",
    ["ui-icons/skills/skill_76_noBG.png"] = "92b2b114-d1a9-48da-bc72-d7b561b5432f",
    ["ui-icons/skills/skill_77.png"] = "d52c9094-5bc6-4853-86b4-5d2b41986392",
    ["ui-icons/skills/skill_77_noBG.png"] = "6b962c5d-df65-47ca-a658-78821a9f2509",
    ["ui-icons/skills/skill_78.png"] = "fde82248-c26c-4ab6-a23d-4e32c8174e8e",
    ["ui-icons/skills/skill_78_noBG.png"] = "45dbe4f2-e98c-4dc6-b761-366c52f3e8d8",
    ["ui-icons/skills/skill_79.png"] = "64a9f89a-b684-44da-8f9a-484b0340d633",
    ["ui-icons/skills/skill_79_noBG.png"] = "ca6fd526-8885-44f7-aaba-2bb02e332351",
    ["ui-icons/skills/skill_7_noBG.png"] = "2872a26f-907b-48d5-90cb-94e87ab60dbd",
    ["ui-icons/skills/skill_8.png"] = "5f72acc5-2229-470e-b0a0-2599103fb4f1",
    ["ui-icons/skills/skill_80.png"] = "ddf655ee-1a81-47c8-ac8e-54b6beeeb9f9",
    ["ui-icons/skills/skill_80_noBG.png"] = "388dc612-1d02-462f-8022-b96f4ea749ca",
    ["ui-icons/skills/skill_81.png"] = "2e4023c4-1181-419d-a28a-fc803183eeb6",
    ["ui-icons/skills/skill_81_noBG.png"] = "200dc5b2-64dd-437a-8779-a8fba47bb0a6",
    ["ui-icons/skills/skill_82.png"] = "9a3ae2b9-9d2d-48ee-8708-278dbda19e6e",
    ["ui-icons/skills/skill_82_noBG.png"] = "fcea21af-2259-4d43-8c11-b11ebe112bc0",
    ["ui-icons/skills/skill_83.png"] = "3f4d9f5c-cca9-44c0-8847-e24743c721d3",
    ["ui-icons/skills/skill_83_noBG.png"] = "b9dc30b8-8d5f-4240-88c5-53703099756b",
    ["ui-icons/skills/skill_84.png"] = "2ada3f9d-2997-4c2c-b345-ca27d22d1307",
    ["ui-icons/skills/skill_84_noBG.png"] = "40226ef7-4815-4b6c-acb8-fa905564f441",
    ["ui-icons/skills/skill_85.png"] = "97e5b5c1-2037-47b4-93d4-bda3640c8dd2",
    ["ui-icons/skills/skill_85_noBG.png"] = "6fb9b88c-e8a3-42c4-94bb-00899f9966f6",
    ["ui-icons/skills/skill_86.png"] = "f3416727-6754-4bff-a601-31c1101823d5",
    ["ui-icons/skills/skill_86_noBG.png"] = "6d429e00-2da7-43a2-8476-9e5ce01b8d68",
    ["ui-icons/skills/skill_87.png"] = "3c900606-b894-4244-ae02-69b8ee18bbbe",
    ["ui-icons/skills/skill_87_noBG.png"] = "b9c6f14a-560a-468b-9a1f-95502b382caa",
    ["ui-icons/skills/skill_88.png"] = "bbfe3c35-449d-4e48-aed8-679ee0a96894",
    ["ui-icons/skills/skill_88_noBG.png"] = "924fa9ec-5fd9-4838-a3f2-7946ba3a7ed6",
    ["ui-icons/skills/skill_89.png"] = "6e46bd07-eeb1-4c24-9921-fb64a31424b8",
    ["ui-icons/skills/skill_89_noBG.png"] = "a2f9b191-36a3-456d-a9e3-492c173dc1da",
    ["ui-icons/skills/skill_8_noBG.png"] = "3dc45509-3787-401e-aab7-cba37d2625d8",
    ["ui-icons/skills/skill_9.png"] = "b2429665-be3e-41eb-a6f3-6a9136a6969a",
    ["ui-icons/skills/skill_90.png"] = "991e012a-2120-4672-be8c-75c694277042",
    ["ui-icons/skills/skill_90_noBG.png"] = "050714f8-873d-46c1-87d8-7ded9aa4cbcd",
    ["ui-icons/skills/skill_91.png"] = "1fa5b894-b3f7-407c-af6e-c5b668d22535",
    ["ui-icons/skills/skill_91_noBG.png"] = "915bbb28-301c-4337-9db1-b30fa481b2ef",
    ["ui-icons/skills/skill_92.png"] = "c75dfc65-18e3-467d-892a-7060cfb51db6",
    ["ui-icons/skills/skill_92_noBG.png"] = "dab3b307-91e3-46d4-942c-964041544591",
    ["ui-icons/skills/skill_93.png"] = "9f46d2e9-b23a-40ae-9901-d2d7f689dabe",
    ["ui-icons/skills/skill_93_noBG.png"] = "6abef6b5-6117-4d62-87ab-909dcbed3e7f",
    ["ui-icons/skills/skill_94.png"] = "be565e8f-07a6-4645-8586-4333149c73f5",
    ["ui-icons/skills/skill_94_noBG.png"] = "5eceb251-3248-4081-b41b-d3b25defe2ae",
    ["ui-icons/skills/skill_95.png"] = "e4f74392-9c06-4383-a742-fd467a8e4784",
    ["ui-icons/skills/skill_95_noBG.png"] = "36b2456d-16b8-4184-b554-41a65646e2bc",
    ["ui-icons/skills/skill_96.png"] = "cbcf3bd1-7f3e-4eed-84d8-6b5c0b8f44f3",
    ["ui-icons/skills/skill_96_noBG.png"] = "4f1f829e-e5ce-4494-b98e-44b46f1a2716",
    ["ui-icons/skills/skill_97.png"] = "3ff60fbf-519e-4076-a900-debda3bf609e",
    ["ui-icons/skills/skill_97_noBG.png"] = "91922129-a118-4e91-a3be-be31066a68ef",
    ["ui-icons/skills/skill_98.png"] = "05683164-b131-4f9d-86e1-606061e3ae87",
    ["ui-icons/skills/skill_98_noBG.png"] = "2c348679-dd49-42db-afd5-35513ece5cd1",
    ["ui-icons/skills/skill_99.png"] = "fe0e7d64-7adb-45c9-be18-d96686f44728",
    ["ui-icons/skills/skill_99_noBG.png"] = "2a5c4950-1087-4c0a-a437-fdf51d8881ef",
    ["ui-icons/skills/skill_9_noBG.png"] = "f557e218-e275-444f-81a1-8c97d3fc9781",
    ["ui-icons/skills/soul_devouring.png"] = "89d98507-c2be-41ea-a92b-21a5069f71b3",
    ["ui-icons/skills/soul_devouring_nobg.png"] = "4f41ed07-e58c-4dd2-abc2-c20c4f162a48",
    ["ui-icons/skills/spawn.png"] = "e1eebfee-1b8a-4bb5-acaa-67e040eed909",
    ["ui-icons/skills/spawn_nobg.png"] = "f44ec36d-011d-44f7-963f-7fdf0be98ee6",
    ["ui-icons/skills/spear_hit.png"] = "cfd2d751-46dd-4d27-a47c-ea83c106c36a",
    ["ui-icons/skills/spear_hit_nobg.png"] = "3af037d0-e5fe-428a-bace-93cdb77f0ed2",
    ["ui-icons/skills/superiority.png"] = "b52d3273-038c-47c6-9937-da389a548f85",
    ["ui-icons/skills/superiority_nobg.png"] = "2366a9df-7419-4997-9bc2-4476bd5b44ff",
    ["ui-icons/skills/tail_strike.png"] = "413855bf-4d4d-4275-9f85-b3128450e4cc",
    ["ui-icons/skills/tail_strike_nobg.png"] = "9d257f00-7b1f-4cc9-8ee9-f762d80380ce",
    ["ui-icons/skills/tranquility.png"] = "5b5927f9-cb3e-4792-ad8d-3d66c42d7433",
    ["ui-icons/skills/tranquility_nobg.png"] = "52312f85-94d7-448c-adc5-2519f9c96276",
    ["ui-icons/skills/vampire.png"] = "c142154d-944f-4517-9a5c-26387ce2413e",
    ["ui-icons/skills/vampire_nobg.png"] = "7dea8ff5-46dc-424c-a758-4c88bbe05909",
    ["ui-icons/skills/venom.png"] = "f4c92b7c-a536-40b7-9027-8c923d0ed89a",
    ["ui-icons/skills/venom_nobg.png"] = "884e4564-e590-4552-bd7e-b8f7a29609e6",
    ["ui-icons/skills/voracity.png"] = "55221dd0-05f6-4907-8e4d-6f145f1340cd",
    ["ui-icons/skills/voracity_nobg.png"] = "119e067e-0fd1-4d67-b1f0-0bb3fdc02c6e",
}
local builtinImageIdsFolded = {}
for key, image in pairs(builtinImageIds) do
    local folded = key:lower()
    if builtinImageIdsFolded[folded] == nil then builtinImageIdsFolded[folded] = image
    elseif builtinImageIdsFolded[folded] ~= image then builtinImageIdsFolded[folded] = false end
end

local function resolveActionImage(asset)
    local registered = builtinImageIds[asset]
    if registered == nil then registered = builtinImageIdsFolded[asset:lower()] end
    if registered == false then return nil end
    return registered or asset
end

-- Construct a sparkle with the basic square sprite, which is available in every theme.
local function iconPanel(asset, color, size)
    if asset then
        return gui.Panel{width = size, height = size, halign = "center", valign = "center",
            bgimage = asset, bgcolor = color, interactable = false}
    end
    return gui.Panel{
        width = size, height = size, halign = "center", valign = "center", flow = "none",
        interactable = false,
        gui.Panel{width = size * 0.67, height = size * 0.67, rotate = 45, halign = "center", valign = "center",
            bgimage = "panels/square.png", bgcolor = color, cornerRadius = 2, interactable = false},
        gui.Panel{width = size * 0.22, height = size * 0.22, rotate = 45, x = size * 0.46, y = -size * 0.38,
            halign = "center", valign = "center", bgimage = "panels/square.png", bgcolor = "#ffffff",
            interactable = false},
    }
end

local function actionIcon(action, rules)
    if type(rules.icon_asset) == "string" and rules.icon_asset ~= "" then
        local resolved = resolveActionImage(rules.icon_asset)
        if resolved then return resolved, "white" end
    end
    local icon = spellIcons[rules.icon]
    if icon then return icon[1], icon[2] end
    local damage = tostring(action.damage_type or ""):lower()
    if damage == "fire" or damage == "\208\190\208\179\208\190\208\189\209\140" then icon = spellIcons.fire
    elseif damage == "cold" or damage == "\209\133\208\190\208\187\208\190\208\180" then icon = spellIcons.frost
    elseif damage == "lightning" or damage == "\209\141\208\187\208\181\208\186\209\130\209\128\208\184\209\135\208\181\209\129\209\130\208\178\208\190" then icon = spellIcons.lightning
    elseif damage == "healing" or damage == "heal" or damage == "\208\187\208\181\209\135\208\181\208\189\208\184\208\181" or damage == "\208\184\209\129\209\134\208\181\208\187\208\181\208\189\208\184\208\181" then
        icon = spellIcons.healing
    elseif action.kind == "attack" then icon = spellIcons.weapon
    else icon = spellIcons.magic end
    return icon[1], icon[2]
end

local shapeNames = {
    sphere = "\209\129\209\132\208\181\209\128\208\176", burst = "\208\178\208\190\208\186\209\128\209\131\208\179 \209\129\208\181\208\177\209\143", cone = "\208\186\208\190\208\189\209\131\209\129", cube = "\208\186\209\131\208\177", line = "\208\187\208\184\208\189\208\184\209\143",
}
local nativeShapes = {sphere = "sphere", burst = "RadiusFromCreature", cone = "cone", cube = "cube", line = "line"}

local function actionDetails(action)
    local rules = action.map_targeting or {}
    local distance = tonumber(rules.range_ft)
    local text = distance and (distance == 0 and "\208\158\209\130 \209\129\208\181\208\177\209\143" or (distance .. " \209\132\209\130."))
        or (action.range and action.range ~= "" and safeText(action.range) or "\208\148\208\176\208\187\209\140\208\189\208\190\209\129\209\130\209\140 \208\189\208\181 \208\183\208\176\208\180\208\176\208\189\208\176")
    if shapeNames[rules.shape] then text = text .. " \194\183 " .. shapeNames[rules.shape] .. " " .. rules.size_ft .. " \209\132\209\130." end
    return text
end

local function clearMarker(targeting)
    if targeting.marker then
        targeting.marker:Destroy()
        targeting.marker = nil
    end
end

local function clearRangeMarker(targeting)
    if targeting.rangeMarker then
        targeting.rangeMarker:Destroy()
        targeting.rangeMarker = nil
    end
end

local function clearTargeting()
    local targeting = state.targeting
    state.targeting = nil
    if not targeting then return end
    clearMarker(targeting)
    clearRangeMarker(targeting)
    if targeting.panel and targeting.panel.valid then targeting.panel:DestroySelf() end
end

local function nativeUnits(feet)
    return feet / 5 * (tonumber(dmhub.unitsPerSquare) or 5)
end

local function distanceTo(caster, target)
    local ok, distance = pcall(function() return caster:Distance(target) end)
    if not ok or type(distance) ~= "number" then return nil end
    return math.ceil(distance * 5 / nativeUnits(5) - 0.00001)
end

local function withinRange(targeting, target, fromCaster)
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if not controlled(caster) or caster.onBoard == false then return nil, "\208\151\208\176\208\186\208\187\208\184\208\189\208\176\209\130\208\181\208\187\209\140 \208\191\208\190\208\186\208\184\208\189\209\131\208\187 \208\186\208\176\209\128\209\130\209\131." end
    local limit = tonumber(targeting.rules.range_ft)
    if limit == 0 and not fromCaster and target.charid ~= caster.charid then return nil, "\208\148\208\181\208\185\209\129\209\130\208\178\208\184\208\181 \208\191\209\128\208\184\208\188\208\181\208\189\209\143\208\181\209\130\209\129\209\143 \208\189\208\176 \209\129\208\181\208\177\209\143." end
    local distance = fromCaster and 0 or distanceTo(caster, target)
    if limit and not distance then return nil, "DMHub \208\189\208\181 \209\129\208\188\208\190\208\179 \208\184\208\183\208\188\208\181\209\128\208\184\209\130\209\140 \209\128\208\176\209\129\209\129\209\130\208\190\209\143\208\189\208\184\208\181." end
    if limit and distance > limit then return nil, distance .. " \209\132\209\130. \194\183 \208\183\208\176 \208\191\209\128\208\181\208\180\208\181\208\187\208\176\208\188\208\184 \208\180\208\176\208\187\209\140\208\189\208\190\209\129\209\130\208\184 " .. limit .. " \209\132\209\130." end
    return distance or 0
end

local function markCells(locs, floor)
    if not dmhub.MarkLocs or not locs or #locs == 0 then return nil end
    local onFloor = {}
    for _, loc in ipairs(locs) do
        onFloor[#onFloor + 1] = loc.floor ~= floor and loc.WithDifferentFloor
            and loc:WithDifferentFloor(floor) or loc
    end
    return dmhub.MarkLocs{locs = onFloor, color = "#ffffff", style = "solid"}
end

local function rangeCircle(caster, feet)
    if not dmhub.HighlightLine then return nil end
    local center, radius = caster:PosAtLoc(), nativeUnits(feet)
    if caster.loc.dir then
        local adjacent = caster:PosAtLoc(caster.loc:dir(1, 0))
        local dx, dy = adjacent.x - center.x, adjacent.y - center.y
        local tileWidth = math.sqrt(dx * dx + dy * dy)
        if tileWidth > 0 then radius = feet / 5 * tileWidth end
    end
    local markers = {}
    for i = 1, 48 do
        local a, b = (i - 1) * math.pi / 24, i * math.pi / 24
        local marker = dmhub.HighlightLine{
            a = {x = center.x + radius * math.cos(a), y = center.y + radius * math.sin(a)},
            b = {x = center.x + radius * math.cos(b), y = center.y + radius * math.sin(b)},
            color = "#ffffff", floorIndex = caster.loc.floor, terrainParallax = true,
        }
        if marker then markers[#markers + 1] = marker end
    end
    if #markers == 0 then return nil end
    return {Destroy = function() for _, marker in ipairs(markers) do marker:Destroy() end end}
end

local function updateRangeMarker(targeting)
    local limit = tonumber(targeting.rules.range_ft)
    if not limit or limit <= 0 then return end
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if not caster or not caster.loc or caster.loc.str == targeting.rangeOrigin then return end
    targeting.rangeOrigin = caster.loc.str
    clearRangeMarker(targeting)
    if limit <= 150 and dmhub.MarkLocs then
        local ok, marker = pcall(function()
            return markCells(caster:GetLocsWithinRadius(limit / 5), caster.loc.floor)
        end)
        if ok then targeting.rangeMarker = marker end
    end
    if not targeting.rangeMarker then targeting.rangeMarker = rangeCircle(caster, limit) end
end

local function isMapTarget(token, scene)
    return token and token.valid and token.onBoard ~= false
        and (scene.is_dm or (not token.hiddenFromLocalViewer and token.canSee ~= false))
end

-- DMHub game assets provide the media. Only the choice and labels are local preferences.
local visualFX = {}
do
    local EVENT = "sessionlab.visual.v1"
    local PREFERENCES = "sessionlab_action_fx_v1"
    local DURATION = 3
    local seen, order = {}, {}
    visualFX.presets = {
        {id = "fire", label = "\208\158\208\179\208\190\208\189\209\140", asset = "fire-radius.webm"},
        {id = "healing", label = "\208\155\208\181\209\135\208\181\208\189\208\184\208\181", asset = "cure-wounds.webm"},
        {id = "radiant", label = "\208\152\208\183\208\187\209\131\209\135\208\181\208\189\208\184\208\181", asset = "magic-effect.webm", color = "#ffe09c"},
        {id = "poison", label = "\208\175\208\180", asset = "magic-effect.webm", color = "#96ee6a"},
        {id = "magic", label = "\208\156\208\176\208\179\208\184\209\143", asset = "magic-effect.webm"},
    }
    local presets = {}
    for _, preset in ipairs(visualFX.presets) do presets[preset.id] = preset end
    local FIRE = presets.fire.asset
    local automatic = {
        ["fire"] = "fire", ["\208\190\208\179\208\190\208\189\209\140"] = "fire", ["fireball"] = "fire", ["\208\190\208\179\208\189\208\181\208\189\208\189\209\139\208\185 \209\136\208\176\209\128"] = "fire",
        ["healing"] = "healing", ["heal"] = "healing", ["\208\187\208\181\209\135\208\181\208\189\208\184\208\181"] = "healing", ["\208\184\209\129\209\134\208\181\208\187\208\181\208\189\208\184\208\181"] = "healing",
        ["healing word"] = "healing", ["\208\187\208\181\209\135\208\176\209\137\208\181\208\181 \209\129\208\187\208\190\208\178\208\190"] = "healing",
        ["cure wounds"] = "healing", ["\208\187\208\181\209\135\208\181\208\189\208\184\208\181 \209\128\208\176\208\189"] = "healing",
        ["lay on hands"] = "healing", ["\208\189\208\176\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \209\128\209\131\208\186"] = "healing", ["\208\178\208\190\208\183\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \209\128\209\131\208\186"] = "healing",
        ["radiant"] = "radiant", ["\208\184\208\183\208\187\209\131\209\135\208\181\208\189\208\184\208\181"] = "radiant", ["divine smite"] = "radiant",
        ["\208\177\208\190\208\182\208\181\209\129\209\130\208\178\208\181\208\189\208\189\208\176\209\143 \208\186\208\176\209\128\208\176"] = "radiant", ["\208\177\208\190\208\182\208\181\209\129\209\130\208\178\208\181\208\189\208\189\209\139\208\181 \208\186\208\176\209\128\209\139"] = "radiant",
        ["poison"] = "poison", ["\209\143\208\180"] = "poison", ["poison spray"] = "poison",
        ["\208\177\209\128\209\139\208\183\208\179\208\184 \209\143\208\180\208\176"] = "poison", ["\209\143\208\180\208\190\208\178\208\184\209\130\209\139\208\181 \208\177\209\128\209\139\208\183\208\179\208\184"] = "poison",
    }

    local function normalized(value)
        return tostring(value or ""):lower():gsub("\208([\144-\175])", function(byte)
            local code = byte:byte()
            if code < 160 then return string.char(208, code + 32) end
            return string.char(209, code - 32)
        end):gsub("\208\129", "\209\145"):match("^%s*(.-)%s*$")
    end

    function visualFX.assetId(value)
        if type(value) ~= "string" or #value > 50 then return nil end
        value = value:match("^%s*(.-)%s*$")
        if #value == 32 and value:match("^%x+$") then return value end
        if #value == 36 and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x+$")
                and #value:match("%x+$") == 12 then return value end
    end

    local function videoAsset(asset)
        return visualFX.assetId(asset) or (type(asset) == "string" and asset:match("^[%w_. /%-]+$")
            and not asset:find("..", 1, true) and asset:sub(1, 1) ~= "/"
            and (asset:lower():match("%.webm$") or asset:lower():match("%.mp4$")) and asset)
    end

    local function preferences(scope)
        local all = dmhub.GetSettingValue(PREFERENCES)
        if type(all) ~= "table" then all = {} end
        local own = all[scope]
        if type(own) ~= "table" then own = {} end
        return {
            choices = type(own.choices) == "table" and own.choices or {},
            library = type(own.library) == "table" and own.library or {},
        }, all
    end

    local function copy(values)
        local result = {}
        for key, value in pairs(values) do result[key] = value end
        return result
    end

    function visualFX.library(scope)
        return preferences(scope).library
    end

    function visualFX.choice(scope, actionId)
        if not scope or not actionId then return nil end
        return preferences(scope).choices[actionId]
    end

    function visualFX.save(scope, actionId, choice, clip, title)
        local own, all = preferences(scope)
        if actionId then
            own.choices = copy(own.choices)
            own.choices[actionId] = choice
        end
        if clip then
            own.library = copy(own.library)
            own.library[clip] = title
        end
        all = copy(all)
        all[scope] = own
        dmhub.SetSettingValue(PREFERENCES, all)
    end

    function visualFX.choiceLabel(choice, library)
        if choice == "none" then return "\208\145\208\181\208\183 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\208\184" end
        if presets[choice] then return presets[choice].label end
        if choice then return library[choice] or choice end
        return "\208\159\208\190 \208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\181 \208\187\208\184\209\129\209\130\208\176"
    end

    local function destroy(panel)
        if panel and panel.valid then panel:DestroySelf() end
    end

    local function cleanupLater(panel)
        dmhub.Schedule(DURATION, function() destroy(panel) end)
    end

    local function videoPanel(token, asset, key, color)
        local host = token.sheet
        if not host or not host.valid then return false end
        -- All targets of one cast reuse the same playback key.
        local panel = gui.Panel{
            width = 180, height = 180, halign = "center", valign = "center",
            floating = true, interactable = false, bgcolor = color or "white",
            bgimage = asset .. "###" .. key,
            videoFinished = function(element) destroy(element) end,
        }
        host:AddChild(panel)
        cleanupLater(panel)
        return true
    end

    local function registeredEffects(asset)
        local lookup = rawget(_G, "GetTokenEffects")
        if type(lookup) ~= "function" then return nil end
        local ok, effects = pcall(lookup, asset)
        if ok and type(effects) == "table" then return effects end
    end

    local function customEffect(token, asset, key)
        local video = videoAsset(asset)
        if video then return videoPanel(token, video, key) end
        local effects = registeredEffects(asset)
        local play = token.sheet and token.sheet.data and token.sheet.data.PlayEffect
        if effects and #effects > 0 and type(play) == "function" then
            local panels = play(asset, false)
            for _, panel in ipairs(panels or {}) do cleanupLater(panel) end
            return true
        end
        return false
    end

    function visualFX.receive(message)
        if rawget(_G, RUNTIME) ~= state or type(message) ~= "table" or message.v ~= 1
                or message.game ~= tostring(dmhub.gameid or "")
                or type(message.key) ~= "string" or #message.key > 160
                or type(message.tokens) ~= "table" then return end
        if message.mode ~= "fire" and message.mode ~= "custom" then return end
        local asset = message.mode == "fire" and FIRE or message.asset
        if type(asset) ~= "string" or asset == "" or #asset > 120 then return end
        local preset = presets[message.preset]
        if seen[message.key] then return end
        seen[message.key] = true
        order[#order + 1] = message.key
        if #order > 128 then seen[table.remove(order, 1)] = nil end
        local painted, failed, used = 0, false, {}
        for index, tokenId in ipairs(message.tokens) do
            if index > 50 then break end
            if type(tokenId) == "string" and #tokenId <= 200 and not used[tokenId] then
                used[tokenId] = true
                local token = dmhub.GetTokenById(tokenId)
                if token and token.valid and token.onBoard ~= false and token.canSee ~= false
                        and (not message.map or not token.mapid or token.mapid == message.map) then
                    local ok, result = pcall(function()
                        if preset and preset.asset == asset then
                            return videoPanel(token, asset, message.key, preset.color)
                        end
                        return customEffect(token, asset, message.key)
                    end)
                    if ok and result then painted = painted + 1
                    elseif not ok then
                        failed = true
                        report("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\178\208\184\208\183\209\131\208\176\208\187\209\140\208\189\209\139\208\185 \209\141\209\132\209\132\208\181\208\186\209\130: " .. safeText(result))
                    else failed = true end
                end
            end
        end
        if painted == 0 and failed then
            report("\208\146\208\184\208\183\209\131\208\176\208\187\209\140\208\189\209\139\208\185 \209\141\209\132\209\132\208\181\208\186\209\130 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189: " .. safeText(asset))
        end
    end

    local function send(mode, asset, tokens, map, preset)
        if #tokens == 0 then return end
        local message = {v = 1, key = "slfx-" .. dmhub.GenerateGuid(),
            game = tostring(dmhub.gameid or ""), mode = mode, asset = asset, tokens = tokens, map = map,
            preset = preset}
        visualFX.receive(message)
        if type(dmhub.BroadcastRemoteEvent) == "function" then
            -- sessionid is a sequence stream, not a recipient ID (PeerToPeerManager).
            local stream = "SessionLabFX|" .. message.game .. "|" .. tostring(dmhub.userid or "local")
            local ok, err = pcall(dmhub.BroadcastRemoteEvent, EVENT, stream, message)
            if not ok then report("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\191\208\181\209\128\208\181\208\180\208\176\209\130\209\140 \209\141\209\132\209\132\208\181\208\186\209\130 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\176\208\188: " .. safeText(err)) end
        else
            report("\208\146 \209\141\209\130\208\190\208\185 \208\178\208\181\209\128\209\129\208\184\208\184 DMHub \209\141\209\132\209\132\208\181\208\186\209\130 \208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189 \209\130\208\190\208\187\209\140\208\186\208\190 \208\189\208\176 \209\130\208\181\208\186\209\131\209\137\208\181\208\188 \208\186\208\187\208\184\208\181\208\189\209\130\208\181.")
        end
    end

    local function effectFor(targeting, radiant)
        local action = targeting.action
        local rules = targeting.rules or {}
        local choice = targeting.menu and action.id and visualFX.choice(targeting.menu.context, id(action.id))
        if choice == "none" then return nil end
        if presets[choice] then return presets[choice] end
        local clip = visualFX.assetId(choice)
        if clip then return {asset = clip} end
        local effect = rules.effect or "auto"
        if effect == "auto" then
            local key = radiant and "radiant" or automatic[normalized(action.damage_type)]
                or automatic[normalized(action.name)]
            return presets[key]
        end
        if presets[effect] then return presets[effect] end
        if effect == "custom" and type(rules.effect_asset) == "string" and rules.effect_asset ~= "" then
            if rules.effect_asset == "Fire Loop sim 3" or rules.effect_asset == FIRE then return presets.fire end
            return {asset = rules.effect_asset}
        end
    end

    local function affectsTarget(summary, payload)
        local outcomes = summary and summary.parts or {}
        if #outcomes == 0 then return true end
        local parts = payload.parts or {payload}
        for index, outcome in ipairs(outcomes) do
            if outcome.hit ~= false then
                if outcome.save_outcome ~= "success" then return true end
                local save = parts[index] and parts[index].save
                if save and (tonumber(save.success_damage) or 0) > 0 then return true end
            end
        end
        return false
    end

    local function playArea(shape, effect)
        local video = videoAsset(effect.asset)
        if not video then
            for _, candidate in ipairs(registeredEffects(effect.asset) or {}) do
                video = videoAsset(candidate.video)
                if video then break end
            end
        end
        if not video then
            report("\208\148\208\187\209\143 \209\141\209\132\209\132\208\181\208\186\209\130\208\176 \208\191\208\190 \208\190\208\177\208\187\208\176\209\129\209\130\208\184 \208\178\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\178\208\184\208\180\208\181\208\190 WebM \208\184\208\187\208\184 \208\178\209\129\209\130\209\128\208\190\208\181\208\189\208\189\209\131\209\142 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\209\142.")
            return
        end
        if visualFX.assetId(video) then
            -- Unlike GUI images, native shape markers expect a filename or URL.
            -- Resolve the game asset as DMHub's OpenImageAssetURL does.
            local rawId = type(dmhub.GetRawImageId) == "function" and dmhub.GetRawImageId(video)
            if type(rawId) ~= "string" or #rawId ~= 24 or not rawId:match("^[%w+/]+==$") then
                report("\208\146\208\184\208\180\208\181\208\190 \208\190\208\177\208\187\208\176\209\129\209\130\208\184 \208\191\208\190\208\186\208\176 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\190 \208\178 \209\128\208\181\209\129\209\131\209\128\209\129\208\176\209\133 \209\141\209\130\208\190\208\185 \208\184\208\179\209\128\209\139 DMHub.")
                return
            end
            local key = rawId:gsub("/", "-"):gsub("%+", "_"):gsub("=", "~")
            video = "https://storage.googleapis.com/dmhub_images/" .. key
        end
        -- Mark broadcasts the resolved shape and its video using DMHub's native marker transport.
        local playback = video .. "###slfx-" .. dmhub.GenerateGuid()
        local marker = shape:Mark{video = playback, color = effect.color or "white", showLocs = true}
        if marker then dmhub.Schedule(DURATION, function() marker:Destroy() end) end
    end

    function visualFX.animate(targeting, rows, payload, shape)
        if targeting.area then
            local effect = effectFor(targeting, false)
            if shape and effect then playArea(shape, effect) end
            return
        end
        payload = payload or {}
        local summaries, groups = {}, {}
        for _, summary in ipairs(payload.token_targets or {}) do summaries[tostring(summary.id)] = summary end
        for _, row in ipairs(rows) do
            local summary = payload.token_target or summaries[tostring(row.id)]
            if type(row.token) == "string" and affectsTarget(summary, payload) then
                local effect = effectFor(targeting, summary and summary.visual_radiant == true)
                if effect then
                    local key = effect.id or effect.asset
                    local group = groups[key] or {effect = effect, tokens = {}}
                    group.tokens[#group.tokens + 1] = row.token
                    groups[key] = group
                end
            end
        end
        for _, group in pairs(groups) do
            local effect = group.effect
            send(effect.id == "fire" and "fire" or "custom", effect.asset, group.tokens,
                targeting.menu and targeting.menu.map, effect.id)
        end
    end

    function visualFX.test(args)
        local requested = tostring(args or ""):match("^%s*(.-)%s*$")
        local token = dmhub.tokenHovered
        if not controlled(token) then
            token = nil
            for _, candidate in ipairs(dmhub.selectedTokens or {}) do
                if controlled(candidate) then token = candidate break end
            end
        end
        if not token then report("\208\146\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \209\129\208\178\208\190\208\185 \209\130\208\190\208\186\208\181\208\189 \208\184 \208\178\208\178\208\181\208\180\208\184\209\130\208\181 /slfx fire.") return end
        local mode = (requested == "" or requested == "fire") and "fire" or "custom"
        send(mode, requested, {token.charid}, token.mapid)
    end

    function visualFX.register()
        if type(dmhub.RegisterSetting) == "function" then
            dmhub.RegisterSetting{id = PREFERENCES, storage = "pergamepreference", default = {}}
        end
        if type(dmhub.RegisterRemoteEvent) ~= "function" then return end
        local ok, err = pcall(dmhub.RegisterRemoteEvent, EVENT, visualFX.receive)
        if not ok then report("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\191\208\190\208\180\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\190\208\177\209\137\208\184\208\181 \208\178\208\184\208\183\209\131\208\176\208\187\209\140\208\189\209\139\208\181 \209\141\209\132\209\132\208\181\208\186\209\130\209\139: " .. safeText(err)) end
    end
end


local function applyMapAction(targeting, rows, distance, areaShape)
    local menu, action = targeting.menu, targeting.action
    if not tokenStillControlled(menu) or (state.pending and state.pending.sending) then return end
    clearTargeting()
    if not active(menu) then openPopup(menu) end
    local body = {
        session = targeting.scene.session, game = dmhub.gameid, caster = targeting.sheet,
        slot_level = targeting.level,
    }
    if targeting.scene.map_actions then
        body.command, body.action, body.action_version = "act", action.id, action.version
        body.distance_ft, body.targets = distance, {}
        for _, row in ipairs(rows) do body.targets[#body.targets + 1] = {id = row.id, token = row.token} end
        body.effects = targeting.effects
    else
        body.command, body.spell = "cast", action.id
        body.token, body.target = rows[1].token, rows[1].id
    end
    local job = {
        path = TOKEN_SCENE, body = body, label = safeText(action.name),
        binding = bindingKey(menu), context = menu.context,
        key = "sl-act-" .. dmhub.GenerateGuid(), actionKind = action.kind, sheet = tostring(targeting.sheet),
        animate = function(payload)
            if context() == menu.context and tokenStillControlled(menu) then
                visualFX.animate(targeting, rows, payload, areaShape)
            end
        end,
    }
    state.pending = job
    sendRoll(menu, job)
end

local function setTargetHint(targeting, text)
    if targeting.hint and targeting.hint.valid and targeting.hint.text ~= text then targeting.hint.text = text end
end

local function applyDirect(targeting, row, token)
    if not isMapTarget(token, targeting.scene) then
        setTargetHint(targeting, "\208\166\208\181\208\187\209\140 \208\177\208\190\208\187\209\140\209\136\208\181 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\176 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181.")
        return false
    end
    local distance, errorText = withinRange(targeting, token)
    if not distance then setTargetHint(targeting, errorText) return false end
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if caster.charid ~= token.charid then
        local ok, sight = pcall(function() return caster:GetLineOfSight(token) end)
        if ok and sight == 0 then setTargetHint(targeting, "\208\156\208\181\208\182\208\180\209\131 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\209\130\208\181\208\187\208\181\208\188 \208\184 \209\134\208\181\208\187\209\140\209\142 \208\181\209\129\209\130\209\140 \208\191\209\128\208\181\208\179\209\128\208\176\208\180\208\176.") return false end
    end
    applyMapAction(targeting, {row}, distance)
    return true
end

local function areaAt(targeting, loc, point)
    if not loc then return nil, "\208\157\208\176\208\178\208\181\208\180\208\184\209\130\208\181 \208\186\209\131\209\128\209\129\208\190\209\128 \208\189\208\176 \208\186\208\187\208\181\209\130\208\186\209\131 \208\186\208\176\209\128\209\130\209\139." end
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if not controlled(caster) or caster.onBoard == false then return nil, "\208\151\208\176\208\186\208\187\208\184\208\189\208\176\209\130\208\181\208\187\209\140 \208\191\208\190\208\186\208\184\208\189\209\131\208\187 \208\186\208\176\209\128\209\130\209\131." end
    -- Map focus provides the cursor's world point. PosAtLoc uses the caster's footprint.
    point = point or caster:PosAtLoc(loc)
    if not point then return nil, "\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\208\184\209\130\209\140 \209\134\208\181\208\189\209\130\209\128 \208\190\208\177\208\187\208\176\209\129\209\130\208\184." end
    local rules = targeting.rules
    local casterOrigin = rules.shape == "burst" or tonumber(rules.range_ft) == 0
    local distance, errorText = withinRange(targeting, loc, casterOrigin)
    if not distance then return nil, errorText end
    if rules.shape == "burst" or (rules.shape == "sphere" and casterOrigin) then
        loc, point = caster.loc, caster:PosAtLoc()
    end
    local feet = tonumber(rules.size_ft) or 0
    local size = nativeUnits(feet)
    local range = nativeUnits(tonumber(rules.range_ft) or distance)
    if rules.shape == "line" or rules.shape == "cone" or rules.shape == "burst" then range = size end
    if rules.shape == "cube" and casterOrigin then
        local dx, dy = loc.x - caster.loc.x, loc.y - caster.loc.y
        if dx == 0 and dy == 0 then return nil, "\208\163\208\186\208\176\208\182\208\184\209\130\208\181 \208\189\208\176\208\191\209\128\208\176\208\178\208\187\208\181\208\189\208\184\208\181 \208\186\209\131\208\177\208\176." end
        local offset = math.max(1, math.ceil((feet / 5 + 1) / 2))
        if math.abs(dx) >= math.abs(dy) then
            loc = caster.loc:dir(dx < 0 and -offset or offset, 0)
        else
            loc = caster.loc:dir(0, dy < 0 and -offset or offset)
        end
        point, range = caster:PosAtLoc(loc), size
    end
    local origin = point
    if rules.shape == "burst" then origin = nil end
    local shape = dmhub.CalculateShape{
        shape = nativeShapes[rules.shape], targetPoint = origin, token = caster,
        range = range, radius = rules.shape == "line" and nativeUnits(5) or size,
    }
    if not shape or shape.valid == false then return nil, "DMHub \208\189\208\181 \209\129\208\188\208\190\208\179 \208\191\208\190\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\190\208\177\208\187\208\176\209\129\209\130\209\140." end
    local nativeTargets = {}
    local tokensInShape = dmhub.tokenInfo and dmhub.tokenInfo.TokensInShape
    if type(tokensInShape) == "function" then
        local ok, result = pcall(tokensInShape, shape)
        if ok and type(result) == "table" then nativeTargets = result end
    end
    local containsToken = shape.ContainsToken
    local cells, rows = {}, {}
    for _, cell in ipairs(shape.locations or {}) do
        if cell.x ~= nil and cell.y ~= nil then
            cells[cell.x .. ":" .. cell.y] = true
        end
    end
    for _, row in ipairs(targeting.targets) do
        local token = dmhub.GetTokenById(row.token)
        if isMapTarget(token, targeting.scene) and token.loc and token.loc.floor == loc.floor then
            local contains = nativeTargets[token.charid] or (type(containsToken) == "function" and containsToken(shape, token))
            if not contains and (token.loc.altitude or 0) == (loc.altitude or 0) then
                for _, occupied in ipairs(token.locsOccupying or {token.loc}) do
                    if occupied.x ~= nil and occupied.y ~= nil and cells[occupied.x .. ":" .. occupied.y] then
                        contains = true
                        break
                    end
                end
            end
            if contains then rows[#rows + 1] = row end
        end
    end
    return {shape = shape, rows = rows, distance = distance, loc = loc}
end

local function previewArea(targeting, loc, point)
    local caster = dmhub.GetTokenById(targeting.menu.token)
    local key = loc and (loc.str .. "|" .. tostring(caster and caster.loc and caster.loc.str))
    if key and point then
        key = key .. "|" .. tostring(point.x) .. "|" .. tostring(point.y) .. "|" .. tostring(point.z)
    end
    if targeting.previewKey == key then return end
    targeting.previewKey = key
    clearMarker(targeting)
    local area, errorText = areaAt(targeting, loc, point)
    if not area then setTargetHint(targeting, errorText) return end
    if dmhub.MarkLocs and area.shape.locations then
        local ok, marker = pcall(markCells, area.shape.locations, area.loc.floor)
        if ok then targeting.marker = marker end
    end
    if not targeting.marker and type(area.shape.Mark) == "function" then
        targeting.marker = area.shape:Mark{color = "#ffffff", showLocs = false}
    end
    setTargetHint(targeting, "\208\166\208\181\208\187\208\181\208\185 \208\178 \208\190\208\177\208\187\208\176\209\129\209\130\208\184: " .. #area.rows .. " \194\183 \208\189\208\176\208\182\208\188\208\184\209\130\208\181 \208\180\208\187\209\143 \208\191\209\128\208\184\208\188\208\181\208\189\208\181\208\189\208\184\209\143")
end

local function commitArea(targeting, loc, point)
    local area, errorText = areaAt(targeting, loc, point)
    if not area then setTargetHint(targeting, errorText) return end
    if #area.rows > 50 then setTargetHint(targeting, "\208\161\208\187\208\184\209\136\208\186\208\190\208\188 \208\188\208\189\208\190\208\179\208\190 \209\134\208\181\208\187\208\181\208\185 \208\178 \208\190\208\177\208\187\208\176\209\129\209\130\208\184 (\208\188\208\176\208\186\209\129\208\184\208\188\209\131\208\188 50).") return end
    applyMapAction(targeting, area.rows, area.distance, area.shape)
end

local function mapTargetClick(token)
    local targeting = state.targeting
    if not targeting then return false end
    if context() ~= targeting.menu.context then clearTargeting() return false end
    if not token or not token.valid then return false end
    if targeting.area then
        commitArea(targeting, token.loc, token:PosAtLoc())
        return true
    end
    for _, row in ipairs(targeting.targets) do
        if row.token == token.charid then applyDirect(targeting, row, token) return true end
    end
    setTargetHint(targeting, "\208\173\209\130\208\190\209\130 \209\130\208\190\208\186\208\181\208\189 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189. \208\156\208\176\209\129\209\130\208\181\209\128 \208\188\208\190\208\182\208\181\209\130 \208\191\209\128\208\184\208\178\209\143\208\183\208\176\209\130\209\140 \208\181\208\179\208\190 \208\186 \209\129\209\134\208\181\208\189\208\181 SessionLab.")
    return true
end

local function selectTarget(menu, sheet, action, level, effects)
    if not active(menu) or not tokenStillControlled(menu) then return end
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \209\134\208\181\208\187\208\184 \209\129\209\134\208\181\208\189\209\139\226\128\166", {})
    local page = menu.page
    local function current() return active(menu) and menu.page == page end
    tokenScene(function(scene)
        if not current() then return end
        if not scene.session then
            show(menu, "\208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\208\190\208\178\209\131\209\142 \209\129\208\181\209\129\209\129\208\184\209\142 \208\178 SessionLab \208\180\208\187\209\143 \208\178\209\139\208\177\208\190\209\128\208\176 \209\134\208\181\208\187\208\184.", {})
            return
        end
        local rules = action.map_targeting or {shape = "single"}
        local area = nativeShapes[rules.shape] ~= nil
        if not scene.map_actions and (area or action.kind == "attack") then
            show(menu, "\208\148\208\187\209\143 \208\176\209\130\208\176\208\186 \208\184 \208\190\208\177\208\187\208\176\209\129\209\130\208\181\208\185 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\208\181 \209\129\208\181\209\128\208\178\208\181\209\128 SessionLab.", {})
            return
        end
        if area and (type(dmhub.CalculateShape) ~= "function" or action.resolution == "attack") then
            show(menu, "\208\148\208\187\209\143 \208\190\208\177\208\187\208\176\209\129\209\130\208\184 \208\189\209\131\208\182\208\181\208\189 \208\191\208\190\208\180\208\180\208\181\209\128\208\182\208\184\208\178\208\176\208\181\208\188\209\139\208\185 \208\186\208\187\208\184\208\181\208\189\209\130 DMHub \208\184 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\181 \208\177\208\181\208\183 \208\177\209\128\208\190\209\129\208\186\208\176 \208\176\209\130\208\176\208\186\208\184.", {})
            return
        end
        local targeting = {menu = menu, scene = scene, sheet = tonumber(sheet), action = action,
            level = level, rules = rules, area = area, targets = {}, effects = effects}
        for _, row in ipairs(scene.targets or {}) do
            local token = type(row.token) == "string" and row.token ~= "" and dmhub.GetTokenById(row.token)
            if token and token.valid and token.onBoard ~= false and (scene.is_dm or row.targetable) then
                targeting.targets[#targeting.targets + 1] = row
            end
        end
        local function cancel()
            clearTargeting()
            if not active(menu) then openPopup(menu) end
            openActions(menu, sheet, action.kind)
        end
        local function listTargets()
            clearTargeting()
            if not active(menu) then openPopup(menu) end
            local rows = {}
            targeting.hint = label(actionDetails(action), 12, "#bfb2f4")
            for _, row in ipairs(targeting.targets) do
                local target = row
                rows[#rows + 1] = button(safeText(row.name), WIDTH - 40, function()
                    local token = dmhub.GetTokenById(target.token)
                    if active(menu) and token and token.valid then applyDirect(targeting, target, token) end
                end)
            end
            show(menu, "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\134\208\181\208\187\209\140", {targeting.hint, menuRows(rows), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, cancel)})
        end
        if #targeting.targets == 0 and not area then
            show(menu, "\208\157\208\176 \208\186\208\176\209\128\209\130\208\181 \208\189\208\181\209\130 \208\191\209\128\208\184\208\178\209\143\208\183\208\176\208\189\208\189\209\139\209\133 \209\134\208\181\208\187\208\181\208\185. \208\156\208\176\209\129\209\130\208\181\209\128 \208\191\209\128\208\184\208\178\209\143\208\183\209\139\208\178\208\176\208\181\209\130 \208\184\209\133 \209\135\208\181\209\128\208\181\208\183 \194\171\208\166\208\181\208\187\209\140 \209\129\209\134\208\181\208\189\209\139\194\187.", {})
            return
        end
        clearTargeting()
        close(menu)
        state.targeting = targeting
        targeting.hint = label(area and "\208\163\208\186\208\176\208\182\208\184\209\130\208\181 \208\186\208\187\208\181\209\130\208\186\209\131 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181" or "\208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189 \209\134\208\181\208\187\208\184", 13, "#e0c9fb")
        local children = {label(safeText(action.name) .. " \194\183 " .. actionDetails(action), 14, "#f2efff")}
        if action.resolution == "save" then
            for _, ability in ipairs(abilities) do
                if ability[1] == action.save_ability then
                    children[#children + 1] = label("\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \194\183 " .. ability[2], 12, "#bfb2f4")
                    break
                end
            end
        end
        children[#children + 1] = targeting.hint
        if not area then children[#children + 1] = button("\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \208\184\208\183 \209\129\208\191\208\184\209\129\208\186\208\176", WIDTH - 20, listTargets) end
        children[#children + 1] = button("\208\158\209\130\208\188\208\181\208\189\208\176", WIDTH - 20, cancel)
        targeting.panel = gui.Panel{
            floating = true, width = WIDTH, height = "auto", flow = "vertical",
            halign = "center", valign = "top", y = 24, pad = 6,
            bgimage = "panels/square.png", bgcolor = "#161624ee", cornerRadius = 8,
            mapfocus = true, captureEscape = true, escape = cancel, thinkTime = 0.2,
            think = function()
                if context() ~= menu.context or not tokenStillControlled(menu) then clearTargeting() return end
                updateRangeMarker(targeting)
                if area then return end
                local token = dmhub.tokenHovered
                local hovered = token and token.valid and token.charid
                if hovered == targeting.hovered then return end
                targeting.hovered = hovered
                for _, row in ipairs(targeting.targets) do
                    if row.token == hovered then
                        local distance, errorText = withinRange(targeting, token)
                        setTargetHint(targeting, errorText or (safeText(row.name) .. " \194\183 " .. distance .. " \209\132\209\130."))
                        return
                    end
                end
                setTargetHint(targeting, "\208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189 \209\134\208\181\208\187\208\184")
            end,
            maphover = function(_, loc, point)
                if state.targeting ~= targeting or not loc then return end
                if area then
                    previewArea(targeting, loc, point)
                elseif not dmhub.tokenHovered and (tonumber(rules.range_ft) or 0) > 0 then
                    local distance, errorText = withinRange(targeting, loc)
                    setTargetHint(targeting, errorText or (distance .. " \209\132\209\130. \194\183 \208\189\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189 \209\134\208\181\208\187\208\184"))
                end
            end,
            mappress = function(_, loc, point)
                if state.targeting ~= targeting then return end
                if area then commitArea(targeting, loc, point) return end
                local hovered = dmhub.tokenHovered
                local tokens = loc and dmhub.GetTokensAtLoc and dmhub.GetTokensAtLoc(loc)
                if not tokens or #tokens == 0 then
                    if hovered and hovered.valid then
                        mapTargetClick(hovered)
                    else
                        setTargetHint(targeting, "\208\157\208\176 \209\141\209\130\208\190\208\185 \208\186\208\187\208\181\209\130\208\186\208\181 \208\189\208\181\209\130 \209\134\208\181\208\187\208\184. \208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189 \208\184\208\187\208\184 \208\178\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\184\208\183 \209\129\208\191\208\184\209\129\208\186\208\176.")
                    end
                    return
                end
                for _, candidate in ipairs(tokens) do
                    if hovered and candidate.charid == hovered.charid then
                        mapTargetClick(candidate)
                        return
                    end
                end
                if #tokens == 1 then mapTargetClick(tokens[1])
                elseif #tokens > 1 then setTargetHint(targeting, "\208\157\208\181\209\129\208\186\208\190\208\187\209\140\208\186\208\190 \209\130\208\190\208\186\208\181\208\189\208\190\208\178 \208\189\208\176 \208\186\208\187\208\181\209\130\208\186\208\181. \208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\134\208\181\208\187\209\140 \208\184\208\183 \209\129\208\191\208\184\209\129\208\186\208\176.")
                end
            end,
            destroy = function()
                if state.targeting == targeting then
                    state.targeting = nil
                    clearMarker(targeting)
                    clearRangeMarker(targeting)
                end
            end,
            children = children,
        }
        menu.host:AddChild(targeting.panel)
        updateRangeMarker(targeting)
        if area and (rules.shape == "burst" or rules.shape == "sphere" and tonumber(rules.range_ft) == 0) then
            local caster = dmhub.GetTokenById(menu.token)
            if caster then previewArea(targeting, caster.loc) end
        end
    end, function(message) if current() then show(menu, message, {}) end end)
end

local function chooseAction(menu, sheet, action, slots, characterLevel)
    local function prepare(level)
        local definitions = action.attack_effects or {}
        if action.resolution ~= "attack" or #definitions == 0 then
            selectTarget(menu, sheet, action, level)
            return
        end
        local available, selected, groups = {}, {}, {}
        for _, effect in ipairs(definitions) do
            if characterLevel >= (tonumber(effect.min_level) or 1) then
                available[#available + 1] = effect
                local group = effect.group or ""
                if effect.enabled ~= false and (group == "" or groups[group] == nil) then
                    selected[effect.id] = true
                    if group ~= "" then groups[group] = effect.id end
                end
            end
        end
        if #available == 0 then
            selectTarget(menu, sheet, action, level, {})
            return
        end
        local function draw()
            local rows = {}
            for _, effect in ipairs(available) do
                local prefix = selected[effect.id] and "[x] " or "[ ] "
                rows[#rows + 1] = button(prefix .. safeText(effect.name) .. " \194\183 " .. safeText(effect.dice),
                    WIDTH - 40, function()
                        if not active(menu) then return end
                        local group = effect.group or ""
                        if group ~= "" and not selected[effect.id] then
                            for _, other in ipairs(available) do
                                if other.group == group then selected[other.id] = nil end
                            end
                        end
                        selected[effect.id] = not selected[effect.id]
                        draw()
                    end)
            end
            show(menu, "\208\173\209\132\209\132\208\181\208\186\209\130\209\139 \194\183 " .. safeText(action.name), {
                menuRows(rows, 186),
                button("\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \209\134\208\181\208\187\209\140", WIDTH - 20, function()
                    local ids = {}
                    for _, effect in ipairs(available) do
                        if selected[effect.id] then ids[#ids + 1] = effect.id end
                    end
                    selectTarget(menu, sheet, action, level, ids)
                end),
                button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openActions(menu, sheet, action.kind) end),
            })
        end
        draw()
    end
    local level = tonumber(action.level) or 0
    if level == 0 or action.kind == "attack" then prepare(0) return end
    local levels, onlyLevel = {}, nil
    for n = level, (action.upcast_allowed == false and level or 9) do
        local slot = slots[tostring(n)] or slots[n]
        local remaining = type(slot) == "table" and (tonumber(slot.max) or 0) - (tonumber(slot.used) or 0)
        if remaining and remaining > 0 then
            local chosenLevel = n
            onlyLevel = chosenLevel
            levels[#levels + 1] = button("\208\175\209\135\208\181\208\185\208\186\208\176 " .. n .. " \194\183 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 " .. remaining,
                WIDTH - 40, function() prepare(chosenLevel) end)
        end
    end
    if #levels == 1 then prepare(onlyLevel) return end
    show(menu, safeText(action.name) .. " \194\183 " .. actionDetails(action), {
        label(#levels > 0 and "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\143\209\135\208\181\208\185\208\186\209\131" or "\208\157\208\181\209\130 \209\129\208\178\208\190\208\177\208\190\208\180\208\189\209\139\209\133 \209\143\209\135\208\181\208\181\208\186.", 13, "#c4b9ed"),
        menuRows(levels), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openActions(menu, sheet, action.kind) end),
    })
    if #levels > 1 and action.map_targeting then
        local preview = {menu = menu, rules = action.map_targeting}
        updateRangeMarker(preview)
        menu.spellRange = preview.rangeMarker
    end
end

local CARD_HEIGHT, CARD_ROW_HEIGHT, LEVEL_HEIGHT = 106, 122, 27

local function actionTile(menu, sheet, action, slots, characterLevel)
    local asset, color = actionIcon(action, action.map_targeting or {})
    local title = safeText(action.name)
    return gui.Button{
        text = "", width = 98, height = CARD_HEIGHT, hmargin = 5, valign = "center", flow = "vertical", halign = "left",
        classes = {"sessionlab-action-tile"}, bgimage = "panels/square.png", bgcolor = "#262338",
        borderWidth = 1, borderColor = "#5e506f", cornerRadius = 8,
        styles = {
            {selectors = {"label", "button", "sessionlab-action-tile", "hover"}, priority = 5,
                bgcolor = "#433456", borderColor = "#c3a8ed", brightness = 1},
            {selectors = {"label", "button", "sessionlab-action-tile", "press"}, priority = 6,
                brightness = 1},
        },
        press = function() if active(menu) then chooseAction(menu, sheet, action, slots, characterLevel) end end,
        swallowPress = true,
        hover = function(element) element.tooltip = title .. " \194\183 " .. actionDetails(action) end,
        gui.Panel{
            width = 51, height = 51, halign = "center", vmargin = 3, interactable = false,
            bgimage = "panels/square.png", bgcolor = "#342744", cornerRadius = 8,
            borderColor = "#806a96", borderWidth = 1,
            iconPanel(asset, color, asset and 43 or 25),
        },
        gui.Label{width = 90, height = 31, fontSize = 11, textWrap = true, textAlignment = "center",
            halign = "center", text = title, color = "#f5eafa", interactable = false},
        gui.Label{width = 90, height = 16, fontSize = 10, textAlignment = "center",
            halign = "center", text = action.range or "", color = "#c4b9d0", interactable = false},
    }
end

local function openEffectEditor(menu, action, back)
    if not active(menu) or not tokenStillControlled(menu) then return end
    local scope, actionId = menu.context, id(action.id)
    local page, uploading, draw
    local function current()
        return active(menu) and menu.page == page and tokenStillControlled(menu)
    end

    local function upload()
        if not current() or uploading then return end
        local uploadAsset = assets and assets.UploadImageAsset
        if type(uploadAsset) ~= "function" or type(dmhub.OpenFileDialog) ~= "function" then
            draw("\208\146 \209\141\209\130\208\190\208\185 \208\178\208\181\209\128\209\129\208\184\208\184 DMHub \208\183\208\176\208\179\209\128\209\131\208\183\208\186\208\176 \208\178\208\184\208\180\208\181\208\190 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\176.")
            return
        end
        dmhub.OpenFileDialog{
            id = "SessionLabActionAnimation", extensions = {"webm"},
            prompt = "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\209\142 WebM",
            open = function(path)
                if not current() or uploading then return end
                if type(path) ~= "string" or not path:lower():match("%.webm$") then
                    draw("\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\132\208\176\208\185\208\187 WebM.")
                    return
                end
                local name = safeText(path:match("[^/\\]+$") or "WebM")
                local finished = false
                uploading = true
                draw("\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176 \208\178\208\184\208\180\208\181\208\190 \208\178 DMHub\226\128\166")
                local uploadPage = page
                local function stillEditing()
                    return page == uploadPage and current()
                end
                local function fail(message)
                    if finished then return end
                    finished, uploading = true, false
                    if stillEditing() then draw("DMHub \208\189\208\181 \208\183\208\176\208\179\209\128\209\131\208\183\208\184\208\187 \208\178\208\184\208\180\208\181\208\190. " .. safeText(message)) end
                end
                local ok, err = pcall(uploadAsset, {
                    path = path, description = name, error = fail,
                    upload = function(value)
                        if finished then return end
                        local clip = visualFX.assetId(value)
                        if not clip then fail("DMHub \208\189\208\181 \208\178\208\181\209\128\208\189\209\131\208\187 ID \208\178\208\184\208\180\208\181\208\190.") return end
                        finished, uploading = true, false
                        if context() ~= scope or rawget(_G, RUNTIME) ~= state then return end
                        if stillEditing() then
                            visualFX.save(scope, actionId, clip, clip, name)
                            draw("\208\146\208\184\208\180\208\181\208\190 \208\189\208\176\208\183\208\189\208\176\209\135\208\181\208\189\208\190.")
                        else
                            visualFX.save(scope, nil, nil, clip, name)
                        end
                    end,
                })
                if not ok then fail(err) end
            end,
        }
    end

    draw = function(message)
        local clips = visualFX.library(scope)
        local choice = visualFX.choice(scope, actionId)
        local selectedClip = visualFX.assetId(choice)
        local function option(caption, value)
            return button((choice == value and "\226\156\147 " or "") .. caption, WIDTH - 40, function()
                if current() and not uploading then
                    visualFX.save(scope, actionId, value)
                    draw("\208\144\208\189\208\184\208\188\208\176\209\134\208\184\209\143 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\176.")
                end
            end)
        end
        local options = {option("\208\159\208\190 \208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\181 \208\187\208\184\209\129\209\130\208\176", nil), option("\208\145\208\181\208\183 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\208\184", "none")}
        for _, preset in ipairs(visualFX.presets) do
            options[#options + 1] = option(preset.label, preset.id)
        end
        local keys = {}
        for clip in pairs(clips) do keys[#keys + 1] = clip end
        table.sort(keys, function(a, b)
            if clips[a] == clips[b] then return a < b end
            return clips[a] < clips[b]
        end)
        for _, clip in ipairs(keys) do options[#options + 1] = option(safeText(clips[clip]), clip) end
        local input = gui.Input{
            width = WIDTH - 20, height = 28, halign = "center", fontSize = 13,
            text = "", placeholderText = "ID \208\178\208\184\208\180\208\181\208\190 \208\184\208\183 \209\141\209\130\208\190\208\185 \208\184\208\179\209\128\209\139 DMHub",
        }
        local content = {
            label(actionDetails(action), 12, "#bfb2f4"),
            label("\208\161\208\181\208\185\209\135\208\176\209\129: " .. safeText(visualFX.choiceLabel(choice, clips)), 13, "#f5ecff"),
            menuRows(options, 155),
            button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 WebM \208\184 \208\189\208\176\208\183\208\189\208\176\209\135\208\184\209\130\209\140", WIDTH - 20, upload, "#514479"),
            input,
            button("\208\157\208\176\208\183\208\189\208\176\209\135\208\184\209\130\209\140 \208\191\208\190 ID", WIDTH - 20, function()
                if not current() or uploading then return end
                local clip = visualFX.assetId(input.text)
                if not clip then draw("\208\146\208\178\208\181\208\180\208\184\209\130\208\181 ID \209\131\208\182\208\181 \208\183\208\176\208\179\209\128\209\131\208\182\208\181\208\189\208\189\208\190\208\179\208\190 \208\178 \208\184\208\179\209\128\209\131 \208\178\208\184\208\180\208\181\208\190.") return end
                visualFX.save(scope, actionId, clip, clip, clips[clip] or clip)
                draw("\208\146\208\184\208\180\208\181\208\190 \208\189\208\176\208\183\208\189\208\176\209\135\208\181\208\189\208\190.")
            end),
            button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, back),
        }
        if selectedClip then
            table.insert(content, #content, button("\208\161\208\186\208\190\208\191\208\184\209\128\208\190\208\178\208\176\209\130\209\140 ID \208\178\208\184\208\180\208\181\208\190", WIDTH - 20, function()
                if not current() then return end
                if type(dmhub.CopyToClipboard) == "function" then
                    dmhub.CopyToClipboard(selectedClip)
                    draw("ID \208\178\208\184\208\180\208\181\208\190 \209\129\208\186\208\190\208\191\208\184\209\128\208\190\208\178\208\176\208\189.")
                else
                    input.text = selectedClip
                end
            end))
        end
        if message then table.insert(content, 3, label(message, 12, "#f5c592")) end
        show(menu, safeText(action.name), content)
        page = menu.page
    end
    draw()
end

local function openEffectActions(menu, actions, back)
    if not active(menu) or not tokenStillControlled(menu) then return end
    local clips, rows = visualFX.library(menu.context), {}
    for _, action in ipairs(actions) do
        local choice = visualFX.choice(menu.context, id(action.id))
        rows[#rows + 1] = button(
            safeText(action.name) .. " \194\183 " .. safeText(visualFX.choiceLabel(choice, clips)),
            WIDTH - 40,
            function()
                openEffectEditor(menu, action, function() openEffectActions(menu, actions, back) end)
            end
        )
    end
    show(menu, "\208\144\208\189\208\184\208\188\208\176\209\134\208\184\208\184 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\185", {
        menuRows(rows, 248), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, back),
    })
end


local function openAttackIcons(menu, sheet, actions, back)
    local choices = {
        {"\208\144\209\130\208\176\208\186\208\176 \208\186\208\187\208\184\208\189\208\186\208\176\208\188\208\184", "1"}, {"\208\145\208\190\208\181\208\178\208\190\208\185 \209\130\208\190\208\191\208\190\209\128", "skill_62"},
        {"\208\146\209\139\208\191\208\176\208\180 \208\186\208\184\208\189\208\182\208\176\208\187\208\190\208\188", "skill_74"}, {"\208\163\208\180\208\176\209\128 \208\186\208\190\208\191\209\140\209\145\208\188", "spear_hit"},
        {"\208\156\208\190\209\137\208\189\209\139\208\185 \208\186\209\131\208\187\208\176\208\186", "skill_58"}, {"\208\163\208\180\208\176\209\128 \208\191\208\190\209\129\208\190\209\133\208\190\208\188", "skill_81"},
        {"\208\162\208\190\209\135\208\189\209\139\208\185 \208\191\209\128\208\184\209\134\208\181\208\187", "skill_80"}, {"\208\147\209\128\208\176\208\180 \209\129\209\130\209\128\208\181\208\187", "skill_73"},
        {"\208\163\208\180\208\176\209\128 \208\186\208\190\208\179\209\130\209\143\208\188\208\184", "claw_strike"}, {"\208\163\208\186\209\131\209\129", "fishbite"},
        {"\208\175\208\180\208\190\208\178\208\184\209\130\208\190\208\181 \208\182\208\176\208\187\208\190", "venom"}, {"\208\158\208\179\208\189\208\181\208\189\208\189\209\139\208\185 \209\136\208\176\209\128", "03_fireball"},
        {"\208\156\208\190\208\187\208\189\208\184\209\143", "25_Lightning"}, {"\208\161\208\184\209\143\209\142\209\137\208\184\208\185 \208\188\208\181\209\135", "Skill_242"},
    }
    if not active(menu) or not tokenStillControlled(menu) then return end
    local function edit(action)
        if not active(menu) or not tokenStillControlled(menu) then return end
        local asset = (action.map_settings or {}).icon_asset or ""
        local saving, page, draw
        local function current()
            return active(menu) and menu.page == page and tokenStillControlled(menu)
        end
        local function save(input)
            if not current() or saving then return end
            local value = input.text:match("^%s*(.-)%s*$")
            local validPath = value:match("^ui%-icons/[%w_/%-]+%.png$")
                or value:match("^game%-icons/[%w_/%-]+%.png$")
            if value ~= "" and (#value > 160 or not (validPath or visualFX.assetId(value))) then
                draw("\208\163\208\186\208\176\208\182\208\184\209\130\208\181 ID \208\184\208\183\208\190\208\177\209\128\208\176\208\182\208\181\208\189\208\184\209\143 \208\184\208\187\208\184 \208\191\209\131\209\130\209\140 \208\186 PNG \208\184\208\183 \208\179\208\176\208\187\208\181\209\128\208\181\208\184 DMHub.")
                return
            end
            local settings = {}
            for key, previous in pairs(action.map_settings or {}) do settings[key] = previous end
            settings.icon_asset = value
            local sheetId, actionId, version = id(sheet), id(action.id), tonumber(action.version)
            if not sheetId or not actionId or not version then
                draw("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\191\209\128\208\190\209\135\208\184\209\130\208\176\209\130\209\140 \208\178\208\181\209\128\209\129\208\184\209\142 \208\176\209\130\208\176\208\186\208\184. \208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\181\209\145 \208\183\208\176\208\189\208\190\208\178\208\190.")
                return
            end
            saving, asset = true, value
            draw("\208\161\208\190\209\133\209\128\208\176\208\189\209\143\209\142 \208\184\208\186\208\190\208\189\208\186\209\131\226\128\166")
            request(SHEETS .. sheetId .. "/abilities/" .. actionId .. "/edit/",
                {version = version, map_settings = settings}, "sl-icon-" .. dmhub.GenerateGuid(),
                function()
                    if current() then back() end
                end, function(message)
                    saving = false
                    if current() then draw(message) end
                end)
        end
        draw = function(message)
            local input = gui.Input{width = WIDTH - 20, height = 28, halign = "center", fontSize = 12,
                text = asset, placeholderText = "ID \208\184\208\187\208\184 \208\191\209\131\209\130\209\140 \208\186 \208\184\208\186\208\190\208\189\208\186\208\181 DMHub"}
            local rows = {}
            for index = 1, #choices, 3 do
                local tiles = {}
                for i = index, math.min(index + 2, #choices) do
                    local name, filename = choices[i][1], choices[i][2]
                    local key = "ui-icons/skills/" .. filename .. ".png"
                    local image = builtinImageIds[key]
                    if image then
                        tiles[#tiles + 1] = gui.Button{
                            text = "", width = 99, height = 66, hmargin = 4, flow = "vertical",
                            bgimage = "panels/square.png", bgcolor = key == asset and "#514479" or "#262338",
                            cornerRadius = 5, swallowPress = true,
                            press = function()
                                if current() and not saving then asset = key draw() end
                            end,
                            iconPanel(image, "white", 37),
                            gui.Label{text = name, width = 95, height = 25, textWrap = true,
                                fontSize = 10, textAlignment = "center", interactable = false},
                        }
                    end
                end
                rows[#rows + 1] = gui.Panel{width = WIDTH - 26, height = 73,
                    flow = "horizontal", halign = "center", children = tiles}
            end
            local content = {
                scrollList(rows, WIDTH - 20, 221, #rows * 73),
                input,
                button("\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140 \208\184\208\186\208\190\208\189\208\186\209\131", WIDTH - 20, function() save(input) end, "#514479"),
                button("\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \209\129\208\178\208\190\209\142 \208\184\208\186\208\190\208\189\208\186\209\131", WIDTH - 20, function()
                    if current() and not saving then asset = "" draw() end
                end),
                button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function()
                    if not saving then openAttackIcons(menu, sheet, actions, back) end
                end),
            }
            if message then table.insert(content, 1, label(message, 12, "#f5c592")) end
            show(menu, "\208\152\208\186\208\190\208\189\208\186\208\176 \194\183 " .. safeText(action.name), content)
            page = menu.page
        end
        draw()
    end
    local rows = {}
    for _, action in ipairs(actions) do
        rows[#rows + 1] = button(safeText(action.name), WIDTH - 40, function() edit(action) end)
    end
    show(menu, "\208\152\208\186\208\190\208\189\208\186\208\184 \208\176\209\130\208\176\208\186", {menuRows(rows, 248), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, back)})
end

openActions = function(menu, sheet, kind)
    menu.section = kind
    local title = kind == "spell" and "\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143" or "\208\144\209\130\208\176\208\186\208\184"
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\209\143\226\128\166", {})
    local page = menu.page
    local function current() return active(menu) and menu.page == page end
    request(SHEETS .. sheet .. "/", nil, nil, function(data)
        if not current() then return end
        local groups, rows, actions, height = {}, {}, {}, 0
        local slots = data.sheet and data.sheet.slots or {}
        local characterLevel = tonumber(data.character and data.character.level) or 1
        for _, action in ipairs(data.actions or {}) do
            if action.kind == kind and id(action.id) then
                local level = tonumber(action.level) or 0
                groups[level] = groups[level] or {}
                table.insert(groups[level], action)
                actions[#actions + 1] = action
            end
        end
        for level = 0, 9 do
            local group = groups[level]
            if group then
                if kind == "spell" then
                    rows[#rows + 1] = gui.Label{
                        text = level == 0 and "\208\151\208\144\208\147\208\158\208\146\208\158\208\160\208\171" or ("\208\163\208\160\208\158\208\146\208\149\208\157\208\172 " .. level),
                        width = WIDTH - 34, height = LEVEL_HEIGHT, halign = "center", textAlignment = "left",
                        fontSize = 12, color = "#ddbc91", interactable = false,
                    }
                    height = height + LEVEL_HEIGHT
                end
                for i = 1, #group, 3 do
                    local tiles = {}
                    for j = i, math.min(i + 2, #group) do
                        tiles[#tiles + 1] = actionTile(menu, sheet, group[j], slots, characterLevel)
                    end
                    rows[#rows + 1] = gui.Panel{width = WIDTH - 26, height = CARD_ROW_HEIGHT, flow = "horizontal",
                        halign = "center", children = tiles}
                    height = height + CARD_ROW_HEIGHT
                end
            end
        end
        if #rows == 0 then show(menu, "\208\146 \208\187\208\184\209\129\209\130\208\181 \208\191\208\190\208\186\208\176 \208\189\208\181\209\130 \209\130\208\176\208\186\208\184\209\133 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\185.", {}) return end
        local function reload() openActions(menu, sheet, kind) end
        local content = {
            button("\208\157\208\176\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\176\208\189\208\184\208\188\208\176\209\134\208\184\208\184", WIDTH - 20, function()
                openEffectActions(menu, actions, reload)
            end),
        }
        if kind == "attack" then
            content[#content + 1] = button("\208\157\208\176\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\184\208\186\208\190\208\189\208\186\208\184", WIDTH - 20, function()
                openAttackIcons(menu, sheet, actions, reload)
            end)
        end
        content[#content + 1] = scrollList(rows, WIDTH - 12, math.min(kind == "attack" and 275 or 306, height), height)
        show(menu, title, content)
    end, function(message)
        if current() then
            show(menu, message, {button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 \208\181\209\137\209\145 \209\128\208\176\208\183", WIDTH - 20, function() openActions(menu, sheet, kind) end)})
        end
    end)
end

local function removeVitals(hud, token)
    local panel = hud.panels[token]
    hud.panels[token] = nil
    if panel and panel.valid then panel:DestroySelf() end
end

local function hudState()
    local scope = context()
    local hud = state.hud
    if hud and hud.context ~= scope then
        for token in pairs(hud.panels) do removeVitals(hud, token) end
        state.hud = nil
    end
    if not state.hud and scope then
        local preferences = dmhub.GetSettingValue(HUD_PREFERENCES)
        if type(preferences) ~= "table" then preferences = {} end
        state.hud = {context = scope, all = preferences.all ~= false,
            hidden = type(preferences.hidden) == "table" and preferences.hidden or {}, panels = {}}
    end
    return state.hud
end

local function vitalsEnabled(hud, token)
    return hud.all and hud.hidden[token] ~= true
end

local function saveVitalsPreferences(hud)
    dmhub.SetSettingValue(HUD_PREFERENCES, {all = hud.all, hidden = hud.hidden})
end

local function vitalsCurrent(hud)
    return rawget(_G, RUNTIME) == state and state.hud == hud and context() == hud.context
end

local function showVitals(hud, tokenId, row)
    local token = dmhub.GetTokenById(tokenId)
    local sheet = token and token.valid and token.onBoard ~= false and token.sheet
    local hp, maxHp, ac = tonumber(row.hp_current), tonumber(row.hp_max), tonumber(row.armor_class)
    if not sheet or not sheet.valid or not hp or not maxHp or not ac then
        removeVitals(hud, tokenId)
        return
    end
    local ratio = math.max(0, math.min(1, hp / math.max(1, maxHp)))
    local temp = math.max(0, tonumber(row.hp_temp) or 0)
    local hpText = string.format("%.0f / %.0f", hp, maxHp)
    local acText = "\208\154\208\148 " .. string.format("%.0f", ac)
    local panel = hud.panels[tokenId]
    local function update(element)
        local fill, shield = element.data.fill, element.data.shield
        local health, armor = element.data.health, element.data.armor
        local width = math.floor(93 * ratio + 0.5)
        local shieldWidth = math.min(93, math.floor(93 * temp / math.max(1, maxHp) + 0.5))
        fill.selfStyle.width = width
        shield.selfStyle.width = shieldWidth
        fill:SetClass("collapsed", width == 0)
        shield:SetClass("collapsed", shieldWidth == 0)
        if health.text ~= hpText then health.text = hpText end
        if armor.text ~= acText then armor.text = acText end
    end
    if panel and panel.valid and panel.parent == sheet then update(panel) return end
    removeVitals(hud, tokenId)
    local fill = gui.Panel{width = 0, height = 12, halign = "left", valign = "top",
        bgimage = "panels/square.png", bgcolor = "#55d68b", cornerRadius = 3, interactable = false}
    local shield = gui.Panel{width = 0, height = 2, halign = "left", valign = "bottom",
        bgimage = "panels/square.png", bgcolor = "#70ccff", interactable = false}
    local health = gui.Label{width = 93, height = 14, fontSize = 10, bold = true,
        halign = "center", valign = "center", textAlignment = "center",
        color = "#ffffff", textOutlineColor = "#132b21", textOutlineWidth = 0.3,
        text = hpText, interactable = false}
    local armor = gui.Label{width = 34, height = 15, fontSize = 10, textAlignment = "center",
        valign = "center", color = "#f2efff", text = acText, interactable = false}
    panel = gui.Panel{
        floating = true, halign = "center", valign = "bottom", y = 16, flow = "horizontal",
        width = 135, height = 15, hpad = 4,
        bgimage = "panels/square.png", bgcolor = "#17192be8", cornerRadius = 5,
        interactable = false, blocksGameInteraction = false, data = {fill = fill, shield = shield, health = health, armor = armor},
        thinkTime = 0.5,
        think = function(element) if not vitalsCurrent(hud) then element:DestroySelf() end end,
        gui.Panel{width = 93, height = 12, valign = "center", flow = "none",
            bgimage = "panels/square.png", bgcolor = "#2b3544", cornerRadius = 3,
            interactable = false, fill, shield, health},
        armor,
    }
    update(panel)
    hud.panels[tokenId] = panel
    sheet:AddChild(panel)
end

local function pollVitals(hud)
    if not vitalsCurrent(hud) or hud.busy or not hud.all or not personalKey() then return end
    hud.busy = true
    hud.poll = (hud.poll or 0) + 1
    local revision, poll = hud.revision, hud.poll
    local function current()
        return vitalsCurrent(hud) and revision == hud.revision and poll == hud.poll
    end
    local function finish()
        hud.busy = false
        if not vitalsCurrent(hud) then return end
        if revision ~= hud.revision then pollVitals(hud) return end
        if hud.timer then return end
        hud.timer = true
        dmhub.Schedule(7, function()
            hud.timer = false
            pollVitals(hud)
        end)
    end
    tokenScene(function(scene)
        if not current() then finish() return end
        hud.error = nil
        local mapped, keep = {}, {}
        for _, row in ipairs(scene.targets or {}) do
            if type(row.token) == "string" and row.token ~= "" then
                mapped[row.token] = row
                if vitalsEnabled(hud, row.token) then
                    showVitals(hud, row.token, row)
                    keep[row.token] = true
                end
            end
        end
        local prefix = hud.context .. "|"
        for key, binding in pairs(allBindings()) do
            if type(key) == "string" and key:sub(1, #prefix) == prefix then
                local tokenId = key:sub(#prefix + 1)
                local sheetId = type(binding) == "table" and id(binding.sheet)
                local token = sheetId and not mapped[tokenId] and vitalsEnabled(hud, tokenId)
                    and dmhub.GetTokenById(tokenId)
                if controlled(token) and token.onBoard ~= false then
                    keep[tokenId] = true
                    request(SHEETS .. sheetId .. "/", nil, nil, function(data)
                        if current() then
                            if type(data.sheet) == "table" then showVitals(hud, tokenId, data.sheet)
                            else removeVitals(hud, tokenId) end
                        end
                    end, function()
                        if current() then removeVitals(hud, tokenId) end
                    end)
                end
            end
        end
        for tokenId in pairs(hud.panels) do
            if not keep[tokenId] then removeVitals(hud, tokenId) end
        end
        finish()
    end, function(message)
        if current() then
            hud.error = message
            for tokenId in pairs(hud.panels) do removeVitals(hud, tokenId) end
        end
        finish()
    end)
end

refreshVitals = function()
    local hud = hudState()
    if not hud then return end
    hud.revision = (hud.revision or 0) + 1
    pollVitals(hud)
end

local function setBuiltinActionBar(hidden)
    if type(dmhub.GetSettingValue(BUILTIN_ACTION_BAR)) ~= "boolean" then return false end
    if dmhub.GetSettingValue(BUILTIN_ACTION_BAR) ~= hidden then
        dmhub.SetSettingValue(BUILTIN_ACTION_BAR, hidden)
    end
    return true
end

local function settingsPage(menu)
    if not active(menu) then return end
    menu.section = "settings"
    local hud = hudState()
    local mapped = mappedTarget(menu.scene, menu.token)
    local enabled = vitalsEnabled(hud, menu.token)
    local rows = {}
    if hud.all and sheetBinding(menu) then
        rows[#rows + 1] = button(enabled and "\208\161\208\186\209\128\209\139\209\130\209\140 \208\165\208\159 \208\184 \208\154\208\148 \209\130\208\190\208\186\208\181\208\189\208\176" or "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\165\208\159 \208\184 \208\154\208\148 \209\130\208\190\208\186\208\181\208\189\208\176",
            WIDTH - 20, function()
                if not active(menu) then return end
                hud.hidden[menu.token] = enabled or nil
                saveVitalsPreferences(hud)
                if enabled then removeVitals(hud, menu.token) end
                refreshVitals()
                settingsPage(menu)
            end)
    end
    rows[#rows + 1] = button(hud.all and "\208\161\208\186\209\128\209\139\209\130\209\140 \208\178\209\129\208\181 \208\165\208\159 \208\184 \208\154\208\148" or "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\178\209\129\208\181 \208\165\208\159 \208\184 \208\154\208\148",
        WIDTH - 20, function()
            if not active(menu) then return end
            hud.all = not hud.all
            saveVitalsPreferences(hud)
            if not hud.all then
                for tokenId in pairs(hud.panels) do removeVitals(hud, tokenId) end
            end
            refreshVitals()
            settingsPage(menu)
        end)
    if menu.scene and menu.scene.is_dm then
        rows[#rows + 1] = button("\208\166\208\181\208\187\209\140 \209\129\209\134\208\181\208\189\209\139", WIDTH - 20, function() sceneBinding(menu) end)
    end
    if not mapped or not id(mapped.sheet) then
        rows[#rows + 1] = button(sheetBinding(menu) and "\208\161\208\188\208\181\208\189\208\184\209\130\209\140 \208\187\208\184\209\129\209\130" or "\208\159\209\128\208\184\208\178\209\143\208\183\208\176\209\130\209\140 \208\187\208\184\209\129\209\130", WIDTH - 20,
            function() chooseSheet(menu) end)
    end
    local barHidden = dmhub.GetSettingValue(BUILTIN_ACTION_BAR)
    if type(barHidden) == "boolean" then
        rows[#rows + 1] = button(barHidden and "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\191\208\176\208\189\208\181\208\187\209\140 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\185 DMHub" or "\208\161\208\186\209\128\209\139\209\130\209\140 \208\191\208\176\208\189\208\181\208\187\209\140 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\185 DMHub",
            WIDTH - 20, function()
                if not active(menu) or not setBuiltinActionBar(not barHidden) then return end
                dmhub.SetSettingValue(HIDE_ACTION_BAR, not barHidden)
                settingsPage(menu)
            end)
    end
    if enabled or hud.all then
        rows[#rows + 1] = gui.Label{
            text = "", width = WIDTH - 20, height = "auto", halign = "center",
            textWrap = true, interactable = false, fontSize = 12, color = "#b6accd",
            thinkTime = 0.5,
            think = function(element)
                if not active(menu) then return end
                local text = hud.error
                if not text then
                    if hud.panels[menu.token] then text = "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184 \208\191\208\190\208\180 \209\130\208\190\208\186\208\181\208\189\208\190\208\188"
                    elseif hud.busy then text = "\208\158\208\177\208\189\208\190\208\178\208\187\209\143\209\142 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184\226\128\166"
                    elseif hud.all and not enabled then text = "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184 \209\129\209\134\208\181\208\189\209\139 \208\178\208\186\208\187\209\142\209\135\208\181\208\189\209\139"
                    else text = "\208\148\208\187\209\143 \209\130\208\190\208\186\208\181\208\189\208\176 \208\189\208\181\209\130 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139\209\133 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\181\208\185. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131 \208\187\208\184\209\129\209\130\208\176." end
                end
                if element.text ~= text then element.text = text end
            end,
        }
    end
    show(menu, "\208\162\208\190\208\186\208\181\208\189 \208\184 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184", rows)
end

local function checkRows(menu, sheet, kind, entries)
    local rows = {}
    local function makeCheck(check)
        return button(check[2], WIDTH - 40, function()
            if not active(menu) or (state.pending and state.pending.sending) then return end
            local job = {
                path = SHEETS .. sheet .. "/roll/", body = {kind = kind, key = check[1]},
                label = check[2], binding = bindingKey(menu), context = menu.context,
                key = "sl-token-" .. dmhub.GenerateGuid(),
            }
            state.pending = job
            sendRoll(menu, job)
        end)
    end
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = makeCheck(entry)
    end
    return rows
end

local tabs = {
    {"skill", "\208\157\208\176\208\178\209\139\208\186\208\184"}, {"ability", "\208\165\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\184"},
    {"save", "\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\184"}, {"spell", "\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143"}, {"attack", "\208\144\209\130\208\176\208\186\208\184"},
    {"settings", "\208\162\208\190\208\186\208\181\208\189 \208\184 \208\165\208\159 / \208\154\208\148"},
}

openSkills = function(menu, kind)
    if not active(menu) then return end
    local pending = state.pending
    if pending and pending.binding == bindingKey(menu) then
        rollStatus(menu, pending)
        return
    end
    local binding = sheetBinding(menu)
    local sheet = type(binding) == "table" and id(binding.sheet)
    if not sheet then
        settingsPage(menu)
        return
    end
    menu.section = kind or "skill"
    local names = {skill = "\208\157\208\176\208\178\209\139\208\186\208\184", ability = "\208\165\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\184", save = "\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\184"}
    local rows = checkRows(menu, sheet, menu.section, menu.section == "skill" and skills or abilities)
    show(menu, names[menu.section] .. " \194\183 " .. safeText(binding.name), {menuRows(rows)})
end

chooseSheet = function(menu)
    if not active(menu) then return end
    menu.section = "settings"
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139\208\181 \208\187\208\184\209\129\209\130\209\139\226\128\166", {})
    local page = menu.page
    local function current()
        return active(menu) and menu.page == page
    end
    request(SHEETS, nil, nil, function(result)
        if not current() then return end
        local function bind(binding)
            if not active(menu) or not tokenStillControlled(menu) then return end
            local function save(value)
                if not active(menu) then return end
                if menu.scene then menu.scene.binding = result.is_dm and value or nil end
                writeBinding(menu, value)
                removeVitals(hudState(), menu.token)
                refreshVitals()
                openSkills(menu)
            end
            if not result.is_dm then save(binding) return end
            show(menu, "\208\161\208\190\209\133\209\128\208\176\208\189\209\143\209\142 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131\226\128\166", {})
            local page = menu.page
            request(TOKEN_SCENE, {command = "bind", game = dmhub.gameid, token = menu.token,
                sheet = binding and tonumber(binding.sheet) or 0}, "sl-bind-" .. dmhub.GenerateGuid(),
                function(response)
                    if active(menu) and menu.page == page then save(response.binding) end
                end, function(message)
                    if active(menu) and menu.page == page then
                        show(menu, message, {button("\208\154 \209\129\208\191\208\184\209\129\208\186\209\131 \208\187\208\184\209\129\209\130\208\190\208\178", WIDTH - 20, function() chooseSheet(menu) end)})
                    end
                end)
        end
        local rows = {}
        for _, character in ipairs(result.characters or {}) do
            local sheet = id(character.id)
            local name = safeText(character.name)
            if sheet then
                rows[#rows + 1] = button(name .. " \194\183 #" .. sheet, WIDTH - 40, function()
                    bind({sheet = sheet, name = name})
                end)
            end
        end
        if #rows == 0 then
            show(menu, "\208\157\208\181\209\130 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139\209\133 \208\187\208\184\209\129\209\130\208\190\208\178 \208\178 \208\186\208\176\208\188\208\191\208\176\208\189\208\184\208\184 SessionLab", {
                button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
            })
            return
        end
        local content = {
            menuRows(rows, 248),
        }
        if sheetBinding(menu) then
            content[#content + 1] = button("\208\158\209\130\208\178\209\143\208\183\208\176\209\130\209\140 \208\187\208\184\209\129\209\130", WIDTH - 20, function() bind(nil) end)
        end
        content[#content + 1] = button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)
        show(menu, "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\187\208\184\209\129\209\130 SessionLab", content)
    end, function(message)
        if not current() then return end
        show(menu, message, {
            button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 \208\181\209\137\209\145 \209\128\208\176\208\183", WIDTH - 20, function() chooseSheet(menu) end),
            button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
        })
    end)
end

local radialPositions = {{-100, -14}, {-76, -66}, {-29, -97}, {29, -97}, {76, -66}, {100, -14}}

local function closeRadial()
    local radial = state.radial
    state.radial = nil
    if not radial or not radial.panel.valid then return end
    if radial.anchor.valid and radial.anchor.popup == radial.panel then
        radial.anchor.popup = nil
    end
    if radial.panel.valid then radial.panel:DestroySelf() end
end

local function openRadial(token)
    local anchor = token.sheet
    if not anchor or not anchor.valid then return false end
    local current = state.radial
    if current and current.anchor == anchor and current.panel.valid and anchor.popup == current.panel then
        return true
    end
    closeRadial()
    if state.menu then close(state.menu) end
    local scope = context()
    local buttons = {}
    for index, tab in ipairs(tabs) do
        local kind, title = tab[1], tab[2]
        local pos = radialPositions[index]
        buttons[#buttons + 1] = gui.Panel{
            floating = true, halign = "center", valign = "center", x = pos[1], y = pos[2],
            width = 40, height = 40, cornerRadius = 20, borderWidth = 2,
            borderColor = kind == "spell" and "#d3b6ff" or "#e8c38c",
            bgimage = "panels/square.png", bgcolor = "#211b2bf4",
            styles = {{selectors = {"hover"}, bgcolor = "#59436a", scale = 1.08, transitionTime = 0.1}},
            hover = function(element) element.tooltip = title end,
            press = function()
                closeRadial()
                openTokenMenu(token, kind)
            end,
            swallowPress = true,
            iconPanel(icons[kind], kind == "spell" and "#d3b6ff" or "#f4d4a3", 23),
        }
    end
    local panel = gui.Panel{
        width = 8, height = 8, halign = "center", valign = "center", flow = "none",
        blocksGameInteraction = false, captureEscape = true,
        escape = closeRadial, thinkTime = 0.4,
        think = function()
            if rawget(_G, RUNTIME) ~= state or context() ~= scope or not controlled(token)
                or token.onBoard == false or token.sheet ~= anchor then
                closeRadial()
            end
        end,
        destroy = function(element)
            if state.radial and state.radial.panel == element then state.radial = nil end
        end,
        children = buttons,
    }
    state.radial = {token = token.charid, anchor = anchor, panel = panel}
    anchor.popupPositioning = "panel"
    anchor.popup = panel
    return true
end

tokenClick = function(token)
    if rawget(_G, RUNTIME) ~= state or not state.targeting then return false end
    return mapTargetClick(token)
end

openTokenMenu = function(token, kind)
    clearTargeting()
    local hud = getHud()
    local host = hud and hud.dialogWorldPanel
    local scope = context()
    if not host or not scope then
        report("\208\161\208\189\208\176\209\135\208\176\208\187\208\176 \208\190\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\209\131 DMHub.")
        return
    end
    if state.menu then close(state.menu) end
    local menu = {context = scope, host = host, token = token.charid, name = safeText(token.description),
        initialSection = kind, map = token.mapid}
    openMenuForToken(menu)
end

local function openMenu(args)
    if not personalKey() then connection.open(URL) return end
    local fromSelection = type(args) == "string" and args:match("^%s*selected%s*$")
    local token
    if not fromSelection then
        local ok, hovered = pcall(function() return dmhub.tokenHovered end)
        if ok and controlled(hovered) then token = hovered end
    end
    if not token then
        local selected = dmhub.selectedTokens or {}
        if #selected == 1 and selected[1].valid then
            token = dmhub.GetTokenById(selected[1].charid)
        end
    end
    if not controlled(token) or token.isObject or token.onBoard == false then
        report("\208\157\208\176\208\178\208\181\208\180\208\184\209\130\208\181\209\129\209\140 \208\189\208\176 \209\129\208\178\208\190\208\185 \209\130\208\190\208\186\208\181\208\189 \208\184\208\187\208\184 \208\178\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \208\181\208\179\208\190 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181.")
        return
    end
    clearTargeting()
    if state.radial and state.radial.token == token.charid and state.radial.panel.valid then
        closeRadial()
    elseif not openRadial(token) then
        report("\208\162\208\190\208\186\208\181\208\189 \208\191\208\190\208\186\208\176 \208\189\208\181 \208\179\208\190\209\130\208\190\208\178. \208\146\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \208\181\208\179\208\190 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181.")
    end
end

getHud = function()
    local gameHudType = rawget(_G, "GameHud")
    return rawget(_G, "gamehud") or (gameHudType and gameHudType.instance)
end

openPopup = function(menu)
    local saved = dmhub.GetSettingValue(POSITION)
    local x = type(saved) == "table" and tonumber(saved.x) or 30
    local y = type(saved) == "table" and tonumber(saved.y) or 48
    menu.content = gui.Panel{width = WIDTH, height = "auto", flow = "vertical", vpad = 5}
    menu.panel = gui.Panel{
        width = WIDTH, height = "auto", flow = "vertical", halign = "left", valign = "top",
        x = x, y = y, floating = true, draggable = true, dragMove = true,
        bgimage = "panels/square.png", bgcolor = "#17192be8", cornerRadius = 9,
        borderWidth = 1, borderColor = "#514773", vpad = 6,
        constrainToScreen = true, swallowPress = true, captureEscape = true,
        escape = function() close(menu) end,
        drag = function(element)
            element.x, element.y = element.xdrag, element.ydrag
            dmhub.SetSettingValue(POSITION, {x = element.x, y = element.y})
        end,
        destroy = function(element)
            if menu.panel == element then
                clearSpellRange(menu)
                if state.menu == menu then state.menu = nil end
            end
        end,
        children = {
            label("SESSIONLAB  /  " .. menu.name, 15, "#f2efff"),
            label("\208\159\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\208\181 \208\190\208\186\208\189\208\190 \208\183\208\176 \208\183\208\176\208\179\208\190\208\187\208\190\208\178\208\190\208\186", 11, "#b6accd"),
            menu.content,
            button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140", WIDTH - 20, function() close(menu) end),
        },
    }
    state.menu = menu
    menu.host:AddChild(menu.panel)
end

openMenuForToken = function(menu)
    if not active(menu) then openPopup(menu) end
    if not personalKey() then
        close(menu)
        connection.open(URL)
        return
    end
    show(menu, "\208\159\209\128\208\190\208\178\208\181\209\128\209\143\209\142 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131 \209\130\208\190\208\186\208\181\208\189\208\176\226\128\166", {})
    local page = menu.page
    local function landing()
        local kind = menu.initialSection
        local binding = sheetBinding(menu)
        local sheet = type(binding) == "table" and id(binding.sheet)
        if kind == "settings" then settingsPage(menu)
        elseif sheet and (kind == "spell" or kind == "attack") then openActions(menu, sheet, kind)
        else openSkills(menu, kind) end
    end
    tokenScene(function(scene)
        if not active(menu) or menu.page ~= page then return end
        menu.scene = scene
        landing()
    end, function(message)
        if not active(menu) or menu.page ~= page then return end
        menu.scene = nil
        if sheetBinding(menu) then landing() return end
        show(menu, message, {button("\208\159\209\128\208\184\208\178\209\143\208\183\208\176\209\130\209\140 \208\187\208\184\209\129\209\130", WIDTH - 20, function() chooseSheet(menu) end)})
    end, menu.token:match("^[%w_.:%-]+$") and ("&token=" .. menu.token) or nil)
end

connection.onChange("tokens", URL, function()
    clearTargeting()
    closeRadial()
    if state.menu then close(state.menu) end
    if state.enrollment and state.enrollment.valid then state.enrollment:DestroySelf() end
    state.pending = nil
    local hud = state.hud
    if hud then
        for token in pairs(hud.panels) do removeVitals(hud, token) end
        state.hud = nil
    end
    refreshVitals()
end)

local function enrollmentToken(token)
    return controlled(token) and not token.isObject and token.onBoard ~= false
end

local function rosterSearch(text)
    return text:lower():gsub("\208\129", "\209\145"):gsub("\208[\144-\175]", function(letter)
        local code = letter:byte(2)
        return code < 160 and string.char(208, code + 32) or string.char(209, code - 32)
    end)
end

local function openEnrollment(rollInitiative)
    local master = dmhub.isDM == true
    if (not master and not rollInitiative) or not context() then return end
    if not personalKey() then connection.open(URL) return end
    local hud = getHud()
    local host = hud and hud.dialogWorldPanel
    if not host or not host.valid then return end
    local picked, seen = {}, {}
    for _, selected in ipairs(dmhub.selectedTokens or {}) do
        local token = selected.valid and dmhub.GetTokenById(selected.charid)
        if enrollmentToken(token) and not seen[token.charid] then
            local name = safeText(token.description)
            picked[#picked + 1] = {token = token.charid, map = token.mapid, name = name ~= "" and name or token.charid}
            seen[token.charid] = true
        end
    end
    if #picked == 0 or #picked > 50 then
        report("\208\146\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \208\190\209\130 1 \208\180\208\190 50 \209\130\208\190\208\186\208\181\208\189\208\190\208\178 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181.")
        return
    end
    if state.enrollment and state.enrollment.valid then return end
    clearTargeting()
    closeRadial()
    if state.menu then close(state.menu) end
    local scope, panel = context(), nil
    local body = gui.Panel{width = WIDTH, height = "auto", flow = "vertical", vpad = 5}
    local function current()
        return rawget(_G, RUNTIME) == state and context() == scope
            and (dmhub.isDM == true) == master and panel and panel.valid
    end
    local function draw(title, rows)
        if not current() then return end
        local children = {label(title, 14, "#e8defb")}
        for _, row in ipairs(rows or {}) do children[#children + 1] = row end
        body.children = children
    end
    local function closePanel() if panel.valid then panel:DestroySelf() end end
    panel = gui.Panel{
        width = WIDTH, height = "auto", flow = "vertical", halign = "center", valign = "center",
        floating = true, swallowPress = true, captureEscape = true, escape = closePanel,
        bgimage = "panels/square.png", bgcolor = "#17192b", cornerRadius = 9,
        borderWidth = 1, borderColor = "#665587", vpad = 6,
        thinkTime = 0.5, think = function() if not current() then closePanel() end end,
        label(rollInitiative and "SESSIONLAB  /  \208\152\208\157\208\152\208\166\208\152\208\144\208\162\208\152\208\146\208\144" or "SESSIONLAB  /  \208\146 \208\161\208\149\208\161\208\161\208\152\208\174", 15, "#f2efff"), body,
        button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140", WIDTH - 20, closePanel),
    }
    state.enrollment = panel
    host:AddChild(panel)
    draw("\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \209\129\208\190\209\129\209\130\208\176\208\178 \209\129\208\181\209\129\209\129\208\184\208\184\226\128\166")
    tokenScene(function(scene)
        if not current() then return end
        local overview
        local name = "\208\161\208\181\209\129\209\129\208\184\209\143 DMHub"
        local function submit()
            if not current() then return end
            local selection = {}
            for _, row in ipairs(picked) do
                local token = dmhub.GetTokenById(row.token)
                if not enrollmentToken(token) or (row.map and token.mapid ~= row.map) then
                    draw("\208\158\208\180\208\184\208\189 \208\184\208\183 \209\130\208\190\208\186\208\181\208\189\208\190\208\178 \208\191\208\190\208\186\208\184\208\189\209\131\208\187 \208\186\208\176\209\128\209\130\209\131. \208\146\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \209\130\208\190\208\186\208\181\208\189\209\139 \208\183\208\176\208\189\208\190\208\178\208\190.")
                    return
                end
                local entry = {token = row.token}
                if master then
                    local sheet = row.sheet ~= row.savedSheet and row.sheet
                    entry.sheet = sheet and sheet.id or nil
                    entry.hidden = token.hiddenFromLocalViewer == true
                end
                selection[#selection + 1] = entry
            end
            local command = rollInitiative and (master and "enroll-initiative" or "initiative") or "enroll"
            local payload = {command = command, game = dmhub.gameid, session = scene.session or 0, tokens = selection}
            if not scene.session then payload.session_name = name end
            local key, sending = "sl-" .. command .. "-" .. dmhub.GenerateGuid(), false
            local function send()
                if not current() or sending then return end
                sending = true
                draw(rollInitiative and "\208\148\208\190\208\177\208\176\208\178\208\187\209\143\209\142 \208\178 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131\226\128\166" or "\208\148\208\190\208\177\208\176\208\178\208\187\209\143\209\142 \209\130\208\190\208\186\208\181\208\189\209\139\226\128\166")
                request(TOKEN_SCENE, payload, key, function(result)
                    if rawget(_G, RUNTIME) == state and context() == scope and master then refreshVitals() end
                    if not current() then return end
                    local rows, added = {}, 0
                    if rollInitiative then
                        if type(result.initiative) ~= "table" then
                            draw("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\208\181 \209\129\208\181\209\128\208\178\208\181\209\128 SessionLab \208\180\208\187\209\143 \208\177\209\128\208\190\209\129\208\186\208\176 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\139.")
                            return
                        end
                        for _, row in ipairs(result.initiative) do
                            rows[#rows + 1] = label(safeText(row.name) .. " \194\183 " .. tostring(row.total) ..
                                (row.rolled and "" or " \194\183 \209\131\208\182\208\181 \208\178 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\181"), 13, "#e8defb")
                        end
                        local controls = {menuRows(rows, 248)}
                        local room = rawget(_G, "SessionLabRoomRuntime")
                        if room and type(room.openInitiative) == "function" then
                            controls[#controls + 1] = button("\208\158\209\130\208\186\209\128\209\139\209\130\209\140 \209\130\209\128\208\181\208\186\208\181\209\128 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\139", WIDTH - 20, function()
                                if current() then closePanel() room.openInitiative() end
                            end)
                        end
                        draw("\208\152\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176 \208\183\208\176\208\191\208\184\209\129\208\176\208\189\208\176 \208\178 \209\130\209\128\208\181\208\186\208\181\209\128", controls)
                        return
                    end
                    for _, row in ipairs(result.targets or {}) do
                        if row.added then added = added + 1 end
                        rows[#rows + 1] = label(safeText(row.name) .. (row.added and " \194\183 \208\180\208\190\208\177\208\176\208\178\208\187\208\181\208\189" or " \194\183 \209\131\208\182\208\181 \208\178 \209\129\208\181\209\129\209\129\208\184\208\184"),
                            13, "#e8defb")
                    end
                    draw("\208\148\208\190\208\177\208\176\208\178\208\187\208\181\208\189\208\190: " .. added, {menuRows(rows, 248)})
                end, function(message)
                    sending = false
                    draw(message, {
                        button("\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \208\183\208\176\208\191\209\128\208\190\209\129", WIDTH - 20, send),
                        button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 \209\129\208\190\209\129\209\130\208\176\208\178 \208\183\208\176\208\189\208\190\208\178\208\190", WIDTH - 20, function() closePanel() openEnrollment(rollInitiative) end),
                    })
                end)
            end
            send()
        end
        if not master then
            if not scene.session then draw("\208\156\208\176\209\129\209\130\208\181\209\128 \208\180\208\190\208\187\208\182\208\181\208\189 \208\189\208\176\209\135\208\176\209\130\209\140 \208\184\208\179\209\128\208\190\208\178\209\131\209\142 \209\129\208\181\209\129\209\129\208\184\209\142.") return end
            for _, row in ipairs(picked) do
                local target = mappedTarget(scene, row.token)
                if not target or not id(target.sheet) then
                    draw("\208\146\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \209\129\208\178\208\190\208\185 \209\130\208\190\208\186\208\181\208\189, \208\186\208\190\209\130\208\190\209\128\209\139\208\185 \208\188\208\176\209\129\209\130\208\181\209\128 \208\180\208\190\208\177\208\176\208\178\208\184\208\187 \208\178 \208\176\208\186\209\130\208\184\208\178\208\189\209\131\209\142 \209\129\209\134\208\181\208\189\209\131.")
                    return
                end
            end
            submit()
            return
        end
        local roster = scene.enrollment
        if not scene.is_dm or type(roster) ~= "table" then
            draw("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\208\181 \209\129\208\181\209\128\208\178\208\181\209\128 SessionLab \208\184 \208\191\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\191\209\128\208\176\208\178\208\176 \208\188\208\176\209\129\209\130\208\181\209\128\208\176.")
            return
        end
        local sheets, bindings = {}, allBindings()
        for _, sheet in ipairs(roster.characters or {}) do
            local key = id(sheet.id)
            if key then sheets[key] = sheet end
        end
        for _, row in ipairs(picked) do
            row.target = mappedTarget(scene, row.token)
            if not row.target then
                local saved = bindings[scope .. "|" .. row.token]
                row.savedSheet = sheets[id((roster.bindings or {})[row.token])]
                row.sheet = row.savedSheet or (type(saved) == "table" and sheets[id(saved.sheet)]) or nil
            end
        end
        local function pickSheet(rows)
            local matches = gui.Panel{width = WIDTH - 20, height = "auto", flow = "vertical", halign = "center"}
            local function filter(text)
                local query, options = rosterSearch(text), {}
                for _, sheet in ipairs(roster.characters or {}) do
                    local folder = safeText(sheet["folder__name"])
                    local title = safeText(sheet.name) .. (folder ~= "" and " \194\183 " .. folder or "") .. " \194\183 #" .. id(sheet.id)
                    if (#rows == 1 or sheet.kind == "npc") and rosterSearch(title):find(query, 1, true) then
                        options[#options + 1] = button(title, WIDTH - 40, function()
                            for _, row in ipairs(rows) do row.sheet = sheet end
                            overview()
                        end)
                    end
                end
                matches.children = {#options > 0 and menuRows(options, 248) or label("\208\159\208\190\208\180\209\133\208\190\208\180\209\143\209\137\208\184\209\133 \208\187\208\184\209\129\209\130\208\190\208\178 \208\189\208\181\209\130.", 13)}
            end
            local search = gui.Input{width = WIDTH - 20, height = 30, halign = "center",
                placeholderText = "\208\159\208\190\208\184\209\129\208\186 \208\191\208\190 \208\187\208\184\209\129\209\130\209\131 \208\184\208\187\208\184 \208\191\208\176\208\191\208\186\208\181", text = "", fontSize = 13,
                change = function(element) filter(element.text) end}
            filter("")
            draw(#rows == 1 and ("\208\155\208\184\209\129\209\130 \208\180\208\187\209\143 " .. rows[1].name) or "\208\158\208\180\208\184\208\189 \209\136\208\176\208\177\208\187\208\190\208\189 NPC \208\180\208\187\209\143 \208\178\209\129\208\181\209\133 \208\177\208\181\208\183 \208\187\208\184\209\129\209\130\208\176", {
                search, matches, button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, overview),
            })
        end
        overview = function()
            local rows, missing = {}, {}
            for _, row in ipairs(picked) do
                if row.target then
                    rows[#rows + 1] = label(safeText(row.target.name) .. " \194\183 \209\131\208\182\208\181 \208\178 \209\129\208\181\209\129\209\129\208\184\208\184", 13, "#b6accd")
                else
                    if not row.sheet then missing[#missing + 1] = row end
                    rows[#rows + 1] = button(row.name .. "  \226\134\146  " ..
                        (row.sheet and safeText(row.sheet.name) or "\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \208\187\208\184\209\129\209\130"), WIDTH - 40,
                        function() pickSheet({row}) end)
                end
            end
            local content = {menuRows(rows, 248)}
            if not scene.session then
                content[#content + 1] = gui.Input{width = WIDTH - 20, height = 30, halign = "center",
                    text = name, placeholderText = "\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \208\189\208\190\208\178\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184", fontSize = 13,
                    change = function(element) name = element.text end, edit = function(element) name = element.text end}
            end
            if #missing > 1 then
                content[#content + 1] = button("\208\158\208\180\208\184\208\189 \208\187\208\184\209\129\209\130 \208\180\208\187\209\143 \208\178\209\129\208\181\209\133 \208\177\208\181\208\183 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\208\184", WIDTH - 20,
                    function() pickSheet(missing) end)
            end
            if #missing == 0 then
                local caption = scene.session and "\208\148\208\190\208\177\208\176\208\178\208\184\209\130\209\140 \208\178 \209\129\208\181\209\129\209\129\208\184\209\142" or "\208\161\208\190\208\183\208\180\208\176\209\130\209\140 \209\129\208\181\209\129\209\129\208\184\209\142 \208\184 \208\180\208\190\208\177\208\176\208\178\208\184\209\130\209\140"
                if rollInitiative then caption = scene.session and "\208\145\209\128\208\190\209\129\208\184\209\130\209\140 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131" or "\208\161\208\190\208\183\208\180\208\176\209\130\209\140 \209\129\208\181\209\129\209\129\208\184\209\142 \208\184 \208\177\209\128\208\190\209\129\208\184\209\130\209\140" end
                content[#content + 1] = button(caption, WIDTH - 20, submit, "#514479")
            end
            draw(scene.session and safeText(roster.session_name) or "\208\161\208\190\208\183\208\180\208\176\208\189\208\184\208\181 \208\176\208\186\209\130\208\184\208\178\208\189\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184", content)
        end
        for _, row in ipairs(picked) do
            if not scene.session or (not row.target and not row.sheet) then overview() return end
        end
        submit()
    end, function(message) draw(message) end, master and "&roster=1" or nil)
end

local function enrollSelected() openEnrollment(false) end
local function rollSelectedInitiative() openEnrollment(true) end

local function updateEnrollmentButton()
    local hud = getHud()
    local host = hud and hud.dialogWorldPanel
    local panel = state.enrollmentButton
    local master = dmhub.isDM == true
    local showButton = context() and personalKey()
        and host and host.valid and #(dmhub.selectedTokens or {}) > 0
    if panel and panel.valid and (not showButton or panel.parent ~= host or state.actionButtonsMaster ~= master) then
        panel:DestroySelf()
    end
    if not showButton or (panel and panel.valid) then return end
    local buttons = {button("\208\145\209\128\208\190\209\129\208\184\209\130\209\140 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131", 168, rollSelectedInitiative, "#514479")}
    if master then buttons[#buttons + 1] = button("\208\146 \209\129\208\181\209\129\209\129\208\184\209\142 \194\183 SessionLab", 168, enrollSelected, "#514479") end
    panel = gui.Panel{width = 176, height = #buttons * 32 + 3, halign = "right", valign = "top", x = -20, y = 64,
        flow = "vertical", children = buttons,
        floating = true, swallowPress = true, thinkTime = 0.5,
        think = function(element) if rawget(_G, RUNTIME) ~= state then element:DestroySelf() end end}
    state.enrollmentButton = panel
    state.actionButtonsMaster = master
    host:AddChild(panel)
end

dmhub.RegisterSetting{id = SETTING, storage = "pergamepreference", default = {}}
dmhub.RegisterSetting{id = POSITION, storage = "pergamepreference", default = {}}
dmhub.RegisterSetting{id = HIDE_ACTION_BAR, storage = "pergamepreference", default = true}
dmhub.RegisterSetting{id = HUD_PREFERENCES, storage = "pergamepreference", default = {}}
visualFX.register()
if type(Commands.RegisterMacro) == "function" then
    Commands.RegisterMacro{name = "slfx", summary = "Test SessionLab visual effect on your token", command = visualFX.test}
    Commands.RegisterMacro{name = COMMAND, summary = "SessionLab radial token menu", command = openMenu}
    Commands.RegisterMacro{name = ENROLL_COMMAND, summary = "Add selected tokens to SessionLab", command = enrollSelected}
    Commands.RegisterMacro{name = INITIATIVE_COMMAND, summary = "Roll initiative for selected tokens", command = rollSelectedInitiative}
else
    Commands.slfx = visualFX.test
    Commands[COMMAND] = openMenu
    Commands[ENROLL_COMMAND] = enrollSelected
    Commands[INITIATIVE_COMMAND] = rollSelectedInitiative
end
local function registerTokenClick()
    local tokenUI = rawget(_G, "TokenUI")
    local register = tokenUI and tokenUI.RegisterClickHandler
    if register and register ~= state.tokenClickRegistration then
        register(RUNTIME, tokenClick)
        state.tokenClickRegistration = register
    end
end
registerTokenClick()

local watchedScope, appliedBarScope
local function watchGame()
    if rawget(_G, RUNTIME) ~= state then return end
    updateEnrollmentButton()
    local scope = context()
    if scope then
        registerTokenClick()
        if appliedBarScope ~= scope and setBuiltinActionBar(dmhub.GetSettingValue(HIDE_ACTION_BAR) ~= false) then
            appliedBarScope = scope
        end
    else
        appliedBarScope = nil
    end
    if scope ~= watchedScope then
        watchedScope = scope
        refreshVitals()
    end
    dmhub.Schedule(0.5, watchGame)
end

local keybinds = rawget(_G, "Keybinds")
if keybinds then
    keybinds.Register{command = COMMAND, name = "SessionLab \226\128\148 \208\188\208\181\208\189\209\142 \209\130\208\190\208\186\208\181\208\189\208\176", section = "gameplay"}
    keybinds.Register{command = ENROLL_COMMAND, name = "SessionLab \226\128\148 \208\178 \209\129\208\181\209\129\209\129\208\184\209\142", section = "gameplay"}
    keybinds.Register{command = INITIATIVE_COMMAND, name = "SessionLab \226\128\148 \208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131", section = "gameplay"}
    dmhub.Schedule(0, function()
        if rawget(_G, RUNTIME) ~= state or dmhub.GetCommandBinding(COMMAND) ~= nil then return end
        local ok, bindings = pcall(keybinds.GetBindings)
        if not ok or type(bindings) ~= "table" then return end
        for _, binding in pairs(bindings) do
            local key = dmhub.GetCommandBinding(binding.command)
            if type(key) == "string" and key:lower() == "r" then return end
        end
        dmhub.SetCommandBinding("r", COMMAND)
    end)
end
dmhub.Schedule(0.5, watchGame)
