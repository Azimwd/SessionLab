import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Sheets from './Sheets';

const mock = vi.hoisted(() => ({
  targets: [
    {id:11, source:3, scene_number:1, name:'Страж № 1', sheet_character:{id:3, name:'Страж № 1'}},
    {id:12, source:3, scene_number:2, name:'Страж № 2', sheet_character:{id:40, name:'Страж № 2'}},
  ],
}));
vi.mock('../app', () => ({
  useApp: () => ({
    cid:'1', sid:'1', masterMode:true, user:{id:1},
    characters:[{id:3, name:'Страж', kind:'npc', active:true, folder:2}],
  }),
  useData: (url:string) => ({data:url.startsWith('/scene/')?
    {session:1, targets:mock.targets}:{results:[{id:2,name:'Враги'}]}}),
  useAction: () => ({}),
}));
vi.mock('../features/sheets/SheetEditor', () => ({
  default: ({character}:{character:{id:number;name:string}}) =>
    <div>Лист {character.id}: {character.name}</div>,
}));

afterEach(cleanup);

it('opens the original as the first NPC and removes the tab of a retired copy', () => {
  const page = <MemoryRouter initialEntries={['/master/sheets?character=3']}><Sheets/></MemoryRouter>;
  const {rerender} = render(page);
  expect(screen.getByText('Лист 3: Страж № 1')).toBeVisible();
  fireEvent.click(screen.getByRole('button',{name:'Страж № 2'}));
  expect(screen.getByText('Лист 40: Страж № 2')).toBeVisible();
  mock.targets = mock.targets.slice(0,1);
  rerender(<MemoryRouter initialEntries={['/master/sheets?character=3']}><Sheets/></MemoryRouter>);
  expect(screen.queryByRole('button',{name:'Страж № 2'})).not.toBeInTheDocument();
  expect(screen.getByText('Лист 3: Страж № 1')).toBeVisible();
});
