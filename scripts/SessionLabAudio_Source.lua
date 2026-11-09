-- SessionLab Audio. Uses DMHub's uploaded audio and native shared playback.
-- Install as a NEW mod. No URL, tokens, backend, or changes to system mods.
local mod=dmhub.GetModLoading()
local old=rawget(_G,"SessionLabAudioRuntime")
if old then old.active=false if old.window then pcall(function() old.window:DestroySelf() end) end end
local S={active=true,panels={},folder="*",query="",tab="library",status="Готово",uploading=false}
_G.SessionLabAudioRuntime=S
setting{id="sessionlab_audio_favorites_v1",storage="preference",default={}}
setting{id="sessionlab_audio_unmuted_volume_v1",storage="preference",default=100}
local DEFAULT_FOLDER="-MyddEFnH5IOto7qCx-3"
local W=344
local function isMaster() return dmhub.isDM==true end
local function fold(s)
 s=string.lower(tostring(s or ""))
 local a,b="АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ","абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
 for i=1,#a,2 do s=s:gsub(a:sub(i,i+1),b:sub(i,i+1)) end
 return s
end
local function clean(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
local function clip(id) return id and assets.audioTable[id] end
local function folderOf(a) return a.parentFolder or DEFAULT_FOLDER end
local function folderName(id)
 local f=assets.audioFoldersTable[id]
 return f and not f.hidden and (f.description or "Папка") or "Без папки"
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
 if not isMaster() then status("Управление доступно только мастеру") return end
 local ok,err=pcall(fn)
 if not ok then status("Ошибка DMHub: "..tostring(err):sub(1,150)) end
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
  status("Воспроизведение остановлено")
 end)
end
local function playTrack(id)
 guarded(function()
  local a=clip(id)
  if not a or a.hidden then status("Трек недоступен — обновите библиотеку") return end
  local previous=currentId()
  local started=audio.PlaySoundEvent{asset=a,volume=1}
  if not started then status("DMHub не запустил трек. Проверьте доступность аудиофайла.") return end
  -- Stop only this mod's previous music. Other ambience/effects keep playing.
  if previous and previous~=id and playing()[previous] then audio.StopSoundEvent(previous) end
  local d=shared() d:BeginChange() d.data.assetid=id d.data.folder=folderOf(a) d:CompleteChange("SessionLab: select music")
  S.selected=id S.playFolder=folderOf(a)
  status("Играет: "..tostring(a.description or "Без названия"))
 end)
