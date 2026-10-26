import { useState } from 'react';
import { Dice5, Sparkles, Zap, ChevronRight } from 'lucide-react';
import { Badge, Button, Card } from '../../components/ui';
import type { Json } from '../../api/client';
import { abilities, skills, modifier, signed } from './constants';

export function SheetRail({sheet, blocked, onRoll, onEdit}: {
  sheet: Json;
  blocked: boolean;
  onRoll: (kind: string, key: string) => void;
  onEdit: () => void;
}) {
  return <aside className="classic-sheet-rail" aria-label="Характеристики персонажа">
    <div className="classic-rail-head"><span>Характеристики</span><button onClick={onEdit}>Изменить</button></div>
    <div className="classic-ability-stack">
      {Object.entries(abilities).map(([key,label])=><div className="classic-score" key={key}>
        <span>{label}</span><strong>{signed(sheet.computed.modifiers[key])}</strong><small>{sheet.abilities[key]} очков</small>
        <button aria-label={`Бросить проверку: ${label}`} disabled={blocked} onClick={()=>onRoll('ability',key)}><Dice5 size={15}/></button>
      </div>)}
    </div>
    <div className="classic-rail-section"><h3>Спасброски</h3>{Object.entries(abilities).map(([key,label])=><button className="classic-rail-row" key={key} disabled={blocked} onClick={()=>onRoll('save',key)} aria-label={`Бросить спасбросок: ${label}`}><span className={sheet.saves.includes(key)?'trained':''}>{sheet.saves.includes(key)?'●':'○'}</span><span>{label}</span><b>{signed(sheet.computed.saves[key])}</b><Dice5 size={14}/></button>)}</div>
    <details className="classic-rail-section classic-skill-list"><summary>Навыки <span>18</span></summary>{Object.entries(skills).map(([key,[label,ability]])=><button className="classic-rail-row" key={key} disabled={blocked} onClick={()=>onRoll('skill',key)} aria-label={`Бросить навык: ${label}`}><span className={(sheet.skills[key]||0)>0?'trained':''}>{(sheet.skills[key]||0)>0?'●':'○'}</span><span>{label}</span><b>{signed(sheet.computed.skills[key] ?? modifier(sheet.abilities[ability]))}</b><Dice5 size={14}/></button>)}</details>
    <div className="classic-passive"><small>Пассивная внимательность</small><strong>{10+(sheet.computed.skills.perception ?? modifier(sheet.abilities.wis))}</strong></div>
  </aside>;
}

function QuickAction({item,sheet,disabled,busy,onUse}:{item:Json;sheet:Json;disabled:boolean;busy:boolean;onUse:(item:Json,level:number)=>void}) {
  const [selected,setSelected]=useState<number|null>(null);
  const levels=item.kind==='spell' && item.level>0 ? (item.upcast_allowed?Array.from({length:10-item.level},(_,i)=>i+item.level):[item.level]) : [0];
  const available=levels.filter(level=>level===0 || (sheet.slots[String(level)] && sheet.slots[String(level)].max>sheet.slots[String(level)].used));
  const level=selected!==null&&available.includes(selected)?selected:(available[0]??item.level);
  return <article className="classic-quick-action"><div><small>{item.kind==='spell'?(item.level?`${item.level} круг`:'Заговор'):'Атака'}</small><h4>{item.name}</h4><span>{[item.dice,item.damage_type].filter(Boolean).join(' · ') || item.casting_time || 'По описанию'}</span></div><div className="classic-quick-controls">{item.kind==='spell'&&item.level>0&&<select aria-label={`Ячейка для быстрого применения ${item.name}`} value={level} onChange={e=>setSelected(Number(e.target.value))}>{levels.map(n=><option key={n} value={n} disabled={!available.includes(n)}>{n} ур. · {sheet.slots[String(n)]?.max-sheet.slots[String(n)]?.used || 0}</option>)}</select>}<Button disabled={disabled||busy||!available.length} aria-label={`${item.kind==='spell'?'Применить':'Атаковать'} ${item.name}`} onClick={()=>onUse(item,level)}>{item.kind==='spell'?<Sparkles size={16}/>:<Zap size={16}/>}</Button></div></article>;
}

export function SheetOverview({sheet,actions,disabled,busy,onUse,onTab,onRoll}:{
  sheet:Json;actions:Json[];disabled:boolean;busy:boolean;
  onUse:(item:Json,level:number)=>void;onTab:(tab:string)=>void;onRoll:(kind:string,key?:string)=>void;
}) {
  const attacks=actions.filter(item=>item.kind==='attack');
  const spells=actions.filter(item=>item.kind==='spell');
  return <div className="classic-overview">
    <div className="classic-overview-top"><Card><div className="section-title"><h2>Боевые показатели</h2><Badge>Лист персонажа</Badge></div><div className="classic-combat-values"><div><small>Класс доспеха</small><strong>{sheet.armor_class}</strong></div><div><small>Инициатива</small><strong>{signed(sheet.computed.initiative)}</strong></div><div><small>Скорость</small><strong>{sheet.speed}<em> фт.</em></strong></div><div><small>Мастерство</small><strong>{signed(sheet.computed.proficiency)}</strong></div></div><div className="classic-combat-footer"><Button variant="secondary" disabled={disabled} onClick={()=>onRoll('initiative')}><Dice5 size={16}/> Бросить инициативу</Button><small>Состояния: {sheet.conditions.length?sheet.conditions.join(', '):'нет'}</small></div></Card><Card><h2>Магия</h2><div className="classic-magic-values"><span>Атака <b>{signed(sheet.computed.spell_attack)}</b></span><span>СЛ спасброска <b>{sheet.computed.spell_dc}</b></span></div><div className="classic-slot-pips">{Object.entries(sheet.slots).filter(([,value])=>(value as Json).max>0).map(([level,value])=><span key={level} title={`Ячейки ${level} уровня: ${(value as Json).max-(value as Json).used} из ${(value as Json).max}`}>{level} ур. <b>{(value as Json).max-(value as Json).used}/{(value as Json).max}</b></span>)}</div><Button variant="ghost" onClick={()=>onTab('spells')}>Все заклинания <ChevronRight size={15}/></Button></Card></div>
    <div className="classic-overview-actions"><Card><div className="section-title"><div><span className="eyebrow">ОРУЖИЕ И ПРИЁМЫ</span><h2>Атаки</h2></div><Button variant="ghost" onClick={()=>onTab('combat')}>Все атаки <ChevronRight size={15}/></Button></div>{attacks.length?attacks.slice(0,3).map(item=><QuickAction key={item.id} item={item} sheet={sheet} disabled={disabled} busy={busy} onUse={onUse}/>):<p className="muted">Атак пока нет. Добавьте их во вкладке «Атаки».</p>}</Card><Card><div className="section-title"><div><span className="eyebrow">БЫСТРОЕ СОТВОРЕНИЕ</span><h2>Заклинания</h2></div><Button variant="ghost" onClick={()=>onTab('spells')}>Все заклинания <ChevronRight size={15}/></Button></div>{spells.length?spells.slice(0,4).map(item=><QuickAction key={item.id} item={item} sheet={sheet} disabled={disabled} busy={busy} onUse={onUse}/>):<p className="muted">Заклинаний пока нет. Добавьте готовое из каталога во вкладке «Заклинания».</p>}</Card></div>
  </div>;
}
