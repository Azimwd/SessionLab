local script = assert(arg[1], "Supply the generated mod path")
local file = assert(io.open(script, "rb"))
local source = file:read("*a")
file:close()
local publicSource = source
source = publicSource:gsub("PASTE_PERSONAL_SHEET_TOKEN_HERE", string.rep("x", 30), 1)

local settings, bindings, requests, timers, logs = {hideactionbar=false}, {}, {}, {}, {}
local bindable = {}
local messages = {}
local remoteEvents, visualMessages, visualCleanup = {}, {}, {}
local guidSequence = 0
local nativeFireIcon = "fa8738bc-3859-4bb1-b1e8-398277e8b267"
local libraryImage = "d52c9094-5bc6-4853-86b4-5d2b41986392"
local uploadedImage = "12345678-1234-1234-1234-123456789abc"
chat = {Send=function(message) messages[#messages+1]=message end}
local watchGame
local function host(restorePrevious)
    return {valid=true, restorePrevious=restorePrevious, AddChild=function(panel, child)
        child.previousSibling=panel.latest
        panel.latest=child
        child.parent=panel
    end}
end
local actor = {valid=true, canControl=true, charid="token-a", description="Hero", sheet=host(true)}
local other = {valid=true, canControl=false, charid="token-b", description="Other", sheet=host(true)}
local far = {valid=true, canControl=false, charid="token-c", description="Far", sheet=host(true)}
actor.loc, other.loc, far.loc = {str="a", floor=2, x=0, y=0}, {str="b", floor=2, x=1, y=0}, {str="c", floor=2, x=30, y=0}
local function position(self, loc) return {x=(loc or self.loc).x,y=0} end
actor.PosAtLoc, other.PosAtLoc, far.PosAtLoc = position, position, position
actor.Distance=function(_,target) return (target==far or target==far.loc) and 90 or 15 end
-- Some DMHub builds return 0 for a bare map location even on an open floor.
actor.GetLineOfSight=function(_,target) return target.charid and 1 or 0 end
local blockedLoc = {str="wall", floor=2, x=3, y=0}
local effects = 0
local world, clickTarget, marked, rangeMarked = host(), nil, false, false
local rangeCells = {{x=0,y=0,floor=-1,WithDifferentFloor=function(_,floor)
    assert(floor==2) return actor.loc
end}}
local areaCells, segments, shapePoints = {actor.loc, other.loc}, 0, {}
local areaVideos = {}
actor.GetLocsWithinRadius=function(_,radius) assert(radius==12) return rangeCells end
gamehud = {dialogWorldPanel=world}
TokenUI = {RegisterClickHandler=function(_, handler) clickTarget=handler end}
Commands = {RegisterMacro=function(spec) Commands[spec.name]=spec.command end}
Keybinds = {
    Register=function(spec) bindable[spec.command]=spec.name end,
    GetBindings=function() return {{command="rotate"}} end,
}
dmhub = {
    gameid="game-a", userid="user-a", tokenHovered=actor, selectedTokens={actor},
    Log=function(message) logs[#logs+1]=message end,
    SearchImages=function() error("Icon IDs must come from the verified registry, not a guessed search") end,
    RegisterRemoteEvent=function(event, callback) remoteEvents[event]=callback end,
    BroadcastRemoteEvent=function(event, stream, data)
        assert(type(stream)=="string" and stream:match("^SessionLabFX|"))
        visualMessages[#visualMessages+1]=data
        remoteEvents[event](data) -- Some transports may also deliver a local echo.
    end,
    GetTokenById=function(id) return id==actor.charid and actor or id==other.charid and other or id==far.charid and far or nil end,
    unitsPerSquare=5, mouseWheel=0,
    GetTokensAtLoc=function(loc) return loc==other.loc and {other} or loc==far.loc and {far} or {} end,
    CalculateShape=function(args)
        assert(args.shape=="sphere" and args.radius==20 and args.range==300)
        assert(args.checklos==nil and args.targetFloorIndex==nil, "Legacy DMHub rejects these fields")
        shapePoints[#shapePoints+1] = args.targetPoint.x
        if args.targetPoint.x==blockedLoc.x then return nil end
        if args.targetPoint.x==2 then return {valid=true, locations={other.loc}} end
        return {valid=true, locations=areaCells, Mark=function(shape, spec)
            local marker = {spec=spec, locations=shape.locations, Destroy=function(self) self.destroyed=true end}
            areaVideos[#areaVideos+1]=marker
            return marker
        end}
    end,
    MarkLocs=function(args)
        assert(args.color=="#ffffff" and args.style=="solid")
        assert(args.locs[1].floor==2)
        if #args.locs==2 then
            marked=true
            return {Destroy=function() marked=false end}
        end
        rangeMarked=true
        return {Destroy=function() rangeMarked=false end}
    end,
    HighlightLine=function(args)
        assert(args.floorIndex==2 and args.color=="#ffffff")
        segments=segments+1
        return {Destroy=function() segments=segments-1 end}
    end,
    GenerateGuid=function() guidSequence=guidSequence+1 return tostring(guidSequence) .. "-aaaaaaaa-bbbb-cccc" end,
    RegisterSetting=function(spec) if settings[spec.id]==nil then settings[spec.id]=spec.default end end,
    GetSettingValue=function(id) return settings[id] end,
    SetSettingValue=function(id, value) settings[id]=value end,
    Schedule=function(delay, cb)
        if delay==0.5 then watchGame=cb
        elseif delay==3 then visualCleanup[#visualCleanup+1]=cb
        else timers[#timers+1]=cb end
    end,
    GetCommandBinding=function(command) return bindings[command] end,
    SetCommandBinding=function(key, command) bindings[command]=key end,
}
local function record(method, args)
    requests[#requests+1] = {method=method, args=args}
end
net = {Get=function(args) record("GET",args) end, Post=function(args) record("POST",args) end}
local function widget(p)
    p.valid=true
    p.selfStyle={width=p.width}
    p.children=p.children or {}
    for _, child in ipairs(p) do
        p.children[#p.children+1]=child
        if not child.press then child.press=p.press end
    end
    p.SetClass=function(element, name, value) element[name]=value end
    p.DestroySelf=function(element)
        element.valid=false
        if element.parent and element.parent.latest == element then
            local previous=element.parent.restorePrevious and element.previousSibling or nil
            while previous and not previous.valid do previous=previous.previousSibling end
            element.parent.latest=previous
        end
        if element.destroy then element.destroy(element) end
    end
    return p
end
gui = {Panel=function(p)
    if p.bgimage and p.bgimage:match("^fire%-radius%.webm###") then effects=effects+1 end
    return widget(p)
end, Label=widget, Input=widget, Button=function(p) p.nativeButton=true return widget(p) end}

local function findBy(node, predicate)
    if not node then return nil end
    if predicate(node) then return node end
    for _, child in ipairs(node.children or {}) do
        local found = findBy(child, predicate)
        if found then return found end
    end
end

local function find(node, title)
    if not node then return nil end
    if node.text==title or node.text=="›  "..title then return node end
    for _, child in ipairs(node.children or {}) do
        local result=find(child, title)
        if result then return result end
    end
end
local function press(title)
    assert(find(world.latest,title), "Missing button: "..title).press()
end
local function last() return requests[#requests].args end
local function answer(value) last().success({data=value}) end
local own = {id=7,token=actor.charid,sheet=4,name="Hero",targetable=true,hp_current=7,hp_max=10,hp_temp=2,armor_class=14}
local enemy = {id=8,token=other.charid,sheet=8,name="Guard",targetable=true,hp_current=23,hp_max=30,armor_class=17}
local dmScene = {session=6,is_dm=true,targets={own,enemy}}
local playerScene = {session=6,is_dm=false,targets={own,{token=other.charid,targetable=true}}}

bindings.rotate="R"
assert(load(source))()
table.remove(timers,1)()
assert(bindings.rotate=="R" and not bindings.sltoken, "Existing R shortcut overwritten")
bindings.rotate=nil
assert(load(source))()
table.remove(timers,1)()
assert(bindings.sltoken=="r")
watchGame()
assert(#requests==1 and settings.hideactionbar==true and not actor.sheet.popup)
answer(dmScene)
assert(actor.sheet.latest.data.health.text=="7 / 10" and other.sheet.latest.data.armor.text=="КД 17")
assert(clickTarget(actor, true)==false and not actor.sheet.popup)
local function openCategory(index, args)
    Commands.sltoken(args)
    local radial = assert(actor.sheet.popup, "Hotkey did not open the radial menu")
    radial.children[index].press()
end
Commands.sltoken()
local initialRadial = assert(actor.sheet.popup)
assert(find(world.latest,"Бросить инициативу") and #requests==1 and #initialRadial.children==6)
assert(bindable.slenroll and bindable.slinitiative)
for i, icon in ipairs(initialRadial.children) do
    assert(icon.y<0 and icon.width==40)
    if i>1 then
        local previous=initialRadial.children[i-1]
        assert(icon.x>previous.x and (icon.x-previous.x)^2+(icon.y-previous.y)^2 > 44^2)
    end
end
assert(#initialRadial.children[4].children[1].children==2, "Missing built-in spell symbol")
Commands.sltoken()
assert(not actor.sheet.popup, "Hotkey did not close the radial menu")
openCategory(1)
assert(world.latest and world.latest.draggable and #requests==2)
world.latest.xdrag, world.latest.ydrag = 107, 133
world.latest.drag(world.latest)
answer({targets={}})
press("Привязать лист")
assert(requests[#requests].method=="GET" and last().url:match("/sheets/$"))
answer({characters={{id=4,name="Hero sheet"},{id=5,name="Other sheet"}}})
press("Hero sheet · #4")
answer(dmScene)
local athletics=assert(find(world.latest,"Атлетика"))
assert(athletics.styles[1].color=="#ffffff" and athletics.styles[1].priority>0)
local scroll = assert(findBy(world.latest,function(p) return p.vscroll end))
dmhub.mouseWheel=-1
scroll.vscrollPosition=0.70
scroll.scroll(scroll)
assert(scroll.vscrollPosition==1 and scroll.thinkTime>0)
scroll.think(scroll)
assert(scroll.vscrollPosition>0.70 and scroll.vscrollPosition<1)
dmhub.mouseWheel=0
for i=1,30 do scroll.think(scroll) end
assert(scroll.vscrollPosition==0.70 and scroll.thinkTime==nil)
scroll.vscrollPosition=0.4
scroll.scroll(scroll)
assert(scroll.vscrollPosition==0.4 and scroll.thinkTime==nil)
local beforeRoll = #requests
athletics.press()
athletics.press()
assert(#requests==beforeRoll+1 and requests[#requests].method=="POST")
local roll=last()
assert(roll.url:match("/sheets/4/roll/$") and roll.data.kind=="skill" and roll.data.key=="athletics")
assert(roll.headers["Idempotency-Key"])
timers[#timers]()
press("Повторить этот запрос")
assert(#requests==beforeRoll+2 and last().headers["Idempotency-Key"]==roll.headers["Idempotency-Key"])
answer({payload={roll={total=17}}})
assert(find(world.latest,"Атлетика: 17 · отправлено в журнал"))
press("Закрыть")
dmhub.tokenHovered=nil
openCategory(1, "selected")
answer({targets={}})
assert(find(world.latest,"Атлетика"), "Binding was not reused")
assert(world.latest.x==107 and world.latest.y==133, "Window did not remember its position")
assert(not find(world.latest,"Навыки") and not find(world.latest,"Заклинания"))

openCategory(3)
answer({targets={}})
press("Мудрость")
assert(last().data.kind=="save" and last().data.key=="wis")
answer({payload={roll={total=16}}})

openCategory(2)
answer({targets={}})
press("Сила")
assert(last().data.kind=="ability" and last().data.key=="str")
answer({payload={roll={total=9}}})

openCategory(4)
answer({targets={}})
local oldSpellRequest = last()
openCategory(2)
answer({targets={}})
oldSpellRequest.success({data={actions={}}})
assert(find(world.latest,"Сила"), "A late spell response replaced the ability page")
openCategory(4)
answer({targets={}})
assert(last().url:match("/sheets/4/$"))
answer({
    actions={
        {id=9,version=1,kind="spell",name="Огненный луч",level=3,upcast_allowed=true,damage_type="fire",map_targeting={shape="single",range_ft=60,icon_asset="ui-icons/skills/02_Big_fire_arrow.png"}},
        {id=11,version=1,kind="spell",name="Огонёк",level=3,map_targeting={icon_asset=uploadedImage}},
        {id=12,version=1,kind="spell",name="Ветер",level=3,map_targeting={icon_asset="ui-icons/skills/grimhollow-mark.png"}},
        {id=13,version=1,kind="spell",name="Холод",level=3,map_targeting={icon_asset="ui-icons/skills/Skill_77.png"}},
        {id=14,version=1,kind="spell",name="Ладонь первая",level=3,map_targeting={icon_asset="ui-icons/skills/Skill_201.png"}},
        {id=15,version=1,kind="spell",name="Ладонь вторая",level=3,map_targeting={icon_asset="ui-icons/skills/skill_201.png"}},
    },
    sheet={slots={["3"]={max=1,used=1},["4"]={max="12",used="9"},["5"]={max=1,used=0}}},
})
assert(find(world.latest,"УРОВЕНЬ 3"))
local row = assert(findBy(world.latest,function(p) return p.flow=="horizontal" and p.height==122 end))
assert(#row.children==3 and row.height-row.children[1].height>=14)
assert(row.children[1].hmargin>=5)
local tile = assert(findBy(row,function(p) return p.nativeButton and p.classes and p.classes[1]=="sessionlab-action-tile" end))
assert(find(tile,"Огненный луч") and tile.bgimage and tile.height==106)
assert(findBy(tile,function(p) return p.bgimage==nativeFireIcon and p.width==43 end), "Catalog filename did not resolve to the real native image key")
assert(findBy(row,function(p) return p.bgimage==uploadedImage end), "An uploaded image ID was changed")
assert(not findBy(world.latest,function(p) return p.bgimage=="ui-icons/skills/grimhollow-mark.png" end), "An unregistered texture would render a blank icon")
assert(findBy(row.children[3],function(p) return p.bgimage=="panels/square.png" and p.rotate==45 end), "An unresolved icon did not get a visible fallback")
assert(findBy(world.latest,function(p) return p.bgimage==libraryImage end), "A verified native UUID was not used for an existing catalog alias")
assert(findBy(world.latest,function(p) return p.bgimage=="1cce2d43-f587-44ed-a5cd-604eb02383a5" end), "An exact legacy key lost its case-sensitive mapping")
assert(findBy(world.latest,function(p) return p.bgimage=="17545cbc-91b2-4c50-94f8-6e9ea20e616c" end), "Two distinct legacy keys were merged by case folding")
tile.press()
assert(rangeMarked, "Range should be drawn while choosing a spell slot")
press("Ячейка 4 · осталось 3")
assert(not rangeMarked)
assert(last().url:match("/token%-scene/%?game=game%-a"))
local mapped = {{id=8,token=other.charid,name="Guard",targetable=true},
    {id=9,token=far.charid,name="Far Guard",targetable=true}}
answer({session=6,map_actions=true,targets=mapped})
local targeting = assert(world.latest)
assert(find(targeting, "Выбрать из списка") and rangeMarked)
local count = #requests
assert(clickTarget(far)==true and #requests==count)
assert(find(targeting,"90 фт. · за пределами дальности 60 фт."))
local previousLookup = dmhub.GetTokensAtLoc
dmhub.GetTokensAtLoc=function() return {} end
dmhub.tokenHovered=other
targeting.mappress(targeting, other.loc, {x=1,y=0})
dmhub.GetTokensAtLoc=previousLookup
dmhub.tokenHovered=nil
assert(not clickTarget(other) and #requests==count+1, "Duplicate spell request")
assert(not targeting.valid and not rangeMarked and last().data.command=="act")
assert(last().data.caster==4 and last().data.action==9 and last().data.slot_level==4)
assert(last().data.targets[1].id==8 and last().data.targets[1].token=="token-b")
answer({event={visibility="dm",payload={token_target={name="Guard",resolved=true,parts={
    {save_outcome="failure",effect_damage={{name="Скрытый эффект",damage=4}}},
}}}}})
assert(effects==1)
assert(#visualMessages==1 and visualMessages[1].tokens[1]==other.charid, "Spell visual was not sent to peers")
local firePanel=other.sheet.latest
assert(firePanel.bgimage:match("^fire%-radius%.webm###") and firePanel.interactable==false)
visualCleanup[#visualCleanup]()
assert(not firePanel.valid, "Visual effect was not removed after its lifetime")
assert(find(world.latest,"Guard · спасбросок провален"))
assert(find(world.latest,"Guard · Скрытый эффект — 4 урона"))
assert(#messages==0)
answer(dmScene)
press("Закрыть")

-- Changing the selection does not reopen the menu.
dmhub.selectedTokens = {}
watchGame()
dmhub.selectedTokens = {actor}
watchGame()
assert(not actor.sheet.popup and not clickTarget(actor, true))
openCategory(4, "selected")
answer({session=6,map_actions=true,targets=mapped})
local areaSheet={actions={{id=10,version=2,kind="spell",name="Взрыв",level=0,resolution="save",save_ability="dex",
    map_targeting={shape="sphere",range_ft=300,size_ft=20}}},sheet={}}
answer(areaSheet)
assert(find(world.latest,"ЗАГОВОРЫ") and not find(world.latest,"Навыки"))
local filePicker, uploader
dmhub.OpenFileDialog=function(spec) filePicker=spec end
assets={UploadImageAsset=function(spec) uploader=spec end}
local beforeUpload=#requests
press("Настроить анимации")
press("Взрыв · По настройке листа")
press("Загрузить WebM и назначить")
assert(filePicker.extensions[1]=="webm")
filePicker.open("C:\\FX\\Explosion.webm")
assert(uploader.description=="Explosion.webm")
uploader.error("permission denied")
assert(find(world.latest,"DMHub не загрузил видео. permission denied"))
press("Загрузить WebM и назначить")
filePicker.open("C:\\FX\\Explosion.webm")
local videoId="00000000-aaaa-4000-bbbb-000000000001"
dmhub.GetRawImageId=function(asset)
    if asset==videoId then return "H3KeE3BfVXX/Zpi61dfU+Q==" end
    return asset
end
uploader.upload(videoId)
assert(find(world.latest,"Сейчас: Explosion.webm"))
local copiedId
dmhub.CopyToClipboard=function(value) copiedId=value end
press("Скопировать ID видео")
assert(copiedId==videoId and find(world.latest,"ID видео скопирован."))
assert(#requests==beforeUpload,"An effect upload used SessionLab's server")
press("Назад")
assert(find(world.latest,"Взрыв · Explosion.webm"))
press("Назад")
answer(areaSheet)
press("Взрыв")
table.insert(mapped, {id=7,token=actor.charid,name="Hero",targetable=true})
answer({session=6,map_actions=true,targets=mapped})
local area = assert(world.latest)
assert(area.mapfocus and find(area,"Спасбросок · Ловкость"))
local beforeArea = #requests
area.maphover(area, blockedLoc, {x=3,y=0})
area.mappress(area, blockedLoc, {x=3,y=0})
assert(#requests==beforeArea and not marked and area.valid)
area.maphover(area, other.loc, {x=1,y=0})
assert(marked and segments==48 and find(area,"Целей в области: 2 · нажмите для применения"))
-- A new world point can arrive with the same loc key.
area.maphover(area, other.loc, {x=2,y=0})
assert(shapePoints[#shapePoints]==2 and find(area,"Целей в области: 1 · нажмите для применения"))
local previews = #shapePoints
area.maphover(area, other.loc, {x=2,y=0})
assert(#shapePoints==previews)
-- Some clients expose the shape's token index through SheetHud instead.
dmhub.tokenInfo = {TokensInShape=function() return {[other.charid]=other,[far.charid]=far} end}
local anotherFloor = far.loc.floor
far.loc.floor = 3
area.mappress(area, other.loc, {x=1,y=0})
assert(shapePoints[#shapePoints]==1)
assert(not marked and segments==0 and not area.valid)
assert(last().data.action==10 and last().data.distance_ft==15 and #last().data.targets==2)
assert(last().data.targets[1].id==8 and last().data.targets[2].id==7)
assert(#areaVideos==0,"A video was played before the cast was confirmed")
far.loc.floor = anotherFloor
dmhub.tokenInfo = nil
answer({event={visibility="public",payload={map_resolved=true,token_targets={
    {name="Guard",parts={{save_outcome="success",save_total=18,save_dc=15}}},
    {name="Hero",parts={{save_outcome="failure",save_total=0,save_dc=15}}},
}}}})
local cloudPlayback="https://storage.googleapis.com/dmhub_images/H3KeE3BfVXX-Zpi61dfU_Q~~###slfx-"
assert(#areaVideos==1 and areaVideos[1].spec.video:find(cloudPlayback, 1, true)==1
    and areaVideos[1].spec.showLocs)
assert(areaVideos[1].locations==areaCells and #visualMessages==1,
    "An area video must use the confirmed map shape once, not per target")
visualCleanup[#visualCleanup]()
assert(areaVideos[1].destroyed,"The area animation did not clean up its marker")
assert(find(world.latest,"Взрыв · целей 2 · пройдено 1 · провалено 1"))
assert(find(world.latest,"Guard · спасбросок пройден (18 против СЛ 15)"))
assert(find(world.latest,"Hero · спасбросок провален (0 против СЛ 15)"))
assert(#messages==1 and messages[1]=="[SessionLab] Взрыв\nGuard · спасбросок пройден (18 против СЛ 15)\nHero · спасбросок провален (0 против СЛ 15)")
answer(dmScene)
press("Закрыть")

-- An icon selected inside DMHub updates just the icon settings of the attack.
openCategory(5, "selected")
answer(dmScene)
local strike={id=18,version=3,kind="attack",name="Длинный меч",level=0,
    map_settings={range_ft=15,effect="none"},map_targeting={shape="single",range_ft=15}}
answer({actions={strike}})
press("Настроить иконки")
press("Длинный меч")
local countBeforeIcon = #requests
press("Удар копьём")
assert(#requests==countBeforeIcon)
press("Сохранить иконку")
assert(last().url:match("/sheets/4/abilities/18/edit/$"))
local saved = last().data
assert(saved.version==3 and saved.map_settings.icon_asset=="ui-icons/skills/spear_hit.png")
assert(saved.map_settings.range_ft==15 and saved.map_settings.effect=="none")
assert(not strike.map_settings.icon_asset, "The loaded attack was changed before saving")
strike.map_settings=saved.map_settings
strike.map_targeting.icon_asset=saved.map_settings.icon_asset
strike.version=4
answer(strike)
assert(last().url:match("/sheets/4/$"))
answer({actions={strike}})
local spearId=assert(source:match('%["ui%-icons/skills/spear_hit%.png"%] = "([^"]+)"'))
assert(findBy(world.latest,function(p) return p.bgimage==spearId and p.width==43 end))
press("Настроить иконки")
press("Длинный меч")
press("Сбросить свою иконку")
press("Сохранить иконку")
assert(last().data.version==4 and last().data.map_settings.icon_asset=="")
answer(strike)
strike.resolution = "attack"
strike.attack_effects = {
    {id="judgment",name="Удар Суда",dice="1d12",enabled=false},
    {id="seal",name="Печать Возмездия",dice="1d8",enabled=false,min_level=10},
    {id="higher",name="Навык 20 уровня",dice="1d8",enabled=true,min_level=20},
}
answer({actions={strike},character={level=15}})
press("Длинный меч")
press("[ ] Удар Суда · 1d12")
press("[ ] Печать Возмездия · 1d8")
assert(not find(world.latest,"[x] Навык 20 уровня · 1d8"))
press("Выбрать цель")
answer({session=6,map_actions=true,targets=mapped})
assert(clickTarget(other))
assert(#last().data.effects==2 and last().data.effects[1]=="judgment" and last().data.effects[2]=="seal")
answer({event={visibility="public",payload={token_target={name="Guard",resolved=true,parts={
    {hit=false},
    {hit=true,effect_damage={{name="Удар Суда",damage=3},{name="Печать Возмездия",damage=0}}},
    {hit=true},
}}}}})
assert(#messages==2 and messages[2]=="[SessionLab] Длинный меч\nGuard · бросок 2 · Удар Суда — 3 урона / Печать Возмездия — 0 урона")
answer(dmScene)
press("Закрыть")

openCategory(6, "selected")
answer(dmScene)
assert(actor.sheet.latest.y==16)
assert(actor.sheet.latest.data.fill.selfStyle.width==65)
assert(actor.sheet.latest.data.shield.selfStyle.width==19)
assert(actor.sheet.latest.data.armor.text=="КД 14")
assert(actor.sheet.latest.data.health.text=="7 / 10")
press("Показать панель действий DMHub")
assert(settings.hideactionbar==false)
press("Скрыть панель действий DMHub")
assert(settings.hideactionbar==true)
assert(other.sheet.latest.data.fill.selfStyle.width==71 and other.sheet.latest.data.armor.text=="КД 17")
assert(other.sheet.latest.data.health.text=="23 / 30")
press("Скрыть ХП и КД токена")
assert(not actor.sheet.latest and other.sheet.latest)
answer(dmScene)
press("Скрыть все ХП и КД")
assert(not actor.sheet.latest and not other.sheet.latest)
assert(settings.sessionlab_vitals_v1.all==false and settings.sessionlab_vitals_v1.hidden[actor.charid])
press("Закрыть")

-- A player sees their own projected HP; the foreign row has no private stats.
openCategory(6, "selected")
answer(playerScene)
assert(not find(world.latest,"Показать ХП и КД токена"))
press("Показать все ХП и КД")
answer(playerScene)
assert(not actor.sheet.latest and not other.sheet.latest, "Per-token exclusion was lost")
press("Показать ХП и КД токена")
answer(playerScene)
assert(actor.sheet.latest and not other.sheet.latest)
press("Скрыть ХП и КД токена")
assert(not actor.sheet.latest)
press("Показать ХП и КД токена")
local inFlight = last()
press("Скрыть все ХП и КД")
inFlight.success({data=playerScene})
assert(not actor.sheet.latest and not other.sheet.latest, "Late response restored hidden HP")
press("Закрыть")

-- A personally bound sheet outside the scene uses the ownership-checked detail endpoint.
openCategory(6, "selected")
answer({targets={}})
press("Показать все ХП и КД")
answer({targets={}})
assert(last().url:match("/sheets/4/$"))
answer({sheet=own})
assert(actor.sheet.latest and not other.sheet.latest)
press("Закрыть")

dmhub.gameid="game-b"
actor.sheet.latest.think(actor.sheet.latest)
assert(not actor.sheet.latest, "Private HP leaked across games")
openCategory(6, "selected")
answer({targets={}})
assert(find(world.latest,"Привязать лист"), "Binding leaked to another game")
press("Закрыть")
local count = #requests
dmhub.tokenHovered=other
dmhub.selectedTokens={}
Commands.sltoken()
assert(world.latest==nil and #requests==count and #logs>0)

-- Enroll selected tokens with one shared template, and create the session only on confirmation.
dmhub.isDM, other.canControl, far.canControl = true, true, true
dmhub.selectedTokens = {actor, other, far, far}
watchGame()
answer({targets={}})
press("В сессию · SessionLab")
assert(last().url:find("&roster=1", 1, true))
local roster = {characters={{id=3,name="Страж",kind="npc"},{id=4,name="Мира",kind="player"}},
    bindings={[actor.charid]=4}, session_name="Бой"}
answer({is_dm=true,targets={},enrollment=roster})
press("Один лист для всех без привязки")
local search = assert(findBy(world.latest, function(node) return node.placeholderText == "Поиск по листу или папке" end))
search.text = "сТрАж"
search.change(search)
assert(find(world.latest,"Страж · #3") and not find(world.latest,"Мира · #4"))
press("Страж · #3")
assert(last().data==nil, "Session created before confirmation")
press("Создать сессию и добавить")
local create = last()
assert(create.data.command=="enroll" and create.data.session==0 and create.data.session_name=="Сессия DMHub")
assert(#create.data.tokens==3 and create.data.tokens[1].sheet==nil and create.data.tokens[2].sheet==3 and create.data.tokens[3].sheet==3)
create.error("Timeout")
press("Повторить запрос")
assert(last().headers["Idempotency-Key"]==create.headers["Idempotency-Key"])
answer({session=9,targets={{name="Мира",added=true},{name="Страж № 1",added=true},{name="Страж № 2",added=true}}})
assert(find(world.latest,"Добавлено: 3") and find(world.latest,"Страж № 2 · добавлен"))
answer({targets={}})
press("Закрыть")

-- An active session and saved templates skip the assignment dialog.
dmhub.selectedTokens = {actor}
Commands.slenroll()
answer({session=9,is_dm=true,targets={},enrollment=roster})
assert(last().data.command=="enroll" and last().data.session==9 and last().data.tokens[1].token==actor.charid)
answer({session=9,targets={{name="Мира",added=false}}})
assert(find(world.latest,"Мира · уже в сессии"))
answer({targets={}})
press("Закрыть")
dmhub.isDM = false
count = #requests
Commands.slenroll()
assert(#requests==count)

-- A player can roll an already linked sheet from the map without a master roster request.
local trackerOpened = false
SessionLabRoomRuntime = {openInitiative=function() trackerOpened=true end}
watchGame()
assert(not find(world.latest,"В сессию · SessionLab"))
press("Бросить инициативу")
assert(not last().url:find("&roster=1",1,true))
answer({session=9,is_dm=false,targets={{token=actor.charid,sheet=4}}})
assert(last().data.command=="initiative" and last().data.tokens[1].token==actor.charid)
assert(last().data.tokens[1].sheet==nil)
answer({initiative={{name="Мира",total=18,rolled=true}}})
assert(find(world.latest,"Мира · 18"))
press("Открыть трекер инициативы")
assert(trackerOpened)
SessionLabRoomRuntime = nil

-- The master can add selected tokens to the scene and tracker in a single action.
dmhub.isDM=true
dmhub.selectedTokens={actor, other}
watchGame()
assert(find(world.latest,"В сессию · SessionLab"))
press("Бросить инициативу")
assert(last().url:find("&roster=1",1,true))
answer({session=9,is_dm=true,targets={},enrollment=roster})
press("Other  →  Выбрать лист")
press("Страж · #3")
press("Бросить инициативу")
assert(last().data.command=="enroll-initiative" and last().data.tokens[2].sheet==3)
answer({initiative={{name="Мира",total=18,rolled=false},{name="Страж № 1",total=11,rolled=true}}})
assert(find(world.latest,"Мира · 18 · уже в инициативе") and find(world.latest,"Страж № 1 · 11"))
answer({targets={}})
press("Закрыть")
dmhub.isDM=false
count=#requests

-- Published source has no credential. A player can connect without editing it.
assert(load(publicSource))()
watchGame()
assert(#requests==count)
Commands.sltoken("selected")
assert(find(world.latest,"Подключение SessionLab"))
local keyInput = assert(findBy(world.latest, function(node) return node.placeholderText == "Личный ключ SessionLab" end))
keyInput.text = string.rep("z", 42)
press("Подключить")
assert(last().url:match("/sheets/$") and last().headers.Authorization=="Bearer "..string.rep("z", 42))
assert(keyInput.text=="")
last().error("401")
assert(next(settings.sessionlab_personal_connection_v1)==nil)
local personalKey = string.rep("y", 42)
keyInput.text = " " .. personalKey .. "\n"
press("Подключить")
answer({characters={{id=4,name="Мира"}},is_dm=false})
assert(find(world.latest,"Подключено. Личный ключ сохранён для всех модов SessionLab."))
assert(last().headers.Authorization=="Bearer "..personalKey and last().url:match("/token%-scene/"))
answer({targets={}})
press("Закрыть")
assert(load(publicSource))()
watchGame()
assert(last().headers.Authorization=="Bearer "..personalKey, "Saved connection did not survive a reload")
answer({targets={}})
dmhub.userid = "different-user"
count = #requests
watchGame()
Commands.slconnect()
assert(find(world.latest,"Подключение SessionLab") and #requests==count, "Another account reused the personal key")
press("Закрыть")

-- Load all four production chunks with the saved preferences, as on client restart.
local function loadMods()
    rawset(_G, "SessionLabConnectionV1", nil)
    DockablePanel = {Register=function() end}
    GameHud = {instance = gamehud}
    for _, name in ipairs({"SessionLabBridge_Main.lua", "SessionLabSheet_ASCII.lua", "SessionLabRoom_Main.lua"}) do
        assert(loadfile("scripts/" .. name))()
    end
    assert(load(publicSource))()
end
dmhub.userid = "user-a"
loadMods()
Commands.slbridge("start")
assert(last().url:match("/dice/events/") and last().headers.Authorization=="Bearer "..personalKey)
answer({events={},cursor=123})
Commands.slroom()
assert(last().url:match("/dmhub/room/$") and last().headers.Authorization=="Bearer "..personalKey)
local staleRoom = last()
Commands.slsheet("start")
assert(last().url:match("/dmhub/sheets/$") and last().headers.Authorization=="Bearer "..personalKey)
local staleSheet = last()
watchGame()
assert(last().url:match("/token%-scene/") and last().headers.Authorization=="Bearer "..personalKey)
local staleTokens = last()
Commands.slconnect()
local connectionPanel = world.latest
keyInput = assert(findBy(connectionPanel, function(node) return node.placeholderText == "Личный ключ SessionLab" end))
keyInput.text = string.rep("q", 44)
press("Подключить")
last().error("401")
assert(SessionLabConnectionV1.get("https://sessionlab.up.railway.app")==personalKey, "Rejected key overwrote the saved key")
local replacement = string.rep("w", 44)
keyInput.text = replacement
press("Подключить")
local beforeSwitch = #requests
answer({characters={}})
local paths = {}
for i=beforeSwitch+1,#requests do
    local req=requests[i].args
    assert(req.headers.Authorization=="Bearer "..replacement, "A mod kept using the old key")
    paths[req.url:match("/dmhub/([^/?]+)")] = true
end
assert(paths.dice and paths.room and paths.sheets and paths["token-scene"], "All four open mods must reconnect")
staleRoom.success({data={role="dm",master_view=true}})
staleSheet.success({data={characters={{id=100,name="Old identity"}}}})
staleTokens.success({data=dmScene})
assert(not SessionLabRoomRuntime.data and not SLsheet.list and not actor.sheet.latest)
loadMods()
assert(SessionLabConnectionV1.get("https://sessionlab.up.railway.app")==replacement)
print("PASS: token UI, combat, enrollment and all four mods sharing a saved personal key")
