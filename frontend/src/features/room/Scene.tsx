import { useState } from 'react';
import { useApp, useData, useAction } from '../../app';
import { Badge, Button, Card, Empty, ErrorBox, Field, Modal } from '../../components/ui';
import type { Json } from '../../api/client';
import { conditions } from '../sheets/constants';

const defenseNames:Record<string,string>={normal:'Обычный урон',resistance:'Сопротивление — половина',immunity:'Иммунитет — без урона',vulnerability:'Уязвимость — двойной'};
export function DefenseFields({types,value,onChange}:{types:Json;value:Json;onChange:(v:Json)=>void}) {
  return <details><summary>Сопротивления, иммунитеты и уязвимости</summary><p className="muted">Настройки относятся к этому участнику сцены. Мастер может изменить их при применении урона.</p><div className="scene-defense-grid">{Object.entries({all:'Все типы',...types}).map(([key,title])=><Field key={key} label={String(title)}><select value={value[key]||'normal'} onChange={e=>onChange({...value,[key]:e.target.value})}>{Object.entries(defenseNames).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field>)}</div></details>;
}

export function TargetDamage({event}:{event:Json}) {
  const a=useApp(),[open,setOpen]=useState(false),[index,setIndex]=useState(0),[selected,setSelected]=useState<number[]>([]);
  const view=a.masterMode?'dm':'player';
  const targets=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,open&&!!a.cid);
  const action=useAction('Запрос урона отправлен мастеру');
  const parts:Json[]=event.payload.parts||[event.payload];
  const usable=parts.map((p,i)=>({p,i})).filter(({p})=>p.damage && Number(p.damage.total)>=0);
  if(!event.id||event.kind!=='ability'||!usable.length||['healing','лечение'].includes(String(event.payload.damage_type).toLowerCase()))return null;
  const part=parts[index],attack=!!part?.roll;
  const choose=(id:number)=>setSelected(prev=>prev.includes(id)?prev.filter(x=>x!==id):attack?[id]:[...prev,id]);
  return <div className="scene-damage-chooser"><Button variant="secondary" onClick={()=>setOpen(!open)}>{open?'Скрыть выбор целей':'Применить к цели'}</Button>{open&&<div className="scene-chooser-body">
    {usable.length>1&&<Field label="Какой бросок применить"><select value={index} onChange={e=>{setIndex(Number(e.target.value));setSelected([]);}}>{usable.map(({p,i})=><option key={i} value={i}>Бросок {i+1} · {p.damage.total} урона</option>)}</select></Field>}
    <p className="muted">{attack?'Выберите одну цель для этого броска атаки.':'Можно выбрать несколько целей.'} Урон применит мастер; здоровье целей скрыто.</p>
    {targets.error&&<ErrorBox error={targets.error}/>}
    <div className="scene-target-picker">{targets.data?.targets?.filter((t:Json)=>t.targetable||a.masterMode).map((t:Json)=><label key={t.id} className={selected.includes(t.id)?'selected':''}><input type="checkbox" checked={selected.includes(t.id)} onChange={()=>choose(t.id)}/><span>{t.name}</span></label>)}</div>
    {targets.data?.targets&&!targets.data.targets.length&&<p>Мастер ещё не добавил цели в сцену.</p>}
    <Button disabled={!selected.length||action.isPending} onClick={()=>action.mutate({path:`/scene/damage/?campaign=${a.cid}`,body:{source_event:event.id,part_index:index,targets:selected}},{onSuccess:()=>{setOpen(false);setSelected([]);}})}>Отправить мастеру ({selected.length})</Button>
    {action.error&&<ErrorBox error={action.error}/>}
  </div>}</div>;
}

