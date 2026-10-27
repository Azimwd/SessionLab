"""Build a short copy of the DMHub sheet mod for its paste-limited editor."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'SessionLabSheet_Main.lua'
TARGET = HERE / 'SessionLabSheet_Compact.lua'


def main():
    lines = [line.strip() for line in SOURCE.read_text(encoding='utf-8').splitlines()
             if line.strip() and not line.lstrip().startswith('--')]
    assert lines[0].startswith('local URL = ') and lines[1].startswith('local SHEET_TOKEN = ')
    header = ['-- SessionLab sheet: paste all lines, final line must be -- End.',
              *lines[:3]]
    chunks = []
    current = ''
    for line in lines[3:]:
        if len(current) + len(line) + 1 > 155:
            chunks.append(current)
            current = ''
        current = (current + ' ' + line).strip()
    if current:
        chunks.append(current)
    TARGET.write_text('\n'.join(header + chunks + ['-- End.', '']), encoding='utf-8')
    print(f'{TARGET.name}: {len(header)+len(chunks)+1} lines, {TARGET.stat().st_size} bytes')


if __name__ == '__main__':
    main()
