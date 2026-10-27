-- ASCII source: Russian labels are encoded as Lua UTF-8 byte escapes.
-- SessionLab sheet for the DMHub editor. Check the last line before saving.
local URL="https://sessionlab.up.railway.app"
local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"
local previous=rawget(_G,"SLsheet")
if previous then previous.on=false end
local S={on=false,run=0,tab="stats",page=1,level={},amount=5,msg="/slsheet start"}
rawset(_G,"SLsheet",S)
local base="/api/integrations/dmhub/sheets/"
local attrs={{"str","\208\161\208\184\208\187\208\176"},{"dex","\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140"},{"con","\208\162\208\181\208\187\208\190"},{"int","\208\152\208\189\209\130\208\181\208\187\208\187\208\181\208\186\209\130"},{"wis","\208\156\209\131\208\180\209\128\208\190\209\129\209\130\209\140"},{"cha","\208\165\208\176\209\128\208\184\208\183\208\188\208\176"}}
local skills={{"acrobatics","\208\144\208\186\209\128\208\190\208\177\208\176\209\130\208\184\208\186\208\176"},{"animal_handling","\208\150\208\184\208\178\208\190\209\130\208\189\209\139\208\181"},{"arcana","\208\156\208\176\208\179\208\184\209\143"},{"athletics","\208\144\209\130\208\187\208\181\209\130\208\184\208\186\208\176"},{"deception","\208\158\208\177\208\188\208\176\208\189"},{"history","\208\152\209\129\209\130\208\190\209\128\208\184\209\143"},{"insight","\208\159\209\128\208\190\208\189\208\184\209\134\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"},{"intimidation","\208\151\208\176\208\191\209\131\208\179\208\184\208\178\208\176\208\189\208\184\208\181"},{"investigation","\208\144\208\189\208\176\208\187\208\184\208\183"},{"medicine","\208\156\208\181\208\180\208\184\209\134\208\184\208\189\208\176"},{"nature","\208\159\209\128\208\184\209\128\208\190\208\180\208\176"},{"perception","\208\146\208\189\208\184\208\188\208\176\209\130\208\181\208\187\209\140\208\189\208\190\209\129\209\130\209\140"},{"performance","\208\146\209\139\209\129\209\130\209\131\208\191\208\187\208\181\208\189\208\184\208\181"},{"persuasion","\208\163\208\177\208\181\208\182\208\180\208\181\208\189\208\184\208\181"},{"religion","\208\160\208\181\208\187\208\184\208\179\208\184\209\143"},{"sleight_of_hand","\208\155\208\190\208\178\208\186\208\190\209\129\209\130\209\140 \209\128\209\131\208\186"},{"stealth","\208\161\208\186\209\128\209\139\209\130\208\189\208\190\209\129\209\130\209\140"},{"survival","\208\146\209\139\208\182\208\184\208\178\208\176\208\189\208\184\208\181"}}
local function text(t) return gui.Label{text=tostring(t or ""),width="100%",height="auto",fontSize=16,color="#F4F5F7"} end
local function btn(t,f) return gui.Label{text=t,width="100%",height=30,fontSize=16,color="#F4F5F7",bgimage="panels/square.png",bgcolor="#353B50",click=f} end
local function signed(n) n=tonumber(n) or 0 return n>=0 and "+"..n or tostring(n) end
local draw,refresh,startSheet
local function api(path,body,done)
 local run=S.run
 local h={Authorization="Bearer "..TOKEN,Accept="application/json"}
 local f
 if body then f=net.Post else f=net.Get end
 if type(f)~="function" then S.msg="HTTP \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189" draw() return end
 local o={url=URL..path,headers=h}
 o.success=function(raw)
  if not S.on or run~=S.run then return end
  S.busy=false
  local ok,r=pcall(function() return type(raw)=="table" and raw or json.decode(raw) end)
  if ok and type(r)=="table" and type(r.data)=="table" then done(r.data)
  else S.msg="\208\158\209\136\208\184\208\177\208\186\208\176 \208\190\209\130\208\178\208\181\209\130\208\176 API: "..tostring(ok and type(r)=="table" and r.error or r):sub(1,120) draw() end
 end
 o.failure=function() if S.on and run==S.run then S.busy=false S.msg="\208\161\208\181\209\130\209\140: \208\191\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \209\128\208\181\208\183\209\131\208\187\209\140\209\130\208\176\209\130 \208\189\208\176 \209\129\208\176\208\185\209\130\208\181" draw() end end
 if body then
  S.busy=true S.seq=(S.seq or 0)+1
  h["Content-Type"]="application/json"
  h["Idempotency-Key"]=tostring(os.time()).."-"..S.seq.."-"..math.random(100000,999999)
  o.body=json.encode(body) o.data=o.body
 end
 local ok,e=pcall(function() f(o) end)
 if not ok then S.busy=false S.msg=tostring(e):sub(1,70) draw() end
