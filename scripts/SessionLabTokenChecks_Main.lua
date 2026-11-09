-- SessionLab Token Checks. Install the generated ASCII Main file as a separate mod.
local URL = "https://sessionlab.up.railway.app"
local TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"

local SHEETS = "/api/integrations/dmhub/sheets/"
local SETTING = "sessionlab_token_sheets_v1"
local COMMAND = "sltoken"
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
    local game, user = dmhub.gameid, dmhub.userid
    if type(game) ~= "string" or game == "" or type(user) ~= "string" or user == "" then
        return nil
    end
    return URL .. "|" .. game .. "|" .. user
end

local function bindingKey(menu)
    return menu.context .. "|" .. menu.token
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
    return controlled(dmhub.GetTokenById(menu.token))
end

local function close(menu)
    if not active(menu) then return end
    state.menu = nil
    menu.owner.popup = nil
end

local function request(path, body, key, success, failure)
    local headers = {Authorization = "Bearer " .. TOKEN, Accept = "application/json"}
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
    options.error = function()
        fail("\208\158\209\136\208\184\208\177\208\186\208\176 \209\129\208\178\209\143\208\183\208\184 \208\184\208\187\208\184 \208\180\208\190\209\129\209\130\209\131\208\191\208\176. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135, \208\187\208\184\209\129\209\130 \208\184 \208\176\208\186\209\130\208\184\208\178\208\189\209\131\209\142 \209\129\208\181\209\129\209\129\208\184\209\142.")
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

local WIDTH, BUTTON = 324, 148
local function label(value, size, color)
    return gui.Label{
        text = value, width = WIDTH - 20, height = "auto", textWrap = true,
        fontSize = size, color = color, halign = "center", vmargin = 3, interactable = false,
    }
end

local function button(text, width, press)
    return gui.Button{
        text = text, width = width, height = 27, fontSize = 13, hmargin = 2, vmargin = 2,
        halign = "center", bgcolor = "#242739", bgimage = "panels/square.png", cornerRadius = 5,
        styles = {{selectors = {"hover"}, bgcolor = "#4b3a78"}},
        press = press, swallowPress = true,
    }
end

