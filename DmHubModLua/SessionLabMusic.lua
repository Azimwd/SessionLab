-- SessionLab Audio. ASCII-safe DMHub Main.
-- SessionLab Audio. Uses DMHub's uploaded audio and native shared playback.
-- Install as a NEW mod. No URL, tokens, backend, or changes to system mods.
local mod=dmhub.GetModLoading()
local old=rawget(_G,"SessionLabAudioRuntime")
if old then old.active=false if old.window then pcall(function() old.window:DestroySelf() end) end end
local S={active=true,panels={},folder="*",query="",tab="library",status="\208\147\208\190\209\130\208\190\208\178\208\190",uploading=false}
_G.SessionLabAudioRuntime=S
setting{id="sessionlab_audio_favorites_v1",storage="preference",default={}}
setting{id="sessionlab_audio_unmuted_volume_v1",storage="preference",default=100}
local DEFAULT_FOLDER="-MyddEFnH5IOto7qCx-3"
local W=344
local function isMaster() return dmhub.isDM==true end
local function fold(s)
 s=string.lower(tostring(s or ""))
 local a,b="\208\144\208\145\208\146\208\147\208\148\208\149\208\129\208\150\208\151\208\152\208\153\208\154\208\155\208\156\208\157\208\158\208\159\208\160\208\161\208\162\208\163\208\164\208\165\208\166\208\167\208\168\208\169\208\170\208\171\208\172\208\173\208\174\208\175","\208\176\208\177\208\178\208\179\208\180\208\181\209\145\208\182\208\183\208\184\208\185\208\186\208\187\208\188\208\189\208\190\208\191\209\128\209\129\209\130\209\131\209\132\209\133\209\134\209\135\209\136\209\137\209\138\209\139\209\140\209\141\209\142\209\143"
 for i=1,#a,2 do s=s:gsub(a:sub(i,i+1),b:sub(i,i+1)) end
 return s
