import { useState } from 'react';
import { ChevronRight, Dice5, Pencil, Plus, RotateCcw, Search, Sparkles, Trash2, Zap } from 'lucide-react';
import { useApp, useAction } from '../../app';
import { Badge, Button, Card, Confirm, Field, Modal } from '../../components/ui';
import type { Json } from '../../api/client';
import AbilityEditor from './AbilityEditor';
import SpellCatalog from './SpellCatalog';
import { abilities, skills, conditions, modifier, signed } from './constants';

export function SheetRail({sheet,draft,blocked,onRoll,onEdit,onChange}: {
  sheet: Json;
  draft: Json;
  blocked: boolean;
  onRoll: (kind: string, key: string) => void;
  onEdit: () => void;
  onChange: (key: string, value: unknown) => void;
}) {
  const proficiency=draft.proficiency_override ?? sheet.computed.proficiency;
  const score=(key:string)=>modifier(draft.abilities[key]);
  const saveBonus=(key:string)=>score(key)+(draft.saves.includes(key)?proficiency:0);
  const skillBonus=(key:string,ability:string)=>score(ability)+proficiency*(draft.skills[key]||0);
  const cycleSkill=(key:string)=>onChange('skills',{...draft.skills,[key]:((draft.skills[key]||0)+1)%3});
  return <aside className="classic-sheet-rail" aria-label="Характеристики персонажа">
    <div className="classic-rail-head"><span>Характеристики</span><button onClick={onEdit}>Все параметры</button></div>
    <div className="classic-ability-stack">
      {Object.entries(abilities).map(([key,label])=><div className="classic-score" key={key}>
        <span>{label}</span><strong>{signed(score(key))}</strong>
        <input aria-label={`Значение: ${label}`} type="number" min={1} max={30} value={draft.abilities[key]} onChange={e=>onChange('abilities',{...draft.abilities,[key]:Number(e.target.value)})}/>
        <button aria-label={`Бросить проверку: ${label}`} disabled={blocked} onClick={()=>onRoll('ability',key)}><Dice5 size={15}/></button>
      </div>)}
    </div>
    <div className="classic-rail-section"><h3>Спасброски</h3>{Object.entries(abilities).map(([key,label])=><div className="classic-rail-row" key={key}>
      <input type="checkbox" aria-label={`Владение спасброском: ${label}`} checked={draft.saves.includes(key)} onChange={e=>onChange('saves',e.target.checked?[...draft.saves,key]:draft.saves.filter((v:string)=>v!==key))}/>
      <span>{label}</span><b>{signed(saveBonus(key))}</b><button aria-label={`Бросить спасбросок: ${label}`} disabled={blocked} onClick={()=>onRoll('save',key)}><Dice5 size={15}/></button>
    </div>)}</div>
    <details className="classic-rail-section classic-skill-list" open><summary>Навыки</summary>
      {Object.entries(skills).map(([key,[label,ability]])=><div className="classic-rail-row" key={key}>
        <button className={`classic-skill-level level-${draft.skills[key]||0}`} onClick={()=>cycleSkill(key)} aria-label={`Владение навыком: ${label} — ${['нет','владение','экспертиза'][draft.skills[key]||0]}`} title="Нажатия: нет → владение → экспертиза → нет">{['○','●','◆'][draft.skills[key]||0]}</button>
        <span>{label}</span><b>{signed(skillBonus(key,ability))}</b><button aria-label={`Бросить навык: ${label}`} disabled={blocked} onClick={()=>onRoll('skill',key)}><Dice5 size={15}/></button>
      </div>)}
    </details>
    <div className="classic-passive"><small>Пассивная внимательность</small><strong>{10+skillBonus('perception','wis')}</strong></div>
  </aside>;
}

