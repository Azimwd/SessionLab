"""Public, snapshot-only presentation for compact native DMHub result cards."""

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


def result_card(event):
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
    for i, part in enumerate(parts, 1):
        suffix = f' · {i}' if len(parts) > 1 else ''
        roll = part.get('roll')
        if roll:
            card['rows'].append({'label': _text(roll.get('formula') or ('Бросок' if event.kind == 'roll' else 'Атака'), 100) + suffix,
                                 'value': roll.get('total', '?'), 'detail': _detail(roll), 'tone': 'roll'})
        damage = part.get('damage')
        if damage:
            detail = _detail(damage) or _text(damage.get('formula'), 100)
            extras = [_detail(v) or _text(v.get('formula'), 100) for v in part.get('upcast', [])]
            if extras:
                detail += ' · усиление: ' + ' + '.join(extras)
            dtype = _text(p.get('damage_type') or 'Урон / эффект', 50)
            card['rows'].append({'label': dtype + suffix, 'value': damage.get('total', '?'),
                                 'detail': detail, 'tone': 'heal' if dtype.casefold() in ('лечение', 'healing', 'heal') else 'damage'})
        save = part.get('save')
        if save:
            record = {'ability': ATTRIBUTES.get(save.get('ability'), _text(save.get('ability'), 30)),
                      'dc': save.get('dc', '?'), 'part': i if len(parts) > 1 else None}
            if 'failed_damage' in save:
                record.update(failed=save['failed_damage'], passed=save.get('success_damage', 0))
            card['saves'].append(record)
    if len(parts) > 1 and p.get('total_damage') is not None:
        card['rows'].append({'label': 'Общий результат', 'value': p['total_damage'], 'detail': '', 'tone': 'damage'})
    return card
