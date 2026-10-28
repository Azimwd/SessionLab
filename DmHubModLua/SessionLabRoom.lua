-- ASCII source: Russian labels use UTF-8 byte escapes.
-- SessionLab room / initiative. Personal token only. ASCII installable file is generated.
local URL="https://sessionlab.up.railway.app"
local TOKEN="g2Rijz9WVnUFMfPY-cxYE7LlF09yNRVbudIGeq_TKZVBrGuKZDWusGPBKQk5UXCe"
local INTERVAL=3
local old=rawget(_G,"SessionLabRoomRuntime")
if old then old.active=false if old.window then old.window:DestroySelf() end end
local S={active=false,run=0,compact=false,preview=false,tab="table",folders={},selected={},counts={},draft={name="",bonus="0",count="1"},msg="\208\157\208\181 \208\191\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\190",x=0,y=40}
rawset(_G,"SessionLabRoomRuntime",S)
local draw,refresh,openWindow,send,closeWindow,start,renderSetup,buildWindow
local W=560
local function fmt(v) return type(v)=="number" and string.format("%g",v) or tostring(v or "") end
local function label(t,w,size,color)
 return gui.Label{text=tostring(t or ""),width=w or W,height="auto",fontSize=size or 14,color=color or "#F4F5F7",textAlignment="left",hpad=0,vpad=0,hmargin=0,vmargin=3,blocksGameInteraction=false,interactable=false}
end
local function column(c,w) return gui.Panel{width=w or W,height="auto",flow="vertical",hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children=c} end
local function row(c,w) return gui.Panel{width=w or W,height="auto",flow="horizontal",hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children=c} end
local function gap() return gui.Panel{width=8,height=1,interactable=false,blocksGameInteraction=false} end
local function button(t,w,f,accent)
 return gui.Button{text=t,width=w,height=32,fontSize=13,color="#F4F5F7",bgimage="panels/square.png",bgcolor=accent and "#695CF5ff" or "#232833ee",classes={accent and "slr-accent" or "slr-button"},hpad=0,vpad=0,hmargin=0,vmargin=3,blocksGameInteraction=true,press=f}
end
local function input(key,w,placeholder)
 return gui.Input{text=S.draft[key],placeholderText=placeholder,width=w,height=32,fontSize=14,color="#F4F5F7",bgimage="panels/square.png",bgcolor="#101217ee",classes={"slr-input"},blocksGameInteraction=true,
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
 return tostring(body or "\208\158\209\136\208\184\208\177\208\186\208\176 \208\183\208\176\208\191\209\128\208\190\209\129\208\176"):sub(1,180)
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
  if not ok or type(r)~="table" or type(r.data)~="table" or r.error then fail(ok and errorText(type(r)=="table" and r.error or r) or "\208\157\208\181\208\178\208\181\209\128\208\189\209\139\208\185 JSON") return end
  finished=true done(r.data)
 end
 opts.error=fail opts.failure=fail
 if body then opts.data=body opts.headers["Idempotency-Key"]=key end
 local ok,err=pcall(function() if body then net.Post(opts) else net.Get(opts) end end)
 if not ok then fail(err) end
 -- Do not create overlapping requests if the native transport never invokes a callback.
 dmhub.Schedule(20,function() fail("\208\162\208\176\208\185\208\188-\208\176\209\131\209\130: \208\191\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \209\129\208\190\209\129\209\130\208\190\209\143\208\189\208\184\208\181, \208\183\208\176\209\130\208\181\208\188 \208\191\208\190\208\178\209\130\208\190\209\128\208\184\209\130\208\181 \208\183\208\176\208\191\209\128\208\190\209\129") end)
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
  d.revision=nil -- Unrelated chat/dice events must not rebuild the room UI.
  local hash=fingerprint(d)
  if hash~=S.hash then
   S.data=d S.hash=hash
   if d.role~="dm" then S.preview=false S.selected={} S.setup=false end
   if needsWindow and S.window then buildWindow() else draw() end
  end
  if not S.pending then status("\208\157\208\176 \209\129\208\178\209\143\208\183\208\184 \194\183 \208\186\208\176\208\182\208\180\209\139\208\181 3 \209\129\208\181\208\186.") end
 end,function(err) S.reading=false S.data=nil S.hash=nil S.setup=false S.selected={} status(errorText(err)) if S.window then buildWindow() end end)
