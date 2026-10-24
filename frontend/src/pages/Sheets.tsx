import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Plus, BookOpen, Pencil } from 'lucide-react';
import { useApp, useAction } from '../app';
import { Button, Field, Modal, Empty, Header } from '../components/ui';
import SheetEditor from '../features/sheets/SheetEditor';

export default function Sheets() {
  const a=useApp(); const [params,setParams]=useSearchParams();
  const [editor,setEditor]=useState<'new'|'edit'|null>(null);const action=useAction('Персонаж сохранён');
  const chars=a.characters.filter(c=>c.active&&(a.masterMode||(c.kind!=='npc'&&c.owner===a.user.id)));
  const character=chars.find(c=>String(c.id)===params.get('character'))||chars.find(c=>String(c.id)===a.charId)||chars[0];
  return <><Header eyebrow={a.masterMode?'ПРОСТРАНСТВО МАСТЕРА':'ЛИСТ ПЕРСОНАЖА'} title={a.masterMode?'Персонажи группы':'Мой персонаж'} subtitle={a.masterMode?'Откройте любой лист, помогите игроку и бросайте от лица его персонажа.':'Характеристики, атаки и магия — в одном месте.'} action={<Button variant="secondary" onClick={()=>setEditor('new')}><Plus size={16}/> Новый персонаж</Button>}/>
    {chars.length>0 && <div className="character-selector"><BookOpen size={19}/><select aria-label="Открытый лист" value={character?.id||''} onChange={e=>{setParams({character:e.target.value});if(!a.masterMode)a.selectCharacter(e.target.value);}}><optgroup label="Персонажи">{chars.filter(c=>c.kind!=='npc').map(c=><option key={c.id} value={c.id}>{c.name} · {c.character_class || 'Без класса'} · {c.level} ур.</option>)}</optgroup>{a.masterMode&&<optgroup label="NPC и противники">{chars.filter(c=>c.kind==='npc').map(c=><option key={c.id} value={c.id}>{c.name} · {c.character_class || 'NPC'} · {c.level} ур.</option>)}</optgroup>}</select><Button variant="secondary" onClick={()=>setEditor('edit')}><Pencil size={15}/> Имя и уровень</Button></div>}
    {character?<SheetEditor key={character.id} character={character}/>:<Empty title="Здесь будет ваш персонаж" text="Начните с имени и класса. Остальное можно заполнить постепенно." action={<Button onClick={()=>setEditor('new')}>Создать персонажа</Button>}/>}
    {editor && <Modal title={editor==='new'?'Новый персонаж':'Данные персонажа'} onClose={()=>setEditor(null)}><form onSubmit={e=>{
      e.preventDefault();const f=new FormData(e.currentTarget);
      action.mutate({path:editor==='new'?`/characters/?campaign=${a.cid}`:`/characters/${character.id}/?campaign=${a.cid}`,method:editor==='new'?'POST':'PATCH',body:{campaign:Number(a.cid),...(editor==='new'?{kind:f.get('kind')||'player'}:{}),name:f.get('name'),character_class:f.get('character_class'),species:f.get('species'),level:Number(f.get('level')),description:f.get('description')}},{onSuccess:(r:any)=>{setParams({character:String(r.id)});if(!a.masterMode)a.selectCharacter(String(r.id));setEditor(null);}});
    }}>{a.masterMode&&editor==='new'&&<Field label="Тип листа"><select name="kind"><option value="player">Персонаж игрока</option><option value="npc">NPC / противник</option></select></Field>}<Field label="Имя"><input name="name" defaultValue={editor==='edit'?character.name:''} required maxLength={100}/></Field><div className="form-grid"><Field label="Класс"><input name="character_class" defaultValue={editor==='edit'?character.character_class:''} placeholder="Бард, воин, волшебник…" maxLength={60}/></Field><Field label="Уровень"><input name="level" type="number" defaultValue={editor==='edit'?character.level:1} min={1} max={30} required/></Field></div><Field label="Вид / раса"><input name="species" defaultValue={editor==='edit'?character.species:''} maxLength={60}/></Field><Field label="Публичное описание"><textarea name="description" defaultValue={editor==='edit'?character.description:''} maxLength={3000} rows={3}/></Field><Button disabled={action.isPending}>{editor==='new'?'Создать и открыть лист':'Сохранить'}</Button></form></Modal>}

  </>;
}
