import { motion } from 'motion/react';
import { Dice5, EyeOff } from 'lucide-react';
import { Badge } from '../../components/ui';
import type { Json } from '../../api/client';
import { abilities, signed } from '../sheets/constants';
import { TargetDamage } from './Scene';

function detail(roll: Json) {
  if (roll.values) return `${roll.values.join(' / ')}${roll.mode !== 'normal' ? ` → ${roll.chosen}` : ''} ${signed(roll.modifier)}`;
  return (roll.terms || []).map((t: Json) => `${t.sign < 0 ? '−' : '+'} ${t.sides ? `[${t.values.join(', ')}]` : t.constant}`).join(' ').replace(/^\+ /,'');
}

function isLimitedEffect(effect: Json) {
  return effect.frequency === 'turn' || effect.frequency === 'action';
}

function effectValue(effect: Json) {
  return `${effect.sign === -1 ? '−' : '+'}${effect.roll.total}`;
}

function limitedEffects(parts: Json[]) {
  const effects = new Map<string, { effect: Json; rolls: { index: number; effect: Json }[] }>();
  parts.forEach((part, index) => {
    for (const effect of (part.effects ?? []) as Json[]) {
      if (!isLimitedEffect(effect)) continue;
      let group = effects.get(effect.id);
      if (!group) {
        group = { effect, rolls: [] };
        effects.set(effect.id, group);
      }
      group.rolls.push({ index, effect });
    }
  });
  return [...effects.values()];
}

function ActionEffects({ parts }: { parts: Json[] }) {
  const effects = limitedEffects(parts);
  if (!effects.length) return null;
  return <section aria-label="Эффекты на всё действие">
    <strong>Эффекты на всё действие</strong>
    <div className="roll-effect-components">{effects.map(({ effect, rolls }) =>
      <div key={effect.id}>
        <strong>{effect.name}</strong>
        <span>{effect.frequency === 'turn' ? 'Раз за ход' : 'На первое попадание действия'} · {effect.damage_type === 'base' ? 'тип основного урона' : effect.damage_type}</span>
        <details>
          <summary>Возможный бонус по броскам</summary>
          {rolls.map(({ index, effect: rolled }) =>
            <div key={index}><small>Бросок {index + 1} · {effectValue(rolled)} ({rolled.dice}{rolled.critical_bonus && ` + на крите ${rolled.critical_bonus.formula}`})</small></div>
          )}
        </details>
        {effect.below_half_type && <small>Ниже половины ХП · {effect.below_half_type}</small>}
      </div>
    )}</div>
  </section>;
}

