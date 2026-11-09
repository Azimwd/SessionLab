-- SessionLab room / initiative. Personal token only. ASCII installable file is generated.
local URL="https://sessionlab.up.railway.app"
local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
local INTERVAL=5
local old=rawget(_G,"SessionLabRoomRuntime")
if old then old.active=false if old.window then old.window:DestroySelf() end end
local S={active=false,run=0,compact=false,preview=false,tab="table",folders={},selected={},counts={},draft={name="",bonus="0",count="1"},msg="Не подключено",x=0,y=40}
rawset(_G,"SessionLabRoomRuntime",S)
local draw,refresh,openWindow,send,closeWindow,start,renderSetup,buildWindow,refreshScene
local W=560
local function fmt(v) return type(v)=="number" and string.format("%g",v) or tostring(v or "") end
local function label(t,w,size,color)
 return gui.Label{text=tostring(t or ""),width=w or W,height="auto",fontSize=size or 14,color=color or "#F4F5F7",textAlignment="left",hpad=0,vpad=0,hmargin=0,vmargin=3,blocksGameInteraction=false,interactable=false}
end
local function column(c,w) return gui.Panel{width=w or W,height="auto",flow="vertical",hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children=c} end
local function row(c,w) return gui.Panel{width=w or W,height="auto",flow="horizontal",hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children=c} end
local function card(children,w,highlight)
 w=w or W
 local inner=gui.Panel{width=w-24,height="auto",flow="vertical",halign="center",valign="top",hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children=children}
 -- Insets are explicit children; no layout writes to native userdata.
 return gui.Panel{width=w,height="auto",flow="vertical",halign="left",valign="top",hpad=0,vpad=0,hmargin=0,vmargin=6,
  bgimage="panels/square.png",bgcolor=highlight and "#26243Dff" or "#1A1E26ff",classes={highlight and "slr-current" or "slr-card"},
  blocksGameInteraction=false,children={gui.Panel{width=w,height=10,interactable=false},gui.Panel{width=w,height="auto",flow="vertical",hpad=0,vpad=0,children={inner},halign="center"},gui.Panel{width=w,height=10,interactable=false}}}
end
local function gap() return gui.Panel{width=8,height=1,interactable=false,blocksGameInteraction=false} end
local function button(t,w,f,accent)
 return gui.Button{text=t,width=w,height=32,fontSize=13,color="#F4F5F7",hoverCursor="default",bgimage="panels/square.png",bgcolor=accent and "#695CF5ff" or "#232833ff",classes={accent and "slr-accent" or "slr-button"},hpad=0,vpad=0,hmargin=0,vmargin=3,blocksGameInteraction=true,press=f}
end
local function input(key,w,placeholder)
 return gui.Input{text=S.draft[key],placeholderText=placeholder,width=w,height=32,fontSize=14,color="#F4F5F7",hoverCursor="text",bgimage="panels/square.png",bgcolor="#101217ff",classes={"slr-input"},blocksGameInteraction=true,
  change=function(e) S.draft[key]=e.text end,edit=function(e) S.draft[key]=e.text end}
end
local function status(t) S.msg=t if S.status then S.status.text=t end if S.launchStatus then S.launchStatus.text=t end end
local function active() return rawget(_G,"SessionLabRoomRuntime")==S and S.active end
local function decode(body)
 if type(body)=="table" then return body end
 return dmhub.FromJson(body)
end
local function errorText(body)
 if type(body)=="table" then
  if body.detail then return tostring(body.detail) end
  for _,v in pairs(body) do return errorText(v) end
 end
 return tostring(body or "Ошибка запроса"):sub(1,180)
end
local function http(path,body,key,done,failed)
 local run=S.run local finished=false
 local function fail(err)
  if finished then return end finished=true
  if not active() or run~=S.run then return end
  failed(err)
 end
 local opts={url=URL..path,headers={Authorization="Bearer "..TOKEN,Accept="application/json"}}
 opts.success=function(raw)
  if finished then return end
  if not active() or run~=S.run then return end
  local ok,r=pcall(decode,raw)
  if not ok or type(r)~="table" or type(r.data)~="table" or r.error then fail(ok and errorText(type(r)=="table" and r.error or r) or "Неверный JSON") return end
  finished=true done(r.data)
 end
 opts.error=fail opts.failure=fail
 if body then opts.data=body opts.headers["Idempotency-Key"]=key end
 local ok,err=pcall(function() if body then net.Post(opts) else net.Get(opts) end end)
 if not ok then fail(err) end
 -- Do not create overlapping requests if the native transport never invokes a callback.
 dmhub.Schedule(20,function() fail("Тайм-аут: проверьте состояние, затем повторите запрос") end)
