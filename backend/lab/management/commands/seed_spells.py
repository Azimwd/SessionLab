"""Idempotent 2014 SRD spell index; no non-SRD book text is imported."""
import json
from pathlib import Path
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils.text import slugify
from lab.data.spell_catalog import SPELLS, SPECIAL
from lab.data.spell_rules import RULES
from lab.models import SpellCatalogEntry


class Command(BaseCommand):
    help = 'Seed the complete SRD 5.1 spell index with original Russian labels.'

    @transaction.atomic
    def handle(self, *args, **options):
        directory = Path(__file__).resolve().parents[2] / 'data'
        index = json.loads((directory / 'srd51_index.json').read_text(encoding='utf-8'))
        official = json.loads((directory / 'srd51_rules_en.json').read_text(encoding='utf-8'))
        russian = json.loads((directory / 'srd51_rules_ru.json').read_text(encoding='utf-8'))
        translated = {}
        for line in (directory / 'srd51_ru.txt').read_text(encoding='utf-8').splitlines():
            if line.strip():
                name, ru = line.split('|', 1)
                if name in translated:
                    raise ValueError(f'Duplicate Russian name entry: {name}')
                translated[name] = ru
        curated = {en: (code, ru, level, resolution, dice, upcast_dice)
                   for code, ru, en, level, resolution, dice, upcast_dice in SPELLS}
        english = {s['name_en'] for s in index}
        assert len(index) == len(english) == 319
        assert english - set(curated) == set(translated)
        if set(russian) != english:
            raise ValueError('Russian SRD 5.1 translation must cover every indexed spell')
        codes = set()
        for entry in index:
            en, level = entry['name_en'], entry['level']
            if en in curated:
                code, ru, base_level, resolution, dice, upcast_dice = curated[en]
                if base_level != level:
                    raise ValueError(f'Conflicting SRD level for {en}')
            else:
                code, ru, resolution, dice, upcast_dice = slugify(en), translated[en], 'automatic', '', ''
            options = SPECIAL.get(code, {})
            # Unconfigured effects record the cast and slot expenditure. Their targets,
            # attacks and saves must be handled by the table until a verified preset exists.
            rules = RULES.get(code, {})
            source = official[en]
            ru_rules = russian[en]
            if not rules.get('verified'):
                # An index entry is not an executable rules implementation.
                resolution, dice, upcast_dice = 'automatic', '', ''
            template = {
                'description': ru_rules['description'],
                'proficient': True, 'bonus': 0,
                'resolution': resolution, 'dice': dice,
                'add_modifier': options.get('add_modifier', False),
                'damage_type': rules.get('damage_type', ''), 'upcast_dice': upcast_dice,
                'upcast_allowed': level > 0,
                'roll_count': options.get('roll_count', 1),
                'upcast_count': options.get('upcast_count', 0),
                'cantrip_scaling': level == 0 and bool(upcast_dice or options.get('upcast_count')),
                'save_ability': rules.get('save_ability', options.get('save_ability', 'wis')),
                'save_half': bool(rules.get('save_half')),
                'casting_time': ru_rules['casting_time'],
                'range': ru_rules['range'], 'duration': ru_rules['duration'],
                'concentration': 'Концентрация' in ru_rules['duration'],
                'components': ru_rules['components'],
                'verified': bool(rules.get('verified')),
                'description_language': 'ru',
                'translation_source': 'OmnisGM SRD 5.1 · CC BY 4.0',
                'translated_name': ru_rules['name_ru'],
                'school': source['school'], 'classes': source['classes'],
                'source_en': source['description_en'],
                'source_page': source['page'],
                'source_url': source.get('official_url', 'https://www.dndbeyond.com/attachments/39j2li89/SRD5.1-CCBY4.0License.pdf'),
                'source_casting_time': source['casting_time'],
                'source_range': source['range'],
                'source_duration': source['duration'],
                'source_components': source['components'],
            }
            key = f'srd51-{code}'
            if key in codes:
                raise ValueError(f'Duplicate SRD slug: {key}')
            codes.add(key)
            SpellCatalogEntry.objects.update_or_create(
                code=key,
                defaults={'name_ru': ru, 'name_en': en, 'edition': '5e-2014',
                          'level': level, 'source': 'SRD 5.1 · CC BY 4.0',
                          'template': template, 'active': True},
            )
        # Earlier versions listed a non-SRD spell under an SRD code. Keep historical
        # references, but remove it from the public catalog.
        SpellCatalogEntry.objects.filter(code__startswith='srd51-').exclude(code__in=codes).update(active=False)
        self.stdout.write(self.style.SUCCESS(f'{len(codes)} Russian SRD 5.1 spell descriptions (15 automated presets).'))
