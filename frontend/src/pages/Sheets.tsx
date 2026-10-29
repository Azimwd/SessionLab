import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Plus, BookOpen, Pencil, FolderPlus, Trash2, Pin, PinOff } from 'lucide-react';
import { useApp, useAction, useData } from '../app';
import { Button, Field, Modal, Empty, Header, Confirm, ErrorBox } from '../components/ui';
import type { Json } from '../api/client';
import SheetEditor from '../features/sheets/SheetEditor';
import { folderKey, folderOptions } from '../features/room/folderOptions';

function SheetsPage() {
  const a=useApp(); const [params,setParams]=useSearchParams();
  const [editor,setEditor]=useState<'new'|'edit'|null>(null),[folderModal,setFolderModal]=useState(false),[deleting,setDeleting]=useState(false),[folderFilter,setFolderFilter]=useState('auto');const action=useAction('Сохранено');
  const lastSheetKey=`sl:last-sheet:${a.user.id}:${a.cid}:${a.masterMode?'dm':'player'}`;
  const [remembered,setRemembered]=useState(()=>{try{return localStorage.getItem(lastSheetKey)||'';}catch{return '';}});
  const pinsKey=`sl:pinned-sheets:${a.user.id}:${a.cid}:${a.masterMode?'dm':'player'}`;
  const [pinned,setPinned]=useState<string[]>(()=>{
    try{const value=JSON.parse(localStorage.getItem(pinsKey)||'[]');return Array.isArray(value)?[...new Set(value.filter(v=>typeof v==='string'||typeof v==='number').map(String))]:[];}catch{return [];}
  });
  useEffect(()=>{try{localStorage.setItem(pinsKey,JSON.stringify(pinned));}catch{/* Pins remain usable in this tab. */}},[pinsKey,pinned]);
  const togglePin=(id:string)=>setPinned(prev=>prev.includes(id)?prev.filter(v=>v!==id):[...prev,id]);
  const openPinned=(id:string)=>{setFolderFilter('auto');setParams({character:id});if(!a.masterMode)a.selectCharacter(id);};
  const folders=useData<Json>('/character-folders/?campaign='+a.cid,!!a.cid);
  const chars=a.characters.filter(c=>c.active&&(a.masterMode||(c.kind!=='npc'&&c.owner===a.user.id)));
  const folderList:Json[]=folders.data?.results||[];
  const initial=chars.find(c=>String(c.id)===params.get('character'))||chars.find(c=>String(c.id)===remembered)||chars.find(c=>String(c.id)===a.charId)||chars[0];
  const selectedFolder=folderFilter==='auto' ? initial ? folderKey(initial) : String(folderList.find(f=>f.is_system)?.id || 'unfiled') : folderFilter;
  const visibleChars=chars.filter(c=>folderKey(c)===selectedFolder);
  const character=visibleChars.find(c=>String(c.id)===params.get('character'))||visibleChars.find(c=>String(c.id)===remembered)||visibleChars.find(c=>String(c.id)===a.charId)||visibleChars[0];
  useEffect(()=>{
    if(!character)return;
    const id=String(character.id);setRemembered(id);
    try{localStorage.setItem(lastSheetKey,id);}catch{/* Browsing still works if storage is unavailable. */}
  },[character?.id,lastSheetKey]);
  const choices=folderOptions(folderList,chars);
  const pinnedChars=pinned.map(id=>chars.find(c=>String(c.id)===id)).filter((c):c is Json=>!!c);
  return <><Header eyebrow={a.masterMode?'ПРОСТРАНСТВО МАСТЕРА':'ЛИСТ ПЕРСОНАЖА'} title={a.masterMode?'Листы группы':'Мои персонажи'} subtitle={a.masterMode?'Откройте любой лист, помогите игроку и бросайте от лица его персонажа.':'Характеристики, атаки и магия — в одном месте.'} action={<Button variant="secondary" onClick={()=>setEditor('new')}><Plus size={16}/> Новый персонаж</Button>}/>
    <section className="sheet-pins" aria-label="Закреплённые листы"><div className="sheet-pins-heading"><Pin size={15}/><strong>Закреплённые листы</strong><span>{pinnedChars.length}</span></div>{pinnedChars.length?<div className="sheet-pin-list">{pinnedChars.map(c=>{const active=character?.id===c.id;const folder=folderList.find(f=>f.id===c.folder)?.name||'Без папки';return <div className={`sheet-pin${active?' active':''}`} key={c.id}><button type="button" className="sheet-pin-open" aria-label={`Открыть закреплённый лист ${c.name}`} aria-current={active?'page':undefined} title={`${c.name} · ${folder}`} onClick={()=>openPinned(String(c.id))}><span>{c.name}</span><small>{folder}</small></button><button type="button" className="sheet-pin-remove" aria-label={`Убрать из закреплённых: ${c.name}`} title="Открепить" onClick={()=>togglePin(String(c.id))}><PinOff size={14}/></button></div>;})}</div>:<p className="muted">Откройте нужный лист и нажмите «Закрепить лист» — он будет доступен здесь одним нажатием.</p>}</section>
    <div className="sheet-folders"><Field label="Папка листов"><select aria-label="Папка листов группы" value={selectedFolder} onChange={e=>{const id=e.target.value;setFolderFilter(id);const first=chars.find(c=>folderKey(c)===id);setParams(first?{character:String(first.id)}:{});}}>{choices.map(([id,name])=><option key={id} value={id}>{name} · {chars.filter(c=>folderKey(c)===id).length}</option>)}</select></Field><Button variant="secondary" onClick={()=>setFolderModal(true)}><FolderPlus size={16}/> Создать папку</Button>{folderList.find(f=>String(f.id)===selectedFolder&&!f.is_system)&&<Button variant="ghost" aria-label="Удалить выбранную папку" disabled={action.isPending} onClick={()=>{const folder=folderList.find(f=>String(f.id)===selectedFolder);if(folder&&window.confirm(`Удалить папку «${folder.name}»? Листы останутся без папки.`))action.mutate({path:`/character-folders/${folder.id}/?campaign=${a.cid}`,method:'DELETE'},{onSuccess:()=>{setFolderFilter('unfiled');setParams({});}});}}><Trash2 size={15}/> Удалить папку</Button>}</div>
    {folders.error&&<ErrorBox error={folders.error}/>}
    {visibleChars.length>0 && <div className="character-selector">{character?.avatar_url?<img className="avatar" src={character.avatar_url} alt=""/>:<BookOpen size={19}/>}<select aria-label="Открытый лист" value={character?.id||''} onChange={e=>{setParams({character:e.target.value});if(!a.masterMode)a.selectCharacter(e.target.value);}}>{visibleChars.map(c=><option key={c.id} value={c.id}>{c.name} · {c.kind==='npc'?'NPC':c.character_class||'Персонаж'}</option>)}</select><Button variant="secondary" aria-pressed={pinned.includes(String(character.id))} onClick={()=>togglePin(String(character.id))}>{pinned.includes(String(character.id))?<PinOff size={15}/>:<Pin size={15}/>} {pinned.includes(String(character.id))?'Открепить лист':'Закрепить лист'}</Button><Button variant="secondary" onClick={()=>setEditor('edit')}><Pencil size={15}/> Изменить</Button><Button variant="ghost" aria-label="Удалить персонажа" onClick={()=>setDeleting(true)}><Trash2 size={16}/></Button></div>}
    {character?<SheetEditor key={character.id} character={character}/>:<Empty title="Здесь будет ваш персонаж" text="Начните с имени и класса. Остальное можно заполнить постепенно." action={<Button onClick={()=>setEditor('new')}>Создать персонажа</Button>}/>}
    {editor && <Modal title={editor==='new'?'Новый персонаж':'Данные персонажа'} onClose={()=>setEditor(null)}><form onSubmit={e=>{
      e.preventDefault();const f=new FormData(e.currentTarget);const photo=f.get('image');
      action.mutate({path:editor==='new'?`/characters/?campaign=${a.cid}`:`/characters/${character.id}/?campaign=${a.cid}`,method:editor==='new'?'POST':'PATCH',body:{campaign:Number(a.cid),...(editor==='new'?{kind:f.get('kind')||'player'}:{}),name:f.get('name'),character_class:f.get('character_class'),species:f.get('species'),level:Number(f.get('level')),description:f.get('description'),folder:f.get('folder')?Number(f.get('folder')):null}},{onSuccess:async(r:any)=>{setFolderFilter('auto');setParams({character:String(r.id)});if(!a.masterMode)a.selectCharacter(String(r.id));if(photo instanceof File&&photo.size){const upload=new FormData();upload.append('image',photo);try{await action.mutateAsync({path:`/characters/${r.id}/avatar/?campaign=${a.cid}`,body:upload});}catch{a.notify('Лист сохранён, фото не загрузилось. Повторите в настройках листа.');}}setEditor(null);}});
    }}>{a.masterMode&&editor==='new'&&<Field label="Тип листа"><select name="kind"><option value="player">Персонаж игрока</option><option value="npc">NPC / противник</option></select></Field>}<Field label="Папка"><select name="folder" defaultValue={editor==='edit'?character.folder||'':folderFilter!=='auto'&&selectedFolder!=='unfiled'&&!folderList.find(f=>String(f.id)===selectedFolder)?.is_system?selectedFolder:''}><option value="">{editor==='new'?'Автоматически: игрок → «Игроки», NPC → «Без папки»':'Без папки'}</option>{(folders.data?.results||[]).map((f:Json)=><option key={f.id} value={f.id}>{f.name}</option>)}</select></Field><Field label="Имя"><input name="name" defaultValue={editor==='edit'?character.name:''} required maxLength={100}/></Field><div className="form-grid"><Field label="Класс"><input name="character_class" defaultValue={editor==='edit'?character.character_class:''} placeholder="Бард, воин, волшебник…" maxLength={60}/></Field><Field label="Уровень"><input name="level" type="number" defaultValue={editor==='edit'?character.level:1} min={1} max={30} required/></Field></div><Field label="Вид / раса"><input name="species" defaultValue={editor==='edit'?character.species:''} maxLength={60}/></Field><Field label="Публичное описание"><textarea name="description" defaultValue={editor==='edit'?character.description:''} maxLength={3000} rows={3}/></Field><Field label="Фото листа (PNG, JPEG, WebP; до 2 МБ)"><input name="image" type="file" accept="image/png,image/jpeg,image/webp"/></Field>{editor==='edit'&&character.avatar_url&&<Button type="button" variant="ghost" onClick={()=>action.mutate({path:`/characters/${character.id}/avatar/?campaign=${a.cid}`,method:'DELETE'})}>Удалить фото</Button>}<Button disabled={action.isPending}>{editor==='new'?'Создать и открыть лист':'Сохранить'}</Button></form></Modal>}
    {folderModal&&<Modal title="Новая папка листов" onClose={()=>setFolderModal(false)}><form onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);action.mutate({path:`/character-folders/?campaign=${a.cid}`,body:{name:String(f.get('name')).trim()}},{onSuccess:(r:Json)=>{setFolderFilter(String(r.id));setParams({});setFolderModal(false);}});}}><Field label="Название"><input name="name" maxLength={80} placeholder="NPC, Враги, Важное…" required/></Field><Button disabled={action.isPending}>Создать папку</Button></form></Modal>}
    {deleting&&character&&<Confirm title={`Удалить «${character.name}»?`} text="Лист будет скрыт из списка. История бросков и сессий сохранится." busy={action.isPending} onClose={()=>setDeleting(false)} onConfirm={()=>action.mutate({path:`/characters/${character.id}/?campaign=${a.cid}`,method:'DELETE'},{onSuccess:()=>{setDeleting(false);setParams({});if(!a.masterMode)a.selectCharacter('');}})}/>}

  </>;
}

export default function Sheets() {
  const a=useApp();
  return <SheetsPage key={`${a.user.id}:${a.cid}:${a.masterMode?'dm':'player'}`}/>;
}
