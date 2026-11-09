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
assert(load(source,'Bridge'))()
local function find(root,text)
 if root.text==text then return root end
 for _,c in ipairs(root.children) do local r=find(c,text) if r then return r end end
end
local function check(node,parent)
 local w=node.width
 if type(w)=='number' and type(parent)=='number' then assert(w<=parent,'Overflow') end
 local sum=0
 for _,c in ipairs(node.children) do check(c,w) if type(c.width)=='number' then sum=sum+c.width+2*(c.hmargin or 0)+2*(c.hpad or 0) end end
 if node.flow=='horizontal' and type(w)=='number' then assert(sum<=w,'Row overflow') end
end
local panel=config.content()
assert(config.vscroll==false and panel.vscroll==true,'Exactly one scroll owner')
assert(panel.height=='100%-8' and panel.clip==true and panel.clipHidden==false,'Bounded viewport must clip partial cards at scroll zero')
assert(panel.hideObjectsOutOfScroll==false and panel.vmargin==4,'Keep partial cards inside the inset frame')
local state=rawget(_G,'SessionLabBridgeRuntime')
assert(state.connectButton.text=='Подключить')
state.connectButton.press()
assert(count==1 and state.active and state.busy and state.connectButton.text=='Остановить')
local ev={id=83,actor='Mage',title='Огненный шар с очень длинным названием',text='Saved result',summary='Saved result',
 card={rows={{label='1d20+2',detail='[16] · +2',value=18,tone='roll'},{label='огонь',detail='8d6: [1, 2, 3, 4, 5, 6, 5, 1]',value=42,tone='damage'}},
 saves={{ability='Ловкость',dc=10,failed=42,passed=21}},tags={'Ячейка 6 ур.','Атака +2','СЛ 10'},
 description=string.rep('Полное описание. ',80),components='В, С, М',timestamp=1}}
request.success({data={events={ev},cursor=83.0}})
assert(state.connected and state.cursor=='83' and not state.busy and #queue==1)
assert(find(panel,ev.title) and find(panel,'Провал: 42 / Успех: 21'))
assert(find(panel,'42').color=='#F08491' and find(panel,'42').fontSize==30)
assert(find(panel,ev.title).height=='auto','Titles must wrap')
local card=state.body.children[1]
find(panel,'Описание действия >').press()
assert(find(panel,ev.card.description) and state.body.children[1]==card)
find(panel,'Скрыть описание').press() assert(not find(panel,ev.card.description))
check(panel)
local scheduled=queue[1] queue={}
state.connectButton.press()
assert(not state.active and state.connectButton.text=='Подключить')
scheduled() assert(count==1,'Stopped polling must not restart')
state.connectButton.press() assert(count==2)
request.error('HTTP error') assert(not state.busy and not state.connected and #queue==1)
request.failure('Duplicate callback') assert(#queue==1)
panel:DestroySelf() assert(state.connectButton==nil and state.status==nil)
panel=config.content() assert(state.connectButton.text=='Остановить')
state.connectButton.press()
Commands.slbridge('start') assert(count==3)
request.success('json-response') assert(state.connected and state.cursor=='84')
Commands.slbridge('stop') assert(not state.active)
local retained=state.body.children[1]
Commands.slbridge('start') request.success({data={events={ev},cursor=84}})
assert(state.body.children[1]==retained and messages==1,'Duplicates and empty polling must not rebuild cards or send chat again')
Commands.slbridge('restart') request.success({data={events={},cursor=84}})
assert(state.body.children[1]==retained)
Commands.slbridge('restart')
request.success({data={events={{id=85,actor='Mage',title='Legacy',text='Legacy',summary='Saved',display={primary={label='Урон',value=52},secondary={label='СЛ спасброска',value=15},detail='Ячейка 6 · Провал 52 · успех 26'}}},cursor=85}})
assert(find(panel,'Провал: 52 / Успех: 26'),'Older backend still gets a readable card') check(panel)
Commands.slbridge('stop')
print('PASS: compact card bounds, full description toggle, save outcomes, legacy fallback, stable empty polling, connect/stop, lifecycle')
