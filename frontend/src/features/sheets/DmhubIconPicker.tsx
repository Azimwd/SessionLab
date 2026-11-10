import { useId, useRef, useState } from 'react';
import {
  Check, createLucideIcon, GitFork, Heart, Image as ImageIcon, Info, Sword,
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
};

const Dice20 = createLucideIcon('Dice20', [
  ['path', { d: 'M12 2 21 7v10l-9 5-9-5V7Z', key: 'outline' }],
  ['path', { d: 'm12 5 6 11H6ZM12 2v3M21 17l-3-1M3 17l3-1M12 22v-6', key: 'facets' }],
]);

const starterIcons: IconEntry[] = [
  { asset: 'ui-icons/heartclicked.png', name: 'Сердце', keywords: ['лечение', 'исцеление', 'здоровье', 'хиты'], glyph: Heart },
  { asset: 'ui-icons/skills/melee-attack-icon.png', name: 'Атака оружием', keywords: ['меч', 'клинок', 'ближний бой', 'удар'], glyph: Sword },
  { asset: 'ui-icons/d20.png', name: 'Кубик d20', keywords: ['навык', 'проверка', 'бросок', 'кости'], glyph: Dice20 },
  { asset: 'ui-icons/ph-arrows-split-fill.png', name: 'Разветвлённая стрелка', keywords: ['молния', 'электричество', 'луч', 'цепь'], glyph: GitFork },
  { asset: 'ui-icons/module-checkmark.png', name: 'Галочка', keywords: ['успех', 'спасбросок', 'проверка'], glyph: Check },
  { asset: 'ui-icons/ph-info-fill.png', name: 'Информация', keywords: ['характеристика', 'подсказка', 'знание'], glyph: Info },
];

type PreviewEntry = Required<Pick<IconEntry, 'asset' | 'name' | 'file'>> & Pick<IconEntry, 'keywords'>;
const byAsset = new Map(starterIcons.map(icon => [icon.asset, icon]));
for (const icon of customPreviews as PreviewEntry[]) {
  byAsset.set(icon.asset, { ...byAsset.get(icon.asset), ...icon });
}

const normalize = (text: string) => text.toLocaleLowerCase('ru').replaceAll('ё', 'е');
const catalog = [...byAsset.values()].sort((a, b) => a.name.localeCompare(b.name, 'ru'));
const PAGE_SIZE = 24;

function IconPreview({ icon }: { icon: IconEntry }) {
  const [failed, setFailed] = useState(false);
  const Glyph = icon.glyph ?? ImageIcon;
  return <span className="dmhub-icon-preview">
    {icon.file && !failed
      ? <img src={`/dmhub-icons/${encodeURIComponent(icon.file)}`} loading="lazy" alt="" onError={() => setFailed(true)} />
      : <Glyph aria-hidden="true" />}
  </span>;
}

export function DmhubIconPicker({ value, onChange }: { value: string; onChange: (asset: string) => void }) {
  const galleryId = useId();
  const toggle = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [limit, setLimit] = useState(PAGE_SIZE);
  const selected = byAsset.get(value);
  const words = normalize(query).trim().split(/\s+/);
  const matches = open ? catalog.filter(icon => {
    const haystack = normalize([icon.name, ...(icon.keywords ?? []), icon.asset].join(' '));
    return words.every(word => haystack.includes(word));
  }) : [];

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
          setLimit(PAGE_SIZE);
        }} />
      </Field>
      <p className="muted">Для иконок без PNG показаны условные значки.</p>
      {matches.length ? <div className="dmhub-icon-grid">
        {matches.slice(0, limit).map(icon => <button key={icon.asset} className="dmhub-icon-choice" type="button"
          aria-pressed={icon.asset === value} title={icon.asset} onClick={() => {
            onChange(icon.asset);
            setOpen(false);
            toggle.current?.focus();
          }}>
          <IconPreview icon={icon} /><span>{icon.name}</span>
        </button>)}
      </div> : <p role="status" className="muted">Иконки не найдены. Попробуйте другое слово.</p>}
      {matches.length > limit && <Button type="button" variant="ghost" onClick={() => setLimit(limit + PAGE_SIZE)}>Показать ещё</Button>}
    </section>}
  </div>;
}
