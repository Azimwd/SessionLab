local f=assert(io.open(arg[1],'rb')) local source=f:read('*a') f:close()
assert(not source:find('[\128-\255]'))
source=source:gsub('local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"','local TOKEN="'..'test_room_123456789012345678901234567890'..'"')
local config,get,post,queue,attached=nil,nil,nil,{},{}
local gets={} local postCount=0
local function ctor(kind)
 return function(p)
  assert(#p==0 and not p.borderBox) p.kind=kind p.children=p.children or {}
  local dead=false local proxy={}
  p.DestroySelf=function()
   if dead then return end
   if p.destroy then p.destroy() end
   for _,c in ipairs(p.children) do c:DestroySelf() end dead=true
  end
  return setmetatable(proxy,{__index=function(_,k) assert(not dead,'Dead userdata '..k) return p[k] end,
   __newindex=function(_,k,v)
    assert(not dead,'Write dead userdata')
    assert(k=='text' or k=='children' or k=='x' or k=='y','Unsupported setter '..k)
    if k=='children' then for _,c in ipairs(p.children) do c:DestroySelf() end end p[k]=v
   end})
 end
end
gui={Panel=ctor('panel'),Label=ctor('label'),Button=ctor('button'),Input=ctor('input'),ShowModal=function() error('Must be nonmodal') end}
DockablePanel={Register=function(c) config=c end}
Commands={RegisterMacro=function() end}
GameHud={instance={dialogWorldPanel={AddChild=function(_,p) attached[#attached+1]=p end}}}
dmhub={Schedule=function(_,f) queue[#queue+1]=f end,FromJson=function() error('Response must be native table') end}
net={Get=function(o) get=o gets[#gets+1]=o end,Post=function(o) post=o postCount=postCount+1 end}
assert(load(source,'Room'))()
local function find(n,t)
 if n.text==t then return n end
 for _,c in ipairs(n.children) do local r=find(c,t) if r then return r end end
end
local function check(n,parent)
 local w=n.width if type(w)=='number' and type(parent)=='number' then assert(w<=parent,'Overflow') end
 local total=0
 for _,c in ipairs(n.children) do check(c,w) total=total+(type(c.width)=='number' and c.width or 0)+2*(c.hmargin or 0) end
 if n.flow=='horizontal' and type(w)=='number' then assert(total<=w,'Row overflow '..total..' / '..w) end
end

local launcher=config.content() find(launcher,'Открыть комнату').press()
local S=rawget(_G,'SessionLabRoomRuntime')
local room={session={id=7,name='Session'},role='player',master_view=false,campaign_name='Campaign',folders={},party={},npcs={},initiative={version=0,running=false,round_number=0,entries={}}}
get.success({data=room})
find(S.window,'Урон / лечение').press()
assert(get.url:find('/scene/'))
local scene={session=7,master_view=false,targets={{id=1,name='Guard 1',targetable=true},{id=2,name='Guard 2',targetable=true}},
 sources={{id=50,label='Fireball',damage_type='fire',parts={{index=0,damage={total=21},save={dc=15,failed_damage=21,success_damage=10}}}}},applications={},damage_types={fire='Огонь'}}
get.success({data=scene}) check(S.window)
find(S.window,'Fireball · #50 · fire').press()
find(S.window,'[ ] Guard 1').press()
assert(not find(S.window,'Нанести урон · 1 целей'))
find(S.window,'Не прошёл').press() find(S.window,'Нанести урон · 1 целей').press()
assert(post.url:find('/scene/commands/'))
assert(post.data.command=='damage' and post.data.source_event==50 and post.data.targets[1]==1 and post.data.outcomes['1'].save_outcome=='failure')
assert(not post.data.defenses and not post.data.base_damage)
local key=post.headers['Idempotency-Key'] post.error('Timeout')
find(S.window,'Повторить запрос').press() assert(post.headers['Idempotency-Key']==key)
local before=#gets post.success({data={applications={{id=1}}}})
local sceneGet,roomGet
for i=before+1,#gets do if gets[i].url:find('/scene/') then sceneGet=gets[i] else roomGet=gets[i] end end
scene.applications={{id=1,source_event=50,part_index=0,target=1,target_name='Guard 1'}}
sceneGet.success({data=scene}) roomGet.success({data=room})
assert(find(S.window,'Применено → Guard 1') and not find(S.window,'[ ] Guard 1'))
assert(not find(S.window,'Настроить'))
-- Reopening from a new sheet event must not lose its id to an older cached read.
S.openDamage(51) assert(S.damageSource==51)
scene.sources[2]={id=51,label='Sword',damage_type='slashing',parts={{index=0,damage={total=8},roll={total=18}}}}
get.success({data=scene})
if S.sceneReading then get.success({data=scene}) end -- discard a pre-handoff in-flight snapshot
find(S.window,'[ ] Guard 1').press() find(S.window,'[ ] Guard 2').press()
assert(not S.damageTargets[1] and S.damageTargets[2])
assert(not find(S.window,'Попал') and not find(S.window,'Промах'))
find(S.window,'Нанести урон · 1 целей').press()
assert(post.data.outcomes['2'].hit==true and #post.data.targets==1)
-- End the uncertain request before testing master participant tools.
Commands.slroom('close') Commands.slroom('open')
room.role='dm' room.master_view=true room.npcs={{id=22,name='Goblin',kind='npc'}}
get.success({data=room})
find(S.window,'Участники').press()
scene.master_view=true scene.targets={{id=1,name='Guard 1',version=2,visible=true,targetable=true,hp_current=30,hp_max=40,hp_temp=0,defenses={fire='resistance'}}}
get.success({data=scene})
find(S.window,'Настроить').press()
assert(find(S.window,'Огонь: Сопротивление'))
find(S.window,'Огонь: Сопротивление').press()
find(S.window,'Сохранить участника').press()
assert(post.data.command=='update' and post.data.target==1 and post.data.version==2 and post.data.defenses.fire=='immunity')
local saved=post.data.defenses.fire post.error('Timeout')
find(S.window,'Огонь: Иммунитет').press()
assert(post.data.defenses.fire==saved,'Retry snapshot must not change with editor draft')
Commands.slroom('close')
Commands.slroom('open')
room.role='player' room.master_view=false get.success({data=room})
find(S.window,'Урон / лечение').press()
scene.master_view=false scene.sources={{id=60,label='Healing Word',damage_type='лечение',effect='healing',parts={{index=0,damage={total=7}}}}} scene.applications={}
get.success({data=scene})
find(S.window,'Healing Word · #60 · лечение').press()
find(S.window,'[ ] Guard 1').press()
assert(not find(S.window,'Не прошёл') and not find(S.window,'Попал'))
find(S.window,'Вылечить · 1 целей').press()
assert(post.data.source_event==60 and post.data.command=='damage' and next(post.data.outcomes['1'])==nil)
Commands.slroom('close')
-- Several saved attack parts are selected and applied with one request.
Commands.slroom('open') get.success({data=room})
find(S.window,'Урон / лечение').press()
scene.sources={{id=70,label='Triple attack',damage_type='fire',parts={{index=0,damage={total=10},roll={total=20}},{index=1,damage={total=7},roll={total=17}},{index=2,damage={total=6},roll={total=15}}}}}
scene.applications={} get.success({data=scene})
find(S.window,'Triple attack · #70 · fire').press()
assert(find(S.window,'[X] Бросок 1 · Попадание: 20 · 10 урона'))
assert(find(S.window,'[ ] Бросок 2 · Попадание: 17 · 7 урона'))
find(S.window,'Выбрать все').press()
assert(S.damageParts[0] and S.damageParts[1] and S.damageParts[2])
find(S.window,'[ ] Guard 1').press()
assert(not find(S.window,'Попал') and not find(S.window,'Промах'))
check(S.window)
find(S.window,'Нанести урон · 1 целей · бросков: 3').press()
assert(#post.data.parts==3 and not post.data.part_index)
for i,p in ipairs(post.data.parts) do assert(p.part_index==i-1 and #p.targets==1 and p.targets[1]==1 and p.outcomes['1'].hit==true) end
local multiKey=post.headers['Idempotency-Key'] post.error('Timeout')
find(S.window,'Повторить запрос').press()
assert(post.headers['Idempotency-Key']==multiKey and #post.data.parts==3)
Commands.slroom('close')
-- Each save part still requires its own outcome.
Commands.slroom('open') get.success({data=room})
find(S.window,'Урон / лечение').press()
scene.sources={{id=71,label='Two saves',damage_type='fire',parts={{index=0,damage={total=10},save={dc=15}},{index=1,damage={total=7},save={dc=16}}}}}
get.success({data=scene}) find(S.window,'Two saves · #71 · fire').press()
assert(find(S.window,'[X] Бросок 1 · СЛ спасброска: 15 · 10 урона'))
assert(find(S.window,'[ ] Бросок 2 · СЛ спасброска: 16 · 7 урона'))
find(S.window,'Выбрать все').press() find(S.window,'[ ] Guard 1').press()
assert(not find(S.window,'Нанести урон · 1 целей · бросков: 2'))
find(S.window,'Не прошёл').press()
assert(not find(S.window,'Нанести урон · 1 целей · бросков: 2'))
find(S.window,'Не прошёл').press()
find(S.window,'Нанести урон · 1 целей · бросков: 2').press()
assert(post.data.parts[1].outcomes['1'].save_outcome=='failure' and post.data.parts[2].outcomes['1'].save_outcome=='failure')
Commands.slroom('close')
Commands.slroom('open') get.success({data=room})
find(S.window,'Урон / лечение').press()
scene.sources={{id=80,label='Rider',damage_type='slashing',parts={{index=0,damage={total=10},roll={total=18},effects={{id='judgment',name='Удар Суда',sign=1,frequency='turn',damage_type='radiant',roll={total=7}}}}}}}
scene.applications={} get.success({data=scene})
find(S.window,'Rider · #80 · slashing').press() find(S.window,'[ ] Guard 1').press()
find(S.window,'[X] Бросок 1 · Удар Суда').press()
check(S.window) find(S.window,'Нанести урон · 1 целей').press()
assert(#post.data.outcomes['1'].effects==0 and post.data.outcomes['1'].hit==true)
Commands.slroom('close')
print('PASS: native damage outcomes, target identity privacy, single attack target, retries, sheet handoff and master defenses')

-- Show flat scene cards and pass sibling IDs to the sheet window.
Commands.slroom('open')
room.role='dm' room.master_view=true get.success({data=room})
find(S.window,'Участники').press()
scene.master_view=true
scene.targets={
 {id=1,source=30,source_name='Guard',name='Guard 1',hp_current=12,hp_max=20,sheet_character={id=101,name='Guard 1'}},
 {id=2,source=30,source_name='Guard',name='Guard 2',hp_current=20,hp_max=20,sheet_character={id=102,name='Guard 2'}},
}
get.success({data=scene})
assert(find(S.window,'Guard 1') and find(S.window,'Guard 2'))
local chosen, siblings
rawset(_G,'SLsheet',{openSceneSheet=function(copies,id) siblings=copies chosen=id end})
find(S.window,'Открыть лист').press()
assert(chosen==101 and siblings[2].id==102)
Commands.slroom('close')
