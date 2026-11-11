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
    asset: 'fa8738bc-3859-4bb1-b1e8-398277e8b267',
    aliases: ['ui-icons/skills/02_Big_fire_arrow.png'],
    name: 'Большая огненная стрела',
    keywords: ['огонь', 'пламя'],
    file: '4164.webp',
    category: 'Магия',
    background: 'painted',
  }, {
    asset: '6d487bf8-a136-45dd-82b3-04e69d83a643', aliases: ['ui-icons/heartclicked.png'],
    name: 'Сердце', file: '4104.webp',
  }, {
    asset: '1cce2d43-f587-44ed-a5cd-604eb02383a5', aliases: ['ui-icons/skills/Skill_201.png'],
    name: 'Ладонь энергии', file: '6454.webp', category: 'Магия',
  }, {
    asset: '17545cbc-91b2-4c50-94f8-6e9ea20e616c', aliases: ['ui-icons/skills/skill_201.png'],
    name: 'Ладонь энергии', file: '5192.webp', category: 'Магия',
  }, ...Array.from({ length: 25 }, (_, i) => ({
    asset: `ui-icons/skills/test_${i}.png`, name: `Пример ${String(i + 1).padStart(2, '0')}`,
    file: `test_${i}.webp`, category: 'Приёмы', background: 'none',
  }))],
}));


it('finds a DMHub icon by Russian keywords and saves its registered ID with the ability',()=>{
 mocks.mutate.mockClear();
 render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={()=>{}}/>);
 fireEvent.change(screen.getByLabelText('Название'),{target:{value:'Лечение'}});
 fireEvent.click(screen.getByRole('button',{name:'Выбрать иконку'}));
 fireEvent.change(screen.getByRole('searchbox',{name:'Поиск иконок'}),{target:{value:'ИСЦЕЛЕНИЕ'}});
 expect(screen.queryByRole('button',{name:'Атака оружием'})).not.toBeInTheDocument();
 fireEvent.click(screen.getByRole('button',{name:'Сердце'}));
 expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('6d487bf8-a136-45dd-82b3-04e69d83a643');
 expect(mocks.mutate).not.toHaveBeenCalled();
 fireEvent.submit(screen.getByLabelText('Название').closest('form')!);
 expect(mocks.mutate.mock.calls[0][0].body.map_settings.icon_asset).toBe('6d487bf8-a136-45dd-82b3-04e69d83a643');
});

it('distinguishes legacy keys whose exact spelling selects different native images', () => {
  for (const [asset, file] of [['ui-icons/skills/Skill_201.png', '6454.webp'], ['ui-icons/skills/skill_201.png', '5192.webp']]) {
    const rendered = render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}}
      initial={{ id: 9, name: 'Ладонь', map_settings: { icon_asset: asset } }} />);
    expect(screen.getByText('Ладонь энергии').querySelector('img')).toHaveAttribute('src', `/dmhub-icons/${file}`);
    rendered.unmount();
  }
});

it('renders the configured preview and saves the DMHub asset key', () => {
  mocks.mutate.mockClear();
  render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}} />);
  fireEvent.click(screen.getByRole('button', { name: 'Выбрать иконку' }));
  fireEvent.change(screen.getByRole('searchbox', { name: 'Поиск иконок' }), { target: { value: 'большая пламя' } });
  const choice = screen.getByRole('button', { name: 'Большая огненная стрела С фоном' });
  expect(choice.querySelector('img')).toHaveAttribute('src', '/dmhub-icons/4164.webp');
  fireEvent.click(choice);
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('fa8738bc-3859-4bb1-b1e8-398277e8b267');
  expect(screen.getByText('Большая огненная стрела')).toBeInTheDocument();
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
  fireEvent.change(within(gallery).getByLabelText('Группа иконок'), { target: { value: 'Магия' } });
  fireEvent.click(within(gallery).getByRole('button', { name: 'Большая огненная стрела С фоном' }));
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('fa8738bc-3859-4bb1-b1e8-398277e8b267');
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

it('shows the preview for a previously saved texture path and replaces it with the registered UUID on selection', () => {
  mocks.mutate.mockClear();
  render(<AbilityEditor characterId={1} kind="spell" spellAbility="cha" onClose={() => {}}
    initial={{ id: 9, name: 'Огненный шар', map_settings: { icon_asset: 'ui-icons/skills/02_Big_fire_arrow.png', effect: 'fire' } }} />);
  expect(screen.getByText('Большая огненная стрела')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Выбрать иконку' }));
  fireEvent.change(screen.getByRole('searchbox'), { target: { value: '02_Big_fire_arrow' } });
  const choice = screen.getByRole('button', { name: 'Большая огненная стрела С фоном' });
  expect(choice).toHaveAttribute('aria-pressed', 'true');
  fireEvent.click(choice);
  expect(screen.getByLabelText(/Иконка из DMHub/)).toHaveValue('fa8738bc-3859-4bb1-b1e8-398277e8b267');
  fireEvent.submit(screen.getByLabelText('Название').closest('form')!);
  expect(mocks.mutate.mock.calls[0][0].body.map_settings).toEqual({
    icon_asset: 'fa8738bc-3859-4bb1-b1e8-398277e8b267', effect: 'fire',
  });
});
