"""Rebuild the Russian SRD spell data from the credited OmnisGM translation.

Usage: python scripts/import_srd51_ru.py /path/to/10_Spells.md
The source is CC BY 4.0; see docs/SPELL_SOURCES.md before redistributing.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'backend/lab/data'
HEAD = re.compile(r'^### (.+?) \((.+?)\)\s*$', re.M)
FACT = re.compile(r'^\*\*(Время накладывания|Дистанция|Компоненты|Длительность):\*\*\s*(.+)$', re.M)
KEYS = {
    'Время накладывания': 'casting_time',
    'Дистанция': 'range',
    'Компоненты': 'components',
    'Длительность': 'duration',
}


def readable(markdown):
    """Preserve paragraphs, bullets, and table cells without displaying Markdown syntax."""
    lines = []
    for raw in markdown.strip().splitlines():
        line = raw.strip()
        if re.fullmatch(r'\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)+\|?', line):
            continue
        if line.startswith('|') and line.endswith('|'):
            line = ' · '.join(cell.strip() for cell in line.strip('|').split('|'))
        line = re.sub(r'!?\[([^\]]+)\]\([^)]*\)', r'\1', line)
        line = re.sub(r'<[^>]+>', '', line)
        line = re.sub(r'(?<!\\)[*_]{1,3}', '', line)
        line = re.sub(r'^#{1,6}\s*', '', line)
        lines.append(line)
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(lines)).strip()


def main(source):
    content = Path(source).read_text(encoding='utf-8')
    headings = list(HEAD.finditer(content))
    index = json.loads((DATA / 'srd51_index.json').read_text(encoding='utf-8'))
    by_name = {item['name_en'].replace('’', "'").casefold(): item['name_en'] for item in index}
    if len(headings) != 319 or len(by_name) != 319:
        raise ValueError('Expected exactly 319 unique SRD 5.1 spells')
    spells = {}
    for position, heading in enumerate(headings):
        russian, english = heading.groups()
        key = english.replace('’', "'").casefold()
        if key not in by_name or by_name[key] in spells:
            raise ValueError(f'Missing or duplicate index entry: {english}')
        block = content[heading.end():headings[position + 1].start() if position + 1 < len(headings) else len(content)]
        facts = list(FACT.finditer(block))
        if len(facts) != 4 or [match.group(1) for match in facts] != list(KEYS):
            raise ValueError(f'Invalid metadata for {english}')
        body = readable(block[facts[-1].end():])
        if len(body) < 35:
            raise ValueError(f'Missing description for {english}')
        spells[by_name[key]] = {
            'name_ru': russian,
            **{KEYS[match.group(1)]: readable(match.group(2)) for match in facts},
            'description': body,
        }
    if set(spells) != {item['name_en'] for item in index}:
        raise ValueError('The translation does not cover the complete index')
    output = DATA / 'srd51_rules_ru.json'
    output.write_text(json.dumps(spells, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Wrote {len(spells)} Russian SRD 5.1 spell descriptions to {output}')


if __name__ == '__main__':
    main(sys.argv[1])
