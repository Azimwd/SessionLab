-- SessionLab / DMHub bridge. Keep your campaign token private.
local URL = "https://sessionlab.up.railway.app"
local TOKEN = "PASTE_NEW_TOKEN_HERE"
local PERSONAL_TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"
local INTERVAL = 3
local CHAT_ENABLED = true
local HISTORY = 6

local old = rawget(_G, "SessionLabBridgeRuntime")
if old then old.active = false end
local state = {
    active = false, busy = false, run = 0, cursor = "latest",
    seen = {}, cards = {},
    rows = {}, status = nil,
}
rawset(_G, "SessionLabBridgeRuntime", state)
local handleAction, onEvent
local function hasPersonal()
    return PERSONAL_TOKEN~="" and PERSONAL_TOKEN:sub(1,6)~="PASTE_"
end

local dock = rawget(_G, "DockablePanel")
local ui = rawget(_G, "gui")
local W = 320
local function fmt(value)
    return type(value) == "number" and string.format("%g", value) or tostring(value or "")
end
local function label(text, width, size, color, align)
    return ui.Label{ text = tostring(text or ""), width = width, height = "auto",
        fontSize = size or 13, fontWeight = size and size>=16 and "bold" or nil, color = color or "#F4F5F7", halign = "left", valign = "top",
        textAlignment = align or "left", hmargin = 0, vmargin = 2, hpad = 0, vpad = 0 }
end
local function column(children, width, align)
    return ui.Panel{ width = width, height = "auto", flow = "vertical", halign = align or "left",
        valign = "top", hmargin = 0, vmargin = 0, hpad = 0, vpad = 0, children = children }
end
local function button(text, width, fn, disclosure, class)
    return ui.Button{ text = text, width = width, height = disclosure and 28 or 34,
        fontSize = 13, color = disclosure and "#ABA2FF" or "#FFFFFF",
        classes = {class or (disclosure and "slbc-disclosure" or "slbc-button")},
        hmargin = 0, vmargin = 3, hpad = 0, vpad = 0, halign = "left", valign = "top",
        textAlignment = disclosure and "left" or "center", press = fn }
end
local function surface(children, width, class)
    return ui.Panel{ width = width, height = "auto", flow = "vertical", halign = "left",
        valign = "top", hmargin = 0, vmargin = 5, hpad = 0, vpad = 0, classes = {class},
        children = {ui.Panel{ width = width, height = 10 }, column(children, width-20, "center"),
            ui.Panel{ width = width, height = 10 }} }
