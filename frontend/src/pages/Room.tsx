import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowUpRight, BookOpen, Users, Shield, Heart, Radio, Eye, EyeOff } from 'lucide-react';
import { useApp, useData, useAction } from '../app';
import { Card, Header, Badge, Empty, ErrorBox, Loading, Pagination, Button } from '../components/ui';
import type { Json } from '../api/client';
import DiceTray from '../features/room/DiceTray';
import Initiative from '../features/room/Initiative';
import { RollResult } from '../features/room/RollResult';

export default function Room() {
  const a=useApp();
  const [page,setPage]=useState(1),[allSessions,setAllSessions]=useState(false),[folderFilter,setFolderFilter]=useState('players');
  const view=a.masterMode?'dm':'player';
  const state=useData<Json>(`/room/?campaign=${a.cid}&view=${view}`,!!a.cid);
  const log=useData<Json>(`/room/events/?campaign=${a.cid}&view=${view}&page=${page}${a.sid && !allSessions?`&session=${a.sid}`:''}`,!!a.cid);
  const folders=useData<Json>(`/character-folders/?campaign=${a.cid}`,!!a.cid&&a.masterMode);
  const visibility=useAction('Видимость стола обновлена');
  if(state.isPending) return <Loading/>;
  if(state.error) return <ErrorBox error={state.error} retry={()=>state.refetch()}/>;
  const party=state.data?.party || [];
  const npcs=state.data?.npcs||[];
  const folderList:Json[]=folders.data?.results||[];
  const selectedFolder=folderList.some(f=>String(f.id)===folderFilter)?folderFilter:'players';
  const displayed=a.masterMode?(selectedFolder==='players'?party:selectedFolder==='unfiled'?npcs.filter((c:Json)=>!c.folder):[...party,...npcs].filter((c:Json)=>String(c.folder)===selectedFolder)):party;
  const controlled=a.masterMode?[...party,...npcs]:state.data?.own_characters||party.filter((c:Json)=>c.owner===a.user.id);
  const tableVisible=state.data?.table_visible_to_players!==false;
  const setVisibility=(body:Json)=>visibility.mutate({path:`/room/table-visibility/?campaign=${a.cid}`,body});
  return <><Header eyebrow={a.masterMode?'ПРОСТРАНСТВО МАСТЕРА':'ВАША ГРУППА · ОБЩИЙ СТОЛ'} title={a.masterMode?'Стол мастера':'Игровая комната'} subtitle={`${a.campaign?.name} · ${state.data?.session?.name || 'Сессия ещё не началась'}`} action={<Link className="button secondary" to={a.masterMode?'/dm':'/sheet'}>{a.masterMode?'Управление сессией':'Мой персонаж'} <ArrowUpRight size={16}/></Link>}/>
    <div className="room-banner"><Radio size={18}/><span>Общий стол: броски, хиты и порядок ходов обновляются у участников автоматически.</span><Badge tone={a.connection==='live'?'green':'amber'}>{a.connection==='live'?'На связи':'Переподключение'}</Badge></div>
    {!state.data?.session && <Card><Empty title="Собираемся за столом" text={a.masterMode?'Создайте и начните сессию в управлении. Листы персонажей можно заполнить уже сейчас.':'Мастер скоро начнёт сессию. Пока можно подготовить персонажа.'} action={<Link className="button" to={a.masterMode?'/dm':'/sheet'}>{a.masterMode?'Открыть управление':'Заполнить лист'}</Link>}/></Card>}
    <div className="section-title spacer room-table-heading"><h2><Users size={19}/> За столом</h2><div className="room-table-tools">{a.masterMode&&<><select aria-label="Папка за столом" value={selectedFolder} onChange={e=>setFolderFilter(e.target.value)}><option value="players">Игроки</option><option value="unfiled">NPC без папки</option>{folderList.map(f=><option key={f.id} value={f.id}>{f.name}</option>)}</select><Button variant="secondary" disabled={visibility.isPending} onClick={()=>setVisibility({scope:'table',visible:!tableVisible})}>{tableVisible?<><EyeOff size={15}/> Скрыть блок от игроков</>:<><Eye size={15}/> Показать блок игрокам</>}</Button></>}<Badge>{a.masterMode&&!tableVisible?'Скрыто от игроков':`${displayed.length} персонажей`}</Badge></div></div>
    {(!a.masterMode&&!tableVisible)?<Card><Empty title="Мастер скрыл отображение за столом" text="Броски и инициатива остаются доступны в комнате."/></Card>:<><div className="party-grid">{displayed.map((c:Json)=><Card key={c.id} className="party-card"><div className="section-title"><div className="avatar">{c.name[0]}</div><Badge>{c.level} ур.</Badge></div><h3>{c.name}</h3><small>{c.character_class || 'Класс не указан'} · {c.owner_name}</small>{a.masterMode&&<div className="inline-tags"><Badge>{c.kind==='npc'?'NPC / противник':'Игрок'}</Badge>{!c.table_visible&&<Badge>Скрыт от игроков</Badge>}</div>}<div className="party-vitals"><span><Heart size={15}/>{c.hp_current}/{c.hp_max}{c.hp_temp?` +${c.hp_temp}`:''}</span><span><Shield size={15}/>{c.armor_class}</span></div><div className="hp-bar"><i style={{width:`${Math.min(100,c.hp_current/Math.max(1,c.hp_max)*100)}%`}}/></div><div className="inline-tags">{c.conditions.map((v:string)=><Badge key={v}>{v}</Badge>)}</div>{a.masterMode&&<div className="room-card-stats"><span>Инициатива <b>{c.initiative>=0?'+':''}{c.initiative}</b></span><span>Скорость <b>{c.speed} фт.</b></span>{Object.entries(c.abilities||{}).map(([key,value])=><span key={key}>{({str:'СИЛ',dex:'ЛОВ',con:'ТЕЛ',int:'ИНТ',wis:'МДР',cha:'ХАР'} as Record<string,string>)[key]} <b>{String(value)}</b></span>)}</div>}<div className="room-card-actions">{(a.masterMode || c.owner===a.user.id) && <Link className="text-link" to={`${a.masterMode?'/master/sheets':'/sheet'}?character=${c.id}`}><BookOpen size={14}/> Открыть лист</Link>}{a.masterMode&&<button className="text-link" disabled={visibility.isPending} aria-label={`${c.table_visible?'Скрыть':'Показать'} ${c.name} игрокам`} onClick={()=>setVisibility({scope:'character',character:c.id,visible:!c.table_visible})}>{c.table_visible?<EyeOff size={14}/>:<Eye size={14}/>} {c.table_visible?'Скрыть':'Показать'}</button>}</div></Card>)}</div>{!displayed.length&&<Empty title={a.masterMode?'В выбранной папке нет персонажей':'За столом пока нет персонажей'} action={<Link className="button" to={a.masterMode?'/master/sheets':'/sheet'}>Открыть листы</Link>}/>}</>}
    <div className="room-columns"><div className="room-main"><Card><Initiative tracker={state.data!.initiative} party={party} npcs={npcs} master={a.masterMode}/></Card><Card><div className="section-title"><div><div className="eyebrow">СОХРАНЯЕТСЯ МЕЖДУ СЕССИЯМИ</div><h2>Журнал комнаты</h2></div><Button variant="ghost" onClick={()=>{setAllSessions(!allSessions);setPage(1);}}>{allSessions?'Текущая сессия':'Все сессии'}</Button></div>{log.error?<ErrorBox error={log.error} retry={()=>log.refetch()}/>:log.isPending?<Loading/>:<><div className="room-journal" aria-live="polite" aria-relevant="additions">{log.data?.results?.map((e:Json)=><RollResult key={e.id} event={e}/>)}</div>{!log.data?.count && <p className="muted">Первый бросок откроет историю этой сессии.</p>}<Pagination page={page} setPage={setPage} count={log.data?.count || 0}/></>}</Card></div><Card className="dice-column"><DiceTray characters={controlled}/></Card></div>
  </>;
}
