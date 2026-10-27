-- SessionLab character sheet for DMHub. Install as a SECOND code mod.
-- This is a view/controller for the SessionLab sheet, not a DMHub-native actor.
local URL = "https://sessionlab.up.railway.app"
local SHEET_TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"
local POLL_SECONDS = 6

local previous = rawget(_G, "SessionLabSheetRuntime")
if previous then previous.active = false end
local state = {active = false, busy = false, run = 0, selected = nil,
    list = {}, details = nil, tab = "stats", page = 1, expanded = nil,
    slots = {}, amount = 5, root = nil, message = "Нажмите /slsheet start"}
_G.SessionLabSheetRuntime = state

local labels = {str = "Сила", dex = "Ловкость", con = "Телосложение",
    int = "Интеллект", wis = "Мудрость", cha = "Харизма"}
local keys = {"str", "dex", "con", "int", "wis", "cha"}
local names = {acrobatics = "Акробатика", animal_handling = "Уход за животными",
    arcana = "Магия", athletics = "Атлетика", deception = "Обман",
    history = "История", insight = "Проницательность", intimidation = "Запугивание",
    investigation = "Анализ", medicine = "Медицина", nature = "Природа",
    perception = "Внимательность", performance = "Выступление",
    persuasion = "Убеждение", religion = "Религия", sleight_of_hand = "Ловкость рук",
    stealth = "Скрытность", survival = "Выживание"}
local skillKeys = {"acrobatics", "animal_handling", "arcana", "athletics",
    "deception", "history", "insight", "intimidation", "investigation",
    "medicine", "nature", "perception", "performance", "persuasion",
    "religion", "sleight_of_hand", "stealth", "survival"}

local function auth()
    return { ["Authorization"] = "Bearer " .. SHEET_TOKEN,
        ["Accept"] = "application/json" }
end
local function decode(body)
    if type(body) == "table" then return body end
    return json.decode(body)
end
local function explain(error)
    if type(error) == "string" then return error end
    if type(error) == "table" then
        return explain(error.detail or error.non_field_errors or error[1] or "Проверьте данные")
    end
    return "Ошибка запроса"
end
local function guid()
    -- One idempotency key per click; retry with the same key on network failure.
    state.serial = (state.serial or 0) + 1
    return tostring(os.time()) .. "-" .. tostring(state.serial) .. "-" .. tostring(math.random(100000, 999999))
end
local function signed(n)
    n = tonumber(n) or 0
    return n >= 0 and ("+" .. tostring(n)) or tostring(n)
end
local function resultText(data)
    local p = type(data.payload) == "table" and data.payload or nil
    if not p then return "" end
    local parts = p.parts or {p}
    local first = parts[1] or {}
    local text = tostring(p.label or "Действие")
    if first.roll then text = text .. " · бросок " .. tostring(first.roll.total) end
    if first.damage then text = text .. " · урон " .. tostring(first.damage.total) end
    if first.save then
        text = text .. " · СЛ " .. tostring(first.save.dc)
        if first.save.failed_damage then
            text = text .. " · провал " .. tostring(first.save.failed_damage) ..
                " / успех " .. tostring(first.save.success_damage)
        end
    end
    return text
end
local function label(text, size, color)
    return gui.Label{ text = tostring(text or ""), fontSize = size or 15,
        color = color or "#F4F5F7", width = "100%", height = "auto", vmargin = 2 }
end
local function button(text, action)
    return gui.Label{ text = text, color = "#F4F5F7", fontSize = 15,
        width = "100%", height = 29, vmargin = 2, bgimage = "panels/square.png",
        bgcolor = "#353B50", click = function() action() end }
end
local function group(items)
    local props = {width = "100%", height = "auto", flow = "vertical",
        vmargin = 4, bgimage = "panels/square.png", bgcolor = "#232833"}
    for i, item in ipairs(items) do props[i] = item end
    return gui.Panel(props)
