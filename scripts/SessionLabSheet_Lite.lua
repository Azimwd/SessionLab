-- SessionLab sheet, compact edition. The token belongs only in the line below.
local URL="https://sessionlab.up.railway.app"
local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
if _G.SLsheet then _G.SLsheet.on=false end
local S={on=false,run=0,tab="stats",page=1,slot={},amount=5,msg="/slsheet start",list={}}
_G.SLsheet=S
local abilities={{"str","Сила"},{"dex","Ловкость"},{"con","Телосложение"},{"int","Интеллект"},{"wis","Мудрость"},{"cha","Харизма"}}
local skills={{"acrobatics","Акробатика"},{"animal_handling","Животные"},{"arcana","Магия"},{"athletics","Атлетика"},{"deception","Обман"},{"history","История"},{"insight","Проницательность"},{"intimidation","Запугивание"},{"investigation","Анализ"},{"medicine","Медицина"},{"nature","Природа"},{"perception","Внимательность"},{"performance","Выступление"},{"persuasion","Убеждение"},{"religion","Религия"},{"sleight_of_hand","Ловкость рук"},{"stealth","Скрытность"},{"survival","Выживание"}}
local function L(t,n) return gui.Label{text=tostring(t or ""),fontSize=n or 15,color="#F4F5F7",width="100%",height="auto",vmargin=2} end
local function B(t,f) return gui.Label{text=t,fontSize=15,color="#F4F5F7",width="100%",height=28,vmargin=2,bgimage="panels/square.png",bgcolor="#353B50",click=f} end
local function sign(n) n=tonumber(n) or 0 return n>=0 and "+"..n or tostring(n) end
local root="/api/integrations/dmhub/sheets/"
local draw,refresh
local function request(path,body,done)
 local run=S.run
 local h={Authorization="Bearer "..TOKEN,Accept="application/json"}
 local method=body and net.Post or net.Get
 if type(method)~="function" then S.msg="HTTP недоступен" draw() return end
 local o={url=URL..path,headers=h}
 o.success=function(raw)
  if not S.on or run~=S.run then return end
  S.busy=false
  local ok,r=pcall(function() return type(raw)=="table" and raw or json.decode(raw) end)
  if ok and type(r)=="table" and type(r.data)=="table" then done(r.data)
  else S.msg="Ошибка ответа API" draw() end
 end
 o.failure=function(e) if S.on and run==S.run then S.busy=false S.msg="Сбой сети: проверьте результат на сайте" draw() end end
 if body then
  S.busy=true S.seq=(S.seq or 0)+1
  h["Content-Type"]="application/json"
  h["Idempotency-Key"]=tostring(os.time()).."-"..S.seq.."-"..math.random(100000,999999)
  o.body=json.encode(body) o.data=o.body
 end
 local ok,e=pcall(function() method(o) end)
 if not ok then S.busy=false S.msg=tostring(e):sub(1,70) draw() end
end
refresh=function()
 if not S.on then return end
 if not S.id then
  request(root,nil,function(d) S.list=d.characters or {} if S.list[1] then S.id=S.list[1].id refresh() else S.msg="Нет листов" draw() end end)
 else request(root..S.id.."/",nil,function(d) S.data=d S.msg="Обновлено" draw() end) end
end
local function post(path,body)
 if S.busy then return end
 S.msg="Отправка..." draw()
 request(path,body,function(d)
  local p=d.payload
  if p then
   local x=(p.parts or {p})[1] or {}
   S.result=tostring(p.label or "Бросок")
   if x.roll then S.result=S.result.." · "..tostring(x.roll.total) end
   if x.damage then S.result=S.result.." · урон "..tostring(x.damage.total) end
   if x.save then S.result=S.result.." · СЛ "..tostring(x.save.dc) end
  end
  refresh()
 end)
end
local function roll(kind,key) post(root..S.id.."/roll/",{kind=kind,key=key}) end
local function cast(a,sh)
 local n=S.slot[a.id] or a.level or 0
 if a.kind=="spell" and a.level>0 then
  local slots=sh.slots or {}
  if not slots[tostring(n)] or slots[tostring(n)].used>=slots[tostring(n)].max then
   n=nil
   for i=a.level,(a.upcast_allowed and 9 or a.level) do
    local v=slots[tostring(i)] if v and v.used<v.max then n=i break end
   end
  end
  if not n then S.msg="Нет ячеек" draw() return end
 end
 post(root..S.id.."/abilities/"..a.id.."/use/",{slot_level=n})
