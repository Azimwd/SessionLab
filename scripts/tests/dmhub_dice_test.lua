local f=assert(io.open((arg and arg[1]) or 'scripts/SessionLabBridge_Main.lua','rb'))
local source=f:read('*a') f:close()
assert(not source:find('[\128-\255]'))
source=source:gsub('local TOKEN = "PASTE_NEW_TOKEN_HERE"','local TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"')
local config,request,queue=nil,nil,{}
local count,messages=0,0
local function ctor(kind)
 return function(p)
  assert(#p==0,'Use explicit children') assert(p.borderBox==nil) p.children=p.children or {} p.kind=kind
  local dead=false local proxy={}
  p.DestroySelf=function()
   if dead then return end
   if p.destroy then p.destroy() end
   for _,c in ipairs(p.children) do c:DestroySelf() end
   dead=true
  end
  return setmetatable(proxy,{__index=function(_,k) assert(not dead,'Dead userdata') return p[k] end,
   __newindex=function(_,k,v)
    assert(not dead and (k=='text' or k=='children'),'Unsupported setter '..k)
    if k=='children' then for _,c in ipairs(p.children) do c:DestroySelf() end end
    p[k]=v
   end})
 end
end
gui={Panel=ctor('panel'),Label=ctor('label'),Button=ctor('button'),Input=ctor('input')}
DockablePanel={Register=function(c) config=c end}
Commands={} chat={Send=function() messages=messages+1 end}
json=function() error('Not a codec') end
dmhub={Schedule=function(_,fn) queue[#queue+1]=fn end,FromJson=function() return {data={events={},cursor=84}} end}
net={Get=function(o) count=count+1 request=o assert(o.error and o.failure) end}
source=source:gsub('local PERSONAL_TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"','local PERSONAL_TOKEN = "PASTE_PERSONAL_SHEET_TOKEN_HERE"')
local ctx={is_dm=true,campaign="Test",characters={{id=11,name="Hero",folder=10},{id=22,name="Goblin",folder=20}},folders={{id=10,name="Игроки"},{id=20,name="NPC"}}}
local lastPost,postCount=nil,0
net.Get=function(o)
 count=count+1
 assert(o.headers.Authorization=='Bearer test_personal_dice_key_1234567890123456')
 if o.url:match('/sheets/$') then o.success({data=ctx}) else request=o end
end
net.Post=function(o) postCount=postCount+1 lastPost=o assert(type(o.data)=='table' and o.headers['Idempotency-Key']) end
assert(load(source,'DiceBridge'))()
local panel=config.content()
local state=rawget(_G,'SessionLabBridgeRuntime')
local function find(root,text)
 if root.text==text then return root end
 for _,c in ipairs(root.children) do local r=find(c,text) if r then return r end end
end
local function press(text) local b=assert(find(panel,text),text) b.press(b) end
local function check(node,parent)
 local w=node.width
 if type(w)=='number' and type(parent)=='number' then assert(w<=parent,'Overflow') end
 local sum=0 for _,c in ipairs(node.children) do check(c,w) if type(c.width)=='number' then sum=sum+c.width+2*(c.hmargin or 0)+2*(c.hpad or 0) end end
 if node.flow=='horizontal' and type(w)=='number' then assert(sum<=w,'Row overflow') end
end
assert(state.context.is_dm and state.actorId==nil)
local tray=state.diceHost.children
press('D20') press('D20 x1') press('D4')
assert(state.formulaLabel.text=='2d20+1d4' and state.diceHost.children==tray)
press('Выбрать персонажа / мастера >') assert(find(panel,'Игроки') and find(panel,'NPC')) press('Hero')
assert(state.actorId==11)
press('Вся комната') assert(state.visibility=='dm')
press('Бросить') assert(state.rollBusy and lastPost.data.formula=='2d20+1d4' and lastPost.data.character==11 and lastPost.data.visibility=='dm')
local function result(id,visibility)
 return {id=id,actor='Hero',title='Произвольный бросок',text='Saved',summary='27',visibility=visibility,card={rows={{label='2d20+1d4',value=27,tone='roll'}},tags={}}}
end
lastPost.success({data=result(101,'dm')})
assert(messages==0 and not state.rollBusy and state.cards[1].visibility=='dm','Private result must not reach chat')
press('Подключить') assert(request.url:find('/dice/events/',1,true))
request.success({data={events={result(101,'dm'),result(102,'dm')},cursor=102}})
assert(messages==0,'GM private feed must not post hidden events to chat')
press('Только мастер') press('Бросить')
local key=lastPost.headers['Idempotency-Key'] local body=lastPost.data
lastPost.error('Timeout') assert(state.rollPending and not state.rollBusy)
press('D20 x2') assert(state.dice[20]==2,'Do not change an unresolved request')
press('Повторить запрос') assert(lastPost.headers['Idempotency-Key']==key and lastPost.data==body)
lastPost.success({data=result(103,'public')}) assert(messages==1)
press('Очистить')
for i=1,50 do state.dieButtons[100].press() end
assert(state.dice[100]==50 and state.formulaLabel.text=='50d100')
state.dieButtons[100].press() assert(state.dice[100]==50)
press('Убрать 1') assert(state.dice[100]==49)
press('Очистить') local before=postCount press('Бросить') assert(postCount==before)
-- Add a negative modifier using the actual input's edit event.
press('D6')
local function input(root) if root.kind=='input' then return root end for _,c in ipairs(root.children) do local r=input(c) if r then return r end end end
local modifier=assert(input(panel)) modifier.text='-3' modifier.edit(modifier)
assert(state.formulaLabel.text=='1d6-3') press('Бросить') assert(lastPost.data.formula=='1d6-3')
lastPost.success({data=result(104,'public')})
-- Changing from a master context to a player context selects only an available owned character.
press('Выбрать персонажа / мастера >') press('Мастер')
ctx={is_dm=false,campaign='Test',characters={{id=11,name='Hero',folder=10}},folders={{id=10,name='Игроки'}}}
press('Обновить список персонажей') assert(state.actorId==11 and not state.context.is_dm)
press('Выбрать персонажа / мастера >') assert(not find(panel,'Мастер') and not find(panel,'Goblin'))
press('Hero')
local previousMessages=messages
press('Бросить') lastPost.success({data=result(105,'public')})
assert(messages==previousMessages,'Player instances must not duplicate the master chat relay')
check(panel)
panel:DestroySelf() assert(state.diceHost==nil and state.formulaLabel==nil)
print('PASS: accumulated mixed dice, modifier, actor folders, private chat suppression, personal polling, idempotent retry, 50-die limit, bounds and lifecycle')