function QuickAction({item,sheet,disabled,busy,onUse,onDetail,onEdit,onArchive}:{
  item:Json;sheet:Json;disabled:boolean;busy:boolean;
  onUse:(item:Json,level:number)=>void;onDetail:()=>void;onEdit:()=>void;onArchive:()=>void;
}) {
  const [selected,setSelected]=useState<number|null>(null);
  const levels=item.kind==='spell'&&item.level>0?(item.upcast_allowed?Array.from({length:10-item.level},(_,i)=>i+item.level):[item.level]):[0];
  const available=levels.filter(level=>level===0||(sheet.slots[String(level)]&&sheet.slots[String(level)].max>sheet.slots[String(level)].used));
  const level=selected!==null&&available.includes(selected)?selected:(available[0]??item.level);
  return <article className="classic-quick-action"><div className="classic-quick-info"><small>{item.kind==='spell'?(item.level?`${item.level} круг`:'Заговор'):'Атака'}</small><h4>{item.name}</h4><span>{[item.dice,item.damage_type].filter(Boolean).join(' · ')||item.casting_time||'По описанию'}</span></div><div className="classic-quick-controls">
    {item.kind==='spell'&&item.level>0&&<select aria-label={`Ячейка для быстрого применения ${item.name}`} value={level} onChange={e=>setSelected(Number(e.target.value))}>{levels.map(n=><option key={n} value={n} disabled={!available.includes(n)}>{n} ур. · {Math.max(0,(sheet.slots[String(n)]?.max??0)-(sheet.slots[String(n)]?.used??0))}</option>)}</select>}
    <button aria-label={`Подробнее: ${item.name}`} title="Подробнее" onClick={onDetail}><ChevronRight size={16}/></button>
    <button aria-label={`Изменить ${item.name}`} title="Редактировать" onClick={onEdit}><Pencil size={15}/></button>
    <button aria-label={`Удалить ${item.name}`} title="Удалить" onClick={onArchive}><Trash2 size={15}/></button>
    <Button disabled={disabled||busy||!available.length} aria-label={`${item.kind==='spell'?'Применить':'Атаковать'} ${item.name}`} title={item.kind==='spell'?'Применить':'Атаковать'} onClick={()=>onUse(item,level)}>{item.kind==='spell'?<Sparkles size={16}/>:<Zap size={16}/>}</Button>
  </div></article>;
}