end
local render, refresh
local function apiGet(path, done)
    local run = state.run
    local ok, err = pcall(function()
        net.Get{url = URL .. path, headers = auth(),
            success = function(body)
                if not state.active or run ~= state.run then return end
                local parsed, reply = pcall(decode, body)
                if parsed and type(reply) == "table" and type(reply.data) == "table" then
                    done(reply.data)
                else
                    state.message = parsed and explain(reply.error) or "Некорректный ответ API"
                    render()
                end
            end,
            failure = function(reason)
                if not state.active or run ~= state.run then return end
                state.message = "Нет связи: " .. tostring(reason):sub(1, 90)
                render()
            end}
    end)
    if not ok then state.message = tostring(err):sub(1, 100); render() end
end
local function apiPost(path, data)
    if state.busy then return end
    if type(net.Post) ~= "function" or type(json.encode) ~= "function" then
        state.message = "Эта версия DMHub не поддерживает net.Post/json.encode"
        render()
        return
    end
    state.busy = true
    state.message = "Выполняется…"
    render()
    local key = guid()
    local run = state.run
    local encoded = json.encode(data)
    local headers = auth()
    headers["Content-Type"] = "application/json"
    headers["Idempotency-Key"] = key
    local function finish(message, shouldRefresh)
        if not state.active or run ~= state.run then return end
        state.busy = false
        state.message = message
        if shouldRefresh then refresh() else render() end
    end
    local ok, err = pcall(function()
        net.Post{url = URL .. path, headers = headers,
            data = encoded, body = encoded,
            success = function(body)
                local parsed, reply = pcall(decode, body)
                if parsed and type(reply) == "table" and type(reply.data) == "table" then
                    if reply.data.payload then state.last = resultText(reply.data) end
                    finish("Результат сохранён в SessionLab", true)
                else
                    finish(parsed and explain(reply.error) or "Некорректный ответ", false)
                end
            end,
            failure = function(reason)
                finish("Связь прервалась. Проверьте результат в SessionLab перед повтором: " ..
                    tostring(reason):sub(1, 50), false)
            end}
    end)
    if not ok then finish("POST не поддерживается: " .. tostring(err):sub(1, 75), false) end
end
refresh = function()
    if not state.active then return end
    if not state.selected then
        apiGet("/api/integrations/dmhub/sheets/", function(data)
            state.list = data.characters or {}
            if #state.list > 0 then state.selected = state.list[1].id; refresh()
            else state.message = "В кампании нет доступных листов"; render() end
        end)
        return
    end
    apiGet("/api/integrations/dmhub/sheets/" .. state.selected .. "/", function(data)
        state.details = data
        state.message = "Лист синхронизирован"
        render()
    end)
end

local function roll(kind, key)
    if state.selected then
        apiPost("/api/integrations/dmhub/sheets/" .. state.selected .. "/roll/",
            {kind = kind, key = key})
    end
end
local function useAbility(action)
    if not state.selected then return end
    local level = state.slots[action.id] or action.level or 0
    if action.kind == "spell" and action.level > 0 then
        local slots = state.details and state.details.sheet and state.details.sheet.slots or {}
        local slot = slots[tostring(level)]
        if not slot or slot.used >= slot.max then
            level = nil
            for n = action.level, (action.upcast_allowed and 9 or action.level) do
                local entry = slots[tostring(n)]
                if entry and entry.used < entry.max then level = n; break end
            end
        end
        if not level then state.message = "Нет свободных ячеек"; render(); return end
        state.slots[action.id] = level
    end
    apiPost("/api/integrations/dmhub/sheets/" .. state.selected ..
        "/abilities/" .. action.id .. "/use/", {slot_level = level})
