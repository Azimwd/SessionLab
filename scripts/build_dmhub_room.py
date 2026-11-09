"""Build the ASCII-only native DMHub mod (UTF-8 labels as Lua byte escapes)."""
from pathlib import Path


def build():
    root = Path(__file__).resolve().parent
    source = (root / 'SessionLabRoom_Source.lua').read_text(encoding='utf-8')
    encoded = ''.join(char if ord(char) < 128 else ''.join('\\%03d' % byte for byte in char.encode('utf-8')) for char in source)
    target = root / 'SessionLabRoom_Main.lua'
    target.write_text('-- ASCII source: Russian labels use UTF-8 byte escapes.\n' + encoded, encoding='ascii')
    return target


if __name__ == '__main__':
    print(build())
