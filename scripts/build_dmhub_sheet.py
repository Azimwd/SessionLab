"""Build the ASCII-only DMHub Main chunk. No runtime dependencies."""
from pathlib import Path


def build(destination=None):
    root = Path(__file__).resolve().parent
    source = (root / 'SessionLabSheet_Window_Source.lua').read_text(encoding='utf-8')
    source = source.replace('-- @include SessionLabSheet_Editor_Source.lua',
                            (root / 'SessionLabSheet_Editor_Source.lua').read_text(encoding='utf-8'))
    source = '\n'.join(line.strip() for line in source.splitlines() if line.strip()
                       and (not line.lstrip().startswith('--') or line.strip() == '-- End.')) + '\n'
    text = '-- ASCII source: Russian labels use Lua UTF-8 byte escapes.\n' + ''.join(
        c if ord(c) < 128 else ''.join('\\%03d' % b for b in c.encode('utf-8')) for c in source
    )
    output = Path(destination) if destination else root / 'SessionLabSheet_ASCII.lua'
    output.write_text(text, encoding='ascii')
    return output


if __name__ == '__main__':
    import sys
    print(build(sys.argv[1] if len(sys.argv) > 1 else None))
