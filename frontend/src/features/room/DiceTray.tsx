import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Dice5 } from 'lucide-react';
import { useApp } from '../../app';
import { request, type Json } from '../../api/client';
import { Button, Field, ErrorBox } from '../../components/ui';
import { RollResult } from './RollResult';

export default function DiceTray({ characters }: { characters: Json[] }) {
  const a = useApp();
  const [selected, setSelected] = useState('');
  const [formula, setFormula] = useState('1d20');
  const [visibility, setVisibility] = useState('public');
  const char = characters.find(c => String(c.id) === selected) || characters.find(c => String(c.id) === a.charId) || characters[0];
  const asMaster = a.masterMode && (selected === 'master' || !char);
  const roll = useMutation({mutationFn: () => request(`/room/rolls/?campaign=${a.cid}`, 'POST', {character:asMaster ? null : char?.id,kind:'custom',formula,visibility}),onSuccess:()=>a.refresh()});
  return <div className="dice-tray"><div className="section-title"><h2>Бросить кубики</h2><Dice5 size={20}/></div>
    <Field label="От чьего лица"><select value={asMaster ? 'master' : char?.id || ''} onChange={e => setSelected(e.target.value)}>{a.masterMode && <option value="master">Мастер / NPC</option>}{!characters.length && !a.masterMode && <option value="">Сначала создайте персонажа</option>}{characters.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
    <div className="dice-picker">{[4,6,8,10,12,20,100].map(n=><button key={n} type="button" onClick={()=>setFormula(`1d${n}`)}>d{n}</button>)}</div>
    <form onSubmit={e=>{e.preventDefault();roll.mutate();}}><Field label="Формула" hint="Например: 2d6+3, 1d20−2 (минус: -)"><input value={formula} maxLength={80} onChange={e=>setFormula(e.target.value)} required/></Field>
    <Field label="Кто увидит результат"><select value={visibility} onChange={e=>setVisibility(e.target.value)}><option value="public">Вся комната</option><option value="dm">Только мастер</option></select></Field>
    <Button disabled={(!char && !asMaster) || !a.sid || roll.isPending}><Dice5 size={17}/>{roll.isPending?'Бросаем…':'Бросить'}</Button></form>
    {!a.sid && <p className="muted">Броски появятся после начала сессии мастером.</p>}
    {roll.error && <ErrorBox error={roll.error}/>} {roll.data && <RollResult event={roll.data}/>}
  </div>;
}
