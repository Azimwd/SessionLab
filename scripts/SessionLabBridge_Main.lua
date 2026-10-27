-- SessionLab / DMHub bridge. Keep your campaign token private.
local URL = "https://sessionlab.up.railway.app"
local TOKEN = "PASTE_NEW_TOKEN_HERE"
local INTERVAL = 3
local CHAT_ENABLED = true
local HISTORY = 6

local old = rawget(_G, "SessionLabBridgeRuntime")
if old then old.active = false end
local state = {
    active = false, busy = false, run = 0, cursor = "latest",
    seen = old and old.seen or {}, cards = old and old.cards or {},
    rows = {}, status = nil,
}
_G.SessionLabBridgeRuntime = state

local function updatePanel()
    if state.status then
        pcall(function()
            state.status.text = state.active and "На связи · обновление каждые 3 сек."
                or "Остановлен · /slbridge start"
        end)
    end
    for i, row in ipairs(state.rows) do
        local ev = state.cards[i]
        pcall(function()
            if not ev then
                row.title.text, row.first.text, row.second.text, row.note.text = "", "", "", ""
                return
            end
            local d = ev.display or {}
            local a, b = d.primary, d.secondary
            local failed, passed = tostring(d.detail or ""):match(
                "Провал%s+(%d+)%s*·%s*успех%s+(%d+)"
            )
            row.title.text = ev.actor .. " · " .. ev.title
            if failed then
                local slot = tostring(d.detail):match("Ячейка%s+(%d+)")
                local dc = b and b.label == "СЛ спасброска" and b.value or "?"
                row.first.text = "НЕ ПРОШЁЛ: " .. failed
                row.second.text = "ПРОШЁЛ: " .. passed
                row.note.text = "Урон · СЛ " .. tostring(dc)
                    .. (slot and " · ячейка " .. slot or "")
            elseif a then
                row.first.text = tostring(a.value or "?") .. "  " .. tostring(a.label or "")
                row.second.text = b and (tostring(b.label) .. "  " .. tostring(b.value or "?")) or ""
                row.note.text = tostring(d.detail or "")
            else
                row.first.text, row.second.text = "ДЕЙСТВИЕ", ""
                row.note.text = tostring(d.description or ev.summary)
            end
        end)
    end
end

local dock = rawget(_G, "DockablePanel")
local ui = rawget(_G, "gui")
if dock and ui then
    local ok, err = pcall(function()
        dock.Register{
            name = "SessionLab · броски", minWidth = 350, maxWidth = 400,
            vscroll = true,
            content = function()
                state.rows = {}
                state.status = ui.Label{
                    text = "Остановлен · /slbridge start", color = "#A0A6B2",
                    fontSize = 14, width = "100%", height = 28,
                }
                local children = {
                    ui.Label{ text = "Результаты SessionLab", color = "#F4F5F7",
                        fontSize = 25, width = "100%", height = 40 },
                    state.status,
                }
                for i = 1, HISTORY do
                    local row = {
                        title = ui.Label{ text = "", color = "#A0A6B2",
                            fontSize = 15, width = "100%", height = 25 },
                        first = ui.Label{ text = "", color = "#F4F5F7",
                            fontSize = 32, width = "100%", height = 37 },
                        second = ui.Label{ text = "", color = "#45CBA6",
                            fontSize = 28, width = "100%", height = "auto" },
                        note = ui.Label{ text = "", color = "#A0A6B2",
                            fontSize = 14, width = "100%", height = "auto",
                            vmargin = 2 },
                    }
                    state.rows[i] = row
                    children[#children + 1] = ui.Panel{
                        row.title, row.first, row.second, row.note,
                        bgimage = "panels/square.png", bgcolor = "#232833",
                        width = "100%", height = "auto", vmargin = 5,
                        flow = "vertical",
                    }
                end
                local props = { bgimage = "panels/square.png",
                    bgcolor = "#1A1E26", width = "100%",
                    height = "auto", flow = "vertical" }
                for i, child in ipairs(children) do props[i] = child end
                local panel = ui.Panel(props)
                updatePanel()
                return panel
            end,
        }
    end)
    if not ok then print("SessionLab panel: " .. tostring(err)) end
