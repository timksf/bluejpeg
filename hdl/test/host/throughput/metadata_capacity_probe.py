#!/usr/bin/env python3
"""Create isolated package overrides for a DU metadata-capacity experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--depth', type=int, default=8)
args = parser.parse_args()
if args.depth <= 0:
    parser.error('depth must be positive')
repo = Path(__file__).resolve().parents[4]
args.output.mkdir(parents=True, exist_ok=True)
for source in (repo / 'hdl/test').iterdir():
    destination = args.output / source.name
    if not destination.exists():
        destination.symlink_to(source)
manifest = {'depth': args.depth, 'packages': {}}
for filename, fifo, expected in [('HuffEncoder.bsv', 'f_meta', 1), ('RLE.bsv', 'f_comp', 1), ('Quantize.bsv', 'f_mode', 2)]:
    source = repo / 'hdl/src/encoder' / filename
    original = source.read_text()
    modified, count = re.subn(r'(' + fifo + r'\s*<-\s*mkSizedFIFO\()\d+(\))', lambda m: m[1] + str(args.depth) + m[2], original)
    assert count == expected, (filename, count)
    (args.output / filename).write_text(modified)
    manifest['packages'][filename] = {'fifo': fifo, 'source_sha256': hashlib.sha256(original.encode()).hexdigest(), 'changed_declarations': count}
(args.output / 'metadata_probe_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Created depth-{args.depth} overrides in {args.output.resolve()}')
print('Pass TEST_DIR=' + str(args.output.resolve()) + ' to the simulation make command')