end
refresh=function()
 if not S.on then return end
 if not S.id then
  api(base,nil,function(d) S.list=d.characters or {} if S.list[1] then S.id=S.list[1].id refresh() else S.msg="\208\157\208\181\209\130 \208\187\208\184\209\129\209\130\208\190\208\178" draw() end end)
 else api(base..S.id.."/",nil,function(d) S.data=d S.msg="\208\158\208\177\208\189\208\190\208\178\208\187\208\181\208\189\208\190" draw() end) end
end
local function act(path,body)
 if S.busy then return end
 S.msg="\208\158\209\130\208\191\209\128\208\176\208\178\208\186\208\176..." draw()
 api(path,body,function(d)
  local p=d.payload or {} local x=(p.parts or {p})[1] or {}
  S.result=tostring(p.label or "\208\148\208\181\208\185\209\129\209\130\208\178\208\184\208\181")
  if x.roll then S.result=S.result.." \194\183 "..tostring(x.roll.total) end
  if x.damage then S.result=S.result.." \194\183 \209\131\209\128\208\190\208\189 "..tostring(x.damage.total) end
  if x.save then S.result=S.result.." \194\183 \208\161\208\155 "..tostring(x.save.dc) end
  refresh()
 end)
end
local function roll(k,id) act(base..S.id.."/roll/",{kind=k,key=id}) end
local function cast(a,sh)
 local n=S.level[a.id] or a.level or 0
 if a.kind=="spell" and a.level>0 then
  local v=(sh.slots or {})[tostring(n)]
  if not v or v.used>=v.max then S.msg="\208\157\208\181\209\130 \209\143\209\135\208\181\208\185\208\186\208\184 "..n draw() return end
 end
 act(base..S.id.."/abilities/"..a.id.."/use/",{slot_level=n})
