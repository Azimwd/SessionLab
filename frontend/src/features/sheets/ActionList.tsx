import { useState } from 'react';
import { Plus, Sparkles, Pencil, Trash2, Zap } from 'lucide-react';
import { useApp, useAction } from '../../app';
import { Button, Badge, Confirm, Loading, ErrorBox } from '../../components/ui';
import type { Json } from '../../api/client';
import AbilityEditor from './AbilityEditor';
import SpellCatalog from './SpellCatalog';
import { abilities, signed } from './constants';

function ActionCard({item,sheet,busy,disabled,disabledReason,onUse,onEdit,onArchive}:{item:Json;sheet:Json;busy:boolean;disabled:boolean;disabledReason:string;onUse:(item:Json,level:number)=>void;onEdit:()=>void;onArchive:()=>void}) {
  const [chosen,setChosen]=useState(0);
  const levels=item.kind==='spell' && item.level>0?(item.upcast_allowed?Array.from({length:10-item.level},(_,i)=>i+item.level):[item.level]):[0];
  const available=levels.filter(n=>n===0 || sheet.slots[String(n)].used<sheet.slots[String(n)].max);
  const level=available.includes(chosen)?chosen:(available[0]??item.level);
  const modifier=sheet.computed.modifiers[item.ability]+(item.proficient?sheet.computed.proficiency:0)+item.bonus;
  return <article className="sheet-action-card"><div className="section-title"><div><Badge>{item.kind==='spell'?(item.level?`${item.level} ур.`:'Заговор'):'Атака'}</Badge><h3>{item.name}</h3></div><div className="actions"><button aria-label={`Изменить ${item.name}`} onClick={onEdit}><Pencil size={16}/></button><button aria-label={`Удалить ${item.name}`} onClick={onArchive}><Trash2 size={16}/></button></div></div>
    <div className="inline-tags">{item.rules_verified===false && <Badge>Эффект по описанию — решает мастер</Badge>}{item.roll_count>1 && <Badge>{item.roll_count} отдельных броска</Badge>}<Badge>{item.resolution==='attack'?`Атака ${signed(modifier)}`:item.resolution==='save'?`СЛ ${8+modifier} · ${abilities[item.save_ability]}`:'Без атаки'}</Badge>{item.dice && <Badge>{item.dice}{item.add_modifier?signed(sheet.computed.modifiers[item.ability]):''} {item.damage_type}</Badge>}{item.concentration && <Badge>Концентрация</Badge>}</div>
    <small>{[item.casting_time,item.range,item.duration].filter(Boolean).join(' · ')}</small>
    {item.description && <details><summary>Описание</summary><p className="preserve-lines">{item.description}</p></details>}
    <div className="action-cast">{item.kind==='spell' && item.level>0 && <select aria-label={`Ячейка для ${item.name}`} value={level} onChange={e=>setChosen(Number(e.target.value))}>{levels.map(n=><option key={n} value={n} disabled={!available.includes(n)}>Ячейка {n} · осталось {sheet.slots[String(n)].max-sheet.slots[String(n)].used}</option>)}</select>}<Button disabled={disabled || busy || !available.length} onClick={()=>onUse(item,level)}>{item.kind==='spell'?<Sparkles size={16}/>:<Zap size={16}/>} {item.kind==='spell'?'Применить':'Атаковать'}</Button></div>
    {(!available.length || disabledReason) && <small className="muted" role="status">{disabledReason || 'Нет свободных ячеек. Настройте их в разделе «Ресурсы».'}</small>}
  </article>;
}
export default function ActionList({items,sheet,kind,characterId,onUse,busy,disabled,disabledReason='',loading,error}:{items:Json[];sheet:Json;kind:'attack'|'spell';characterId:number;onUse:(item:Json,level:number)=>void;busy:boolean;disabled:boolean;disabledReason?:string;loading:boolean;error:unknown}) {
  const a=useApp(),action=useAction('Действие удалено');
  const [editor,setEditor]=useState<Json|null|undefined>(undefined),[archive,setArchive]=useState<Json|null>(null),[catalog,setCatalog]=useState(false);
  return <><div className="section-title"><div><h2>{kind==='spell'?'Заклинания':'Атаки'}</h2><p>{kind==='spell'?'Выберите доступную ячейку и примените заклинание.':'Бонусы берутся из сохранённого листа персонажа.'}</p></div><div className="actions">{kind==='spell' && <Button variant="secondary" onClick={()=>setCatalog(true)}><Plus size={16}/> Из каталога</Button>}<Button variant="secondary" onClick={()=>setEditor(null)}><Plus size={16}/> Своё</Button></div></div>
    {loading?<Loading/>:error?<ErrorBox error={error}/>:<div className="sheet-actions-grid">{items.filter(i=>i.kind===kind).map(item=><ActionCard key={item.id} item={item} sheet={sheet} busy={busy} disabled={disabled} disabledReason={disabledReason} onUse={onUse} onEdit={()=>setEditor(item)} onArchive={()=>setArchive(item)}/>)}</div>}
    {!loading && !items.some(i=>i.kind===kind) && <div className="empty compact"><Sparkles/><h3>{kind==='spell'?'Добавьте первое заклинание':'Добавьте свою атаку'}</h3><p>Название, кубики и характеристика — всё задаётся обычными полями.</p></div>}
    {editor!==undefined && <AbilityEditor characterId={characterId} initial={editor||undefined} kind={kind} spellAbility={sheet.spell_ability} onClose={()=>setEditor(undefined)}/>}
    {catalog && <SpellCatalog characterId={characterId} existing={items} onClose={()=>setCatalog(false)}/>}
    {archive && <Confirm title={`Удалить «${archive.name}»?`} text="Действие исчезнет из листа. Результаты прошлых бросков сохранятся." busy={action.isPending} onClose={()=>setArchive(null)} onConfirm={()=>action.mutate({path:`/abilities/${archive.id}/?campaign=${a.cid}`,method:'PATCH',body:{version:archive.version,active:false}},{onSuccess:()=>setArchive(null)})}/>}
  </>;
}