end
local function actionCard(action)
    local rows = {}
    local spell = action.kind == "spell"
    local title = (spell and (action.level == 0 and "Заговор" or (action.level .. " круг"))
        or "Атака") .. " · " .. action.name
    rows[#rows + 1] = button(title, function()
        state.expanded = state.expanded == action.id and nil or action.id
        render()
    end)
    if state.expanded ~= action.id then
        rows[#rows + 1] = button("Применить", function()
            if not state.busy then useAbility(action) end
        end)
    end
    if state.expanded == action.id then
        local level = state.slots[action.id] or action.level or 0
        rows[#rows + 1] = label(action.casting_time .. " · " ..
            (action.range ~= "" and action.range or "Дистанция не указана") .. " · " ..
            (action.duration ~= "" and action.duration or "Длительность не указана"), 13, "#A0A6B2")
        if spell and action.level > 0 then
            local sheet = state.details.sheet
            local available = {}
            for n = action.level, 9 do
                local slot = sheet.slots[tostring(n)]
                if slot and slot.max > slot.used and (n == action.level or action.upcast_allowed) then
                    available[#available + 1] = n
                end
            end
            if #available > 0 then
                if not sheet.slots[tostring(level)] or
                    sheet.slots[tostring(level)].max <= sheet.slots[tostring(level)].used then
                    level = available[1]
                    state.slots[action.id] = level
                end
                rows[#rows + 1] = label("Ячейка " .. level .. " · свободно " ..
                    (sheet.slots[tostring(level)].max - sheet.slots[tostring(level)].used), 14)
                if #available > 1 then
                    rows[#rows + 1] = button("Выбрать другую ячейку", function()
                        for i, n in ipairs(available) do
                            if n == level then state.slots[action.id] = available[i % #available + 1]; break end
                        end
                        render()
                    end)
                end
            else
                rows[#rows + 1] = label("Нет доступных ячеек", 14, "#F08491")
            end
        end
        rows[#rows + 1] = label(action.description or "", 14, "#A0A6B2")
        local canUse = not spell or action.level == 0 or
            (state.details.sheet.slots[tostring(level)] and
                state.details.sheet.slots[tostring(level)].max >
                state.details.sheet.slots[tostring(level)].used)
        if canUse then
            rows[#rows + 1] = button(state.busy and "Подождите…" or "Применить · бросить", function()
                if not state.busy then useAbility(action) end
            end)
        end
    end
    return group(rows)
end

render = function()
    if not state.root then return end
    local items = {label("SessionLab · лист персонажа", 23),
        label(state.message, 13, "#A0A6B2")}
    if state.last and state.last ~= "" then
        items[#items + 1] = label(state.last, 19, "#45CBA6")
    end
    if not state.active then
        items[#items + 1] = label("/slsheet start — включить лист", 14)
    else
        items[#items + 1] = button("Обновить лист", refresh)
        for _, character in ipairs(state.list) do
            items[#items + 1] = button((state.selected == character.id and "• " or "") ..
                character.name, function()
                state.selected, state.details, state.expanded, state.page = character.id, nil, nil, 1
                refresh()
            end)
        end
        local data = state.details
        if data and data.character.id == state.selected then
            local c, sheet = data.character, data.sheet
            local stats = sheet.computed
            items[#items + 1] = group{
                label(c.name .. " · " .. (c.class or "") .. " · " .. c.level .. " ур.", 21),
                label("КД " .. sheet.armor_class .. "   Хиты " .. sheet.hp_current ..
                    "/" .. sheet.hp_max .. "   Врем. " .. sheet.hp_temp, 17),
                label("Инициатива " .. signed(stats.initiative) ..
                    "   Скорость " .. sheet.speed .. " фт.", 15),
            }
            for _, tab in ipairs({"stats", "skills", "attacks", "spells", "notes"}) do
                local captions = {stats = "Характеристики", skills = "Навыки",
                    attacks = "Атаки", spells = "Заклинания", notes = "Инвентарь и заметки"}
                items[#items + 1] = button((state.tab == tab and "• " or "") .. captions[tab],
                    function() state.tab, state.page, state.expanded = tab, 1, nil; render() end)
            end
            if state.tab == "stats" then
                for _, key in ipairs(keys) do
                    local attr = key
                    items[#items + 1] = button(labels[key] .. "  " .. sheet.abilities[key] ..
                        "  (" .. signed(stats.modifiers[key]) .. ") · бросить",
                        function() roll("ability", attr) end)
                    items[#items + 1] = button("Спасбросок " .. labels[key] .. "  " ..
                        signed(stats.saves[key]), function() roll("save", attr) end)
                end
                items[#items + 1] = button("Бросить инициативу", function() roll("initiative", "") end)
                for _, kind in ipairs({"damage", "heal", "temporary"}) do
                    local captions = {damage = "Урон", heal = "Лечение", temporary = "Временные хиты"}
                    items[#items + 1] = button(captions[kind] .. " · " .. state.amount, function()
                        apiPost("/api/integrations/dmhub/sheets/" .. state.selected ..
                            "/resources/", {action = kind, amount = state.amount})
                    end)
                end
                items[#items + 1] = button("Изменить количество: " .. state.amount, function()
                    local amounts = {1, 5, 10, 20, 50, 100}
                    for i, v in ipairs(amounts) do
                        if v == state.amount then state.amount = amounts[i % #amounts + 1]; break end
                    end
                    render()
                end)
                items[#items + 1] = label("Состояния: " .. table.concat(sheet.conditions or {}, ", "), 14)
            elseif state.tab == "skills" then
                for _, key in ipairs(skillKeys) do
                    local skill = key
                    local rank = sheet.skills[key] or 0
                    items[#items + 1] = button(names[key] .. " " .. signed(stats.skills[key]) ..
                        (rank == 2 and " · мастерство" or rank == 1 and " · владение" or ""),
                        function() roll("skill", skill) end)
                end
            elseif state.tab == "notes" then
                items[#items + 1] = label("ИНВЕНТАРЬ", 16)
                items[#items + 1] = label(sheet.inventory or "", 14)
                items[#items + 1] = label("ЗАМЕТКИ", 16)
                items[#items + 1] = label(sheet.notes or "", 14)
                items[#items + 1] = label("ПРЕДЫСТОРИЯ", 16)
                items[#items + 1] = label(sheet.background or "", 14)
            else
                local actions = {}
                for _, action in ipairs(data.actions or {}) do
                    if action.kind == (state.tab == "spells" and "spell" or "attack") then
                        actions[#actions + 1] = action
                    end
                end
                local start = (state.page - 1) * 10 + 1
                for index = start, math.min(start + 9, #actions) do
                    items[#items + 1] = actionCard(actions[index])
                end
                if #actions == 0 then items[#items + 1] = label("Пока нет действий", 14) end
                if state.page > 1 then items[#items + 1] = button("Назад", function()
                    state.page = state.page - 1; state.expanded = nil; render() end) end
                if start + 9 < #actions then items[#items + 1] = button("Далее", function()
                    state.page = state.page + 1; state.expanded = nil; render() end) end
            end
        end
    end
    state.root.children = items
end

local function start()
    if SHEET_TOKEN == "PASTE_PERSONAL_SHEET_TOKEN_HERE" or SHEET_TOKEN == "" then
        chat.Send("[SessionLab] Вставьте личный ключ в SHEET_TOKEN")
        return
    end
    if state.active then return end
    state.active = true
    state.run = state.run + 1
    local run = state.run
    state.message = "Загружаю лист…"
    render()
    refresh()
    local function tick()
        if not state.active or run ~= state.run then return end
        if not state.busy then refresh() end
        dmhub.Schedule(POLL_SECONDS, tick)
    end
    dmhub.Schedule(POLL_SECONDS, tick)
end
Commands.slsheet = function(args)
    local action = tostring(args or ""):lower():match("^%s*(.-)%s*$")
    if action == "stop" then
        state.active = false; state.run = state.run + 1
        state.message = "Лист остановлен"; render()
    elseif action == "refresh" then refresh()
    elseif action == "" or action == "start" then start()
    else chat.Send("[SessionLab] /slsheet start|stop|refresh") end
end

if DockablePanel and gui then
    local ok, err = pcall(function()
        DockablePanel.Register{name = "SessionLab · лист", minWidth = 350,
            maxWidth = 420, vscroll = true,
            content = function()
                state.root = gui.Panel{width = "100%", height = "auto", flow = "vertical",
                    bgimage = "panels/square.png", bgcolor = "#1A1E26"}
                render()
                return state.root
            end}
    end)
    if not ok then print("SessionLab sheet: " .. tostring(err)) end
end
print("SessionLab sheet loaded · /slsheet start")
-- End.
