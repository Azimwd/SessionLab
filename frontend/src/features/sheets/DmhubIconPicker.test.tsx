import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import AbilityEditor from './AbilityEditor';

afterEach(cleanup);

const mocks = vi.hoisted(() => ({ mutate: vi.fn() }));
vi.mock('../../app', () => ({
  useApp: () => ({ cid: '1' }),
  useAction: () => ({ mutate: mocks.mutate, isPending: false }),
}));
vi.mock('./dmhub-icon-previews.json', () => ({
  default: [{
    asset: 'ui-icons/skills/1.png',
    name: 'Магический щит',
    keywords: ['защита', 'барьер'],
    file: 'shield.png',
    category: 'Защита',
    background: 'painted',
  }, ...Array.from({ length: 25 }, (_, i) => ({
    asset: `ui-icons/skills/test_${i}.png`, name: `Пример ${String(i + 1).padStart(2, '0')}`,
    file: `test_${i}.webp`, category: 'Приёмы', background: 'none',
  }))],
}));


it('finds a DMHub icon by Russian keywords and saves its path with the ability',()=>{
 mocks.mutate.mockClear();
 render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={()=>{}}/>);
 fireEvent.change(screen.getByLabelText('Название'),{target:{value:'Лечение'}});
 fireEvent.click(screen.getByRole('button',{name:'Выбрать иконку'}));
 fireEvent.change(screen.getByRole('searchbox',{name:'Поиск иконок'}),{target:{value:'ИСЦЕЛЕНИЕ'}});
 expect(screen.queryByRole('button',{name:'Атака оружием'})).not.toBeInTheDocument();
 fireEvent.click(screen.getByRole('button',{name:'Сердце'}));
 expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('ui-icons/heartclicked.png');
 expect(mocks.mutate).not.toHaveBeenCalled();
 fireEvent.submit(screen.getByLabelText('Название').closest('form')!);
 expect(mocks.mutate.mock.calls[0][0].body.map_settings.icon_asset).toBe('ui-icons/heartclicked.png');
});

it('renders the configured preview and saves the DMHub asset key', () => {
  mocks.mutate.mockClear();
  render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}} />);
  fireEvent.click(screen.getByRole('button', { name: 'Выбрать иконку' }));
  fireEvent.change(screen.getByRole('searchbox', { name: 'Поиск иконок' }), { target: { value: 'магический барьер' } });
  const choice = screen.getByRole('button', { name: 'Магический щит С фоном' });
  expect(choice.querySelector('img')).toHaveAttribute('src', '/dmhub-icons/shield.png');
  fireEvent.click(choice);
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('ui-icons/skills/1.png');
  expect(screen.getByText('Магический щит')).toBeInTheDocument();
  expect(mocks.mutate).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Сбросить иконку' }));
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('');
});

it('pages through a large group and resets the page when the search or variant changes', () => {
  render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}} />);
  fireEvent.click(screen.getByRole('button', { name: 'Выбрать иконку' }));
  const gallery = screen.getByRole('region', { name: 'Галерея иконок DMHub' });
  fireEvent.change(within(gallery).getByLabelText('Группа иконок'), { target: { value: 'Приёмы' } });
  expect(within(gallery).getAllByRole('button', { name: /^Пример/ })).toHaveLength(24);
  expect(within(gallery).getByRole('button', { name: 'Назад' })).toBeDisabled();
  fireEvent.click(within(gallery).getByRole('button', { name: 'Далее' }));
  expect(within(gallery).getAllByRole('button', { name: /^Пример/ })).toHaveLength(1);
  expect(within(gallery).getByRole('button', { name: 'Пример 25 Без фона' })).toBeInTheDocument();
  fireEvent.change(within(gallery).getByRole('searchbox'), { target: { value: 'Пример 01' } });
  expect(within(gallery).getByRole('button', { name: 'Пример 01 Без фона' })).toBeInTheDocument();
  fireEvent.change(within(gallery).getByLabelText('Оформление иконки'), { target: { value: 'painted' } });
  expect(within(gallery).getByRole('status')).toHaveTextContent('Иконки не найдены');
  fireEvent.change(within(gallery).getByRole('searchbox'), { target: { value: '' } });
  fireEvent.change(within(gallery).getByLabelText('Группа иконок'), { target: { value: 'Защита' } });
  fireEvent.click(within(gallery).getByRole('button', { name: 'Магический щит С фоном' }));
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('ui-icons/skills/1.png');
});

it('keeps an existing DMHub asset key editable when no preview is available', () => {
  render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}}
    initial={{ id: 9, name: 'Мой эффект', map_settings: { icon_asset: 'ui-icons/skills/987.png' } }} />);
  const field = screen.getByLabelText(/Иконка из DMHub/);
  expect(field).toHaveValue('ui-icons/skills/987.png');
  fireEvent.click(screen.getByRole('button', { name: 'Выбрать иконку' }));
  const gallery = screen.getByRole('region', { name: 'Галерея иконок DMHub' });
  fireEvent.change(within(gallery).getByRole('searchbox'), { target: { value: 'совсем неизвестный значок' } });
  expect(within(gallery).getByRole('status')).toHaveTextContent('Иконки не найдены');
  expect(field).toHaveValue('ui-icons/skills/987.png');
});
