import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Sheets from './Sheets';
const mocks=vi.hoisted(()=>({cid:'1',master:true,chars:[] as any[]}));
vi.mock('../app',()=>({useApp:()=>({user:{id:7},cid:mocks.cid,masterMode:mocks.master,charId:'1',characters:mocks.chars,selectCharacter:vi.fn()}),useAction:()=>({isPending:false}),useData:()=>({data:{results:[{id:10,name:'Игроки',is_system:true},{id:20,name:'NPC'}]}})}));
vi.mock('../features/sheets/SheetEditor',()=>({default:({character}:{character:any})=><div>Лист: {character.name}</div>}));
const mount=(url='/master/sheets')=>render(<MemoryRouter initialEntries={[url]}><Sheets/></MemoryRouter>);
beforeEach(()=>{localStorage.clear();mocks.cid='1';mocks.master=true;mocks.chars=[{id:1,name:'Мира',kind:'player',active:true,owner:7,folder:10},{id:2,name:'Флора',kind:'npc',active:true,owner:7,folder:20}];});
afterEach(cleanup);
it('restores the last opened sheet and its folder after leaving the page',()=>{
 const view=mount();
 fireEvent.change(screen.getByLabelText('Папка листов группы'),{target:{value:'20'}});
 expect(screen.getByText('Лист: Флора')).toBeInTheDocument();
 view.unmount();mount();
 expect(screen.getByText('Лист: Флора')).toBeInTheDocument();
 expect(screen.getByLabelText('Папка листов группы')).toHaveValue('20');
});
it('explicit links win over remembered sheets and campaigns stay separate',()=>{
 localStorage.setItem('sl:last-sheet:7:1:dm','2');
 const view=mount('/master/sheets?character=1');
 expect(screen.getByText('Лист: Мира')).toBeInTheDocument();view.unmount();
 mocks.cid='2';mount();expect(screen.getByText('Лист: Мира')).toBeInTheDocument();
});
it('an unavailable remembered sheet falls back to an accessible character',()=>{
 localStorage.setItem('sl:last-sheet:7:1:dm','999');mount();
 expect(screen.getByText('Лист: Мира')).toBeInTheDocument();
});
