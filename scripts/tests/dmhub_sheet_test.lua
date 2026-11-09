-- Run from repository root: lua scripts/tests/dmhub_sheet_test.lua
-- Native API contract test, not a substitute for visual QA in DMHub.
local sourcePath = (arg and arg[1]) or "scripts/SessionLabSheet_ASCII.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = file:read("*a") file:close()
assert(not source:find("[\128-\255]"), "Installable source must be ASCII")
assert(not source:find("%.vscrollPosition"), "Never index native scroll-position userdata")
source = source:gsub("PASTE_PERSONAL_SHEET_TOKEN_HERE", "test_personal_token_12345678901234567890")
local queue, requests = {}, {}
local modal, dock, pendingPost, heldGet
local nextPost, holdGet = "ok", false
local postCount = 0
local lastPost
local replay={}
local fixture = {
 character={id=1.0,name="Test Hero",level=5.0,folder=10},
 sheet={version=1,spell_ability="int",skills={},saves={},background="",initiative_bonus=0,death_successes=0,death_failures=0,armor_class=16,hp_current=30,hp_max=40,hp_temp=0,speed=30,
  abilities={str=14,dex=12,con=12,int=16,wis=10,cha=10},conditions={},inventory="",notes="",
  computed={modifiers={str=2,dex=1},saves={str=2},skills={acrobatics=1},initiative=1,proficiency=3,spell_attack=6,spell_dc=14},
  slots={["3"]={max=2,used=0},["4"]={max=1,used=0}}},
 actions={{id=7.0,version=1,name="Ray",kind="spell",level=0.0,description="Cantrip description"},
  {id=8.0,version=1,name="Fireball",kind="spell",level=3.0,upcast_allowed=true,description="Damage spell"},
  {id=9.0,version=1,name="Sword",kind="attack",level=0}},
}
local function copy(t)
 if type(t)~="table" then return t end
 local result={} for k,v in pairs(t) do result[k]=copy(v) end return result