end

local function onEvent(ev)
    local id = ev.id and tostring(ev.id)
    if id and state.seen[id] then return end
    if id then state.seen[id] = true end
    local actor = tostring(ev.actor or "SessionLab")
    local title = tostring(ev.title or "Бросок")
    local summary = tostring(ev.summary or ev.text or ""):gsub("%s+", " ")
    table.insert(state.cards, 1, {
        actor = actor, title = title, summary = summary,
        display = type(ev.display) == "table" and ev.display or nil,
    })
    while #state.cards > HISTORY do table.remove(state.cards) end
    updatePanel()
    if CHAT_ENABLED and type(ev.text) == "string" and ev.text ~= "" then
        pcall(chat.Send, actor .. " · " .. title
            .. (summary ~= "" and " — " .. summary or ""))
    end
end

local poll
poll = function(run)
    if _G.SessionLabBridgeRuntime ~= state or not state.active
        or state.run ~= run or state.busy then return end
    state.busy = true
    local function finish()
        if _G.SessionLabBridgeRuntime ~= state or state.run ~= run then return end
        state.busy = false
        if state.active then
            dmhub.Schedule(INTERVAL, function() poll(run) end)
        end
    end
    local function success(body)
        if _G.SessionLabBridgeRuntime ~= state or state.run ~= run then return end
        local ok, reply = pcall(function()
            if type(body) == "table" then return body end
            return rawget(_G, "json").decode(body)
        end)
        local data = ok and type(reply) == "table" and reply.data
        if type(data) == "table" and type(data.events) == "table" then
            for _, ev in ipairs(data.events) do
                if type(ev) == "table" then
                    local sent, err = pcall(onEvent, ev)
                    if not sent then print("SessionLab event: " .. tostring(err)) end
                    if ev.id ~= nil then state.cursor = tostring(ev.id) end
                end
            end
            if data.cursor ~= nil then state.cursor = tostring(data.cursor) end
        else
            print("SessionLab API: " .. tostring(ok and reply.error or reply))
        end
        finish()
    end
    local ok, err = pcall(function()
        net.Get{
            url = URL .. "/api/integrations/dmhub/events/?cursor=" .. state.cursor,
            headers = { ["Authorization"] = "Bearer " .. TOKEN,
                ["Accept"] = "application/json" },
            success = success,
            failure = function(reason)
                print("SessionLab HTTP: " .. tostring(reason))
                finish()
            end,
        }
    end)
    if not ok then print("SessionLab HTTP: " .. tostring(err)); finish() end
end

Commands.slbridge = function(args)
    local action = tostring(args or ""):lower():match("^%s*(.-)%s*$")
    if action == "status" then
        chat.Send("[SessionLab] " .. (state.active and "ON" or "OFF")
            .. " · " .. state.cursor)
        return
    end
    if action == "stop" or action == "restart" then
        state.active, state.busy = false, false
        state.run = state.run + 1
        updatePanel()
        if action == "stop" then return end
    elseif action ~= "" and action ~= "start" then
        chat.Send("[SessionLab] /slbridge [start|stop|status|restart]")
        return
    elseif state.active then return end
    if TOKEN == "PASTE_NEW_TOKEN_HERE" or TOKEN == "" then
        chat.Send("[SessionLab] Вставьте ключ в TOKEN")
        return
    end
    state.active, state.busy, state.cursor = true, false, "latest"
    state.run = state.run + 1
    updatePanel()
    poll(state.run)
end
-- End of SessionLab Bridge.
-- Paste guard: no executable Lua follows this line.
-- The bridge code above is complete.
-- If this comment is missing, paste the file again.
-- Keep your existing TOKEN when updating Main.lua.
-- A fresh token is needed only after rotation or revocation.
-- End.
