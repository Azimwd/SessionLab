import { useEffect, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { useApp, useData } from '../../app';
import { request, type Json } from '../../api/client';
import { Modal, Button, Field, Badge, ErrorBox, Loading } from '../../components/ui';

const classes: Record<string,string> = {Bard:'Бард', Cleric:'Жрец', Druid:'Друид', Paladin:'Паладин', Ranger:'Следопыт', Sorcerer:'Чародей', Warlock:'Колдун', Wizard:'Волшебник'};
const schools: Record<string,string> = {abjuration:'Ограждение', conjuration:'Вызов', divination:'Прорицание', enchantment:'Очарование', evocation:'Воплощение', illusion:'Иллюзия', necromancy:'Некромантия', transmutation:'Преобразование'};
const label=(n:number)=>n===0?'Заговор':`${n} круг`;
const source='https://www.dndbeyond.com/attachments/39j2li89/SRD5.1-CCBY4.0License.pdf';

function AddSpell({spell,characterId,existing=[]}:{spell:Json;characterId?:number;existing?:Json[]}) {
  const a=useApp();
  const mine=a.characters.filter(c=>c.active && c.kind!=='npc' && c.owner===a.user.id);
  const options=a.masterMode?a.characters.filter(c=>c.active):mine;
  const [selected,setSelected]=useState(String(characterId||a.charId||options[0]?.id||''));
  const already=existing.some(v=>v.active && v.catalog_entry===spell.id && v.character===Number(selected));
  const add=useMutation({mutationFn:()=>request(`/characters/${selected}/spells/catalog/?campaign=${a.cid}`,'POST',{spell_id:spell.id}),onSuccess:()=>{a.refresh();a.notify('Заклинание добавлено в лист');},onError:e=>a.notify(e.message)});
  if(!options.length)return <Link className="button secondary" to="/profile">Создать персонажа</Link>;
  return <div className="catalog-add"><select aria-label={`Лист для ${spell.name_ru}`} value={selected} onChange={e=>setSelected(e.target.value)}>{options.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select><Button variant="secondary" disabled={!selected||add.isPending||already} onClick={()=>add.mutate()}>{already?'Добавлено':'В мой список'}</Button></div>;
}

export function SpellDetails() {
  const a=useApp(),{id}=useParams();
  const spell=useData<Json>(`/spells/catalog/${id}/?campaign=${a.cid}`,!!a.cid&&!!id);
  if(spell.isPending)return <Loading/>;
  if(spell.error)return <ErrorBox error={spell.error}/>;
  const s=spell.data!,r=s.rules||{};
  return <div className="spell-reference spell-detail"><Link className="text-link" to="/spells">← К справочнику</Link><header><div><div className="eyebrow">SRD 5.1 · 2014</div><h1>{s.name_ru}</h1><p>{label(s.level)} · {schools[r.school]||r.school}</p></div><AddSpell spell={s}/></header><div className="spell-facts"><div><small>Наложение</small><strong>{r.casting_time}</strong></div><div><small>Дистанция</small><strong>{r.range}</strong></div><div><small>Длительность</small><strong>{r.duration}</strong></div><div><small>Компоненты</small><strong>{r.components}</strong></div></div><div className="inline-tags"><Badge>{r.verified?'Авторасчёт проверен':'Применение по тексту'}</Badge>{r.concentration?<Badge>Концентрация</Badge>:null}{r.casting_time?.includes('Ритуал')?<Badge>Ритуал</Badge>:null}{(r.classes||[]).map((c:string)=><Badge key={c}>{classes[c]||c}</Badge>)}</div><section className="spell-description"><h2>Описание на русском</h2><p className="preserve-lines">{r.description}</p>{r.verified?<p className="muted">Для этого заклинания настроен проверенный автоматический расчёт.</p>:<p className="save-callout">Полное описание доступно на русском. Автоматический расчёт особых эффектов пока не настроен; применяйте правила вместе с мастером.</p>}</section><details className="spell-description" lang="en"><summary>Оригинальный текст SRD 5.1 на английском</summary><p className="preserve-lines">{r.source_en}</p><a className="text-link" href={r.source_url||source} target="_blank" rel="noreferrer">Официальный источник ↗</a></details><p className="muted">Материал SRD 5.1 от <a href="https://dnd.wizards.com/resources/systems-reference-document" target="_blank" rel="noreferrer">Wizards of the Coast LLC</a>. Перевод: <a href="https://rules.omnisgm.com" target="_blank" rel="noreferrer">OmnisGM</a>, CC BY 4.0. <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noreferrer">Условия лицензии ↗</a></p></div>;
}

export default function SpellCatalog({characterId,existing=[],onClose}:{characterId?:number;existing?:Json[];onClose?:()=>void}) {
  const a=useApp();
  const [search,setSearch]=useState(''),[query,setQuery]=useState(''),[level,setLevel]=useState(''),[cls,setCls]=useState(''),[school,setSchool]=useState(''),[status,setStatus]=useState(''),[sort,setSort]=useState('level'),[offset,setOffset]=useState(0);
  useEffect(()=>{const t=setTimeout(()=>setQuery(search.trim()),250);return()=>clearTimeout(t);},[search]);
  const params=new URLSearchParams({campaign:a.cid,offset:String(offset),sort});
  if(query)params.set('q',query);
  if(level)params.set('level',level);
  if(cls)params.set('class',cls);
  if(school)params.set('school',school);
  if(status)params.set('status',status);
  const catalog=useData<{count:number;results:Json[]}>(`/spells/catalog/?${params}`,!!a.cid);
  const change=(setter:(v:string)=>void)=>(e:React.ChangeEvent<HTMLInputElement|HTMLSelectElement>)=>{setter(e.target.value);setOffset(0);};
  const body=<>
    <p className="muted">319 заклинаний SRD 5.1 (2014) с полными русскими описаниями. Поиск выполняется по всему справочнику. Автоматический расчёт настроен для 15 заклинаний; остальные применяются по описанию с мастером.</p>
    <div className="catalog-filters"><Field label="Название или описание"><input value={search} onChange={change(setSearch)} placeholder="Например: Огненный шар, лечение, холод…"/></Field><Field label="Круг"><select value={level} onChange={change(setLevel)}><option value="">Все круги</option>{Array.from({length:10},(_,n)=><option key={n} value={n}>{label(n)}</option>)}</select></Field><Field label="Класс"><select value={cls} onChange={change(setCls)}><option value="">Все классы</option>{Object.entries(classes).map(([key,title])=><option value={key} key={key}>{title}</option>)}</select></Field><Field label="Школа"><select value={school} onChange={change(setSchool)}><option value="">Все школы</option>{Object.entries(schools).map(([key,title])=><option value={key} key={key}>{title}</option>)}</select></Field><Field label="Автоматизация"><select value={status} onChange={change(setStatus)}><option value="">Все</option><option value="verified">Авторасчёт</option><option value="reference">По описанию</option></select></Field><Field label="Сортировка"><select value={sort} onChange={change(setSort)}><option value="level">По кругу ↑</option><option value="-level">По кругу ↓</option><option value="name">По названию</option></select></Field></div>
    {catalog.isPending?<Loading/>:catalog.error?<ErrorBox error={catalog.error}/>:<><div className="catalog-list">{catalog.data?.results.map(spell=><article className="catalog-row" key={spell.id}><div><Link className="catalog-title" to={`/spells/${spell.id}`} onClick={onClose}>{spell.name_ru}</Link><small>{label(spell.level)} · {schools[spell.rules?.school]||spell.rules?.school}</small><div className="inline-tags"><Badge>{spell.rules?.verified?'Авторасчёт':'По описанию'}</Badge>{(spell.rules?.classes||[]).map((c:string)=><Badge key={c}>{classes[c]||c}</Badge>)}</div><small>{[spell.rules?.casting_time||spell.rules?.source_casting_time,spell.rules?.range||spell.rules?.source_range,spell.rules?.duration||spell.rules?.source_duration].filter(Boolean).join(' · ')}</small></div><div className="catalog-actions"><Link className="button secondary" to={`/spells/${spell.id}`} onClick={onClose}>Подробнее</Link>{characterId&&<AddSpell spell={spell} characterId={characterId} existing={existing}/>}</div></article>)}</div>{!catalog.data?.count&&<p className="muted">Ничего не найдено. Сбросьте часть фильтров или проверьте написание.</p>}<div className="catalog-pagination"><Button variant="secondary" disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-30))}>Назад</Button><Badge>{catalog.data?.count||0} заклинаний · стр. {Math.floor(offset/30)+1}</Badge><Button variant="secondary" disabled={offset+30>=(catalog.data?.count||0)} onClick={()=>setOffset(offset+30)}>Далее</Button></div></>}
  </>;
  return onClose?<Modal wide title="Добавить заклинание" onClose={onClose}>{body}</Modal>:<div className="spell-reference"><h1>Справочник заклинаний</h1>{body}</div>;
}