function TargetEditor({target,types,onClose}:{target:Json;types:Json;onClose:()=>void}) {
  const a=useApp(),action=useAction('Цель обновлена');
  const [draft,setDraft]=useState<Json>({...target});
  const set=(key:string,value:unknown)=>setDraft({...draft,[key]:value});
  return <Modal title={`Настройки: ${target.name}`} onClose={onClose}><form onSubmit={e=>{e.preventDefault();action.mutate({path:`/scene/targets/${target.id}/?campaign=${a.cid}`,method:'PATCH',body:{version:target.version,name:draft.name,visible:draft.visible,targetable:draft.targetable,hp_current:Number(draft.hp_current),hp_max:Number(draft.hp_max),hp_temp:Number(draft.hp_temp),defenses:draft.defenses,conditions:draft.conditions||[]}},{onSuccess:onClose});}}>
    <Field label="Имя цели"><input value={draft.name} maxLength={100} required onChange={e=>set('name',e.target.value)}/></Field>
    <div className="scene-defense-grid">{[['hp_current','Текущие ХП'],['hp_max','Максимум ХП'],['hp_temp','Временные ХП']].map(([k,label])=><Field key={k} label={label}><input type="number" min={k==='hp_max'?1:0} max={1000000} value={draft[k]} onChange={e=>set(k,e.target.value)} required/></Field>)}</div>
    <label><input type="checkbox" checked={draft.visible} onChange={e=>set('visible',e.target.checked)}/> Видна игрокам</label><br/>
    <label><input type="checkbox" checked={draft.targetable} onChange={e=>set('targetable',e.target.checked)}/> Игроки могут выбирать целью</label>
    {target.linked_sheet&&<p className="muted">Это персонаж игрока: ХП синхронизированы с его листом.</p>}
    <details><summary>Состояния этого участника</summary><div className="scene-target-picker">{conditions.map(name=><label key={name}><input type="checkbox" checked={(draft.conditions||[]).includes(name)} onChange={e=>set('conditions',e.target.checked?[...(draft.conditions||[]),name]:(draft.conditions||[]).filter((v:string)=>v!==name))}/>{name}</label>)}</div></details>
    <DefenseFields types={types} value={draft.defenses} onChange={v=>set('defenses',v)}/>
    {action.error&&<ErrorBox error={action.error}/>}<Button disabled={action.isPending}>Сохранить</Button>
  </form></Modal>;
}

