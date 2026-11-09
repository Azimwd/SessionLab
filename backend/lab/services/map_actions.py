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
    'cone-of-cold': ('cone', 60),
    'circle-of-death': ('sphere', 60),
    'freezing-sphere': ('sphere', 60),
    'sunburst': ('sphere', 60),
}
ICONS = {'auto', 'magic', 'fire', 'frost', 'healing', 'lightning', 'weapon'}
EFFECTS = {'auto', 'none', 'fire', 'custom'}
MEASURE = r'(?P<unit>фут\w*|фт\.?|ft\.?|feet|foot|м(?:етр\w*)?|m|met(?:er|re)s?)'
DISTANCE = re.compile(r'^(?:дальность|дистанция|range)?\s*:?\s*(?P<amount>\d+(?:[.,]\d+)?)\s*' + MEASURE
                      + r'(?=$|[\s.,;(])', re.I)
AREA = re.compile(
    r'\b(?:радиус(?:ом|а)?|radius(?:\s+of)?)\s*:?\s*(?P<amount>\d+(?:[.,]\d+)?)\s*'
    + MEASURE + r'(?=$|[\s.,;)])', re.I,
)
AREA_SHAPE = re.compile(
    r'\b(?:сфер\w*|круг\w*|взрыв\w*|област\w*|sphere|burst|area)\s+'
    r'(?:с\s+|with\s+(?:a\s+)?)?' + AREA.pattern, re.I,
)
SELF_SHAPE = re.compile(
    r'(?P<shape>конус\w*|cone|куб\w*|cube|лини\w*|line)\s*(?P<amount>\d+(?:[.,]\d+)?)\s*'
    + MEASURE + r'(?=$|[\s.,;)])', re.I,
)
SPELL_ALIASES = {'огненный шар': 'fireball', 'fireball': 'fireball'}


def feet(match):
    amount = float(match['amount'].replace(',', '.'))
    unit = match['unit'].casefold()
    return round(amount * 10 / 3, 6) if unit.startswith(('м', 'm')) else amount


def described_area(distance, description, self_origin):
    if self_origin and (match := SELF_SHAPE.search(distance)):
        shape = match['shape']
        if shape.startswith(('конус', 'cone')):
            return 'cone', feet(match)
        if shape.startswith(('куб', 'cube')):
            return 'cube', feet(match)
        return 'line', feet(match)
    match = AREA.search(distance) or AREA_SHAPE.search(description)
    if match:
        return ('burst' if self_origin else 'sphere'), feet(match)
    return 'single', 0


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
    code = ability.catalog_entry.code.removeprefix('srd51-') if ability.catalog_entry_id else ''
    if not code and ability.kind == 'spell':
        code = SPELL_ALIASES.get(ability.name.strip().casefold(), '')
    distance = ability.range.strip().lower()
    self_origin = distance.startswith(('на себя', 'self'))
    if match := DISTANCE.match(distance):
        distance_ft = feet(match)
    elif distance.startswith(('касание', 'touch')):
        distance_ft = 5
    elif self_origin:
        distance_ft = 0
    else:
        distance_ft = 150 if code == 'fireball' and not distance else None
    if 'shape' in settings:
        shape, size = settings['shape'], settings.get('size_ft', 0)
    elif ability.kind == 'spell' and ability.resolution != 'attack':
        shape, size = CATALOG_SHAPES.get(code) or described_area(
            distance, ability.description.casefold(), self_origin)
    else:
        shape, size = 'single', 0
    if shape != 'single' and not 0 < size <= 150:
        shape, size = 'single', 0
    return {
        'shape': shape, 'size_ft': size if shape != 'single' else 0,
        'range_ft': settings.get('range_ft', distance_ft),
        'icon': settings.get('icon', 'auto'), 'icon_asset': settings.get('icon_asset', ''),
        'effect': settings.get('effect', 'auto'), 'effect_asset': settings.get('effect_asset', ''),
    }
