-- lua scripts/tests/dmhub_audio_test.lua [installable Main path]
local source=(arg and arg[1]) or "scripts/SessionLabAudio_Main.lua"
local registers,documents,preferences,settings={},{},{volume=60},{}
local plays,stops,uploads,savedVolumes,savedMutes=0,0,0,0,0
local uploadCallback,mode,root
local role=true
local failPlay=false
local panels={}
local function ctor(kind)
 return function(props)
  assert(#props==0,"Use explicit children")
  assert(type(props.width)~="number" or props.width>=0)
  props.kind=kind props.children=props.children or {}
  local destroyed=false
  function props:SetClass(name,value) self.classesState=self.classesState or {} self.classesState[name]=value end
  function props:DestroySelf()
   if destroyed then return end if self.destroy then self.destroy(self) end
   for _,child in ipairs(self.children) do child:DestroySelf() end
   destroyed=true
  end
  -- Replaced subtrees are invalidated, like native userdata.
  local proxy={}
  return setmetatable(proxy,{__index=function(_,key) assert(not destroyed,"Destroyed userdata: "..key) return props[key] end,
   __newindex=function(_,key,value)
    assert(not destroyed,"Destroyed userdata setter: "..key)
    assert(key=="text" or key=="value" or key=="children" or key=="classesState","Unsupported native setter: "..key)
    if key=="children" then for _,child in ipairs(props.children) do child:DestroySelf() end end
    props[key]=value
   end})
 end
end
gui={Panel=ctor("panel"),Label=ctor("label"),Input=ctor("input"),Slider=ctor("slider"),Button=ctor("button")}
function setting(t) settings[t.id]=t if preferences[t.id]==nil then preferences[t.id]=t.default end end
local mod={}
function mod:GetDocumentSnapshot(id)
 if not documents[id] then
  documents[id]={data={},path="/mods/audio/"..id,BeginChange=function() assert(dmhub.isDM,"Player writes shared document") end,CompleteChange=function() assert(dmhub.isDM) end}
 end
 return documents[id]
end
dmhub={isDM=true,GetModLoading=function() return mod end,GetSettingValue=function(k) return preferences[k] end,SetSettingValue=function(k,v) preferences[k]=v end,
 OpenFileDialog=function(t) assert(dmhub.isDM) uploadCallback=t.openFiles end}
GameHud={instance={dialogWorldPanel={AddChild=function(_,w) assert(w.floating and w.constrainToScreen) end}}}
dmhub.screenDimensions={x=1440,y=1000}
DockablePanel={Register=function(t) registers[t.name]=t end}
audio={currentlyPlaying={},masterVolume=0.6,muted=false,events={Listen=function(_,p) panels[#panels+1]=p end},
 PlaySoundEvent=function(t) assert(dmhub.isDM,"Player starts sound") assert(t.asset.id) if failPlay then return nil end plays=plays+1 audio.currentlyPlaying[t.asset.id]={time=0} return t.asset.id end,
 StopSoundEvent=function(id) assert(dmhub.isDM,"Player stops sound") stops=stops+1 audio.currentlyPlaying[id]=nil end,
 UploadMasterVolume=function() error("Personal controls must not upload shared master volume") end,UploadMuted=function() error("Personal controls must not upload shared mute") end}
local function asset(id,title,folder)
 return {id=id,description=title,duration=90,parentFolder=folder,volume=1,Upload=function() assert(dmhub.isDM) uploads=uploads+1 end}
end
assets={audioTable={a=asset("a","Атмосфера","calm"),b=asset("b","Битва","combat"),c=asset("c","Дракон","combat"),hidden=asset("hidden","Секрет","combat")},
 audioFoldersTable={calm={description="Атмосфера"},combat={description="Бой"}}}
assets.audioTable.hidden.hidden=true
function assets:UploadNewAudioFolder(t) assert(dmhub.isDM) self.audioFoldersTable.new={description=t.description,Upload=function() uploads=uploads+1 end} end
function assets:UploadAudioAsset(t) assert(dmhub.isDM) if t.path=="bad.wav" then t.error("Invalid audio") else t.upload("new-asset") end end
local function walk(node,fn)
 fn(node) for _,child in ipairs(node.children or {}) do walk(child,fn) end
end
local function find(node,kind,text)
 local result walk(node,function(n) if n.kind==kind and n.text==text then result=result or n end end) return result
end
local function press(text,node)
 local b=assert(find(node or root,"button",text),"Missing button: "..text) assert(b.interactable~=false) b.press(b)
end
local function containing(text)
 local found
 walk(root,function(n) if n.classes and n.classes[1]=="sla-track" then
  if find(n,"label",text) then found=n end
 end end)
 return assert(found,"No track: "..text)
end
local function inputWith(placeholder)
 local found walk(root,function(n) if n.kind=="input" and n.placeholderText==placeholder then found=n end end) return assert(found,placeholder)
end
local function sliderOf(node)
 local found walk(node,function(n) if n.kind=="slider" then found=n end end) return assert(found)
end
local f=assert(io.open(source,"rb")) local code=f:read("*a") f:close()
assert(not code:find("[\128-\255]"),"Main must be ASCII-safe")
assert(load(code))()
local dock=assert(registers["SessionLab · музыка"])
assert(not dock.dmonly,"Players need their own volume controls")
local launcher=dock.content() press("Открыть плеер",launcher)
root=assert(SessionLabAudioRuntime.windowContent) assert(find(root,"label","Треков: 3"))
local used=2*(root.vpad or 0)
for _,child in ipairs(root.children) do used=used+child.height+2*(child.vmargin or 0) end
assert(type(root.height)=="number" and used==root.height,"Player must fill an explicitly bounded viewport")
walk(root,function(n)
 if n.kind=="button" and n.interactable~=false then assert(n.hoverCursor=="default","Buttons must keep the standard arrow cursor") end
 if n.kind=="button" then assert(n.text~="★" and n.text~="☆" and n.text~="▶" and n.text~="■","Unsupported icon glyph") end
end)
local window=SessionLabAudioRuntime.window
assert(window.draggable and not gui.ShowModal)
assert(type(window.height)=="number" and window.maxHeight==nil,"Floating window must not use auto/maxHeight layout")
assert(type(window.children[3].height)=="number","Viewport must have a numeric height")
local dragEvent={xdrag=40,ydrag=-20} window.drag(dragEvent) assert(dragEvent.x==40 and dragEvent.y==-20)
press("Открыть плеер",launcher) assert(SessionLabAudioRuntime.window==window,"Duplicate music window")
-- Open/repeated empty updates must preserve the list and search focus.
local first=containing("Битва")
for _=1,10 do root.think(root) end
assert(containing("Битва")==first,"Tick rebuilt library")
local query=inputWith("Поиск по названию или папке")
query.edit({text="БОЙ"}) assert(find(root,"label","Треков: 2"))
assert(not find(root,"label","Атмосфера"))
query.edit({text="["}) assert(find(root,"label","Треков: 0"),"Search must use literals")
query.edit({text=""})
-- Shared music switch preserves unrelated native ambience.
audio.currentlyPlaying.ambient={time=4}
press("Пуск",containing("Битва")) assert(plays==1 and audio.currentlyPlaying.b and currentId==nil)
local playingRow=containing("Битва")
root.think(root) assert(containing("Битва")==playingRow)
assert(documents["sessionlab-audio-current-v1"].data.assetid=="b")
press("Следующий") assert(audio.currentlyPlaying.c and not audio.currentlyPlaying.b and audio.currentlyPlaying.ambient)
press("Предыдущий") assert(audio.currentlyPlaying.b and not audio.currentlyPlaying.c)
-- A failed start must not stop the old track or change the shared selection.
failPlay=true local beforeStops=stops press("Следующий") failPlay=false
assert(audio.currentlyPlaying.b and stops==beforeStops and documents["sessionlab-audio-current-v1"].data.assetid=="b")
press("Стоп") assert(not audio.currentlyPlaying.b and audio.currentlyPlaying.ambient)
-- Favorite survives Main reload via preference, rather than transient runtime.
press("Избр.",containing("Битва")) assert(preferences.sessionlab_audio_favorites_v1.b)
press("Избранное") assert(find(root,"label","Треков: 1"))
press("Библиотека")
-- Existing folder structure and editable metadata use native assets.
press("Бой · 2") assert(find(root,"label","Треков: 2"))
press("...",containing("Битва"))
inputWith("Название трека").change({text="Новая битва"}) press("Сохранить название трека")
assert(assets.audioTable.b.description=="Новая битва")
press("...",containing("Новая битва")) press("Повтор трека: выключен") assert(assets.audioTable.b.loop)
press("...",containing("Новая битва")) press("Атмосфера") assert(assets.audioTable.b.parentFolder=="calm")
press("Управление") -- toggle current editor closed
press("Управление")
inputWith("Новый плейлист, например «Бой»").change({text="Таверна"}) press("Создать плейлист")
assert(assets.audioFoldersTable.new.description=="Таверна")
-- Mixed success/error import terminates; no forever-busy state.
press("Загрузить файлы") assert(uploadCallback) uploadCallback({"music.mp3","bad.wav"})
assert(not SessionLabAudioRuntime.uploading)
assert(SessionLabAudioRuntime.status:find("Ошибок: 1",1,true))
-- Local volume never changes sound-event volume or a shared document.
local nplay,nstop=plays,stops
local volume=sliderOf(root) volume.preview({value=0.2}) volume.confirm({value=0.2})
assert(preferences.volume==20 and audio.masterVolume==0.6 and plays==nplay and stops==nstop)
press("Выключить звук") assert(preferences.volume==0 and not audio.muted)
-- A player gets no transport, upload, or asset management controls.
local retainedNext=assert(find(root,"button","Следующий")).press
dmhub.isDM=false retainedNext() assert(plays==nplay and stops==nstop)
SessionLabAudioRuntime.window:DestroySelf()
press("Открыть плеер",launcher)
local player=assert(SessionLabAudioRuntime.windowContent)
assert(not find(player,"button","Следующий") and not find(player,"button","Загрузить файлы"))
assert(not find(player,"button","Управление") and not find(player,"button","Пуск"))
volume=sliderOf(player) volume.preview({value=0.4}) volume.confirm({value=0.4})
assert(preferences.volume==40 and audio.masterVolume==0.6 and not audio.muted and plays==nplay and stops==nstop)
-- Retained master UI callbacks must also check the current role.
retainedNext() assert(plays==nplay and stops==nstop)
SessionLabAudioRuntime.window:DestroySelf()
assert(next(SessionLabAudioRuntime.panels)==nil)
-- Preferences and native playback survive mod replacement; old callbacks retire.
dmhub.isDM=true assert(load(code))()
launcher=registers["SessionLab · музыка"].content() press("Открыть плеер",launcher)
root=assert(SessionLabAudioRuntime.windowContent)
press("Избранное") assert(find(root,"label","Треков: 1"))
SessionLabAudioRuntime.window:DestroySelf()
for _,size in ipairs({{1024,768},{720,680},{420,700}}) do
 dmhub.screenDimensions={x=size[1],y=size[2]}
 press("Открыть плеер",launcher)
 local win=assert(SessionLabAudioRuntime.window) assert(win.width<=size[1] and type(win.height)=="number" and win.height<=size[2])
 press("Закрыть",win) assert(not SessionLabAudioRuntime.window and next(SessionLabAudioRuntime.panels)==nil)
end
print("PASS: shared music, isolated volume, role guards, folders, literal Cyrillic search, favorites, import errors, stable tick, lifecycle")