function ResolveDialog({row,types,onClose}:{row:Json;types:Json;onClose:()=>void}) {
  const a=useApp(),action=useAction('Запрос обработан');
  const [save,setSave]=useState(''),[saveMode,setSaveMode]=useState('normal'),[hit,setHit]=useState(true),[defense,setDefense]=useState('auto'),[override,setOverride]=useState('');
  const part=row.part;
  const submit=(apply:boolean)=>action.mutate({path:`/scene/damage/${row.id}/resolve/?campaign=${a.cid}`,body:apply?{action:'apply',save_outcome:save,save_mode:saveMode,hit,defense,...(override!==''?{base_damage:Number(override)}:{})}:{action:'reject'}},{onSuccess:onClose});
  return <Modal title={`${row.label} → ${row.target_name}`} onClose={onClose}>
    <p>{row.requester_name} · исходный урон <b>{part.damage.total}</b> · {row.damage_type||'тип не указан'}</p>
    <p className="muted">ХП цели (только мастер): {row.target_detail.hp_current}/{row.target_detail.hp_max} · временные {row.target_detail.hp_temp}</p>
    {part.roll&&<><p>Атака: <b>{part.roll.total}</b> · {part.roll.mode==='advantage'?'Преимущество':part.roll.mode==='disadvantage'?'Помеха':'Обычный бросок'}</p><label><input type="checkbox" checked={hit} onChange={e=>setHit(e.target.checked)}/> Попадание подтверждено</label></>}
    {part.save&&<><p>Спасбросок: {part.save.ability.toUpperCase()} · СЛ {part.save.dc}. Провал: {part.save.failed_damage??part.damage.total}; успех: {part.save.success_damage??'по решению мастера'}.</p><Field label="Результат спасброска этой цели"><select value={save} onChange={e=>setSave(e.target.value)}><option value="">Выберите результат</option><option value="failure">Не прошла</option><option value="success">Прошла</option><option value="roll">Бросить на сервере и применить результат</option></select></Field>{save==='roll'&&<Field label="Режим спасброска"><select value={saveMode} onChange={e=>setSaveMode(e.target.value)}><option value="normal">Обычный</option><option value="advantage">Преимущество</option><option value="disadvantage">Помеха</option></select></Field>}</>}
    <Field label="Защита от этого урона"><select value={defense} onChange={e=>setDefense(e.target.value)}><option value="auto">По настройкам цели — {defenseNames[row.effective_defense||'normal']}</option>{Object.entries(defenseNames).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field>
    <div className="inline-tags">{Object.entries(row.target_detail.defenses||{}).filter(([,v])=>v!=='normal').map(([key,v])=><Badge key={key}>{key==='all'?'Все типы':types[key]||key}: {defenseNames[String(v)]}</Badge>)}</div>{!row.recognized_damage_type&&<p className="muted">Тип урона не распознан. При необходимости выберите защиту вручную.</p>}
    <Field label="Урон по решению мастера (необязательно)" hint="Заменяет урон после спасброска/попадания, до сопротивления или иммунитета."><input type="number" min={0} max={1000000} value={override} placeholder="Оставить рассчитанный" onChange={e=>setOverride(e.target.value)}/></Field>
    <p className="muted">Сначала учитывается спасбросок, затем сопротивление/иммунитет. Временные ХП поглощают урон первыми. Игрокам не передаются ХП и настройки защиты.</p>
    {action.error&&<ErrorBox error={action.error}/>}<div className="actions"><Button disabled={action.isPending||!!part.save&&!save} onClick={()=>submit(true)}>Применить урон</Button><Button variant="secondary" disabled={action.isPending} onClick={()=>submit(false)}>Отклонить</Button></div>
  </Modal>;
}

export default function Scene({characters}:{characters:Json[]}) {
  const a=useApp(),view=a.masterMode?'dm':'player';
  const state=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,!!a.cid);
  const pending=useData<Json[]>(`/scene/damage/?campaign=${a.cid}&view=${view}${a.masterMode?'&status=pending':''}`,!!a.cid);
  const action=useAction('Сцена обновлена');
  const [adding,setAdding]=useState(false),[editing,setEditing]=useState<Json|null>(null),[resolving,setResolving]=useState<Json|null>(null);
  const [source,setSource]=useState(''),[count,setCount]=useState(1),[protection,setProtection]=useState<Json>({});
  const selected=characters.find(c=>String(c.id)===source)||characters[0];
  const types=state.data?.damage_types||{};
  return <Card className="scene-panel"><div className="section-title"><div><div className="eyebrow">УЧАСТНИКИ ТЕКУЩЕЙ СЦЕНЫ</div><h2>Цели сцены</h2><p>{a.masterMode?'У каждого экземпляра NPC собственное здоровье. Исходный лист остаётся шаблоном.':'Выбирайте цели из результата атаки или заклинания. Здоровье целей видит только мастер.'}</p></div>{a.masterMode&&<Button disabled={!a.sid} onClick={()=>setAdding(true)}>Добавить из листа</Button>}</div>
    {state.error&&<ErrorBox error={state.error}/>}{action.error&&<ErrorBox error={action.error}/>}
    <div className="scene-target-grid">{state.data?.targets?.map((t:Json)=><article className="scene-target-card" key={t.id}><strong>{t.name}</strong><div className="inline-tags">{!t.targetable&&<Badge>Не является целью</Badge>}{a.masterMode&&!t.visible&&<Badge>Скрыта</Badge>}</div>{a.masterMode&&<><p><b>{t.hp_current}/{t.hp_max}</b> ХП {t.hp_temp>0&&`+ ${t.hp_temp} временных`}</p><div className="actions"><Button variant="secondary" onClick={()=>setEditing(t)}>Настроить</Button><Button variant="ghost" disabled={action.isPending} onClick={()=>action.mutate({path:`/scene/targets/${t.id}/?campaign=${a.cid}`,method:'PATCH',body:{version:t.version,active:false}})}>Убрать</Button></div></>}</article>)}</div>
    {state.data?.targets&&!state.data.targets.length&&<Empty title="В сцене пока нет целей"/>}
    <h3>{a.masterMode?'Ожидают применения':'Мои запросы урона'}</h3><div className="scene-requests">{(Array.isArray(pending.data)?pending.data:[]).map(r=><div key={r.id}><span><b>{r.label}</b> → {r.target_name}<small>{r.requester_name} · {r.status==='pending'?'Ожидает мастера':r.status==='applied'?'Применён':'Отклонён'}</small></span>{a.masterMode&&<Button variant="secondary" onClick={()=>setResolving(r)}>Рассмотреть</Button>}</div>)}{!pending.data?.length&&<p className="muted">Запросов нет.</p>}{pending.error&&<ErrorBox error={pending.error}/>}</div>
    {adding&&<Modal title="Добавить участников сцены" onClose={()=>setAdding(false)}><form onSubmit={e=>{e.preventDefault();action.mutate({path:`/scene/targets/?campaign=${a.cid}`,body:{source:selected?.id,count:selected?.kind==='player'?1:count,defenses:protection}},{onSuccess:()=>{setAdding(false);setProtection({});}});}}><Field label="Лист-шаблон"><select value={selected?.id||''} onChange={e=>setSource(e.target.value)}>{characters.map(c=><option key={c.id} value={c.id}>{c.name} · {c.kind==='npc'?'NPC':'Игрок'}</option>)}</select></Field>{selected?.kind==='npc'&&<Field label="Количество экземпляров"><input type="number" min={1} max={20} value={count} onChange={e=>setCount(Number(e.target.value))}/></Field>}<DefenseFields types={types} value={protection} onChange={setProtection}/>{action.error&&<ErrorBox error={action.error}/>}<Button disabled={action.isPending||!selected}>Добавить в сцену</Button></form></Modal>}
    {editing&&<TargetEditor target={editing} types={types} onClose={()=>setEditing(null)}/>}{resolving&&<ResolveDialog row={resolving} types={types} onClose={()=>setResolving(null)}/>}
  </Card>;
}
