#!/usr/bin/env python3
"""Write protocol experiments to files, without emitting escapes to a terminal."""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def apc(control, payload=b''):
    return b'\x1b_G' + control.encode('ascii') + b';' + payload + b'\x1b\\'


def fixtures():
    pixels = bytes([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
    encoded = base64.b64encode(pixels)
    return {
        'kitty-query.bin': apc('i=31,s=1,v=1,a=q,t=d,f=24', b'AAAA') + b'\x1b[c',
        'kitty-inline.bin': b'before\r\n' + apc('a=T,f=32,s=2,v=2,i=1', encoded) + b'after\r\n',
        'kitty-chunked.bin': apc('a=t,f=32,s=2,v=2,i=2,m=1', encoded[:8]) + apc('m=0', encoded[8:]) + apc('a=p,i=2'),
        'kitty-delete.bin': apc('a=d,d=I,i=2'),
        'kitty-malformed.bin': apc('a=T,f=32,s=2,v=2,i=3', b'not-base64!') + b'after malformed\r\n',
        'ctx-vector-200.bin': b'\x1b[?200h: rgba 0.2 0.6 0.9 1 rectangle 8 8 30 20 fill X \r\n',
        'ctx-mode-queries.bin': b'\x1b[?200$p\x1b[?7020$p',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, data in fixtures().items():
        path = args.output / name
        with path.open('xb') as stream:
            stream.write(data)
        manifest[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    with (args.output / 'manifest.json').open('x') as stream:
        json.dump(manifest, stream, indent=2)
        stream.write('\n')


if __name__ == '__main__':
    main()