local function show(menu, title, content)
    if not active(menu) then return end
    local children = {
        label(menu.name, 15, "#f2efff"),
        label(title, 12, "#bfb2f4"),
    }
    for _, child in ipairs(content) do children[#children + 1] = child end
    children[#children + 1] = button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140", WIDTH - 20, function() close(menu) end)
    menu.panel.children = children
end

local openSkills, chooseSheet, sendRoll, openPopup, openMenuForToken, getHud

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
        if payload.token_target then
            local target = payload.token_target
            local outcomes = {}
            for _, part in ipairs(target.parts or {}) do
                outcomes[#outcomes + 1] = part.hit == false and "\208\191\209\128\208\190\208\188\208\176\209\133"
                    or part.hit == true and "\208\191\208\190\208\191\208\176\208\180\208\176\208\189\208\184\208\181"
                    or part.save_outcome == "success" and "\209\129\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \208\191\209\128\208\190\208\185\208\180\208\181\208\189"
                    or part.save_outcome == "failure" and "\209\129\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \208\191\209\128\208\190\208\178\208\176\208\187\208\181\208\189"
                    or "\208\191\209\128\208\184\208\188\208\181\208\189\208\181\208\189\208\190"
            end
            message = safeText(target.name) .. " \194\183 " ..
                (target.resolved and table.concat(outcomes, " \194\183 ") or "\209\141\209\132\209\132\208\181\208\186\209\130 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\209\143\208\181\209\130\209\129\209\143 \208\191\208\190 \208\190\208\191\208\184\209\129\208\176\208\189\208\184\209\142")
            if state.hud then state.hud.next = true end
        end
        local shown = state.menu
        if shown and bindingKey(shown) == pending.binding and active(shown) then
            show(shown, message, {
                button("\208\149\209\137\209\145 \208\191\209\128\208\190\208\178\208\181\209\128\208\186\208\176", WIDTH - 20, function() openSkills(shown) end),
            })
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
local tokenUI = rawget(_G, "TokenUI")
local tokenHud = rawget(_G, "TokenHud")

local function tokenScene(success, failure)
    local game = dmhub.gameid
    if type(game) ~= "string" or not game:match("^[%w_.:%-]+$") then
        failure("\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\208\184\209\130\209\140 \208\184\208\179\209\128\209\131 DMHub.")
        return
    end
    local scope = context()
    request(TOKEN_SCENE .. "?game=" .. game, nil, nil, function(scene)
        if context() ~= scope then return end
        success(scene)
    end, failure)
end

local function mappedTarget(scene, token)
    for _, row in ipairs(scene and scene.targets or {}) do
        if row.token == token then return row end
    end
end

local function sheetBinding(menu)
    local row = mappedTarget(menu.scene, menu.token)
    if row and id(row.sheet) then return {sheet = row.sheet, name = row.name} end
    return allBindings()[bindingKey(menu)]
end

local function menuRows(entries)
    return gui.Panel{
        width = WIDTH - 20, height = math.min(248, #entries * 31),
        flow = "vertical", vscroll = true, halign = "center", children = entries,
    }
end

local function sceneBinding(menu)
    if not active(menu) then return end
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\190\208\178 \209\129\209\134\208\181\208\189\209\139\226\128\166", {})
    tokenScene(function(scene)
        if not active(menu) then return end
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
                if not active(menu) then return end
                if state.hud and state.hud.context == menu.context and state.hud.token == menu.token then
                    state.hud = nil
                end
                openMenuForToken(menu)
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
        show(menu, message, {button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)})
    end)
end

local function clearTargeting()
    local targeting = state.targeting
    state.targeting = nil
    if targeting and targeting.panel and targeting.panel.valid then
        targeting.panel:DestroySelf()
    end
end

local function confirmTarget(targeting, row)
    local menu = targeting.menu
    if context() ~= menu.context then clearTargeting() return end
    clearTargeting()
    if not active(menu) then openPopup(menu) end
    local spell = targeting.spell
    show(menu, safeText(spell.name) .. " \226\134\146 " .. safeText(row.name), {
        button("\208\159\208\190\208\180\209\130\208\178\208\181\209\128\208\180\208\184\209\130\209\140 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\208\181", WIDTH - 20, function()
            if not active(menu) or (state.pending and state.pending.sending) then return end
            local job = {
                path = TOKEN_SCENE,
                body = {
                    command = "cast", session = targeting.scene.session, game = dmhub.gameid,
                    caster = targeting.sheet, spell = spell.id, slot_level = targeting.level,
                    token = row.token, target = row.id,
                },
                label = safeText(spell.name),
                binding = bindingKey(menu), context = menu.context,
                key = "sl-cast-" .. dmhub.GenerateGuid(),
            }
            state.pending = job
            sendRoll(menu, job)
        end),
        button("\208\158\209\130\208\188\208\181\208\189\208\176", WIDTH - 20, function() openSkills(menu) end),
    })
end

local function selectTarget(menu, sheet, spell, level)
    if not active(menu) then return end
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \209\134\208\181\208\187\208\184 \209\129\209\134\208\181\208\189\209\139\226\128\166", {})
    tokenScene(function(scene)
        if not active(menu) then return end
        local targeting = {menu = menu, scene = scene, sheet = tonumber(sheet), spell = spell, level = level, targets = {}}
        for _, row in ipairs(scene.targets or {}) do
            local token = type(row.token) == "string" and row.token ~= "" and dmhub.GetTokenById(row.token)
            if token and token.valid and (scene.is_dm or row.targetable) then
                targeting.targets[#targeting.targets + 1] = row
            end
        end
        local function listTargets()
            clearTargeting()
            if not active(menu) then openPopup(menu) end
            local rows = {}
            for _, row in ipairs(targeting.targets) do
                local target = row
                rows[#rows + 1] = button(safeText(row.name), WIDTH - 40,
                    function() if active(menu) then confirmTarget(targeting, target) end end)
            end
            show(menu, "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\134\208\181\208\187\209\140", {
                menuRows(rows), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
            })
        end
        if #targeting.targets == 0 then
            show(menu, "\208\157\208\176 \208\186\208\176\209\128\209\130\208\181 \208\189\208\181\209\130 \208\191\209\128\208\184\208\178\209\143\208\183\208\176\208\189\208\189\209\139\209\133 \209\134\208\181\208\187\208\181\208\185. \208\156\208\176\209\129\209\130\208\181\209\128 \208\191\209\128\208\184\208\178\209\143\208\183\209\139\208\178\208\176\208\181\209\130 \208\184\209\133 \209\135\208\181\209\128\208\181\208\183 \194\171\208\166\208\181\208\187\209\140 \209\129\209\134\208\181\208\189\209\139\194\187.", {
                button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
            })
            return
        end
        local hud = getHud()
        if not tokenUI or not tokenUI.RegisterClickHandler or not hud or not hud.dialogWorldPanel then
            listTargets()
            return
        end
        clearTargeting()
        close(menu)
        state.targeting = targeting
        targeting.panel = gui.Panel{
            floating = true, width = WIDTH, height = "auto", flow = "vertical",
            halign = "center", valign = "top", y = 30, pad = 6,
            bgimage = "panels/square.png", bgcolor = "#161624", cornerRadius = 8,
            captureEscape = true, escape = clearTargeting,
            destroy = function() if state.targeting == targeting then state.targeting = nil end end,
            children = {
                label(safeText(spell.name) .. " \194\183 \208\189\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189 \209\134\208\181\208\187\208\184", 14, "#f2efff"),
                button("\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \208\184\208\183 \209\129\208\191\208\184\209\129\208\186\208\176", WIDTH - 20, listTargets),
                button("\208\158\209\130\208\188\208\181\208\189\208\176", WIDTH - 20, clearTargeting),
            },
        }
        hud.dialogWorldPanel:AddChild(targeting.panel)
    end, function(message)
        show(menu, message, {button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)})
    end)
end

if tokenUI and tokenUI.RegisterClickHandler then
    tokenUI.RegisterClickHandler(RUNTIME, function(token)
        local targeting = state.targeting
        if not targeting then return false end
        if context() ~= targeting.menu.context then clearTargeting() return false end
        if not token or not token.valid then return false end
        for _, row in ipairs(targeting.targets) do
            if row.token == token.charid then confirmTarget(targeting, row) return true end
        end
        return false
    end)
end

local function openSpells(menu, sheet)
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143\226\128\166", {})
    request(SHEETS .. sheet .. "/", nil, nil, function(data)
        if not active(menu) then return end
        local rows = {}
        local slots = data.sheet and data.sheet.slots or {}
        for _, action in ipairs(data.actions or {}) do
            if action.kind == "spell" and id(action.id) then
                local spell = action
                rows[#rows + 1] = button(safeText(spell.name), WIDTH - 40, function()
                    if not active(menu) then return end
                    local level = tonumber(spell.level) or 0
                    if level == 0 then selectTarget(menu, sheet, spell, 0) return end
                    local levels = {}
                    for n = level, (spell.upcast_allowed == false and level or 9) do
                        local slot = slots[tostring(n)] or slots[n]
                        if slot and slot.max > slot.used then
                            local selectedLevel = n
                            levels[#levels + 1] = button("\208\175\209\135\208\181\208\185\208\186\208\176 " .. n .. " \194\183 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 " .. (slot.max - slot.used),
                                WIDTH - 40, function() selectTarget(menu, sheet, spell, selectedLevel) end)
                        end
                    end
                    show(menu, #levels > 0 and "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\143\209\135\208\181\208\185\208\186\209\131" or "\208\157\208\181\209\130 \209\129\208\178\208\190\208\177\208\190\208\180\208\189\209\139\209\133 \209\143\209\135\208\181\208\181\208\186.", {
                        menuRows(levels), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSpells(menu, sheet) end),
                    })
                end)
            end
        end
        show(menu, #rows > 0 and "\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143" or "\208\163 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176 \208\189\208\181\209\130 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\208\185.", {
            menuRows(rows), button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
        })
    end, function(message)
        show(menu, message, {button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)})
    end)
