import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Dice5 } from 'lucide-react';
import { useApp } from '../../app';
import { request, type Json } from '../../api/client';
import { Button, Field, ErrorBox } from '../../components/ui';
import { RollResult } from './RollResult';
import { folderKey, folderOptions } from './folderOptions';

export function appendDie(previous:string,sides:number) {
  if (!previous) return `1d${sides}`;
  const terms=previous.match(/^\d+d(?:4|6|8|10|12|20|100)(?:\+\d+d(?:4|6|8|10|12|20|100))*$/)?.[0].split('+');
  if (terms) {
    const sum=terms.reduce((total,term)=>total+Number(term.split('d')[0]),0);
    if (sum>=50) return previous;
    const idx=terms.findIndex(term=>Number(term.split('d')[1])===sides);
    if(idx>=0) terms[idx]=`${Number(terms[idx].split('d')[0])+1}d${sides}`;
    else terms.push(`1d${sides}`);
    return terms.join('+');
  }
  return `${previous}+1d${sides}`.slice(0,80);
}

export default function DiceTray({ characters, folders=[] }: { characters: Json[]; folders?: Json[] }) {
  const a = useApp();
  const [selected, setSelected] = useState('');
  const [formula, setFormula] = useState('');
  const [visibility, setVisibility] = useState('public');
  const char = characters.find(c => String(c.id) === selected) || characters.find(c => String(c.id) === a.charId) || characters[0];
  const asMaster = a.masterMode && (selected === 'master' || !char);
  const roll = useMutation({mutationFn: () => request(`/room/rolls/?campaign=${a.cid}`, 'POST', {character:asMaster ? null : char?.id,kind:'custom',formula,visibility}),onSuccess:()=>a.refresh()});
  const addDie = (sides:number) => setFormula(previous => appendDie(previous,sides));
  return <div className="dice-tray"><div className="section-title"><h2>Бросить кубики</h2><Dice5 size={20}/></div>
    <Field label="От чьего лица"><select aria-label="От чьего лица бросить кубики" value={asMaster ? 'master' : char?.id || ''} onChange={e => setSelected(e.target.value)}>{a.masterMode && <option value="master">Мастер (без листа)</option>}{!characters.length && !a.masterMode && <option value="">Сначала создайте персонажа</option>}{folderOptions(folders,characters).map(([id,name])=>{const group=characters.filter(c=>folderKey(c)===id);return group.length?<optgroup key={id} label={name}>{group.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</optgroup>:null})}</select></Field>
    <div className="dice-picker">{[4,6,8,10,12,20,100].map(n=><button key={n} type="button" aria-label={`Добавить d${n}`} onClick={()=>addDie(n)}>+ d{n}</button>)}<button type="button" onClick={()=>setFormula('')}>Очистить</button></div>
    <form onSubmit={e=>{e.preventDefault();roll.mutate();}}><Field label="Формула" hint="Например: 2d6+3, 1d20−2 (минус: -)"><input value={formula} maxLength={80} onChange={e=>setFormula(e.target.value)} required/></Field>
    <Field label="Кто увидит результат"><select value={visibility} onChange={e=>setVisibility(e.target.value)}><option value="public">Вся комната</option><option value="dm">Только мастер</option></select></Field>
    <Button disabled={(!char && !asMaster) || !a.sid || roll.isPending}><Dice5 size={17}/>{roll.isPending?'Бросаем…':'Бросить'}</Button></form>
    {!a.sid && <p className="muted">Броски появятся после начала сессии мастером.</p>}
    {roll.error && <ErrorBox error={roll.error}/>} {roll.data && <RollResult event={roll.data}/>}
  </div>;
}
