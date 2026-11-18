"""Presentation for compact native DMHub result cards."""

ATTRIBUTES = {'str': 'Сила', 'dex': 'Ловкость', 'con': 'Телосложение',
              'int': 'Интеллект', 'wis': 'Мудрость', 'cha': 'Харизма'}


def _text(value, limit=10000):
    return str(value or '').strip()[:limit]


def _detail(roll):
    terms = []
    if roll.get('terms'):
        for term in roll['terms']:
            values = term.get('values', [])
            prefix = '−' if term.get('sign', 1) < 0 else ''
            if term.get('sides'):
                terms.append(f"{prefix}{len(values)}d{term['sides']}: [{', '.join(map(str, values))}]")
            else:
                terms.append(f"{prefix}{term.get('constant', 0)}")
    elif roll.get('values'):
        values = ', '.join(map(str, roll['values']))
        terms.append(f"[{values}]")
        if roll.get('mode') in ('advantage', 'disadvantage'):
            terms.append(('преимущество' if roll['mode'] == 'advantage' else 'помеха') + f", выбран {roll.get('chosen', '?')}")
        if roll.get('modifier'):
            terms.append(f"{roll['modifier']:+}")
    if roll.get('ability_modifier'):
        terms.append(f"модификатор {roll['ability_modifier']:+}")
    return _text(' · '.join(terms), 4000)


DEFENSES = {'resistance': 'сопротивление', 'immunity': 'иммунитет', 'vulnerability': 'уязвимость'}


def _attack_damage_rows(rows, part, suffix, resolution):
    if resolution is None:
        for effect in part.get('effects', []):
            roll = effect['roll']
            frequency = {'turn': 'раз за ход', 'action': 'на первое попадание действия'}.get(
                effect.get('frequency'), 'на каждом попадании')
            dice = _detail(roll) or _text(roll.get('formula') or effect.get('dice'), 120)
            bonus = effect.get('critical_bonus')
            if bonus:
                dice += ' · доп. кубики на крите: ' + (_detail(bonus) or _text(bonus.get('formula'), 120))
            rows.append({'label': _text(effect['name'], 80) + suffix,
                         'value': f"{effect.get('sign', 1) * roll['total']:+}",
                         'detail': f'Возможный эффект · {frequency} · {dice}', 'tone': 'roll'})
        return
    components = resolution.get('components', [])
    if len(components) <= 1:
        return
    damage_components = [component for component in components if 'final_damage' in component]
    for component in components:
        if 'reduction' in component:
            rows.append({'label': _text(component['name'], 80) + suffix,
                         'value': f"−{component['reduction']}", 'detail': 'Снижение основного урона до сопротивлений',
                         'tone': 'roll'})
    for index, component in enumerate(damage_components):
        defense = DEFENSES.get(component.get('defense'))
        detail = f'До защиты: {component["base_damage"]} · {defense}' if defense else ''
        rows.append({'label': _text(component['name'], 80) + suffix,
                     'value': component['final_damage'], 'detail': detail, 'tone': 'damage'})
    rows.append({'label': 'Применённый урон' + suffix, 'value': resolution['final_damage'],
                 'detail': '', 'tone': 'damage'})


