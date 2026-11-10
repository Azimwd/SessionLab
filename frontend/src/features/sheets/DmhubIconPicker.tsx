import { useId, useRef, useState } from 'react';
import {
  Check, createLucideIcon, Heart, Image as ImageIcon, Sword,
  type LucideIcon,
} from 'lucide-react';
import { Button, Field } from '../../components/ui';
import customPreviews from './dmhub-icon-previews.json';
import './dmhub-icon-picker.css';

type IconEntry = {
  asset: string;
  name: string;
  keywords?: string[];
  file?: string;
  glyph?: LucideIcon;
  category?: string;
  background?: string;
};

const Dice20 = createLucideIcon('Dice20', [
  ['path', { d: 'M12 2 21 7v10l-9 5-9-5V7Z', key: 'outline' }],
  ['path', { d: 'm12 5 6 11H6ZM12 2v3M21 17l-3-1M3 17l3-1M12 22v-6', key: 'facets' }],
]);

const starterIcons: IconEntry[] = [
  { asset: 'ui-icons/heartclicked.png', name: 'Сердце', keywords: ['лечение', 'исцеление', 'здоровье', 'хиты'], glyph: Heart },
  { asset: 'ui-icons/skills/melee-attack-icon.png', name: 'Атака оружием', keywords: ['меч', 'клинок', 'ближний бой', 'удар'], glyph: Sword },
  { asset: 'ui-icons/d20.png', name: 'Кубик d20', keywords: ['навык', 'проверка', 'бросок', 'кости'], glyph: Dice20 },
  { asset: 'ui-icons/module-checkmark.png', name: 'Галочка', keywords: ['успех', 'спасбросок', 'проверка'], glyph: Check },
];

type PreviewEntry = Required<Pick<IconEntry, 'asset' | 'name' | 'file'>> & Pick<IconEntry, 'keywords' | 'category' | 'background'>;
const byAsset = new Map(starterIcons.map(icon => [icon.asset, icon]));
for (const icon of customPreviews as PreviewEntry[]) {
  const existing = byAsset.get(icon.asset);
  byAsset.set(icon.asset, { ...existing, ...icon, keywords: [...(existing?.keywords ?? []), ...(icon.keywords ?? [])] });
}

const normalize = (text: string) => text.toLocaleLowerCase('ru').replaceAll('ё', 'е');
const catalog = [...byAsset.values()].map(icon => ({
  ...icon,
  searchText: normalize([icon.name, ...(icon.keywords ?? []), icon.asset].join(' ')),
})).sort((a, b) => a.name.localeCompare(b.name, 'ru'));
const categories = [...new Set(catalog.map(icon => icon.category).filter((category): category is string => Boolean(category)))].sort((a, b) => a.localeCompare(b, 'ru'));
const PAGE_SIZE = 24;

function IconPreview({ icon }: { icon: IconEntry }) {
  const [failed, setFailed] = useState(false);
  const Glyph = icon.glyph ?? ImageIcon;
  return <span className="dmhub-icon-preview">
    {icon.file && !failed
      ? <img src={`/dmhub-icons/${encodeURIComponent(icon.file)}`} loading="lazy" decoding="async" alt="" onError={() => setFailed(true)} />
      : <Glyph aria-hidden="true" />}
  </span>;
}

export function DmhubIconPicker({ value, onChange }: { value: string; onChange: (asset: string) => void }) {
  const galleryId = useId();
  const toggle = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(0);
  const [category, setCategory] = useState('');
  const [background, setBackground] = useState('');
  const grid = useRef<HTMLDivElement>(null);
  const selected = byAsset.get(value);
  const words = normalize(query).trim().split(/\s+/);
  const matches = open ? catalog.filter(icon => {
    if (category && icon.category !== category) return false;
    if (background && icon.background !== background) return false;
    return words.every(word => icon.searchText.includes(word));
  }) : [];
  const pages = Math.max(1, Math.ceil(matches.length / PAGE_SIZE));
  const goToPage = (next: number) => {
    setPage(next);
    if (grid.current) grid.current.scrollTop = 0;
  };

  return <div className="dmhub-icon-picker">
    <Field label="Иконка из DMHub" hint="Можно выбрать из галереи или указать путь к PNG или ID изображения вручную.">
      <input value={value} maxLength={160} onChange={event => onChange(event.target.value.trim())} />
    </Field>
    <div className="dmhub-icon-actions">
      {selected && <span className="dmhub-icon-selected">
        <IconPreview key={selected.asset} icon={selected} />{selected.name}
      </span>}
      <button ref={toggle} type="button" className="button ghost" aria-expanded={open} aria-controls={open ? galleryId : undefined} onClick={() => setOpen(!open)}>
        {open ? 'Скрыть галерею' : 'Выбрать иконку'}
      </button>
      {value && <Button type="button" variant="ghost" onClick={() => onChange('')}>Сбросить иконку</Button>}
    </div>
    {open && <section id={galleryId} className="dmhub-icon-gallery" aria-label="Галерея иконок DMHub">
      <Field label="Поиск иконок">
        <input type="search" autoFocus value={query} placeholder="Например, лечение или меч" onChange={event => {
          setQuery(event.target.value);
          goToPage(0);
        }} />
      </Field>
      <div className="dmhub-icon-filters">
        <Field label="Группа иконок">
          <select value={category} onChange={event => { setCategory(event.target.value); goToPage(0); }}>
            <option value="">Все группы</option>
            {categories.map(group => <option key={group} value={group}>{group}</option>)}
          </select>
        </Field>
        <Field label="Оформление иконки">
          <select value={background} onChange={event => { setBackground(event.target.value); goToPage(0); }}>
            <option value="">Все варианты</option>
            <option value="painted">С фоном</option>
            <option value="none">Без фона</option>
          </select>
        </Field>
      </div>
      <p className="muted" aria-live="polite">Найдено: {matches.length}. Русские названия описывают изображение.</p>
      {matches.length ? <div ref={grid} className="dmhub-icon-grid">
        {matches.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE).map(icon => <button key={icon.asset} className="dmhub-icon-choice" type="button"
          aria-pressed={icon.asset === value} title={icon.asset} onClick={() => {
            onChange(icon.asset);
            setOpen(false);
            toggle.current?.focus();
          }}>
          <IconPreview icon={icon} /><span>{icon.name}</span>
          {icon.background && <small className="muted">{icon.background === 'none' ? 'Без фона' : 'С фоном'}</small>}
        </button>)}
      </div> : <p role="status" className="muted">Иконки не найдены. Попробуйте другое слово.</p>}
      {pages > 1 && <nav className="dmhub-icon-pagination" aria-label="Страницы иконок">
        <Button type="button" variant="ghost" disabled={page === 0} onClick={() => goToPage(page - 1)}>Назад</Button>
        <span>Страница {page + 1} из {pages}</span>
        <Button type="button" variant="ghost" disabled={page + 1 === pages} onClick={() => goToPage(page + 1)}>Далее</Button>
      </nav>}
    </section>}
  </div>;
}