end
local function nextKey()
 S.seq=(S.seq or 0)+1
 return "slroom-"..tostring(os.time()).."-"..math.random(100000,999999).."-"..S.seq
end
local function transmit()
 local pending=S.pending if not pending or pending.sending then return end
 pending.sending=true status("\208\161\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\184\208\181...")
 http("/api/integrations/dmhub/room/commands/",pending.body,pending.key,function()
  if S.pending~=pending then return end
  S.pending=nil S.confirm=nil S.hash=nil S.setup=false S.setupHost=nil
  status("\208\161\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\190") refresh() draw()
 end,function(err)
  if S.pending~=pending then return end
  pending.sending=false status(errorText(err).." \194\183 \208\191\208\190\208\178\209\130\208\190\209\128\208\184\209\130\208\181 \209\130\208\190\209\130 \208\182\208\181 \208\183\208\176\208\191\209\128\208\190\209\129 \208\184\208\187\208\184 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\208\181") if S.window then buildWindow() end
 end)
end
send=function(body)
 if S.pending or not S.data or not S.data.master_view then return end
 if body.command=="initiative" then
  if not S.data.session then status("\208\157\208\181\209\130 \208\176\208\186\209\130\208\184\208\178\208\189\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184") return end
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
local function characters()
 local out={} local d=S.data or {}
 for _,c in ipairs(d.party or {}) do out[#out+1]=c end
 for _,c in ipairs(d.npcs or {}) do out[#out+1]=c end return out
end
local function currentText()
 local t=S.data and S.data.initiative or {}
 for _,e in ipairs(t.entries or {}) do if e.id==t.current then return e.name end end
 return t.hidden_turn and "\208\161\208\186\209\128\209\139\209\130\209\139\208\185 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186" or (t.running and "\208\158\208\182\208\184\208\180\208\176\208\189\208\184\208\181" or "\208\157\208\181 \208\189\208\176\209\135\208\176\209\130\208\190")
end
local function requestReset()
 if S.confirm=="reset" then initiative("reset") else S.confirm="reset" draw() end
end
local function trackerUI()
 local t=S.data.initiative local rows={}
 if S.data.master_view then
  rows[#rows+1]=row({button(t.running and "\208\159\208\176\209\131\208\183\208\176" or "\208\159\209\128\208\190\208\180\208\190\208\187\208\182\208\184\209\130\209\140",140,function() initiative(t.running and "stop" or "start") end),gap(),button("\208\161\208\187\208\181\208\180\209\131\209\142\209\137\208\184\208\185 \209\133\208\190\208\180",200,function() initiative("next") end),gap(),button(S.confirm=="reset" and "\208\159\208\190\208\180\209\130\208\178\208\181\209\128\208\180\208\184\209\130\209\140 \209\129\208\177\209\128\208\190\209\129" or "\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140",204,requestReset)})
  if not t.running and (t.round_number or 0)==0 then rows[#rows+1]=button(S.setup and "\208\161\208\186\209\128\209\139\209\130\209\140 \208\191\208\190\208\180\208\179\208\190\209\130\208\190\208\178\208\186\209\131" or "\208\146\209\139\208\177\209\128\208\176\209\130\209\140 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\190\208\178",W,function() S.setup=not S.setup draw() end) end
 end
 for _,e in ipairs(t.entries or {}) do
  local entry=e local marker=e.id==t.current and "> " or ""
  local parts={label(marker..e.name.." \194\183 "..fmt(e.initiative)..(e.hidden and " \194\183 \209\129\208\186\209\128\209\139\209\130" or ""),S.data.master_view and 256 or W,16,e.id==t.current and "#B3A9FF" or nil)}
  if S.data.master_view and not t.running then
   parts[#parts+1]=button("\208\152\208\183\208\188\208\181\208\189\208\184\209\130\209\140",96,function() S.editEntry=entry.id S.draft.entryName=entry.name S.draft.entryScore=fmt(entry.initiative) draw() end)
   parts[#parts+1]=gap()
   parts[#parts+1]=button(e.hidden and "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140" or "\208\161\208\186\209\128\209\139\209\130\209\140",96,function() initiative("edit",{entry=entry.id,hidden=not entry.hidden}) end)
   parts[#parts+1]=gap() parts[#parts+1]=button("\208\163\208\177\209\128\208\176\209\130\209\140",96,function() initiative("remove",{entry=entry.id}) end)
  end
  rows[#rows+1]=row(parts)
  if S.editEntry==entry.id and not t.running then
   rows[#rows+1]=row({input("entryName",320,"\208\152\208\188\209\143 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\176"),gap(),input("entryScore",104,"\208\152\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176"),gap(),button("\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140",120,function()
    local score=tonumber(S.draft.entryScore)
    if not score or score%1~=0 or score< -100 or score>100 or not S.draft.entryName:match("%S") then status("\208\152\208\188\209\143 \208\184 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176 \226\136\146100\226\128\166100") return end
    S.editEntry=nil initiative("edit",{entry=entry.id,name=S.draft.entryName,initiative=score})
   end)})
  end
 end
 if #(t.entries or {})==0 then rows[#rows+1]=label("\208\146 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\181 \208\191\208\190\208\186\208\176 \208\189\208\181\209\130 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\190\208\178",W,14,"#A0A6B2") end
 return column(rows)
end
local function tableUI()
 local rows={} local d=S.data
 if d.master_view then rows[#rows+1]=button(d.table_visible_to_players and "\208\161\209\130\208\190\208\187 \208\178\208\184\208\180\208\181\208\189 \208\184\208\179\209\128\208\190\208\186\208\176\208\188 \194\183 \209\129\208\186\209\128\209\139\209\130\209\140" or "\208\161\209\130\208\190\208\187 \209\129\208\186\209\128\209\139\209\130 \194\183 \208\191\208\190\208\186\208\176\208\183\208\176\209\130\209\140",W,function() visible("table",nil,not d.table_visible_to_players) end) end
 for _,f in ipairs(d.folders or {}) do
  local folder=f local key=tostring(f.id) local list={}
  for _,c in ipairs(characters()) do if tostring(c.folder or "unfiled")==key then list[#list+1]=c end end
  local parts={button((S.folders[key] and "+ " or "\226\136\146 ")..f.name.." \194\183 "..#list,d.master_view and 416 or W,function() S.folders[key]=not S.folders[key] draw() end)}
  if d.master_view then parts[#parts+1]=gap() parts[#parts+1]=button(f.visible_to_players and "\208\146\208\184\208\180\208\181\208\189" or "\208\161\208\186\209\128\209\139\209\130",136,function() visible("folder",folder.id,not folder.visible_to_players) end) end
  rows[#rows+1]=row(parts)
  if not S.folders[key] then
   for _,c in ipairs(list) do
    local char=c
    local info={label(c.name.." \194\183 "..(c.character_class or "").." \194\183 \209\131\209\128. "..fmt(c.level),d.master_view and 416 or W,17),label("\208\165\208\184\209\130\209\139 "..fmt(c.hp_current).."/"..fmt(c.hp_max).." +"..fmt(c.hp_temp).." \194\183 \208\154\208\148 "..fmt(c.armor_class).." \194\183 \208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140 "..fmt(c.speed).." \194\183 \208\152\208\189\209\134. "..fmt(c.initiative),d.master_view and 416 or W,14,"#A0A6B2")}
    local scores={}
    for _,a in ipairs({{"str","\208\161\208\152\208\155"},{"dex","\208\155\208\158\208\146"},{"con","\208\162\208\149\208\155"},{"int","\208\152\208\157\208\162"},{"wis","\208\156\208\148\208\160"},{"cha","\208\165\208\144\208\160"}}) do
     scores[#scores+1]=a[2].." "..fmt((c.abilities or {})[a[1]])
    end
    info[#info+1]=label(table.concat(scores," \194\183 "),d.master_view and 416 or W,12,"#A0A6B2")
    if #(c.conditions or {})>0 then info[#info+1]=label(table.concat(c.conditions,", "),d.master_view and 416 or W,12,"#F0B17C") end
    local content={column(info,d.master_view and 416 or W)}
    if d.master_view then content[#content+1]=gap() content[#content+1]=button(c.table_visible and "\208\159\208\190\208\186\208\176\208\183\208\176\208\189" or "\208\161\208\186\209\128\209\139\209\130",136,function() visible("character",char.id,not char.table_visible) end) end
    rows[#rows+1]=row(content)
   end
  end
 end
 if #(d.folders or {})==0 then rows[#rows+1]=label("\208\156\208\176\209\129\209\130\208\181\209\128 \208\191\208\190\208\186\208\176 \208\189\208\181 \208\190\209\130\208\186\209\128\209\139\208\187 \209\129\209\130\208\190\208\187 \208\180\208\187\209\143 \208\184\208\179\209\128\208\190\208\186\208\190\208\178",W,14,"#A0A6B2") end
 return column(rows)
end
renderSetup=function()
 if not S.setupHost then return end
 local rows={label("\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\187\208\184\209\129\209\130\209\139 \194\183 \208\191\208\190\208\178\209\130\208\190\209\128\208\189\208\190\208\181 \208\189\208\176\208\182\208\176\209\130\208\184\208\181 \208\188\208\181\208\189\209\143\208\181\209\130 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 NPC",W,13,"#A0A6B2")}
 for _,f in ipairs(S.data.folders or {}) do
  rows[#rows+1]=label(f.name,W,16,"#B3A9FF")
  for _,c in ipairs(characters()) do
   if tostring(c.folder or "unfiled")==tostring(f.id) then
    local char=c local count=S.selected[c.id] or 0
    rows[#rows+1]=button((count>0 and "["..count.."] " or "[ ] ")..c.name,W,function()
     if char.kind=="player" then S.selected[char.id]=count>0 and 0 or 1 else S.selected[char.id]=(count+1)%21 end renderSetup()
    end)
   end
  end
 end
 S.setupHost.children=rows
end
local function setupUI()
 S.setupHost=column({}) renderSetup()
 local rows={label("\208\159\208\190\208\180\208\179\208\190\209\130\208\190\208\178\208\186\208\176 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\139",W,19),S.setupHost,label("\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\185 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186: \208\184\208\188\209\143 / \208\177\208\190\208\189\209\131\209\129 / \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190",W,13,"#A0A6B2"),
  row({input("name",320,"\208\152\208\188\209\143"),gap(),input("bonus",104,"\208\145\208\190\208\189\209\131\209\129"),gap(),input("count",120,"\208\154\208\190\208\187-\208\178\208\190")}),
  button("\208\157\208\176\209\135\208\176\209\130\209\140 \194\183 \208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\209\131 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\209\139\208\188",W,function()
   local participants={}
   for _,c in ipairs(characters()) do local count=S.selected[c.id] or 0 if count>0 then participants[#participants+1]={character=c.id,count=count} end end
   if S.draft.name:match("%S") then
    local bonus,count=tonumber(S.draft.bonus),tonumber(S.draft.count)
    if not bonus or bonus%1~=0 or bonus< -30 or bonus>30 or not count or count%1~=0 or count<1 or count>20 then status("\208\145\208\190\208\189\209\131\209\129 \226\136\14630\226\128\16630; \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 1\226\128\16620") return end
    participants[#participants+1]={name=S.draft.name,bonus=bonus,count=count}
   end
   if #participants==0 then status("\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\133\208\190\209\130\209\143 \208\177\209\139 \208\190\208\180\208\189\208\190\208\179\208\190 \209\131\209\135\208\176\209\129\209\130\208\189\208\184\208\186\208\176") return end
   initiative("start",{participants=participants})
  end)}
 return column(rows)
end
local function renderBody()
 if not S.body then return end
 if S.compact then S.body.children={} return end
 if not S.data then S.body.children={label("\208\159\208\190\208\180\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181 \208\186 \208\186\208\190\208\188\208\189\208\176\209\130\208\181...",W,16)} return end
 if S.setup and S.data.master_view then
  -- Keep inputs alive during polling; selected counts update in a separate host.
  if not S.setupHost then S.body.children={setupUI()} end return
 end
 S.setupHost=nil
 S.body.children={S.tab=="table" and tableUI() or trackerUI()}
end
draw=function()
 if S.title then S.title.text=currentText() end
 if S.round then local t=S.data and S.data.initiative or {} S.round.text="\208\160\208\176\209\131\208\189\208\180 "..fmt(t.round_number or 0).." \194\183 "..(t.running and "\208\145\208\190\208\185" or "\208\159\208\176\209\131\208\183\208\176") end
 if S.modeButton then S.modeButton.text=S.preview and "\208\160\208\181\208\182\208\184\208\188 \208\188\208\176\209\129\209\130\208\181\209\128\208\176" or "\208\146\208\184\208\180 \208\184\208\179\209\128\208\190\208\186\208\176" end
 renderBody()
end
closeWindow=function()
 S.active=false S.run=S.run+1 S.reading=false S.pending=nil
 local win=S.window S.window=nil
 S.body=nil S.title=nil S.round=nil S.status=nil S.modeButton=nil S.setupHost=nil
 if win then win:DestroySelf() end
end
buildWindow=function()
 S.modeButton=nil S.setupHost=nil
 local screenHeight=720
 if dmhub.screenDimensions then screenHeight=tonumber(dmhub.screenDimensions.y) or 720 end
 local bodyHeight=math.min(360,math.max(100,screenHeight-350))
 local compact=S.compact local width=compact and 400 or 584 local inner=width-24
 S.title=label(currentText(),inner,compact and 19 or 24,"#B3A9FF")
 S.round=label("",inner,14,"#A0A6B2")
 local master=S.data and S.data.master_view
 local expandWidth=compact and (master and 120 or 184) or (master and 176 or 276)
 local closeWidth=compact and (master and 104 or 184) or (master and 176 or 276)
 local buttons={button(compact and "\208\160\208\176\208\183\208\178\208\181\209\128\208\189\209\131\209\130\209\140" or "\208\161\208\178\208\181\209\128\208\189\209\131\209\130\209\140",expandWidth,function() S.compact=not S.compact buildWindow() end),gap()}
 if master then
  buttons[#buttons+1]=button("\208\161\208\187\208\181\208\180\209\131\209\142\209\137\208\184\208\185 \209\133\208\190\208\180",compact and 136 or 192,function() initiative("next") end,true)
  buttons[#buttons+1]=gap()
 end
 buttons[#buttons+1]=button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140",closeWidth,closeWindow)
 local top={label("SESSIONLAB \194\183 "..(compact and "\208\152\208\157\208\152\208\166\208\152\208\144\208\162\208\152\208\146\208\144" or "\208\154\208\158\208\156\208\157\208\144\208\162\208\144"),inner,11,"#9085FF"),S.title,S.round,row(buttons,inner)}
 if not compact then
  if S.data then top[#top+1]=label((S.data.campaign_name or "").." \194\183 "..(S.data.session and S.data.session.name or "\208\157\208\181\209\130 \208\176\208\186\209\130\208\184\208\178\208\189\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184"),W,13,"#A0A6B2") end
  local nav={button("\208\151\208\176 \209\129\209\130\208\190\208\187\208\190\208\188",160,function() S.tab="table" S.setup=false draw() end),gap(),button("\208\152\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176",160,function() S.tab="initiative" S.setup=false draw() end)}
  if S.data and S.data.role=="dm" then
   S.modeButton=button(S.preview and "\208\160\208\181\208\182\208\184\208\188 \208\188\208\176\209\129\209\130\208\181\209\128\208\176" or "\208\146\208\184\208\180 \208\184\208\179\209\128\208\190\208\186\208\176",224,function() S.preview=not S.preview S.data=nil S.hash=nil S.setup=false S.selected={} S.setupHost=nil buildWindow() refresh() end)
   nav[#nav+1]=gap() nav[#nav+1]=S.modeButton
  end
  top[#top+1]=row(nav)
  S.status=label(S.msg,W,12,"#A0A6B2") top[#top+1]=S.status
  if S.pending and not S.pending.sending then
   top[#top+1]=row({button("\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \208\183\208\176\208\191\209\128\208\190\209\129",276,transmit),gap(),button("\208\159\209\128\208\190\208\178\208\181\209\128\208\184\209\130\209\140 \209\129\208\190\209\129\209\130\208\190\209\143\208\189\208\184\208\181",276,function() S.pending=nil S.hash=nil refresh() end)})
  end
  S.body=gui.Panel{width=W,height=bodyHeight,flow="vertical",vscroll=true,hpad=0,vpad=0,hmargin=0,vmargin=0,blocksGameInteraction=false,children={}}
  top[#top+1]=S.body
 else
  S.body=nil S.modeButton=nil S.status=label(S.msg,inner,11,"#A0A6B2") top[#top+1]=S.status
  if S.pending and not S.pending.sending then top[#top+1]=button("\208\159\208\190\208\178\209\130\208\190\209\128\208\184\209\130\209\140 \208\183\208\176\208\191\209\128\208\190\209\129",inner,transmit) end
 end
 local win
 win=gui.Panel{width=width,height="auto",flow="vertical",floating=true,halign="center",valign="top",x=S.x,y=S.y,hpad=12,vpad=8,
  bgimage="panels/square.png",bgcolor="#101217e8",classes={"slr-window"},blocksGameInteraction=false,draggable=true,constrainToScreen=true,
  styles={
   {selectors={"slr-window"},priority=100,bgimage="panels/square.png",bgcolor="#101217e8",cornerRadius=12,borderWidth=1,borderColor="#303642ff"},
   {selectors={"slr-button"},priority=100,bgimage="panels/square.png",bgcolor="#232833ee",cornerRadius=6,borderWidth=1,borderColor="#303642ff",color="#F4F5F7",hpad=0,vpad=0,hmargin=0},
   {selectors={"slr-accent"},priority=100,bgimage="panels/square.png",bgcolor="#695CF5ff",cornerRadius=6,borderWidth=1,borderColor="#9085FFff",color="#FFFFFF",hpad=0,vpad=0,hmargin=0},
   {selectors={"slr-input"},priority=100,bgimage="panels/square.png",bgcolor="#101217ee",cornerRadius=6,borderWidth=1,borderColor="#303642ff",color="#F4F5F7"},
  },
  drag=function(e) S.x=e.xdrag S.y=e.ydrag e.x=S.x e.y=S.y end,
  destroy=function() if S.window==win then S.window=nil S.active=false S.run=S.run+1 S.body=nil S.title=nil S.round=nil S.status=nil S.modeButton=nil S.setupHost=nil end end,
  children=top}
 local previous=S.window S.window=win if previous then previous:DestroySelf() end
 local hud=rawget(_G,"GameHud") local host=hud and hud.instance and hud.instance.dialogWorldPanel
 if not host then S.window=nil win:DestroySelf() status("\208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\208\190\208\178\208\190\208\185 \209\129\209\130\208\190\208\187 DMHub \208\184 \208\191\208\190\208\191\209\128\208\190\208\177\209\131\208\185\209\130\208\181 \209\129\208\189\208\190\208\178\208\176") return false end
 host:AddChild(win) draw() return true
end


start=function()
 if S.active then return end
 if #TOKEN<32 or TOKEN:sub(1,6)=="PASTE_" then status("\208\146\209\129\209\130\208\176\208\178\209\140\209\130\208\181 \208\187\208\184\209\135\208\189\209\139\208\185 \208\186\208\187\209\142\209\135 \208\178 TOKEN") return end
 S.active=true S.run=S.run+1 S.reading=false local run=S.run
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
Commands.slroom=function(args)
 local cmd=tostring(args or ""):lower():match("^%s*(.-)%s*$")
 if cmd=="close" or cmd=="stop" then closeWindow()
 elseif cmd=="refresh" then refresh()
 else openWindow() end
end
if type(Commands.RegisterMacro)=="function" then
 Commands.RegisterMacro{name="slroom",summary="SessionLab room and initiative",command=Commands.slroom}
end
DockablePanel.Register{name="SessionLab \194\183 \208\186\208\190\208\188\208\189\208\176\209\130\208\176",minWidth=300,maxWidth=400,vscroll=true,content=function()
 local launch=label(S.msg,276,13,"#A0A6B2") S.launchStatus=launch
 return gui.Panel{width=300,height="auto",flow="vertical",children={label("SESSIONLAB",276,24,"#B3A9FF"),label("\208\154\208\190\208\188\208\189\208\176\209\130\208\176 \208\184 \208\184\208\189\208\184\209\134\208\184\208\176\209\130\208\184\208\178\208\176",276,16),button("\208\158\209\130\208\186\209\128\209\139\209\130\209\140 \208\186\208\190\208\188\208\189\208\176\209\130\209\131",276,openWindow),launch},destroy=function() if S.launchStatus==launch then S.launchStatus=nil end end}
end}
print("SessionLab room loaded \194\183 /slroom")
-- End.