def result_card(event, resolutions=None):
    p = event.payload
    card = {'rows': [], 'saves': [], 'tags': [],
            'description': _text(p.get('description')),
            'components': _text(p.get('components'), 1000),
            'notice': _text(p.get('adjudication') or p.get('mechanics_note'), 2000),
            'timestamp': int(event.created_at.timestamp()) if event.created_at else None}
    if event.visibility == 'dm':
        card['tags'].append('Только мастеру')
    if p.get('kind') == 'spell' and p.get('slot_level') is not None:
        level = p['slot_level']
        card['tags'].append('Заговор' if level == 0 else f'Ячейка {level} ур.')
    if isinstance(p.get('spell_attack_bonus'), (int, float)):
        card['tags'].append(f"Атака {p['spell_attack_bonus']:+g}")
    if p.get('spell_save_dc') is not None:
        card['tags'].append(f"СЛ {p['spell_save_dc']}")
    parts = p.get('parts') or [p]
    resolutions = resolutions or {}
    attack = p.get('resolution') == 'attack' or bool(resolutions) or any(part.get('effects') for part in parts)
    first_effect_ids = {key.split(':', 1)[0] for key in p.get('advantage_effects', [])}
    for i, part in enumerate(parts, 1):
        suffix = f' · {i}' if len(parts) > 1 else ''
        resolution = resolutions.get(i - 1)
        missed = resolution is not None and resolution['hit'] is False
        roll = part.get('roll')
        if roll:
            details = _detail(roll)
            if i == 1:
                names = [_text(effect['name'], 80) for effect in part.get('effects', [])
                         if effect['id'] in first_effect_ids]
                if names:
                    reason = 'преимущество погасило помеху' if roll.get('mode') == 'normal' else 'преимущество'
                    details += f' · {", ".join(names)}: {reason}'
            label = _text(roll.get('formula') or ('Бросок' if event.kind == 'roll' else 'Атака'), 100) + suffix
            card['rows'].append({'label': label + (' · Промах' if missed else ''),
                                 'value': roll.get('total', '?'), 'detail': details, 'tone': 'miss' if missed else 'roll'})
        if missed:
            continue
        damage = part.get('damage')
        if damage:
            detail = _detail(damage) or _text(damage.get('formula'), 100)
            extras = [_detail(v) or _text(v.get('formula'), 100) for v in part.get('upcast', [])]
            if extras:
                detail += ' · усиление: ' + ' + '.join(extras)
            if (resolution and resolution['hit'] and len(resolution.get('components', [])) <= 1
                    and (defense := DEFENSES.get(resolution.get('defense')))):
                detail += f' · {defense}: {resolution["final_damage"]} урона'
            dtype = _text(p.get('damage_type') or 'Урон / эффект', 50)
            label = 'Бросок основного урона' if attack else dtype
            card['rows'].append({'label': label + suffix, 'value': damage.get('total', '?'),
                                 'detail': detail, 'tone': 'heal' if dtype.casefold() in ('лечение', 'healing', 'heal') else 'damage'})
        if attack:
            _attack_damage_rows(card['rows'], part, suffix, resolution)
        save = part.get('save')
        if save:
            record = {'ability': ATTRIBUTES.get(save.get('ability'), _text(save.get('ability'), 30)),
                      'dc': save.get('dc', '?'), 'part': i if len(parts) > 1 else None}
            if 'failed_damage' in save:
                record.update(failed=save['failed_damage'], passed=save.get('success_damage', 0))
            card['saves'].append(record)
    has_miss = any(r['hit'] is False for r in resolutions.values())
    if len(parts) > 1 and p.get('total_damage') is not None and not has_miss:
        card['rows'].append({'label': 'Сумма бросков основного урона' if attack else 'Общий результат',
                             'value': p['total_damage'], 'detail': '', 'tone': 'damage'})
    if len(parts) > 1 and any(r['hit'] is True for r in resolutions.values()):
        applied = sum(r['final_damage'] for r in resolutions.values())
        changed = any(not r['hit'] or len(r.get('components', [])) > 1
                      or r['final_damage'] != parts[index].get('damage', {}).get('total')
                      for index, r in resolutions.items() if 0 <= index < len(parts))
        if len(resolutions) != len(parts) or changed:
            card['rows'].append({'label': 'Всего применено урона', 'value': applied,
                                 'detail': f'Рассчитано бросков: {len(resolutions)} из {len(parts)}', 'tone': 'damage'})
    if resolutions and len(resolutions) == len(parts):
        card['damage_resolved'] = True
    if attack and not card['notice'] and any(part.get('damage') for part in parts) and len(resolutions) < len(parts):
        card['notice'] = 'Для нерассчитанных бросков показаны кубики и возможные эффекты. Применённый урон появится после выбора цели и исхода.'
    return card