end
local function step(direction)
 guarded(function()
  local id=currentId() local a=clip(id)
  local folder=(a and folderOf(a)) or S.playFolder or S.folder
  local rows=sortedTracks(folder,"","library")
  if #rows==0 then status("В плейлисте нет треков") return end
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
local function label(text,width,size,color,height)
 return gui.Label{text=text or "",width=width or W,height=height or "auto",fontSize=size or 14,color=color or "#F4F5F7",interactable=false,vmargin=3}
end
local function panel(children,width,height,valign)
 return gui.Panel{width=width or W,height=height or "auto",flow="vertical",halign="center",valign=valign,children=children,interactable=false}
end
local function row(children,width,height,halign,cursor)
 return gui.Panel{width=width or W,height=height or "auto",halign=halign,hoverCursor=cursor,flow="horizontal",children=children,interactable=false}
end
local function button(text,width,fn,accent,disabled)
 return gui.Button{text=text,width=width,height=34,fontSize=13,hoverCursor="default",valign="center",bgimage="panels/square.png",bgcolor=accent and "#695CF5ff" or "#232833ff",color="#F4F5F7",cornerRadius=6,borderWidth=1,borderColor="#303642ff",vmargin=3,hmargin=2,classes={accent and "sla-accent" or "sla-button"},interactable=not disabled,
  press=function() if S.active and not disabled then fn() end end}
end
local function input(value,width,placeholder,edit)
 return gui.Input{text=value or "",width=width,height=34,fontSize=13,hoverCursor="text",placeholderText=placeholder,classes={"sla-input"},vmargin=3,
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
  if S.uploading then status("Дождитесь завершения загрузки") return end
  if not paths or #paths==0 then return end
  S.uploading=true local completed,failed=0,0 local done={}
  local function finish(index,errorText)
   if done[index] then return end done[index]=true completed=completed+1
   if errorText then failed=failed+1 end
   S.status="Загрузка: "..completed.." / "..#paths..(failed>0 and " · ошибок: "..failed or "")
   if completed==#paths then S.uploading=false S.status=failed==0 and "Файлы загружены. Ищите их в библиотеке." or "Загрузка завершена. Ошибок: "..failed end
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
  dmhub.OpenFileDialog{id="SessionLabAudioImport",extensions={"ogg","mp3","wav","flac"},multiFiles=true,prompt="Выберите аудиофайлы",openFiles=uploadFiles}
 end)
end
local function createPanel(options)
 options=options or {}
 local wide=options.wide or false
 local CW=options.width or 344
 local FW=wide and 210 or CW
 local W=wide and CW-FW-20 or CW
 local VW=wide and 260 or W
 local BH=wide and (options.height-228) or 0
 local TH=wide and BH-106 or 310
 local titleWidth=wide and CW-284 or W
 local p={folder="*",query="",tab="library",rows={},selected=nil,editing=false,assetsSig="",activeSig=""}
 local root,renderLibrary,renderFolders,renderManager,updatePlayback
 local stateLabel=label("",wide and CW or W,12,"#A0A6B2",wide and 20 or nil)
 local nowTitle=label("Музыка не запущена",titleWidth,wide and 26 or 20,nil,wide and 34 or nil)
 local nowMeta=label("",titleWidth,12,"#A0A6B2",wide and 18 or nil)
 local volumeText=label("Личная громкость DMHub",VW,12,"#A0A6B2",wide and 18 or nil)
 local muteButton
 muteButton=button(personalVolume()==0 and "Включить звук" or "Выключить звук",VW-4,function()
  if personalVolume()>0 then
   dmhub.SetSettingValue("sessionlab_audio_unmuted_volume_v1",personalVolume()) dmhub.SetSettingValue("volume",0)
  else dmhub.SetSettingValue("volume",tonumber(dmhub.GetSettingValue("sessionlab_audio_unmuted_volume_v1")) or 100) end
  updatePlayback()
 end)
 local slider=gui.Slider{hoverCursor="default",width=VW,height=24,sliderWidth=VW-10,labelWidth=0,labelFormat="",minValue=0,maxValue=1,
  value=personalVolume()/100,
  preview=function(e) p.adjusting=true persistVolume(e.value) volumeText.text="Личная громкость DMHub · "..math.floor(e.value*100).."%" end,
  confirm=function(e) persistVolume(e.value) p.adjusting=false updatePlayback() end}
 local folders=gui.Panel{width=FW,height=wide and BH-26 or 112,flow="vertical",vscroll=true,clip=true,bgimage="panels/square.png",bgcolor="#101217ff",clipHidden=true,scrollHandleColor="#695CF5ff"}
 local tracks=gui.Panel{width=W,height=TH,flow="vertical",vscroll=true,clip=true,bgimage="panels/square.png",bgcolor="#101217ff",clipHidden=true,scrollHandleColor="#695CF5ff"}
 local manager=panel({},W)
 local managerScroll=gui.Panel{width=W,height=TH,flow="vertical",vscroll=true,clip=true,bgimage="panels/square.png",bgcolor="#101217ff",clipHidden=true,scrollHandleColor="#695CF5ff",classes={"collapsed"},children={manager}}
 local countLabel=label("",W,12,"#A0A6B2",wide and 20 or nil)
 renderFolders=function()
  local values={{id="*",name="Все треки"}}
  local counts={} local total=0 local unfiled=0
  for _,a in pairs(assets.audioTable or {}) do if not a.hidden then
   total=total+1 local f=folderOf(a) counts[f]=(counts[f] or 0)+1
   if not assets.audioFoldersTable[f] then unfiled=unfiled+1 end
  end end
  local known={}
  for id,f in pairs(assets.audioFoldersTable or {}) do if not f.hidden then known[#known+1]={id=id,name=f.description or "Папка"} end end
  table.sort(known,function(a,b) return fold(a.name)<fold(b.name) end)
  for _,f in ipairs(known) do values[#values+1]=f end
  if unfiled>0 then values[#values+1]={id="?",name="Без папки"} end
  local children={}
  for _,v in ipairs(values) do local f=v
   local n=f.id=="*" and total or (f.id=="?" and unfiled or counts[f.id] or 0)
   children[#children+1]=button(f.name.." · "..n,FW-20,function()
    p.folder=f.id renderFolders() renderLibrary()
   end,p.folder==f.id)
  end
  folders.children=children
 end
 renderManager=function()
  local W=W-20
  if wide then tracks:SetClass("collapsed",p.editing) managerScroll:SetClass("collapsed",not p.editing) end
  if not isMaster() or not p.editing then manager.children={} return end
  local a=clip(p.selected) local children={label("УПРАВЛЕНИЕ БИБЛИОТЕКОЙ",W,11,"#9085FF")}
  local name=""
  children[#children+1]=input("",W,"Новый плейлист, например «Бой»",function(v) name=v end)
  children[#children+1]=button("Создать плейлист",W-4,function() guarded(function()
   local title=clean(name) if title=="" then status("Введите название плейлиста") return end
   assets:UploadNewAudioFolder{description=title} status("Плейлист создан: "..title) refreshAll(true)
  end) end)
  local selectedFolder=assets.audioFoldersTable[p.folder]
  if selectedFolder and not selectedFolder.hidden then
   local title=selectedFolder.description or ""
   children[#children+1]=input(title,W,"Название текущего плейлиста",function(v) title=v end)
   children[#children+1]=button("Переименовать плейлист",W-4,function() guarded(function()
    if clean(title)=="" then status("Название не может быть пустым") return end
    selectedFolder.description=clean(title) selectedFolder:Upload() refreshAll(true)
   end) end)
  end
  if a and not a.hidden then
   local title=a.description or ""
   children[#children+1]=label("Трек: "..title,W,13)
   children[#children+1]=input(title,W,"Название трека",function(v) title=v end)
   children[#children+1]=button("Сохранить название трека",W-4,function() guarded(function()
    if clean(title)=="" then status("Название не может быть пустым") return end
    a.description=clean(title) a:Upload() refreshAll(true)
   end) end)
   children[#children+1]=button(a.loop and "Повтор трека: включён" or "Повтор трека: выключен",W-4,function() guarded(function()
    a.loop=not a.loop a:Upload() refreshAll(true)
   end) end)
   children[#children+1]=label("Перенести выбранный трек:",W,12,"#A0A6B2")
   local destinations={}
   for id,f in pairs(assets.audioFoldersTable or {}) do if not f.hidden and id~=folderOf(a) then destinations[#destinations+1]={id=id,name=f.description or "Папка"} end end
   table.sort(destinations,function(x,y) return fold(x.name)<fold(y.name) end)
   local moves={}
   for _,f in ipairs(destinations) do local destination=f
    moves[#moves+1]=button(destination.name,W-20,function() guarded(function()
     a.parentFolder=destination.id a:Upload() status("Трек перенесён: "..destination.name) refreshAll(true)
    end) end)
   end
   children[#children+1]=gui.Panel{width=W,height=90,vscroll=true,flow="vertical",children=moves}
  else children[#children+1]=label("Нажмите «...» у трека для редактирования.",W,12,"#A0A6B2") end
  children[#children+1]=button("Закрыть управление",W-4,function() p.editing=false renderManager() end)
  manager.children=children
 end
 renderLibrary=function()
  local rows=sortedTracks(p.folder,p.query,p.tab) p.rows={}
  local children={} local fav=favorites() local active=playing()
  for _,entry in ipairs(rows) do
   local id,a=entry.id,entry.asset
   local title=label(a.description or "Без названия",isMaster() and W-196 or W-90,14,nil,20)
   local meta=label(folderName(folderOf(a)).." · "..time(a.duration),isMaster() and W-196 or W-90,11,"#A0A6B2",16)
   local text=panel({title,meta},isMaster() and W-196 or W-90,nil,"center")
   local star=button("Избр.",52,function() favorite(id) end,fav[id]==true)
   local childrenRow={star,text}
   local play
   if isMaster() then
    play=button(active[id] and "Стоп" or "Пуск",66,function()
     if playing()[id] then stopTrack(id) else playTrack(id) end
    end,active[id]~=nil)
    childrenRow[#childrenRow+1]=play
    childrenRow[#childrenRow+1]=button("...",28,function() p.selected=id p.editing=true renderManager() end)
   end
   local r=gui.Panel{width=W-18,height=66,minHeight=66,hpad=6,flow="horizontal",bgimage="panels/square.png",bgcolor="#1A1E26ff",classes={"sla-track"},interactable=false,cornerRadius=8,borderWidth=1,borderColor="#303642ff",vmargin=4,children=childrenRow}
   r:SetClass("sla-playing",active[id]~=nil)
   p.rows[id]={panel=r,play=play,title=title,meta=meta,asset=a}
   children[#children+1]=r
  end
  if #children==0 then children[1]=label(p.tab=="favorites" and "Добавляйте треки кнопкой «Избр.»" or (p.tab=="playing" and "Сейчас ничего не играет" or "Треки не найдены"),W-18,14,"#A0A6B2") end
  tracks.children=children countLabel.text="Треков: "..#rows
 end
 updatePlayback=function()
  local active=playing() local id=currentId() local a=clip(id) local sound=id and active[id]
  if a and sound then
   nowTitle.text=a.description or "Без названия"
   nowMeta.text=folderName(folderOf(a)).." · "..time(sound.time).." / "..time(a.duration)..(a.loop and " · повтор" or "")
  else
   local n=0 for _ in pairs(active) do n=n+1 end
   nowTitle.text=n>0 and "Играет звук DMHub" or "Музыка не запущена"
   nowMeta.text=n>0 and ("Активных звуков: "..n.." · вкладка «Играет»") or "Выберите трек в библиотеке"
  end
  for key,view in pairs(p.rows) do
   view.panel:SetClass("sla-playing",active[key]~=nil)
   if view.play then view.play.text=active[key] and "Стоп" or "Пуск" end
  end
  if not p.adjusting then
   local value=personalVolume()/100
   volumeText.text="Личная громкость DMHub · "..math.floor(value*100).."%"
   slider.value=value
  end
  muteButton.text=personalVolume()==0 and "Включить звук" or "Выключить звук"
  stateLabel.text=S.status
 end
 local search=input("",W,"Поиск по названию или папке",function(v) p.query=v renderLibrary() end)
 local tabs={}
 for _,v in ipairs({{"library","Библиотека"},{"favorites","Избранное"},{"playing","Играет"}}) do local tab=v
  local tabButton
  tabButton=button(tab[2],110,function()
   p.tab=tab[1]
   for _,b in ipairs(tabs) do b:SetClass("sla-selected",b==tabButton) end
   renderLibrary()
  end)
  tabButton:SetClass("sla-selected",p.tab==tab[1]) tabs[#tabs+1]=tabButton
 end
 local transport
 if isMaster() then
  transport=row({button("Предыдущий",110,function() step(-1) end),button("Стоп",110,function() stopTrack(currentId()) end),button("Следующий",110,function() step(1) end)},math.min(W,titleWidth))
 else transport=label("Музыкой управляет мастер",W,12,"#A0A6B2") end
 local tools={}
 if isMaster() then
  tools[#tools+1]=button("Загрузить файлы",168,chooseFiles,true)
  tools[#tools+1]=button("Управление",168,function() p.editing=not p.editing renderManager() end)
 end
 local children
 if wide then
  local hero=panel({label("СЕЙЧАС ИГРАЕТ",titleWidth,11,"#9085FF"),nowTitle,nowMeta,transport},titleWidth,124)
  local volume=panel({volumeText,slider,muteButton},VW,124)
  local heading=row({hero,gui.Panel{width=24,height=1,interactable=false},volume},CW,124)
  local folderTitle=label("ПЛЕЙЛИСТЫ",FW,12,"#9085FF",20)
  local sidebar=panel({folderTitle,folders},FW,BH)
  local tabsRow=row(tabs,W,40)
  local library=panel({tabsRow,search,countLabel,tracks,managerScroll},W,BH)
  local body=row({sidebar,gui.Panel{width=20,height=1,interactable=false},library},CW,BH)
  tools[#tools+1]=button("Обновить",110,function() refreshAll(true) end)
  local footer=row(tools,CW,42)
  children={heading,gui.Panel{width=CW,height=12,interactable=false},body,footer,stateLabel}
 else
  children={label("SESSIONLAB · МУЗЫКА",W,12,"#9085FF"),nowTitle,nowMeta,transport,volumeText,slider,muteButton,row(tabs,W),search,label("ПЛЕЙЛИСТЫ",W,11,"#A0A6B2"),folders,countLabel,tracks}
  if #tools>0 then children[#children+1]=row(tools,W) end
  children[#children+1]=button("Обновить библиотеку",W-4,function() refreshAll(true) end)
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
  if not ok then stateLabel.text="Не удалось обновить: "..tostring(err):sub(1,130) end
 end
 p.refresh=refresh
 root=gui.Panel{width=CW+24,height=wide and options.height or "auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  styles={
   {selectors={"sla-button"},priority=100,bgimage="panels/square.png",bgcolor="#232833ff",color="#F4F5F7",borderWidth=1,borderColor="#303642ff",cornerRadius=6},
   {selectors={"sla-button","hover"},priority=110,bgcolor="#303642ff"},
   {selectors={"sla-accent","hover"},priority=110,bgcolor="#8071FFff",brightness=1.12},
   {selectors={"sla-accent"},priority=100,bgimage="panels/square.png",bgcolor="#695CF5ff",color="white",cornerRadius=6},
   {selectors={"sla-input"},bgimage="panels/square.png",bgcolor="#1A1E26ff",color="#F4F5F7",borderWidth=1,borderColor="#303642ff",cornerRadius=6},
   {selectors={"sla-button","sla-selected"},priority=105,bgcolor="#35304Dff",borderColor="#9085FFff"},
   {selectors={"sla-track","sla-playing"},priority=100,borderColor="#9085FFff",bgcolor="#232039ff"},
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
 if not host then S.status="Сначала откройте игровой стол DMHub" refreshAll(false) return end
 local sx,sy=1280,960
 pcall(function() sx=dmhub.screenDimensions.x sy=dmhub.screenDimensions.y end)
 local ww=math.max(340,math.min(1180,math.floor(sx-80)))
 local wh=math.max(400,math.min(850,math.floor(sy-100)))
 local wide=ww>=880 and wh>=640
 local window
 local content=createPanel{wide=wide,width=ww-48,height=wh-76}
 S.windowContent=content
 local header=row({label("SESSIONLAB · АУДИО",ww-174,19,"#9085FF"),button("Закрыть",118,closeWindow)},ww-48,42,"center","default")
 local viewport=gui.Panel{width=ww-24,height=wh-72,flow="vertical",halign="center",hpad=0,vpad=0,hmargin=0,vmargin=0,vscroll=not wide,clip=true,children={content}}
 window=gui.Panel{width=ww,height=wh,hpad=0,vpad=0,hmargin=0,vmargin=0,flow="vertical",halign="center",valign="center",floating=true,constrainToScreen=true,draggable=true,
  bgimage="panels/square.png",bgcolor="#101217ff",borderWidth=1,borderColor="#303642ff",cornerRadius=12,
  drag=function(e) e.x=e.xdrag e.y=e.ydrag end,
  destroy=function() if S.window==window then S.window=nil S.windowContent=nil end end,
  children={gui.Panel{width=ww,height=10,interactable=false},header,viewport}}
 S.window=window host:AddChild(window)
end
DockablePanel.Register{name="SessionLab · музыка",minWidth=300,maxWidth=420,vscroll=true,content=function()
 return gui.Panel{width=288,height="auto",flow="vertical",halign="center",bgimage="panels/square.png",bgcolor="#101217ff",hpad=12,vpad=12,
  children={label("SessionLab · музыка",264,23,"#9085FF"),label("Плейлисты и плеер в отдельном окне",264,14,"#A0A6B2"),
   button("Открыть плеер",260,openWindow,true)}}
end}
-- End.