end
local function fingerprint(v)
 if type(v)~="table" then return type(v)..":"..tostring(v) end
 local keys={} for k in pairs(v) do keys[#keys+1]=k end table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={} for _,k in ipairs(keys) do out[#out+1]=tostring(k).."="..fingerprint(v[k]) end return "{"..table.concat(out,";").."}"
end
refresh=function()
 if not active() or S.reading then return end
 S.reading=true
 local preview=S.preview
 local mode=preview and "?view=player" or ""
 http("/api/integrations/dmhub/room/"..mode,nil,nil,function(d)
  S.reading=false
  if preview~=S.preview then refresh() return end
  local needsWindow=not S.data or S.data.role~=d.role or S.data.master_view~=d.master_view
  if needsWindow then S.scene=nil S.sceneHash=nil S.sceneEdit=nil end
  d.revision=nil -- Unrelated chat/dice events must not rebuild the room UI.
  local hash=fingerprint(d)
  if hash~=S.hash then
   S.data=d S.hash=hash
   if d.role~="dm" then S.preview=false S.selected={} S.setup=false end
   if needsWindow and S.window then buildWindow() else draw() end
  end
  if not S.pending then status("На связи · каждые "..INTERVAL.." сек.") end
  if refreshScene then refreshScene() end
 end,function(err) S.reading=false S.data=nil S.hash=nil S.setup=false S.selected={} status(errorText(err)) if S.window then buildWindow() end end)
end
local function nextKey()
 S.seq=(S.seq or 0)+1
 return "slroom-"..tostring(os.time()).."-"..math.random(100000,999999).."-"..S.seq
end
local function transmit()
 local pending=S.pending if not pending or pending.sending then return end
 pending.sending=true status("Сохранение...")
 http(pending.path or "/api/integrations/dmhub/room/commands/",pending.body,pending.key,function()
  if S.pending~=pending then return end
  S.pending=nil S.confirm=nil S.hash=nil S.setup=false S.setupHost=nil
  if pending.scene then S.sceneEdit=nil S.sceneHash=nil S.sceneAdding=false S.removeTarget=nil S.damageTargets={} S.damageOutcomes={} refreshScene() end
  status("Сохранено") refresh() draw()
 end,function(err)
  if S.pending~=pending then return end
  pending.sending=false status(errorText(err).." · повторите тот же запрос или обновите") if S.window then buildWindow() end
 end)
end
send=function(body)
 if S.pending or not S.data or not S.data.master_view then return end
 if body.command=="initiative" then
  if not S.data.session then status("Нет активной сессии") return end
  body.version=S.data.initiative.version body.session=S.data.session.id
 end
 S.pending={body=body,key=nextKey(),sending=false} transmit()
end
local function initiative(verb,extra)
 local b=extra or {} b.command="initiative" b.action=verb send(b)
end
local function visible(scope,id,value)
 local b={command="visibility",scope=scope,visible=value}
 if scope=="folder" then b.folder=id elseif scope=="character" then b.character=id end
 send(b)
end
local function characters(forTable)
 local out={} local d=S.data or {}
 for _,c in ipairs(d.party or {}) do out[#out+1]=c end
 for _,c in ipairs((forTable and d.table_npcs) or d.npcs or {}) do out[#out+1]=c end return out
end
local function currentText()
 local t=S.data and S.data.initiative or {}
 for _,e in ipairs(t.entries or {}) do if e.id==t.current then return e.name end end
 return t.hidden_turn and "Скрытый участник" or (t.running and "Ожидание" or "Не начато")
end
local function requestReset()
 if S.confirm=="reset" then initiative("reset") else S.confirm="reset" draw() end
end
local function trackerUI()
 local t=S.data.initiative local rows={} local C=W-24
 if S.data.master_view then
  rows[#rows+1]=row({button(t.running and "Пауза" or "Продолжить",140,function() initiative(t.running and "stop" or "start") end),gap(),button("Следующий ход",200,function() initiative("next") end,true),gap(),button(S.confirm=="reset" and "Подтвердить сброс" or "Сбросить",204,requestReset)})
  if not t.running and (t.round_number or 0)==0 then rows[#rows+1]=button(S.setup and "Скрыть подготовку" or "Выбрать участников",W,function() S.setup=not S.setup draw() end) end
 end
 for i,e in ipairs(t.entries or {}) do
  local entry=e local current=e.id==t.current
  local content={label(current and "ТЕКУЩИЙ ХОД" or "УЧАСТНИК "..i,C,11,current and "#B3A9FF" or "#858D9F"),
   row({label(e.name,C-112,20,current and "#CEC6FF" or "#F4F5F7"),gap(),column({label("ИНИЦИАТИВА",104,10,"#858D9F"),label(fmt(e.initiative),104,24,"#B3A9FF")},104)},C)}
  if e.hidden then content[#content+1]=label("Скрыт от игроков",C,12,"#F0B17C") end
  if S.data.master_view and not t.running then
   content[#content+1]=row({button("Изменить",173,function() S.editEntry=entry.id S.draft.entryName=entry.name S.draft.entryScore=fmt(entry.initiative) draw() end),gap(),
    button(e.hidden and "Показать" or "Скрыть",173,function() initiative("edit",{entry=entry.id,hidden=not entry.hidden}) end),gap(),button("Убрать",174,function() initiative("remove",{entry=entry.id}) end)},C)
  end
  if S.editEntry==entry.id and not t.running then
   content[#content+1]=row({input("entryName",296,"Имя участника"),gap(),input("entryScore",104,"Инициатива"),gap(),button("Сохранить",120,function()
    local score=tonumber(S.draft.entryScore)
    if not score or score%1~=0 or score< -100 or score>100 or not S.draft.entryName:match("%S") then status("Имя и инициатива −100…100") return end
    S.editEntry=nil initiative("edit",{entry=entry.id,name=S.draft.entryName,initiative=score})
   end)},C)
  end
  rows[#rows+1]=card(content,W,current)
 end
 if #(t.entries or {})==0 then rows[#rows+1]=card({label("В инициативе пока нет участников",C,16),label("Выберите листы для подготовки боя.",C,13,"#858D9F")}) end
 return column(rows)
end
local function tableUI()
 local rows={} local d=S.data local C=W-24
 if d.master_view then rows[#rows+1]=button(d.table_visible_to_players and "Стол виден игрокам · скрыть" or "Стол скрыт · показать",W,function() visible("table",nil,not d.table_visible_to_players) end) end
 for _,f in ipairs(d.folders or {}) do
  local folder=f local key=tostring(f.id) local list={}
  for _,c in ipairs(characters(true)) do if tostring(c.folder or "unfiled")==key then list[#list+1]=c end end
  local parts={button((S.folders[key] and "+ " or "− ")..f.name.." · "..#list,d.master_view and 416 or W,function() S.folders[key]=not S.folders[key] draw() end,true)}
  if d.master_view then parts[#parts+1]=gap() parts[#parts+1]=button(f.visible_to_players and "Виден" or "Скрыт",136,function() visible("folder",folder.id,not folder.visible_to_players) end) end
  rows[#rows+1]=row(parts)
  if not S.folders[key] then
   for _,c in ipairs(list) do
    local char=c
    local content={label(c.kind=="npc" and "ПЕРСОНАЖ МАСТЕРА" or "ПЕРСОНАЖ ИГРОКА",C,10,"#858D9F"),label(c.name,C,21),label((c.character_class or "").." · Уровень "..fmt(c.level),C,13,"#A0A6B2")}
    local stats={}
    if c.hp_current~=nil then stats[#stats+1]="ХП "..fmt(c.hp_current).."/"..fmt(c.hp_max)..(c.hp_temp and c.hp_temp>0 and " +"..fmt(c.hp_temp) or "") end
    stats[#stats+1]="КД "..fmt(c.armor_class) stats[#stats+1]="Скорость "..fmt(c.speed) stats[#stats+1]="Иниц. "..fmt(c.initiative)
    content[#content+1]=label(table.concat(stats,"    ·    "),C,15,"#B3A9FF")
    local scores={}
    for _,a in ipairs({{"str","СИЛ"},{"dex","ЛОВ"},{"con","ТЕЛ"},{"int","ИНТ"},{"wis","МДР"},{"cha","ХАР"}}) do scores[#scores+1]=a[2].." "..fmt((c.abilities or {})[a[1]]) end
    content[#content+1]=label(table.concat(scores,"   ·   "),C,12,"#A0A6B2")
    if #(c.conditions or {})>0 then content[#content+1]=label(table.concat(c.conditions,", "),C,12,"#F0B17C") end
    if d.master_view and not c.scene_target then content[#content+1]=button(c.table_visible and "Показан" or "Скрыт",C,function() visible("character",char.id,not char.table_visible) end) end
    rows[#rows+1]=card(content)
   end
  end
 end
 if #(d.folders or {})==0 then rows[#rows+1]=card({label("Мастер пока не открыл стол для игроков",C,14,"#A0A6B2")}) end
 return column(rows)
end
renderSetup=function()
 if not S.setupHost then return end
 local rows={label("Выберите листы · повторное нажатие меняет количество NPC",W,13,"#A0A6B2")}
 for _,f in ipairs(S.data.folders or {}) do
  rows[#rows+1]=label(f.name,W,16,"#B3A9FF")
  for _,c in ipairs(characters()) do
   if tostring(c.folder or "unfiled")==tostring(f.id) then
    local char=c local count=S.selected[c.id] or 0
    rows[#rows+1]=card({label(c.kind=="npc" and "NPC · количество выбирается нажатием" or "ПЕРСОНАЖ ИГРОКА",W-24,11,"#858D9F"),button((count>0 and "["..count.."] " or "[ ] ")..c.name,W-24,function()
     if char.kind=="player" then S.selected[char.id]=count>0 and 0 or 1 else S.selected[char.id]=(count+1)%21 end renderSetup()
    end,count>0)},W,count>0)
   end
  end
 end
 S.setupHost.children=rows
end
local function setupUI()
 S.setupHost=column({}) renderSetup()
 local rows={label("Подготовка инициативы",W,19),S.setupHost,label("Временный участник: имя / бонус / количество",W,13,"#A0A6B2"),
  row({input("name",320,"Имя"),gap(),input("bonus",104,"Бонус"),gap(),input("count",120,"Кол-во")}),
  button("Начать · бросить инициативу выбранным",W,function()
   local participants={}
   for _,c in ipairs(characters()) do local count=S.selected[c.id] or 0 if count>0 then participants[#participants+1]={character=c.id,count=count} end end
   if S.draft.name:match("%S") then
    local bonus,count=tonumber(S.draft.bonus),tonumber(S.draft.count)
    if not bonus or bonus%1~=0 or bonus< -30 or bonus>30 or not count or count%1~=0 or count<1 or count>20 then status("Бонус −30…30; количество 1…20") return end
    participants[#participants+1]={name=S.draft.name,bonus=bonus,count=count}
   end
   if #participants==0 then status("Выберите хотя бы одного участника") return end
   initiative("start",{participants=participants})
  end)}
 return column(rows)
end
-- Scene uses the same saved rolls, target identities and defenses as the website.
local scenePath="/api/integrations/dmhub/scene/"
local function resetDamage()
 S.damageTargets={} S.damageOutcomes={} S.damageParts=nil
end
refreshScene=function()
 if not active() or S.sceneReading or (S.tab~="damage" and S.tab~="scene") then return end
 S.sceneReading=true local preview=S.preview local epoch=S.sceneEpoch or 0
 http(scenePath..(preview and "?view=player" or ""),nil,nil,function(d)
  S.sceneReading=false
  if preview~=S.preview or epoch~=(S.sceneEpoch or 0) then refreshScene() return end
  local hash=fingerprint(d)
  if S.scene and S.scene.session~=d.session then S.sceneEdit=nil S.damageSource=nil resetDamage() end
  S.scene=d
  if hash~=S.sceneHash then S.sceneHash=hash if not S.sceneEdit then draw() end end
 end,function(err) S.sceneReading=false S.scene=nil S.sceneHash=nil status(errorText(err)) draw() end)
end
local function sendScene(b)
 if S.pending or not S.scene or not S.scene.session then status("Нет активной сессии или запрос ещё выполняется") return end
 if b.command~="damage" and not S.scene.master_view then return end
 b.session=S.scene.session
 local function copy(v) if type(v)~="table" then return v end local result={} for k,x in pairs(v) do result[k]=copy(x) end return result end
 b=copy(b)
 S.pending={body=b,key=nextKey(),sending=false,path=scenePath.."commands/",scene=true} transmit()
end
local function defenseEditor()
 local rows={label("Защиты · нажмите для смены · учитываются автоматически",W,13,"#A0A6B2")}
 local opts={"normal","resistance","immunity","vulnerability"}
 local names={normal="Обычный",resistance="Сопротивление",immunity="Иммунитет",vulnerability="Уязвимость"}
 local keys={"all","acid","bludgeoning","cold","fire","force","lightning","necrotic","piercing","poison","psychic","radiant","slashing","thunder"}
 for _,key in ipairs(keys) do
  local k=key local v=S.sceneEdit.defenses[k] or "normal"
  rows[#rows+1]=button((k=="all" and "Все типы" or (S.scene.damage_types or {})[k] or k)..": "..(names[v] or v),W,function()
   for i,value in ipairs(opts) do if value==v then S.sceneEdit.defenses[k]=opts[i%#opts+1] break end end draw()
  end)
 end
 return column(rows)
end
local function editScene(t,source)
 S.sceneEdit={target=t,source=source,defenses={},visible=t and t.visible~=false or true,targetable=t and t.targetable~=false or true}
 if t then S.sceneEdit.visible=t.visible S.sceneEdit.targetable=t.targetable end
 for k,v in pairs(t and t.defenses or {}) do S.sceneEdit.defenses[k]=v end
 S.draft.sceneName=t and t.name or source.name
 S.draft.sceneCount="1" S.draft.sceneHP=fmt(t and t.hp_current or 0) S.draft.sceneMax=fmt(t and t.hp_max or 1) S.draft.sceneTemp=fmt(t and t.hp_temp or 0)
 draw()
end
local function sceneEditorUI()
 local e=S.sceneEdit local t=e.target
 local rows={label(t and "Настройки: "..t.name or "Добавить: "..e.source.name,W,20,"#B3A9FF"),input("sceneName",W,"Имя участника")}
 if t then
  rows[#rows+1]=label("Текущие / максимальные / временные ХП",W,13,"#A0A6B2")
  rows[#rows+1]=row({input("sceneHP",180,"ХП"),gap(),input("sceneMax",180,"Максимум"),gap(),input("sceneTemp",184,"Временные ХП")})
  rows[#rows+1]=button(e.visible and "Виден игрокам" or "Скрыт от игроков",W,function() e.visible=not e.visible draw() end)
  rows[#rows+1]=button(e.targetable and "Можно выбирать целью" or "Нельзя выбирать целью",W,function() e.targetable=not e.targetable draw() end)
  if t.linked_sheet or t.sheet_character then rows[#rows+1]=label("ХП связаны с листом",W,13,"#A0A6B2") end
 elseif e.source.kind~="player" then
  rows[#rows+1]=label("Количество отдельных экземпляров NPC · 1…20",W,13,"#A0A6B2")
  rows[#rows+1]=input("sceneCount",W,"Количество NPC")
 end
 rows[#rows+1]=defenseEditor()
 rows[#rows+1]=row({button("Отмена",276,function() S.sceneEdit=nil draw() end),gap(),button(t and "Сохранить участника" or "Добавить в сцену",276,function()
  if S.pending then return end
  local name=S.draft.sceneName
  if not name or not name:match("%S") then status("Введите имя участника") return end
  if t then
   local hp,max,temp=tonumber(S.draft.sceneHP),tonumber(S.draft.sceneMax),tonumber(S.draft.sceneTemp)
   if not hp or not max or not temp or hp%1~=0 or max%1~=0 or temp%1~=0 or hp<0 or max<1 or hp>max or max>1000000 or temp<0 or temp>1000000 then status("Проверьте ХП: целые числа, текущие не больше максимальных") return end
   local body={command="update",target=t.id,version=t.version,name=name,visible=e.visible,targetable=e.targetable,defenses=e.defenses}
   body.hp_current=hp body.hp_max=max body.hp_temp=temp
   sendScene(body)
  else
   local count=e.source.kind=="player" and 1 or tonumber(S.draft.sceneCount)
   if not count or count%1~=0 or count<1 or count>20 then status("Количество NPC: 1…20") return end
   sendScene({command="add",source=e.source.id,count=count,name=name,defenses=e.defenses})
  end
 end,true)})
 return column(rows)
end
local function sceneUI()
 local d=S.scene
 if not d then return label("Участники загружаются…",W,16) end
 if not d.session then return label("Мастер должен запустить сессию на сайте",W,16) end
 if S.sceneEdit and d.master_view then return sceneEditorUI() end
 local C=W-24
 local rows={label("Участники текущей сцены",W,20,"#B3A9FF")}
 if d.master_view then
  rows[#rows+1]=button(S.sceneAdding and "Скрыть выбор листов" or "Добавить из листа",W,function() S.sceneAdding=not S.sceneAdding draw() end,true)
  if S.sceneAdding then
   for _,c in ipairs(characters()) do
    local source=c
    rows[#rows+1]=card({button("+ "..c.name..(c.kind=="npc" and " · NPC" or " · Игрок"),C,function() editScene(nil,source) end)})
   end
  end
 else rows[#rows+1]=label("Защиты и здоровье настраивает мастер. ХП целей скрыты.",W,13,"#A0A6B2") end
 local function appendTarget(t, copies)
  local content={label(copies and "ЛИСТ ЭКЗЕМПЛЯРА" or t.linked_sheet and "ЛИСТ ИГРОКА" or "УЧАСТНИК СЦЕНЫ",C,10,"#858D9F"),label(t.name,C,21)}
  if d.master_view then
   content[#content+1]=label("ХП "..fmt(t.hp_current).." / "..fmt(t.hp_max).."    + "..fmt(t.hp_temp).." временных",C,19,"#B3A9FF")
   content[#content+1]=label((t.visible and "Виден игрокам" or "Скрыт от игроков").." · "..(t.targetable and "Доступен как цель" or "Нельзя выбрать целью"),C,12,"#A0A6B2")
   if copies then
    content[#content+1]=button("Открыть лист",C,function()
     local sheet=rawget(_G,"SLsheet")
     if sheet and type(sheet.openSceneSheet)=="function" then
      sheet.openSceneSheet(copies,t.sheet_character.id)
     else
      status("Установите обновлённый мод SessionLab · лист")
     end
    end,true)
   end
   content[#content+1]=row({button("Настроить",264,function() editScene(t,nil) end),gap(),button(S.removeTarget==t.id and "Подтвердить удаление" or "Убрать из сцены",264,function()
    if S.removeTarget==t.id then sendScene({command="update",target=t.id,version=t.version,active=false}) else S.removeTarget=t.id draw() end
   end)},C)
  end
  rows[#rows+1]=card(content)
 end
 local groups={}
 for _,t in ipairs(d.targets or {}) do
  if d.master_view and t.sheet_character then
   local group=groups[t.source] or {}
   group[#group+1]=t.sheet_character
   groups[t.source]=group
  end
 end
 for _,t in ipairs(d.targets or {}) do
  appendTarget(t,t.sheet_character and groups[t.source])
 end
 if #(d.targets or {})==0 then rows[#rows+1]=label("В сцене пока нет участников",W,14,"#A0A6B2") end
 return column(rows)
end
local function damageUI()
 local d=S.scene
 if not d then return label("Загрузка бросков и целей…",W,16) end
 if not d.session then return label("Нет активной сессии",W,16) end
 local rows={label("Урон и лечение",W,20,"#B3A9FF"),label("Выберите броски и цель. При промахе снимите выбор с броска.",W,13,"#A0A6B2")}
 local source
 for _,v in ipairs(d.sources or {}) do if v.id==S.damageSource then source=v break end end
 if not source then
  S.damageSource=nil
  for _,v in ipairs(d.sources or {}) do
   local item=v
   rows[#rows+1]=button(v.label.." · #"..fmt(v.id).." · "..v.damage_type,W,function() S.damageSource=item.id resetDamage() draw() end)
  end
  if #(d.sources or {})==0 then rows[#rows+1]=label("Нет бросков урона в этой сессии. Используйте атаку или заклинание в листе.",W,14,"#A0A6B2") end
  return column(rows)
 end
 local healing=source.effect=="healing" or source.damage_type=="healing" or source.damage_type=="heal" or source.damage_type=="лечение" or source.damage_type=="исцеление"
 rows[#rows+1]=button("Другой бросок · "..source.label,W,function() S.damageSource=nil resetDamage() draw() end)
 local used,spent={},{}
 for _,a in ipairs(d.applications or {}) do
  if a.source_event==source.id then
   used[a.part_index]=used[a.part_index] or {} used[a.part_index][a.target]=true
   for _,p in ipairs(source.parts or {}) do if p.index==a.part_index and p.roll and not healing then spent[p.index]=true end end
  end
 end
 if S.damageParts==nil then
  S.damageParts={}
  for _,p in ipairs(source.parts or {}) do if not spent[p.index] then S.damageParts[p.index]=true break end end
 end
 local function restrictTargets()
  local attack=false
  for _,p in ipairs(source.parts or {}) do if S.damageParts[p.index] and p.roll and not healing then attack=true end end
  if attack then
   local first
   for _,t in ipairs(d.targets or {}) do if S.damageTargets[t.id] then first=t.id break end end
   S.damageTargets=first and {[first]=true} or {}
  end
 end
 if #(source.parts or {})>1 then
  rows[#rows+1]=row({button("Выбрать все",276,function()
   if S.pending then return end
   S.damageParts={} for _,p in ipairs(source.parts) do if not spent[p.index] then S.damageParts[p.index]=true end end
   restrictTargets() draw()
  end),gap(),button("Снять выбор",276,function() if S.pending then return end S.damageParts={} draw() end)})
  for _,p in ipairs(source.parts) do
   local part=p
   local title="Бросок "..fmt(p.index+1)..(not healing and p.roll and " · Попадание: "..fmt(p.roll.total) or "")..(not healing and p.save and " · СЛ спасброска: "..fmt(p.save.dc) or "").." · "..fmt(p.damage.total)..(healing and " лечения" or " урона")
   if spent[p.index] then rows[#rows+1]=label(title.." · уже применён",W,13,"#858D9F")
   else rows[#rows+1]=button((S.damageParts[p.index] and "[X] " or "[ ] ")..title,W,function()
    if S.pending then return end
    S.damageParts[part.index]=not S.damageParts[part.index] restrictTargets() draw()
   end,S.damageParts[p.index]) end
  end
 end
 local chosen={} local attack=false local total=0
 for _,p in ipairs(source.parts or {}) do
  if S.damageParts[p.index] and not spent[p.index] then chosen[#chosen+1]=p total=total+p.damage.total if p.roll and not healing then attack=true end end
 end
 if #chosen==0 then rows[#rows+1]=label("Выберите неприменённые броски",W,16,"#A0A6B2") return column(rows) end
 if #(source.parts or {})==1 and not healing and chosen[1].roll then rows[#rows+1]=label("На попадание: "..fmt(chosen[1].roll.total),W,18,"#B3A9FF") end
 if #(source.parts or {})==1 and not healing and chosen[1].save then rows[#rows+1]=label("СЛ спасброска: "..fmt(chosen[1].save.dc),W,18,"#B3A9FF") end
 for _,p in ipairs(chosen) do for _,effect in ipairs(p.effects or {}) do rows[#rows+1]=label("Бросок "..fmt(p.index+1).." · "..effect.name.." "..(effect.sign==-1 and "−" or "+")..fmt(effect.roll.total).." · "..effect.damage_type..(effect.frequency=="turn" and " · раз за ход" or ""),W,13,"#B3A9FF") end end
 rows[#rows+1]=label((healing and "Восстановление ХП: " or "Урон до защиты: ")..fmt(total).." · бросков: "..#chosen,W,16)
 local ids={} local complete=true
 for _,t in ipairs(d.targets or {}) do
  local available=(t.targetable or d.master_view) and (not source.effect_target or source.effect_target==t.id)
  for _,p in ipairs(chosen) do if used[p.index] and used[p.index][t.id] then available=false end end
  if available then
   local target=t local selected=S.damageTargets[t.id]
   local content={} local C=W-24
   content[#content+1]=button((selected and "[X] " or "[ ] ")..t.name,C,function()
    if S.pending then return end
    if attack and not selected then S.damageTargets={} end
    S.damageTargets[target.id]=not selected draw()
   end,selected)
   if selected then
    ids[#ids+1]=t.id
    for _,p in ipairs(chosen) do
     local part=p
     if not healing and p.save then
      local o=(S.damageOutcomes[p.index] or {})[t.id] or {}
      if o.save_outcome~="failure" and o.save_outcome~="success" then complete=false end
      if #chosen>1 then content[#content+1]=label("Бросок "..fmt(p.index+1).." · СЛ "..fmt(p.save.dc),C,13,"#B3A9FF") end
      local function outcome(value)
       if S.pending then return end
       S.damageOutcomes[part.index]=S.damageOutcomes[part.index] or {}
       S.damageOutcomes[part.index][target.id]={save_outcome=value} draw()
      end
      content[#content+1]=row({button((o.save_outcome=="failure" and "> " or "").."Не прошёл",264,function() outcome("failure") end,o.save_outcome=="failure"),gap(),button((o.save_outcome=="success" and "> " or "").."Прошёл",264,function() outcome("success") end,o.save_outcome=="success")},C)
     end
     for _,effect in ipairs(p.effects or {}) do
      local eff=effect local current=(S.damageOutcomes[p.index] or {})[target.id] or {}
      local enabled=current.effects
      if enabled==nil then enabled={} for _,v in ipairs(p.effects) do enabled[#enabled+1]=v.id end end
      local checked=false for _,id in ipairs(enabled) do if id==effect.id then checked=true end end
      content[#content+1]=button((checked and "[X] " or "[ ] ").."Бросок "..fmt(p.index+1).." · "..effect.name,C,function()
       if S.pending then return end
       local nextIds={} for _,id in ipairs(enabled) do if id~=eff.id then nextIds[#nextIds+1]=id end end
       if not checked then nextIds[#nextIds+1]=eff.id end
       S.damageOutcomes[part.index]=S.damageOutcomes[part.index] or {}
       S.damageOutcomes[part.index][target.id]=S.damageOutcomes[part.index][target.id] or {}
       S.damageOutcomes[part.index][target.id].effects=nextIds draw()
      end,checked)
     end
    end
   end
   rows[#rows+1]=card(content,W,selected)
  end
 end
 if #ids>0 and complete and not S.pending then
  local batch={}
  for _,p in ipairs(chosen) do
   local outcomes={}
   for _,id in ipairs(ids) do
    local o={}
    for k,v in pairs((S.damageOutcomes[p.index] or {})[id] or {}) do o[k]=v end
    if not healing and p.roll then o.hit=true end
    outcomes[tostring(id)]=o
   end
   batch[#batch+1]={part_index=p.index,targets=ids,outcomes=outcomes}
  end
  local text=(healing and "Вылечить · " or "Нанести урон · ")..#ids.." целей"..(#batch>1 and " · бросков: "..#batch or "")
  rows[#rows+1]=button(text,W,function()
   local body={command="damage",source_event=source.id}
   if #batch==1 then for k,v in pairs(batch[1]) do body[k]=v end else body.parts=batch end
   sendScene(body)
  end,true)
 else rows[#rows+1]=label(S.pending and "Запрос выполняется…" or (healing and "Выберите, кого вылечить · не выше максимума ХП" or "Выберите доступные цели и исходы спасбросков, если они есть"),W,14,"#A0A6B2") end
 for _,a in ipairs(d.applications or {}) do
  if a.source_event==source.id and S.damageParts[a.part_index] then rows[#rows+1]=label("Применено → "..a.target_name,W,13,"#A0A6B2") end
 end
 return column(rows)
end

local function renderBody()
 if not S.body then return end
 if S.compact then S.body.children={} return end
 if not S.data then S.body.children={label("Подключение к комнате...",W,16)} return end
 if S.setup and S.data.master_view then
  -- Keep inputs alive during polling; selected counts update in a separate host.
  if not S.setupHost then S.body.children={setupUI()} end return
 end
 S.setupHost=nil
 S.body.children={S.tab=="scene" and sceneUI() or S.tab=="damage" and damageUI() or S.tab=="table" and tableUI() or trackerUI()}
end
draw=function()
 if S.title then S.title.text=currentText() end
 if S.round then local t=S.data and S.data.initiative or {} S.round.text="Раунд "..fmt(t.round_number or 0).." · "..(t.running and "Бой" or "Пауза") end
 if S.modeButton then S.modeButton.text=S.preview and "Режим мастера" or "Вид игрока" end
 renderBody()
end
closeWindow=function()
 S.active=false S.run=S.run+1 S.reading=false S.sceneReading=false S.pending=nil
 local win=S.window S.window=nil
 S.body=nil S.title=nil S.round=nil S.status=nil S.modeButton=nil S.setupHost=nil
 if win then win:DestroySelf() end
end
buildWindow=function()
 S.modeButton=nil S.setupHost=nil
 local screenHeight=720
 if dmhub.screenDimensions then screenHeight=tonumber(dmhub.screenDimensions.y) or 720 end
 local bodyHeight=math.min(360,math.max(100,screenHeight-350))
 local compact=S.compact local windowColor=compact and "#101217e8" or "#101217ff" local width=compact and 400 or 584 local inner=width-24
 S.title=label(currentText(),inner,compact and 19 or 24,"#B3A9FF")
 S.round=label("",inner,14,"#A0A6B2")
 local master=S.data and S.data.master_view
 local expandWidth=compact and (master and 120 or 184) or (master and 176 or 276)
 local closeWidth=compact and (master and 104 or 184) or (master and 176 or 276)
 local buttons={button(compact and "Развернуть" or "Свернуть",expandWidth,function() S.compact=not S.compact buildWindow() end),gap()}
 if master then
  buttons[#buttons+1]=button("Следующий ход",compact and 136 or 192,function() initiative("next") end,true)
  buttons[#buttons+1]=gap()
 end
 buttons[#buttons+1]=button("Закрыть",closeWidth,closeWindow)
 local top={label("SESSIONLAB · "..(compact and "ИНИЦИАТИВА" or "КОМНАТА"),inner,11,"#9085FF"),S.title,S.round,row(buttons,inner)}
 if not compact then
  if S.data then top[#top+1]=label((S.data.campaign_name or "").." · "..(S.data.session and S.data.session.name or "Нет активной сессии"),W,13,"#A0A6B2") end
  local nav={button("За столом",132,function() S.tab="table" S.setup=false buildWindow() end,S.tab=="table"),gap(),button("Инициатива",132,function() S.tab="initiative" S.setup=false buildWindow() end,S.tab=="initiative")}
  if S.data and S.data.role=="dm" then
   S.modeButton=button(S.preview and "Режим мастера" or "Вид игрока",280,function() S.preview=not S.preview S.scene=nil S.sceneHash=nil S.sceneEdit=nil S.sceneReading=false S.data=nil S.hash=nil S.setup=false S.selected={} S.setupHost=nil buildWindow() refresh() end)
   nav[#nav+1]=gap() nav[#nav+1]=S.modeButton
  end
  top[#top+1]=row(nav)
  top[#top+1]=row({button("Участники",276,function() S.tab="scene" S.setup=false S.sceneEdit=nil buildWindow() refreshScene() end,S.tab=="scene"),gap(),button("Урон / лечение",276,function() S.tab="damage" S.setup=false S.sceneEdit=nil buildWindow() refreshScene() end,S.tab=="damage")})
  S.status=label(S.msg,W,12,"#A0A6B2") top[#top+1]=S.status
  if S.pending and not S.pending.sending then
   top[#top+1]=row({button("Повторить запрос",276,transmit),gap(),button("Проверить состояние",276,function() S.pending=nil S.hash=nil refresh() end)})
  end
  S.body=gui.Panel{width=W,height=bodyHeight,flow="vertical",vscroll=true,hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children={}}
  top[#top+1]=S.body
 else
  S.body=nil S.modeButton=nil S.status=label(S.msg,inner,11,"#A0A6B2") top[#top+1]=S.status
  if S.pending and not S.pending.sending then top[#top+1]=button("Повторить запрос",inner,transmit) end
 end
 local win
 win=gui.Panel{width=width,height="auto",flow="vertical",floating=true,halign="center",valign="top",x=S.x,y=S.y,hpad=12,vpad=8,
  bgimage="panels/square.png",bgcolor=windowColor,opacity=1,classes={"slr-window"},blocksGameInteraction=not compact,draggable=true,constrainToScreen=true,
  styles={
   {selectors={"slr-window"},priority=100,bgimage="panels/square.png",bgcolor=windowColor,opacity=1,cornerRadius=12,borderWidth=1,borderColor="#303642ff"},
   {selectors={"slr-card"},priority=100,bgimage="panels/square.png",bgcolor="#1A1E26ff",opacity=1,cornerRadius=9,borderWidth=1,borderColor="#303642ff"},
   {selectors={"slr-current"},priority=100,bgimage="panels/square.png",bgcolor="#26243Dff",opacity=1,cornerRadius=9,borderWidth=2,borderColor="#9085FFff"},
   {selectors={"slr-button"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",cornerRadius=6,borderWidth=1,borderColor="#303642ff",color="#F4F5F7",hpad=0,vpad=0,hmargin=0},
   {selectors={"slr-accent"},priority=100,bgimage="panels/square.png",bgcolor="#695CF5ff",cornerRadius=6,borderWidth=1,borderColor="#9085FFff",color="#FFFFFF",hpad=0,vpad=0,hmargin=0},
   {selectors={"slr-button","hover"},priority=110,bgcolor="#303747ff",borderColor="#606B82ff"},
   {selectors={"slr-accent","hover"},priority=110,bgcolor="#8071FFff"},
   {selectors={"slr-input"},priority=100,bgimage="panels/square.png",bgcolor="#101217ff",cornerRadius=6,borderWidth=1,borderColor="#303642ff",color="#F4F5F7"},
  },
  drag=function(e) S.x=e.xdrag S.y=e.ydrag e.x=S.x e.y=S.y end,
  destroy=function() if S.window==win then S.window=nil S.active=false S.run=S.run+1 S.body=nil S.title=nil S.round=nil S.status=nil S.modeButton=nil S.setupHost=nil end end,
  children=top}
 local previous=S.window S.window=win if previous then previous:DestroySelf() end
 local hud=rawget(_G,"GameHud") local host=hud and hud.instance and hud.instance.dialogWorldPanel
 if not host then S.window=nil win:DestroySelf() status("Откройте игровой стол DMHub и попробуйте снова") return false end
 host:AddChild(win) draw() return true
end


start=function()
 if S.active then return end
 if #TOKEN<32 or TOKEN:sub(1,6)=="PASTE_" then status("Вставьте личный ключ в TOKEN") return end
 S.active=true S.run=S.run+1 S.reading=false S.sceneReading=false local run=S.run
 refresh()
 local function tick()
  if not active() or S.run~=run then return end
  if not S.pending then refresh() end
  dmhub.Schedule(INTERVAL,tick)
 end
 dmhub.Schedule(INTERVAL,tick)
end
openWindow=function()
 if S.window then return end
 if not buildWindow() then return end
 start()
end
S.openDamage=function(eventId)
 S.sceneEpoch=(S.sceneEpoch or 0)+1
 S.tab="damage" S.compact=false S.setup=false S.sceneEdit=nil S.scene=nil S.sceneHash=nil S.damageSource=eventId resetDamage()
 if S.window then buildWindow() else openWindow() end
 refreshScene()
end
Commands.slroom=function(args)
 local cmd=tostring(args or ""):lower():match("^%s*(.-)%s*$")
 if cmd=="close" or cmd=="stop" then closeWindow()
 elseif cmd=="refresh" then refresh()
 else openWindow() end
end
if type(Commands.RegisterMacro)=="function" then
 Commands.RegisterMacro{name="slroom",summary="SessionLab room and initiative",command=Commands.slroom}
end
DockablePanel.Register{name="SessionLab · комната",minWidth=300,maxWidth=420,vscroll=true,content=function()
 local launch=gui.Label{text="SUBSessionLab · инициатива",width=264,height="auto",fontSize=14,color="#A0A6B2",interactable=false,vmargin=3}
 S.launchStatus=launch
 return gui.Panel{width=288,height="auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  children={gui.Label{text="SessionLab · инициатива",width=264,height="auto",fontSize=23,color="#9085FF",interactable=false,vmargin=3},launch,
   gui.Button{text="Открыть комнату",width=260,height=34,fontSize=13,color="#F4F5F7",hoverCursor="default",vmargin=3,hmargin=2,
    bgimage="panels/square.png",bgcolor="#695CF5ff",cornerRadius=6,borderWidth=1,borderColor="#9085FFff",
    styles={{selectors={"hover"},bgcolor="#8071FFff"}},press=function() openWindow() end}},
  destroy=function() if S.launchStatus==launch then S.launchStatus=nil end end}
end}
print("SessionLab room loaded · /slroom")
-- End.