end

local function hudState()
    local hud = state.hud
    if hud and hud.context == context() then return hud end
end

local function toggleHud(token)
    local scope = context()
    if not scope then return end
    local hud = hudState()
    if hud and hud.token == token then
        state.hud = nil
    else
        state.hud = {token = token, context = scope, text = "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \208\165\208\159 \208\184 \208\154\208\148\226\128\166", next = true}
    end
end

local function refreshHud(hud)
    if not hud.next or hud.busy then return end
    if #TOKEN < 24 or TOKEN:find("^PASTE_") then
        hud.text = "\208\163\208\186\208\176\208\182\208\184\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 SessionLab"
        hud.next = false
        return
    end
    hud.next, hud.busy = false, true
    local function finish(row, errorText)
        if hudState() ~= hud then return end
        hud.busy = false
        hud.text = row and row.hp_current ~= nil
            and ("\208\165\208\159 " .. row.hp_current .. "/" .. row.hp_max ..
                 ((tonumber(row.hp_temp) or 0) > 0 and " +" .. row.hp_temp or "") .. "  \194\183  \208\154\208\148 " .. row.armor_class)
            or (errorText or "\208\165\208\159 \208\184 \208\154\208\148 \209\129\208\186\209\128\209\139\209\130\209\139 \208\184\208\187\208\184 \208\187\208\184\209\129\209\130 \208\189\208\181 \208\191\209\128\208\184\208\178\209\143\208\183\208\176\208\189")
        dmhub.Schedule(7, function() hud.next = true end)
    end
    tokenScene(function(scene)
        local row = mappedTarget(scene, hud.token)
        if row then finish(row) return end
        local binding = allBindings()[hud.context .. "|" .. hud.token]
        local sheet = type(binding) == "table" and id(binding.sheet)
        if not sheet then finish(nil) return end
        request(SHEETS .. sheet .. "/", nil, nil, function(data) finish(data.sheet) end,
            function() finish(nil, "\208\165\208\159 \208\184 \208\154\208\148 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139") end)
    end, function()
        finish(nil, "\208\165\208\159 \208\184 \208\154\208\148 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139")
    end)
