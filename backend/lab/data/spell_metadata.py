"""Class lists and schools transcribed from the CC BY 4.0 SRD 5.1.

The full source is https://www.dndbeyond.com/attachments/39j2li89/SRD5.1-CCBY4.0License.pdf .
Only the eight classes in that document's spell lists are represented here.
"""
import json
from functools import lru_cache
from pathlib import Path

CLASS_NAMES = ('Bard', 'Cleric', 'Druid', 'Paladin', 'Ranger', 'Sorcerer', 'Warlock', 'Wizard')
SCHOOL_NAMES = ('abjuration', 'conjuration', 'divination', 'enchantment', 'evocation', 'illusion', 'necromancy', 'transmutation')


@lru_cache(maxsize=1)
def _source():
    return json.loads((Path(__file__).parent / 'srd51_rules_en.json').read_text(encoding='utf-8'))


def catalog_names(cls='', school=''):
    return [name for name, data in _source().items()
            if (not cls or cls in data['classes']) and (not school or school == data['school'])]
