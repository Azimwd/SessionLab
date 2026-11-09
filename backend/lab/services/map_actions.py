import re

from rest_framework.exceptions import ValidationError


SHAPES = {'single', 'sphere', 'burst', 'cone', 'cube', 'line'}
CATALOG_SHAPES = {
    'fireball': ('sphere', 20),
    'shatter': ('sphere', 10),
    'burning-hands': ('cone', 15),
    'thunderwave': ('cube', 15),
    'lightning-bolt': ('line', 100),
    'word-of-radiance': ('burst', 5),
}
ICONS = {'auto', 'magic', 'fire', 'frost', 'healing', 'lightning', 'weapon'}
EFFECTS = {'auto', 'none', 'fire', 'custom'}
DISTANCE = re.compile(r'^(\d+(?:[.,]\d+)?)\s*(?:фут\w*|фт\.?|ft\.?|feet|foot|(м(?:етр\w*)?|m|met(?:er|re)s?))\s*$', re.I)


def validate_map_settings(value):
    if not isinstance(value, dict) or value.keys() - {
        'shape', 'size_ft', 'range_ft', 'icon', 'icon_asset', 'effect', 'effect_asset',
    }:
        raise ValidationError('Некорректные настройки карты DMHub')
    for key, choices in [('shape', SHAPES), ('icon', ICONS), ('effect', EFFECTS)]:
        if key in value and (not isinstance(value[key], str) or value[key] not in choices):
            raise ValidationError(f'Некорректное значение {key}')
    for key, limit in [('size_ft', 150), ('range_ft', 10000)]:
        if key in value and (type(value[key]) is not int or not (1 if key == 'size_ft' else 0) <= value[key] <= limit):
            raise ValidationError(f'Некорректное расстояние в футах ({key})')
    if value.get('shape', 'single') != 'single' and 'size_ft' not in value:
        raise ValidationError('Укажите размер области в футах')
    icon = value.get('icon_asset', '')
    if not isinstance(icon, str) or len(icon) > 160 or icon and not re.fullmatch(
        r'(?:[0-9a-fA-F-]{32,36}|(?:game-icons|ui-icons)/[A-Za-z0-9_/-]+\.png)', icon
    ):
        raise ValidationError('Укажите ключ изображения DMHub или путь к встроенной PNG-иконке')
    effect = value.get('effect_asset', '')
    if not isinstance(effect, str) or len(effect) > 120 or any(ord(ch) < 32 for ch in effect):
        raise ValidationError('Укажите имя эффекта из DMHub')
    if value.get('effect') == 'custom' and not effect.strip():
        raise ValidationError('Укажите имя эффекта из DMHub')
    return value


def map_targeting(ability):
    settings = ability.map_settings
    code = ability.catalog_entry.code if ability.catalog_entry_id else ''
    shape, size = CATALOG_SHAPES.get(code, ('single', 0))
    shape = settings.get('shape', shape)
    size = settings.get('size_ft', size)
    distance = ability.range.strip().lower()
    match = DISTANCE.fullmatch(distance)
    distance_ft = None
    if match:
        number = float(match[1].replace(',', '.'))
        distance_ft = number * 10 / 3 if match[2] else number
    elif distance.startswith(('касание', 'touch')):
        distance_ft = 5
    elif distance.startswith(('на себя', 'self')):
        distance_ft = 0
    return {
        'shape': shape, 'size_ft': size if shape != 'single' else 0,
        'range_ft': settings.get('range_ft', distance_ft),
        'icon': settings.get('icon', 'auto'), 'icon_asset': settings.get('icon_asset', ''),
        'effect': settings.get('effect', 'auto'), 'effect_asset': settings.get('effect_asset', ''),
    }
