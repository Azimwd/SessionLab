import { useState } from 'react';
import { useApp, useData, useAction } from '../../app';
import { Badge, Button, Card, Empty, ErrorBox, Field, Modal } from '../../components/ui';
import type { Json } from '../../api/client';
import { conditions } from '../sheets/constants';

const defenseNames:Record<string,string>={normal:'Обычный урон',resistance:'Сопротивление — половина',immunity:'Иммунитет — без урона',vulnerability:'Уязвимость — двойной'};
export function DefenseFields({types,value,onChange}:{types:Json;value:Json;onChange:(v:Json)=>void}) {
  return <details><summary>Сопротивления, иммунитеты и уязвимости</summary><p className="muted">Настройки относятся к этому участнику сцены. Мастер задаёт их при добавлении цели и меняет в её настройках. При уроне они учитываются автоматически.</p><div className="scene-defense-grid">{Object.entries({all:'Все типы',...types}).map(([key,title])=><Field key={key} label={String(title)}><select value={value[key]||'normal'} onChange={e=>onChange({...value,[key]:e.target.value})}>{Object.entries(defenseNames).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></Field>)}</div></details>;
}

export function TargetDamage({event}:{event:Json}) {
  const a=useApp(),[open,setOpen]=useState(false),[index,setIndex]=useState(0),[selected,setSelected]=useState<number[]>([]),[outcomes,setOutcomes]=useState<Record<string,Json>>({});
  const view=a.masterMode?'dm':'player';
  const targets=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,open&&!!a.cid);
  const action=useAction('Урон применён');
  const parts:Json[]=event.payload.parts||[event.payload];
  const usable=parts.map((p,i)=>({p,i})).filter(({p})=>p.damage && Number(p.damage.total)>=0);
  if(!event.id||event.kind!=='ability'||!usable.length||['healing','лечение'].includes(String(event.payload.damage_type).toLowerCase()))return null;
  const activeIndex=usable.some(v=>v.i===index)?index:usable[0].i;
  const part=parts[activeIndex],attack=!!part?.roll;
  const visibleTargets:Json[]=targets.data?.targets?.filter((t:Json)=>t.targetable||a.masterMode)||[];
  const choose=(id:number)=>setSelected(prev=>prev.includes(id)?prev.filter(x=>x!==id):attack?[id]:[...prev,id]);
  const setOutcome=(id:number,value:Json)=>setOutcomes(prev=>({...prev,[String(id)]:value}));
  const complete=selected.length>0&&selected.every(id=>part.save?['success','failure'].includes(outcomes[id]?.save_outcome):attack?typeof outcomes[id]?.hit==='boolean':true);
  const apply=()=>{
    const chosen:Record<string,Json>={};
    for(const id of selected) chosen[String(id)]=outcomes[id]||{};
    action.mutate({path:`/scene/damage/?campaign=${a.cid}`,body:{source_event:event.id,part_index:activeIndex,targets:selected,outcomes:chosen}},
      {onSuccess:()=>{setOpen(false);setSelected([]);setOutcomes({});}});
  };
  return <div className="scene-damage-chooser"><Button variant="secondary" onClick={()=>setOpen(!open)}>{open?'Скрыть выбор целей':'Применить к цели'}</Button>{open&&<div className="scene-chooser-body">
    {usable.length>1&&<Field label="Какой бросок применить"><select value={activeIndex} onChange={e=>{setIndex(Number(e.target.value));setSelected([]);setOutcomes({});}}>{usable.map(({p,i})=><option key={i} value={i}>Бросок {i+1} · {p.damage.total} урона</option>)}</select></Field>}
    <p className="muted">{attack?'Выберите одну цель и отметьте попадание.':'Выберите цели и укажите известный исход спасброска для каждой.'} Защита применяется автоматически по настройкам мастера. ХП целей скрыты.</p>
    {targets.error&&<ErrorBox error={targets.error}/>}
    <div className="scene-target-picker">{visibleTargets.map(t=><label key={t.id} className={selected.includes(t.id)?'selected':''}><input type="checkbox" checked={selected.includes(t.id)} onChange={()=>choose(t.id)}/><span>{t.name}</span></label>)}</div>
    {selected.map(id=>{const t=visibleTargets.find(v=>v.id===id);if(!t)return null;return <div className="scene-target-outcome" key={id}><strong>{t.name}</strong>{part.save?<Field label={`Спасбросок: ${t.name}`}><select value={outcomes[id]?.save_outcome||''} onChange={e=>setOutcome(id,{save_outcome:e.target.value})}><option value="">Выберите исход</option><option value="failure">Не прошёл — {part.save.failed_damage??part.damage.total} урона до защиты</option><option value="success">Прошёл — {part.save.success_damage??'по правилам'} урона до защиты</option></select></Field>:attack?<Field label={`Попадание: ${t.name}`}><select value={outcomes[id]?.hit===undefined?'':outcomes[id].hit?'hit':'miss'} onChange={e=>setOutcome(id,e.target.value?{hit:e.target.value==='hit'}:{})}><option value="">Выберите исход</option><option value="hit">Попал</option><option value="miss">Промах</option></select></Field>:<p>Исходный урон: {part.damage.total}. Защиту учтёт сервер.</p>}</div>})}
    {targets.data?.targets&&!visibleTargets.length&&<p>Мастер ещё не добавил доступные цели в сцену.</p>}
    <Button disabled={!complete||action.isPending||selected.some(id=>!visibleTargets.some(t=>t.id===id))} onClick={apply}>Нанести урон ({selected.length})</Button>
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

export default function Scene({characters}:{characters:Json[]}) {
  const a=useApp(),view=a.masterMode?'dm':'player';
  const state=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,!!a.cid);
  const pending=useData<Json[]>(`/scene/damage/?campaign=${a.cid}&view=${view}&status=applied`,!!a.cid);
  const action=useAction('Сцена обновлена');
  const [adding,setAdding]=useState(false),[editing,setEditing]=useState<Json|null>(null);
  const [source,setSource]=useState(''),[count,setCount]=useState(1),[protection,setProtection]=useState<Json>({});
  const selected=characters.find(c=>String(c.id)===source)||characters[0];
  const types=state.data?.damage_types||{};
  return <Card className="scene-panel"><div className="section-title"><div><div className="eyebrow">УЧАСТНИКИ ТЕКУЩЕЙ СЦЕНЫ</div><h2>Цели сцены</h2><p>{a.masterMode?'У каждого экземпляра NPC собственное здоровье. Исходный лист остаётся шаблоном.':'Выбирайте цели из результата атаки или заклинания. Здоровье целей видит только мастер.'}</p></div>{a.masterMode&&<Button disabled={!a.sid} onClick={()=>setAdding(true)}>Добавить из листа</Button>}</div>
    {state.error&&<ErrorBox error={state.error}/>}{action.error&&<ErrorBox error={action.error}/>}
    <div className="scene-target-grid">{state.data?.targets?.map((t:Json)=><article className="scene-target-card" key={t.id}><strong>{t.name}</strong><div className="inline-tags">{!t.targetable&&<Badge>Не является целью</Badge>}{a.masterMode&&!t.visible&&<Badge>Скрыта</Badge>}</div>{a.masterMode&&<><p><b>{t.hp_current}/{t.hp_max}</b> ХП {t.hp_temp>0&&`+ ${t.hp_temp} временных`}</p><div className="actions"><Button variant="secondary" onClick={()=>setEditing(t)}>Настроить</Button><Button variant="ghost" disabled={action.isPending} onClick={()=>action.mutate({path:`/scene/targets/${t.id}/?campaign=${a.cid}`,method:'PATCH',body:{version:t.version,active:false}})}>Убрать</Button></div></>}</article>)}</div>
    {state.data?.targets&&!state.data.targets.length&&<Empty title="В сцене пока нет целей"/>}
    <h3>{a.masterMode?'Последние применения урона':'Мои применения урона'}</h3><div className="scene-requests">{(Array.isArray(pending.data)?pending.data:[]).map(r=><div key={r.id}><span><b>{r.label}</b> → {r.target_name}<small>{r.requester_name} · Урон применён</small></span></div>)}{!pending.data?.length&&<p className="muted">Пока нет применений урона.</p>}{pending.error&&<ErrorBox error={pending.error}/>}</div>
    {adding&&<Modal title="Добавить участников сцены" onClose={()=>setAdding(false)}><form onSubmit={e=>{e.preventDefault();action.mutate({path:`/scene/targets/?campaign=${a.cid}`,body:{source:selected?.id,count:selected?.kind==='player'?1:count,defenses:protection}},{onSuccess:()=>{setAdding(false);setProtection({});}});}}><Field label="Лист-шаблон"><select value={selected?.id||''} onChange={e=>setSource(e.target.value)}>{characters.map(c=><option key={c.id} value={c.id}>{c.name} · {c.kind==='npc'?'NPC':'Игрок'}</option>)}</select></Field>{selected?.kind==='npc'&&<Field label="Количество экземпляров"><input type="number" min={1} max={20} value={count} onChange={e=>setCount(Number(e.target.value))}/></Field>}<DefenseFields types={types} value={protection} onChange={setProtection}/>{action.error&&<ErrorBox error={action.error}/>}<Button disabled={action.isPending||!selected}>Добавить в сцену</Button></form></Modal>}
    {editing&&<TargetEditor target={editing} types={types} onClose={()=>setEditing(null)}/>}
  </Card>;
}
