#!/usr/bin/env python3
"""Preserve original streamed terrain layer BC7 mip chains and decoded channels.

No layer placement, normal-channel semantics or color/height blending inferred.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import zstandard
from PIL import Image, ImageDraw
from UnityPy.enums import BuildTarget, TextureFormat
from UnityPy.export.Texture2DConverter import parse_image_data

spec = importlib.util.spec_from_file_location('layer_reader', Path(__file__).with_name('read-vegetation-storage.py'))
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)
LIMIT = 32*1024*1024


def decode(data):
    if not 16 <= len(data) <= LIMIT or data[0] != 255: raise ValueError('Invalid texture envelope')
    width, height = struct.unpack_from('<HH', data, 2)
    if not (0 < width <= 4096 and 0 < height <= 4096) or width & (width-1) or height & (height-1):
        raise ValueError('Unsupported bounded texture dimensions')
    if data[6] != TextureFormat.BC7.value or data[7] not in (1, 3): raise ValueError('Unverified streamed texture format/flags')
    packed, raw = struct.unpack_from('<II', data, 8)
    if packed != len(data)-16 or not 0 < raw <= LIMIT: raise ValueError('Texture size envelope mismatch')
    payload = data[16:]
    if not payload.startswith(bytes.fromhex('28b52ffd')) or zstandard.frame_content_size(payload) != raw:
        raise ValueError('Texture frame/envelope mismatch')
    decoded = zstandard.ZstdDecompressor().decompress(payload, max_output_size=raw, allow_extra_data=False)
    r = reader.Reader(decoded); name = r.string()
    if name not in ('TerrainLayerDiffuseCompress', 'TerrainLayerNormalCompress'): raise ValueError('Unknown terrain layer payload')
    length = r.count(LIMIT); blocks = r.take(length)
    if r.pos != len(decoded): raise ValueError('Trailing terrain texture bytes')
    levels = []; w, h = width, height; offset = 0
    while True:
        size = max(1, (w+3)//4)*max(1, (h+3)//4)*16
        levels.append({'width': w, 'height': h, 'offset': offset, 'bytes': size}); offset += size
        if w == h == 1: break
        w, h = max(1, w//2), max(1, h//2)
    if offset != len(blocks): raise ValueError('Original complete BC7 mip chain length mismatch')
    return {'width': width, 'height': height, 'format': data[6], 'opaqueHeaderU8': data[1], 'sourceFlagsU8': data[7],
            'payloadName': name, 'mips': levels, 'blocks': blocks, 'decompressedSHA256': hashlib.sha256(decoded).hexdigest()}


if __name__ == '__main__':
    root, output = map(Path, sys.argv[1:3]); output.mkdir(parents=True, exist_ok=True)
    rows = []
    for kind in ('Diffuse', 'Normal'):
        sources = sorted((root/f'{kind}TextureArray').glob(f'{kind}-*.bytes'), key=lambda p: int(p.stem.split('-')[-1]))
        for path in sources:
            stat = path.stat(); data = path.read_bytes(); item = decode(data); blocks = item.pop('blocks')
            if not item['payloadName'].startswith('TerrainLayer'+kind): raise ValueError('Texture family/payload disagreement')
            image = parse_image_data(blocks, item['width'], item['height'], TextureFormat.BC7,
                                     (2022,3,0,0), BuildTarget.StandaloneWindows64, flip=False)
            stem = path.stem; image.save(output/f'{stem}.png'); (output/f'{stem}.bc7-mips').write_bytes(blocks)
            if (path.stat().st_size, path.stat().st_mtime_ns) != (stat.st_size, stat.st_mtime_ns): raise ValueError('Source changed while decoding')
            rows.append({**item, 'kind': kind, 'layerIndex': int(stem.split('-')[-1]), 'sourceFile': str(path.relative_to(root)),
                         'sourceSHA256': hashlib.sha256(data).hexdigest(), 'mipFile': f'{stem}.bc7-mips',
                         'mipSHA256': hashlib.sha256(blocks).hexdigest(), 'imageFile': f'{stem}.png',
                         'imageSHA256': hashlib.sha256((output/f'{stem}.png').read_bytes()).hexdigest(),
                         'channelExtrema': image.getextrema(), 'orientation': 'Encoded BC7 row order, no vertical flip'})
            print('Preserved original', stem, item['width'], item['height'], len(item['mips']), 'mip levels', flush=True)
    if {r['layerIndex'] for r in rows if r['kind']=='Diffuse'} != {r['layerIndex'] for r in rows if r['kind']=='Normal'}:
        raise ValueError('Source diffuse/normal layer indices differ')
    diffuse = [r for r in rows if r['kind']=='Diffuse']; columns = 4; cell = 270
    sheet = Image.new('RGB', (columns*cell, ((len(diffuse)+columns-1)//columns)*cell), '#222830'); draw = ImageDraw.Draw(sheet)
    for i, row in enumerate(diffuse):
        image = Image.open(output/row['imageFile']).convert('RGB'); image.thumbnail((256,240))
        x, y = i%columns*cell, i//columns*cell; sheet.paste(image, (x+7,y+23)); draw.text((x+7,y+5), f"Original layer {row['layerIndex']}", fill='white')
    sheet.save(output/'diffuse-layer-contact-sheet.jpg', quality=60)
    (output/'manifest.json').write_text(json.dumps({'schema': 'original-terrain-layer-textures-v1', 'textures': rows,
        'scope': 'Original BC7 channels/mips only. Layer placement, height blending, normal/roughness packing and shader color behavior NOT yet mapped.'}, indent=2)+'\n')