export function RollResult({ event, large = false, allowApply = false }: { event: Json; large?: boolean; allowApply?: boolean }) {
  const p = event.payload;
  const targets = p.token_targets ?? (p.token_target ? [p.token_target] : []);
  const resolved = p.map_resolved || p.token_target?.resolved;
  return <motion.article layout initial={{opacity:0,y:10}} animate={{opacity:1,y:0}} className={`roll-result ${large ? 'large' : ''}`}>
    <div className="roll-event-title"><span className="roll-symbol"><Dice5 size={20}/></span><div><strong>{p.label}</strong><small>{p.character_name || event.actor_name} · {new Date(event.created_at).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}</small></div>{event.visibility === 'dm' && <Badge><EyeOff size={12}/> Мастеру</Badge>}</div>
    {p.parts && <div className="multi-rolls">
      {p.parts.map((part: Json, i: number) => <RollResult key={i} event={{ ...event, payload: {
        ...part, label: `Бросок ${i+1}`, character_name: p.character_name, damage_type: p.damage_type,
        effects: part.effects?.filter((effect: Json) => !isLimitedEffect(effect)),
      } }}/>)}
      <p><b>{p.parts.some((part: Json) => part.effects?.length) ? 'Сумма основного урона' : 'Сумма результатов'}: {p.total_damage}</b> · учитывайте попадание каждого броска.</p>
      <ActionEffects parts={p.parts}/>
    </div>}
    {p.roll?.mode && p.roll.mode!=='normal'&&<Badge>{p.roll.mode==='advantage'?'Преимущество':'Помеха'}</Badge>}
    {p.roll && <div className="roll-line"><span><b>{p.roll.formula}</b><small>{detail(p.roll)}</small></span><strong className={p.roll.chosen === 20 ? 'good-roll' : ''}>{p.roll.total}</strong></div>}
    {p.damage && <div className={`roll-line ${['healing','heal','лечение','исцеление'].includes(String(p.damage_type).trim().toLowerCase())?'healing':'damage'}`}><span><b>{p.effects?.length?'Основной урон · ':''}{p.damage_type || 'Результат'}{p.damage.critical ? ' · критический' : ''}</b><small>{p.damage.formula}: {detail(p.damage)}{p.damage.ability_modifier !== undefined ? ` ${signed(p.damage.ability_modifier)} (характеристика)` : ''}{p.upcast?.length ? ` + усиление: ${p.upcast.map((r: Json) => `${r.formula} [${detail(r)}] = ${r.total}`).join('; ')}` : ''}</small></span><strong>{p.damage.total}</strong></div>}
    {!!p.effects?.length&&<div className="roll-effect-components">{p.effects.map((e:Json)=><div key={e.id}><strong>{e.name}</strong><span>{effectValue(e)} · {e.damage_type==='base'?'тип основного урона':e.damage_type}{e.frequency==='turn'?' · раз за ход':e.frequency==='action'?' · первое попадание':''}</span><small>{e.dice}{e.critical_bonus&&` + на крите ${e.critical_bonus.formula}`}{e.below_half_type&&` · ниже половины ХП: ${e.below_half_type}`}</small></div>)}</div>}
    {p.save && <p className="save-callout">Спасбросок: <b>{abilities[p.save.ability]}</b>, СЛ <b>{p.save.dc}</b>.{p.save.success_damage !== undefined && <> Если успешен — <b>{p.save.success_damage}</b> урона; если провален — <b>{p.save.failed_damage ?? p.damage?.total}</b> урона.</>}</p>}
    {p.kind === 'spell' && <div className="inline-tags"><Badge>{p.slot_level === 0 ? 'Заговор' : `Ячейка ${p.slot_level} ур.`}</Badge>{p.spell_attack_bonus !== undefined && <Badge>Атака заклинанием {signed(p.spell_attack_bonus)}</Badge>}{p.spell_save_dc !== undefined && <Badge>СЛ заклинаний {p.spell_save_dc}</Badge>}{p.concentration && <Badge>Концентрация</Badge>}</div>}
    {p.kind === 'spell' && !p.save && !!p.possible_saves?.length && <p className="save-callout">Если по описанию требуется спасбросок: {p.possible_saves.map((ability:string)=>abilities[ability]).join(', ')} · СЛ {p.spell_save_dc}. Условия определяются текстом заклинания.</p>}
    {p.mechanics_note && <p className="save-callout">{p.recurring && (p.damage || p.parts)?'Бросок для одного срабатывания. ':''}{p.mechanics_note}</p>}
    {event.kind === 'resource' && <p>{p.amount > 0 && <b>{p.amount} · </b>}{p.hp_current===undefined?'Здоровье скрыто':<>Хиты: {p.hp_current}/{p.hp_max}</>}</p>}
    {p.description && <details><summary>Описание действия</summary><p className="preserve-lines">{p.description}</p></details>}
    {targets.map((target:Json) => <p key={target.id} className="save-callout">
      Цель: <b>{target.name}</b>.{' '}
      {target.resolved
        ? target.parts.map((part:Json) => {
          if (part.save_outcome === 'success' || part.save_outcome === 'failure') {
            const outcome = part.save_outcome === 'success' ? 'пройден' : 'провален';
            const score = part.save_total != null && part.save_dc != null
              ? ` (${part.save_total} против СЛ ${part.save_dc})` : '';
            return `Спасбросок ${outcome}${score}`;
          }
          return part.hit === false ? 'Промах' : part.hit === true ? 'Попадание' : 'Применено';
        }).join(' · ')
        : 'Эффект определяется по описанию.'}
    </p>)}
    {p.map_resolved && !targets.length && <p className="save-callout">В области нет привязанных целей.</p>}
    {p.adjudication && <p className="save-callout" role="status">{p.adjudication}</p>}
    {p.components && <small>Компоненты: {p.components}</small>}
    {allowApply && !resolved && <TargetDamage key={event.id} event={event}/>}
    {p.kind && !resolved && <small className="muted">Урон и лечение применяются после решения за столом.</small>}
  </motion.article>;
}