end
local function clean(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
local function clip(id) return id and assets.audioTable[id] end
local function folderOf(a) return a.parentFolder or DEFAULT_FOLDER end
local function folderName(id)
 local f=assets.audioFoldersTable[id]
 return f and not f.hidden and (f.description or "\208\159\208\176\208\191\208\186\208\176") or "\208\145\208\181\208\183 \208\191\208\176\208\191\208\186\208\184"
end
local function time(n)
 n=math.max(0,math.floor(tonumber(n) or 0))
 return string.format("%d:%02d",math.floor(n/60),n%60)
end
local function playing() return audio.currentlyPlaying or {} end
local function favorites() return dmhub.GetSettingValue("sessionlab_audio_favorites_v1") or {} end
local function shared() return mod:GetDocumentSnapshot("sessionlab-audio-current-v1") end
local function currentId() local d=shared() return d and d.data and d.data.assetid end
local refreshAll
local function status(message)
 S.status=message
 if refreshAll then refreshAll(false) end
end
local function guarded(fn)
 if not isMaster() then status("\208\163\208\191\209\128\208\176\208\178\208\187\208\181\208\189\208\184\208\181 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\190 \209\130\208\190\208\187\209\140\208\186\208\190 \208\188\208\176\209\129\209\130\208\181\209\128\209\131") return end
 local ok,err=pcall(fn)
 if not ok then status("\208\158\209\136\208\184\208\177\208\186\208\176 DMHub: "..tostring(err):sub(1,150)) end
end
local function sortedTracks(folder,query,tab)
 local rows={} local q=fold(query) local fav=favorites() local active=playing()
 for id,a in pairs(assets.audioTable or {}) do
  if not a.hidden and (folder=="*" or folderOf(a)==folder or (folder=="?" and not assets.audioFoldersTable[folderOf(a)]))
   and (tab~="favorites" or fav[id]) and (tab~="playing" or active[id])
   and (q=="" or fold((a.description or "").." "..folderName(folderOf(a))):find(q,1,true)) then
   rows[#rows+1]={id=id,asset=a}
  end
 end
 table.sort(rows,function(a,b)
  local x,y=fold(a.asset.description),fold(b.asset.description)
  if x==y then return tostring(a.id)<tostring(b.id) end return x<y
 end)
 return rows
end
local function stopTrack(id)
 guarded(function()
  if id then audio.StopSoundEvent(id) end
  status("\208\146\208\190\209\129\208\191\209\128\208\190\208\184\208\183\208\178\208\181\208\180\208\181\208\189\208\184\208\181 \208\190\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\190")
 end)
end
local function playTrack(id)
 guarded(function()
  local a=clip(id)
  if not a or a.hidden then status("\208\162\209\128\208\181\208\186 \208\189\208\181\208\180\208\190\209\129\209\130\209\131\208\191\208\181\208\189 \226\128\148 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\208\181 \208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\209\131") return end
  local previous=currentId()
  local started=audio.PlaySoundEvent{asset=a,volume=1}
  if not started then status("DMHub \208\189\208\181 \208\183\208\176\208\191\209\131\209\129\209\130\208\184\208\187 \209\130\209\128\208\181\208\186. \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\180\208\190\209\129\209\130\209\131\208\191\208\189\208\190\209\129\209\130\209\140 \208\176\209\131\208\180\208\184\208\190\209\132\208\176\208\185\208\187\208\176.") return end
  -- Stop only this mod's previous music. Other ambience/effects keep playing.
  if previous and previous~=id and playing()[previous] then audio.StopSoundEvent(previous) end
  local d=shared() d:BeginChange() d.data.assetid=id d.data.folder=folderOf(a) d:CompleteChange("SessionLab: select music")
  S.selected=id S.playFolder=folderOf(a)
  status("\208\152\208\179\209\128\208\176\208\181\209\130: "..tostring(a.description or "\208\145\208\181\208\183 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\209\143"))
 end)
end
local function step(direction)
 guarded(function()
  local id=currentId() local a=clip(id)
  local folder=(a and folderOf(a)) or S.playFolder or S.folder
  local rows=sortedTracks(folder,"","library")
  if #rows==0 then status("\208\146 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130\208\181 \208\189\208\181\209\130 \209\130\209\128\208\181\208\186\208\190\208\178") return end
  local index=direction==1 and 0 or 1
  for i,row in ipairs(rows) do if row.id==id then index=i break end end
  playTrack(rows[((index-1+direction)%#rows)+1].id)
 end)
end
-- The engine's audio.masterVolume and UploadMasterVolume are SHARED controls.
-- Use the native per-user preference (0..100); never upload a player's mix.
local function personalVolume()
 return math.max(0,math.min(100,tonumber(dmhub.GetSettingValue("volume")) or 100))
end
local function persistVolume(value)
 value=math.max(0,math.min(1,tonumber(value) or 0))*100
 dmhub.SetSettingValue("volume",value)
 if value>0 then dmhub.SetSettingValue("sessionlab_audio_unmuted_volume_v1",value) end
end
local function favorite(id)
 local values={} for k,v in pairs(favorites()) do if v then values[k]=true end end
 values[id]=not values[id]
 dmhub.SetSettingValue("sessionlab_audio_favorites_v1",values)
 refreshAll(true)
end
local function label(text,width,size,color)
 return gui.Label{text=text or "",width=width or W,height="auto",fontSize=size or 14,color=color or "#F4F5F7",interactable=false,vmargin=3}
end
local function panel(children,width,height)
 return gui.Panel{width=width or W,height=height or "auto",flow="vertical",halign="center",children=children,interactable=false}
end
local function row(children,width)
 return gui.Panel{width=width or W,height="auto",flow="horizontal",children=children,interactable=false}
end
local function button(text,width,fn,accent,disabled)
 return gui.Button{text=text,width=width,height=34,fontSize=13,bgimage="panels/square.png",bgcolor=accent and "#695CF5ff" or "#232833ff",color="#F4F5F7",cornerRadius=6,borderWidth=1,borderColor="#303642ff",vmargin=3,hmargin=2,classes={accent and "sla-accent" or "sla-button"},interactable=not disabled,
  press=function() if S.active and not disabled then fn() end end}
end
local function input(value,width,placeholder,edit)
 return gui.Input{text=value or "",width=width,height=34,fontSize=13,placeholderText=placeholder,classes={"sla-input"},vmargin=3,
  edit=function(e) edit(e.text or "") end,change=function(e) edit(e.text or "") end}
end
local function signature()
 local parts={}
 for id,a in pairs(assets.audioTable or {}) do parts[#parts+1]=table.concat({tostring(id),tostring(a.description),tostring(a.parentFolder),tostring(a.hidden),tostring(a.loop),tostring(a.duration)},"|") end
 for id,f in pairs(assets.audioFoldersTable or {}) do parts[#parts+1]=tostring(id).."|"..tostring(f.description).."|"..tostring(f.hidden) end
 table.sort(parts) return table.concat(parts,"\n")
end
local function activeSignature()
 local ids={} for id in pairs(playing()) do ids[#ids+1]=tostring(id) end table.sort(ids)
 return table.concat(ids,"|").."/"..tostring(currentId())
end
local function uploadFiles(paths)
 guarded(function()
  if S.uploading then status("\208\148\208\190\208\182\208\180\208\184\209\130\208\181\209\129\209\140 \208\183\208\176\208\178\208\181\209\128\209\136\208\181\208\189\208\184\209\143 \208\183\208\176\208\179\209\128\209\131\208\183\208\186\208\184") return end
  if not paths or #paths==0 then return end
  S.uploading=true local completed,failed=0,0 local done={}
  local function finish(index,errorText)
   if done[index] then return end done[index]=true completed=completed+1
   if errorText then failed=failed+1 end
   S.status="\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176: "..completed.." / "..#paths..(failed>0 and " \194\183 \208\190\209\136\208\184\208\177\208\190\208\186: "..failed or "")
   if completed==#paths then S.uploading=false S.status=failed==0 and "\208\164\208\176\208\185\208\187\209\139 \208\183\208\176\208\179\209\128\209\131\208\182\208\181\208\189\209\139. \208\152\209\137\208\184\209\130\208\181 \208\184\209\133 \208\178 \208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\208\181." or "\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176 \208\183\208\176\208\178\208\181\209\128\209\136\208\181\208\189\208\176. \208\158\209\136\208\184\208\177\208\190\208\186: "..failed end
   refreshAll(completed==#paths)
  end
  for i,path in ipairs(paths) do
   local index=i
   local ok,err=pcall(function() assets:UploadAudioAsset{path=path,upload=function() finish(index) end,error=function(e) finish(index,e) end} end)
   if not ok then finish(index,err) end
  end
 end)
end
local function chooseFiles()
 guarded(function()
  dmhub.OpenFileDialog{id="SessionLabAudioImport",extensions={"ogg","mp3","wav","flac"},multiFiles=true,prompt="\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\176\209\131\208\180\208\184\208\190\209\132\208\176\208\185\208\187\209\139",openFiles=uploadFiles}
 end)
end
local function createPanel(options)
 options=options or {}
 local wide=options.wide or false
 local CW=options.width or 344
 local FW=wide and 210 or CW
 local W=wide and CW-FW-20 or CW
 local VW=wide and 260 or W
 local TH=wide and math.max(160,(options.height or 700)-430) or 310
 local titleWidth=wide and CW-284 or W
 local p={folder="*",query="",tab="library",rows={},selected=nil,editing=false,assetsSig="",activeSig=""}
 local root,renderLibrary,renderFolders,renderManager,updatePlayback
 local stateLabel=label("",W,12,"#A0A6B2")
 local nowTitle=label("\208\156\209\131\208\183\209\139\208\186\208\176 \208\189\208\181 \208\183\208\176\208\191\209\131\209\137\208\181\208\189\208\176",titleWidth,wide and 26 or 20)
 local nowMeta=label("",titleWidth,12,"#A0A6B2")
 local volumeText=label("\208\155\208\184\209\135\208\189\208\176\209\143 \208\179\209\128\208\190\208\188\208\186\208\190\209\129\209\130\209\140 DMHub",VW,12,"#A0A6B2")
 local muteButton
 muteButton=button(personalVolume()==0 and "\208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\183\208\178\209\131\208\186" or "\208\146\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\183\208\178\209\131\208\186",VW-4,function()
  if personalVolume()>0 then
   dmhub.SetSettingValue("sessionlab_audio_unmuted_volume_v1",personalVolume()) dmhub.SetSettingValue("volume",0)
  else dmhub.SetSettingValue("volume",tonumber(dmhub.GetSettingValue("sessionlab_audio_unmuted_volume_v1")) or 100) end
  updatePlayback()
 end)
 local slider=gui.Slider{width=VW,height=24,sliderWidth=VW-10,labelWidth=0,labelFormat="",minValue=0,maxValue=1,
  value=personalVolume()/100,
  preview=function(e) p.adjusting=true persistVolume(e.value) volumeText.text="\208\155\208\184\209\135\208\189\208\176\209\143 \208\179\209\128\208\190\208\188\208\186\208\190\209\129\209\130\209\140 DMHub \194\183 "..math.floor(e.value*100).."%" end,
  confirm=function(e) persistVolume(e.value) p.adjusting=false updatePlayback() end}
 local folders=gui.Panel{width=FW,height=wide and TH+100 or 112,flow="vertical",vscroll=true,clip=true}
 local tracks=gui.Panel{width=W,height=TH,flow="vertical",vscroll=true,clip=true}
 local manager=panel({},W)
 local managerScroll=gui.Panel{width=W,height=TH,flow="vertical",vscroll=true,clip=true,classes={"collapsed"},children={manager}}
 local countLabel=label("",W,12,"#A0A6B2")
 renderFolders=function()
  local values={{id="*",name="\208\146\209\129\208\181 \209\130\209\128\208\181\208\186\208\184"}}
  local counts={} local total=0 local unfiled=0
  for _,a in pairs(assets.audioTable or {}) do if not a.hidden then
   total=total+1 local f=folderOf(a) counts[f]=(counts[f] or 0)+1
   if not assets.audioFoldersTable[f] then unfiled=unfiled+1 end
  end end
  local known={}
  for id,f in pairs(assets.audioFoldersTable or {}) do if not f.hidden then known[#known+1]={id=id,name=f.description or "\208\159\208\176\208\191\208\186\208\176"} end end
  table.sort(known,function(a,b) return fold(a.name)<fold(b.name) end)
  for _,f in ipairs(known) do values[#values+1]=f end
  if unfiled>0 then values[#values+1]={id="?",name="\208\145\208\181\208\183 \208\191\208\176\208\191\208\186\208\184"} end
  local children={}
  for _,v in ipairs(values) do local f=v
   local n=f.id=="*" and total or (f.id=="?" and unfiled or counts[f.id] or 0)
   children[#children+1]=button(f.name.." \194\183 "..n,FW-20,function()
    p.folder=f.id renderFolders() renderLibrary()
   end,p.folder==f.id)
  end
  folders.children=children
 end
 renderManager=function()
  local W=W-20
  if wide then tracks:SetClass("collapsed",p.editing) managerScroll:SetClass("collapsed",not p.editing) end
  if not isMaster() or not p.editing then manager.children={} return end
  local a=clip(p.selected) local children={label("\208\163\208\159\208\160\208\144\208\146\208\155\208\149\208\157\208\152\208\149 \208\145\208\152\208\145\208\155\208\152\208\158\208\162\208\149\208\154\208\158\208\153",W,11,"#9085FF")}
  local name=""
  children[#children+1]=input("",W,"\208\157\208\190\208\178\209\139\208\185 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130, \208\189\208\176\208\191\209\128\208\184\208\188\208\181\209\128 \194\171\208\145\208\190\208\185\194\187",function(v) name=v end)
  children[#children+1]=button("\208\161\208\190\208\183\208\180\208\176\209\130\209\140 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130",W-4,function() guarded(function()
   local title=clean(name) if title=="" then status("\208\146\208\178\208\181\208\180\208\184\209\130\208\181 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130\208\176") return end
   assets:UploadNewAudioFolder{description=title} status("\208\159\208\187\208\181\208\185\208\187\208\184\209\129\209\130 \209\129\208\190\208\183\208\180\208\176\208\189: "..title) refreshAll(true)
  end) end)
  local selectedFolder=assets.audioFoldersTable[p.folder]
  if selectedFolder and not selectedFolder.hidden then
   local title=selectedFolder.description or ""
   children[#children+1]=input(title,W,"\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \209\130\208\181\208\186\209\131\209\137\208\181\208\179\208\190 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130\208\176",function(v) title=v end)
   children[#children+1]=button("\208\159\208\181\209\128\208\181\208\184\208\188\208\181\208\189\208\190\208\178\208\176\209\130\209\140 \208\191\208\187\208\181\208\185\208\187\208\184\209\129\209\130",W-4,function() guarded(function()
    if clean(title)=="" then status("\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \208\189\208\181 \208\188\208\190\208\182\208\181\209\130 \208\177\209\139\209\130\209\140 \208\191\209\131\209\129\209\130\209\139\208\188") return end
    selectedFolder.description=clean(title) selectedFolder:Upload() refreshAll(true)
   end) end)
  end
  if a and not a.hidden then
   local title=a.description or ""
   children[#children+1]=label("\208\162\209\128\208\181\208\186: "..title,W,13)
   children[#children+1]=input(title,W,"\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \209\130\209\128\208\181\208\186\208\176",function(v) title=v end)
   children[#children+1]=button("\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \209\130\209\128\208\181\208\186\208\176",W-4,function() guarded(function()
    if clean(title)=="" then status("\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181 \208\189\208\181 \208\188\208\190\208\182\208\181\209\130 \208\177\209\139\209\130\209\140 \208\191\209\131\209\129\209\130\209\139\208\188") return end
    a.description=clean(title) a:Upload() refreshAll(true)
   end) end)
   children[#children+1]=button(a.loop and "\208\159\208\190\208\178\209\130\208\190\209\128 \209\130\209\128\208\181\208\186\208\176: \208\178\208\186\208\187\209\142\209\135\209\145\208\189" or "\208\159\208\190\208\178\209\130\208\190\209\128 \209\130\209\128\208\181\208\186\208\176: \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189",W-4,function() guarded(function()
    a.loop=not a.loop a:Upload() refreshAll(true)
   end) end)
   children[#children+1]=label("\208\159\208\181\209\128\208\181\208\189\208\181\209\129\209\130\208\184 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\209\139\208\185 \209\130\209\128\208\181\208\186:",W,12,"#A0A6B2")
   local destinations={}
   for id,f in pairs(assets.audioFoldersTable or {}) do if not f.hidden and id~=folderOf(a) then destinations[#destinations+1]={id=id,name=f.description or "\208\159\208\176\208\191\208\186\208\176"} end end
   table.sort(destinations,function(x,y) return fold(x.name)<fold(y.name) end)
   local moves={}
   for _,f in ipairs(destinations) do local destination=f
    moves[#moves+1]=button(destination.name,W-20,function() guarded(function()
     a.parentFolder=destination.id a:Upload() status("\208\162\209\128\208\181\208\186 \208\191\208\181\209\128\208\181\208\189\208\181\209\129\209\145\208\189: "..destination.name) refreshAll(true)
    end) end)
   end
   children[#children+1]=gui.Panel{width=W,height=90,vscroll=true,flow="vertical",children=moves}
  else children[#children+1]=label("\208\157\208\176\208\182\208\188\208\184\209\130\208\181 \194\171\226\128\166\194\187 \209\131 \209\130\209\128\208\181\208\186\208\176 \208\180\208\187\209\143 \209\128\208\181\208\180\208\176\208\186\209\130\208\184\209\128\208\190\208\178\208\176\208\189\208\184\209\143.",W,12,"#A0A6B2") end
  children[#children+1]=button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140 \209\131\208\191\209\128\208\176\208\178\208\187\208\181\208\189\208\184\208\181",W-4,function() p.editing=false renderManager() end)
  manager.children=children
 end
 renderLibrary=function()
  local rows=sortedTracks(p.folder,p.query,p.tab) p.rows={}
  local children={} local fav=favorites() local active=playing()
  for _,entry in ipairs(rows) do
   local id,a=entry.id,entry.asset
   local title=label(a.description or "\208\145\208\181\208\183 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\209\143",isMaster() and W-140 or W-70,14)
   local meta=label(folderName(folderOf(a)).." \194\183 "..time(a.duration),isMaster() and W-140 or W-70,11,"#A0A6B2")
   local text=panel({title,meta},isMaster() and W-140 or W-70)
   local star=button(fav[id] and "\226\152\133" or "\226\152\134",34,function() favorite(id) end)
   local childrenRow={star,text}
   local play
   if isMaster() then
    play=button(active[id] and "\226\150\160" or "\226\150\182",34,function()
     if playing()[id] then stopTrack(id) else playTrack(id) end
    end,active[id]~=nil)
    childrenRow[#childrenRow+1]=play
    childrenRow[#childrenRow+1]=button("\226\128\166",30,function() p.selected=id p.editing=true renderManager() end)
   end
   local r=gui.Panel{width=W-18,height="auto",minHeight=62,flow="horizontal",bgimage="panels/square.png",bgcolor="#1A1E26ff",classes={"sla-track"},interactable=false,cornerRadius=8,borderWidth=1,borderColor="#303642ff",vmargin=4,children=childrenRow}
   r:SetClass("sla-playing",active[id]~=nil)
   p.rows[id]={panel=r,play=play,title=title,meta=meta,asset=a}
   children[#children+1]=r
  end
  if #children==0 then children[1]=label(p.tab=="favorites" and "\208\148\208\190\208\177\208\176\208\178\208\187\209\143\208\185\209\130\208\181 \209\130\209\128\208\181\208\186\208\184 \208\183\208\178\209\145\208\183\208\180\208\190\209\135\208\186\208\190\208\185 \226\152\134" or (p.tab=="playing" and "\208\161\208\181\208\185\209\135\208\176\209\129 \208\189\208\184\209\135\208\181\208\179\208\190 \208\189\208\181 \208\184\208\179\209\128\208\176\208\181\209\130" or "\208\162\209\128\208\181\208\186\208\184 \208\189\208\181 \208\189\208\176\208\185\208\180\208\181\208\189\209\139"),W-18,14,"#A0A6B2") end
  tracks.children=children countLabel.text="\208\162\209\128\208\181\208\186\208\190\208\178: "..#rows
 end
 updatePlayback=function()
  local active=playing() local id=currentId() local a=clip(id) local sound=id and active[id]
  if a and sound then
   nowTitle.text=a.description or "\208\145\208\181\208\183 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\209\143"
   nowMeta.text=folderName(folderOf(a)).." \194\183 "..time(sound.time).." / "..time(a.duration)..(a.loop and " \194\183 \208\191\208\190\208\178\209\130\208\190\209\128" or "")
  else
   local n=0 for _ in pairs(active) do n=n+1 end
   nowTitle.text=n>0 and "\208\152\208\179\209\128\208\176\208\181\209\130 \208\183\208\178\209\131\208\186 DMHub" or "\208\156\209\131\208\183\209\139\208\186\208\176 \208\189\208\181 \208\183\208\176\208\191\209\131\209\137\208\181\208\189\208\176"
   nowMeta.text=n>0 and ("\208\144\208\186\209\130\208\184\208\178\208\189\209\139\209\133 \208\183\208\178\209\131\208\186\208\190\208\178: "..n.." \194\183 \208\178\208\186\208\187\208\176\208\180\208\186\208\176 \194\171\208\152\208\179\209\128\208\176\208\181\209\130\194\187") or "\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \209\130\209\128\208\181\208\186 \208\178 \208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\208\181"
  end
  for key,view in pairs(p.rows) do
   view.panel:SetClass("sla-playing",active[key]~=nil)
   if view.play then view.play.text=active[key] and "\226\150\160" or "\226\150\182" end
  end
  if not p.adjusting then
   local value=personalVolume()/100
   volumeText.text="\208\155\208\184\209\135\208\189\208\176\209\143 \208\179\209\128\208\190\208\188\208\186\208\190\209\129\209\130\209\140 DMHub \194\183 "..math.floor(value*100).."%"
   slider.value=value
  end
  muteButton.text=personalVolume()==0 and "\208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\183\208\178\209\131\208\186" or "\208\146\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\183\208\178\209\131\208\186"
  stateLabel.text=S.status
 end
 local search=input("",W,"\208\159\208\190\208\184\209\129\208\186 \208\191\208\190 \208\189\208\176\208\183\208\178\208\176\208\189\208\184\209\142 \208\184\208\187\208\184 \208\191\208\176\208\191\208\186\208\181",function(v) p.query=v renderLibrary() end)
 local tabs={}
 for _,v in ipairs({{"library","\208\145\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\208\176"},{"favorites","\208\152\208\183\208\177\209\128\208\176\208\189\208\189\208\190\208\181"},{"playing","\208\152\208\179\209\128\208\176\208\181\209\130"}}) do local tab=v
  tabs[#tabs+1]=button(tab[2],110,function() p.tab=tab[1] renderLibrary() end)
 end
 local transport
 if isMaster() then
  transport=row({button("\208\159\209\128\208\181\208\180\209\139\208\180\209\131\209\137\208\184\208\185",110,function() step(-1) end),button("\208\161\209\130\208\190\208\191",110,function() stopTrack(currentId()) end),button("\208\161\208\187\208\181\208\180\209\131\209\142\209\137\208\184\208\185",110,function() step(1) end)},math.min(W,titleWidth))
 else transport=label("\208\156\209\131\208\183\209\139\208\186\208\190\208\185 \209\131\208\191\209\128\208\176\208\178\208\187\209\143\208\181\209\130 \208\188\208\176\209\129\209\130\208\181\209\128",W,12,"#A0A6B2") end
 local tools={}
 if isMaster() then
  tools[#tools+1]=button("\208\151\208\176\208\179\209\128\209\131\208\183\208\184\209\130\209\140 \209\132\208\176\208\185\208\187\209\139",168,chooseFiles,true)
  tools[#tools+1]=button("\208\163\208\191\209\128\208\176\208\178\208\187\208\181\208\189\208\184\208\181",168,function() p.editing=not p.editing renderManager() end)
 end
 local children
 if wide then
  local hero=panel({label("\208\161\208\149\208\153\208\167\208\144\208\161 \208\152\208\147\208\160\208\144\208\149\208\162",titleWidth,11,"#9085FF"),nowTitle,nowMeta,transport},titleWidth)
  local volume=panel({volumeText,slider,muteButton},VW)
  local heading=row({hero,gui.Panel{width=24,height=1,interactable=false},volume},CW)
  local sidebar=panel({label("\208\159\208\155\208\149\208\153\208\155\208\152\208\161\208\162\208\171",FW,12,"#9085FF"),folders},FW)
  local library=panel({row(tabs,W),search,countLabel,tracks,managerScroll},W)
  local body=row({sidebar,gui.Panel{width=20,height=1,interactable=false},library},CW)
  tools[#tools+1]=button("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\209\140",110,function() refreshAll(true) end)
  children={heading,gui.Panel{width=CW,height=12,interactable=false},body,row(tools,CW),stateLabel}
 else
  children={label("SESSIONLAB \194\183 \208\156\208\163\208\151\208\171\208\154\208\144",W,12,"#9085FF"),nowTitle,nowMeta,transport,volumeText,slider,muteButton,row(tabs,W),search,label("\208\159\208\155\208\149\208\153\208\155\208\152\208\161\208\162\208\171",W,11,"#A0A6B2"),folders,countLabel,tracks}
  if #tools>0 then children[#children+1]=row(tools,W) end
  children[#children+1]=button("\208\158\208\177\208\189\208\190\208\178\208\184\209\130\209\140 \208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\209\131",W-4,function() refreshAll(true) end)
  children[#children+1]=manager children[#children+1]=stateLabel
 end
 local function refresh(force)
  if not S.active or p.destroyed then return end
  local ok,err=pcall(function()
   local sig=force and signature() or p.assetsSig local changed=sig~=p.assetsSig
   local active=activeSignature() local activeChanged=active~=p.activeSig
   if force or changed then p.assetsSig=sig renderFolders() renderLibrary()
   elseif activeChanged and p.tab=="playing" then renderLibrary() end
   p.activeSig=active updatePlayback()
  end)
  if not ok then stateLabel.text="\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\190\208\177\208\189\208\190\208\178\208\184\209\130\209\140: "..tostring(err):sub(1,130) end
 end
 p.refresh=refresh
 root=gui.Panel{width=CW+24,height=wide and options.height or "auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  styles={
   {selectors={"sla-button"},bgimage="panels/square.png",bgcolor="#232833ff",color="#F4F5F7",borderWidth=1,borderColor="#303642ff",cornerRadius=6},
   {selectors={"sla-button","hover"},bgcolor="#303642ff"},
   {selectors={"sla-accent"},bgimage="panels/square.png",bgcolor="#695CF5ff",color="white",cornerRadius=6},
   {selectors={"sla-input"},bgimage="panels/square.png",bgcolor="#1A1E26ff",color="#F4F5F7",borderWidth=1,borderColor="#303642ff",cornerRadius=6},
   {selectors={"sla-track","sla-playing"},borderColor="#9085FFff",bgcolor="#232039ff"},
  },children=children,monitorAssets="audio",thinkTime=1,
  refreshAssets=function() refresh(true) end,refreshAudio=function() refresh(false) end,
  think=function() refresh(false) end,
  destroy=function() p.destroyed=true S.panels[p]=nil end}
 S.panels[p]=true
 refresh(true) audio.events:Listen(root)
 return root
end
refreshAll=function(force)
 for p in pairs(S.panels) do p.refresh(force) end
end
local function closeWindow()
 local window=S.window
 S.window=nil S.windowContent=nil
 if window then window:DestroySelf() end
end
local function openWindow()
 if S.window then return end
 local hud=rawget(_G,"GameHud")
 local host=hud and hud.instance and hud.instance.dialogWorldPanel
 if not host then S.status="\208\161\208\189\208\176\209\135\208\176\208\187\208\176 \208\190\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\184\208\179\209\128\208\190\208\178\208\190\208\185 \209\129\209\130\208\190\208\187 DMHub" refreshAll(false) return end
 local sx,sy=1280,960
 pcall(function() sx=dmhub.screenDimensions.x sy=dmhub.screenDimensions.y end)
 local ww=math.max(340,math.min(1180,math.floor(sx-80)))
 local wh=math.max(400,math.min(850,math.floor(sy-100)))
 local wide=ww>=880 and wh>=640
 local window
 local content=createPanel{wide=wide,width=ww-48,height=wh-76}
 S.windowContent=content
 local header=row({label("SESSIONLAB \194\183 \208\144\208\163\208\148\208\152\208\158",ww-174,19,"#9085FF"),button("\208\151\208\176\208\186\209\128\209\139\209\130\209\140",118,closeWindow)},ww-48)
 local viewport=gui.Panel{width=ww-24,height=wh-72,flow="vertical",halign="center",vscroll=not wide,clip=true,children={content}}
 window=gui.Panel{width=ww,height=wh,flow="vertical",halign="center",valign="center",floating=true,constrainToScreen=true,draggable=true,
  bgimage="panels/square.png",bgcolor="#101217ff",borderWidth=1,borderColor="#303642ff",cornerRadius=12,
  drag=function(e) e.x=e.xdrag e.y=e.ydrag end,
  destroy=function() if S.window==window then S.window=nil S.windowContent=nil end end,
  children={gui.Panel{width=ww,height=10,interactable=false},header,viewport}}
 S.window=window host:AddChild(window)
end
DockablePanel.Register{name="SessionLab \194\183 \208\188\209\131\208\183\209\139\208\186\208\176",minWidth=300,maxWidth=420,vscroll=true,content=function()
 return gui.Panel{width=288,height="auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  children={label("SessionLab \194\183 \208\188\209\131\208\183\209\139\208\186\208\176",264,23,"#9085FF"),label("\208\159\208\187\208\181\208\185\208\187\208\184\209\129\209\130\209\139 \208\184 \208\191\208\187\208\181\208\181\209\128 \208\178 \208\190\209\130\208\180\208\181\208\187\209\140\208\189\208\190\208\188 \208\190\208\186\208\189\208\181",264,14,"#A0A6B2"),
   button("\208\158\209\130\208\186\209\128\209\139\209\130\209\140 \208\191\208\187\208\181\208\181\209\128",260,openWindow,true)}}
end}
-- End.
