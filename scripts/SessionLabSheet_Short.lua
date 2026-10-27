-- SessionLab sheet. Replace SHEET_TOKEN. Last line: -- End.
local URL="https://sessionlab.up.railway.app"
local SHEET_TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
local old=rawget(_G,"SLsheet") if old then old.on=false end
local S={on=false,run=0,tab="stats",page=1,slot={},amount=5,msg="/slsheet start",list={}}
_G.SLsheet=S
local names={str="Сила",dex="Ловкость",con="Телосложение",int="Интеллект",wis="Мудрость",cha="Харизма"}
local attrs={"str","dex","con","int","wis","cha"}
local skills={acrobatics="Акробатика",animal_handling="Уход за животными",arcana="Магия",athletics="Атлетика",deception="Обман",history="История",insight="Проницательность",intimidation="Запугивание",investigation="Анализ",medicine="Медицина",nature="Природа",perception="Внимательность",performance="Выступление",persuasion="Убеждение",religion="Религия",sleight_of_hand="Ловкость рук",stealth="Скрытность",survival="Выживание"}
local function signed(v) v=tonumber(v) or 0 return v>=0 and "+"..v or tostring(v) end
local function label(t,n) return gui.Label{text=tostring(t or ""),fontSize=n or 15,color="#F4F5F7",width="100%",height="auto",vmargin=2} end
local function button(t,fn) return gui.Label{text=t,color="#F4F5F7",fontSize=15,width="100%",height=28,vmargin=2,bgimage="panels/square.png",bgcolor="#353B50",click=fn} end
local function req(path,body,done)
 local run=S.run
 local h={Authorization="Bearer "..SHEET_TOKEN,Accept="application/json"}
 local call=body and net.Post or net.Get
 if type(call)~="function" then S.msg="DMHub: HTTP POST недоступен" if S.draw then S.draw() end return end
 local options={url=URL..path,headers=h,success=function(raw)
  if not S.on or run~=S.run then return end
  local ok,r=pcall(function() return type(raw)=="table" and raw or json.decode(raw) end)
  S.busy=false
  if ok and type(r)=="table" and type(r.data)=="table" then done(r.data)
  else S.msg="Ошибка API: "..tostring(ok and r.error or r):sub(1,80) S.draw() end
 end,failure=function(e) if S.on and run==S.run then S.busy=false S.msg="Нет связи; проверьте результат на сайте: "..tostring(e):sub(1,50) S.draw() end end}
 if body then
  S.busy=true S.seq=(S.seq or 0)+1
  h["Content-Type"]="application/json"
  h["Idempotency-Key"]=tostring(os.time()).."-"..S.seq.."-"..math.random(100000,999999)
  options.body=json.encode(body) options.data=options.body
 end
 local ok,e=pcall(function() call(options) end)
 if not ok then S.busy=false S.msg=tostring(e):sub(1,100) S.draw() end
end
local function base() return "/api/integrations/dmhub/sheets/" end
local function refresh()
 if not S.on then return end
 if not S.id then req(base(),nil,function(d) S.list=d.characters or {} if S.list[1] then S.id=S.list[1].id refresh() else S.msg="Нет доступных листов" S.draw() end end) return end
 req(base()..S.id.."/",nil,function(d) S.data=d S.msg="Лист обновлён" S.draw() end)
end
local function action(path,body)
 if S.busy then return end
 S.msg="Сохраняю действие…" S.draw()
 req(path,body,function(d)
  local p=d.payload
  if p then
   local first=(p.parts or {p})[1] or {}
   S.result=tostring(p.label or "Бросок")
   if first.roll then S.result=S.result.." · "..tostring(first.roll.total) end
   if first.damage then S.result=S.result.." · урон "..tostring(first.damage.total) end
   if first.save then S.result=S.result.." · СЛ "..tostring(first.save.dc) end
  end
  refresh()
 end)
end
local function roll(kind,key) action(base()..S.id.."/roll/",{kind=kind,key=key}) end
local function cast(a)
 local n=S.slot[a.id] or a.level or 0
 if a.kind=="spell" and a.level>0 then
  local slots=S.data.sheet.slots local v=slots[tostring(n)]
  if not v or v.used>=v.max then
   n=nil
   for i=a.level,(a.upcast_allowed and 9 or a.level) do
    local s=slots[tostring(i)] if s and s.used<s.max then n=i break end
   end
  end
  if not n then S.msg="Нет свободных ячеек" S.draw() return end
  S.slot[a.id]=n
 end
 action(base()..S.id.."/abilities/"..a.id.."/use/",{slot_level=n})
