local script = assert(arg[1], "Supply the generated mod path")
local file = assert(io.open(script, "rb"))
local source = file:read("*a")
file:close()
source = source:gsub("PASTE_PERSONAL_SHEET_TOKEN_HERE", string.rep("x", 30), 1)

local settings, bindings, requests, timers, logs = {}, {}, {}, {}, {}
local actor = {valid=true, canControl=true, charid="token-a", description="Hero"}
local other = {valid=true, canControl=false, charid="token-b", description="Other"}
local owner = {}
local mapPanel, clickTarget, makeHud
gamehud = {dialog={sheet=owner}, dialogWorldPanel={AddChild=function(_, panel) mapPanel=panel end}}
TokenUI = {RegisterClickHandler=function(_, handler) clickTarget=handler end}
TokenHud = {RegisterPanel=function(spec) makeHud=spec.create end}
Commands = {RegisterMacro=function(spec) Commands[spec.name]=spec.command end}
Keybinds = {
    Register=function(spec) assert(spec.command=="sltoken") end,
    GetBindings=function() return {{command="rotate"}} end,
}
dmhub = {
    gameid="game-a", userid="user-a", tokenHovered=actor, selectedTokens={actor},
    Log=function(message) logs[#logs+1]=message end,
    GetTokenById=function(id) return id==actor.charid and actor or id==other.charid and other or nil end,
    GenerateGuid=function() return tostring(#requests) .. "-aaaaaaaa-bbbb-cccc" end,
    RegisterSetting=function(spec) settings[spec.id]=settings[spec.id] or spec.default end,
    GetSettingValue=function(id) return settings[id] end,
    SetSettingValue=function(id, value) settings[id]=value end,
    Schedule=function(_, cb) timers[#timers+1]=cb end,
    GetCommandBinding=function(command) return bindings[command] end,
    SetCommandBinding=function(key, command) bindings[command]=key end,
}
local function record(method, args)
    requests[#requests+1] = {method=method, args=args}
end
net = {Get=function(args) record("GET",args) end, Post=function(args) record("POST",args) end}
local function widget(p)
    p.valid=true
    p.SetClass=function(element, name, value) element[name]=value end
    p.DestroySelf=function(element) element.valid=false if element.destroy then element.destroy(element) end end
    return p
end
gui = {Panel=widget, Label=widget, Button=widget}

local function find(node, title)
    if not node then return nil end
    if node.text==title then return node end
    for _, child in ipairs(node.children or {}) do
        local result=find(child, title)
        if result then return result end
    end
end
local function press(title)
    assert(find(owner.popup,title), "Missing button: "..title).press()
end

bindings.rotate="R"
assert(load(source))()
table.remove(timers,1)()
assert(bindings.rotate=="R" and not bindings.sltoken, "Existing R shortcut overwritten")
bindings.rotate=nil
assert(load(source))()
table.remove(timers,1)()
assert(bindings.sltoken=="r")
Commands.sltoken()
assert(owner.popupPositioning=="mouse" and #requests==1)
requests[1].args.success({data={targets={}}})
press("Привязать лист")
assert(requests[2].method=="GET" and requests[2].args.url:match("/sheets/$"))
requests[2].args.success({data={characters={{id=4,name="Hero sheet"},{id=5,name="Other sheet"}}}})
press("Hero sheet · #4")
local athletics=assert(find(owner.popup,"Атлетика"))
athletics.press()
athletics.press()
assert(#requests==3 and requests[3].method=="POST")
local roll=requests[3].args
assert(roll.url:match("/sheets/4/roll/$") and roll.data.kind=="skill" and roll.data.key=="athletics")
assert(roll.headers["Idempotency-Key"])
timers[#timers]()
press("Повторить этот запрос")
assert(#requests==4 and requests[4].args.headers["Idempotency-Key"]==roll.headers["Idempotency-Key"])
requests[4].args.success({data={payload={roll={total=17}}}})
assert(find(owner.popup,"Атлетика: 17 · отправлено в журнал"))
press("Закрыть")
dmhub.tokenHovered=nil
Commands.sltoken("selected")
requests[5].args.success({data={targets={}}})
assert(find(owner.popup,"Атлетика") and #requests==5, "Binding was not reused")

local function last() return requests[#requests].args end
local function answer(value) last().success({data=value}) end
press("Спасброски")
press("Мудрость")
assert(last().data.kind=="save" and last().data.key=="wis")
answer({payload={roll={total=16}}})
press("Ещё проверка")
press("Характеристики")
press("Сила")
assert(last().data.kind=="ability" and last().data.key=="str")
answer({payload={roll={total=9}}})
press("Ещё проверка")

press("Заклинания")
assert(last().url:match("/sheets/4/$"))
answer({
    actions={{id=9,kind="spell",name="Огненный шар",level=3,upcast_allowed=true}},
    sheet={slots={["3"]={max=1,used=0},["4"]={max=2,used=0}}},
})
press("Огненный шар")
press("Ячейка 4 · осталось 2")
assert(last().url:match("/token%-scene/%?game=game%-a"))
answer({session=6,targets={{id=8,token=other.charid,name="Guard",targetable=true}}})
assert(mapPanel and mapPanel.valid and not owner.popup)
assert(clickTarget(other)==true)
assert(not mapPanel.valid and last().data==nil)
press("Подтвердить заклинание")
assert(last().data.command=="cast" and last().data.token=="token-b" and last().data.caster==4)
assert(last().data.spell==9 and last().data.slot_level==4 and last().data.target==8)
answer({event={payload={token_target={name="Guard",resolved=true,parts={{save_outcome="failure"}}}}}})
assert(find(owner.popup,"Guard · спасбросок провален"))
press("Закрыть")

local panel = makeHud(actor)
panel.think(panel)
local toggle = assert(find(panel,"ХП / КД"))
assert(not toggle.collapsed)
toggle.press()
panel.think(panel)
answer({session=6,targets={{token=actor.charid,sheet=4,hp_current=7,hp_max=10,hp_temp=2,armor_class=14}}})
panel.think(panel)
assert(find(panel,"ХП 7/10 +2  ·  КД 14"))
toggle.press()
panel.think(panel)
assert(panel.children[1].collapsed)

dmhub.gameid="game-b"
Commands.sltoken("selected")
answer({targets={}})
assert(find(owner.popup,"Привязать лист"), "Binding leaked to another game")
press("Закрыть")
local count = #requests
dmhub.tokenHovered=other
Commands.sltoken()
assert(owner.popup==nil and #requests==count and #logs>0)
print("PASS: skill, save, ability, target click, spell slot, HUD toggle and idempotent retry")