end

if tokenHud and tokenHud.RegisterPanel then
    tokenHud.RegisterPanel{
        id = RUNTIME,
        ord = 105,
        create = function(token)
            if token.isObject then return nil end
            local tokenId = token.charid
            local vitals = gui.Label{
                width = 132, height = 17, fontSize = 11, halign = "center",
                bgimage = "panels/square.png", bgcolor = "#161624ee", color = "#f2efff",
                cornerRadius = 4, interactable = false, classes = {"collapsed"}, text = "",
            }
            local toggle = gui.Button{
                width = 48, height = 16, fontSize = 11, halign = "center", text = "\208\165\208\159 / \208\154\208\148",
                bgimage = "panels/square.png", bgcolor = "#32264a", color = "#ffffff",
                cornerRadius = 4, swallowPress = true, classes = {"collapsed"},
                press = function() toggleHud(tokenId) end,
            }
            return gui.Panel{
                floating = true, halign = "center", valign = "bottom", y = 28,
                width = 132, height = "auto", flow = "vertical", interactable = false,
                data = {selected = false, shown = false},
                thinkTime = 0.5,
                think = function(element)
                    local hud = hudState()
                    local shown = hud and hud.token == tokenId
                    local selected = dmhub.selectedTokens or {}
                    local single = #selected == 1 and selected[1].charid == tokenId
                    if element.data.selected ~= single then
                        element.data.selected = single
                        toggle:SetClass("collapsed", not single)
                    end
                    shown = shown == true
                    if element.data.shown ~= shown then
                        element.data.shown = shown
                        vitals:SetClass("collapsed", not shown)
                    end
                    if shown then
                        refreshHud(hud)
                        if vitals.text ~= hud.text then vitals.text = hud.text end
                    end
                end,
                children = {vitals, toggle},
            }
        end,
    }
end

