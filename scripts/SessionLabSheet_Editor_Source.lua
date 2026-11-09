-- Included in the same Lua chunk by build_dmhub_sheet.py. Never install this file alone.
local function clone(t)
 if type(t)~="table" then return t end
 local r={} for k,v in pairs(t) do r[k]=clone(v) end return r
end
local function input(value,w,onEdit,multiline,onSubmit)
 local function edit(e) onEdit(e.text or "") end
 return gui.Input{text=tostring(value or ""),width=w,height=multiline and 140 or 34,multiline=multiline or false,
  fontSize=14,hmargin=0,vmargin=3,hpad=0,vpad=0,classes={"slinput"},interactable=not S.busy,
  edit=function(e) if not S.editor then S.typing=true end edit(e) end,
  change=function(e) edit(e) S.typing=false end,deselect=function() S.typing=false end,
  submit=function(e) S.typing=false if onSubmit then onSubmit(e) end end}
end
local function field(title,value,w,update,multiline)
 return column({label(title,w,12,"#A0A6B2"),input(value,w,update,multiline)},w)
end
local function numeric(title,value,w,update)
 return field(title,num(value),w,function(s) update(tonumber(s) or s) end)
end
local function cycle(title,value,choices,w,update,key)
 key=key or title
 local titleValue=""
 for _,c in ipairs(choices) do if c[1]==value then titleValue=c[2] end end
 local items={button(title..": "..titleValue.." >",w,function()
  if S.selectOpen==key then S.selectOpen=nil else S.selectOpen=key end draw()
 end)}
 if S.selectOpen==key then
  for _,choice in ipairs(choices) do local option=choice
   items[#items+1]=button(option[2],w,function() S.selectOpen=nil update(option[1]) draw() end,option[1]==value)
  end
 end
 return column(items,w)
end
local function flag(title,value,w,update)
 return button((value and "[x] " or "[ ] ")..title,w,function() update(not value) draw() end,value)
end
framed=function(children,w,h)
 return gui.Panel{width=w,height=h,flow="vertical",halign="left",valign="top",hmargin=0,vmargin=5,hpad=0,vpad=0,classes={"slcard"},interactable=false,children={
  gui.Panel{width=w,height=12},
  gui.Panel{width=w-24,height=h-24,flow="vertical",halign="center",valign="top",vscroll=true,hmargin=0,vmargin=0,hpad=0,vpad=0,children={column(children,w-40)}},
  gui.Panel{width=w,height=12}}}
end
confirmAction=function(question,fn)
 if S.busy then return end
 S.confirm={question=question,yes=fn} draw()
end
local function sendWrite(pending)
 if S.busy then return end
 S.busy=true S.msg="Сохранение..." draw()
 api(pending.path,pending.body,function(data)
  S.pendingWrite=nil
  if pending.id==S.id then
   S.editor=nil S.confirm=nil S.msg="Сохранено"
   if pending.done then pending.done(data) end
   S.renderedData=false refresh()
  end
 end,pending.key)
end
write=function(path,body,done)
 if S.busy or S.pendingWrite then return end
 S.writeSeq=(S.writeSeq or 0)+1
 local pending={path=path,body=clone(body),done=done,id=S.id,
  key="sheet-"..tostring(os.time()).."-"..S.writeSeq.."-"..math.random(100000,999999)}
 S.pendingWrite=pending sendWrite(pending)
end
local function saveSheet(data)
 local body=clone(data) body.version=S.data.sheet.version
 write(base..idstr(S.id).."/edit/",body)
end
local function cancelEditor()
 confirmAction("Отменить несохранённые изменения?",function() S.editor=nil S.confirm=nil S.renderedData=false refresh() draw() end)
end
beginEdit=function(kind,action)
 if S.busy or S.pendingWrite then return end
 if S.editor then confirmAction("Отменить текущую форму?",function() S.editor=nil beginEdit(kind,action) end) return end
 local value
 if kind=="action" then
  value=clone(action or {})
 else value=clone(S.data.sheet) end
 S.editor={kind=kind,value=value,id=S.id,conditionsBefore=clone(value.conditions or {})} S.confirm=nil draw()
end
local function newAction(kind)
 beginEdit("action",{kind=kind,use_spell_ability=kind=="spell",name="",description="",ability=kind=="spell" and S.data.sheet.spell_ability or "str",
  proficient=true,bonus=0,resolution=kind=="spell" and "save" or "attack",dice="1d6",add_modifier=kind=="attack",damage_type="",
  level=kind=="spell" and 1 or 0,upcast_dice="",upcast_allowed=true,roll_count=1,roll_modes={},attack_effects={},upcast_count=0,
  cantrip_scaling=false,save_ability="dex",save_success="none",casting_time="1 действие",range="",duration="",concentration=false})
end
local function archiveAction(a)
 confirmAction("Удалить «"..a.name.."» из листа?",function()
  S.confirm=nil write(base..idstr(S.id).."/abilities/"..idstr(a.id).."/edit/",{version=a.version,active=false})
 end)
end
local conditionNames={"Ослеплён","Очарован","Оглох","Испуган","Схвачен","Недееспособен","Невидим","Парализован","Окаменел","Отравлен","Сбит с ног","Опутан","Ошеломлён","Без сознания","Концентрация"}
local function has(list,item) for _,v in ipairs(list or {}) do if v==item then return true end end return false end
local function toggle(list,item)
 local out={} local found=false
 for _,v in ipairs(list or {}) do if v==item then found=true else out[#out+1]=v end end
 if not found then out[#out+1]=item end return out
end
local function quickSkill(k)
 if S.editor then return end
 local skills=clone(S.data.sheet.skills or {}) skills[k]=((tonumber(skills[k]) or 0)+1)%3
 saveSheet({skills=skills})
end
local function quickSave(k) if not S.editor then saveSheet({saves=toggle(S.data.sheet.saves,k)}) end end
local function restoreSlots()
 confirmAction("Восстановить все ячейки после отдыха?",function()
  S.confirm=nil write(base..idstr(S.id).."/resources/",{action="restore_slots",version=S.data.sheet.version})
 end)
end
local classChoices={{"","Все классы"},{"Bard","Бард"},{"Cleric","Жрец"},{"Druid","Друид"},{"Paladin","Паладин"},{"Ranger","Следопыт"},{"Sorcerer","Чародей"},{"Warlock","Колдун"},{"Wizard","Волшебник"}}
local schoolChoices={{"","Все школы"},{"abjuration","Ограждение"},{"conjuration","Вызов"},{"divination","Прорицание"},{"enchantment","Очарование"},{"evocation","Воплощение"},{"illusion","Иллюзия"},{"necromancy","Некромантия"},{"transmutation","Преобразование"}}
local levelChoices={{-1,"Все круги"},{0,"Заговоры"}}
for n=1,9 do levelChoices[#levelChoices+1]={n,num(n).." круг"} end
local function urlencode(s) return (tostring(s):gsub("[^%w%-_%.~]",function(c) return string.format("%%%02X",string.byte(c)) end)) end
local function loadCatalog()
 S.typing=false
 local c=S.catalog if not c or c.loading then return end
 c.loading=true S.catSeq=(S.catSeq or 0)+1 local seq=S.catSeq
 local url="/api/integrations/dmhub/catalog/?offset="..num(c.offset).."&q="..urlencode(c.q or "").."&class="..urlencode(c.class or "").."&school="..urlencode(c.school or "")
 if c.level>=0 then url=url.."&level="..num(c.level) end
 api(url,nil,function(data)
  if S.catalog~=c or seq~=S.catSeq then return end
  c.loading=false c.results=data.results or {} c.count=data.count or 0 draw()
 end,nil,function() if S.catalog==c then c.loading=false end end)
end
openCatalog=function()
 if S.editor then return end
 S.catalog={q="",class="",school="",level=-1,offset=0,results={},count=0} S.tab="catalog"
 draw() loadCatalog()
end
local function addEffectPreset(v,key)
 v.attack_effects=v.attack_effects or {}
 local function add(e)
  if #v.attack_effects>=6 then return end
  for _,old in ipairs(v.attack_effects) do if old.id==e.id then return end end
  v.attack_effects[#v.attack_effects+1]=e
 end
 if key=="judgment" then add({id="judgment",name="Удар Суда",dice="1d8",damage_type="radiant",sign=1,frequency="turn",enabled=true,min_level=3,below_half_type="necrotic",critical_upgrade=true,scaling={{level=7,dice="1d10"},{level=10,dice="1d12"},{level=15,dice="2d10"}}})
 elseif key=="assessment" then
  add({id="assessment_sinful",name="Оценка: грешная цель",dice="1d4",damage_type="base",sign=1,frequency="all",enabled=false,min_level=7,group="assessment"})
  add({id="assessment_innocent",name="Оценка: невинная цель",dice="1d4",damage_type="base",sign=-1,frequency="all",enabled=false,min_level=7,group="assessment"})
 elseif key=="seal" then add({id="revenge_seal",name="Печать Возмездия",dice="1d8",damage_type="necrotic",sign=1,frequency="turn",enabled=false,min_level=10,target_required=true,advantage_first=true})
 else add({id="custom_"..tostring(os.time()).."_"..math.random(100000,999999),name="Новый эффект",dice="1d4",damage_type="base",sign=1,frequency="all",enabled=true,min_level=1}) end
 draw()
end
local function effectsEditor(v,w)
 local rows={label("ДОПОЛНИТЕЛЬНЫЕ ЭФФЕКТЫ",w,16,"#B3A9FF")}
 for _,option in ipairs({{"judgment","Добавить Удар Суда"},{"assessment","Добавить Оценку Жизни"},{"seal","Добавить Печать Возмездия"},{"custom","Добавить свой эффект"}}) do
  local o=option rows[#rows+1]=button(o[2],w,function() addEffectPreset(v,o[1]) end)
 end
 for i,e in ipairs(v.attack_effects or {}) do
  local index=i local effect=e
  rows[#rows+1]=label(e.name,w,18,"#B3A9FF")
  rows[#rows+1]=field("Имя эффекта",e.name,w,function(t) effect.name=t end)
  rows[#rows+1]=field("Кубики эффекта",e.dice,w,function(t) effect.dice=t end)
  rows[#rows+1]=cycle("Тип эффекта",e.damage_type or "base",{{"base","Как оружие"},{"radiant","Радиантный"},{"necrotic","Некротический"},{"fire","Огонь"},{"cold","Холод"},{"force","Силовой"},{"acid","Кислота"},{"lightning","Молния"},{"poison","Яд"},{"psychic","Психический"},{"thunder","Гром"},{"slashing","Рубящий"},{"piercing","Колющий"},{"bludgeoning","Дробящий"}},w,function(t) effect.damage_type=t end,"type-effect-"..i)
  rows[#rows+1]=cycle("Знак эффекта",e.sign or 1,{{1,"Добавить урон"},{-1,"Уменьшить основной урон"}},w,function(t) effect.sign=t end,"sign-effect-"..i)
  rows[#rows+1]=cycle("Ограничение эффекта",e.frequency or "all",{{"all","Каждое попадание"},{"action","Первое попадание применения"},{"turn","Раз за ход"}},w,function(t) effect.frequency=t end,"frequency-effect-"..i)
  rows[#rows+1]=flag("Включать по умолчанию",e.enabled~=false,w,function(t) effect.enabled=t end)
  rows[#rows+1]=flag("На крите добавить кости ступенью выше",e.critical_upgrade==true,w,function(t) effect.critical_upgrade=t end)
  rows[#rows+1]=flag("Ниже половины ХП: некротический урон",e.below_half_type=="necrotic",w,function(t) effect.below_half_type=t and "necrotic" or "" end)
  rows[#rows+1]=flag("Метка: выбрать цель до броска",e.target_required==true,w,function(t) effect.target_required=t end)
  rows[#rows+1]=flag("Преимущество первой атаке за ход",e.advantage_first==true,w,function(t) effect.advantage_first=t end)
  rows[#rows+1]=numeric("Минимальный уровень",e.min_level or 1,w,function(t) effect.min_level=t end)
  for n,step in ipairs(e.scaling or {}) do
   local s=step
   rows[#rows+1]=numeric("Рост: с уровня",step.level,w,function(t) s.level=t end)
   rows[#rows+1]=field("Рост: кубики",step.dice,w,function(t) s.dice=t end)
  end
  if #(e.scaling or {})<8 then rows[#rows+1]=button("Добавить ступень роста",w,function() effect.scaling=effect.scaling or {} effect.scaling[#effect.scaling+1]={level=math.min(30,(effect.scaling[#effect.scaling] and effect.scaling[#effect.scaling].level or 1)+1),dice=effect.dice} draw() end) end
  rows[#rows+1]=button("Удалить эффект",w,function() table.remove(v.attack_effects,index) draw() end)
 end
 return column(rows,w)
end
prepareEffectsCast=function(a,n,trigger)
 local ids={}
 for _,effect in ipairs(a.attack_effects or {}) do if effect.enabled~=false and (S.data.character.level or 1)>=(effect.min_level or 1) then ids[effect.id]=true end end
 local e={kind="cast_effects",id=S.id,value={},action=a,level=n,trigger=trigger,ids=ids,targets={}}
 S.editor=e draw()
 api("/api/integrations/dmhub/scene/",nil,function(d) if S.editor~=e then return end e.targets=d.targets or {} draw() end)
end

editorUI=function(w)
 local e=S.editor if not e then return {} end
 local v=e.value local inner=w-24 local half=math.floor((inner-8)/2)
 local rows={label(e.kind=="action" and (v.id and "Редактировать действие" or "Новое действие") or "Редактирование листа",inner,23),
  label("Изменения сохраняются на сайт. Пока форма открыта, автообновление приостановлено.",inner,12,"#A0A6B2")}
 local function set(k,val) v[k]=val end
 if e.kind=="cast_effects" then
  rows[#rows+1]=label("Активируйте эффекты по решению за столом. Длительность, заряды и истощение — вручную.",inner,13,"#A0A6B2")
  local marked=false
  for _,definition in ipairs(e.action.attack_effects or {}) do
   local effect=definition
   if (S.data.character.level or 1)>=(effect.min_level or 1) then
    rows[#rows+1]=flag(effect.name,e.ids[effect.id]==true,inner,function(value)
     if value and effect.group then for _,other in ipairs(e.action.attack_effects) do if other.group==effect.group then e.ids[other.id]=nil end end end
     e.ids[effect.id]=value
    end)
   else rows[#rows+1]=label(effect.name.." · требуется уровень "..tostring(effect.min_level),inner,13,"#A0A6B2") end
   if e.ids[effect.id] and effect.target_required then marked=true end
  end
  if marked then
   local choices={{0,"Выберите цель метки"}}
   for _,t in ipairs(e.targets) do if t.targetable then choices[#choices+1]={t.id,t.name} end end
   rows[#rows+1]=cycle("Цель метки",e.target or 0,choices,inner,function(value) e.target=value end)
  end
 elseif e.kind=="action" then
  rows[#rows+1]=field("Название",v.name,inner,function(t) set("name",t) end)
  if v.kind=="spell" then rows[#rows+1]=flag("Основная характеристика магии из листа",v.use_spell_ability==true,inner,function(t) set("use_spell_ability",t) end) end
  if v.kind~="spell" or not v.use_spell_ability then rows[#rows+1]=cycle("Характеристика",v.ability,attrs,inner,function(t) set("ability",t) end)
  else rows[#rows+1]=label("Используется характеристика магии из листа: "..tostring(S.data.sheet.spell_ability),inner,13,"#B3A9FF") end
  rows[#rows+1]=cycle("Применение",v.resolution,{{"attack","Бросок атаки"},{"save","Спасбросок цели"},{"automatic","Автоматически"}},inner,function(t) set("resolution",t) end)
  rows[#rows+1]=cycle("Эффект",(v.damage_type=="лечение" or v.damage_type=="healing" or v.damage_type=="heal" or v.damage_type=="исцеление") and "healing" or "damage",{{"damage","Урон"},{"healing","Лечение"}},inner,function(t) v.damage_type=t=="healing" and "лечение" or "" if t=="healing" then v.resolution="automatic" end end)
  rows[#rows+1]=line({field("Кубики урона / лечения",v.dice,half,function(t) set("dice",t) end),field("Тип урона / лечение",v.damage_type,half,function(t) set("damage_type",t) end)},inner)
  rows[#rows+1]=line({numeric("Доп. бонус",v.bonus,half,function(t) set("bonus",t) end),numeric("Количество бросков",v.roll_count,half,function(t) set("roll_count",t) end)},inner)
  if v.resolution=="attack" then
   local modes=v.roll_modes or {} v.roll_modes=modes
   rows[#rows+1]=label("РЕЖИМ КАЖДОЙ АТАКИ",inner,14,"#B3A9FF")
   local count=math.min(20,math.max(tonumber(v.roll_count) or 1,#modes))
   for i=1,count do local index=i
    rows[#rows+1]=cycle("Атака "..i,modes[i] or "normal",{{"normal","Обычная"},{"advantage","Преимущество"},{"disadvantage","Помеха"}},inner,function(value)
     for n=1,index do modes[n]=modes[n] or "normal" end modes[index]=value
    end)
   end
   if count<20 then rows[#rows+1]=button("Настроить дополнительный бросок",inner,function() for n=1,count do modes[n]=modes[n] or "normal" end modes[count+1]="normal" draw() end) end
  end
  if v.resolution=="attack" then rows[#rows+1]=effectsEditor(v,inner) end
  if v.resolution=="save" then rows[#rows+1]=cycle("Спасбросок цели",v.save_ability,attrs,inner,function(t) set("save_ability",t) end) end
  if v.resolution=="save" then rows[#rows+1]=cycle("Урон при успехе",v.save_success or "rules",{{"rules","По правилам каталога"},{"none","Нет урона"},{"half","Половина, округление вниз"},{"full","Полный урон"}},inner,function(t) set("save_success",t) end) end
  if v.kind=="spell" then
   rows[#rows+1]=cycle("Круг",v.level,{{0,"Заговор"},{1,"1"},{2,"2"},{3,"3"},{4,"4"},{5,"5"},{6,"6"},{7,"7"},{8,"8"},{9,"9"}},inner,function(t) set("level",t) end)
   rows[#rows+1]=flag("Разрешено усиление ячейкой",v.upcast_allowed,inner,function(t) set("upcast_allowed",t) if not t then v.upcast_dice="" v.upcast_count=0 end end)
   rows[#rows+1]=flag("Усиление заговора на 5, 11, 17 уровнях",v.cantrip_scaling,inner,function(t) set("cantrip_scaling",t) end)
   rows[#rows+1]=line({field("Доп. кубики за ступень",v.upcast_dice,half,function(t) set("upcast_dice",t) end),numeric("Доп. броски за ступень",v.upcast_count,half,function(t) set("upcast_count",t) end)},inner)
   rows[#rows+1]=field("Длительность",v.duration,inner,function(t) set("duration",t) end)
   rows[#rows+1]=flag("Концентрация",v.concentration,inner,function(t) set("concentration",t) end)
  end
  rows[#rows+1]=flag("Добавлять бонус мастерства",v.proficient,inner,function(t) set("proficient",t) end)
  rows[#rows+1]=flag("Добавлять модификатор к урону / лечению",v.add_modifier,inner,function(t) set("add_modifier",t) end)
  rows[#rows+1]=line({field("Время применения",v.casting_time,half,function(t) set("casting_time",t) end),field("Дальность",v.range,half,function(t) set("range",t) end)},inner)
  rows[#rows+1]=field("Описание, компоненты и особые правила",v.description,inner,function(t) set("description",t) end,true)
 elseif e.kind=="stats" then
  for _,a in ipairs(attrs) do local k=a[1] rows[#rows+1]=numeric(a[2],v.abilities[k],inner,function(t) v.abilities[k]=t end) end
 elseif e.kind=="resources" then
  for _,f in ipairs({{"armor_class","Класс доспеха"},{"hp_max","Максимальные хиты"},{"hp_current","Текущие хиты"},{"hp_temp","Временные хиты"},{"speed","Скорость"},{"initiative_bonus","Бонус инициативы"},{"death_successes","Успехи спасбросков от смерти"},{"death_failures","Провалы спасбросков от смерти"}}) do
   local k=f[1] rows[#rows+1]=numeric(f[2],v[k],inner,function(t) v[k]=t end)
  end
  rows[#rows+1]=field("Бонус мастерства (пусто = по уровню)",v.proficiency_override or "",inner,function(t) if t=="" then v.proficiency_override=nil else v.proficiency_override=tonumber(t) or t end end)
  rows[#rows+1]=flag("Автоматический бонус мастерства",v.proficiency_override==nil,inner,function(t) if t then v.proficiency_override=nil else v.proficiency_override=S.data.sheet.computed.proficiency end end)
 elseif e.kind=="magic" then
  rows[#rows+1]=cycle("Заклинательная характеристика",v.spell_ability,attrs,inner,function(t) set("spell_ability",t) end)
  for n=1,9 do local key=num(n) v.slots[key]=v.slots[key] or {max=0,used=0} local cell=v.slots[key]
   rows[#rows+1]=label(num(n).." круг",inner,16,"#9085FF")
   rows[#rows+1]=line({numeric("Всего",cell.max,half,function(t) cell.max=t end),numeric("Потрачено",cell.used,half,function(t) cell.used=t end)},inner)
  end
 elseif e.kind=="notes" then
  for _,f in ipairs({{"inventory","Инвентарь"},{"notes","Заметки"},{"background","Предыстория"}}) do local k=f[1] rows[#rows+1]=field(f[2],v[k],inner,function(t) v[k]=t end,true) end
 elseif e.kind=="conditions" then
  for _,name in ipairs(conditionNames) do local item=name rows[#rows+1]=flag(item,has(v.conditions,item),inner,function() v.conditions=toggle(v.conditions,item) end) end
 end
 local save=function()
  if e.kind=="cast_effects" then
   local ids={} local marked=false
   for _,effect in ipairs(e.action.attack_effects or {}) do if e.ids[effect.id] then ids[#ids+1]=effect.id if effect.target_required then marked=true end end end
   if marked and (not e.target or e.target==0) then S.msg="Выберите цель метки" draw() return end
   S.editor=nil
   act(base..idstr(e.id).."/abilities/"..idstr(e.action.id).."/use/",{slot_level=e.level,trigger=e.trigger==true,effects=ids,effect_target=marked and e.target or nil})
  elseif e.kind=="action" then
   local body=clone(v) body.id=nil body.character=nil body.catalog_entry=nil body.active=nil
   local path=base..idstr(e.id).."/abilities/"
   if v.id then path=path..idstr(v.id).."/edit/" end
   write(path,body)
  elseif e.kind=="conditions" then
   local add,remove={},{}
   for _,item in ipairs(v.conditions or {}) do if not has(e.conditionsBefore,item) then add[#add+1]=item end end
   for _,item in ipairs(e.conditionsBefore) do if not has(v.conditions,item) then remove[#remove+1]=item end end
   write(base..idstr(e.id).."/conditions/",{add=add,remove=remove})
  else
   local body={}
   local fields={stats={"abilities"},resources={"armor_class","hp_max","hp_current","hp_temp","speed","initiative_bonus","proficiency_override","death_successes","death_failures"},magic={"slots","spell_ability"},notes={"inventory","notes","background"},conditions={"conditions"}}
   for _,key in ipairs(fields[e.kind]) do body[key]=v[key] end
   -- Lua cannot express JSON null; use a dedicated flag handled by the adapter.
   if e.kind=="resources" and v.proficiency_override==nil then body.auto_proficiency=true end
   body.version=v.version write(base..idstr(e.id).."/edit/",body)
  end
 end
 rows[#rows+1]=line({button(e.kind=="cast_effects" and "Бросить" or "Сохранить",half,save,true,S.busy or S.pendingWrite~=nil),button("Отмена",half,cancelEditor,false,S.busy)},inner)
 return {card(rows,w)}
end
actionListUI=function(kind,w,sh,height)
 S.lists=S.lists or {} S.lists[kind]=S.lists[kind] or {q="",level=-1,sort="level"}
 local f=S.lists[kind] local iw=w-40 local half=math.floor((iw-8)/2)
 local rows={label(kind=="spell" and "Быстрое сотворение" or "Атаки",iw,19)}
 local search=input(f.q,iw,function(t) f.q=t end,false,function() S.typing=false draw() end)
 rows[#rows+1]=line({search},iw)
 rows[#rows+1]=button("Найти / применить фильтры",iw,function() S.typing=false draw() end)
 if kind=="spell" then
  rows[#rows+1]=cycle("Круг",f.level,levelChoices,iw,function(t) f.level=t end)
 end
 rows[#rows+1]=cycle("Порядок",f.sort,{{"level","По кругу"},{"name","По имени"},{"-level","Старшие круги"}},iw,function(t) f.sort=t end,"sort-"..kind)
 rows[#rows+1]=line({button("Добавить",half,function() newAction(kind) end),button(kind=="spell" and "Справочник" or "Новая атака",half,function() if kind=="spell" then openCatalog() else newAction(kind) end end)},iw)
 local list={}
 for _,a in ipairs(S.data.actions or {}) do
  if a.kind==kind and (kind~="spell" or f.level<0 or a.level==f.level) and (f.q=="" or fold(a.name):find(fold(f.q),1,true)) then list[#list+1]=a end
 end
 table.sort(list,function(a,b)
  local la,lb=tonumber(a.level) or 0,tonumber(b.level) or 0
  if f.sort~="name" and la~=lb then if f.sort=="-level" then return la>lb else return la<lb end end
  return fold(a.name)<fold(b.name)
 end)
 rows[#rows+1]=label("Найдено: "..#list,iw,12,"#A0A6B2")
 for _,a in ipairs(list) do rows[#rows+1]=actionCard(a,iw,sh,true) end
 if #list==0 then rows[#rows+1]=label("Действий пока нет или фильтр не дал результатов",iw,14,"#A0A6B2") end
 return framed(rows,w,height)
end
catalogUI=function(w)
 local c=S.catalog local iw=w-24 local half=math.floor((iw-8)/2)
 local rows={label("Справочник заклинаний",iw,24),label("Та же библиотека и механика, что на сайте. Добавление одним нажатием.",iw,13,"#A0A6B2")}
 local search=input(c.q,iw,function(t) c.q=t end,false,function() c.offset=0 loadCatalog() end) rows[#rows+1]=search
 local function changed(k,v) c[k]=v c.offset=0 c.results={} c.loading=false loadCatalog() end
 rows[#rows+1]=cycle("Круг",c.level,levelChoices,iw,function(v) changed("level",v) end)
 rows[#rows+1]=cycle("Класс",c.class,classChoices,iw,function(v) changed("class",v) end)
 rows[#rows+1]=cycle("Школа",c.school,schoolChoices,iw,function(v) changed("school",v) end)
 rows[#rows+1]=button("Найти во всём справочнике",iw,function() c.offset=0 c.loading=false loadCatalog() end,true)
 rows[#rows+1]=label(c.loading and "Загрузка..." or "Найдено: "..num(c.count),iw,14,"#A0A6B2")
 for _,entry in ipairs(c.results or {}) do
  local item=entry local rules=item.rules or {}
  local parts={label(item.name_ru,iw-24,19),label(item.level==0 and "Заговор" or num(item.level).." круг",iw-24,12,"#9085FF")}
  parts[#parts+1]=button(c.open==item.id and "Скрыть описание" or "Описание заклинания",iw-24,function() if c.open==item.id then c.open=nil else c.open=item.id end draw() end)
  if c.open==item.id then parts[#parts+1]=label((rules.casting_time or "").." · "..(rules.range or "").." · "..(rules.duration or ""),iw-24,13) parts[#parts+1]=label(rules.description or "Описание отсутствует в источнике",iw-24,14) end
  local added=false for _,a in ipairs(S.data.actions or {}) do if a.catalog_entry==item.id then added=true end end
  parts[#parts+1]=button(added and "Уже добавлено" or "Добавить в лист",iw-24,function() write(base..idstr(S.id).."/catalog-add/",{spell_id=item.id}) end,true,S.busy or added)
  rows[#rows+1]=card(parts,iw)
 end
 rows[#rows+1]=line({button("Предыдущие 30",half,function() c.offset=math.max(0,c.offset-30) loadCatalog() end,false,c.offset==0 or c.loading),button("Следующие 30",half,function() c.offset=c.offset+30 loadCatalog() end,false,c.offset+30>=c.count or c.loading)},iw)
 rows[#rows+1]=button("Назад к заклинаниям",iw,function() changeTab("spell") end)
 return {card(rows,w)}
end
local function pendingUI(w)
 if not S.pendingWrite or S.busy then return nil end
 return card({label("Запрос не подтверждён",w-24,19,"#F08491"),label("При повторе используется тот же ключ запроса — без дублирования операции.",w-24,13),
  button("Повторить тот же запрос",w-24,function() sendWrite(S.pendingWrite) end,true),
  button("Отменить черновик и обновить",w-24,function() S.pendingWrite=nil S.editor=nil S.renderedData=false refresh() end)},w)
end