end
local function ctor(kind)
 return function(props)
  assert(props.borderBox==nil, "Unsupported borderBox")
  assert(#props==0, "Use ordered children, not mixed numeric constructor fields")
  props.kind=kind props.children=props.children or {}
  local proxy={}
  local destroyed=false
  props.DestroySelf=function()
   if destroyed then return end
   if props.destroy then props.destroy() end
   for _,child in ipairs(props.children) do child:DestroySelf() end
   destroyed=true
  end
  return setmetatable(proxy,{__index=function(_,k)
   assert(not destroyed,"Error indexing destroyed userdata: "..k)
   assert(k~="vscrollPosition","Unsupported native scroll getter")
   return props[k]
  end,__newindex=function(_,k,v)
   assert(not destroyed,"Error assigning destroyed userdata: "..k)
   assert(k=="children" or k=="text" or k=="x" or k=="y", "Unsupported setter: "..k)
   if k=="children" then for _,child in ipairs(props.children) do child:DestroySelf() end end
   props[k]=v
  end})
 end
end
gui={Panel=ctor("panel"),Label=ctor("label"),Input=ctor("input"),Button=ctor("button")}
gui.ShowModal=function() error("Sheet must not block the game with a modal") end
GameHud={instance={dialogWorldPanel={AddChild=function(_,w) assert(w.floating and w.constrainToScreen) modal=w end}}}
gui.CloseModal=function() error("Sheet must close only its own window") end
DockablePanel={Register=function(config) dock=config end}
Commands={RegisterMacro=function() end}
chat={Send=function() end}
-- Exact environment behind the reported error: json is a FUNCTION.
json=function() error("Global json must not be used for transport") end
dmhub={screenDimensions={x=1280,y=960},Schedule=function(_,fn) queue[#queue+1]=fn end,
 FromJson=function(raw)
  assert(raw=="fixture-json", "Unexpected JSON")
  return {data=copy(fixture)}
 end}
net={Get=function(o)
 requests[#requests+1]=o
 assert(type(o.error)=="function", "DMHub uses error callback")
 if holdGet then heldGet=o return end
 if o.url:find("/scene/",1,true) then o.success({data={targets={}}})
 elseif o.url:find("/catalog/?",1,true) then
  o.success({data={count=31,results={{id=100,name_ru="Каталог заклинание",level=2,rules={description="Описание из каталога"}}}}})
 elseif o.url:match("/sheets/$") then o.success({data={characters={fixture.character,{id=2,name="NPC",folder=20},{id=3,name="Loose",kind="npc"}},folders={{id=10,name="Игроки",is_system=true},{id=20,name="Важные NPC"}}}})
 else assert(o.url:match("/sheets/1/$"),o.url) o.success({data=copy(fixture)}) end
end,
Post=function(o)
 postCount=postCount+1 requests[#requests+1]=o lastPost=o
 assert(type(o.data)=="table", "net.Post requires a table, not encoded JSON")
 assert(o.body==nil, "No undocumented body field")
 assert(o.headers["Idempotency-Key"] and o.headers.Authorization)
 if nextPost=="hold" then pendingPost=o return end
 if nextPost=="error" then o.error("HTTP 400: invalid spell") return end
 if nextPost=="api-error" then o.success({error={message="No spell slot"}}) return end
 local key=o.headers["Idempotency-Key"]
 if replay[key] then o.success(copy(replay[key])) return end
 local data=o.data local result
 if o.url:match("/conditions/$") then
  local present={} for _,item in ipairs(fixture.sheet.conditions) do present[item]=true end
  for _,item in ipairs(data.remove or {}) do present[item]=nil end
  for _,item in ipairs(data.add or {}) do present[item]=true end
  fixture.sheet.conditions={} for item in pairs(present) do fixture.sheet.conditions[#fixture.sheet.conditions+1]=item end
  fixture.sheet.version=fixture.sheet.version+1 result=copy(fixture.sheet)
 elseif o.url:match("/sheets/1/edit/$") then
  if data.version~=fixture.sheet.version then o.success({error={detail="Stale version"}}) return end
  for k,v in pairs(data) do if k~="version" then fixture.sheet[k]=copy(v) end end
  fixture.sheet.version=fixture.sheet.version+1 result=copy(fixture.sheet)
 elseif o.url:match("/resources/$") and data.action=="restore_slots" then
  for _,v in pairs(fixture.sheet.slots) do v.used=0 end
  fixture.sheet.version=fixture.sheet.version+1 result=copy(fixture.sheet)
 elseif o.url:match("/abilities/$") then
  result=copy(data) result.id=200+#fixture.actions result.version=1
  fixture.actions[#fixture.actions+1]=result
 elseif o.url:match("/abilities/%d+/edit/$") then
  local id=tonumber(o.url:match("/abilities/(%d+)/"))
  for i,a in ipairs(fixture.actions) do if a.id==id then
   result=copy(a) for k,v in pairs(data) do result[k]=copy(v) end
   result.version=a.version+1
   if data.active==false then table.remove(fixture.actions,i) else fixture.actions[i]=result end
   break
  end end
 elseif o.url:match("/catalog%-add/$") then
  result={id=1000,version=1,catalog_entry=data.spell_id,name="Каталог заклинание",kind="spell",level=2,upcast_allowed=true}
  fixture.actions[#fixture.actions+1]=result
 else
  result={id=55,kind="ability",payload={damage_type="fire",label="Fireball",save={dc=14,failed_damage=27,success_damage=13},damage={total=27}}}
  fixture.sheet.version=fixture.sheet.version+1
 end
 local response={data=result} replay[key]=copy(response) o.success(response)
end}
local function find(root,caption)
 if root.text==caption then return root end
 for _,child in ipairs(root.children or {}) do local found=find(child,caption) if found then return found end end
end
local function press(caption)
 local b=assert(find(modal,caption),"Missing button: "..caption)
 assert(b.interactable~=false,"Disabled button: "..caption)
 b.press(b)
end
local function check(node,parentWidth)
 local w=node.width
 if type(w)=="number" then
  assert(w>=0,"Negative width")
  if type(parentWidth)=="number" and not node.floating then assert(w<=parentWidth+1,"Child wider than parent: "..w.." > "..parentWidth) end
 end
 local total=0
 for _,c in ipairs(node.children or {}) do
  check(c,w)
  if not c.floating and type(c.width)=="number" then total=total+c.width+2*(c.hmargin or 0)+2*(c.hpad or 0) end
 end
 if node.flow=="horizontal" and type(w)=="number" then assert(total<=w+1,"Row overflow: "..total.." > "..w) end
end
local function runDue()
 local q=queue queue={}
 for _,fn in ipairs(q) do fn() end
end
local function actionCard(name,root)
 root=root or modal
 local children=root.children or {}
 if root.classes and root.classes[1]=="slcard" and children[2] and children[2].children[1] and children[2].children[1].text==name then return root end
 for _,child in ipairs(children) do local found=actionCard(name,child) if found then return found end end
end
local function actionPress(name,caption)
 local b=assert(find(assert(actionCard(name),"Missing action "..name),caption),caption)
 assert(b.interactable~=false) b.press(b)
end
local function formInput(title,value)
 local function scan(node)
  local ch=node.children or {}
  if ch[1] and ch[1].text==title and ch[2] and ch[2].kind=="input" then return ch[2] end
  for _,c in ipairs(ch) do local r=scan(c) if r then return r end end
 end
 local element=assert(scan(modal),"Missing input "..title)
 element.text=value element.edit(element)
end
assert(load(source,"SessionLabSheet"))()
local launcher=dock.content() find(launcher,"Открыть лист").press() runDue()
local state=rawget(_G,"SLsheet")
assert(state.data and not state.busy) check(modal)
assert(state.panel.children[1].children[1]==state.leftScroll)
assert(not find(modal,"Все действия · 3"))
press("Заклинания") check(modal)
for _=1,3 do
 actionPress("Ray","Подробнее") assert(state.open==7 and find(modal,"Cantrip description"))
 actionPress("Ray","Скрыть") assert(state.open==nil and not find(modal,"Cantrip description"))
end
for _,key in ipairs({8,"8","8.0"}) do
 fixture.sheet.version=fixture.sheet.version+1 fixture.sheet.slots={[key]={max=10.0,used=0.0}}
 press("Обновить") assert(state.level[8]==8)
 assert(find(modal,"Ячейка 8 · осталось 10"))
 actionPress("Fireball","Сотворить") assert(lastPost.data.slot_level==8)
end
assert(state.result:find("Провал: 27 / Успех: 13",1,true))
local handoff
rawset(_G,"SessionLabRoomRuntime",{openDamage=function(id) handoff=id end})
find(state.window,"Нанести урон").press()
assert(handoff==55,"Sheet result must open matching saved event in native room")
local oldLeft,oldRight=state.leftScroll,state.rightScroll
press("Обновить") assert(oldLeft==state.leftScroll and oldRight==state.rightScroll)
-- Editor draft survives typing and scheduled polling.
actionPress("Ray","Изменить")
formInput("Название","Ray edited") formInput("Описание, компоненты и особые правила","New description")
local requestCount=#requests runDue()
assert(#requests==requestCount and state.editor.value.name=="Ray edited")
check(modal) press("Сохранить")
assert(not state.editor and fixture.actions[1].name=="Ray edited")
-- Native POST error keeps the draft and provides an idempotent retry.
press("Добавить") formInput("Название","Новая магия")
nextPost="error" press("Сохранить")
assert(state.editor and state.pendingWrite and not state.busy)
local retryKey=lastPost.headers["Idempotency-Key"]
nextPost="ok" press("Повторить тот же запрос")
assert(lastPost.headers["Idempotency-Key"]==retryKey and not state.pendingWrite)
assert(actionCard("Новая магия"))
actionPress("Новая магия","Удалить") press("Подтвердить")
assert(not actionCard("Новая магия"))
-- Catalog operates on the server and supports adding in one click.
press("Справочник") assert(find(modal,"Каталог заклинание"))
press("Описание заклинания") assert(find(modal,"Описание из каталога"))
press("Скрыть описание") assert(not find(modal,"Описание из каталога"))
press("Добавить в лист") assert(lastPost.data.spell_id==100)
press("Назад к заклинаниям") assert(actionCard("Каталог заклинание"))
press("Обзор") press("Настроить ячейки") check(modal)
assert(state.editor.kind=="magic")
state.editor.value.slots["8"]={max=12,used=5}
press("Сохранить") assert(fixture.sheet.slots["8"].max==12)
press("Восстановить ячейки") press("Подтвердить") assert(fixture.sheet.slots["8"].used==0)
press("Редактировать боевые ресурсы")
formInput("Максимальные хиты","50") formInput("Класс доспеха","18")
press("Сохранить") assert(fixture.sheet.hp_max==50 and fixture.sheet.armor_class==18)
press("Редактировать записи")
formInput("Инвентарь","Rope") formInput("Заметки","Notes")
press("Сохранить") assert(fixture.sheet.inventory=="Rope" and fixture.sheet.notes=="Notes")
press("14") formInput("Сила","18") press("Сохранить")
assert(fixture.sheet.abilities.str==18)
local savesNode=state.leftScroll.children[1].children[5]
savesNode.children[2].children[2].children[1].press()
assert(fixture.sheet.saves[1]=="str")
savesNode=state.leftScroll.children[1].children[5]
savesNode.children[2].children[2].children[1].press()
assert(#fixture.sheet.saves==0)
press("Состояния · 0") press("[ ] Ослеплён")
fixture.sheet.version=fixture.sheet.version+1 fixture.sheet.conditions={"Испуган"}
press("Сохранить")
assert(lastPost.url:match("/conditions/$") and lastPost.data.add[1]=="Ослеплён" and lastPost.data.version==nil)
local conditions={} for _,name in ipairs(fixture.sheet.conditions) do conditions[name]=true end
assert(conditions["Ослеплён"] and conditions["Испуган"])
press("Новая атака") press("Добавить Удар Суда") formInput("Название","Archer") formInput("Кубики урона / лечения","1d8")
formInput("Количество бросков","3")
press("Атака 1: Обычная >") press("Преимущество")
press("Атака 3: Обычная >") press("Помеха")
press("Сохранить") assert(actionCard("Archer"))
assert(lastPost.data.roll_modes[1]=="advantage" and lastPost.data.roll_modes[2]=="normal" and lastPost.data.roll_modes[3]=="disadvantage")
actionPress("Archer","Атаковать")
assert(state.editor and state.editor.kind=="cast_effects")
press("Бросить") assert(lastPost.data.slot_level==0 and lastPost.data.effects[1]=="judgment")
-- Exercise quick proficiency cycle with the actual sidebar control.
for expected=1,3 do
 local skillsNode=state.leftScroll.children[1].children[6]
 local row=skillsNode.children[2].children[2]
 row.children[1].press()
 assert((fixture.sheet.skills.acrobatics or 0)==expected%3)
end
-- Dense lists show every action in a bounded scroll area, without a truncation button.
for i=1,45 do fixture.actions[#fixture.actions+1]={id=3000+i,version=1,kind="spell",level=i%10,name=string.format("Extra %02d",i),upcast_allowed=true} end
fixture.sheet.version=fixture.sheet.version+1
press("Обновить") assert(actionCard("Extra 45"))
press("Заклинания") assert(actionCard("Extra 45")) check(modal)
press("Круг: Все круги >") press("Заговоры")
assert(actionCard("Ray edited") and not actionCard("Extra 45"))
press("Круг: Заговоры >") press("Все круги")
press("Порядок: По кругу >") press("По имени")
assert(state.lists.spell.sort=="name")
-- A slot change must update only the pressed label, keeping every scroll subtree mounted.
fixture.sheet.slots={[3]={max=2,used=0},[8]={max=10,used=0}}
fixture.sheet.version=fixture.sheet.version+1 press("Обновить")
local beforeRoot=state.rightScroll.children[1]
local fireball=assert(actionCard("Fireball"))
local slotControl=assert(find(fireball,"Ячейка 8 · осталось 10"))
slotControl.press()
assert(state.level[8]==3 and slotControl.text=="Ячейка 3 · осталось 2")
assert(state.rightScroll.children[1]==beforeRoot and actionCard("Fireball")==fireball)
slotControl.press() assert(state.level[8]==8 and slotControl.text=="Ячейка 8 · осталось 10")
-- Folder headers expand the real folder contents, with a separate unfiled group.
press("Test Hero  ›")
assert(find(modal,"+ Игроки · 1") and find(modal,"+ Важные NPC · 1") and find(modal,"+ Без папки · 1"))
assert(not find(modal,"NPC"))
local stableRight=state.rightScroll and state.rightScroll.children[1]
local stableLeft=state.leftScroll and state.leftScroll.children[1]
press("+ Важные NPC · 1") assert(find(modal,"NPC"))
assert(not stableRight or state.rightScroll.children[1]==stableRight,"Folder expansion rebuilt spells")
assert(not stableLeft or state.leftScroll.children[1]==stableLeft,"Folder expansion rebuilt attributes")
assert(modal.draggable and modal.drag,"Window must own the native drag handler")
local event={xdrag=91,ydrag=-27} modal.drag(event)
assert(event.x==91 and event.y==-27,"Drag must update the event target coordinates")
press("Закрепить для боя")
assert(state.pinned[1] and find(modal,"БЫСТРЫЙ ДОСТУП"))
local search
local function findSearch(node)
 if node.kind=="input" and node.placeholderText=="Поиск по имени или папке" then search=node end
 for _,child in ipairs(node.children or {}) do findSearch(child) end
end
findSearch(modal) assert(search)
local stable=state.rightScroll.children[1]
search.edit({text="NPC"})
assert(find(modal,"NPC · Важные NPC") and not find(modal,"+ Игроки · 1"))
assert(state.rightScroll.children[1]==stable,"Search rebuilt the sheet")
search.change({text=""})
press("- Важные NPC · 1") assert(not find(modal,"NPC"))
press("Test Hero  ›")
-- Destruction is simulated recursively by the GUI proxy; accessing a dead pane fails.
for _,size in ipairs({{940,720},{720,680},{420,700}}) do
 press("Закрыть") assert(not state.window and not state.leftScroll and not state.windowTitle and not state.on)
 runDue() assert(#queue==0, "Closed sheet rescheduled polling")
 dmhub.screenDimensions={x=size[1],y=size[2]} Commands.slsheet("open") check(modal)
 press("Заклинания") check(modal)
 press("Обзор") check(modal)
end
modal:DestroySelf() launcher:DestroySelf() assert(state.launchStatus==nil) runDue()
Commands.slsheet("open") check(modal)
print("PASS: stable slot-change subtree, condition deltas, folder groups, editable forms, idempotent retry, 45-action scroll, lifecycle and layout")