end
local function render()
 if not S.root then return end
 local rows={label("SessionLab · лист",23),label(S.msg,13)}
 if S.result then rows[#rows+1]=label(S.result,19) end
 if S.on then
  rows[#rows+1]=button("Обновить",refresh)
  for _,c in ipairs(S.list) do
   local id=c.id rows[#rows+1]=button((id==S.id and "• " or "")..c.name,function() S.id=id S.data=nil S.page=1 refresh() end)
  end
  local d=S.data
  if d and d.character.id==S.id then
   local sh=d.sheet local cs=sh.computed
   rows[#rows+1]=label(d.character.name.." · "..d.character.level.." ур.",21)
   rows[#rows+1]=label("КД "..sh.armor_class.." · Хиты "..sh.hp_current.."/"..sh.hp_max.." · Врем. "..sh.hp_temp,16)
   rows[#rows+1]=label("Инициатива "..signed(cs.initiative).." · Скорость "..sh.speed,15)
   for _,tab in ipairs({"stats","skills","attacks","spells","notes"}) do
    local n={stats="Характеристики",skills="Навыки",attacks="Атаки",spells="Заклинания",notes="Заметки"}
    rows[#rows+1]=button((S.tab==tab and "• " or "")..n[tab],function() S.tab=tab S.page=1 S.open=nil render() end)
   end
   if S.tab=="stats" then
    for _,k in ipairs(attrs) do
     local key=k
     rows[#rows+1]=button(names[k].." "..sh.abilities[k].." ("..signed(cs.modifiers[k])..") · бросить",function() roll("ability",key) end)
     rows[#rows+1]=button("Спасбросок "..names[k].." "..signed(cs.saves[k]),function() roll("save",key) end)
    end
    rows[#rows+1]=button("Инициатива · бросить",function() roll("initiative","") end)
    for _,kind in ipairs({"damage","heal","temporary"}) do
     local n={damage="Урон",heal="Лечение",temporary="Врем. хиты"}
     rows[#rows+1]=button(n[kind].." "..S.amount,function() action(base()..S.id.."/resources/",{action=kind,amount=S.amount}) end)
    end
    rows[#rows+1]=button("Сменить количество ("..S.amount..")",function() local a={1,5,10,20,50} for i,v in ipairs(a) do if v==S.amount then S.amount=a[i%#a+1] break end end render() end)
    rows[#rows+1]=label("Состояния: "..table.concat(sh.conditions or {},", "),14)
   elseif S.tab=="skills" then
    local order={"acrobatics","animal_handling","arcana","athletics","deception","history","insight","intimidation","investigation","medicine","nature","perception","performance","persuasion","religion","sleight_of_hand","stealth","survival"}
    for _,k in ipairs(order) do local key=k rows[#rows+1]=button(skills[k].." "..signed(cs.skills[k]),function() roll("skill",key) end) end
   elseif S.tab=="notes" then
    rows[#rows+1]=label("Инвентарь",18) rows[#rows+1]=label(sh.inventory)
    rows[#rows+1]=label("Заметки",18) rows[#rows+1]=label(sh.notes)
    rows[#rows+1]=label("Предыстория",18) rows[#rows+1]=label(sh.background)
   else
    local list={}
    for _,a in ipairs(d.actions or {}) do if a.kind==(S.tab=="spells" and "spell" or "attack") then list[#list+1]=a end end
    local start=(S.page-1)*8+1
    for i=start,math.min(start+7,#list) do
     local a=list[i]
     rows[#rows+1]=button((a.kind=="spell" and (a.level==0 and "Заговор · " or a.level.." круг · ") or "")..a.name,function() S.open=S.open==a.id and nil or a.id render() end)
     if S.open==a.id then
      rows[#rows+1]=label((a.casting_time or "").." · "..(a.range or "").." · "..(a.duration or ""),13)
      rows[#rows+1]=label(a.description,14)
      if a.kind=="spell" and a.level>0 then
       local levels={}
       for n=a.level,(a.upcast_allowed and 9 or a.level) do local s=sh.slots[tostring(n)] if s and s.used<s.max then levels[#levels+1]=n end end
       if #levels>0 then
        local selected=S.slot[a.id] or levels[1]
        rows[#rows+1]=button("Ячейка "..selected.." · выбрать",function() for j,n in ipairs(levels) do if n==selected then S.slot[a.id]=levels[j%#levels+1] break end end render() end)
       else rows[#rows+1]=label("Нет свободных ячеек",14) end
      end
     end
     rows[#rows+1]=button("Применить "..a.name,function() cast(a) end)
    end
    if S.page>1 then rows[#rows+1]=button("Назад",function() S.page=S.page-1 render() end) end
    if start+7<#list then rows[#rows+1]=button("Далее",function() S.page=S.page+1 render() end) end
   end
  end
 end
 S.root.children=rows
end
S.draw=render
Commands.slsheet=function(cmd)
 cmd=tostring(cmd or "")
 if cmd=="stop" then S.on=false S.run=S.run+1 S.msg="Остановлен" render() return end
 if cmd=="refresh" then refresh() return end
 if cmd~="" and cmd~="start" then chat.Send("/slsheet start|stop|refresh") return end
 if S.on then return end
 if SHEET_TOKEN=="PASTE_PERSONAL_SHEET_TOKEN_HERE" or SHEET_TOKEN=="" then chat.Send("Укажите SHEET_TOKEN") return end
 S.on=true S.run=S.run+1 local run=S.run refresh()
 local function tick() if not S.on or run~=S.run then return end if not S.busy then refresh() end dmhub.Schedule(6,tick) end
 dmhub.Schedule(6,tick)
end
if DockablePanel and gui then DockablePanel.Register{name="SessionLab · лист",minWidth=350,maxWidth=420,vscroll=true,content=function()
 S.root=gui.Panel{width="100%",height="auto",flow="vertical",bgimage="panels/square.png",bgcolor="#1A1E26"} render() return S.root end}
end
print("SessionLab sheet loaded · /slsheet start")
-- End.