end
local function richData(ev)
    if type(ev.card) == "table" then return ev.card end
    local d = ev.display or {}
    local rich = {rows = {}, saves = {}, tags = {}, description = d.description or ""}
    local failed, passed = tostring(d.detail or ""):match("Провал%s+(%d+)%s*·%s*успех%s+(%d+)")
    local slot = tostring(d.detail or ""):match("Ячейка%s+(%d+)")
    if slot then rich.tags[1] = "Ячейка "..slot.." ур." end
    if failed then
        rich.rows[1] = {label="Урон", value=failed, tone="damage", detail=""}
        rich.saves[1] = {dc=d.secondary and d.secondary.value or "?", failed=failed, passed=passed}
    else
        for _,v in ipairs({d.primary or false,d.secondary or false}) do
            if v then
                if v.label == "СЛ спасброска" then rich.saves[#rich.saves+1]={dc=v.value}
                else rich.rows[#rich.rows+1]={label=v.label,value=v.value,detail=d.detail or "",tone=v.label=="Урон" and "damage" or "roll"} end
            end
        end
    end
    if #rich.rows==0 and rich.description=="" then rich.description=ev.summary or "" end
    return rich
end
local function resultRow(row, width)
    local inner = width-20
    local value = fmt(row.value)
    local color = row.tone=="damage" and "#F08491" or row.tone=="heal" and "#45CBA6" or "#F4F5F7"
    local left = {label(row.label,inner-110,13)}
    if row.detail and row.detail~="" then left[#left+1]=label(row.detail,inner-110,11,"#A0A6B2") end
    return surface({ui.Panel{width=inner,height="auto",flow="horizontal",hmargin=0,vmargin=0,hpad=0,vpad=0,
        children={column(left,inner-110),ui.Panel{width=8,height=1},label(value,102,#value>=8 and 20 or #value>=6 and 24 or 30,color,"right")}}},width,"slbc-result")
end
local function resultCard(ev)
    local inner = W-20
    local rich = richData(ev)
    local content
    local function children()
        local time=""
        local stamp=tonumber(rich.timestamp)
        if stamp then pcall(function() time=os.date("%H:%M",math.floor(stamp)) end) end
        local items={label(ev.title,inner,17),label(ev.actor..(time~="" and " · "..time or ""),inner,11,"#A0A6B2")}
        for _,row in ipairs(rich.rows or {}) do items[#items+1]=resultRow(row,inner) end
        for _,save in ipairs(rich.saves or {}) do
            local lines={label("Спасбросок"..(save.ability and save.ability~="" and ": "..save.ability or "").." · СЛ "..fmt(save.dc),inner-20,12,"#C5BDFF")}
            if save.failed~=nil then lines[#lines+1]=label("Провал: "..fmt(save.failed).." / Успех: "..fmt(save.passed),inner-20,16) end
            items[#items+1]=surface(lines,inner,"slbc-notice")
        end
        local tags=rich.tags or {}
        for i=1,#tags,2 do
            local width=math.floor((inner-6)/2)
            local parts={surface({label(tags[i],width-20,10,"#BFC4D0")},width,"slbc-tag")}
            if tags[i+1] then parts[#parts+1]=ui.Panel{width=6,height=1} parts[#parts+1]=surface({label(tags[i+1],width-20,10,"#BFC4D0")},width,"slbc-tag") end
            items[#items+1]=ui.Panel{width=inner,height="auto",flow="horizontal",hmargin=0,vmargin=0,hpad=0,vpad=0,children=parts}
        end
        if rich.notice and rich.notice~="" then items[#items+1]=surface({label(rich.notice,inner-20,12,"#D8D2FF")},inner,"slbc-notice") end
        if rich.description and rich.description~="" then
            items[#items+1]=button(ev.expanded and "Скрыть описание" or "Описание действия >",inner,function()
                ev.expanded=not ev.expanded
                content.children=children()
            end,true)
            if ev.expanded then items[#items+1]=label(rich.description,inner,13) end
        end
        if rich.components and rich.components~="" then items[#items+1]=label("Компоненты: "..rich.components,inner,10,"#A0A6B2") end
        if #items<=2 then items[#items+1]=label(ev.summary~="" and ev.summary or "Смотрите описание действия",inner,13,"#A0A6B2") end
        items[#items+1]=label("Урон и лечение применяются по решению за столом.",inner,10,"#858C9B")
        return items
    end
    content=column(children(),inner,"center")
    return ui.Panel{width=W,height="auto",flow="vertical",halign="center",valign="top",
        hmargin=0,vmargin=6,hpad=0,vpad=0,classes={"slbc-card"},children={ui.Panel{width=W,height=10},content,ui.Panel{width=W,height=10}}}
end
local function renderHistory()
    if not state.body then return end
    local children={}
    for _,ev in ipairs(state.cards) do children[#children+1]=resultCard(ev) end
    if #children==0 then children[1]=surface({label("Пока нет бросков",W-20,16),label("Подключите мост и выполните бросок в SessionLab.",W-20,12,"#A0A6B2")},W,"slbc-card") end
    state.body.children=children
end
local function updatePanel()
    if state.status then
        state.status.text=state.active and (state.connected and "На связи · каждые 3 сек." or "Подключение...") or "Мост остановлен"
    end
    if state.connectButton then state.connectButton.text=state.active and "Остановить" or "Подключить" end
end
local diceTypes={4,6,8,20,10,12,100}
state.dice={} state.diceStack={} state.visibility="public" state.modifier="0"
local renderDice
local function diceFormula()
    local parts,seen={},{}
    for _,sides in ipairs(state.diceStack) do local count=state.dice[sides] or 0
        if count>0 and not seen[sides] then parts[#parts+1]=fmt(count).."d"..fmt(sides) seen[sides]=true end
    end
    local result=table.concat(parts,"+")
    local bonus=tonumber(state.modifier)
    if result~="" and bonus and bonus~=0 then result=result..string.format("%+g",bonus) end
    return result
end
local function updateDice()
    if state.formulaLabel then state.formulaLabel.text=diceFormula()~="" and diceFormula() or "Выберите кубики" end
    for sides,b in pairs(state.dieButtons or {}) do
        local count=state.dice[sides] or 0 b.text="D"..sides..(count>0 and " x"..count or "")
    end
    if state.rollButton then state.rollButton.text=state.rollBusy and "Бросок..." or state.rollPending and "Повторить запрос" or "Бросить" end
    if state.diceStatus then state.diceStatus.text=state.diceMessage or "" end
end
local function loadDiceContext()
    if not hasPersonal() then state.diceMessage="Для бросков укажите PERSONAL_TOKEN — личный ключ листа." updateDice() return end
    local function success(raw)
        if rawget(_G,"SessionLabBridgeRuntime")~=state then return end
        local ok,reply=pcall(function() return type(raw)=="table" and raw or dmhub.FromJson(raw) end)
        if not ok or type(reply)~="table" or type(reply.data)~="table" then
            state.diceMessage="Не удалось загрузить персонажей. Проверьте личный ключ." updateDice() return
        end
        state.context=reply.data
        local valid=state.actorId==nil and state.context.is_dm
        for _,c in ipairs(state.context.characters or {}) do if c.id==state.actorId then valid=true end end
        if not valid then state.actorId=nil if not state.context.is_dm and (state.context.characters or {})[1] then state.actorId=state.context.characters[1].id end end
        state.diceMessage="Кампания: "..tostring(state.context.campaign or "")
        renderDice()
    end
    local function failure()
        if rawget(_G,"SessionLabBridgeRuntime")~=state then return end
        state.context=nil state.diceMessage="Ошибка загрузки листов. Проверьте PERSONAL_TOKEN." renderDice()
    end
    local ok=pcall(function() net.Get{url=URL.."/api/integrations/dmhub/sheets/",headers={Authorization="Bearer "..PERSONAL_TOKEN,Accept="application/json"},success=success,error=failure,failure=failure} end)
    if not ok then failure() end
end
local function sendDice()
    if state.rollBusy then return end
    if not hasPersonal() then state.diceMessage="Укажите PERSONAL_TOKEN — личный ключ листа." updateDice() return end
    if not state.context then state.diceMessage="Сначала загрузите персонажей." updateDice() return end
    if not state.rollPending then
        local bonus=tonumber(state.modifier)
        if not bonus or bonus~=math.floor(bonus) or math.abs(bonus)>10000 then state.diceMessage="Модификатор: целое число от -10000 до 10000." updateDice() return end
        if diceFormula()=="" then state.diceMessage="Выберите хотя бы один кубик." updateDice() return end
        if state.actorId==nil and not state.context.is_dm then state.diceMessage="Выберите своего персонажа." updateDice() return end
        state.diceSeq=(state.diceSeq or 0)+1
        state.rollPending={body={formula=diceFormula(),character=state.actorId,visibility=state.visibility},
            key="native-dice-"..os.time().."-"..state.diceSeq.."-"..math.random(100000,999999)}
    end
    local pending=state.rollPending
    state.rollBusy=true state.diceMessage="Отправка броска..." updateDice()
    local finished=false
    local function failure(reason)
        if finished or rawget(_G,"SessionLabBridgeRuntime")~=state then return end
        finished=true state.rollBusy=false
        state.diceMessage="Запрос не подтверждён: "..tostring(reason or "ошибка сети"):sub(1,150)..". Повтор использует тот же ключ."
        updateDice()
    end
    local function success(raw)
        if finished or rawget(_G,"SessionLabBridgeRuntime")~=state then return end
        local ok,reply=pcall(function() return type(raw)=="table" and raw or dmhub.FromJson(raw) end)
        if not ok or type(reply)~="table" or type(reply.data)~="table" or not reply.data.id then failure("неверный ответ API") return end
        finished=true state.rollBusy=false state.rollPending=nil
        state.diceMessage=reply.data.visibility=="dm" and "Бросок сохранён: только мастеру." or "Бросок сохранён: вся комната."
        onEvent(reply.data) updateDice()
    end
    local ok,err=pcall(function() net.Post{url=URL.."/api/integrations/dmhub/dice/",data=pending.body,
        headers={Authorization="Bearer "..PERSONAL_TOKEN,Accept="application/json",["Content-Type"]="application/json",["Idempotency-Key"]=pending.key},success=success,error=failure,failure=failure} end)
    if not ok then failure(err) end
end
renderDice=function()
    if not state.diceHost then return end
    state.dieButtons={}
    local rows={label("Бросить кубики",W,16)}
    for _,range in ipairs({{1,4},{5,7}}) do
        local children={} local n=range[2]-range[1]+1 local width=math.floor((W-8*(n-1))/n)
        for i=range[1],range[2] do local sides=diceTypes[i]
            if i>range[1] then children[#children+1]=ui.Panel{width=8,height=1} end
            local b=button("D"..sides,width,function()
                if state.rollBusy or state.rollPending then return end
                if #state.diceStack>=50 then state.diceMessage="Максимум 50 кубиков за бросок." updateDice() return end
                state.dice[sides]=(state.dice[sides] or 0)+1 state.diceStack[#state.diceStack+1]=sides updateDice()
            end,false,"slbc-die")
            state.dieButtons[sides]=b children[#children+1]=b
        end
        rows[#rows+1]=ui.Panel{width=W,height="auto",flow="horizontal",hmargin=0,vmargin=0,hpad=0,vpad=0,children=children}
    end
    state.formulaLabel=label("",W,16,"#ABA2FF") rows[#rows+1]=state.formulaLabel
    local actor="Не выбран"
    if state.context then
        if state.actorId==nil and state.context.is_dm then actor="Мастер" end
        for _,c in ipairs(state.context.characters or {}) do if c.id==state.actorId then actor=c.name end end
    end
    rows[#rows+1]=label("От лица: "..actor,W,12)
    rows[#rows+1]=button("Выбрать персонажа / мастера >",W,function() if state.rollBusy or state.rollPending then return end state.actorMenu=not state.actorMenu renderDice() end,true)
    if state.actorMenu and state.context then
        if state.context.is_dm then rows[#rows+1]=button("Мастер",W,function() state.actorId=nil state.actorMenu=false renderDice() end) end
        local groups={}
        for _,f in ipairs(state.context.folders or {}) do groups[#groups+1]={id=tonumber(f.id),name=f.name,items={}} end
        groups[#groups+1]={id=0,name="Без папки",items={}}
        for _,c in ipairs(state.context.characters or {}) do
            local target=groups[#groups] for _,g in ipairs(groups) do if g.id==tonumber(c.folder) then target=g break end end
            target.items[#target.items+1]=c
        end
        for _,g in ipairs(groups) do if #g.items>0 then
            rows[#rows+1]=label(g.name,W,12,"#ABA2FF")
            for _,c in ipairs(g.items) do local character=c
                rows[#rows+1]=button(c.name,W,function() state.actorId=character.id state.actorMenu=false renderDice() end,true)
            end
        end end
    end
    local visibilityButton
    visibilityButton=button(state.visibility=="dm" and "Только мастер" or "Вся комната",184,function()
        if state.rollBusy or state.rollPending then return end
        state.visibility=state.visibility=="public" and "dm" or "public"
        visibilityButton.text=state.visibility=="dm" and "Только мастер" or "Вся комната"
    end,false,"slbc-die")
    local modifier=ui.Input{text=state.modifier,width=70,height=34,fontSize=13,hmargin=0,vmargin=3,hpad=0,vpad=0,
        edit=function(e) if not state.rollBusy and not state.rollPending then state.modifier=e.text updateDice() end end,
        change=function(e) if not state.rollBusy and not state.rollPending then state.modifier=e.text updateDice() end end}
    rows[#rows+1]=ui.Panel{width=W,height="auto",flow="horizontal",hmargin=0,vmargin=0,hpad=0,vpad=0,
        children={visibilityButton,ui.Panel{width=8,height=1},label("Бонус",50,12),ui.Panel{width=8,height=1},modifier}}
    state.rollButton=button("Бросить",124,sendDice)
    rows[#rows+1]=ui.Panel{width=W,height="auto",flow="horizontal",hmargin=0,vmargin=0,hpad=0,vpad=0,children={
        button("Убрать 1",90,function()
            if state.rollBusy or state.rollPending then return end
            local sides=table.remove(state.diceStack) if sides then state.dice[sides]=state.dice[sides]-1 end updateDice()
        end,false,"slbc-die"),ui.Panel{width=8,height=1},button("Очистить",90,function()
            if state.rollBusy then return end
            state.dice={} state.diceStack={} state.modifier="0" state.rollPending=nil
            state.diceMessage="Набор очищен. Если был сбой запроса, проверьте журнал сессии." renderDice()
        end,false,"slbc-die"),ui.Panel{width=8,height=1},state.rollButton}}
    rows[#rows+1]=button("Обновить список персонажей",W,loadDiceContext,true)
    state.diceStatus=label(state.diceMessage or "",W,11,"#A0A6B2") rows[#rows+1]=state.diceStatus
    state.diceHost.children=rows updateDice()
end

if dock and ui then
    dock.Register{
        name="SessionLab · броски",minWidth=350,maxWidth=440,vscroll=false,
        content=function()
            state.status=label("Мост остановлен",W,12,"#A0A6B2")
            local status=state.status
            state.connectButton=button(state.active and "Остановить" or "Подключить",W,function() handleAction(state.active and "stop" or "start") end)
            state.body=column({},W,"center")
            state.diceHost=column({},W,"center")
            local children={label("Результаты сессии",W,20),state.status,state.connectButton,state.diceHost,state.body}
            -- Own one bounded viewport: clip immediately, including at scroll position zero.
            -- Dock's auto-height content wrapper otherwise lets card backgrounds paint over the frame.
            local panel=ui.Panel{width="100%-8",height="100%-8",flow="vertical",halign="center",valign="top",hmargin=4,vmargin=4,hpad=0,vpad=0,
                vscroll=true,clip=true,clipHidden=false,hideObjectsOutOfScroll=false,
                bgimage="panels/square.png",bgcolor="#101217ff",children={ui.Panel{width=W,height=6},column(children,W,"center"),ui.Panel{width=W,height=12}},
                styles={
                    {selectors={"slbc-card"},priority=100,bgimage="panels/square.png",bgcolor="#1A1E26ff",borderWidth=1,borderColor="#303642ff",cornerRadius=9,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-result"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",cornerRadius=7,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-tag"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",borderWidth=1,borderColor="#303642ff",cornerRadius=4,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-notice"},priority=100,bgimage="panels/square.png",bgcolor="#302A4Aff",cornerRadius=7,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-die"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",borderWidth=1,borderColor="#303642ff",cornerRadius=6,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-button"},priority=100,bgimage="panels/square.png",bgcolor="#695CF5ff",cornerRadius=6,borderWidth=0,hpad=0,vpad=0,hmargin=0},
                    {selectors={"slbc-disclosure"},priority=100,bgimage="panels/square.png",bgcolor="#1A1E26ff",borderWidth=0,hpad=0,vpad=0,hmargin=0},
                },
                destroy=function()
                    if state.status==status then state.status,state.connectButton,state.body,state.diceHost=nil,nil,nil,nil
                        state.dieButtons={} state.formulaLabel=nil state.rollButton=nil state.diceStatus=nil end
                end}
            renderHistory() renderDice() updatePanel()
            if hasPersonal() and not state.context then loadDiceContext() end
            return panel
        end,
    }
end

onEvent=function(ev)
    local id = ev.id and fmt(ev.id)
    if id and state.seen[id] then return end
    if id then state.seen[id] = true end
    local actor = tostring(ev.actor or "SessionLab")
    local title = tostring(ev.title or "Бросок")
    local summary = tostring(ev.summary or ev.text or ""):gsub("%s+", " ")
    table.insert(state.cards, 1, {
        actor = actor, title = title, summary = summary,
        display = type(ev.display) == "table" and ev.display or nil,
        card = type(ev.card) == "table" and ev.card or nil,
        visibility = ev.visibility,
    })
    while #state.cards > HISTORY do table.remove(state.cards) end
    renderHistory()
    updatePanel()
    local relay = not hasPersonal() or (state.context and state.context.is_dm)
    if CHAT_ENABLED and relay and ev.visibility~="dm" and type(ev.text) == "string" and ev.text ~= "" then
        pcall(chat.Send, actor .. " · " .. title
            .. (summary ~= "" and " — " .. summary or ""))
    end
end

local poll
poll = function(run)
    if _G.SessionLabBridgeRuntime ~= state or not state.active
        or state.run ~= run or state.busy then return end
    state.busy = true
    local finished = false
    local function finish()
        if finished then return end
        finished = true
        if _G.SessionLabBridgeRuntime ~= state or state.run ~= run then return end
        state.busy = false
        if state.active then
            dmhub.Schedule(INTERVAL, function() poll(run) end)
        end
    end
    local function success(body)
        if finished then return end
        if _G.SessionLabBridgeRuntime ~= state or state.run ~= run then return end
        local ok, reply = pcall(function()
            if type(body) == "table" then return body end
            return dmhub.FromJson(body)
        end)
        local data = ok and type(reply) == "table" and reply.data
        if type(data) == "table" and type(data.events) == "table" then
            state.connected = true
            for _, ev in ipairs(data.events) do
                if type(ev) == "table" then
                    local sent, err = pcall(onEvent, ev)
                    if not sent then print("SessionLab event: " .. tostring(err)) end
                    if ev.id ~= nil then state.cursor = type(ev.id) == "number" and string.format("%d", ev.id) or tostring(ev.id) end
                end
            end
            if data.cursor ~= nil then state.cursor = type(data.cursor) == "number" and string.format("%d", data.cursor) or tostring(data.cursor) end
        else
            state.connected = false
            print("SessionLab API: " .. tostring(ok and type(reply) == "table" and reply.error or reply))
        end
        updatePanel()
        finish()
    end
    local function failure(reason)
        if finished or state.run ~= run or rawget(_G, "SessionLabBridgeRuntime") ~= state then return end
        state.connected = false
        updatePanel()
        print("SessionLab HTTP: " .. tostring(reason))
        finish()
    end
    local ok, err = pcall(function()
        net.Get{
            url = URL .. (hasPersonal() and "/api/integrations/dmhub/dice/events/?cursor=" or "/api/integrations/dmhub/events/?cursor=") .. state.cursor,
            headers = { ["Authorization"] = "Bearer " .. (hasPersonal() and PERSONAL_TOKEN or TOKEN),
                ["Accept"] = "application/json" },
            success = success,
            error = failure, failure = failure,
        }
    end)
    if not ok then print("SessionLab HTTP: " .. tostring(err)); finish() end
end

handleAction = function(args)
    local action = tostring(args or ""):lower():match("^%s*(.-)%s*$")
    if action == "status" then
        chat.Send("[SessionLab] " .. (state.active and "ON" or "OFF")
            .. " · " .. state.cursor)
        return
    end
    if action == "stop" or action == "restart" then
        state.connected = false
        state.active, state.busy = false, false
        state.run = state.run + 1
        updatePanel()
        if action == "stop" then return end
    elseif action ~= "" and action ~= "start" then
        chat.Send("[SessionLab] /slbridge [start|stop|status|restart]")
        return
    elseif state.active then return end
    if not hasPersonal() and (TOKEN == "PASTE_NEW_TOKEN_HERE" or TOKEN == "") then
        chat.Send("[SessionLab] Вставьте ключ в TOKEN")
        return
    end
    state.active, state.busy, state.cursor = true, false, "latest"
    state.connected = false
    state.run = state.run + 1
    updatePanel()
    poll(state.run)
end
Commands.slbridge = handleAction
-- End of SessionLab Bridge.
-- Paste guard: no executable Lua follows this line.
-- The bridge code above is complete.
-- If this comment is missing, paste the file again.
-- Keep your existing TOKEN when updating Main.lua.
-- A fresh token is needed only after rotation or revocation.
-- End.
