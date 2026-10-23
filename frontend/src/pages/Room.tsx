import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowUpRight, BookOpen, Users, Shield, Heart, Radio } from 'lucide-react';
import { useApp, useData } from '../app';
import { Card, Header, Badge, Empty, ErrorBox, Loading, Pagination, Button } from '../components/ui';
import type { Json } from '../api/client';
import DiceTray from '../features/room/DiceTray';
import Initiative from '../features/room/Initiative';
import { RollResult } from '../features/room/RollResult';

export default function Room() {
  const a=useApp();
  const [page,setPage]=useState(1),[allSessions,setAllSessions]=useState(false);
  const view=a.masterMode?'dm':'player';
  const state=useData<Json>(`/room/?campaign=${a.cid}&view=${view}`,!!a.cid);
  const log=useData<Json>(`/room/events/?campaign=${a.cid}&view=${view}&page=${page}${a.sid && !allSessions?`&session=${a.sid}`:''}`,!!a.cid);
  if(state.isPending) return <Loading/>;
  if(state.error) return <ErrorBox error={state.error} retry={()=>state.refetch()}/>;
  const party=state.data?.party || [];
  const controlled=party.filter((c:Json)=>a.masterMode || c.owner===a.user.id);
  return <><Header eyebrow={a.masterMode?'ПРОСТРАНСТВО МАСТЕРА':'ВАША ГРУППА · ОБЩИЙ СТОЛ'} title={a.masterMode?'Стол мастера':'Игровая комната'} subtitle={`${a.campaign?.name} · ${state.data?.session?.name || 'Сессия ещё не началась'}`} action={<Link className="button secondary" to={a.masterMode?'/dm':'/sheet'}>{a.masterMode?'Управление сессией':'Мой персонаж'} <ArrowUpRight size={16}/></Link>}/>
    <div className="room-banner"><Radio size={18}/><span>Общий стол: броски, хиты и порядок ходов обновляются у участников автоматически.</span><Badge tone={a.connection==='live'?'green':'amber'}>{a.connection==='live'?'На связи':'Переподключение'}</Badge></div>
    {!state.data?.session && <Card><Empty title="Собираемся за столом" text={a.masterMode?'Создайте и начните сессию в управлении. Листы персонажей можно заполнить уже сейчас.':'Мастер скоро начнёт сессию. Пока можно подготовить персонажа.'} action={<Link className="button" to={a.masterMode?'/dm':'/sheet'}>{a.masterMode?'Открыть управление':'Заполнить лист'}</Link>}/></Card>}
    <div className="section-title spacer"><h2><Users size={19}/> За столом</h2><Badge>{party.length} персонажей</Badge></div>
    <div className="party-grid">{party.map((c:Json)=><Card key={c.id} className="party-card"><div className="section-title"><div className="avatar">{c.name[0]}</div><Badge>{c.level} ур.</Badge></div><h3>{c.name}</h3><small>{c.character_class || 'Класс не указан'} · {c.owner_name}</small><div className="party-vitals"><span><Heart size={15}/>{c.hp_current}/{c.hp_max}{c.hp_temp?` +${c.hp_temp}`:''}</span><span><Shield size={15}/>{c.armor_class}</span></div><div className="hp-bar"><i style={{width:`${Math.min(100,c.hp_current/c.hp_max*100)}%`}}/></div><div className="inline-tags">{c.conditions.map((v:string)=><Badge key={v}>{v}</Badge>)}</div>{(a.masterMode || c.owner===a.user.id) && <Link className="text-link" to={`${a.masterMode?'/master/sheets':'/sheet'}?character=${c.id}`}><BookOpen size={14}/> Открыть лист</Link>}</Card>)}</div>
    {!party.length && <Empty title="Добавьте первого персонажа" action={<Link className="button" to="/profile">Создать персонажа</Link>}/>}
    <div className="room-columns"><div className="room-main"><Card><Initiative tracker={state.data!.initiative} party={party} master={a.masterMode}/></Card><Card><div className="section-title"><div><div className="eyebrow">СОХРАНЯЕТСЯ МЕЖДУ СЕССИЯМИ</div><h2>Журнал комнаты</h2></div><Button variant="ghost" onClick={()=>{setAllSessions(!allSessions);setPage(1);}}>{allSessions?'Текущая сессия':'Все сессии'}</Button></div>{log.error?<ErrorBox error={log.error} retry={()=>log.refetch()}/>:log.isPending?<Loading/>:<><div className="room-journal" aria-live="polite" aria-relevant="additions">{log.data?.results?.map((e:Json)=><RollResult key={e.id} event={e}/>)}</div>{!log.data?.count && <p className="muted">Первый бросок откроет историю этой сессии.</p>}<Pagination page={page} setPage={setPage} count={log.data?.count || 0}/></>}</Card></div><Card className="dice-column"><DiceTray characters={controlled}/></Card></div>
  </>;
}