export function SheetOverview({sheet,draft,actions,characterId,disabled,busy,restoreDisabled,onUse,onTab,onRoll,onChange,onRestore}:{
  sheet:Json;draft:Json;actions:Json[];characterId:number;disabled:boolean;busy:boolean;restoreDisabled:boolean;
  onUse:(item:Json,level:number)=>void;onTab:(tab:string)=>void;onRoll:(kind:string,key?:string)=>void;
  onChange:(key:string,value:unknown)=>void;onRestore:()=>void;
}) {
  const app=useApp();
  const archiveAction=useAction('Действие удалено');
  const [spellSearch,setSpellSearch]=useState(''),[spellLevel,setSpellLevel]=useState(''),[attackSearch,setAttackSearch]=useState('');
  const [editor,setEditor]=useState<{kind:'attack'|'spell';item?:Json}|null>(null);
  const [catalog,setCatalog]=useState(false),[detail,setDetail]=useState<Json|null>(null),[archive,setArchive]=useState<Json|null>(null);
  const attacks=actions.filter(item=>item.kind==='attack'&&item.name.toLocaleLowerCase('ru').includes(attackSearch.trim().toLocaleLowerCase('ru'))).sort((a,b)=>a.name.localeCompare(b.name,'ru'));
  const spells=actions.filter(item=>item.kind==='spell'&&(!spellLevel||String(item.level)===spellLevel)&&(`${item.name} ${item.description||''}`).toLocaleLowerCase('ru').includes(spellSearch.trim().toLocaleLowerCase('ru'))).sort((a,b)=>a.level-b.level||a.name.localeCompare(b.name,'ru'));
  const showAction=(item:Json)=><QuickAction key={item.id} item={item} sheet={sheet} disabled={disabled} busy={busy} onUse={onUse} onDetail={()=>setDetail(item)} onEdit={()=>setEditor({kind:item.kind,item})} onArchive={()=>setArchive(item)}/>;
  const slots=Object.entries(sheet.slots).filter(([,value])=>(value as Json).max>0);
  const setNumber=(key:string)=>(e:React.ChangeEvent<HTMLInputElement>)=>onChange(key,Number(e.target.value));
  return <div className="classic-overview">
    <div className="classic-overview-top"><Card><div className="section-title"><h2>Боевые показатели</h2></div>
      <div className="classic-combat-values"><Field label="Класс доспеха"><input aria-label="Класс доспеха на обзоре" type="number" min={0} max={50} value={draft.armor_class} onChange={setNumber('armor_class')}/></Field><Field label="Бонус инициативы"><input aria-label="Бонус инициативы на обзоре" type="number" min={-30} max={30} value={draft.initiative_bonus} onChange={setNumber('initiative_bonus')}/></Field><Field label="Скорость, футы"><input aria-label="Скорость на обзоре" type="number" min={0} max={1000} value={draft.speed} onChange={setNumber('speed')}/></Field><Field label="Бонус мастерства" hint="Пусто — по уровню"><input aria-label="Бонус мастерства на обзоре" type="number" min={0} max={15} value={draft.proficiency_override??''} placeholder={String(sheet.computed.proficiency)} onChange={e=>onChange('proficiency_override',e.target.value===''?null:Number(e.target.value))}/></Field></div>
      <div className="classic-combat-footer"><Button variant="secondary" disabled={disabled} onClick={()=>onRoll('initiative')}><Dice5 size={16}/> Инициатива {signed(modifier(draft.abilities.dex)+draft.initiative_bonus)}</Button></div>
      <details className="classic-conditions"><summary><span>Состояния</span><span className="classic-active-conditions">{draft.conditions.length?draft.conditions.map((c:string)=><Badge key={c}>{c}</Badge>):<small className="muted">Нет · нажмите, чтобы отметить</small>}</span></summary><div className="condition-picker">{conditions.map(c=><label key={c} className={draft.conditions.includes(c)?'selected':''}><input type="checkbox" checked={draft.conditions.includes(c)} onChange={e=>onChange('conditions',e.target.checked?[...draft.conditions,c]:draft.conditions.filter((v:string)=>v!==c))}/>{c}</label>)}</div></details>
    </Card><Card><div className="section-title"><h2>Магия</h2><Button variant="secondary" disabled={restoreDisabled} onClick={onRestore}><RotateCcw size={15}/> Сбросить ячейки</Button></div>
      <div className="classic-magic-values"><span>Атака <b>{signed(sheet.computed.spell_attack)}</b></span><span>СЛ спасброска <b>{sheet.computed.spell_dc}</b></span></div>
      <div className="classic-slot-pips">{slots.length?slots.map(([level,value])=><span key={level} title={`Ячейки ${level} уровня: ${(value as Json).max-(value as Json).used} из ${(value as Json).max}`}>{level} ур. <b>{(value as Json).max-(value as Json).used}/{(value as Json).max}</b></span>):<small className="muted">Ячейки не настроены</small>}</div>
      <Button variant="ghost" onClick={()=>onTab('spells')}>Настроить ячейки <ChevronRight size={15}/></Button>
    </Card></div>
    <div className="classic-overview-actions"><Card><div className="section-title"><div><span className="eyebrow">ОРУЖИЕ И ПРИЁМЫ</span><h2>Атаки <Badge>{actions.filter(a=>a.kind==='attack').length}</Badge></h2></div><Button variant="secondary" onClick={()=>setEditor({kind:'attack'})}><Plus size={15}/> Добавить</Button></div>
      <label className="classic-action-search"><Search size={15}/><input aria-label="Поиск атак на обзоре" placeholder="Найти атаку…" value={attackSearch} onChange={e=>setAttackSearch(e.target.value)}/></label>
      <div className="classic-action-scroll" aria-label="Атаки персонажа">{attacks.map(showAction)}{!attacks.length&&<p className="muted">{attackSearch?'Атака не найдена.':'Добавьте первую атаку.'}</p>}</div>
      <Button variant="ghost" onClick={()=>onTab('combat')}>Полный раздел атак <ChevronRight size={15}/></Button>
    </Card><Card><div className="section-title"><div><span className="eyebrow">БЫСТРОЕ СОТВОРЕНИЕ</span><h2>Заклинания <Badge>{actions.filter(a=>a.kind==='spell').length}</Badge></h2></div><div className="classic-add-actions"><Button variant="secondary" onClick={()=>setCatalog(true)}><Plus size={15}/> Из каталога</Button><Button variant="ghost" onClick={()=>setEditor({kind:'spell'})}>Своё</Button></div></div>
      <div className="classic-spell-filters"><label className="classic-action-search"><Search size={15}/><input aria-label="Поиск заклинаний на обзоре" placeholder="Найти заклинание…" value={spellSearch} onChange={e=>setSpellSearch(e.target.value)}/></label><select aria-label="Круг заклинаний на обзоре" value={spellLevel} onChange={e=>setSpellLevel(e.target.value)}><option value="">Все круги</option>{Array.from({length:10},(_,n)=><option value={n} key={n}>{n===0?'Заговоры':`${n} круг`}</option>)}</select></div>
      <div className="classic-action-scroll" aria-label="Заклинания персонажа">{spells.map((item,index)=><div key={item.id}>{(index===0||spells[index-1].level!==item.level)&&<div className="classic-action-group">{item.level===0?'Заговоры':`${item.level} круг`}</div>}{showAction(item)}</div>)}{!spells.length&&<p className="muted">{spellSearch||spellLevel?'Заклинаний по фильтру нет.':'Добавьте заклинание из каталога или создайте своё.'}</p>}</div>
      <Button variant="ghost" onClick={()=>onTab('spells')}>Ячейки и полный раздел <ChevronRight size={15}/></Button>
    </Card></div>
    <Card className="classic-overview-notes"><div className="section-title"><h2>Инвентарь и заметки</h2><Button variant="ghost" onClick={()=>onTab('notes')}>Полный раздел <ChevronRight size={15}/></Button></div><div className="classic-notes-grid"><Field label="Инвентарь"><textarea aria-label="Инвентарь на обзоре" rows={3} maxLength={20000} placeholder="Предметы и снаряжение…" value={draft.inventory} onChange={e=>onChange('inventory',e.target.value)}/></Field><Field label="Заметки"><textarea aria-label="Заметки на обзоре" rows={3} maxLength={20000} placeholder="Личные записи…" value={draft.notes} onChange={e=>onChange('notes',e.target.value)}/></Field></div></Card>
    {editor&&<AbilityEditor characterId={characterId} initial={editor.item} kind={editor.kind} spellAbility={sheet.spell_ability} onClose={()=>setEditor(null)}/>}
    {catalog&&<SpellCatalog characterId={characterId} existing={actions} onClose={()=>setCatalog(false)}/>}
    {detail&&<Modal title={detail.name} onClose={()=>setDetail(null)} wide><div className="classic-action-detail"><div className="inline-tags"><Badge>{detail.kind==='spell'?(detail.level?`${detail.level} круг`:'Заговор'):'Атака'}</Badge>{detail.dice&&<Badge>{detail.dice} · {detail.damage_type}</Badge>}</div><p className="muted">{[detail.casting_time,detail.range,detail.duration].filter(Boolean).join(' · ')}</p><p className="preserve-lines">{detail.description||'Описание для этого действия не заполнено.'}</p><div className="actions"><Button variant="secondary" onClick={()=>{setEditor({kind:detail.kind,item:detail});setDetail(null);}}>Редактировать</Button><Button variant="ghost" onClick={()=>setDetail(null)}>Закрыть</Button></div></div></Modal>}
    {archive&&<Confirm title={`Удалить «${archive.name}»?`} text="Действие исчезнет из листа. История бросков сохранится." busy={archiveAction.isPending} onClose={()=>setArchive(null)} onConfirm={()=>archiveAction.mutate({path:`/abilities/${archive.id}/?campaign=${app.cid}`,method:'PATCH',body:{version:archive.version,active:false}},{onSuccess:()=>setArchive(null)})}/>}
  </div>;
}
