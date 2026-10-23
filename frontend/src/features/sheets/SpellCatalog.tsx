import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useApp, useData } from '../../app';
import { request, type Json } from '../../api/client';
import { Modal, Button, Field, Badge, ErrorBox, Loading } from '../../components/ui';

export default function SpellCatalog({characterId,existing=[],onClose}:{characterId?:number;existing?:Json[];onClose?:()=>void}) {
  const a=useApp();
  const [search,setSearch]=useState(''),[level,setLevel]=useState(''),[offset,setOffset]=useState(0);
  const path=`/spells/catalog/?campaign=${a.cid}&q=${encodeURIComponent(search)}&offset=${offset}${level!==''?`&level=${level}`:''}`;
  const catalog=useData<{count:number;results:Json[]}>(path);
  const add=useMutation({mutationFn:(id:number)=>request(`/characters/${characterId}/spells/catalog/?campaign=${a.cid}`,'POST',{spell_id:id}),onSuccess:()=>{a.refresh();a.notify('Заклинание добавлено в лист');}});
  const ids=new Set(existing.filter(item=>item.active).map(item=>item.catalog_entry));
  const body=<>
    <p className="muted">SRD 5.1 · редакция D&D 2014. В каталоге 319 названий на русском. Метка «Проверено» означает, что описание и параметры этой записи сверены с официальными правилами; для остальных механика пока требует сверки с мастером. Разные редакции D&D могут отличаться.</p>
    <div className="catalog-filters"><Field label="Поиск по названию"><input value={search} onChange={e=>{setSearch(e.target.value);setOffset(0);}} placeholder="Огненный шар…"/></Field><Field label="Уровень"><select value={level} onChange={e=>{setLevel(e.target.value);setOffset(0);}}><option value="">Все</option>{Array.from({length:10},(_,n)=><option key={n} value={n}>{n===0?'Заговор':`${n} уровень`}</option>)}</select></Field></div>
    {catalog.isPending?<Loading/>:catalog.error?<ErrorBox error={catalog.error}/>:<><div className="catalog-list">{catalog.data?.results.map(spell=><article className="catalog-row" key={spell.id}><div><strong>{spell.name_ru}</strong><small>{spell.name_en} · {spell.level===0?'Заговор':`${spell.level} уровень`}</small><div className="inline-tags"><Badge>{spell.rules?.verified?'Правила проверены':'Механика на проверке'}</Badge>{spell.rules?.dice && <Badge>{spell.rules.dice} {spell.rules.damage_type}</Badge>}{spell.rules?.concentration && <Badge>Концентрация</Badge>}</div><small>{[spell.rules?.casting_time,spell.rules?.range,spell.rules?.duration].filter(Boolean).join(' · ')}</small>{spell.rules?.components && <small>Компоненты: {spell.rules.components}</small>}<details><summary>Описание и применение</summary><p className="preserve-lines">{spell.rules?.description}</p>{spell.rules?.upcast_dice && <p>При усилении: +{spell.rules.upcast_dice} за уровень ячейки выше исходного.</p>}<a href="https://www.dndbeyond.com/sources/dnd/basic-rules-2014/spells" target="_blank" rel="noreferrer">Официальные правила SRD 5.1 ↗</a></details></div>{characterId && <Button variant="secondary" disabled={add.isPending||ids.has(spell.id)} onClick={()=>add.mutate(spell.id)}>{ids.has(spell.id)?'Добавлено':'Добавить'}</Button>}</article>)}</div>{!catalog.data?.count && <p className="muted">По запросу ничего не найдено.</p>}<div className="catalog-pagination"><Button variant="secondary" disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-30))}>Назад</Button><Badge>{catalog.data?.count||0} заклинаний</Badge><Button variant="secondary" disabled={offset+30>=(catalog.data?.count||0)} onClick={()=>setOffset(offset+30)}>Далее</Button></div></>}
    {add.error && <ErrorBox error={add.error}/>}
    {!characterId && <p className="muted">Для добавления заклинания откройте <Link to={a.masterMode?'/master/sheets':'/sheet'}>лист персонажа</Link>.</p>}
  </>;
  return onClose?<Modal wide title="Каталог заклинаний" onClose={onClose}>{body}</Modal>:<div className="spell-reference"><h1>Справочник заклинаний</h1>{body}</div>;
}