end
draw=function()
 if not S.panel then return end
 local rows={L("SessionLab · лист",22),L(S.msg,13)}
 if S.result then rows[#rows+1]=L(S.result,19) end
 if S.on then
  rows[#rows+1]=B("Обновить",refresh)
  for _,c in ipairs(S.list) do local id=c.id rows[#rows+1]=B((id==S.id and "• " or "")..c.name,function() S.id=id S.data=nil S.page=1 refresh() end) end
  local d=S.data
  if d and d.character and d.character.id==S.id then
   local sh=d.sheet local cs=sh.computed
   rows[#rows+1]=L(d.character.name.." · "..d.character.level.." ур.",19)
   rows[#rows+1]=L("КД "..sh.armor_class.." · Хиты "..sh.hp_current.."/"..sh.hp_max.." · Врем. "..sh.hp_temp)
   local tabs={{"stats","Показатели"},{"skills","Навыки"},{"attacks","Атаки"},{"spells","Заклинания"},{"notes","Заметки"}}
   for _,t in ipairs(tabs) do local tab=t[1] rows[#rows+1]=B((S.tab==tab and "• " or "")..t[2],function() S.tab=tab S.page=1 S.open=nil draw() end) end
   if S.tab=="stats" then
    for _,a in ipairs(abilities) do local k=a[1] rows[#rows+1]=B(a[2].." "..sh.abilities[k].." "..sign(cs.modifiers[k]),function() roll("ability",k) end)
     rows[#rows+1]=B("Спасбросок "..a[2].." "..sign(cs.saves[k]),function() roll("save",k) end) end
    rows[#rows+1]=B("Инициатива "..sign(cs.initiative),function() roll("initiative","") end)
    rows[#rows+1]=B("Количество: "..S.amount,function() local v={1,5,10,20,50} for i,n in ipairs(v) do if n==S.amount then S.amount=v[i%#v+1] break end end draw() end)
    for _,a in ipairs({{"damage","Урон"},{"heal","Лечение"},{"temporary","Врем. хиты"}}) do
     local kind=a[1] rows[#rows+1]=B(a[2].." "..S.amount,function() post(root..S.id.."/resources/",{action=kind,amount=S.amount}) end) end
    rows[#rows+1]=L("Состояния: "..table.concat(sh.conditions or {},", "))
   elseif S.tab=="skills" then
    for _,a in ipairs(skills) do local k=a[1] rows[#rows+1]=B(a[2].." "..sign(cs.skills[k]),function() roll("skill",k) end) end
   elseif S.tab=="notes" then
    rows[#rows+1]=L("Инвентарь",18) rows[#rows+1]=L(sh.inventory)
    rows[#rows+1]=L("Заметки",18) rows[#rows+1]=L(sh.notes)
   else
    local list={}
    for _,a in ipairs(d.actions or {}) do if a.kind==(S.tab=="spells" and "spell" or "attack") then list[#list+1]=a end end
    local first=(S.page-1)*6+1
    for i=first,math.min(first+5,#list) do
     local a=list[i] rows[#rows+1]=B((a.kind=="spell" and a.level.." круг · " or "")..a.name,function() S.open=S.open==a.id and nil or a.id draw() end)
     if S.open==a.id then
      rows[#rows+1]=L((a.casting_time or "").." · "..(a.range or "").." · "..(a.duration or ""),13)
      rows[#rows+1]=L(a.description)
      if a.kind=="spell" and a.level>0 then
       local v={}
       for n=a.level,(a.upcast_allowed and 9 or a.level) do local x=(sh.slots or {})[tostring(n)] if x and x.used<x.max then v[#v+1]=n end end
       if #v>0 then local n=S.slot[a.id] or v[1]
        rows[#rows+1]=B("Ячейка "..n.." · выбрать",function() for j,k in ipairs(v) do if n==k then S.slot[a.id]=v[j%#v+1] break end end draw() end)
       else rows[#rows+1]=L("Нет ячеек") end
      end
     end
     rows[#rows+1]=B("Применить "..a.name,function() cast(a,sh) end)
    end
    if S.page>1 then rows[#rows+1]=B("Назад",function() S.page=S.page-1 draw() end) end
    if first+5<#list then rows[#rows+1]=B("Далее",function() S.page=S.page+1 draw() end) end
   end
  end
 end
 S.panel.children=rows
end
Commands.slsheet=function(cmd)
 cmd=tostring(cmd or "")
 if cmd=="stop" then S.on=false S.run=S.run+1 S.msg="Остановлен" draw() return end
 if cmd=="refresh" then refresh() return end
 if S.on then return end
 if TOKEN=="" or TOKEN:find("^PASTE_") then chat.Send("Укажите TOKEN в файле") return end
 S.on=true S.run=S.run+1 local run=S.run refresh()
 local function tick() if not S.on or run~=S.run then return end if not S.busy then refresh() end dmhub.Schedule(6,tick) end
 dmhub.Schedule(6,tick)
end
if DockablePanel and gui then DockablePanel.Register{name="SessionLab · лист",minWidth=350,maxWidth=420,vscroll=true,content=function()
 S.panel=gui.Panel{width="100%",height="auto",flow="vertical"} draw() return S.panel end}
end
print("SessionLab sheet loaded · /slsheet start")
-- End.
