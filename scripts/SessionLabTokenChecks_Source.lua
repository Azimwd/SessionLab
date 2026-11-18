-- SessionLab Token Checks. Install the generated ASCII Main file as a separate mod.
local URL = "https://sessionlab.up.railway.app"
local TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"
-- @include SessionLabConnection_Source.lua

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
    {"athletics", "Атлетика"}, {"acrobatics", "Акробатика"},
    {"perception", "Внимательность"}, {"stealth", "Скрытность"},
    {"investigation", "Анализ"}, {"survival", "Выживание"},
    {"animal_handling", "Уход за животными"}, {"insight", "Проницательность"},
    {"arcana", "Магия"}, {"history", "История"},
    {"medicine", "Медицина"}, {"nature", "Природа"},
    {"religion", "Религия"}, {"sleight_of_hand", "Ловкость рук"},
    {"deception", "Обман"}, {"intimidation", "Запугивание"},
    {"performance", "Выступление"}, {"persuasion", "Убеждение"},
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
    if not token then failure("Подключите личный ключ SessionLab через /slconnect.") return end
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
            fail(type(detail) == "string" and safeText(detail) or "SessionLab не принял запрос.")
            return
        end
        finished = true
        success(result.data)
    end
    options.error = function(message)
        local status = type(message) == "string" and tonumber(message:match("%f[%d]([45]%d%d)%f[%D]"))
        if status == 401 or status == 403 then
            fail("Нет доступа в SessionLab. Проверьте личный ключ и права на лист.")
        elseif status == 404 and not body and path:find("/token-scene/", 1, true) then
            fail("Сервер SessionLab не поддерживает привязку токенов. Нужно обновить сервер.")
        elseif status == 404 then
            fail("Лист или цель больше недоступны. Проверьте привязку.")
        elseif status == 429 then
            fail("Слишком много запросов к SessionLab. Повторите чуть позже.")
        else
            fail("SessionLab не принял запрос. Проверьте подключение, лист и активную сессию.")
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
        dmhub.Schedule(15, function() fail("SessionLab не ответил вовремя.") end)
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
        show(menu, pending.label, {label("Отправляю действие…", 13, "#bfb2f4")})
    else
        show(menu, pending.label, {
            label(pending.error .. " Перед новым броском проверьте журнал.", 13, "#f5c592"),
            button("Повторить этот запрос", WIDTH - 20, function() sendRoll(menu, pending) end),
            button("Вернуться к проверкам", WIDTH - 20, function()
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
        pending.error = "Токен больше недоступен."
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
        local message = "Проверка записана в журнал SessionLab"
        if total then message = pending.label .. ": " .. tostring(total) .. " · отправлено в журнал" end
        if pending.animate then
            local ok, err = pcall(pending.animate, payload)
            if not ok then report("Не удалось показать анимацию: " .. safeText(err)) end
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
                        local save = "спасбросок " .. (outcome == "success" and "пройден" or "провален")
                        if outcome == "success" then passed = passed + 1 else failed = failed + 1 end
                        if tonumber(part.save_total) and tonumber(part.save_dc) then
                            save = save .. " (" .. part.save_total .. " против СЛ " .. part.save_dc .. ")"
                        end
                        outcomes[#outcomes + 1] = save
                        saves[#saves + 1] = save
                    else
                        outcomes[#outcomes + 1] = part.hit == false and "промах"
                            or part.hit == true and "попадание" or "применено"
                    end
                    local effects = {}
                    for _, effect in ipairs(part.effect_damage or {}) do
                        local damage = tonumber(effect.damage)
                        if damage then
                            effects[#effects + 1] = safeText(effect.name) .. " — " .. damage .. " урона"
                        end
                    end
                    if #effects > 0 then
                        local strike = #parts > 1 and (" · бросок " .. index) or ""
                        effectLines[#effectLines + 1] = name .. strike .. " · " .. table.concat(effects, " / ")
                    end
                end
                if #saves > 0 then
                    local line = name .. " · " .. table.concat(saves, " / ")
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
                    message = name .. " · " ..
                        (target.resolved and table.concat(outcomes, " · ") or "эффект определяется по описанию")
                end
            end
            if payload.token_targets then
                message = pending.label .. " · целей " .. #targets
                if passed + failed > 0 then message = message .. " · пройдено " .. passed .. " · провалено " .. failed end
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
            content[#content + 1] = button(pending.actionKind and "К действиям" or "Ещё проверка", WIDTH - 20, function()
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
    {"str", "Сила"}, {"dex", "Ловкость"}, {"con", "Телосложение"},
    {"int", "Интеллект"}, {"wis", "Мудрость"}, {"cha", "Харизма"},
}

local function tokenScene(success, failure, query)
    local game = dmhub.gameid
    if type(game) ~= "string" or not game:match("^[%w_.:%-]+$") then
        failure("Не удалось определить игру DMHub.")
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
    show(menu, "Загружаю участников сцены…", {})
    local page = menu.page
    tokenScene(function(scene)
        if not active(menu) or menu.page ~= page then return end
        if not scene.is_dm or not scene.session then
            show(menu, "Привязка к сцене доступна мастеру в активной сессии.", {
                button("Назад", WIDTH - 20, function() openSkills(menu) end),
            })
            return
        end
        local rows = {}
        local function bind(target)
            if not active(menu) or not tokenStillControlled(menu) then return end
            show(menu, "Сохраняю привязку…", {})
            request(TOKEN_SCENE, {
                command = "link", session = scene.session, game = dmhub.gameid,
                token = menu.token, target = target,
            }, "sl-link-" .. dmhub.GenerateGuid(), function()
                refreshVitals()
                if active(menu) then openMenuForToken(menu) end
            end, function(message)
                show(menu, message, {button("Назад", WIDTH - 20, function() openSkills(menu) end)})
            end)
        end
        for _, row in ipairs(scene.targets or {}) do
            if id(row.sheet) then
                local target = row.id
                rows[#rows + 1] = button(safeText(row.name) .. " · #" .. id(target), WIDTH - 40,
                    function() bind(target) end)
            end
        end
        local content = {}
        if #rows > 0 then content[#content + 1] = menuRows(rows) end
        if mappedTarget(scene, menu.token) then
            content[#content + 1] = button("Отвязать от сцены", WIDTH - 20, function() bind(0) end)
        end
        content[#content + 1] = button("Назад", WIDTH - 20, function() openSkills(menu) end)
        show(menu, #rows > 0 and "Выберите участника сцены" or "Добавьте участников в комнате SessionLab.", content)
    end, function(message)
        if active(menu) and menu.page == page then
            show(menu, message, {button("Назад", WIDTH - 20, function() openSkills(menu) end)})
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
-- @include SessionLabIconKeys_Source.lua
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
    if damage == "fire" or damage == "огонь" then icon = spellIcons.fire
    elseif damage == "cold" or damage == "холод" then icon = spellIcons.frost
    elseif damage == "lightning" or damage == "электричество" then icon = spellIcons.lightning
    elseif damage == "healing" or damage == "heal" or damage == "лечение" or damage == "исцеление" then
        icon = spellIcons.healing
    elseif action.kind == "attack" then icon = spellIcons.weapon
    else icon = spellIcons.magic end
    return icon[1], icon[2]
end

local shapeNames = {
    sphere = "сфера", burst = "вокруг себя", cone = "конус", cube = "куб", line = "линия",
}
local nativeShapes = {sphere = "sphere", burst = "RadiusFromCreature", cone = "cone", cube = "cube", line = "line"}

local function actionDetails(action)
    local rules = action.map_targeting or {}
    local distance = tonumber(rules.range_ft)
    local text = distance and (distance == 0 and "От себя" or (distance .. " фт."))
        or (action.range and action.range ~= "" and safeText(action.range) or "Дальность не задана")
    if shapeNames[rules.shape] then text = text .. " · " .. shapeNames[rules.shape] .. " " .. rules.size_ft .. " фт." end
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
    if not controlled(caster) or caster.onBoard == false then return nil, "Заклинатель покинул карту." end
    local limit = tonumber(targeting.rules.range_ft)
    if limit == 0 and not fromCaster and target.charid ~= caster.charid then return nil, "Действие применяется на себя." end
    local distance = fromCaster and 0 or distanceTo(caster, target)
    if limit and not distance then return nil, "DMHub не смог измерить расстояние." end
    if limit and distance > limit then return nil, distance .. " фт. · за пределами дальности " .. limit .. " фт." end
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

-- @include SessionLabEffects_Source.lua

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
        setTargetHint(targeting, "Цель больше недоступна на карте.")
        return false
    end
    local distance, errorText = withinRange(targeting, token)
    if not distance then setTargetHint(targeting, errorText) return false end
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if caster.charid ~= token.charid then
        local ok, sight = pcall(function() return caster:GetLineOfSight(token) end)
        if ok and sight == 0 then setTargetHint(targeting, "Между заклинателем и целью есть преграда.") return false end
    end
    applyMapAction(targeting, {row}, distance)
    return true
end

local function areaAt(targeting, loc, point)
    if not loc then return nil, "Наведите курсор на клетку карты." end
    local caster = dmhub.GetTokenById(targeting.menu.token)
    if not controlled(caster) or caster.onBoard == false then return nil, "Заклинатель покинул карту." end
    -- Map focus provides the cursor's world point. PosAtLoc uses the caster's footprint.
    point = point or caster:PosAtLoc(loc)
    if not point then return nil, "Не удалось определить центр области." end
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
        if dx == 0 and dy == 0 then return nil, "Укажите направление куба." end
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
    if not shape or shape.valid == false then return nil, "DMHub не смог построить область." end
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
    setTargetHint(targeting, "Целей в области: " .. #area.rows .. " · нажмите для применения")
end

local function commitArea(targeting, loc, point)
    local area, errorText = areaAt(targeting, loc, point)
    if not area then setTargetHint(targeting, errorText) return end
    if #area.rows > 50 then setTargetHint(targeting, "Слишком много целей в области (максимум 50).") return end
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
    setTargetHint(targeting, "Этот токен недоступен. Мастер может привязать его к сцене SessionLab.")
    return true
end

local function selectTarget(menu, sheet, action, level, effects)
    if not active(menu) or not tokenStillControlled(menu) then return end
    show(menu, "Загружаю цели сцены…", {})
    local page = menu.page
    local function current() return active(menu) and menu.page == page end
    tokenScene(function(scene)
        if not current() then return end
        if not scene.session then
            show(menu, "Откройте игровую сессию в SessionLab для выбора цели.", {})
            return
        end
        local rules = action.map_targeting or {shape = "single"}
        local area = nativeShapes[rules.shape] ~= nil
        if not scene.map_actions and (area or action.kind == "attack") then
            show(menu, "Для атак и областей обновите сервер SessionLab.", {})
            return
        end
        if area and (type(dmhub.CalculateShape) ~= "function" or action.resolution == "attack") then
            show(menu, "Для области нужен поддерживаемый клиент DMHub и действие без броска атаки.", {})
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
            show(menu, "Выберите цель", {targeting.hint, menuRows(rows), button("Назад", WIDTH - 20, cancel)})
        end
        if #targeting.targets == 0 and not area then
            show(menu, "На карте нет привязанных целей. Мастер привязывает их через «Цель сцены».", {})
            return
        end
        clearTargeting()
        close(menu)
        state.targeting = targeting
        targeting.hint = label(area and "Укажите клетку на карте" or "Нажмите на токен цели", 13, "#e0c9fb")
        local children = {label(safeText(action.name) .. " · " .. actionDetails(action), 14, "#f2efff")}
        if action.resolution == "save" then
            for _, ability in ipairs(abilities) do
                if ability[1] == action.save_ability then
                    children[#children + 1] = label("Спасбросок · " .. ability[2], 12, "#bfb2f4")
                    break
                end
            end
        end
        children[#children + 1] = targeting.hint
        if not area then children[#children + 1] = button("Выбрать из списка", WIDTH - 20, listTargets) end
        children[#children + 1] = button("Отмена", WIDTH - 20, cancel)
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
                        setTargetHint(targeting, errorText or (safeText(row.name) .. " · " .. distance .. " фт."))
                        return
                    end
                end
                setTargetHint(targeting, "Нажмите на токен цели")
            end,
            maphover = function(_, loc, point)
                if state.targeting ~= targeting or not loc then return end
                if area then
                    previewArea(targeting, loc, point)
                elseif not dmhub.tokenHovered and (tonumber(rules.range_ft) or 0) > 0 then
                    local distance, errorText = withinRange(targeting, loc)
                    setTargetHint(targeting, errorText or (distance .. " фт. · нажмите на токен цели"))
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
                        setTargetHint(targeting, "На этой клетке нет цели. Нажмите на токен или выберите из списка.")
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
                elseif #tokens > 1 then setTargetHint(targeting, "Несколько токенов на клетке. Выберите цель из списка.")
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
                rows[#rows + 1] = button(prefix .. safeText(effect.name) .. " · " .. safeText(effect.dice),
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
            show(menu, "Эффекты · " .. safeText(action.name), {
                menuRows(rows, 186),
                button("Выбрать цель", WIDTH - 20, function()
                    local ids = {}
                    for _, effect in ipairs(available) do
                        if selected[effect.id] then ids[#ids + 1] = effect.id end
                    end
                    selectTarget(menu, sheet, action, level, ids)
                end),
                button("Назад", WIDTH - 20, function() openActions(menu, sheet, action.kind) end),
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
            levels[#levels + 1] = button("Ячейка " .. n .. " · осталось " .. remaining,
                WIDTH - 40, function() prepare(chosenLevel) end)
        end
    end
    if #levels == 1 then prepare(onlyLevel) return end
    show(menu, safeText(action.name) .. " · " .. actionDetails(action), {
        label(#levels > 0 and "Выберите ячейку" or "Нет свободных ячеек.", 13, "#c4b9ed"),
        menuRows(levels), button("Назад", WIDTH - 20, function() openActions(menu, sheet, action.kind) end),
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
        hover = function(element) element.tooltip = title .. " · " .. actionDetails(action) end,
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

-- @include SessionLabEffectEditor_Source.lua

local function openAttackIcons(menu, sheet, actions, back)
    local choices = {
        {"Атака клинками", "1"}, {"Боевой топор", "skill_62"},
        {"Выпад кинжалом", "skill_74"}, {"Удар копьём", "spear_hit"},
        {"Мощный кулак", "skill_58"}, {"Удар посохом", "skill_81"},
        {"Точный прицел", "skill_80"}, {"Град стрел", "skill_73"},
        {"Удар когтями", "claw_strike"}, {"Укус", "fishbite"},
        {"Ядовитое жало", "venom"}, {"Огненный шар", "03_fireball"},
        {"Молния", "25_Lightning"}, {"Сияющий меч", "Skill_242"},
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
                draw("Укажите ID изображения или путь к PNG из галереи DMHub.")
                return
            end
            local settings = {}
            for key, previous in pairs(action.map_settings or {}) do settings[key] = previous end
            settings.icon_asset = value
            local sheetId, actionId, version = id(sheet), id(action.id), tonumber(action.version)
            if not sheetId or not actionId or not version then
                draw("Не удалось прочитать версию атаки. Откройте её заново.")
                return
            end
            saving, asset = true, value
            draw("Сохраняю иконку…")
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
                text = asset, placeholderText = "ID или путь к иконке DMHub"}
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
                button("Сохранить иконку", WIDTH - 20, function() save(input) end, "#514479"),
                button("Сбросить свою иконку", WIDTH - 20, function()
                    if current() and not saving then asset = "" draw() end
                end),
                button("Назад", WIDTH - 20, function()
                    if not saving then openAttackIcons(menu, sheet, actions, back) end
                end),
            }
            if message then table.insert(content, 1, label(message, 12, "#f5c592")) end
            show(menu, "Иконка · " .. safeText(action.name), content)
            page = menu.page
        end
        draw()
    end
    local rows = {}
    for _, action in ipairs(actions) do
        rows[#rows + 1] = button(safeText(action.name), WIDTH - 40, function() edit(action) end)
    end
    show(menu, "Иконки атак", {menuRows(rows, 248), button("Назад", WIDTH - 20, back)})
end

openActions = function(menu, sheet, kind)
    menu.section = kind
    local title = kind == "spell" and "Заклинания" or "Атаки"
    show(menu, "Загружаю действия…", {})
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
                        text = level == 0 and "ЗАГОВОРЫ" or ("УРОВЕНЬ " .. level),
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
        if #rows == 0 then show(menu, "В листе пока нет таких действий.", {}) return end
        local function reload() openActions(menu, sheet, kind) end
        local content = {
            button("Настроить анимации", WIDTH - 20, function()
                openEffectActions(menu, actions, reload)
            end),
        }
        if kind == "attack" then
            content[#content + 1] = button("Настроить иконки", WIDTH - 20, function()
                openAttackIcons(menu, sheet, actions, reload)
            end)
        end
        content[#content + 1] = scrollList(rows, WIDTH - 12, math.min(kind == "attack" and 275 or 306, height), height)
        show(menu, title, content)
    end, function(message)
        if current() then
            show(menu, message, {button("Загрузить ещё раз", WIDTH - 20, function() openActions(menu, sheet, kind) end)})
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
    local acText = "КД " .. string.format("%.0f", ac)
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
        rows[#rows + 1] = button(enabled and "Скрыть ХП и КД токена" or "Показать ХП и КД токена",
            WIDTH - 20, function()
                if not active(menu) then return end
                hud.hidden[menu.token] = enabled or nil
                saveVitalsPreferences(hud)
                if enabled then removeVitals(hud, menu.token) end
                refreshVitals()
                settingsPage(menu)
            end)
    end
    rows[#rows + 1] = button(hud.all and "Скрыть все ХП и КД" or "Показать все ХП и КД",
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
        rows[#rows + 1] = button("Цель сцены", WIDTH - 20, function() sceneBinding(menu) end)
    end
    if not mapped or not id(mapped.sheet) then
        rows[#rows + 1] = button(sheetBinding(menu) and "Сменить лист" or "Привязать лист", WIDTH - 20,
            function() chooseSheet(menu) end)
    end
    local barHidden = dmhub.GetSettingValue(BUILTIN_ACTION_BAR)
    if type(barHidden) == "boolean" then
        rows[#rows + 1] = button(barHidden and "Показать панель действий DMHub" or "Скрыть панель действий DMHub",
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
                    if hud.panels[menu.token] then text = "Показатели под токеном"
                    elseif hud.busy then text = "Обновляю показатели…"
                    elseif hud.all and not enabled then text = "Показатели сцены включены"
                    else text = "Для токена нет доступных показателей. Проверьте привязку листа." end
                end
                if element.text ~= text then element.text = text end
            end,
        }
    end
    show(menu, "Токен и показатели", rows)
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
    {"skill", "Навыки"}, {"ability", "Характеристики"},
    {"save", "Спасброски"}, {"spell", "Заклинания"}, {"attack", "Атаки"},
    {"settings", "Токен и ХП / КД"},
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
    local names = {skill = "Навыки", ability = "Характеристики", save = "Спасброски"}
    local rows = checkRows(menu, sheet, menu.section, menu.section == "skill" and skills or abilities)
    show(menu, names[menu.section] .. " · " .. safeText(binding.name), {menuRows(rows)})
end

chooseSheet = function(menu)
    if not active(menu) then return end
    menu.section = "settings"
    show(menu, "Загружаю доступные листы…", {})
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
            show(menu, "Сохраняю привязку…", {})
            local page = menu.page
            request(TOKEN_SCENE, {command = "bind", game = dmhub.gameid, token = menu.token,
                sheet = binding and tonumber(binding.sheet) or 0}, "sl-bind-" .. dmhub.GenerateGuid(),
                function(response)
                    if active(menu) and menu.page == page then save(response.binding) end
                end, function(message)
                    if active(menu) and menu.page == page then
                        show(menu, message, {button("К списку листов", WIDTH - 20, function() chooseSheet(menu) end)})
                    end
                end)
        end
        local rows = {}
        for _, character in ipairs(result.characters or {}) do
            local sheet = id(character.id)
            local name = safeText(character.name)
            if sheet then
                rows[#rows + 1] = button(name .. " · #" .. sheet, WIDTH - 40, function()
                    bind({sheet = sheet, name = name})
                end)
            end
        end
        if #rows == 0 then
            show(menu, "Нет доступных листов в кампании SessionLab", {
                button("Назад", WIDTH - 20, function() openSkills(menu) end),
            })
            return
        end
        local content = {
            menuRows(rows, 248),
        }
        if sheetBinding(menu) then
            content[#content + 1] = button("Отвязать лист", WIDTH - 20, function() bind(nil) end)
        end
        content[#content + 1] = button("Назад", WIDTH - 20, function() openSkills(menu) end)
        show(menu, "Выберите лист SessionLab", content)
    end, function(message)
        if not current() then return end
        show(menu, message, {
            button("Загрузить ещё раз", WIDTH - 20, function() chooseSheet(menu) end),
            button("Назад", WIDTH - 20, function() openSkills(menu) end),
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
        report("Сначала откройте игру DMHub.")
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
        report("Наведитесь на свой токен или выделите его на карте.")
        return
    end
    clearTargeting()
    if state.radial and state.radial.token == token.charid and state.radial.panel.valid then
        closeRadial()
    elseif not openRadial(token) then
        report("Токен пока не готов. Выделите его на карте.")
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
            label("Перетащите окно за заголовок", 11, "#b6accd"),
            menu.content,
            button("Закрыть", WIDTH - 20, function() close(menu) end),
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
    show(menu, "Проверяю привязку токена…", {})
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
        show(menu, message, {button("Привязать лист", WIDTH - 20, function() chooseSheet(menu) end)})
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
    return text:lower():gsub("Ё", "ё"):gsub("\208[\144-\175]", function(letter)
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
        report("Выделите от 1 до 50 токенов на карте.")
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
        label(rollInitiative and "SESSIONLAB  /  ИНИЦИАТИВА" or "SESSIONLAB  /  В СЕССИЮ", 15, "#f2efff"), body,
        button("Закрыть", WIDTH - 20, closePanel),
    }
    state.enrollment = panel
    host:AddChild(panel)
    draw("Загружаю состав сессии…")
    tokenScene(function(scene)
        if not current() then return end
        local overview
        local name = "Сессия DMHub"
        local function submit()
            if not current() then return end
            local selection = {}
            for _, row in ipairs(picked) do
                local token = dmhub.GetTokenById(row.token)
                if not enrollmentToken(token) or (row.map and token.mapid ~= row.map) then
                    draw("Один из токенов покинул карту. Выделите токены заново.")
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
                draw(rollInitiative and "Добавляю в инициативу…" or "Добавляю токены…")
                request(TOKEN_SCENE, payload, key, function(result)
                    if rawget(_G, RUNTIME) == state and context() == scope and master then refreshVitals() end
                    if not current() then return end
                    local rows, added = {}, 0
                    if rollInitiative then
                        if type(result.initiative) ~= "table" then
                            draw("Обновите сервер SessionLab для броска инициативы.")
                            return
                        end
                        for _, row in ipairs(result.initiative) do
                            rows[#rows + 1] = label(safeText(row.name) .. " · " .. tostring(row.total) ..
                                (row.rolled and "" or " · уже в инициативе"), 13, "#e8defb")
                        end
                        local controls = {menuRows(rows, 248)}
                        local room = rawget(_G, "SessionLabRoomRuntime")
                        if room and type(room.openInitiative) == "function" then
                            controls[#controls + 1] = button("Открыть трекер инициативы", WIDTH - 20, function()
                                if current() then closePanel() room.openInitiative() end
                            end)
                        end
                        draw("Инициатива записана в трекер", controls)
                        return
                    end
                    for _, row in ipairs(result.targets or {}) do
                        if row.added then added = added + 1 end
                        rows[#rows + 1] = label(safeText(row.name) .. (row.added and " · добавлен" or " · уже в сессии"),
                            13, "#e8defb")
                    end
                    draw("Добавлено: " .. added, {menuRows(rows, 248)})
                end, function(message)
                    sending = false
                    draw(message, {
                        button("Повторить запрос", WIDTH - 20, send),
                        button("Загрузить состав заново", WIDTH - 20, function() closePanel() openEnrollment(rollInitiative) end),
                    })
                end)
            end
            send()
        end
        if not master then
            if not scene.session then draw("Мастер должен начать игровую сессию.") return end
            for _, row in ipairs(picked) do
                local target = mappedTarget(scene, row.token)
                if not target or not id(target.sheet) then
                    draw("Выделите свой токен, который мастер добавил в активную сцену.")
                    return
                end
            end
            submit()
            return
        end
        local roster = scene.enrollment
        if not scene.is_dm or type(roster) ~= "table" then
            draw("Обновите сервер SessionLab и проверьте права мастера.")
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
                    local title = safeText(sheet.name) .. (folder ~= "" and " · " .. folder or "") .. " · #" .. id(sheet.id)
                    if (#rows == 1 or sheet.kind == "npc") and rosterSearch(title):find(query, 1, true) then
                        options[#options + 1] = button(title, WIDTH - 40, function()
                            for _, row in ipairs(rows) do row.sheet = sheet end
                            overview()
                        end)
                    end
                end
                matches.children = {#options > 0 and menuRows(options, 248) or label("Подходящих листов нет.", 13)}
            end
            local search = gui.Input{width = WIDTH - 20, height = 30, halign = "center",
                placeholderText = "Поиск по листу или папке", text = "", fontSize = 13,
                change = function(element) filter(element.text) end}
            filter("")
            draw(#rows == 1 and ("Лист для " .. rows[1].name) or "Один шаблон NPC для всех без листа", {
                search, matches, button("Назад", WIDTH - 20, overview),
            })
        end
        overview = function()
            local rows, missing = {}, {}
            for _, row in ipairs(picked) do
                if row.target then
                    rows[#rows + 1] = label(safeText(row.target.name) .. " · уже в сессии", 13, "#b6accd")
                else
                    if not row.sheet then missing[#missing + 1] = row end
                    rows[#rows + 1] = button(row.name .. "  →  " ..
                        (row.sheet and safeText(row.sheet.name) or "Выбрать лист"), WIDTH - 40,
                        function() pickSheet({row}) end)
                end
            end
            local content = {menuRows(rows, 248)}
            if not scene.session then
                content[#content + 1] = gui.Input{width = WIDTH - 20, height = 30, halign = "center",
                    text = name, placeholderText = "Название новой сессии", fontSize = 13,
                    change = function(element) name = element.text end, edit = function(element) name = element.text end}
            end
            if #missing > 1 then
                content[#content + 1] = button("Один лист для всех без привязки", WIDTH - 20,
                    function() pickSheet(missing) end)
            end
            if #missing == 0 then
                local caption = scene.session and "Добавить в сессию" or "Создать сессию и добавить"
                if rollInitiative then caption = scene.session and "Бросить инициативу" or "Создать сессию и бросить" end
                content[#content + 1] = button(caption, WIDTH - 20, submit, "#514479")
            end
            draw(scene.session and safeText(roster.session_name) or "Создание активной сессии", content)
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
    local buttons = {button("Бросить инициативу", 168, rollSelectedInitiative, "#514479")}
    if master then buttons[#buttons + 1] = button("В сессию · SessionLab", 168, enrollSelected, "#514479") end
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
    keybinds.Register{command = COMMAND, name = "SessionLab — меню токена", section = "gameplay"}
    keybinds.Register{command = ENROLL_COMMAND, name = "SessionLab — в сессию", section = "gameplay"}
    keybinds.Register{command = INITIATIVE_COMMAND, name = "SessionLab — бросить инициативу", section = "gameplay"}
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
