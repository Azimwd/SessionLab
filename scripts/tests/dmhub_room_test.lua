local f=assert(io.open(arg[1],'rb')) local source=f:read('*a') f:close()
assert(not source:find('[\128-\255]'))
source=source:gsub('local TOKEN="PASTE_PERSONAL_SHEET_TOKEN_HERE"','local TOKEN="'..'test_room_123456789012345678901234567890'..'"')
local config,get,post,queue,attached=nil,nil,nil,{},{}
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
net={Get=function(o) get=o end,Post=function(o) post=o end}
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
local launcher=config.content()
find(launcher,'Открыть комнату').press()
local S=rawget(_G,'SessionLabRoomRuntime')
assert(S.active and S.window and S.window.blocksGameInteraction==true and S.window.floating)
local data={revision=1,session={id=7,name='Session'},role='dm',master_view=true,campaign_name='Campaign',table_visible_to_players=true,
 folders={{id=1,name='Игроки',visible_to_players=true},{id=2,name='NPC',visible_to_players=false}},
 party={{id=11,name='Hero',folder=1,kind='player',level=1,hp_current=10,hp_max=10,hp_temp=0,armor_class=12,speed=30,initiative=2,table_visible=true,conditions={},abilities={str=10}}},
 npcs={{id=22,name='Goblin',folder=2,kind='npc',level=1,hp_current=7,hp_max=7,hp_temp=0,armor_class=11,speed=30,initiative=3,table_visible=false,conditions={'Ослеплён'}}},
 initiative={version=0,running=false,round_number=0,entries={}}}
get.success({data=data}) check(S.window)
assert(S.window.bgcolor=='#101217ff' and S.window.styles[1].opacity==1,'Expanded background must be opaque')
assert(find(S.window,'Вид игрока') and find(S.window,'Скрыт'))
local body=S.body local child=body.children[1]
S.data.revision=2 S.reading=false Commands.slroom('refresh') get.success({data=data})
assert(body.children[1]==child,'Unrelated revisions must not reset scroll')
find(S.window,'Инициатива').press()
find(S.window,'Выбрать участников').press()
find(S.window,'[ ] Hero').press() find(S.window,'[ ] Goblin').press() find(S.window,'[1] Goblin').press()
local function input(n,placeholder)
 if n.placeholderText==placeholder then return n end
 for _,c in ipairs(n.children) do local r=input(c,placeholder) if r then return r end end
end
local name=input(S.window,'Имя') name.text='T' name.edit(name) name.text='Temporary' name.edit(name)
assert(S.draft.name=='Temporary' and input(S.window,'Имя')==name)
input(S.window,'Бонус').text='4' input(S.window,'Бонус').edit(input(S.window,'Бонус'))
find(S.window,'Начать · бросить инициативу выбранным').press()
assert(post.data.command=='initiative' and post.data.version==0 and #post.data.participants==3)
assert(post.data.participants[2].count==2 and post.data.participants[3].bonus==4)
local requestKey=post.headers['Idempotency-Key'] post.error('Timeout')
find(S.window,'Повторить запрос').press() assert(post.headers['Idempotency-Key']==requestKey)
post.success({data={version=2}})
data.initiative={version=2,running=true,round_number=1,current=99,entries={{id=99,name='Hero',initiative=18},{id=100,name='Goblin 1',initiative=11}}}
get.success({data=data}) check(S.window)
find(S.window,'Свернуть').press() assert(S.compact and S.window.width==400 and S.window.bgcolor=='#101217e8' and not S.window.blocksGameInteraction)
assert(find(S.window,'Hero') and find(S.window,'Раунд 1 · Бой'))
local controls
for _,c in ipairs(S.window.children) do
 if c.flow=='horizontal' and find(c,'Развернуть') then controls=c end
end
assert(controls and find(controls,'Следующий ход') and find(controls,'Закрыть'),'Compact actions must share one aligned row')
local width=0 for _,c in ipairs(controls.children) do width=width+c.width end
assert(width==376,'Compact actions must exactly fill the inner width')
assert(S.window.styles[1].cornerRadius==12 and S.window.styles[1].borderWidth==1)
check(S.window)
find(S.window,'Следующий ход').press() assert(post.data.action=='next' and post.data.version==2)
post.success({data={version=3}}) get.success({data=data})
find(S.window,'Развернуть').press() check(S.window)
find(S.window,'Вид игрока').press() assert(get.url:find('view=player'))
local public={session={id=7,name='Session'},role='dm',master_view=false,folders={data.folders[1]},party=data.party,npcs={},initiative={version=3,running=true,round_number=1,current=99,entries={{id=99,name='Hero',initiative=18}}},table_visible_to_players=true}
get.success({data=public})
assert(not find(S.window,'Следующий ход') and find(S.window,'Режим мастера'))
assert(not find(S.window,'Goblin')) check(S.window)
find(S.window,'Закрыть').press() assert(not S.active and not S.window)
get.success({data=data}) assert(not S.window,'Late response must not reopen window')
config.content() Commands.slroom('open')
local player={} for k,v in pairs(public) do player[k]=v end player.role='player' get.success({data=player})
assert(not find(S.window,'Режим мастера') and not find(S.window,'Вид игрока'))
Commands.slroom('close')
print('PASS: nonmodal room, transparency, role preview, folders, stable forms/polls, NPC counts, idempotent retry, compact tracker, lifecycle and bounds')