local function checkRows(menu, sheet, kind, entries)
    local rows = {}
    local function makeCheck(check)
        return button(check[2], BUTTON, function()
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
    for i = 1, #entries, 2 do
        rows[#rows + 1] = gui.Panel{
            width = WIDTH - 20, height = 31, flow = "horizontal", halign = "center",
            children = {makeCheck(entries[i]), makeCheck(entries[i + 1])},
        }
    end
    return rows
end

openSkills = function(menu, kind)
    if not active(menu) then return end
    local pending = state.pending
    if pending and pending.binding == bindingKey(menu) then
        rollStatus(menu, pending)
        return
    end
    local binding = sheetBinding(menu)
    local sheet = type(binding) == "table" and id(binding.sheet)
    local sceneLink = button("\208\166\208\181\208\187\209\140 \209\129\209\134\208\181\208\189\209\139", BUTTON, function() sceneBinding(menu) end)
    local hud = button("\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 / \209\129\208\186\209\128\209\139\209\130\209\140 \208\165\208\159 \208\184 \208\154\208\148", WIDTH - 20, function()
        toggleHud(menu.token)
    end)
    if not sheet then
        show(menu, "\208\162\208\190\208\186\208\181\208\189 \208\191\208\190\208\186\208\176 \208\189\208\181 \209\129\208\178\209\143\208\183\208\176\208\189 \209\129 \208\187\208\184\209\129\209\130\208\190\208\188", {
            button("\208\159\209\128\208\184\208\178\209\143\208\183\208\176\209\130\209\140 \208\187\208\184\209\129\209\130", WIDTH - 20, function() chooseSheet(menu) end),
            sceneLink, hud,
        })
        return
    end
    kind = kind or "skill"
    local names = {skill = "\208\157\208\176\208\178\209\139\208\186\208\184", ability = "\208\165\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\184", save = "\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\184"}
    local rows = checkRows(menu, sheet, kind, kind == "skill" and skills or abilities)
    local function tab(text, click) return button(text, BUTTON, click) end
    local function pair(first, second)
        return gui.Panel{width = WIDTH - 20, height = 31, flow = "horizontal",
            halign = "center", children = {first, second}}
    end
    table.insert(rows, 1, pair(
        tab("\208\157\208\176\208\178\209\139\208\186\208\184", function() openSkills(menu, "skill") end),
        tab("\208\165\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\184", function() openSkills(menu, "ability") end)
    ))
    table.insert(rows, 2, pair(
        tab("\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\184", function() openSkills(menu, "save") end),
        tab("\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143", function() openSpells(menu, sheet) end)
    ))
    local mapped = mappedTarget(menu.scene, menu.token)
    if mapped and id(mapped.sheet) then
        rows[#rows + 1] = sceneLink
    else
        rows[#rows + 1] = pair(button("\208\161\208\188\208\181\208\189\208\184\209\130\209\140 \208\187\208\184\209\129\209\130", BUTTON, function() chooseSheet(menu) end), sceneLink)
    end
    rows[#rows + 1] = hud
    show(menu, names[kind] .. " \194\183 " .. safeText(binding.name), rows)
end

chooseSheet = function(menu)
    if not active(menu) then return end
    show(menu, "\208\151\208\176\208\179\209\128\209\131\208\182\208\176\209\142 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\209\139\208\181 \208\187\208\184\209\129\209\130\209\139\226\128\166", {})
    request(SHEETS, nil, nil, function(result)
        if not active(menu) then return end
        local rows = {}
        for _, character in ipairs(result.characters or {}) do
            local sheet = id(character.id)
            local name = safeText(character.name)
            if sheet then
                rows[#rows + 1] = button(name .. " \194\183 #" .. sheet, WIDTH - 40, function()
                    if not active(menu) or not tokenStillControlled(menu) then return end
                    writeBinding(menu, {sheet = sheet, name = name})
                    if state.hud then state.hud.next = true end
                    openSkills(menu)
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
            gui.Panel{width = WIDTH - 20, height = math.min(248, #rows * 31),
                flow = "vertical", vscroll = true, halign = "center", children = rows},
        }
        if allBindings()[bindingKey(menu)] then
            content[#content + 1] = button("\208\158\209\130\208\178\209\143\208\183\208\176\209\130\209\140 \208\187\208\184\209\129\209\130", WIDTH - 20, function()
                if not active(menu) or not tokenStillControlled(menu) then return end
                writeBinding(menu, nil)
                openSkills(menu)
            end)
        end
        content[#content + 1] = button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end)
        show(menu, "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\187\208\184\209\129\209\130 SessionLab", content)
    end, function(message)
        show(menu, message, {
            button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 \208\181\209\137\209\145 \209\128\208\176\208\183", WIDTH - 20, function() chooseSheet(menu) end),
            button("\208\157\208\176\208\183\208\176\208\180", WIDTH - 20, function() openSkills(menu) end),
        })
    end)
end

local function openMenu(args)
    local fromSelection = type(args) == "string" and args:match("^%s*selected%s*$")
    local token
    if fromSelection then
        local selected = dmhub.selectedTokens or {}
        if #selected == 1 and selected[1].valid then
            token = dmhub.GetTokenById(selected[1].charid)
        end
    else
        local ok, hovered = pcall(function() return dmhub.tokenHovered end)
        if ok then token = hovered end
    end
    if not token or not token.valid or type(token.charid) ~= "string" or token.charid == "" then
        if state.menu and active(state.menu) then close(state.menu) return end
        report("\208\157\208\176\208\178\208\181\208\180\208\184\209\130\208\181\209\129\209\140 \208\189\208\176 \209\130\208\190\208\186\208\181\208\189. \208\152\208\187\208\184 \208\178\209\139\208\180\208\181\208\187\208\184\209\130\208\181 \208\190\208\180\208\184\208\189 \209\130\208\190\208\186\208\181\208\189 \208\184 \208\178\208\178\208\181\208\180\208\184\209\130\208\181 /sltoken selected.")
        return
    end
    if not controlled(token) then
        report("\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\130\208\190\208\186\208\181\208\189, \208\186\208\190\209\130\208\190\209\128\209\139\208\188 \208\188\208\190\208\182\208\181\209\130\208\181 \209\131\208\191\209\128\208\176\208\178\208\187\209\143\209\130\209\140.")
        return
    end
    clearTargeting()
    local hud = getHud()
    local owner = hud and hud.dialog and hud.dialog.sheet
    local scope = context()
    if not owner or not scope then
        report("\208\161\208\189\208\176\209\135\208\176\208\187\208\176 \208\190\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\209\131 DMHub.")
        return
    end
    local menu = {context = scope, owner = owner, token = token.charid, name = safeText(token.description)}
    openMenuForToken(menu)
end

getHud = function()
    local gameHudType = rawget(_G, "GameHud")
    return rawget(_G, "gamehud") or (gameHudType and gameHudType.instance)
end

openPopup = function(menu)
    menu.panel = gui.Panel{
        width = WIDTH, height = "auto", flow = "vertical", halign = "left", valign = "top",
        bgimage = "panels/square.png", bgcolor = "#161624", cornerRadius = 9,
        borderWidth = 1, borderColor = "#514773", vpad = 6,
        constrainToScreen = true, swallowPress = true, captureEscape = true,
        escape = function() close(menu) end,
        destroy = function(element)
            if state.menu == menu and menu.panel == element then state.menu = nil end
        end,
    }
    state.menu = menu
    menu.owner.popupPositioning = "mouse"
    menu.owner.popup = menu.panel
end

openMenuForToken = function(menu)
    if not active(menu) then openPopup(menu) end
    if #TOKEN < 24 or TOKEN:find("^PASTE_") then
        show(menu, "\208\163\208\186\208\176\208\182\208\184\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 SessionLab \208\178 TOKEN.", {})
        return
    end
    show(menu, "\208\159\209\128\208\190\208\178\208\181\209\128\209\143\209\142 \208\191\209\128\208\184\208\178\209\143\208\183\208\186\209\131 \209\130\208\190\208\186\208\181\208\189\208\176\226\128\166", {})
    tokenScene(function(scene)
        if not active(menu) then return end
        menu.scene = scene
        openSkills(menu)
    end, function()
        if active(menu) then menu.scene = nil openSkills(menu) end
    end)
end

dmhub.RegisterSetting{id = SETTING, storage = "pergamepreference", default = {}}
if type(Commands.RegisterMacro) == "function" then
    Commands.RegisterMacro{name = COMMAND, summary = "SessionLab token skill checks", command = openMenu}
else
    Commands[COMMAND] = openMenu
end
local keybinds = rawget(_G, "Keybinds")
if keybinds then
    keybinds.Register{command = COMMAND, name = "SessionLab \226\128\148 \208\191\209\128\208\190\208\178\208\181\209\128\208\186\208\184 \209\130\208\190\208\186\208\181\208\189\208\176", section = "gameplay"}
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
