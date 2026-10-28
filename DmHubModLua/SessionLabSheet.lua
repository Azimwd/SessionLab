-- ASCII source: Russian labels use Lua UTF-8 byte escapes.
local URL="https://sessionlab.up.railway.app"
local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
local previous=rawget(_G,"SLsheet")
if previous then previous.on=false if previous.window then pcall(function() previous.window:DestroySelf() end) end end
local S={on=false,run=0,tab="stats",page=1,level={},amount=5,msg="/slsheet start"}
S.pinned=previous and previous.pinned or {}
S.recent=previous and previous.recent or {}
rawset(_G,"SLsheet",S)
local base="/api/integrations/dmhub/sheets/"
local function idstr(n) return string.format("%d",tonumber(n)) end
local function normalizeSlots(sh)
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
local upper,lower="\208\144\208\145\208\146\208\147\208\148\208\149\208\129\208\150\208\151\208\152\208\153\208\154\208\155\208\156\208\157\208\158\208\159\208\160\208\161\208\162\208\163\208\164\208\165\208\166\208\167\208\168\208\169\208\170\208\171\208\172\208\173\208\174\208\175","\208\176\208\177\208\178\208\179\208\180\208\181\209\145\208\182\208\183\208\184\208\185\208\186\208\187\208\188\208\189\208\190\208\191\209\128\209\129\209\130\209\131\209\132\209\133\209\134\209\135\209\136\209\137\209\138\209\139\209\140\209\141\209\142\209\143"
for i=1,#upper,2 do s=s:gsub(upper:sub(i,i+1),lower:sub(i,i+1)) end
foldCount=foldCount+1 if foldCount>512 then foldCache={} foldCount=1 end
foldCache[original]=s
return s
end
local attrs={{"str","\208\161\208\184\208\187\208\176"},{"dex","\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140"},{"con","\208\162\208\181\208\187\208\190"},{"int","\208\152\208\189\209\130\208\181\208\187\208\187\208\181\208\186\209\130"},{"wis","\208\156\209\131\208\180\209\128\208\190\209\129\209\130\209\140"},{"cha","\208\165\208\176\209\128\208\184\208\183\208\188\208\176"}}
local skills={{"acrobatics","\208\144\208\186\209\128\208\190\208\177\208\176\209\130\208\184\208\186\208\176"},{"animal_handling","\208\150\208\184\208\178\208\190\209\130\208\189\209\139\208\181"},{"arcana","\208\156\208\176\208\179\208\184\209\143"},{"athletics","\208\144\209\130\208\187\208\181\209\130\208\184\208\186\208\176"},{"deception","\208\158\208\177\208\188\208\176\208\189"},{"history","\208\152\209\129\209\130\208\190\209\128\208\184\209\143"},{"insight","\208\159\209\128\208\190\208\189\208\184\209\134\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"},{"intimidation","\208\151\208\176\208\191\209\131\208\179\208\184\208\178\208\176\208\189\208\184\208\181"},{"investigation","\208\144\208\189\208\176\208\187\208\184\208\183"},{"medicine","\208\156\208\181\208\180\208\184\209\134\208\184\208\189\208\176"},{"nature","\208\159\209\128\208\184\209\128\208\190\208\180\208\176"},{"perception","\208\146\208\189\208\184\208\188\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"},{"performance","\208\146\209\139\209\129\209\130\209\131\208\191\208\187\208\181\208\189\208\184\208\181"},{"persuasion","\208\163\208\177\208\181\208\182\208\180\208\181\208\189\208\184\208\181"},{"religion","\208\160\208\181\208\187\208\184\208\179\208\184\209\143"},{"sleight_of_hand","\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140 \209\128\209\131\208\186"},{"stealth","\208\161\208\186\209\128\209\139\209\130\208\189\208\190\209\129\209\130\209\140"},{"survival","\208\146\209\139\208\182\208\184\208\178\208\176\208\189\208\184\208\181"}}
local function signed(n) return string.format("%+g",tonumber(n) or 0) end
local draw,refresh,startSheet,openWindow
local beginEdit,editorUI,actionListUI,write,confirmAction,catalogUI,openCatalog,actionCard,framed
local function api(path,body,done,requestKey,onError)
local run=S.run
local h={Authorization="Bearer "..TOKEN,Accept="application/json"}
local f
if body then f=net.Post else f=net.Get end
if type(f)~="function" then if body then S.busy=false end S.msg="HTTP \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189" draw() return end
local o={url=URL..path,headers=h}
local finished=false
local function active() return S.on and run==S.run and not finished end
local function fail(message)
if not active() then return end
finished=true
if not body and S.busy then return end
if body then S.busy=false end
if onError then onError() end
S.msg=tostring(message or "\208\158\209\136\208\184\208\177\208\186\208\176 \208\183\208\176\208\191\209\128\208\190\209\129\208\176"):sub(1,240) draw()
end
o.success=function(raw)
if not active() then return end
finished=true
if not body and S.busy then if onError then onError() end return end
if body then S.busy=false end
local ok,r=pcall(function() return type(raw)=="table" and raw or dmhub.FromJson(raw) end)
if ok and type(r)=="table" and type(r.data)=="table" then
local applied,err=pcall(done,r.data)
if not applied then S.msg="\208\158\209\136\208\184\208\177\208\186\208\176 \208\190\208\177\209\128\208\176\208\177\208\190\209\130\208\186\208\184: "..tostring(err):sub(1,150) draw() end
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
S.msg="\208\158\209\136\208\184\208\177\208\186\208\176 API: "..tostring(message or "\208\189\208\181\208\178\208\181\209\128\208\189\209\139\208\185 \209\132\208\190\209\128\208\188\208\176\209\130 \208\190\209\130\208\178\208\181\209\130\208\176"):sub(1,180) draw()
end
end
o.error=function(message) fail("\208\158\209\136\208\184\208\177\208\186\208\176 \208\183\208\176\208\191\209\128\208\190\209\129\208\176: "..tostring(message or "\208\191\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \209\128\208\181\208\183\209\131\208\187\209\140\209\130\208\176\209\130 \208\189\208\176 \209\129\208\176\208\185\209\130\208\181")) end
o.failure=o.error
if body then
S.busy=true S.seq=(S.seq or 0)+1
h["Content-Type"]="application/json"
h["Idempotency-Key"]=requestKey or (tostring(os.time()).."-"..S.seq.."-"..math.random(100000,999999))
o.data=body
end
local ok,e=pcall(function() f(o) end)
if not ok then fail("\208\158\209\136\208\184\208\177\208\186\208\176 \208\190\209\130\208\191\209\128\208\176\208\178\208\186\208\184: "..tostring(e)) end
end
refresh=function()
if not S.on or S.busy or S.editor or S.typing or S.pendingWrite then return end
if not S.id then
api(base,nil,function(d)
S.list=d.characters or {} S.folders=d.folders or {} S.msg="\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176" draw()
if S.list[1] then S.id=tonumber(S.list[1].id) dmhub.Schedule(0.1,refresh) else S.msg="\208\157\208\181\209\130 \208\187\208\184\209\129\209\130\208\190\208\178" draw() end
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
S.data=d S.msg="\208\155\208\184\209\129\209\130 \208\183\208\176\208\179\209\128\209\131\208\182\208\181\208\189"
if changed or not S.renderedData then S.renderedData=true draw() end
end)
end
end
local function act(path,body)
if S.busy or S.pendingWrite or S.editor then return end
S.busy=true
S.msg="\208\158\209\130\208\191\209\128\208\176\208\178\208\186\208\176..." draw()
api(path,body,function(d)
local p=d.payload or {} local parts=p.parts or {p}
local result={tostring(p.label or "\208\148\208\181\208\185\209\129\209\130\208\178\208\184\208\181")}
for i,x in ipairs(parts) do
local values={}
if x.roll then values[#values+1]="\208\145\209\128\208\190\209\129\208\190\208\186: "..string.format("%g",tonumber(x.roll.total) or 0) end
if x.save then
values[#values+1]="\208\161\208\155 "..string.format("%g",tonumber(x.save.dc) or 0)
if x.save.failed_damage~=nil then values[#values+1]="\208\159\209\128\208\190\208\178\208\176\208\187: "..string.format("%g",x.save.failed_damage).." / \208\163\209\129\208\191\208\181\209\133: "..string.format("%g",x.save.success_damage or 0) end
end
if x.damage and not (x.save and x.save.failed_damage~=nil) then values[#values+1]="\208\163\209\128\208\190\208\189 / \209\141\209\132\209\132\208\181\208\186\209\130: "..string.format("%g",tonumber(x.damage.total) or 0) end
if #values>0 then result[#result+1]=(#parts>1 and i..". " or "")..table.concat(values," \194\183 ") end
end
S.result=table.concat(result,"\n")
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
if trigger then act(base..idstr(S.id).."/abilities/"..idstr(a.id).."/use/",{trigger=true,mode=S.rollMode or "normal"}) return end
local n=selectedLevel(a,sh)
if n==nil then S.msg="\208\157\208\181\209\130 \209\129\208\178\208\190\208\177\208\190\208\180\208\189\208\190\208\185 \209\143\209\135\208\181\208\185\208\186\208\184 \208\180\208\187\209\143 \194\171"..a.name.."\194\187" draw() return end
act(base..idstr(S.id).."/abilities/"..idstr(a.id).."/use/",{slot_level=n,mode=S.rollMode or "normal"})
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
local function choose(c)
if S.editor then confirmAction("\208\158\209\130\208\188\208\181\208\189\208\184\209\130\209\140 \208\189\208\181\209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189\208\189\209\139\208\181 \208\184\208\183\208\188\208\181\208\189\208\181\208\189\208\184\209\143?",function() S.editor=nil choose(c) end) return end
local history={tonumber(c.id)}
for _,id in ipairs(S.recent) do if id~=tonumber(c.id) and #history<6 then history[#history+1]=id end end
S.recent=history
S.id=tonumber(c.id) S.data=nil S.page=1 S.open=nil S.search="" S.chooser=false S.renderedData=false S.typing=false
S.msg="\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176: "..c.name draw() dmhub.Schedule(0.1,refresh)
end
local function changeTab(t)
if S.editor then confirmAction("\208\158\209\130\208\188\208\181\208\189\208\184\209\130\209\140 \208\189\208\181\209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189\208\189\209\139\208\181 \208\184\208\183\208\188\208\181\208\189\208\181\208\189\208\184\209\143?",function() S.editor=nil changeTab(t) end) return end
S.tab=t S.page=1 S.search="" S.open=nil S.catalog=nil S.typing=false draw()
end
local function toggleAction(id)
if S.open==id then S.open=nil else S.open=id end
draw()
end
local function clearWindowReferences()
S.window=nil S.panel=nil S.leftScroll=nil S.rightScroll=nil
S.windowTitle=nil S.windowStatus=nil S.chooserHost=nil
S.typing=false S.selectOpen=nil
end
local function closeWindow()
if S.editor then confirmAction("\208\151\208\176\208\186\209\128\209\139\209\130\209\140 \208\177\208\181\208\183 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\184\209\143?",function() S.editor=nil closeWindow() end) return end
local window=S.window
clearWindowReferences()
if window then window:DestroySelf() end
end
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
S.busy=true S.msg="\208\161\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\184\208\181..." draw()
api(pending.path,pending.body,function(data)
S.pendingWrite=nil
if pending.id==S.id then
S.editor=nil S.confirm=nil S.msg="\208\161\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\190"
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
confirmAction("\208\158\209\130\208\188\208\181\208\189\208\184\209\130\209\140 \208\189\208\181\209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189\208\189\209\139\208\181 \208\184\208\183\208\188\208\181\208\189\208\181\208\189\208\184\209\143?",function() S.editor=nil S.confirm=nil S.renderedData=false refresh() draw() end)
end
beginEdit=function(kind,action)
if S.busy or S.pendingWrite then return end
if S.editor then confirmAction("\208\158\209\130\208\188\208\181\208\189\208\184\209\130\209\140 \209\130\208\181\208\186\209\131\209\137\209\131\209\142 \209\132\208\190\209\128\208\188\209\131?",function() S.editor=nil beginEdit(kind,action) end) return end
local value
if kind=="action" then
value=clone(action or {})
else value=clone(S.data.sheet) end
S.editor={kind=kind,value=value,id=S.id,conditionsBefore=clone(value.conditions or {})} S.confirm=nil draw()
end
local function newAction(kind)
beginEdit("action",{kind=kind,name="",description="",ability=kind=="spell" and S.data.sheet.spell_ability or "str",
proficient=true,bonus=0,resolution=kind=="spell" and "save" or "attack",dice="1d6",add_modifier=kind=="attack",damage_type="",
level=kind=="spell" and 1 or 0,upcast_dice="",upcast_allowed=true,roll_count=1,upcast_count=0,
cantrip_scaling=false,save_ability="dex",casting_time="1 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\181",range="",duration="",concentration=false})
end
local function archiveAction(a)
confirmAction("\208\163\208\180\208\176\208\187\208\184\209\130\209\140 \194\171"..a.name.."\194\187 \208\184\208\183 \208\187\208\184\209\129\209\130\208\176?",function()
S.confirm=nil write(base..idstr(S.id).."/abilities/"..idstr(a.id).."/edit/",{version=a.version,active=false})
end)
end
local conditionNames={"\208\158\209\129\208\187\208\181\208\191\208\187\209\145\208\189","\208\158\209\135\208\176\209\128\208\190\208\178\208\176\208\189","\208\158\208\179\208\187\208\190\209\133","\208\152\209\129\208\191\209\131\208\179\208\176\208\189","\208\161\209\133\208\178\208\176\209\135\208\181\208\189","\208\157\208\181\208\180\208\181\208\181\209\129\208\191\208\190\209\129\208\190\208\177\208\181\208\189","\208\157\208\181\208\178\208\184\208\180\208\184\208\188","\208\159\208\176\209\128\208\176\208\187\208\184\208\183\208\190\208\178\208\176\208\189","\208\158\208\186\208\176\208\188\208\181\208\189\208\181\208\187","\208\158\209\130\209\128\208\176\208\178\208\187\208\181\208\189","\208\161\208\177\208\184\209\130 \209\129 \208\189\208\190\208\179","\208\158\208\191\209\131\209\130\208\176\208\189","\208\158\209\136\208\181\208\187\208\190\208\188\208\187\209\145\208\189","\208\145\208\181\208\183 \209\129\208\190\208\183\208\189\208\176\208\189\208\184\209\143","\208\154\208\190\208\189\209\134\208\181\208\189\209\130\209\128\208\176\209\134\208\184\209\143"}
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
confirmAction("\208\146\208\190\209\129\209\129\209\130\208\176\208\189\208\190\208\178\208\184\209\130\209\140 \208\178\209\129\208\181 \209\143\209\135\208\181\208\185\208\186\208\184 \208\191\208\190\209\129\208\187\208\181 \208\190\209\130\208\180\209\139\209\133\208\176?",function()
S.confirm=nil write(base..idstr(S.id).."/resources/",{action="restore_slots",version=S.data.sheet.version})
end)
end
local classChoices={{"","\208\146\209\129\208\181 \208\186\208\187\208\176\209\129\209\129\209\139"},{"Bard","\208\145\208\176\209\128\208\180"},{"Cleric","\208\150\209\128\208\181\209\134"},{"Druid","\208\148\209\128\209\131\208\184\208\180"},{"Paladin","\208\159\208\176\208\187\208\176\208\180\208\184\208\189"},{"Ranger","\208\161\208\187\208\181\208\180\208\190\208\191\209\139\209\130"},{"Sorcerer","\208\167\208\176\209\128\208\190\208\180\208\181\208\185"},{"Warlock","\208\154\208\190\208\187\208\180\209\131\208\189"},{"Wizard","\208\146\208\190\208\187\209\136\208\181\208\177\208\189\208\184\208\186"}}
local schoolChoices={{"","\208\146\209\129\208\181 \209\136\208\186\208\190\208\187\209\139"},{"abjuration","\208\158\208\179\209\128\208\176\208\182\208\180\208\181\208\189\208\184\208\181"},{"conjuration","\208\146\209\139\208\183\208\190\208\178"},{"divination","\208\159\209\128\208\190\209\128\208\184\209\134\208\176\208\189\208\184\208\181"},{"enchantment","\208\158\209\135\208\176\209\128\208\190\208\178\208\176\208\189\208\184\208\181"},{"evocation","\208\146\208\190\208\191\208\187\208\190\209\137\208\181\208\189\208\184\208\181"},{"illusion","\208\152\208\187\208\187\209\142\208\183\208\184\209\143"},{"necromancy","\208\157\208\181\208\186\209\128\208\190\208\188\208\176\208\189\209\130\208\184\209\143"},{"transmutation","\208\159\209\128\208\181\208\190\208\177\209\128\208\176\208\183\208\190\208\178\208\176\208\189\208\184\208\181"}}
local levelChoices={{-1,"\208\146\209\129\208\181 \208\186\209\128\209\131\208\179\208\184"},{0,"\208\151\208\176\208\179\208\190\208\178\208\190\209\128\209\139"}}
for n=1,9 do levelChoices[#levelChoices+1]={n,num(n).." \208\186\209\128\209\131\208\179"} end
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
editorUI=function(w)
local e=S.editor if not e then return {} end
local v=e.value local inner=w-24 local half=math.floor((inner-8)/2)
local rows={label(e.kind=="action" and (v.id and "\208\160\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\209\130\209\140 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\181" or "\208\157\208\190\208\178\208\190\208\181 \208\180\208\181\208\185\209\129\209\130\208\178\208\184\208\181") or "\208\160\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\208\189\208\184\208\181 \208\187\208\184\209\129\209\130\208\176",inner,23),
label("\208\152\208\183\208\188\208\181\208\189\208\181\208\189\208\184\209\143 \209\129\208\190\209\133\209\128\208\176\208\189\209\143\209\142\209\130\209\129\209\143 \208\189\208\176 \209\129\208\176\208\185\209\130. \208\159\208\190\208\186\208\176 \209\132\208\190\209\128\208\188\208\176 \208\190\209\130\208\186\209\128\209\139\209\130\208\176, \208\176\208\178\209\130\208\190\208\190\208\177\208\189\208\190\208\178\208\187\208\181\208\189\208\184\208\181 \208\191\209\128\208\184\208\190\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\190.",inner,12,"#A0A6B2")}
local function set(k,val) v[k]=val end
if e.kind=="action" then
rows[#rows+1]=field("\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181",v.name,inner,function(t) set("name",t) end)
rows[#rows+1]=cycle("\208\165\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\176",v.ability,attrs,inner,function(t) set("ability",t) end)
rows[#rows+1]=cycle("\208\159\209\128\208\184\208\188\208\181\208\189\208\181\208\189\208\184\208\181",v.resolution,{{"attack","\208\145\209\128\208\190\209\129\208\190\208\186 \208\176\209\130\208\176\208\186\208\184"},{"save","\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \209\134\208\181\208\187\208\184"},{"automatic","\208\144\208\178\209\130\208\190\208\188\208\176\209\130\208\184\209\135\208\181\209\129\208\186\208\184"}},inner,function(t) set("resolution",t) end)
rows[#rows+1]=line({field("\208\154\209\131\208\177\208\184\208\186\208\184 \209\131\209\128\208\190\208\189\208\176 / \208\187\208\181\209\135\208\181\208\189\208\184\209\143",v.dice,half,function(t) set("dice",t) end),field("\208\162\208\184\208\191 \209\131\209\128\208\190\208\189\208\176 / \208\187\208\181\209\135\208\181\208\189\208\184\208\181",v.damage_type,half,function(t) set("damage_type",t) end)},inner)
rows[#rows+1]=line({numeric("\208\148\208\190\208\191. \208\177\208\190\208\189\209\131\209\129",v.bonus,half,function(t) set("bonus",t) end),numeric("\208\154\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \208\177\209\128\208\190\209\129\208\186\208\190\208\178",v.roll_count,half,function(t) set("roll_count",t) end)},inner)
if v.resolution=="save" then rows[#rows+1]=cycle("\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \209\134\208\181\208\187\208\184",v.save_ability,attrs,inner,function(t) set("save_ability",t) end) end
if v.kind=="spell" then
rows[#rows+1]=cycle("\208\154\209\128\209\131\208\179",v.level,{{0,"\208\151\208\176\208\179\208\190\208\178\208\190\209\128"},{1,"1"},{2,"2"},{3,"3"},{4,"4"},{5,"5"},{6,"6"},{7,"7"},{8,"8"},{9,"9"}},inner,function(t) set("level",t) end)
rows[#rows+1]=flag("\208\160\208\176\208\183\209\128\208\181\209\136\208\181\208\189\208\190 \209\131\209\129\208\184\208\187\208\181\208\189\208\184\208\181 \209\143\209\135\208\181\208\185\208\186\208\190\208\185",v.upcast_allowed,inner,function(t) set("upcast_allowed",t) if not t then v.upcast_dice="" v.upcast_count=0 end end)
rows[#rows+1]=flag("\208\163\209\129\208\184\208\187\208\181\208\189\208\184\208\181 \208\183\208\176\208\179\208\190\208\178\208\190\209\128\208\176 \208\189\208\176 5, 11, 17 \209\131\209\128\208\190\208\178\208\189\209\143\209\133",v.cantrip_scaling,inner,function(t) set("cantrip_scaling",t) end)
rows[#rows+1]=line({field("\208\148\208\190\208\191. \208\186\209\131\208\177\208\184\208\186\208\184 \208\183\208\176 \209\129\209\130\209\131\208\191\208\181\208\189\209\140",v.upcast_dice,half,function(t) set("upcast_dice",t) end),numeric("\208\148\208\190\208\191. \208\177\209\128\208\190\209\129\208\186\208\184 \208\183\208\176 \209\129\209\130\209\131\208\191\208\181\208\189\209\140",v.upcast_count,half,function(t) set("upcast_count",t) end)},inner)
rows[#rows+1]=field("\208\148\208\187\208\184\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140",v.duration,inner,function(t) set("duration",t) end)
rows[#rows+1]=flag("\208\154\208\190\208\189\209\134\208\181\208\189\209\130\209\128\208\176\209\134\208\184\209\143",v.concentration,inner,function(t) set("concentration",t) end)
end
rows[#rows+1]=flag("\208\148\208\190\208\177\208\176\208\178\208\187\209\143\209\130\209\140 \208\177\208\190\208\189\209\131\209\129 \208\188\208\176\209\129\209\130\208\181\209\128\209\129\209\130\208\178\208\176",v.proficient,inner,function(t) set("proficient",t) end)
rows[#rows+1]=flag("\208\148\208\190\208\177\208\176\208\178\208\187\209\143\209\130\209\140 \208\188\208\190\208\180\208\184\209\132\208\184\208\186\208\176\209\130\208\190\209\128 \208\186 \209\131\209\128\208\190\208\189\209\131 / \208\187\208\181\209\135\208\181\208\189\208\184\209\142",v.add_modifier,inner,function(t) set("add_modifier",t) end)
rows[#rows+1]=line({field("\208\146\209\128\208\181\208\188\209\143 \208\191\209\128\208\184\208\188\208\181\208\189\208\181\208\189\208\184\209\143",v.casting_time,half,function(t) set("casting_time",t) end),field("\208\148\208\176\208\187\209\140\208\189\208\190\209\129\209\130\209\140",v.range,half,function(t) set("range",t) end)},inner)
rows[#rows+1]=field("\208\158\208\191\208\184\209\129\208\176\208\189\208\184\208\181, \208\186\208\190\208\188\208\191\208\190\208\189\208\181\208\189\209\130\209\139 \208\184 \208\190\209\129\208\190\208\177\209\139\208\181 \208\191\209\128\208\176\208\178\208\184\208\187\208\176",v.description,inner,function(t) set("description",t) end,true)
elseif e.kind=="stats" then
for _,a in ipairs(attrs) do local k=a[1] rows[#rows+1]=numeric(a[2],v.abilities[k],inner,function(t) v.abilities[k]=t end) end
elseif e.kind=="resources" then
for _,f in ipairs({{"armor_class","\208\154\208\187\208\176\209\129\209\129 \208\180\208\190\209\129\208\191\208\181\209\133\208\176"},{"hp_max","\208\156\208\176\208\186\209\129\208\184\208\188\208\176\208\187\209\140\208\189\209\139\208\181 \209\133\208\184\209\130\209\139"},{"hp_current","\208\162\208\181\208\186\209\131\209\137\208\184\208\181 \209\133\208\184\209\130\209\139"},{"hp_temp","\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \209\133\208\184\209\130\209\139"},{"speed","\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140"},{"initiative_bonus","\208\145\208\190\208\189\209\131\209\129 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\139"},{"death_successes","\208\163\209\129\208\191\208\181\209\133\208\184 \209\129\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\190\208\178 \208\190\209\130 \209\129\208\188\208\181\209\128\209\130\208\184"},{"death_failures","\208\159\209\128\208\190\208\178\208\176\208\187\209\139 \209\129\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\190\208\178 \208\190\209\130 \209\129\208\188\208\181\209\128\209\130\208\184"}}) do
local k=f[1] rows[#rows+1]=numeric(f[2],v[k],inner,function(t) v[k]=t end)
end
rows[#rows+1]=field("\208\145\208\190\208\189\209\131\209\129 \208\188\208\176\209\129\209\130\208\181\209\128\209\129\209\130\208\178\208\176 (\208\191\209\131\209\129\209\130\208\190 = \208\191\208\190 \209\131\209\128\208\190\208\178\208\189\209\142)",v.proficiency_override or "",inner,function(t) if t=="" then v.proficiency_override=nil else v.proficiency_override=tonumber(t) or t end end)
rows[#rows+1]=flag("\208\144\208\178\209\130\208\190\208\188\208\176\209\130\208\184\209\135\208\181\209\129\208\186\208\184\208\185 \208\177\208\190\208\189\209\131\209\129 \208\188\208\176\209\129\209\130\208\181\209\128\209\129\209\130\208\178\208\176",v.proficiency_override==nil,inner,function(t) if t then v.proficiency_override=nil else v.proficiency_override=S.data.sheet.computed.proficiency end end)
elseif e.kind=="magic" then
rows[#rows+1]=cycle("\208\151\208\176\208\186\208\187\208\184\208\189\208\176\209\130\208\181\208\187\209\140\208\189\208\176\209\143 \209\133\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\176",v.spell_ability,attrs,inner,function(t) set("spell_ability",t) end)
for n=1,9 do local key=num(n) v.slots[key]=v.slots[key] or {max=0,used=0} local cell=v.slots[key]
rows[#rows+1]=label(num(n).." \208\186\209\128\209\131\208\179",inner,16,"#9085FF")
rows[#rows+1]=line({numeric("\208\146\209\129\208\181\208\179\208\190",cell.max,half,function(t) cell.max=t end),numeric("\208\159\208\190\209\130\209\128\208\176\209\135\208\181\208\189\208\190",cell.used,half,function(t) cell.used=t end)},inner)
end
elseif e.kind=="notes" then
for _,f in ipairs({{"inventory","\208\152\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140"},{"notes","\208\151\208\176\208\188\208\181\209\130\208\186\208\184"},{"background","\208\159\209\128\208\181\208\180\209\139\209\129\209\130\208\190\209\128\208\184\209\143"}}) do local k=f[1] rows[#rows+1]=field(f[2],v[k],inner,function(t) v[k]=t end,true) end
elseif e.kind=="conditions" then
for _,name in ipairs(conditionNames) do local item=name rows[#rows+1]=flag(item,has(v.conditions,item),inner,function() v.conditions=toggle(v.conditions,item) end) end
end
local save=function()
if e.kind=="action" then
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
if e.kind=="resources" and v.proficiency_override==nil then body.auto_proficiency=true end
body.version=v.version write(base..idstr(e.id).."/edit/",body)
end
end
rows[#rows+1]=line({button("\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140",half,save,true,S.busy or S.pendingWrite~=nil),button("\208\158\209\130\208\188\208\181\208\189\208\176",half,cancelEditor,false,S.busy)},inner)
return {card(rows,w)}
end
actionListUI=function(kind,w,sh,height)
S.lists=S.lists or {} S.lists[kind]=S.lists[kind] or {q="",level=-1,sort="level"}
local f=S.lists[kind] local iw=w-40 local half=math.floor((iw-8)/2)
local rows={label(kind=="spell" and "\208\145\209\139\209\129\209\130\209\128\208\190\208\181 \209\129\208\190\209\130\208\178\208\190\209\128\208\181\208\189\208\184\208\181" or "\208\144\209\130\208\176\208\186\208\184",iw,19)}
local search=input(f.q,iw,function(t) f.q=t end,false,function() S.typing=false draw() end)
rows[#rows+1]=line({search},iw)
rows[#rows+1]=button("\208\157\208\176\208\185\209\130\208\184 / \208\191\209\128\208\184\208\188\208\181\208\189\208\184\209\130\209\140 \209\132\208\184\208\187\209\140\209\130\209\128\209\139",iw,function() S.typing=false draw() end)
if kind=="spell" then
rows[#rows+1]=cycle("\208\154\209\128\209\131\208\179",f.level,levelChoices,iw,function(t) f.level=t end)
end
rows[#rows+1]=cycle("\208\159\208\190\209\128\209\143\208\180\208\190\208\186",f.sort,{{"level","\208\159\208\190 \208\186\209\128\209\131\208\179\209\131"},{"name","\208\159\208\190 \208\184\208\188\208\181\208\189\208\184"},{"-level","\208\161\209\130\208\176\209\128\209\136\208\184\208\181 \208\186\209\128\209\131\208\179\208\184"}},iw,function(t) f.sort=t end,"sort-"..kind)
rows[#rows+1]=line({button("\208\148\208\190\208\177\208\176\208\178\208\184\209\130\209\140",half,function() newAction(kind) end),button(kind=="spell" and "\208\161\208\191\209\128\208\176\208\178\208\190\209\135\208\189\208\184\208\186" or "\208\157\208\190\208\178\208\176\209\143 \208\176\209\130\208\176\208\186\208\176",half,function() if kind=="spell" then openCatalog() else newAction(kind) end end)},iw)
local list={}
for _,a in ipairs(S.data.actions or {}) do
if a.kind==kind and (kind~="spell" or f.level<0 or a.level==f.level) and (f.q=="" or fold(a.name):find(fold(f.q),1,true)) then list[#list+1]=a end
end
table.sort(list,function(a,b)
local la,lb=tonumber(a.level) or 0,tonumber(b.level) or 0
if f.sort~="name" and la~=lb then if f.sort=="-level" then return la>lb else return la<lb end end
return fold(a.name)<fold(b.name)
end)
rows[#rows+1]=label("\208\157\208\176\208\185\208\180\208\181\208\189\208\190: "..#list,iw,12,"#A0A6B2")
for _,a in ipairs(list) do rows[#rows+1]=actionCard(a,iw,sh,true) end
if #list==0 then rows[#rows+1]=label("\208\148\208\181\208\185\209\129\209\130\208\178\208\184\208\185 \208\191\208\190\208\186\208\176 \208\189\208\181\209\130 \208\184\208\187\208\184 \209\132\208\184\208\187\209\140\209\130\209\128 \208\189\208\181 \208\180\208\176\208\187 \209\128\208\181\208\183\209\131\208\187\209\140\209\130\208\176\209\130\208\190\208\178",iw,14,"#A0A6B2") end
return framed(rows,w,height)
end
catalogUI=function(w)
local c=S.catalog local iw=w-24 local half=math.floor((iw-8)/2)
local rows={label("\208\161\208\191\209\128\208\176\208\178\208\190\209\135\208\189\208\184\208\186 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\208\185",iw,24),label("\208\162\208\176 \208\182\208\181 \208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\208\176 \208\184 \208\188\208\181\209\133\208\176\208\189\208\184\208\186\208\176, \209\135\209\130\208\190 \208\189\208\176 \209\129\208\176\208\185\209\130\208\181. \208\148\208\190\208\177\208\176\208\178\208\187\208\181\208\189\208\184\208\181 \208\190\208\180\208\189\208\184\208\188 \208\189\208\176\208\182\208\176\209\130\208\184\208\181\208\188.",iw,13,"#A0A6B2")}
local search=input(c.q,iw,function(t) c.q=t end,false,function() c.offset=0 loadCatalog() end) rows[#rows+1]=search
local function changed(k,v) c[k]=v c.offset=0 c.results={} c.loading=false loadCatalog() end
rows[#rows+1]=cycle("\208\154\209\128\209\131\208\179",c.level,levelChoices,iw,function(v) changed("level",v) end)
rows[#rows+1]=cycle("\208\154\208\187\208\176\209\129\209\129",c.class,classChoices,iw,function(v) changed("class",v) end)
rows[#rows+1]=cycle("\208\168\208\186\208\190\208\187\208\176",c.school,schoolChoices,iw,function(v) changed("school",v) end)
rows[#rows+1]=button("\208\157\208\176\208\185\209\130\208\184 \208\178\208\190 \208\178\209\129\209\145\208\188 \209\129\208\191\209\128\208\176\208\178\208\190\209\135\208\189\208\184\208\186\208\181",iw,function() c.offset=0 c.loading=false loadCatalog() end,true)
rows[#rows+1]=label(c.loading and "\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176..." or "\208\157\208\176\208\185\208\180\208\181\208\189\208\190: "..num(c.count),iw,14,"#A0A6B2")
for _,entry in ipairs(c.results or {}) do
local item=entry local rules=item.rules or {}
local parts={label(item.name_ru,iw-24,19),label(item.level==0 and "\208\151\208\176\208\179\208\190\208\178\208\190\209\128" or num(item.level).." \208\186\209\128\209\131\208\179",iw-24,12,"#9085FF")}
parts[#parts+1]=button(c.open==item.id and "\208\161\208\186\209\128\209\139\209\130\209\140 \208\190\208\191\208\184\209\129\208\176\208\189\208\184\208\181" or "\208\158\208\191\208\184\209\129\208\176\208\189\208\184\208\181 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143",iw-24,function() if c.open==item.id then c.open=nil else c.open=item.id end draw() end)
if c.open==item.id then parts[#parts+1]=label((rules.casting_time or "").." \194\183 "..(rules.range or "").." \194\183 "..(rules.duration or ""),iw-24,13) parts[#parts+1]=label(rules.description or "\208\158\208\191\208\184\209\129\208\176\208\189\208\184\208\181 \208\190\209\130\209\129\209\131\209\130\209\129\209\130\208\178\209\131\208\181\209\130 \208\178 \208\184\209\129\209\130\208\190\209\135\208\189\208\184\208\186\208\181",iw-24,14) end
local added=false for _,a in ipairs(S.data.actions or {}) do if a.catalog_entry==item.id then added=true end end
parts[#parts+1]=button(added and "\208\163\208\182\208\181 \208\180\208\190\208\177\208\176\208\178\208\187\208\181\208\189\208\190" or "\208\148\208\190\208\177\208\176\208\178\208\184\209\130\209\140 \208\178 \208\187\208\184\209\129\209\130",iw-24,function() write(base..idstr(S.id).."/catalog-add/",{spell_id=item.id}) end,true,S.busy or added)
rows[#rows+1]=card(parts,iw)
end
rows[#rows+1]=line({button("\208\159\209\128\208\181\208\180\209\139\208\180\209\131\209\137\208\184\208\181 30",half,function() c.offset=math.max(0,c.offset-30) loadCatalog() end,false,c.offset==0 or c.loading),button("\208\161\208\187\208\181\208\180\209\131\209\142\209\137\208\184\208\181 30",half,function() c.offset=c.offset+30 loadCatalog() end,false,c.offset+30>=c.count or c.loading)},iw)
rows[#rows+1]=button("\208\157\208\176\208\183\208\176\208\180 \208\186 \208\183\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143\208\188",iw,function() changeTab("spell") end)
return {card(rows,w)}
end
local function pendingUI(w)
if not S.pendingWrite or S.busy then return nil end
return card({label("\208\151\208\176\208\191\209\128\208\190\209\129 \208\189\208\181 \208\191\208\190\208\180\209\130\208\178\208\181\209\128\208\182\208\180\209\145\208\189",w-24,19,"#F08491"),label("\208\159\209\128\208\184 \208\191\208\190\208\178\209\130\208\190\209\128\208\181 \208\184\209\129\208\191\208\190\208\187\209\140\208\183\209\131\208\181\209\130\209\129\209\143 \209\130\208\190\209\130 \208\182\208\181 \208\186\208\187\209\142\209\135 \208\183\208\176\208\191\209\128\208\190\209\129\208\176 \226\128\148 \208\177\208\181\208\183 \208\180\209\131\208\177\208\187\208\184\209\128\208\190\208\178\208\176\208\189\208\184\209\143 \208\190\208\191\208\181\209\128\208\176\209\134\208\184\208\184.",w-24,13),
button("\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \209\130\208\190\209\130 \208\182\208\181 \208\183\208\176\208\191\209\128\208\190\209\129",w-24,function() sendWrite(S.pendingWrite) end,true),
button("\208\158\209\130\208\188\208\181\208\189\208\184\209\130\209\140 \209\135\208\181\209\128\208\189\208\190\208\178\208\184\208\186 \208\184 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\209\140",w-24,function() S.pendingWrite=nil S.editor=nil S.renderedData=false refresh() end)},w)
end
actionCard=function(a,w,sh,compact)
local inner=w-24
local parts={label(a.name,inner,18),label(a.kind=="spell" and (a.level==0 and "\208\151\208\176\208\179\208\190\208\178\208\190\209\128" or num(a.level).." \208\186\209\128\209\131\208\179") or "\208\158\209\128\209\131\208\182\208\184\208\181 \208\184 \208\191\209\128\208\184\209\145\208\188\209\139",inner,12,"#9085FF")}
local half=math.floor((inner-8)/2)
local available=selectedLevel(a,sh)~=nil
parts[#parts+1]=line({button(S.open==a.id and "\208\161\208\186\209\128\209\139\209\130\209\140" or "\208\159\208\190\208\180\209\128\208\190\208\177\208\189\208\181\208\181",half,function() toggleAction(a.id) end),button(a.kind=="spell" and "\208\161\208\190\209\130\208\178\208\190\209\128\208\184\209\130\209\140" or "\208\144\209\130\208\176\208\186\208\190\208\178\208\176\209\130\209\140",half,function() cast(a,sh) end,true,S.busy or not available)},inner)
if a.kind=="spell" and a.level>0 then
local levels=spellLevels(a,sh)
if #levels>0 then
local selected=selectedLevel(a,sh)
local remaining=slot(sh,selected)
local function caption(n) local v=slot(sh,n) return "\208\175\209\135\208\181\208\185\208\186\208\176 "..num(n).." \194\183 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 "..num(v.max-v.used) end
local slotButton
slotButton=button(caption(selected),inner,function()
local current=S.level[a.id] or selected
for j,n in ipairs(levels) do if n==current then S.level[a.id]=levels[j%#levels+1] break end end
slotButton.text=caption(S.level[a.id])
end)
parts[#parts+1]=slotButton
else parts[#parts+1]=label("\208\157\208\181\209\130 \209\129\208\178\208\190\208\177\208\190\208\180\208\189\209\139\209\133 \209\143\209\135\208\181\208\181\208\186",inner,12,"#F08491") end
end
if S.open==a.id then parts[#parts+1]=label((a.casting_time or "").." \194\183 "..(a.range or "").." \194\183 "..(a.duration or ""),inner,12,"#A0A6B2") parts[#parts+1]=label(a.description,inner,14) end
parts[#parts+1]=line({button("\208\152\208\183\208\188\208\181\208\189\208\184\209\130\209\140",half,function() beginEdit("action",a) end,false,S.busy),button("\208\163\208\180\208\176\208\187\208\184\209\130\209\140",half,function() archiveAction(a) end,false,S.busy)},inner)
if a.rules_recurring then parts[#parts+1]=button("\208\145\209\128\208\190\209\129\208\184\209\130\209\140 \208\191\208\190\208\178\209\130\208\190\209\128\208\189\209\139\208\185 \209\141\209\132\209\132\208\181\208\186\209\130",inner,function() cast(a,sh,true) end,false,S.busy) end
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
local current=valid and d.character.name or "\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176"
left[#left+1]=button(current.."  \226\128\186",L,function()
S.chooser=not S.chooser draw(true)
if S.chooser then api(base,nil,function(data) S.list=data.characters or {} S.folders=data.folders or {} draw(true) end) end
end)
local function folderName(c)
for _,f in ipairs(S.folders or {}) do if tonumber(f.id)==tonumber(c.folder) then return f.name end end
return "\208\145\208\181\208\183 \208\191\208\176\208\191\208\186\208\184"
end
local byId={} for _,c in ipairs(S.list or {}) do byId[tonumber(c.id)]=c end
if valid then
left[#left+1]=label(folderName(d.character),L,12,"#A0A6B2")
left[#left+1]=button(S.pinned[S.id] and "\208\163\208\177\209\128\208\176\209\130\209\140 \208\184\208\183 \208\177\209\139\209\129\209\130\209\128\208\190\208\179\208\190 \208\180\208\190\209\129\209\130\209\131\208\191\208\176" or "\208\151\208\176\208\186\209\128\208\181\208\191\208\184\209\130\209\140 \208\180\208\187\209\143 \208\177\208\190\209\143",L,function()
S.pinned[S.id]=not S.pinned[S.id] draw(true)
end)
end
local function shortcut(c)
return button((tonumber(c.id)==S.id and "\226\128\162 " or "")..c.name.." \194\183 "..folderName(c),L,function() choose(c) end,tonumber(c.id)==S.id)
end
local pins={}
for _,c in ipairs(S.list or {}) do if S.pinned[tonumber(c.id)] then pins[#pins+1]=c end end
if #pins>0 then
left[#left+1]=label("\208\145\208\171\208\161\208\162\208\160\208\171\208\153 \208\148\208\158\208\161\208\162\208\163\208\159",L,11,"#9085FF")
for _,c in ipairs(pins) do left[#left+1]=shortcut(c) end
end
local recent={}
for _,id in ipairs(S.recent) do if byId[id] and not S.pinned[id] and id~=S.id then recent[#recent+1]=byId[id] end end
if #recent>0 then
left[#left+1]=label("\208\157\208\149\208\148\208\144\208\146\208\157\208\152\208\149 \208\155\208\152\208\161\208\162\208\171",L,11,"#A0A6B2")
for _,c in ipairs(recent) do left[#left+1]=shortcut(c) end
end
if S.chooser or not valid then
S.folderOpen=S.folderOpen or {}
local groups={}
for _,f in ipairs(S.folders or {}) do groups[#groups+1]={id=tonumber(f.id),name=f.name,characters={}} end
groups[#groups+1]={id=0,name="\208\145\208\181\208\183 \208\191\208\176\208\191\208\186\208\184",characters={}}
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
if #items==0 then items[1]=label("\208\157\208\184\209\135\208\181\208\179\208\190 \208\189\208\181 \208\189\208\176\208\185\208\180\208\181\208\189\208\190",L,12,"#A0A6B2") end
host.children=items return
end
for _,g in ipairs(groups) do
local group=g
items[#items+1]=button((S.folderOpen[g.id] and "- " or "+ ")..g.name.." \194\183 "..#g.characters,L,function() S.folderOpen[group.id]=not S.folderOpen[group.id] renderChooser() end)
if S.folderOpen[g.id] then
for _,c in ipairs(g.characters) do local character=c items[#items+1]=button(c.name,L,function() choose(character) end,tonumber(c.id)==S.id) end
if #g.characters==0 then items[#items+1]=label("\208\157\208\181\209\130 \208\187\208\184\209\129\209\130\208\190\208\178",L,12,"#A0A6B2") end
end
end
host.children=items
end
left[#left+1]=gui.Input{text=S.characterQuery or "",placeholderText="\208\159\208\190\208\184\209\129\208\186 \208\191\208\190 \208\184\208\188\208\181\208\189\208\184 \208\184\208\187\208\184 \208\191\208\176\208\191\208\186\208\181",width=L,height=34,fontSize=13,classes={"slinput"},
edit=function(e) S.characterQuery=e.text or "" renderChooser() end,
change=function(e) S.characterQuery=e.text or "" renderChooser() end}
renderChooser() left[#left+1]=host
end
if valid then
local sh=d.sheet local cs=sh.computed or {}
local attributes={label("\208\165\208\144\208\160\208\144\208\154\208\162\208\149\208\160\208\152\208\161\208\162\208\152\208\154\208\152",LI,11,"#A0A6B2")}
local half=math.floor((LI-8)/2)
for i=1,#attrs,2 do
local cells={}
for j=i,i+1 do local a=attrs[j] local k=a[1]
cells[#cells+1]=card({label(a[2],half-24,11,"#A0A6B2"),label(signed((cs.modifiers or {})[k]),half-24,25,"#9085FF"),button(num((sh.abilities or {})[k] or 10),half-24,function() beginEdit("stats") end),button("\208\145\209\128\208\190\209\129\208\190\208\186",half-24,function() roll("ability",k) end)},half)
end
attributes[#attributes+1]=line(cells,LI)
end
left[#left+1]=card(attributes,L)
local saves={label("\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\186\208\184",LI,16)}
for _,a in ipairs(attrs) do local k=a[1] saves[#saves+1]=line({button(has(sh.saves,k) and "\208\146\208\187." or "\226\128\148",40,function() quickSave(k) end,false,S.busy or S.pendingWrite~=nil),button(a[2].."  "..signed((cs.saves or {})[k]),LI-48,function() roll("save",k) end)},LI) end
left[#left+1]=card(saves,L)
local skillRows={label("\208\157\208\176\208\178\209\139\208\186\208\184",LI,16)}
for _,a in ipairs(skills) do local k=a[1] local prof=tonumber((sh.skills or {})[k]) or 0
skillRows[#skillRows+1]=line({button(({"\226\128\148","\208\146\208\187.","\208\156\209\129\209\130."})[prof+1],40,function() quickSkill(k) end,false,S.busy or S.pendingWrite~=nil),button(a[2].."  "..signed((cs.skills or {})[k]),LI-48,function() roll("skill",k) end)},LI)
end
left[#left+1]=card(skillRows,L)
left[#left+1]=cycle("\208\145\209\128\208\190\209\129\208\186\208\184",S.rollMode or "normal",{{"normal","\208\158\208\177\209\139\209\135\208\189\209\139\208\185"},{"advantage","\208\159\209\128\208\181\208\184\208\188\209\131\209\137\208\181\209\129\209\130\208\178\208\190"},{"disadvantage","\208\159\208\190\208\188\208\181\209\133\208\176"}},L,function(v) S.rollMode=v end)
left[#left+1]=button("\208\161\208\191\208\176\209\129\208\177\209\128\208\190\209\129\208\190\208\186 \208\190\209\130 \209\129\208\188\208\181\209\128\209\130\208\184",L,function() roll("death","") end)
if leftOnly and not P.narrow and S.leftScroll then
S.leftScroll.children={column(left,L)}
return
end
local hp,maxhp=tonumber(sh.hp_current) or 0,tonumber(sh.hp_max) or 1
local health={label("\208\151\208\148\208\158\208\160\208\158\208\146\208\172\208\149 \208\159\208\149\208\160\208\161\208\158\208\157\208\144\208\150\208\144",RI,11,"#A0A6B2"),label("\208\165\208\184\209\130\209\139  "..num(hp).." / "..num(maxhp),RI,26),label("\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \209\133\208\184\209\130\209\139: "..num(sh.hp_temp),RI,12,"#45CBA6")}
health[#health+1]=gui.Panel{width=RI,height=6,hmargin=0,vmargin=4,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#303642ff",children={gui.Panel{width=math.floor(RI*math.max(0,math.min(1,hp/math.max(1,maxhp)))),height=6,halign="left",bgimage="panels/square.png",bgcolor="#45CBA6ff"}}}
local amount=gui.Input{text=num(S.amount),width=72,height=34,fontSize=15,hmargin=0,vmargin=3,hpad=0,vpad=0,classes={"slinput"},change=function(e) S.amount=math.max(0,math.min(10000,math.floor(tonumber(e.text) or 0))) end}
local resourceWidth=math.floor((RI-72-24)/3)
local resourceButtons={}
for _,v in ipairs({{"damage","\208\163\209\128\208\190\208\189"},{"heal","\208\155\208\181\209\135\208\181\208\189\208\184\208\181"},{"temporary","\208\146\209\128\208\181\208\188. \209\133\208\184\209\130\209\139"}}) do
local kind=v[1]
resourceButtons[#resourceButtons+1]=button(v[2],P.narrow and math.floor((RI-16)/3) or resourceWidth,function() act(base..idstr(S.id).."/resources/",{action=kind,amount=S.amount}) end,false,S.busy)
end
if P.narrow then
health[#health+1]=line({label("\208\154\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190",RI-80,14,"#A0A6B2"),amount},RI)
health[#health+1]=line(resourceButtons,RI)
else health[#health+1]=line({amount,resourceButtons[1],resourceButtons[2],resourceButtons[3]},RI) end
right[#right+1]=card(health,R)
right[#right+1]=button("\208\160\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\209\130\209\140 \208\177\208\190\208\181\208\178\209\139\208\181 \209\128\208\181\209\129\209\131\209\128\209\129\209\139",R,function() beginEdit("resources") end,false,S.busy)
local tabs={} local tabWidth=math.floor((R-32)/5)
for _,v in ipairs({{"stats","\208\158\208\177\208\183\208\190\209\128"},{"skills","\208\157\208\176\208\178\209\139\208\186\208\184"},{"attack","\208\144\209\130\208\176\208\186\208\184"},{"spell","\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143"},{"notes","\208\151\208\176\208\191\208\184\209\129\208\184"}}) do local tab=v[1] tabs[#tabs+1]=button(v[2],tabWidth,function() changeTab(tab) end,S.tab==tab) end
if P.narrow then
local rows,cells={},{} local smallWidth=math.floor((R-16)/3)
for i,v in ipairs({{"stats","\208\158\208\177\208\183\208\190\209\128"},{"skills","\208\157\208\176\208\178\209\139\208\186\208\184"},{"attack","\208\144\209\130\208\176\208\186\208\184"},{"spell","\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143"},{"notes","\208\151\208\176\208\191\208\184\209\129\208\184"}}) do
local t=v[1] cells[#cells+1]=button(v[2],smallWidth,function() changeTab(t) end,S.tab==t)
if #cells==3 or i==5 then rows[#rows+1]=line(cells,R) cells={} end
end
right[#right+1]=column(rows,R)
else right[#right+1]=line(tabs,R) end
if S.result then right[#right+1]=card({label("\208\159\208\158\208\161\208\155\208\149\208\148\208\157\208\149\208\149 \208\148\208\149\208\153\208\161\208\162\208\146\208\152\208\149",RI,11,"#A0A6B2"),label(S.result,RI,20,"#9085FF")},R) end
local pair=P.narrow and R or math.floor((R-12)/2) local PI=pair-24
local function two(items) return P.narrow and column(items,R) or line(items,R,12) end
if S.editor then
right=editorUI(R)
elseif S.tab=="catalog" and S.catalog then
right=catalogUI(R)
elseif S.tab=="stats" then
local CI=pair-40
local combat={label("\208\145\208\190\208\181\208\178\209\139\208\181 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184",CI,19)}
local cells={} local quarter=math.floor((CI-8)/2)
for _,v in ipairs({{"\208\154\208\187\208\176\209\129\209\129 \208\180\208\190\209\129\208\191\208\181\209\133\208\176",sh.armor_class},{"\208\152\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176",signed(cs.initiative)},{"\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140",sh.speed},{"\208\146\208\187\208\176\208\180\208\181\208\189\208\184\208\181",signed(cs.proficiency)}}) do
cells[#cells+1]=card({label(v[1],quarter-24,10,"#A0A6B2"),label(type(v[2])=="number" and num(v[2]) or v[2] or "\226\128\148",quarter-24,23)},quarter)
if #cells==2 then combat[#combat+1]=line(cells,CI) cells={} end
end
combat[#combat+1]=button("\208\152\208\183\208\188\208\181\208\189\208\184\209\130\209\140 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184",CI,function() beginEdit("resources") end)
combat[#combat+1]=button("\208\145\209\128\208\190\209\129\208\184\209\130\209\140 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131",CI,function() roll("initiative","") end)
combat[#combat+1]=button("\208\161\208\190\209\129\209\130\208\190\209\143\208\189\208\184\209\143 \194\183 "..#(sh.conditions or {}),CI,function() beginEdit("conditions") end)
local magic={label("\208\156\208\176\208\179\208\184\209\143",CI,19),label("\208\144\209\130\208\176\208\186\208\176  "..signed(cs.spell_attack).."  \194\183  \208\161\208\155  "..num(cs.spell_dc),CI,18,"#9085FF")}
for n=1,9 do local v=slot(sh,n) or {max=0,used=0}
magic[#magic+1]=label(num(n).." \208\186\209\128\209\131\208\179: "..num(v.max-v.used).." / "..num(v.max),CI,13,v.max>0 and "#F4F5F7" or "#A0A6B2")
end
magic[#magic+1]=button("\208\157\208\176\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \209\143\209\135\208\181\208\185\208\186\208\184",CI,function() beginEdit("magic") end)
magic[#magic+1]=button("\208\146\208\190\209\129\209\129\209\130\208\176\208\189\208\190\208\178\208\184\209\130\209\140 \209\143\209\135\208\181\208\185\208\186\208\184",CI,restoreSlots)
right[#right+1]=two({framed(combat,pair,360),framed(magic,pair,360)})
right[#right+1]=two({actionListUI("attack",pair,sh,560),actionListUI("spell",pair,sh,560)})
local notes={}
for _,v in ipairs({{"\208\152\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140",sh.inventory},{"\208\151\208\176\208\188\208\181\209\130\208\186\208\184",sh.notes}}) do
notes[#notes+1]=framed({label(v[1],CI,19),button("\208\160\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\209\130\209\140 \208\183\208\176\208\191\208\184\209\129\208\184",CI,function() beginEdit("notes") end),label(v[2]~="" and v[2] or "\208\159\208\190\208\186\208\176 \208\191\209\131\209\129\209\130\208\190",CI,14,"#A0A6B2")},pair,220)
end
right[#right+1]=two(notes)
elseif S.tab=="skills" then
local rows={label("\208\157\208\176\208\178\209\139\208\186\208\184 \208\184 \208\178\208\187\208\176\208\180\208\181\208\189\208\184\209\143",RI,20)}
for _,a in ipairs(skills) do local k=a[1] local prof=tonumber((sh.skills or {})[k]) or 0
rows[#rows+1]=line({button(({"\208\145\208\181\208\183 \208\178\208\187\208\176\208\180\208\181\208\189\208\184\209\143","\208\146\208\187\208\176\208\180\208\181\208\189\208\184\208\181","\208\156\208\176\209\129\209\130\208\181\209\128\209\129\209\130\208\178\208\190"})[prof+1],math.floor(RI*0.4),function() quickSkill(k) end,false,S.busy),button(a[2].."  "..signed((cs.skills or {})[k]),RI-math.floor(RI*0.4)-8,function() roll("skill",k) end)},RI)
end
right[#right+1]=card(rows,R)
elseif S.tab=="notes" then
right[#right+1]=button("\208\160\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\209\130\209\140 \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140 \208\184 \208\183\208\176\208\188\208\181\209\130\208\186\208\184",R,function() beginEdit("notes") end,true)
for _,v in ipairs({{"\208\152\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140",sh.inventory},{"\208\151\208\176\208\188\208\181\209\130\208\186\208\184",sh.notes},{"\208\159\209\128\208\181\208\180\209\139\209\129\209\130\208\190\209\128\208\184\209\143",sh.background}}) do right[#right+1]=card({label(v[1],RI,20),label(v[2] or "\226\128\148",RI,14)},R) end
else
right[#right+1]=actionListUI(S.tab=="attack" and "attack" or "spell",R,sh,math.max(380,P.bodyHeight-180))
end
if S.confirm then
local confirmation=S.confirm
right={card({label(confirmation.question,RI,22),button("\208\159\208\190\208\180\209\130\208\178\208\181\209\128\208\180\208\184\209\130\209\140",RI,function() S.confirm=nil confirmation.yes() draw() end,true,S.busy),button("\208\157\208\176\208\183\208\176\208\180",RI,function() S.confirm=nil draw() end,false,S.busy)},R)}
end
local pending=pendingUI(R)
if pending then right={pending} end
else
right={card({label("\208\155\208\184\209\129\209\130 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176",RI,25),label(S.msg,RI,15,"#A0A6B2"),button(S.on and "\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \208\183\208\176\208\179\209\128\209\131\208\183\208\186\209\131" or "\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\184\209\130\209\140",RI,function() if S.on then refresh() else startSheet("start") end end,true)},R)}
end
if P.narrow then
S.panel.children={column({column(right,R),column(left,L)},P.content,"center")}
else
if not S.leftScroll then
S.leftScroll=gui.Panel{width=P.left,height=P.bodyHeight,flow="vertical",vscroll=true,halign="left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,children={column(left,L)}}
S.rightScroll=gui.Panel{width=P.right,height=P.bodyHeight,flow="vertical",vscroll=true,halign="left",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,children={column(right,R)}}
S.panel.children={line({S.leftScroll,S.rightScroll},P.content,16,"center")}
else
S.leftScroll.children={column(left,L)}
S.rightScroll.children={column(right,R)}
end
end
if S.windowTitle then S.windowTitle.text=valid and d.character.name.." \194\183 "..num(d.character.level).." \209\131\209\128\208\190\208\178\208\181\208\189\209\140" or "\208\155\208\184\209\129\209\130 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176" end
if S.windowStatus then S.windowStatus.text=S.msg end
end
openWindow=function()
if S.window then return end
local hud=rawget(_G,"GameHud")
local host=hud and hud.instance and hud.instance.dialogWorldPanel
if not host then
S.msg="\208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\208\190\208\178\208\190\208\185 \209\129\209\130\208\190\208\187 DMHub \208\184 \208\191\208\190\208\191\209\128\208\190\208\177\209\131\208\185\209\130\208\181 \209\129\208\189\208\190\208\178\208\176"
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
S.windowTitle=label("\208\155\208\184\209\129\209\130 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176",titleWidth,23)
S.windowStatus=label(S.msg,P.window-40,12,"#A0A6B2","center")
S.panel=gui.Panel{width=P.window-32,height=P.bodyHeight,flow="vertical",vscroll=P.narrow,halign="center",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#101217ff"}
local header
if P.narrow then
S.windowTitle=label("\208\155\208\184\209\129\209\130 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176",P.window-48,22)
header=column({S.windowTitle,line({button("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\209\140",math.floor((P.window-56)/2),refresh),button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140",math.floor((P.window-56)/2),closeWindow)},P.window-48)},P.window-48,"center")
P.bodyHeight=P.height-142
S.panel=gui.Panel{width=P.window-32,height=P.bodyHeight,flow="vertical",vscroll=true,halign="center",valign="top",hmargin=0,vmargin=0,hpad=0,vpad=0,bgimage="panels/square.png",bgcolor="#101217ff"}
else header=line({column({label("SESSIONLAB",titleWidth,11,"#9085FF"),S.windowTitle},titleWidth),button("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\209\140",120,refresh),button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140",120,closeWindow)},P.window-48,nil,"center") end
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
destroy=function() if S.window==window then clearWindowReferences() end end,
children={gui.Panel{width=P.window,height=P.height,floating=true,halign="center",valign="center",bgimage="panels/square.png",bgcolor="#101217ff",interactable=false},
gui.Panel{width=P.window,height=12},dragHandle,
S.windowStatus,S.panel,gui.Panel{width=P.window,height=12}},
}
S.window=window host:AddChild(window) draw()
if not S.on then startSheet("start") end
end
startSheet=function(cmd)
if cmd=="stop" then S.on=false S.run=S.run+1 S.msg="\208\158\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189" draw() return end
if cmd=="refresh" then refresh() return end
if S.on then return end
if #TOKEN < 10 or TOKEN:sub(1,6)=="PASTE_" then S.msg="\208\146\209\129\209\130\208\176\208\178\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \208\178 TOKEN" draw() return end
S.on=true S.run=S.run+1 S.msg="\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181..." draw() local run=S.run refresh()
local function tick() if not S.on or run~=S.run then return end if not S.busy then refresh() end dmhub.Schedule(6,tick) end
dmhub.Schedule(6,tick)
end
Commands.slsheet=function(cmd)
if cmd==nil or cmd=="" or cmd=="start" or cmd=="open" then openWindow() else startSheet(cmd) end
end
DockablePanel.Register{name="SessionLab \194\183 \208\187\208\184\209\129\209\130",minWidth=300,maxWidth=400,vscroll=true,content=function()
local launchStatus=label(S.msg,276,13,"#A0A6B2")
S.launchStatus=launchStatus
local content=column({label("SessionLab",276,25,"#9085FF"),label("\208\155\208\184\209\129\209\130 \208\191\208\181\209\128\209\129\208\190\208\189\208\176\208\182\208\176 \208\178 \208\190\209\130\208\180\208\181\208\187\209\140\208\189\208\190\208\188 \208\190\208\186\208\189\208\181",276,14,"#A0A6B2"),button("\208\158\209\130\208\186\209\128\209\139\209\130\209\140 \208\187\208\184\209\129\209\130",276,openWindow,true),S.launchStatus},276,"center")
return gui.Panel{width=300,height="auto",flow="vertical",destroy=function() if S.launchStatus==launchStatus then S.launchStatus=nil end end,children={gui.Panel{width=300,height=12},content,gui.Panel{width=300,height=12}}}
end}
print("SessionLab sheet loaded \194\183 /slsheet start")
local runSessionLabSheet=Commands.slsheet
if type(Commands.RegisterMacro)=="function" then
Commands.RegisterMacro{name="slsheet",summary="SessionLab sheet",command=function(args)
chat.Send("SessionLab: command received")
runSessionLabSheet(args or "start")
end}
end
-- End.
