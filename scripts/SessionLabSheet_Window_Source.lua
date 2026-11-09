-- SessionLab sheet for the DMHub editor. Check the last line before saving.
local URL="https://sessionlab.up.railway.app"
local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
local previous=rawget(_G,"SLsheet")
if previous then previous.on=false if previous.window then pcall(function() previous.window:DestroySelf() end) end end
local S={on=false,run=0,tab="stats",page=1,level={},amount=5,msg="/slsheet start"}
S.pinned=previous and previous.pinned or {}
S.recent=previous and previous.recent or {}
rawset(_G,"SLsheet",S)
local REFRESH_INTERVAL=10
local base="/api/integrations/dmhub/sheets/"
local function idstr(n) return string.format("%d",tonumber(n)) end
local function normalizeSlots(sh)
 -- Some native JSON converters turn object keys like "8" into numeric Lua keys.
 -- Keep one representation; missing/invalid entries never create free slots.
 local slots={}
 for key,value in pairs(sh.slots or {}) do
  local n=tonumber(key)
  if n and n>=1 and n<=9 and n==math.floor(n) and type(value)=="table" then
   local maximum,used=tonumber(value.max),tonumber(value.used)
   if maximum and used and maximum>=0 and used>=0 and used<=maximum then
    slots[string.format("%d",n)]={max=maximum,used=used}
   end
  end
 end
 sh.slots=slots
end
local foldCache={} local foldCount=0
local function fold(s)
 local original=tostring(s or "")
 if foldCache[original] then return foldCache[original] end
 s=string.lower(original)
 local upper,lower="АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ","абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
 for i=1,#upper,2 do s=s:gsub(upper:sub(i,i+1),lower:sub(i,i+1)) end
 foldCount=foldCount+1 if foldCount>512 then foldCache={} foldCount=1 end
 foldCache[original]=s
 return s