end
draw=function()
 if not S.panel then return end
 local r={text("SessionLab \194\183 \208\187\208\184\209\129\209\130"),text(S.msg)}
 if not S.on then r[#r+1]=btn("\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\184\209\130\209\140",function() startSheet("start") end) end
 if S.result then r[#r+1]=text(S.result) end
 if S.on then
  r[#r+1]=btn("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\209\140",refresh)
  for _,c in ipairs(S.list or {}) do local id=c.id r[#r+1]=btn((id==S.id and "\226\128\162 " or "")..c.name,function() S.id=id S.data=nil refresh() end) end
  local d=S.data
  if d and d.character and d.character.id==S.id then
   local sh=d.sheet local cs=sh.computed
   r[#r+1]=text(d.character.name.." \194\183 \208\154\208\148 "..sh.armor_class.." \194\183 \208\165\208\184\209\130\209\139 "..sh.hp_current.."/"..sh.hp_max.." \194\183 \208\146\209\128\208\181\208\188. "..sh.hp_temp)
   for _,t in ipairs({{"stats","\208\159\208\190\208\186\208\176\208\183\208\176\209\130\208\181\208\187\208\184"},{"skills","\208\157\208\176\208\178\209\139\208\186\208\184"},{"attack","\208\144\209\130\208\176\208\186\208\184"},{"spell","\208\151\208\176\208\186\208\187\208\184\208\189\208\176\208\189\208\184\209\143"},{"notes","\208\151\208\176\208\188\208\181\209\130\208\186\208\184"}}) do
    local tab=t[1] r[#r+1]=btn(t[2],function() S.tab=tab S.page=1 S.open=nil draw() end)
   end
   if S.tab=="stats" then
    for _,a in ipairs(attrs) do local k=a[1]
     r[#r+1]=btn(a[2].." "..sh.abilities[k].." "..signed(cs.modifiers[k]),function() roll("ability",k) end)
     r[#r+1]=btn("\208\161\208\191\208\176\209\129 "..a[2].." "..signed(cs.saves[k]),function() roll("save",k) end)
    end
    r[#r+1]=btn("\208\152\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176 "..signed(cs.initiative),function() roll("initiative","") end)
    r[#r+1]=btn("\208\154\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190: "..S.amount,function() local v={1,5,10,20,50} for i,n in ipairs(v) do if n==S.amount then S.amount=v[i%5+1] break end end draw() end)
    for _,v in ipairs({{"damage","\208\163\209\128\208\190\208\189"},{"heal","\208\155\208\181\209\135\208\181\208\189\208\184\208\181"},{"temporary","\208\146\209\128\208\181\208\188. \209\133\208\184\209\130\209\139"}}) do local kind=v[1]
     r[#r+1]=btn(v[2],function() act(base..S.id.."/resources/",{action=kind,amount=S.amount}) end)
    end
    r[#r+1]=text("\208\161\208\190\209\129\209\130\208\190\209\143\208\189\208\184\209\143: "..table.concat(sh.conditions or {},", "))
   elseif S.tab=="skills" then
    for _,a in ipairs(skills) do local k=a[1] r[#r+1]=btn(a[2].." "..signed(cs.skills[k]),function() roll("skill",k) end) end
   elseif S.tab=="notes" then
    r[#r+1]=text("\208\152\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140: "..tostring(sh.inventory or ""))
    r[#r+1]=text("\208\151\208\176\208\188\208\181\209\130\208\186\208\184: "..tostring(sh.notes or ""))
   else
    local list={}
    for _,a in ipairs(d.actions or {}) do if a.kind==S.tab then list[#list+1]=a end end
    local start=(S.page-1)*6+1
    for i=start,math.min(start+5,#list) do local a=list[i]
     r[#r+1]=btn(a.name,function() S.open=S.open==a.id and nil or a.id draw() end)
     if S.open==a.id then
      r[#r+1]=text((a.casting_time or "").." \194\183 "..(a.range or "").." \194\183 "..(a.duration or ""))
      r[#r+1]=text(a.description)
      if a.kind=="spell" and a.level>0 then
       local levels={}
       for n=a.level,(a.upcast_allowed and 9 or a.level) do local v=(sh.slots or {})[tostring(n)] if v and v.used<v.max then levels[#levels+1]=n end end
       if #levels>0 then local current=S.level[a.id] or levels[1]
        r[#r+1]=btn("\208\175\209\135\208\181\208\185\208\186\208\176 "..current,function() for j,n in ipairs(levels) do if n==current then S.level[a.id]=levels[j%#levels+1] break end end draw() end)
       else r[#r+1]=text("\208\157\208\181\209\130 \209\143\209\135\208\181\208\181\208\186") end
      end
     end
     r[#r+1]=btn("\208\159\209\128\208\184\208\188\208\181\208\189\208\184\209\130\209\140 "..a.name,function() cast(a,sh) end)
    end
    if S.page>1 then r[#r+1]=btn("\208\157\208\176\208\183\208\176\208\180",function() S.page=S.page-1 draw() end) end
    if start+5<#list then r[#r+1]=btn("\208\148\208\176\208\187\208\181\208\181",function() S.page=S.page+1 draw() end) end
   end
  end
 end
 S.panel.children=r
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
Commands.slsheet=startSheet
DockablePanel.Register{name="SessionLab \194\183 \208\187\208\184\209\129\209\130",minWidth=350,maxWidth=420,vscroll=true,content=function()
 S.panel=gui.Panel{width="100%",height="auto",flow="vertical"} draw() return S.panel end}
print("SessionLab sheet loaded \194\183 /slsheet start")
local runSessionLabSheet=startSheet
if type(Commands.RegisterMacro)=="function" then
 Commands.RegisterMacro{name="slsheet",summary="SessionLab sheet",command=function(args)
  chat.Send("SessionLab: command received")
  runSessionLabSheet(args or "start")
 end}
end
-- End.
