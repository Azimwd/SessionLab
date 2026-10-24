"""Refresh the English SRD reference from Wizards of the Coast's 2014 Basic Rules.

Requires lxml (developer tool only). The 18 SRD spell names renamed for the
Basic Rules use the existing PDF transcription; inspect them manually before
marking any Russian mechanics as verified. This never generates Russian rules.
"""
import json
import re
import urllib.request
from pathlib import Path
from lxml import html

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'backend/lab/data/srd51_rules_en.json'
INDEX = ROOT / 'backend/lab/data/srd51_index.json'
URL = 'https://www.dndbeyond.com/sources/dnd/basic-rules-2014/spells'
records = json.loads(DATA.read_text(encoding='utf-8'))
indexed = {entry['name_en'] for entry in json.loads(INDEX.read_text(encoding='utf-8'))}
req = urllib.request.Request(URL, headers={'User-Agent': 'SessionLab SRD index updater'})
doc = html.fromstring(urllib.request.urlopen(req, timeout=40).read())
updated = set()
for heading in doc.xpath('//h3[@id]'):
    name = heading.text_content().strip()
    if name not in indexed:
        continue
    sections = []
    sibling = heading.getnext()
    while sibling is not None and sibling.tag != 'h3':
        value = re.sub(r'\s+', ' ', sibling.text_content()).strip()
        if value and sibling.tag in ('p', 'ul', 'ol', 'table', 'blockquote'):
            sections.append((sibling.get('class') or '', value))
        sibling = sibling.getnext()
    original = records[name]
    description = '\n\n'.join(value for cls, value in sections if not ('Metadata' in cls or 'Hanging' in cls))
    if len(description) < 50:
        raise ValueError(f'Incomplete HTML spell: {name}')
    original['description_en'] = description
    original['official_url'] = URL + '#' + heading.get('id')
    for key, prefix in [('casting_time', 'Casting Time:'), ('range', 'Range:'), ('components', 'Components:'), ('duration', 'Duration:')]:
        values = [v[len(prefix):].strip() for _, v in sections if v.startswith(prefix)]
        if values:
            original[key] = values[0]
    updated.add(name)
if len(updated) != 301:
    raise ValueError(f'Expected 301 Basic Rules descriptions, got {len(updated)}; inspect source changes')
for name in indexed - updated:
    records[name]['official_url'] = 'https://www.dndbeyond.com/attachments/39j2li89/SRD5.1-CCBY4.0License.pdf'
DATA.write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'{len(updated)} official HTML records refreshed; {len(indexed-updated)} PDF spell names kept for review.')