end
local attrs={{"str","Сила"},{"dex","Ловкость"},{"con","Тело"},{"int","Интеллект"},{"wis","Мудрость"},{"cha","Харизма"}}
local skills={{"acrobatics","Акробатика"},{"animal_handling","Животные"},{"arcana","Магия"},{"athletics","Атлетика"},{"deception","Обман"},{"history","История"},{"insight","Проницательность"},{"intimidation","Запугивание"},{"investigation","Анализ"},{"medicine","Медицина"},{"nature","Природа"},{"perception","Внимательность"},{"performance","Выступление"},{"persuasion","Убеждение"},{"religion","Религия"},{"sleight_of_hand","Ловкость рук"},{"stealth","Скрытность"},{"survival","Выживание"}}
local function signed(n) return string.format("%+g",tonumber(n) or 0) end
local draw,refresh,startSheet,openWindow
local beginEdit,editorUI,actionListUI,write,confirmAction,catalogUI,openCatalog,actionCard,framed,prepareEffectsCast
local function api(path,body,done,requestKey,onError)
 local run=S.run
 local h={Authorization="Bearer "..TOKEN,Accept="application/json"}
 local f
 if body then f=net.Post else f=net.Get end
 if type(f)~="function" then if body then S.busy=false end S.msg="HTTP недоступен" draw() return end
 local o={url=URL..path,headers=h}
 local finished=false
 local function active() return S.on and run==S.run and not finished end
 local function fail(message)
  if not active() then return end
  finished=true
  if not body and S.busy then return end
  if body then S.busy=false end
  if onError then onError() end
  S.msg=tostring(message or "Ошибка запроса"):sub(1,240) draw()
 end
 o.success=function(raw)
  if not active() then return end
  finished=true
  if not body and S.busy then if onError then onError() end return end
  if body then S.busy=false end
  local ok,r=pcall(function() return type(raw)=="table" and raw or dmhub.FromJson(raw) end)
  if ok and type(r)=="table" and type(r.data)=="table" then
   local applied,err=pcall(done,r.data)
   if not applied then S.msg="Ошибка обработки: "..tostring(err):sub(1,150) draw() end
  else
   local message=ok and type(r)=="table" and (r.error or r.detail) or r
   if type(message)=="table" then
    local function flatten(x)
     if type(x)~="table" then return tostring(x) end
     local items={} for k,v in pairs(x) do items[#items+1]=(type(k)=="string" and k..": " or "")..flatten(v) end
     return table.concat(items,"; ")
    end
    message=flatten(message)
   end
   if onError then onError() end
   S.msg="Ошибка API: "..tostring(message or "неверный формат ответа"):sub(1,180) draw()
  end
 end
 o.error=function(message) fail("Ошибка запроса: "..tostring(message or "проверьте результат на сайте")) end
 o.failure=o.error
 if body then
  S.busy=true S.seq=(S.seq or 0)+1
  h["Content-Type"]="application/json"
  h["Idempotency-Key"]=requestKey or (tostring(os.time()).."-"..S.seq.."-"..math.random(100000,999999))
  -- DMHub net.Post serializes a data TABLE itself. Global json is a debug function.
  o.data=body
 end
 local ok,e=pcall(function() f(o) end)
 if not ok then fail("Ошибка отправки: "..tostring(e)) end
end
refresh=function()
 if not S.on or S.busy or S.editor or S.typing or S.pendingWrite then return end
 if not S.id then
  api(base,nil,function(d)
   S.list=d.characters or {} S.folders=d.folders or {} S.msg="Выберите персонажа" draw()
   if S.list[1] then S.id=tonumber(S.list[1].id) dmhub.Schedule(0.1,refresh) else S.msg="Нет листов" draw() end
  end)
 else
  local id=S.id
  api(base..string.format("%d",id).."/",nil,function(d)
   if S.id~=id then return end
   if S.editor or S.typing then return end
   if d.sheet then normalizeSlots(d.sheet) end
   local function signature(value)
    if not value or not value.sheet then return "" end
    local parts={tostring(value.sheet.version),tostring(value.character.name),tostring(value.character.level)}
    for _,a in ipairs(value.actions or {}) do parts[#parts+1]=tostring(a.id)..":"..tostring(a.version) end
    return table.concat(parts,"|")
   end
   local changed=signature(S.data)~=signature(d)
   S.data=d S.msg="Лист загружен"
   if changed or not S.renderedData then S.renderedData=true draw() end
  end,nil,function()
   if S.id==id and S.sceneSiblings then S.data=nil S.renderedData=false end
  end)
 end
end
local function act(path,body)
 if S.busy or S.pendingWrite or S.editor then return end
 S.busy=true
 S.msg="Отправка..." draw()
 api(path,body,function(d)
  local p=d.payload or {} local parts=p.parts or {p}
  local dtype=tostring(p.damage_type or ""):lower():match("^%s*(.-)%s*$")
  local healing=dtype=="healing" or dtype=="heal" or dtype=="лечение" or dtype=="исцеление"
  local result={tostring(p.label or "Действие")}
  for i,x in ipairs(parts) do
   local values={}
   if x.roll then values[#values+1]="Бросок: "..string.format("%g",tonumber(x.roll.total) or 0) end
   if x.save then
    values[#values+1]="СЛ "..string.format("%g",tonumber(x.save.dc) or 0)
    if x.save.failed_damage~=nil then values[#values+1]="Провал: "..string.format("%g",x.save.failed_damage).." / Успех: "..string.format("%g",x.save.success_damage or 0) end
   end
   if x.damage and not (x.save and x.save.failed_damage~=nil) then values[#values+1]=(healing and "Лечение: " or "Урон / эффект: ")..string.format("%g",tonumber(x.damage.total) or 0) end
   for _,effect in ipairs(x.effects or {}) do values[#values+1]=effect.name..": "..(effect.sign==-1 and "−" or "+")..tostring(effect.roll.total) end
   if #values>0 then result[#result+1]=(#parts>1 and i..". " or "")..table.concat(values," · ") end
  end
  S.result=table.concat(result,"\n")
  S.damageEvent=nil
  S.healingResult=healing
  if d.kind=="ability" then
   for _,part in ipairs(parts) do if part.damage and type(part.damage.total)=="number" and part.damage.total>=0 then S.damageEvent=d.id break end end
  end
  refresh()
 end)
end
local function roll(k,id) act(base..idstr(S.id).."/roll/",{kind=k,key=id,mode=S.rollMode or "normal"}) end
local function slot(sh,n) return (sh.slots or {})[string.format("%d",n)] end
local function spellLevels(a,sh)
 local result={} local first=tonumber(a.level) or 0
 if a.kind~="spell" or first==0 then return result end
 for n=first,(a.upcast_allowed and 9 or first) do
  local v=slot(sh,n)
  if v and (tonumber(v.used) or 0)<(tonumber(v.max) or 0) then result[#result+1]=n end
 end
 return result
end
local function selectedLevel(a,sh)
 if a.kind~="spell" or (tonumber(a.level) or 0)==0 then return 0 end
 local levels=spellLevels(a,sh)
 for _,n in ipairs(levels) do if n==S.level[a.id] then return n end end
 S.level[a.id]=levels[1]
 return levels[1]
end
local function cast(a,sh,trigger)
 if a.resolution=="attack" and #(a.attack_effects or {})>0 then
  local n=trigger and nil or selectedLevel(a,sh)
  if not trigger and n==nil then S.msg="Нет свободной ячейки" draw() return end
  prepareEffectsCast(a,n,trigger) return
 end
 if trigger then act(base..idstr(S.id).."/abilities/"..idstr(a.id).."/use/",{trigger=true}) return end
 local n=selectedLevel(a,sh)
 if n==nil then S.msg="Нет свободной ячейки для «"..a.name.."»" draw() return end
 act(base..idstr(S.id).."/abilities/"..idstr(a.id).."/use/",{slot_level=n})
end
local P={window=1080,height=820,left=204,right=800}
local function num(n) return string.format("%g",tonumber(n) or 0) end
local function label(t,w,size,color,align)
 return gui.Label{text=tostring(t or ""),width=w,height="auto",fontSize=size or 14,color=color or "#F4F5F7",halign=align or "left",valign="top",hmargin=0,vmargin=2,hpad=0,vpad=0,textAlignment="left",interactable=false}
end
local function column(children,w,align)
 return gui.Panel{width=w,height="auto",flow="vertical",halign=align or "left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,interactable=false,children=children}
end
local function line(children,w,gap,align)
 local ordered={}
 local n=0
 for i,c in ipairs(children) do
  if i>1 then n=n+1 ordered[n]=gui.Panel{width=gap or 8,height=1,hmargin=0,vmargin=0,hpad=0,vpad=0} end
  n=n+1 ordered[n]=c
 end
 return gui.Panel{width=w,height="auto",flow="horizontal",halign=align or "left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,interactable=false,children=ordered}
end
local function card(children,w)
 local inner=column(children,w-24,"center")
 return gui.Panel{width=w,height="auto",flow="vertical",halign="left",valign="top",hmargin=0,vmargin=5,hpad=0,vpad=0,interactable=false,classes={"slcard"},
  children={gui.Panel{width=w,height=12},inner,gui.Panel{width=w,height=12}}}
end
local function button(t,w,fn,accent,disabled)
 return gui.Button{text=t,width=w,height=34,minHeight=34,maxHeight=34,fontSize=13,color="#F4F5F7",halign="left",valign="top",classes={accent and "slaccent" or "slbutton"},interactable=not disabled,hmargin=0,vmargin=3,hpad=0,vpad=0,textAlignment="center",press=function() if not disabled then fn() end end}
end
local function choose(c, siblings)
 if S.busy or S.pendingWrite then return end
 if S.editor then
  confirmAction("Отменить несохранённые изменения?",function() S.editor=nil choose(c,siblings) end)
  return
 end
 S.sceneSiblings=siblings
 S.sceneName=siblings and c.name or nil
 if not siblings then
  local history={tonumber(c.id)}
  for _,id in ipairs(S.recent) do if id~=tonumber(c.id) and #history<6 then history[#history+1]=id end end
  S.recent=history
 end
 S.id=tonumber(c.id) S.data=nil S.page=1 S.open=nil S.search="" S.chooser=false S.renderedData=false S.typing=false
 S.result=nil S.damageEvent=nil
 S.msg="Загрузка: "..c.name draw()
 if S.on then dmhub.Schedule(0.1,refresh) end
end
S.openSceneSheet=function(siblings, id)
 for _,copy in ipairs(siblings) do
  if tonumber(copy.id)==tonumber(id) then
   choose(copy,siblings)
   openWindow()
   return
  end
 end
end
local function changeTab(t)
 if S.editor then confirmAction("Отменить несохранённые изменения?",function() S.editor=nil changeTab(t) end) return end
 S.tab=t S.page=1 S.search="" S.open=nil S.catalog=nil S.typing=false draw()
end
local function toggleAction(id)
 -- `condition and nil or id` ALWAYS returns id in Lua.
 if S.open==id then S.open=nil else S.open=id end
 draw()
end
local function clearWindowReferences()
 S.on=false S.run=S.run+1 S.busy=false
 S.window=nil S.panel=nil S.leftScroll=nil S.rightScroll=nil
 S.windowTitle=nil S.windowStatus=nil S.chooserHost=nil
 S.typing=false S.selectOpen=nil
end
local function clearSceneSelection()
 if not S.sceneSiblings then return end
 S.sceneSiblings=nil S.sceneName=nil S.id=nil S.data=nil S.result=nil S.damageEvent=nil
end
local function closeWindow()
 if S.editor then confirmAction("Закрыть без сохранения?",function() S.editor=nil closeWindow() end) return end
 local window=S.window
 -- Clear references BEFORE the engine destroys the native userdata.
 clearWindowReferences()
 clearSceneSelection()
 if window then window:DestroySelf() end
end
-- @include SessionLabSheet_Editor_Source.lua
actionCard=function(a,w,sh,compact)
 local inner=w-24
 local parts={label(a.name,inner,18),label(a.kind=="spell" and (a.level==0 and "Заговор" or num(a.level).." круг") or "Оружие и приёмы",inner,12,"#9085FF")}
 local half=math.floor((inner-8)/2)
 local available=selectedLevel(a,sh)~=nil
 parts[#parts+1]=line({button(S.open==a.id and "Скрыть" or "Подробнее",half,function() toggleAction(a.id) end),button(a.kind=="spell" and "Сотворить" or "Атаковать",half,function() cast(a,sh) end,true,S.busy or not available)},inner)
 if a.kind=="spell" and a.level>0 then
  local levels=spellLevels(a,sh)
  if #levels>0 then
   local selected=selectedLevel(a,sh)
   local remaining=slot(sh,selected)
   local function caption(n) local v=slot(sh,n) return "Ячейка "..num(n).." · осталось "..num(v.max-v.used) end
   local slotButton
   slotButton=button(caption(selected),inner,function()
    local current=S.level[a.id] or selected
    for j,n in ipairs(levels) do if n==current then S.level[a.id]=levels[j%#levels+1] break end end
    slotButton.text=caption(S.level[a.id])
   end)
   parts[#parts+1]=slotButton
  else parts[#parts+1]=label("Нет свободных ячеек",inner,12,"#F08491") end
 end
 if S.open==a.id then parts[#parts+1]=label((a.casting_time or "").." · "..(a.range or "").." · "..(a.duration or ""),inner,12,"#A0A6B2") parts[#parts+1]=label(a.description,inner,14) end
 parts[#parts+1]=line({button("Изменить",half,function() beginEdit("action",a) end,false,S.busy),button("Удалить",half,function() archiveAction(a) end,false,S.busy)},inner)
 if a.rules_recurring then parts[#parts+1]=button("Бросить повторный эффект",inner,function() cast(a,sh,true) end,false,S.busy) end
 return card(parts,w)
end
draw=function(leftOnly)
 if S.launchStatus then S.launchStatus.text=S.msg end
 if not S.panel then return end
 local scrollbar=P.narrow and 0 or 16
 local L,R=P.left-scrollbar,P.right-scrollbar local LI,RI=L-24,R-24
 local left,right={},{}
 local d=S.data
 local valid=d and d.character and tonumber(d.character.id)==S.id and d.sheet
 local current=valid and (S.sceneName or d.character.name) or "Выбрать персонажа"
 left[#left+1]=button(current.."  ›",L,function()
  S.chooser=not S.chooser draw(true)
  if S.chooser then api(base,nil,function(data) S.list=data.characters or {} S.folders=data.folders or {} draw(true) end) end
 end)
 local function folderName(c)
  for _,f in ipairs(S.folders or {}) do if tonumber(f.id)==tonumber(c.folder) then return f.name end end
  return "Без папки"
 end
 local byId={} for _,c in ipairs(S.list or {}) do byId[tonumber(c.id)]=c end
 if valid and not S.sceneSiblings then
  left[#left+1]=label(folderName(d.character),L,12,"#A0A6B2")
  left[#left+1]=button(S.pinned[S.id] and "Убрать из быстрого доступа" or "Закрепить для боя",L,function()
   S.pinned[S.id]=not S.pinned[S.id] draw(true)
  end)
 end
 local function shortcut(c)
  return button((tonumber(c.id)==S.id and "• " or "")..c.name.." · "..folderName(c),L,function() choose(c) end,tonumber(c.id)==S.id)
 end
 local pins={}
 for _,c in ipairs(S.list or {}) do if S.pinned[tonumber(c.id)] then pins[#pins+1]=c end end
 if #pins>0 then
  left[#left+1]=label("БЫСТРЫЙ ДОСТУП",L,11,"#9085FF")
  for _,c in ipairs(pins) do left[#left+1]=shortcut(c) end
 end
 local recent={}
 for _,id in ipairs(S.recent) do if byId[id] and not S.pinned[id] and id~=S.id then recent[#recent+1]=byId[id] end end
 if #recent>0 then
  left[#left+1]=label("НЕДАВНИЕ ЛИСТЫ",L,11,"#A0A6B2")
  for _,c in ipairs(recent) do left[#left+1]=shortcut(c) end
 end
 if S.chooser or not valid then
  S.folderOpen=S.folderOpen or {}
  local groups={}
  for _,f in ipairs(S.folders or {}) do groups[#groups+1]={id=tonumber(f.id),name=f.name,characters={}} end
  groups[#groups+1]={id=0,name="Без папки",characters={}}
  for _,c in ipairs(S.list or {}) do
   local target=groups[#groups]
   for _,g in ipairs(groups) do if g.id==tonumber(c.folder) then target=g break end end
   target.characters[#target.characters+1]=c
  end
  local host=column({},L) S.chooserHost=host
  local function renderChooser()
   if S.chooserHost~=host then return end
   local items={}
   local query=fold(S.characterQuery or "")
   if query~="" then
    for _,c in ipairs(S.list or {}) do
     if fold(c.name.." "..folderName(c)):find(query,1,true) then items[#items+1]=shortcut(c) end
    end
    if #items==0 then items[1]=label("Ничего не найдено",L,12,"#A0A6B2") end
    host.children=items return
   end
   for _,g in ipairs(groups) do
   local group=g
   items[#items+1]=button((S.folderOpen[g.id] and "- " or "+ ")..g.name.." · "..#g.characters,L,function() S.folderOpen[group.id]=not S.folderOpen[group.id] renderChooser() end)
   if S.folderOpen[g.id] then
    for _,c in ipairs(g.characters) do local character=c items[#items+1]=button(c.name,L,function() choose(character) end,tonumber(c.id)==S.id) end
    if #g.characters==0 then items[#items+1]=label("Нет листов",L,12,"#A0A6B2") end
   end
  end
   host.children=items
  end
  left[#left+1]=gui.Input{text=S.characterQuery or "",placeholderText="Поиск по имени или папке",width=L,height=34,fontSize=13,classes={"slinput"},
   edit=function(e) S.characterQuery=e.text or "" renderChooser() end,
   change=function(e) S.characterQuery=e.text or "" renderChooser() end}
  renderChooser() left[#left+1]=host
 end
 if valid then
  local sh=d.sheet local cs=sh.computed or {}
  local attributes={label("ХАРАКТЕРИСТИКИ",LI,11,"#A0A6B2")}
  local half=math.floor((LI-8)/2)
  for i=1,#attrs,2 do
   local cells={}
   for j=i,i+1 do local a=attrs[j] local k=a[1]
    cells[#cells+1]=card({label(a[2],half-24,11,"#A0A6B2"),label(signed((cs.modifiers or {})[k]),half-24,25,"#9085FF"),button(num((sh.abilities or {})[k] or 10),half-24,function() beginEdit("stats") end),button("Бросок",half-24,function() roll("ability",k) end)},half)
   end
   attributes[#attributes+1]=line(cells,LI)
  end
  left[#left+1]=card(attributes,L)
  local saves={label("Спасброски",LI,16)}
  for _,a in ipairs(attrs) do local k=a[1] saves[#saves+1]=line({button(has(sh.saves,k) and "Вл." or "—",40,function() quickSave(k) end,false,S.busy or S.pendingWrite~=nil),button(a[2].."  "..signed((cs.saves or {})[k]),LI-48,function() roll("save",k) end)},LI) end
  left[#left+1]=card(saves,L)
  local skillRows={label("Навыки",LI,16)}
  for _,a in ipairs(skills) do local k=a[1] local prof=tonumber((sh.skills or {})[k]) or 0
   skillRows[#skillRows+1]=line({button(({"—","Вл.","Мст."})[prof+1],40,function() quickSkill(k) end,false,S.busy or S.pendingWrite~=nil),button(a[2].."  "..signed((cs.skills or {})[k]),LI-48,function() roll("skill",k) end)},LI)
  end
  if S.sceneSiblings then
   local copies={label("ЛИСТЫ ЭТОЙ ГРУППЫ",L-24,12,"#9085FF")}
   for _,entry in ipairs(S.sceneSiblings) do
    local copy=entry
    copies[#copies+1]=button(copy.name,L-24,function() choose(copy,S.sceneSiblings) end,tonumber(copy.id)==S.id,S.busy)
   end
   table.insert(left,1,card(copies,L))
  end
  left[#left+1]=card(skillRows,L)
  left[#left+1]=cycle("Проверки",S.rollMode or "normal",{{"normal","Обычный"},{"advantage","Преимущество"},{"disadvantage","Помеха"}},L,function(v) S.rollMode=v end)
  left[#left+1]=button("Спасбросок от смерти",L,function() roll("death","") end)
  if leftOnly and not P.narrow and S.leftScroll then
   S.leftScroll.children={column(left,L)}
   return
  end
  local hp,maxhp=tonumber(sh.hp_current) or 0,tonumber(sh.hp_max) or 1
  local health={label("ЗДОРОВЬЕ ПЕРСОНАЖА",RI,11,"#A0A6B2"),label("Хиты  "..num(hp).." / "..num(maxhp),RI,26),label("Временные хиты: "..num(sh.hp_temp),RI,12,"#45CBA6")}
  health[#health+1]=gui.Panel{width=RI,height=6,hmargin=0,vmargin=4,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#303642ff",children={gui.Panel{width=math.floor(RI*math.max(0,math.min(1,hp/math.max(1,maxhp)))),height=6,halign="left",bgimage="panels/square.png",bgcolor="#45CBA6ff"}}}
  local amount=gui.Input{text=num(S.amount),width=72,height=34,fontSize=15,hmargin=0,vmargin=3,hpad=0,vpad=0,classes={"slinput"},change=function(e) S.amount=math.max(0,math.min(10000,math.floor(tonumber(e.text) or 0))) end}
  local resourceWidth=math.floor((RI-72-24)/3)
  local resourceButtons={}
  for _,v in ipairs({{"damage","Урон"},{"heal","Лечение"},{"temporary","Врем. хиты"}}) do
   local kind=v[1]
   resourceButtons[#resourceButtons+1]=button(v[2],P.narrow and math.floor((RI-16)/3) or resourceWidth,function() act(base..idstr(S.id).."/resources/",{action=kind,amount=S.amount}) end,false,S.busy)
  end
  if P.narrow then
   health[#health+1]=line({label("Количество",RI-80,14,"#A0A6B2"),amount},RI)
   health[#health+1]=line(resourceButtons,RI)
  else health[#health+1]=line({amount,resourceButtons[1],resourceButtons[2],resourceButtons[3]},RI) end
  right[#right+1]=card(health,R)
  right[#right+1]=button("Новый ход вне боя",R,function() write(base..idstr(S.id).."/resources/",{action="next_turn",version=sh.version}) end,false,S.busy)
  right[#right+1]=button("Редактировать боевые ресурсы",R,function() beginEdit("resources") end,false,S.busy)
  local tabs={} local tabWidth=math.floor((R-32)/5)
  for _,v in ipairs({{"stats","Обзор"},{"skills","Навыки"},{"attack","Атаки"},{"spell","Заклинания"},{"notes","Записи"}}) do local tab=v[1] tabs[#tabs+1]=button(v[2],tabWidth,function() changeTab(tab) end,S.tab==tab) end
  if P.narrow then
   local rows,cells={},{} local smallWidth=math.floor((R-16)/3)
   for i,v in ipairs({{"stats","Обзор"},{"skills","Навыки"},{"attack","Атаки"},{"spell","Заклинания"},{"notes","Записи"}}) do
    local t=v[1] cells[#cells+1]=button(v[2],smallWidth,function() changeTab(t) end,S.tab==t)
    if #cells==3 or i==5 then rows[#rows+1]=line(cells,R) cells={} end
   end
   right[#right+1]=column(rows,R)
  else right[#right+1]=line(tabs,R) end
  if S.result then
   local content={label("ПОСЛЕДНЕЕ ДЕЙСТВИЕ",RI,11,"#A0A6B2"),label(S.result,RI,20,"#9085FF")}
   if S.damageEvent then content[#content+1]=button(S.healingResult and "Вылечить" or "Нанести урон",RI,function()
    local room=rawget(_G,"SessionLabRoomRuntime")
    if room and type(room.openDamage)=="function" then room.openDamage(S.damageEvent) else S.msg="Установите обновлённый мод SessionLab · комната" draw() end
   end,true) end
   right[#right+1]=card(content,R)
  end
  local pair=P.narrow and R or math.floor((R-12)/2) local PI=pair-24
  local function two(items) return P.narrow and column(items,R) or line(items,R,12) end
  if S.editor then
   right=editorUI(R)
  elseif S.tab=="catalog" and S.catalog then
   right=catalogUI(R)
  elseif S.tab=="stats" then
   local CI=pair-40
   local combat={label("Боевые показатели",CI,19)}
   local cells={} local quarter=math.floor((CI-8)/2)
   for _,v in ipairs({{"Класс доспеха",sh.armor_class},{"Инициатива",signed(cs.initiative)},{"Скорость",sh.speed},{"Владение",signed(cs.proficiency)}}) do
    cells[#cells+1]=card({label(v[1],quarter-24,10,"#A0A6B2"),label(type(v[2])=="number" and num(v[2]) or v[2] or "—",quarter-24,23)},quarter)
    if #cells==2 then combat[#combat+1]=line(cells,CI) cells={} end
   end
   combat[#combat+1]=button("Изменить показатели",CI,function() beginEdit("resources") end)
   combat[#combat+1]=button("Бросить инициативу",CI,function() roll("initiative","") end)
   combat[#combat+1]=button("Состояния · "..#(sh.conditions or {}),CI,function() beginEdit("conditions") end)
   local magic={label("Магия",CI,19),label("Атака  "..signed(cs.spell_attack).."  ·  СЛ  "..num(cs.spell_dc),CI,18,"#9085FF")}
   for n=1,9 do local v=slot(sh,n) or {max=0,used=0}
    magic[#magic+1]=label(num(n).." круг: "..num(v.max-v.used).." / "..num(v.max),CI,13,v.max>0 and "#F4F5F7" or "#A0A6B2")
   end
   magic[#magic+1]=button("Настроить ячейки",CI,function() beginEdit("magic") end)
   magic[#magic+1]=button("Восстановить ячейки",CI,restoreSlots)
   right[#right+1]=two({framed(combat,pair,360),framed(magic,pair,360)})
   right[#right+1]=two({actionListUI("attack",pair,sh,560),actionListUI("spell",pair,sh,560)})
   local notes={}
   for _,v in ipairs({{"Инвентарь",sh.inventory},{"Заметки",sh.notes}}) do
    notes[#notes+1]=framed({label(v[1],CI,19),button("Редактировать записи",CI,function() beginEdit("notes") end),label(v[2]~="" and v[2] or "Пока пусто",CI,14,"#A0A6B2")},pair,220)
   end
   right[#right+1]=two(notes)
  elseif S.tab=="skills" then
   local rows={label("Навыки и владения",RI,20)}
   for _,a in ipairs(skills) do local k=a[1] local prof=tonumber((sh.skills or {})[k]) or 0
    rows[#rows+1]=line({button(({"Без владения","Владение","Мастерство"})[prof+1],math.floor(RI*0.4),function() quickSkill(k) end,false,S.busy),button(a[2].."  "..signed((cs.skills or {})[k]),RI-math.floor(RI*0.4)-8,function() roll("skill",k) end)},RI)
   end
   right[#right+1]=card(rows,R)
  elseif S.tab=="notes" then
   right[#right+1]=button("Редактировать инвентарь и заметки",R,function() beginEdit("notes") end,true)
   for _,v in ipairs({{"Инвентарь",sh.inventory},{"Заметки",sh.notes},{"Предыстория",sh.background}}) do right[#right+1]=card({label(v[1],RI,20),label(v[2] or "—",RI,14)},R) end
  else
   right[#right+1]=actionListUI(S.tab=="attack" and "attack" or "spell",R,sh,math.max(380,P.bodyHeight-180))
  end
  if S.confirm then
   local confirmation=S.confirm
   right={card({label(confirmation.question,RI,22),button("Подтвердить",RI,function() S.confirm=nil confirmation.yes() draw() end,true,S.busy),button("Назад",RI,function() S.confirm=nil draw() end,false,S.busy)},R)}
  end
  local pending=pendingUI(R)
  if pending then right={pending} end
 else
  right={card({label("Лист персонажа",RI,25),label(S.msg,RI,15,"#A0A6B2"),button(S.on and "Повторить загрузку" or "Подключить",RI,function() if S.on then refresh() else startSheet("start") end end,true)},R)}
 end
 if P.narrow then
  S.panel.children={column({column(right,R),column(left,L)},P.content,"center")}
 else
  if not S.leftScroll then
   -- Mount the scroll containers once per window; update only their contents.
   -- Do not index vscrollPosition: some DMHub builds log a native error even in pcall.
   S.leftScroll=gui.Panel{width=P.left,height=P.bodyHeight,flow="vertical",vscroll=true,halign="left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,children={column(left,L)}}
   S.rightScroll=gui.Panel{width=P.right,height=P.bodyHeight,flow="vertical",vscroll=true,halign="left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,children={column(right,R)}}
   S.panel.children={line({S.leftScroll,S.rightScroll},P.content,16,"center")}
  else
   S.leftScroll.children={column(left,L)}
   S.rightScroll.children={column(right,R)}
  end
 end
 if S.windowTitle then S.windowTitle.text=valid and (S.sceneName or d.character.name).." · "..num(d.character.level).." уровень" or "Лист персонажа" end
 if S.windowStatus then S.windowStatus.text=S.msg end
end
openWindow=function()
 if S.window then return end
 local hud=rawget(_G,"GameHud")
 local host=hud and hud.instance and hud.instance.dialogWorldPanel
 if not host then
  S.msg="Откройте игровой стол DMHub и попробуйте снова"
  if S.launchStatus then S.launchStatus.text=S.msg end
  return
 end
 clearWindowReferences()
 local sx,sy=1280,960
 pcall(function() sx=dmhub.screenDimensions.x sy=dmhub.screenDimensions.y end)
 P.window=math.max(340,math.min(1120,math.floor(sx-80))) P.height=math.max(320,math.min(860,math.floor(sy-100)))
 P.content=P.window-48 P.narrow=P.window<860 P.left=P.narrow and P.content or 240 P.right=P.narrow and P.content or P.content-P.left-16
 P.bodyHeight=P.height-122
 local titleWidth=P.window-304
 S.windowTitle=label("Лист персонажа",titleWidth,23)
 S.windowStatus=label(S.msg,P.window-40,12,"#A0A6B2","center")
 S.panel=gui.Panel{width=P.window-32,height=P.bodyHeight,flow="vertical",vscroll=P.narrow,halign="center",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#101217ff"}
 local header
 if P.narrow then
  S.windowTitle=label("Лист персонажа",P.window-48,22)
  header=column({S.windowTitle,line({button("Обновить",math.floor((P.window-56)/2),refresh),button("Закрыть",math.floor((P.window-56)/2),closeWindow)},P.window-48)},P.window-48,"center")
  P.bodyHeight=P.height-142
  S.panel=gui.Panel{width=P.window-32,height=P.bodyHeight,flow="vertical",vscroll=true,halign="center",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#101217ff"}
 else header=line({column({label("SESSIONLAB",titleWidth,11,"#9085FF"),S.windowTitle},titleWidth),button("Обновить",120,refresh),button("Закрыть",120,closeWindow)},P.window-48,nil,"center") end
 local window
 local dragHandle=gui.Panel{width=P.window-48,height="auto",flow="vertical",halign="center",interactable=false,children={header}}
 window=gui.Panel{
  width=P.window,height=P.height,flow="vertical",halign="center",valign="center",hmargin=0,vmargin=0,hpad=0,vpad=0,classes={"slwindow"},
  bgimage="panels/square.png",bgcolor="#101217ff",floating=true,constrainToScreen=true,blocksGameInteraction=true,draggable=true,
  drag=function(e) e.x=e.xdrag e.y=e.ydrag end,
  styles={
   {selectors={"slwindow"},priority=100,bgimage="panels/square.png",bgcolor="#101217ff",opacity=1,hpad=0,vpad=0,hmargin=0,vmargin=0,borderWidth=1,borderColor="#303642ff",cornerRadius=12},
   {selectors={"slcard"},priority=100,bgimage="panels/square.png",bgcolor="#1A1E26ff",opacity=1,hpad=0,vpad=0,hmargin=0,borderWidth=1,borderColor="#303642ff",cornerRadius=9},
   {selectors={"slbutton"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",hpad=0,vpad=0,hmargin=0,borderWidth=1,borderColor="#303642ff",cornerRadius=6,color="#F4F5F7",fontSize=13},
   {selectors={"slaccent"},priority=100,bgimage="panels/square.png",bgcolor="#695CF5ff",hpad=0,vpad=0,hmargin=0,borderWidth=1,borderColor="#9085FFff",cornerRadius=6,color="white",fontSize=13},
   {selectors={"slbutton","disabled"},priority=110,opacity=0.45},
   {selectors={"slaccent","disabled"},priority=110,opacity=0.45},
   {selectors={"slinput"},priority=100,bgimage="panels/square.png",bgcolor="#101217ff",hpad=0,vpad=0,hmargin=0,borderWidth=1,borderColor="#303642ff",cornerRadius=6,color="#F4F5F7"},
  },

  destroy=function() if S.window==window then clearWindowReferences() clearSceneSelection() end end,
  children={gui.Panel{width=P.window,height=P.height,floating=true,halign="center",valign="center",bgimage="panels/square.png",bgcolor="#101217ff",interactable=false},
   gui.Panel{width=P.window,height=12},dragHandle,
   S.windowStatus,S.panel,gui.Panel{width=P.window,height=12}},
 }
 S.window=window host:AddChild(window) draw()
 if not S.on then startSheet("start") end
end

startSheet=function(cmd)
 if cmd=="stop" then S.on=false S.run=S.run+1 S.busy=false S.msg="Остановлен" draw() return end
 if cmd=="refresh" then refresh() return end
 if S.on then return end
 if #TOKEN < 10 or TOKEN:sub(1,6)=="PASTE_" then S.msg="Вставьте личный ключ в TOKEN" draw() return end
 S.on=true S.run=S.run+1 S.msg="Подключение..." draw() local run=S.run refresh()
 local function tick() if not S.on or run~=S.run then return end if not S.busy then refresh() end dmhub.Schedule(REFRESH_INTERVAL,tick) end
 dmhub.Schedule(REFRESH_INTERVAL,tick)
end
Commands.slsheet=function(cmd)
 if cmd==nil or cmd=="" or cmd=="start" or cmd=="open" then openWindow() else startSheet(cmd) end
end
DockablePanel.Register{name="SessionLab · лист",minWidth=300,maxWidth=420,vscroll=true,content=function()
 local launchStatus=gui.Label{text="SUBSessionLab · лист",width=264,height="auto",fontSize=14,color="#A0A6B2",interactable=false,vmargin=3}
 S.launchStatus=launchStatus
 return gui.Panel{width=288,height="auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  children={gui.Label{text="SessionLab · лист",width=264,height="auto",fontSize=23,color="#9085FF",interactable=false,vmargin=3},launchStatus,
   gui.Button{text="Открыть лист",width=260,height=34,fontSize=13,color="#F4F5F7",hoverCursor="default",vmargin=3,hmargin=2,
    bgimage="panels/square.png",bgcolor="#695CF5ff",cornerRadius=6,borderWidth=1,borderColor="#9085FFff",
    styles={{selectors={"hover"},bgcolor="#8071FFff"}},press=function() openWindow() end}},
  destroy=function() if S.launchStatus==launchStatus then S.launchStatus=nil end end}
end}
print("SessionLab sheet loaded · /slsheet start")
local runSessionLabSheet=Commands.slsheet
if type(Commands.RegisterMacro)=="function" then
 Commands.RegisterMacro{name="slsheet",summary="SessionLab sheet",command=function(args)
  chat.Send("SessionLab: command received")
  runSessionLabSheet(args or "start")
 end}
end
-- End.
