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
  const a=useApp(),[open,setOpen]=useState(false),[indices,setIndices]=useState<number[]|null>(null),[selected,setSelected]=useState<number[]>([]),[outcomes,setOutcomes]=useState<Record<number,Record<string,Json>>>({});
  const view=a.masterMode?'dm':'player';
  const targets=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,open&&!!a.cid);
  const healing=['healing','heal','лечение','исцеление'].includes(String(event.payload.damage_type).trim().toLowerCase());
  const action=useAction(healing?'Лечение применено':'Урон применён');
  const parts:Json[]=event.payload.parts||[event.payload];
  const usable=parts.map((p,i)=>({p,i})).filter(({p})=>p.damage && Number(p.damage.total)>=0);
  if(!event.id||event.kind!=='ability'||!usable.length)return null;
  const chosenParts=usable.filter(({i})=>(indices??[usable[0].i]).includes(i));
  const attack=!healing&&chosenParts.some(({p})=>!!p.roll);
  const visibleTargets:Json[]=targets.data?.targets?.filter((t:Json)=>t.targetable||a.masterMode)||[];
  const choose=(id:number)=>setSelected(prev=>prev.includes(id)?prev.filter(x=>x!==id):attack?[id]:[...prev,id]);
  const changeParts=(next:number[])=>{
    setIndices(next);
    if(!healing&&next.some(i=>!!parts[i].roll))setSelected(prev=>prev.slice(0,1));
  };
  const setOutcome=(index:number,id:number,value:Json)=>setOutcomes(prev=>({...prev,[index]:{...prev[index],[String(id)]:value}}));
  const complete=chosenParts.length>0&&selected.length>0&&chosenParts.every(({p,i})=>selected.every(id=>healing?true:p.save?['success','failure'].includes(outcomes[i]?.[id]?.save_outcome):true));
  const apply=()=>{
    const batch=chosenParts.map(({p,i})=>({part_index:i,targets:selected,outcomes:Object.fromEntries(selected.map(id=>[String(id),{...(outcomes[i]?.[id]||{}),...(!healing&&p.roll?{hit:true}:{})}]))}));
    action.mutate({path:`/scene/damage/?campaign=${a.cid}`,body:{source_event:event.id,...(batch.length===1?batch[0]:{parts:batch})}},
      {onSuccess:()=>{setOpen(false);setSelected([]);setOutcomes({});setIndices(null);}});
  };
  return <div className="scene-damage-chooser"><Button variant="secondary" onClick={()=>setOpen(!open)}>{open?'Скрыть выбор целей':'Применить к цели'}</Button>{open&&<div className="scene-chooser-body">
    {usable.length>1&&<fieldset className="scene-roll-picker"><legend>Какие броски применить</legend><div className="actions"><Button variant="secondary" disabled={action.isPending} onClick={()=>changeParts(usable.map(v=>v.i))}>Выбрать все</Button><Button variant="ghost" disabled={action.isPending} onClick={()=>changeParts([])}>Снять выбор</Button></div>{usable.map(({p,i})=><label key={i} className={chosenParts.some(v=>v.i===i)?'selected':''}><input type="checkbox" disabled={action.isPending} checked={chosenParts.some(v=>v.i===i)} onChange={e=>changeParts(e.target.checked?[...chosenParts.map(v=>v.i),i]:chosenParts.filter(v=>v.i!==i).map(v=>v.i))}/><span>Бросок {i+1} · {p.damage.total} {healing?'лечения':'урона'}{p.roll&&` · атака ${p.roll.total}`}</span></label>)}</fieldset>}
    <p className="muted">{healing?'Выберите, кого вылечить. ХП восстанавливаются до максимума, временные ХП не меняются.':attack?'Выберите цель и нанесите урон. При промахе закройте выбор целей или снимите выбор с этого броска.':'Выберите цели и укажите известный исход спасброска для каждой.'} {!healing&&'Защита применяется автоматически для каждого броска отдельно.'} ХП целей скрыты.</p>
    {targets.error&&<ErrorBox error={targets.error}/>}
    <div className="scene-target-picker">{visibleTargets.map(t=><label key={t.id} className={selected.includes(t.id)?'selected':''}><input type="checkbox" checked={selected.includes(t.id)} disabled={action.isPending} onChange={()=>choose(t.id)}/><span>{t.name}</span></label>)}</div>
    {chosenParts.map(({p,i})=><div className="scene-part-outcomes" key={i}>{chosenParts.length>1&&<h4>Бросок {i+1} · {p.damage.total} {healing?'лечения':'урона'}</h4>}{selected.map(id=>{const t=visibleTargets.find(v=>v.id===id);if(!t)return null;const outcome=outcomes[i]?.[id]||{};const suffix=chosenParts.length>1?` · бросок ${i+1}`:'';return <div className="scene-target-outcome" key={id}><strong>{t.name}</strong>{healing?<p>Восстановление: {p.damage.total} ХП, не выше максимума.</p>:p.save?<Field label={`Спасбросок${suffix}: ${t.name}`}><select disabled={action.isPending} value={outcome.save_outcome||''} onChange={e=>setOutcome(i,id,{save_outcome:e.target.value})}><option value="">Выберите исход</option><option value="failure">Не прошёл — {p.save.failed_damage??p.damage.total} урона до защиты</option><option value="success">Прошёл — {p.save.success_damage??'по правилам'} урона до защиты</option></select></Field>:<p>Исходный урон: {p.damage.total}. Защиту учтёт сервер.</p>}</div>})}</div>)}
    {targets.data?.targets&&!visibleTargets.length&&<p>Мастер ещё не добавил доступные цели в сцену.</p>}
    <Button disabled={!complete||action.isPending||selected.some(id=>!visibleTargets.some(t=>t.id===id))} onClick={apply}>{healing?'Вылечить':'Нанести урон'} ({chosenParts.length>1?`${chosenParts.length} броска, целей: ${selected.length}`:selected.length})</Button>
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

function SceneHistory() {
  const a=useApp(),view=a.masterMode?'dm':'player';
  const [cursors,setCursors]=useState<(number|null)[]>([null]);
  const before=cursors[cursors.length-1];
  const history=useData<Json>(`/scene/damage/?campaign=${a.cid}&view=${view}&status=applied&page_size=10${before===null?'':`&before=${before}`}`,!!a.cid);
  const entries:Json[]=Array.isArray(history.data)?history.data.slice(0,10):history.data?.results||[];
  const next=history.data?.next_cursor;
  return <section className="scene-history">
    <h3>{a.masterMode?'Последние применения урона и лечения':'Мои применения урона и лечения'}</h3>
    <div key={before??'latest'} className="scene-requests" role="region" aria-label="История урона и лечения" tabIndex={0} aria-busy={history.isPending}>
      {entries.map(r=><div key={r.id}><span><b>{r.label}</b> → {r.target_name}<small>{r.requester_name} · {r.effect==='healing'?'Лечение применено':'Урон применён'}</small></span></div>)}
      {history.isPending?<p className="muted">Загрузка истории…</p>:!history.error&&!entries.length&&<p className="muted">Пока нет применений урона и лечения.</p>}
      {history.error&&<ErrorBox error={history.error}/>}
    </div>
    <nav className="scene-history-pages" aria-label="Страницы истории урона и лечения">
      <Button variant="secondary" disabled={cursors.length===1||history.isPending} onClick={()=>setCursors(prev=>prev.slice(0,-1))}>Назад</Button>
      <span className="muted" aria-live="polite">Страница {cursors.length}</span>
      <Button variant="secondary" disabled={!next||history.isPending||!!history.error} onClick={()=>{if(next)setCursors(prev=>[...prev,next]);}}>Далее</Button>
      {cursors.length>1&&<Button variant="ghost" onClick={()=>setCursors([null])}>К последним</Button>}
    </nav>
  </section>;
}

export default function Scene({characters}:{characters:Json[]}) {
  const a=useApp(),view=a.masterMode?'dm':'player';
  const state=useData<Json>(`/scene/targets/?campaign=${a.cid}&view=${view}`,!!a.cid);
  const action=useAction('Сцена обновлена');
  const [adding,setAdding]=useState(false),[editing,setEditing]=useState<Json|null>(null);
  const [source,setSource]=useState(''),[count,setCount]=useState(1),[protection,setProtection]=useState<Json>({});
  const selected=characters.find(c=>String(c.id)===source)||characters[0];
  const types=state.data?.damage_types||{};
  return <Card className="scene-panel"><div className="section-title"><div><div className="eyebrow">УЧАСТНИКИ ТЕКУЩЕЙ СЦЕНЫ</div><h2>Участники сессии</h2><p>{a.masterMode?'Здесь мастер настраивает состав текущей сцены, ХП, видимость и защиты участников. У каждого экземпляра NPC собственное здоровье.':'Выбирайте цели из результата атаки или заклинания. Здоровье целей видит только мастер.'}</p></div>{a.masterMode&&<Button disabled={!a.sid} onClick={()=>setAdding(true)}>Добавить из листа</Button>}</div>
    {state.error&&<ErrorBox error={state.error}/>}{action.error&&<ErrorBox error={action.error}/>}
    <div className="scene-target-grid">{state.data?.targets?.map((t:Json)=><article className="scene-target-card" key={t.id}><strong>{t.name}</strong><div className="inline-tags">{!t.targetable&&<Badge>Не является целью</Badge>}{a.masterMode&&!t.visible&&<Badge>Скрыта</Badge>}</div>{a.masterMode&&<><p><b>{t.hp_current}/{t.hp_max}</b> ХП {t.hp_temp>0&&`+ ${t.hp_temp} временных`}</p><div className="actions"><Button variant="secondary" onClick={()=>setEditing(t)}>Настроить</Button><Button variant="ghost" disabled={action.isPending} onClick={()=>action.mutate({path:`/scene/targets/${t.id}/?campaign=${a.cid}`,method:'PATCH',body:{version:t.version,active:false}})}>Убрать</Button></div></>}</article>)}</div>
    {state.data?.targets&&!state.data.targets.length&&<Empty title="В сцене пока нет целей"/>}
    <SceneHistory key={`${a.cid}:${a.sid}:${view}`}/>
    {adding&&<Modal title="Добавить участников сцены" onClose={()=>setAdding(false)}><form onSubmit={e=>{e.preventDefault();action.mutate({path:`/scene/targets/?campaign=${a.cid}`,body:{source:selected?.id,count:selected?.kind==='player'?1:count,defenses:protection}},{onSuccess:()=>{setAdding(false);setProtection({});}});}}><Field label="Лист-шаблон"><select value={selected?.id||''} onChange={e=>setSource(e.target.value)}>{characters.map(c=><option key={c.id} value={c.id}>{c.name} · {c.kind==='npc'?'NPC':'Игрок'}</option>)}</select></Field>{selected?.kind==='npc'&&<Field label="Количество экземпляров"><input type="number" min={1} max={20} value={count} onChange={e=>setCount(Number(e.target.value))}/></Field>}<DefenseFields types={types} value={protection} onChange={setProtection}/>{action.error&&<ErrorBox error={action.error}/>}<Button disabled={action.isPending||!selected}>Добавить в сцену</Button></form></Modal>}
    {editing&&<TargetEditor target={editing} types={types} onClose={()=>setEditing(null)}/>}
  </Card>;
}
