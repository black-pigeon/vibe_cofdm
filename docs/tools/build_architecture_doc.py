"""Build the architecture DOCX from its Markdown source via OpenXML SDK."""
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / '整体链路架构.md'
for dot in (root / 'assets').glob('architecture_*.dot'):
    for fmt in ('png', 'svg'):
        subprocess.run(['dot', '-T' + fmt, str(dot), '-o', str(dot.with_suffix('.' + fmt))], check=True)


def clean(text):
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'\1（\2）', text)
    return text.replace('**', '').replace('`', '')


blocks = []
lines = source.read_text().splitlines()
i = 0
code = False
while i < len(lines):
    line = lines[i]
    i += 1
    if line.startswith('```'):
        code = not code
        continue
    if code:
        if line:
            blocks.append({'kind': 'code', 'text': line})
        continue
    if not line.strip():
        continue
    if line.startswith('|'):
        rows = []
        while True:
            cells = [clean(x.strip()) for x in line.strip().strip('|').split('|')]
            if not all(re.fullmatch(r':?-+:?', x) for x in cells):
                rows.append(cells)
            if i >= len(lines) or not lines[i].startswith('|'):
                break
            line = lines[i]
            i += 1
        assert len({len(row) for row in rows}) == 1
        blocks.append({'kind': 'table', 'rows': rows})
        continue
    image = re.fullmatch(r'!\[([^\]]+)\]\(([^)]+)\)', line)
    if image:
        path = (root / image[2]).resolve()
        with Image.open(path) as im:
            width, height = im.size
        blocks.append({'kind': 'image', 'path': str(path), 'alt': image[1], 'width': width, 'height': height})
        continue
    heading = re.match(r'^(#+) (.*)', line)
    if heading:
        blocks.append({'kind': 'heading', 'level': len(heading[1]), 'text': clean(heading[2])})
    else:
        blocks.append({'kind': 'paragraph', 'text': clean(line)})

dotnet = shutil.which('dotnet') or str(Path.home() / '.dotnet/dotnet')
with tempfile.TemporaryDirectory(prefix='cofdm-architecture-') as tmp:
    content = Path(tmp) / 'content.json'
    content.write_text(json.dumps(blocks, ensure_ascii=False))
    subprocess.run([dotnet, 'run', '--project', str(root / 'tools/ArchitectureDocx'), '--', str(content), str(source.with_suffix('.docx'))], check=True)
print(f'Built {len(blocks)} content blocks, {sum(x["kind"] == "table" for x in blocks)} tables and {sum(x["kind"] == "image" for x in blocks)} images.')
