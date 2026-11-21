"""Exports a map script's grid (scripts/maps/map_<name>.gd) to JSON for the
Blender map builder: size, solid cells, cover rects, floors, sites, spawns.
Usage: python art/export_map.py dustline > art/maps/dustline.json"""
import re, sys, json

name = sys.argv[1].lower()
src = open('scripts/maps/map_%s.gd' % name, encoding='utf-8').read()


def rects(key):
    m = re.search(r'"%s":\s*\[(.*?)\n\t\t\],' % key, src, re.S)
    return [list(map(int, r)) for r in re.findall(r'Rect2i\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)', m.group(1))] if m else []


W, H = map(int, re.search(r'"size":\s*Vector2i\((\d+),\s*(\d+)\)', src).groups())
floors, cover = rects('floors'), rects('cover')
open_ = [[False] * W for _ in range(H)]
for x, y, w, h in floors:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                open_[yy][xx] = True
for x, y, w, h in cover:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            open_[yy][xx] = False
sites = {k: list(map(int, v)) for k, *v in re.findall(r'"(\w)":\s*Rect2i\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)', re.search(r'"sites":\s*\{(.*?)\}', src).group(1))}
sp = re.search(r'"spawns":\s*\[(.*?)\n\t\t\],', src, re.S).group(1)
spawns = [[list(map(int, c)) for c in re.findall(r'Vector2i\((\d+),\s*(\d+)\)', side)] for side in re.findall(r'\[(.*?)\]', sp)]
print(json.dumps({"name": name, "size": [W, H], "open": ["".join('.' if c else '#' for c in row) for row in open_],
                  "floors": floors, "cover": cover, "sites": sites, "spawns": spawns}))
