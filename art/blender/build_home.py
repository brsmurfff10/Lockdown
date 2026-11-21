"""Lockdown home renderer (Blender 5.x, Cycles).

Renders the walkable player homes described by art/homes/layouts.py (which
writes data/homes/props.json and data/homes/<id>.json):

    assets/homes/<id>.png           the shell: floors, walls, windows, doors
                                    (gridW*64 x gridH*64, cell (x, y) covers
                                    pixels [x*64, (x+1)*64) x [y*64, (y+1)*64),
                                    outside the home is transparent)
    assets/homes/props/<kind>.png   one sprite per furniture kind, w*64 x h*64,
                                    drawn at rot 0 (front toward image bottom),
                                    transparent background, no ground shadow

Headless:
    blender -b --factory-startup --python art/blender/build_home.py -- <project> [ids... | --props | --all] [--out DIR] [--samples N] [--only-props k1,k2]

    --all       every prop and every data/homes/<id>.json
    --props     every prop
    ids         those homes
    --out DIR   write there instead of assets/homes (props go to DIR/props)

Coordinates: everything is modelled in "image" cell units: u to the right,
v down the image, z up; 1 cell = 1 m. Blender x = u, y = -v. A prop of w x h
cells occupies u in [0, w], v in [0, h]; its front faces +v (image bottom).
"""
import bpy, bmesh, json, math, os, random, sys
from mathutils import Vector, Matrix, noise as mnoise

PX = 64
WALL_H = 1.1        # interior / exterior walls
GARDEN_H = 0.55     # low garden walls, hedges, railings
IN_FLOOR = ".,~_mD"
OUT_FLOOR = "gdsw"
WALLISH = "#WE"


# --- colour helpers --------------------------------------------------------------

def lin(c):
    """sRGB hex string or 0..1 sRGB tuple -> linear RGB tuple."""
    if isinstance(c, str):
        c = c.lstrip("#")
        if len(c) == 3:
            c = "".join(k * 2 for k in c)
        c = tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def mulc(c, f):
    return tuple(max(0.0, min(1.0, v * f)) for v in c)


# --- node helpers ----------------------------------------------------------------

def nd(nt, kind, props=None, **ins):
    n = nt.nodes.new(kind)
    for k, v in (props or {}).items():
        setattr(n, k, v)
    for k, v in ins.items():
        setsock(nt, n.inputs[k.replace("_", " ")], v)
    return n


def setsock(nt, sock, v):
    if isinstance(v, bpy.types.NodeSocket):
        nt.links.new(v, sock)
    else:
        if sock.type == "RGBA" and len(v) == 3:
            v = (*v, 1.0)
        sock.default_value = v


def sock(n, name, typ=None, out=False):
    for s in (n.outputs if out else n.inputs):
        if s.name == name and (typ is None or s.type == typ):
            return s
    raise KeyError(name)


def mixc(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    setsock(nt, sock(n, "Factor", "VALUE"), fac)
    setsock(nt, sock(n, "A", "RGBA"), a)
    setsock(nt, sock(n, "B", "RGBA"), b)
    return sock(n, "Result", "RGBA", out=True)


def math_(nt, op, a, b=0.0, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    setsock(nt, n.inputs[0], a)
    setsock(nt, n.inputs[1], b)
    return n.outputs[0]


def ramp(nt, fac, stops, interp="LINEAR"):
    r = nt.nodes.new("ShaderNodeValToRGB")
    cr = r.color_ramp
    cr.interpolation = interp
    while len(cr.elements) < len(stops):
        cr.elements.new(0.5)
    for el, (p, c) in zip(cr.elements, stops):
        el.position = p
        el.color = (*c, 1.0) if len(c) == 3 else c
    setsock(nt, r.inputs[0], fac)
    return r.outputs[0]


def coords(nt, scale=(1, 1, 1), kind="Object", rot=None):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    if rot:
        mp.inputs["Rotation"].default_value = rot
    nt.links.new(tc.outputs[kind], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def noise(nt, vec, scale, detail=4.0, rough=0.5, dist=0.0):
    return nd(nt, "ShaderNodeTexNoise", Vector=vec, Scale=scale, Detail=detail, Roughness=rough, Distortion=dist)


def bump(nt, b, height, strength, distance=0.02, normal=None):
    n = nd(nt, "ShaderNodeBump", Strength=strength, Distance=distance, Height=height)
    if normal is not None:
        nt.links.new(normal, n.inputs["Normal"])
    nt.links.new(n.outputs[0], b.inputs["Normal"])
    return n.outputs[0]


def _new(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])
    return m, nt, b, out


_MC = {}


def cached(fn):
    def w(name, *a, **k):
        key = "LH_" + name
        if key in _MC:
            return _MC[key]
        m = fn(key, *a, **k)
        _MC[key] = m
        return m
    return w


# --- materials -------------------------------------------------------------------

@cached
def m_plain(name, col, rough=0.5, metal=0.0, coat=0.0, sheen=0.0, emit=0.0, ecol=None, var=0.0, vscale=8.0,
            bumpk=0.0, bscale=200.0, spec=0.5, alpha=1.0):
    m, nt, b, _ = _new(name)
    col = lin(col)
    if var > 0:
        co = coords(nt)
        n = noise(nt, co, vscale, 3)
        setsock(nt, b.inputs["Base Color"], ramp(nt, n.outputs["Fac"], [(0.3, mulc(col, 1 - var)), (0.7, mulc(col, 1 + var))]))
    else:
        b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Sheen Weight"].default_value = sheen
    b.inputs["Specular IOR Level"].default_value = spec
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(ecol or col), 1)
        b.inputs["Emission Strength"].default_value = emit
    if bumpk:
        co = coords(nt)
        n = noise(nt, co, bscale, 2)
        bump(nt, b, n.outputs["Fac"], bumpk, 0.01)
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
    return m


@cached
def m_fabric(name, col, col2=None, weave=300.0, var=0.12, sheen=0.5, rough=0.9, pattern=None, pscale=6.0):
    """Cloth with a crossed weave bump. pattern: None | 'check' | 'stripe' (col2 lines)."""
    m, nt, b, _ = _new(name)
    co = coords(nt)
    c = lin(col)
    n = noise(nt, co, 5.0, 3)
    base = ramp(nt, n.outputs["Fac"], [(0.3, mulc(c, 1 - var)), (0.7, mulc(c, 1 + var))])
    if pattern and col2:
        c2 = lin(col2)
        if pattern == "check":
            ch = nd(nt, "ShaderNodeTexChecker", Vector=co, Scale=pscale, Color1=(1, 1, 1), Color2=(0, 0, 0))
            base = mixc(nt, math_(nt, "MULTIPLY", ch.outputs["Fac"], 0.5), base, c2)
        else:
            wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "X", "wave_profile": "SIN"},
                    Vector=co, Scale=pscale, Distortion=0.0)
            st = math_(nt, "GREATER_THAN", wv.outputs["Fac"], 0.8)
            base = mixc(nt, st, base, c2)
    setsock(nt, b.inputs["Base Color"], base)
    w1 = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "X"}, Vector=co, Scale=weave)
    w2 = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Y"}, Vector=co, Scale=weave)
    h = math_(nt, "MULTIPLY", w1.outputs["Fac"], w2.outputs["Fac"])
    bump(nt, b, h, 0.15, 0.005)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Sheen Weight"].default_value = sheen
    b.inputs["Specular IOR Level"].default_value = 0.25
    return m


@cached
def m_wood(name, c0, c1, scale=4.0, rough=0.45, coat=0.15, axis="X", grain=1.0):
    """Furniture wood: distorted wave grain stretched along axis."""
    m, nt, b, _ = _new(name)
    s = (0.12, 2.5, 2.5) if axis == "X" else (2.5, 0.12, 2.5)
    co = coords(nt, s)
    wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Y" if axis == "X" else "X"},
            Vector=co, Scale=scale, Distortion=7.0, Detail=4.0, Detail_Scale=1.5)
    n = noise(nt, coords(nt, (0.5, 6, 6) if axis == "X" else (6, 0.5, 6)), 3.0, 5)
    f = math_(nt, "MULTIPLY", wv.outputs["Fac"], grain)
    col = ramp(nt, f, [(0.0, lin(c1)), (0.8, lin(c0))])
    col = mixc(nt, 0.35, col, ramp(nt, n.outputs["Fac"], [(0.3, mulc(lin(c0), 0.8)), (0.7, mulc(lin(c0), 1.15))]), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    bump(nt, b, wv.outputs["Fac"], 0.05, 0.01)
    return m


@cached
def m_planks(name, c0, c1, plank_w=0.18, plank_l=1.4, gap="#2a1c12", rough=0.4, coat=0.2, axis="X", wear=0.0, gapw=0.004):
    """Floorboards / deck: brick pattern of planks with grain and per-plank tint."""
    m, nt, b, _ = _new(name)
    rot = (0, 0, 0) if axis == "X" else (0, 0, math.pi / 2)
    co = coords(nt, (1, 1, 1), rot=rot)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.37, "offset_frequency": 2}, Vector=co, Color1=lin(c0), Color2=lin(c1),
            Mortar=lin(gap), Scale=1.0, Mortar_Size=gapw, Mortar_Smooth=0.2, Bias=0.0, Brick_Width=plank_l, Row_Height=plank_w)
    gco = coords(nt, (0.15, 4.0, 4.0), rot=rot)
    wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Y"}, Vector=gco, Scale=6.0,
            Distortion=8.0, Detail=3.0)
    grain = ramp(nt, wv.outputs["Fac"], [(0.0, (0.78, 0.78, 0.78)), (0.7, (1, 1, 1))])
    col = mixc(nt, 1.0, br.outputs["Color"], grain, "MULTIPLY")
    if wear:
        n = noise(nt, coords(nt), 1.5, 4)
        col = mixc(nt, math_(nt, "MULTIPLY", n.outputs["Fac"], wear), col, (0.55, 0.5, 0.42), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    h = math_(nt, "ADD", math_(nt, "MULTIPLY", math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), 1.0), math_(nt, "MULTIPLY", wv.outputs["Fac"], 0.05))
    bump(nt, b, h, 0.4, 0.01)
    return m


@cached
def m_tiles(name, col, grout, size=0.3, offset=0.0, rough=0.25, var=0.06, coat=0.3, gw=0.01, col2=None, rect=1.0):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    c = lin(col)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": offset, "offset_frequency": 2}, Vector=co,
            Color1=mulc(c, 1 - var), Color2=lin(col2) if col2 else mulc(c, 1 + var), Mortar=lin(grout), Scale=1.0,
            Mortar_Size=gw, Mortar_Smooth=0.1, Bias=0.0, Brick_Width=size * rect, Row_Height=size)
    n = noise(nt, co, 3.0, 4)
    base = br.outputs["Color"]
    if col2:  # true checkerboard (classic black & white), grout from the brick pattern
        ck = nd(nt, "ShaderNodeTexChecker", Vector=coords(nt, (1, 1, 1)), Color1=c, Color2=lin(col2), Scale=1.0 / size)
        base = mixc(nt, math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), lin(grout), ck.outputs["Color"])
    col_ = mixc(nt, 0.15, base, ramp(nt, n.outputs["Fac"], [(0.3, (0.85, 0.85, 0.85)), (0.7, (1, 1, 1))]), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], col_)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    bump(nt, b, math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), 0.3, 0.01)
    return m


@cached
def m_marble(name, base, vein, tile=1.0, rough=0.12, grout=None, vein2=None):
    """Polished stone: soft cloudy base + a few thin distorted veins."""
    m, nt, b, _ = _new(name)
    co = coords(nt)
    vb, vc = lin(base), lin(vein)
    n1 = noise(nt, coords(nt, (1.0, 0.6, 1.0)), 0.35, 3.5, 0.5)
    veins = ramp(nt, n1.outputs["Fac"], [(0.493, (0, 0, 0)), (0.4995, (0.8, 0.8, 0.8)), (0.5005, (0.8, 0.8, 0.8)), (0.507, (0, 0, 0))])
    n2 = noise(nt, coords(nt, (1.7, 1.1, 1.7)), 0.7, 3.5, 0.5)
    veins2 = ramp(nt, n2.outputs["Fac"], [(0.496, (0, 0, 0)), (0.5, (0.4, 0.4, 0.4)), (0.504, (0, 0, 0))])
    cloud = noise(nt, co, 1.2, 4)
    col = ramp(nt, cloud.outputs["Fac"], [(0.3, mulc(vb, 0.93) if vein2 is None else lin(vein2)), (0.7, mulc(vb, 1.04))])
    col = mixc(nt, veins, col, vc)
    col = mixc(nt, veins2, col, mulc(vc, 0.9))
    if tile:
        br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.5}, Vector=co, Color1=(1, 1, 1), Color2=(1, 1, 1),
                Mortar=lin(grout) if grout else mulc(vb, 0.75), Scale=1.0, Mortar_Size=0.004, Brick_Width=tile, Row_Height=tile, Bias=0)
        col = mixc(nt, 1.0, col, br.outputs["Color"], "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = 0.4
    b.inputs["Coat Roughness"].default_value = 0.05
    return m


@cached
def m_carpet(name, col, var=0.04, fleck=None):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    c = lin(col)
    n = noise(nt, co, 2.0, 3)
    n2 = noise(nt, co, 180.0, 2)
    cc = ramp(nt, n.outputs["Fac"], [(0.3, mulc(c, 1 - var)), (0.7, mulc(c, 1 + var))])
    cc = mixc(nt, 0.5, cc, ramp(nt, n2.outputs["Fac"], [(0.3, mulc(c, 0.8)), (0.7, mulc(c, 1.15))]))
    setsock(nt, b.inputs["Base Color"], cc)
    b.inputs["Roughness"].default_value = 0.95
    b.inputs["Sheen Weight"].default_value = 0.6
    b.inputs["Specular IOR Level"].default_value = 0.2
    bump(nt, b, n2.outputs["Fac"], 0.35, 0.005)
    return m


@cached
def m_concrete(name, col, rough=0.4, var=0.12, seams=2.0):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    c = lin(col)
    n = noise(nt, co, 1.2, 6)
    n2 = noise(nt, co, 25.0, 3)
    cc = ramp(nt, n.outputs["Fac"], [(0.25, mulc(c, 1 - var)), (0.75, mulc(c, 1 + var))])
    cc = mixc(nt, 0.3, cc, ramp(nt, n2.outputs["Fac"], [(0.4, mulc(c, 0.85)), (0.6, c)]))
    if seams:
        br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.0}, Vector=co, Color1=(1, 1, 1), Color2=(1, 1, 1),
                Mortar=(0.55, 0.55, 0.55), Scale=1.0, Mortar_Size=0.006, Brick_Width=seams, Row_Height=seams, Bias=0)
        cc = mixc(nt, 1.0, cc, br.outputs["Color"], "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], cc)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = 0.15
    bump(nt, b, n2.outputs["Fac"], 0.08, 0.01)
    return m


@cached
def m_grass(name, c0="#5d8f3b", c1="#3f6e2a"):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    n = noise(nt, co, 1.5, 5)
    n2 = noise(nt, co, 60.0, 2)
    vor = nd(nt, "ShaderNodeTexVoronoi", Vector=co, Scale=30.0)
    cc = ramp(nt, n.outputs["Fac"], [(0.3, lin(c1)), (0.7, lin(c0))])
    cc = mixc(nt, 0.4, cc, ramp(nt, n2.outputs["Fac"], [(0.3, mulc(lin(c1), 0.7)), (0.7, mulc(lin(c0), 1.25))]))
    wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "X", "wave_profile": "SIN"}, Vector=co, Scale=0.25)
    cc = mixc(nt, 0.08, cc, ramp(nt, wv.outputs["Fac"], [(0.4, (0.8, 0.8, 0.8)), (0.6, (1.2, 1.2, 1.2))]), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], cc)
    b.inputs["Roughness"].default_value = 0.85
    b.inputs["Sheen Weight"].default_value = 0.4
    h = math_(nt, "ADD", n2.outputs["Fac"], math_(nt, "MULTIPLY", vor.outputs["Distance"], 0.5))
    bump(nt, b, h, 0.6, 0.02)
    return m


@cached
def m_patio(name, col="#bdb3a2", col2="#a39885", size=0.6):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.5}, Vector=co, Color1=lin(col), Color2=lin(col2), Mortar=lin("#6f675b"),
            Scale=1.0, Mortar_Size=0.012, Mortar_Smooth=0.3, Bias=0.0, Brick_Width=size * 1.5, Row_Height=size)
    n = noise(nt, co, 6.0, 6)
    cc = mixc(nt, 0.35, br.outputs["Color"], ramp(nt, n.outputs["Fac"], [(0.3, (0.75, 0.75, 0.75)), (0.7, (1, 1, 1))]), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], cc)
    b.inputs["Roughness"].default_value = 0.8
    bump(nt, b, math_(nt, "ADD", math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), math_(nt, "MULTIPLY", n.outputs["Fac"], 0.2)), 0.5, 0.02)
    return m


@cached
def m_pooltile(name, col="#3fb0c9", col2="#2b93b0"):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.0}, Vector=co, Color1=lin(col), Color2=lin(col2), Mortar=lin("#d8eef2"),
            Scale=1.0, Mortar_Size=0.006, Bias=0.0, Brick_Width=0.12, Row_Height=0.12)
    vor = nd(nt, "ShaderNodeTexVoronoi", props={"feature": "DISTANCE_TO_EDGE"}, Vector=coords(nt, (1, 1.3, 1)), Scale=3.5, Randomness=0.8)
    ca = ramp(nt, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (0.035, (0, 0, 0))])
    setsock(nt, b.inputs["Base Color"], br.outputs["Color"])
    b.inputs["Roughness"].default_value = 0.2
    b.inputs["Emission Color"].default_value = (0.7, 0.95, 1.0, 1)
    setsock(nt, b.inputs["Emission Strength"], math_(nt, "MULTIPLY", ca, 0.3))  # Fake caustics.
    return m


@cached
def m_water(name, tint="#7fd3e6", glossy=0.35, deep="#1f7f9e", depth_w=0.35):
    """Mix of a tinted transparent layer and a glossy rippled surface."""
    m, nt, b, out = _new(name)
    nt.nodes.remove(b)
    co = coords(nt)
    n = noise(nt, co, 3.0, 3)
    tr = nd(nt, "ShaderNodeBsdfTransparent", Color=lin(tint))
    pr = nd(nt, "ShaderNodeBsdfPrincipled", Base_Color=lin(deep), Roughness=0.03)
    bump(nt, pr, n.outputs["Fac"], 0.25, 0.05)
    mix1 = nd(nt, "ShaderNodeMixShader", Fac=depth_w)
    nt.links.new(tr.outputs[0], mix1.inputs[1])
    nt.links.new(pr.outputs[0], mix1.inputs[2])
    nt.links.new(mix1.outputs[0], out.inputs[0])
    return m


@cached
def m_glass(name, tint="#d7eef5", refl=0.25, rough=0.05):
    m, nt, b, out = _new(name)
    nt.nodes.remove(b)
    tr = nd(nt, "ShaderNodeBsdfTransparent", Color=lin(tint))
    gl = nd(nt, "ShaderNodeBsdfPrincipled", Base_Color=lin(tint), Roughness=rough)
    mix1 = nd(nt, "ShaderNodeMixShader", Fac=refl)
    nt.links.new(tr.outputs[0], mix1.inputs[1])
    nt.links.new(gl.outputs[0], mix1.inputs[2])
    nt.links.new(mix1.outputs[0], out.inputs[0])
    return m


@cached
def m_screen(name, kind="game", strength=2.2):
    """Emissive screen; uses Generated coords of its own object (z = up the screen)."""
    m, nt, b, _ = _new(name)
    g = coords(nt, kind="Generated")
    sep = nd(nt, "ShaderNodeSeparateXYZ", Vector=g)
    zz, xx = sep.outputs["Z"], sep.outputs["X"]
    if kind == "game":       # FPS scene: sky, horizon, ground, a crate, HUD bar
        col = ramp(nt, zz, [(0.0, lin("#6b5a3e")), (0.45, lin("#a08860")), (0.5, lin("#d9c79a")), (0.55, lin("#8fb8de")), (1.0, lin("#3d78c2"))])
        br = nd(nt, "ShaderNodeTexBrick", Vector=coords(nt, (1, 1, 1), kind="Generated"), Color1=(0.3, 0.2, 0.1), Color2=(0.25, 0.3, 0.15),
                Mortar=(0, 0, 0), Scale=3.0, Mortar_Size=0.0, Brick_Width=0.6, Row_Height=0.35)
        box = math_(nt, "MULTIPLY", math_(nt, "LESS_THAN", zz, 0.48), math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", xx, 0.62), math_(nt, "LESS_THAN", xx, 0.8)))
        col = mixc(nt, math_(nt, "MULTIPLY", box, math_(nt, "GREATER_THAN", zz, 0.25)), col, lin("#7a5328"))
        hud = math_(nt, "LESS_THAN", zz, 0.08)
        col = mixc(nt, math_(nt, "MULTIPLY", hud, 0.7), col, lin("#101418"))
    elif kind == "desktop":  # wallpaper with two windows
        col = ramp(nt, math_(nt, "ADD", zz, math_(nt, "MULTIPLY", xx, 0.4)), [(0.0, lin("#1b2a6b")), (0.7, lin("#5a3db0")), (1.4, lin("#d0568f"))])
        w1 = math_(nt, "MULTIPLY", math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", xx, 0.1), math_(nt, "LESS_THAN", xx, 0.55)),
                   math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", zz, 0.25), math_(nt, "LESS_THAN", zz, 0.85)))
        w2 = math_(nt, "MULTIPLY", math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", xx, 0.6), math_(nt, "LESS_THAN", xx, 0.92)),
                   math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", zz, 0.15), math_(nt, "LESS_THAN", zz, 0.6)))
        col = mixc(nt, w1, col, lin("#e8ecf2"))
        col = mixc(nt, w2, col, lin("#22272e"))
    elif kind == "tv":       # warm movie still
        col = ramp(nt, zz, [(0.0, lin("#1a0f12")), (0.35, lin("#7a2e1f")), (0.6, lin("#e0873a")), (0.75, lin("#f5c46b")), (1.0, lin("#3b4f7a"))])
        n = noise(nt, g, 4.0, 3)
        col = mixc(nt, 0.25, col, n.outputs["Color"], "OVERLAY")
    elif kind == "arcade":
        col = ramp(nt, zz, [(0.0, lin("#120428")), (1.0, lin("#2a0a5c"))])
        br = nd(nt, "ShaderNodeTexBrick", Vector=coords(nt, (1, 1, 1), kind="Generated"), Color1=lin("#ff3fa0"), Color2=lin("#3ff0ff"),
                Mortar=(0, 0, 0), Scale=6.0, Mortar_Size=0.25, Brick_Width=0.5, Row_Height=0.25)
        col = mixc(nt, math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", zz, 0.55), math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"])), col, br.outputs["Color"])
    elif kind == "laptop":
        col = ramp(nt, zz, [(0.0, lin("#2b4c7e")), (1.0, lin("#6fa3d8"))])
        w1 = math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", xx, 0.15), math_(nt, "LESS_THAN", zz, 0.75))
        w1 = math_(nt, "MULTIPLY", w1, math_(nt, "MULTIPLY", math_(nt, "LESS_THAN", xx, 0.8), math_(nt, "GREATER_THAN", zz, 0.2)))
        col = mixc(nt, w1, col, lin("#dfe6ee"))
    elif kind == "code":     # dark editor with coloured lines
        wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Z"}, Vector=g, Scale=12.0)
        n = noise(nt, coords(nt, (8, 1, 30), kind="Generated"), 1.0, 1)
        line = math_(nt, "MULTIPLY", math_(nt, "GREATER_THAN", wv.outputs["Fac"], 0.55), math_(nt, "LESS_THAN", xx, math_(nt, "ADD", 0.3, math_(nt, "MULTIPLY", n.outputs["Fac"], 0.8))))
        col = mixc(nt, line, lin("#16181d"), ramp(nt, n.outputs["Fac"], [(0.4, lin("#5fd38a")), (0.5, lin("#e0b45a")), (0.6, lin("#7aa6ff"))], "CONSTANT"))
    else:
        col = lin("#33aaff")
    b.inputs["Base Color"].default_value = (0.01, 0.01, 0.01, 1)
    setsock(nt, b.inputs["Emission Color"], col)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.15
    return m


@cached
def m_emit(name, col, strength=4.0):
    m, nt, b, _ = _new(name)
    b.inputs["Base Color"].default_value = (*lin(col), 1)
    b.inputs["Emission Color"].default_value = (*lin(col), 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


@cached
def m_rgb(name, strength=4.0, scale=1.0, axis="X"):
    """Rainbow emissive gradient (RGB strips, keyboards)."""
    m, nt, b, _ = _new(name)
    co = coords(nt, (scale, scale, scale))
    sep = nd(nt, "ShaderNodeSeparateXYZ", Vector=co)
    f = math_(nt, "FRACT", sep.outputs[axis])
    col = ramp(nt, f, [(0.0, (1, 0, 0.3)), (0.25, (1, 0.6, 0)), (0.45, (0.1, 1, 0.3)), (0.65, (0, 0.6, 1)), (0.85, (0.6, 0, 1)), (1.0, (1, 0, 0.3))])
    b.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
    setsock(nt, b.inputs["Emission Color"], col)
    b.inputs["Emission Strength"].default_value = strength
    return m


@cached
def m_leaf(name, c0="#4f8f3a", c1="#2e5e25", rough=0.55, sss=0.0):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    n = noise(nt, co, 9.0, 3)
    f = math_(nt, "ADD", math_(nt, "MULTIPLY", n.outputs["Fac"], 0.7), math_(nt, "MULTIPLY", oi.outputs["Random"], 0.3))
    setsock(nt, b.inputs["Base Color"], ramp(nt, f, [(0.3, lin(c1)), (0.7, lin(c0))]))
    b.inputs["Roughness"].default_value = rough
    b.inputs["Sheen Weight"].default_value = 0.2
    bump(nt, b, noise(nt, co, 40.0, 3).outputs["Fac"], 0.3, 0.01)
    return m


@cached
def m_random(name, cols, rough=0.6, sheen=0.0):
    """Per-object random pick from a palette (books, bottles)."""
    m, nt, b, _ = _new(name)
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    stops = [(i / len(cols), lin(c)) for i, c in enumerate(cols)]
    setsock(nt, b.inputs["Base Color"], ramp(nt, oi.outputs["Random"], stops, "CONSTANT"))
    b.inputs["Roughness"].default_value = rough
    b.inputs["Sheen Weight"].default_value = sheen
    return m


@cached
def m_brick(name, col="#9a4e36", col2="#7d3b28", mortar="#cfc3b0", bw=0.22, bh=0.075, rough=0.85):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.5}, Vector=co, Color1=lin(col), Color2=lin(col2), Mortar=lin(mortar), Scale=1.0,
            Mortar_Size=0.008, Mortar_Smooth=0.2, Bias=0.0, Brick_Width=bw, Row_Height=bh)
    n = noise(nt, co, 8.0, 5)
    cc = mixc(nt, 0.4, br.outputs["Color"], ramp(nt, n.outputs["Fac"], [(0.3, (0.7, 0.7, 0.7)), (0.7, (1.1, 1.1, 1.1))]), "MULTIPLY")
    setsock(nt, b.inputs["Base Color"], cc)
    b.inputs["Roughness"].default_value = rough
    bump(nt, b, math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), 0.5, 0.01)
    return m


# --- geometry --------------------------------------------------------------------

def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _obj(name, bm, mat, bev=0.0, seg=2, sub=0, smooth=False, solid=0.0, mats=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    for mm in (mats or [mat]):
        me.materials.append(mm)
    if smooth or sub:
        for p in me.polygons:
            p.use_smooth = True
    if solid:
        md = ob.modifiers.new("Solid", "SOLIDIFY")
        md.thickness = solid
    if bev:
        md = ob.modifiers.new("Bevel", "BEVEL")
        md.width = bev
        md.segments = seg
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(35)
        md.harden_normals = False
    if sub:
        md = ob.modifiers.new("Sub", "SUBSURF")
        md.levels = md.render_levels = sub
    return ob


def X(u, v, z=0.0):
    return Vector((u, -v, z))


def mt_rz(deg, cu=0.0, cv=0.0):
    """Clockwise (as seen in the image) rotation about a vertical axis through (cu, cv)."""
    p = X(cu, cv)
    return Matrix.Translation(p) @ Matrix.Rotation(-math.radians(deg), 4, "Z") @ Matrix.Translation(-p)


def mt_back(deg, v, z):
    """Tilt about a horizontal (u) axis at (v, z): positive = top leans back toward -v."""
    p = Vector((0, -v, z))
    return Matrix.Translation(p) @ Matrix.Rotation(-math.radians(deg), 4, "X") @ Matrix.Translation(-p)


def mt_side(deg, u, z):
    """Tilt about a v axis at (u, z): positive = top leans toward +u."""
    p = Vector((u, 0, z))
    return Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, "Y") @ Matrix.Translation(-p)


def _apply(bm, mtx):
    if mtx is not None:
        bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)


def B(u0, v0, u1, v1, z0, z1, mat, bev=0.012, seg=2, sub=0, mtx=None, name="box", smooth=False):
    bm = bmesh.new()
    r = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(abs(u1 - u0), abs(v1 - v0), abs(z1 - z0)), verts=r["verts"])
    bmesh.ops.translate(bm, vec=((u0 + u1) / 2, -(v0 + v1) / 2, (z0 + z1) / 2), verts=r["verts"])
    _apply(bm, mtx)
    return _obj(name, bm, mat, bev=min(bev, abs(u1 - u0) / 2.2, abs(v1 - v0) / 2.2, abs(z1 - z0) / 2.2) if bev else 0, seg=seg, sub=sub, smooth=smooth)


def C(cu, cv, r, z0, z1, mat, segs=24, bev=0.0, r2=None, mtx=None, sub=0, name="cyl", axis="Z", smooth=True, caps=True):
    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=caps, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=abs(z1 - z0))
    vs = res["verts"]
    if axis == "X":
        bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, vec=(cu, -cv, (z0 + z1) / 2) if axis == "Z" else (cu, -cv, z0), verts=vs)
    _apply(bm, mtx)
    ob = _obj(name, bm, mat, bev=bev, sub=sub, smooth=smooth)
    if smooth and not sub:
        _autosmooth(ob)
    return ob


def _autosmooth(ob, deg=40):
    try:
        md = ob.modifiers.new("Smooth", "NODES")
        md.node_group = _smooth_group(deg)
    except Exception:
        pass


_SG = {}


def _smooth_group(deg):
    """Flat caps + smooth sides: shade-smooth-by-angle without the operator."""
    if deg in _SG:
        return _SG[deg]
    ng = bpy.data.node_groups.new("LH_SmoothByAngle", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    gi = ng.nodes.new("NodeGroupInput")
    go = ng.nodes.new("NodeGroupOutput")
    ss = ng.nodes.new("GeometryNodeSetShadeSmooth")
    ea = ng.nodes.new("GeometryNodeInputMeshEdgeAngle")
    lt = ng.nodes.new("FunctionNodeCompare")
    lt.data_type = "FLOAT"
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = math.radians(deg)
    ng.links.new(ea.outputs[0], lt.inputs[0])
    try:
        ss.domain = "EDGE"
    except Exception:
        pass
    ng.links.new(gi.outputs[0], ss.inputs["Geometry"])
    ng.links.new(lt.outputs[0], ss.inputs["Shade Smooth"])
    ng.links.new(ss.outputs[0], go.inputs[0])
    _SG[deg] = ng
    return ng


def S(cu, cv, cz, rx, ry, rz, mat, mtx=None, segs=24, rings=12, name="sph", sub=0):
    bm = bmesh.new()
    res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=(rx, ry, rz), verts=res["verts"])
    bmesh.ops.translate(bm, vec=(cu, -cv, cz), verts=res["verts"])
    _apply(bm, mtx)
    return _obj(name, bm, mat, smooth=True, sub=sub)


def T(cu, cv, cz, R, r, mat, segs=32, rsegs=10, mtx=None, name="torus", sy=1.0):
    """Torus lying flat (axis z). sy squashes it along v (ovals)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ring = []
        for j in range(rsegs):
            b_ = 2 * math.pi * j / rsegs
            rr = R + r * math.cos(b_)
            ring.append(bm.verts.new((cu + rr * math.cos(a), -cv + rr * math.sin(a) * sy, cz + r * math.sin(b_))))
        rings.append(ring)
    for i in range(segs):
        for j in range(rsegs):
            a, b_ = rings[i], rings[(i + 1) % segs]
            bm.faces.new([a[j], b_[j], b_[(j + 1) % rsegs], a[(j + 1) % rsegs]])
    _apply(bm, mtx)
    return _obj(name, bm, mat, smooth=True)


def _ccw(pts):
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return pts if a > 0 else list(reversed(pts))


def P(pts_uv, z0, z1, mat, bev=0.01, seg=2, mtx=None, name="prism", sub=0, smooth=False):
    """Vertical prism from a (u, v) outline."""
    pts = _ccw([(u, -v) for u, v in pts_uv])
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    n = len(pts)
    for k in range(n):
        bm.faces.new([lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]])
    _apply(bm, mtx)
    return _obj(name, bm, mat, bev=bev, seg=seg, sub=sub, smooth=smooth)


def rrect(u0, v0, u1, v1, r, n=5):
    r = min(r, (u1 - u0) / 2, (v1 - v0) / 2)
    pts = []
    for cu, cv, a0 in ((u1 - r, v0 + r, -90), (u1 - r, v1 - r, 0), (u0 + r, v1 - r, 90), (u0 + r, v0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
    return pts


def ell(cu, cv, ru, rv, n=32, a0=0, a1=360):
    full = (a1 - a0) % 360 == 0
    k = n if full else n + 1
    return [(cu + ru * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cv + rv * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(k)]


def RB(u0, v0, u1, v1, z0, z1, mat, r=0.08, bev=0.02, mtx=None, name="rbox", sub=0):
    """Box with rounded vertical corners."""
    return P(rrect(u0, v0, u1, v1, r), z0, z1, mat, bev=bev, mtx=mtx, name=name, sub=sub, smooth=True)


def cushion(u0, v0, u1, v1, z0, z1, mat, puff=0.35, mtx=None, name="cushion"):
    """Soft cushion: subdivided box, rounded."""
    bm = bmesh.new()
    r = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=2, use_grid_fill=True)
    du, dv, dz = abs(u1 - u0), abs(v1 - v0), abs(z1 - z0)
    for v in bm.verts:
        x, y, z = v.co
        k = 1.0 + puff * (1 - (2 * abs(x)) ** 2) * (1 - (2 * abs(y)) ** 2) * (1 if z > 0 else 0.3) * (2 * abs(z))
        v.co = Vector(((u0 + u1) / 2 + x * du, -(v0 + v1) / 2 + y * dv, (z0 + z1) / 2 + z * dz * k))
    _apply(bm, mtx)
    ob = _obj(name, bm, mat, smooth=True)
    md = ob.modifiers.new("Sub", "SUBSURF")
    md.levels = md.render_levels = 2
    md.use_creases = True
    return ob


def cloth(u0, v0, u1, v1, z, mat, amp=0.04, freq=3.0, droop=0.12, seed=0, edges="lrb", thick=0.03, res=24, fold=0.0):
    """Draped sheet (duvets, throws): noisy displaced grid that droops at the given edges."""
    bm = bmesh.new()
    nu, nv = res, max(4, int(res * (v1 - v0) / max(0.01, u1 - u0)))
    vs = []
    off = Vector((seed * 7.3, seed * 3.1, 0))
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            tu, tv = i / nu, j / nv
            u, v = u0 + (u1 - u0) * tu, v0 + (v1 - v0) * tv
            h = z + amp * mnoise.noise(Vector((u * freq, v * freq, 0)) + off)
            h += fold * math.sin(tv * math.pi * 6) * 0.5
            e = 0.0
            if "l" in edges:
                e = max(e, 1 - tu * (u1 - u0) / 0.12)
            if "r" in edges:
                e = max(e, 1 - (1 - tu) * (u1 - u0) / 0.12)
            if "b" in edges:
                e = max(e, 1 - (1 - tv) * (v1 - v0) / 0.12)
            if "t" in edges:
                e = max(e, 1 - tv * (v1 - v0) / 0.12)
            h -= droop * max(0.0, e) ** 2
            row.append(bm.verts.new((u, -v, h)))
        vs.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new([vs[j][i], vs[j + 1][i], vs[j + 1][i + 1], vs[j][i + 1]])
    ob = _obj("cloth", bm, mat, smooth=True, solid=thick)
    md = ob.modifiers.new("Sub", "SUBSURF")
    md.levels = md.render_levels = 1
    return ob


def blob(cu, cv, cz, r, mat, seed=0, rough=0.25, squash=1.0, subd=3, name="blob"):
    """Noisy icosphere (foliage crowns)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subd, radius=r)
    off = Vector((seed * 13.1, seed * 5.7, seed * 2.3))
    for v in bm.verts:
        d = v.co.normalized()
        k = 1 + rough * mnoise.noise(d * 2.5 + off) + rough * 0.5 * mnoise.noise(d * 6 + off)
        v.co = Vector((d.x * r * k, d.y * r * k, d.z * r * k * squash))
    bmesh.ops.translate(bm, vec=(cu, -cv, cz), verts=bm.verts)
    return _obj(name, bm, mat, smooth=True)


def leaves(cu, cv, z, n, r0, r1, length, width, mat, seed=0, lift=(0.6, 0.1), droop=0.25, name="leaves"):
    """Rosette of leaves radiating from (cu, cv)."""
    rng = random.Random(seed)
    bm = bmesh.new()
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi) if n > 8 else 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        r = rng.uniform(r0, r1)
        L = length * rng.uniform(0.75, 1.15)
        W = width * rng.uniform(0.8, 1.2)
        el = rng.uniform(*lift) if isinstance(lift, tuple) else lift
        base = Vector((cu + math.cos(a) * r * 0.15, -cv + math.sin(a) * r * 0.15, z + rng.uniform(-0.05, 0.05)))
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        prof = [(0, 0), (0.2, 0.35), (0.45, 0.5), (0.7, 0.4), (0.9, 0.18), (1.0, 0.0)]
        left, right, mid = [], [], []
        for t, wv in prof:
            reach = r * 0.15 + (r - r * 0.15) * 0 + L * t
            p = base + d * (L * t) + Vector((0, 0, L * t * el - droop * L * t * t))
            left.append(bm.verts.new(p + side * W * wv + Vector((0, 0, -0.01 * wv))))
            right.append(bm.verts.new(p - side * W * wv + Vector((0, 0, -0.01 * wv))))
            mid.append(bm.verts.new(p + Vector((0, 0, 0.012))))
        for k in range(len(prof) - 1):
            bm.faces.new([mid[k], mid[k + 1], left[k + 1], left[k]] if k else [mid[0], mid[1], left[1]])
            bm.faces.new([mid[k], right[k], right[k + 1], mid[k + 1]] if k else [mid[0], right[1], mid[1]])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return _obj(name, bm, mat, smooth=True)


def meta(name, elems, mat, res=0.025):
    """Metaball family. elems: (kind, (u, v, z), radius, (sx, sy, sz) or None, stiffness[, negative])."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = 0.6
    for e in elems:
        kind, (u, v, z), rad = e[0], e[1], e[2]
        el = mb.elements.new(type=kind)
        el.co = (u, -v, z)
        el.radius = rad
        if len(e) > 3 and e[3]:
            el.size_x, el.size_y, el.size_z = e[3]
        if len(e) > 4 and e[4]:
            el.stiffness = e[4]
        if len(e) > 5 and e[5]:
            el.use_negative = True
    ob = _link(bpy.data.objects.new(name, mb))
    mb.materials.append(mat)
    return ob


def text(body, cu, cv, z, size, mat, ext=0.003, rot=0.0):
    cu_ = bpy.data.curves.new("txt", "FONT")
    cu_.body = body
    cu_.size = size
    cu_.align_x = "CENTER"
    cu_.align_y = "CENTER"
    cu_.extrude = ext
    ob = _link(bpy.data.objects.new("txt", cu_))
    ob.location = (cu, -cv, z)
    ob.rotation_euler = (0, 0, -math.radians(rot))
    cu_.materials.append(mat)
    return ob


# --- scene / render --------------------------------------------------------------

def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.metaballs, bpy.data.lights, bpy.data.cameras):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def _gpu():
    try:
        p = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                p.compute_device_type = kind
                p.get_devices()
                if any(dv.type == kind for dv in p.devices):
                    for dv in p.devices:
                        dv.use = dv.type == kind
                    return kind
            except TypeError:
                continue
    except Exception as e:
        print("GPU setup failed:", e)
    return "CPU"


def setup_scene(samples):
    sc = bpy.context.scene
    r = sc.render
    r.engine = "CYCLES"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    try:
        sc.cycles.use_adaptive_sampling = True
    except Exception:
        pass
    r.film_transparent = True
    r.filter_size = 1.0
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.resolution_percentage = 100
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.0
    w = bpy.data.worlds.get("LH_World") or bpy.data.worlds.new("LH_World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*lin("#c9d2e0"), 1)
    bg.inputs[1].default_value = 0.85
    return sc


def lights(key=3.2, angle=18, fill=0.0):
    """Key sun from the top-left of the image (from -u, -v), elevation ~55 deg."""
    d = Vector((0.55, -0.62, -1.15)).normalized()   # light travel direction (Blender coords)
    ld = bpy.data.lights.new("Key", "SUN")
    ld.energy = key
    ld.angle = math.radians(angle)
    ld.color = lin("#fff4e6")
    ob = _link(bpy.data.objects.new("Key", ld))
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if fill:
        ld2 = bpy.data.lights.new("Fill", "SUN")
        ld2.energy = fill
        ld2.angle = math.radians(40)
        ld2.color = lin("#dfe8ff")
        ob2 = _link(bpy.data.objects.new("Fill", ld2))
        ob2.rotation_euler = Vector((-0.6, 0.5, -1.0)).normalized().to_track_quat("-Z", "Y").to_euler()
        ld2.use_shadow = False


def camera(w, h):
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = max(w, h)
    cd.sensor_fit = "HORIZONTAL" if w >= h else "VERTICAL"
    cd.clip_start = 0.01
    cd.clip_end = 100
    cam = _link(bpy.data.objects.new("Cam", cd))
    cam.location = (w / 2, -h / 2, 20)
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.resolution_x = int(round(w * PX))
    sc.render.resolution_y = int(round(h * PX))


def render(path):
    path = os.path.abspath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# --- home shells -----------------------------------------------------------------

STYLE = {
    # wood = (c0, c1, gap, plank width, plank length, wear); tile = (col, grout, size[, col2 = checkerboard])
    "rental": dict(wood=("#b48c5e", "#93714b", "#3a2a1c", 0.16, 0.9, 0.35), tile=("#d9d0bf", "#a39a8a", 0.25), carpet="#8c8377",
                   concrete="#9a968f", marble=("#e6e2da", "#a8a39b"), door="#a07850", frame="#e8e2d6", garden="wall"),
    "modern": dict(wood=("#d2b28a", "#b8946a", "#4b3826", 0.2, 1.6, 0.0), tile=("#ebe9e5", "#c9c5bf", 0.6), carpet="#b7b2aa",
                   concrete="#a3a19c", marble=("#ecebe8", "#aeaba5"), door="#3d3f44", frame="#2b2d31", garden="planter"),
    "suburban": dict(wood=("#c09468", "#a07a52", "#3e2b1c", 0.15, 1.2, 0.05), tile=("#e2dccf", "#b5ab9a", 0.33), carpet="#b3a998",
                     concrete="#9c9993", marble=("#e8e4dc", "#aaa498"), door="#7b2e22", frame="#f0ece4", garden="hedge"),
    "classic": dict(wood=("#9c6a42", "#7e522f", "#2e1d12", 0.11, 0.8, 0.05), tile=("#e9e5dc", "#3c3a37", 0.3, "#2d2b29"), carpet="#7d2f32",
                    concrete="#9c9993", marble=("#ebe7df", "#9e978a"), door="#1f3a2e", frame="#f2eee6", garden="hedge"),
    "coastal": dict(wood=("#d6c3a3", "#bba584", "#5d4c38", 0.18, 1.6, 0.05), tile=("#e9eef0", "#9bb7c2", 0.2), carpet="#b5ae9c",
                    concrete="#a8a69f", marble=("#eeede9", "#b2b0aa"), door="#3f6f8f", frame="#f4f4f2", garden="glass"),
    "loft": dict(wood=("#6f4a2f", "#55361f", "#1c120b", 0.2, 2.0, 0.15), tile=("#2f3033", "#1c1c1e", 0.2), carpet="#5f6268",
                 concrete="#8d8b86", marble=("#d8d6d2", "#8a8782"), door="#2a2a2c", frame="#1d1d1f", garden="planter"),
    "villa": dict(wood=("#b8875c", "#966a43", "#3b2717", 0.16, 1.4, 0.0), tile=("#dccdb3", "#b9a586", 0.5), carpet="#b9ab95",
                  concrete="#a29d94", marble=("#f0ece4", "#b7ab98"), door="#6e4a2c", frame="#e9e1d2", garden="stone"),
    "penthouse": dict(wood=("#5b3d29", "#432b1c", "#140d08", 0.2, 2.2, 0.0), tile=("#2b2b2f", "#18181a", 0.8), carpet="#a99e8c",
                      concrete="#7c7a77", marble=("#222226", "#8a8275", "#2e2d2c"), door="#141416", frame="#121214", garden="glass"),
}
WALLS = {  # (rim, core) materials by the home's "walls" field: rim = full cell, core = inset raised wall top
    "plaster_worn": lambda: (m_plain("wall_worn", "#d2c7b4", rough=0.9, var=0.1, vscale=3.0, bumpk=0.15, bscale=60),
                             m_plain("wallc_worn", "#8d8273", rough=0.9, var=0.12, vscale=3.0, bumpk=0.2, bscale=60)),
    "plaster_white": lambda: (m_plain("wall_white", "#f4f2ee", rough=0.8, var=0.03, bumpk=0.06, bscale=80),
                              m_plain("wallc_white", "#a9a6a1", rough=0.8, var=0.04, bumpk=0.06, bscale=80)),
    "plaster_warm": lambda: (m_plain("wall_warm", "#efe5d4", rough=0.85, var=0.05, bumpk=0.08, bscale=80),
                             m_plain("wallc_warm", "#a39582", rough=0.85, var=0.06, bumpk=0.08, bscale=80)),
    "plaster_blue": lambda: (m_plain("wall_blue", "#eef2f3", rough=0.85, var=0.04, bumpk=0.08, bscale=80),
                             m_plain("wallc_blue", "#7f98a6", rough=0.85, var=0.05, bumpk=0.08, bscale=80)),
    "brick": lambda: (m_plain("wall_brickrim", "#3a3533", rough=0.7, var=0.05), m_brick("wall_brick")),
    "stone_white": lambda: (m_plain("wall_stone", "#efe6d4", rough=0.85, var=0.05, bumpk=0.1, bscale=40),
                            m_plain("wallc_stone", "#b59f7c", rough=0.85, var=0.14, vscale=5.0, bumpk=0.35, bscale=25)),
    "marble_dark": lambda: (m_plain("wall_darkrim", "#6a665f", rough=0.3, metal=0.3),
                            m_plain("wallc_dark", "#26262a", rough=0.25, var=0.06, vscale=3.0, coat=0.5)),
}


def _style(d):
    st = STYLE.get(d.get("style"), STYLE["modern"])
    wk = d.get("walls", "plaster_white")
    if wk not in WALLS:
        wk = "brick" if "brick" in wk else "marble_dark" if ("marble" in wk or "dark" in wk) else \
            "stone_white" if "stone" in wk else "plaster_worn" if "worn" in wk else "plaster_white"
    return st, WALLS[wk]()


def _floor_mats(sid, st):
    w = st["wood"]
    t = st["tile"]
    mk = st["marble"]
    return {
        ".": m_planks("floor_wood_" + sid, w[0], w[1], plank_w=w[3], plank_l=w[4], gap=w[2], wear=w[5]),
        ",": m_tiles("floor_tile_" + sid, t[0], t[1], size=t[2], col2=t[3] if len(t) > 3 else None, var=0.0 if len(t) > 3 else 0.05),
        "~": m_carpet("floor_carpet_" + sid, st["carpet"]),
        "_": m_concrete("floor_concrete_" + sid, st["concrete"]),
        "m": m_marble("floor_marble_" + sid, mk[0], mk[1], tile=1.0, vein2=mk[2] if len(mk) > 2 else None),
        "d": m_planks("floor_deck", "#a8784f", "#946640", plank_w=0.14, plank_l=3.0, gap="#3a2616", rough=0.7, coat=0.0, axis="Y", gapw=0.008, wear=0.25),
        "g": m_grass("floor_grass"),
        "s": m_patio("floor_patio"),
    }


def build_shell(d):
    grid = d["grid"]
    H, W = len(grid), len(grid[0])
    sid = d.get("style", "modern")
    st, (wall_mat, core_mat) = _style(d)
    fm = _floor_mats(sid, st)

    def ch(x, y):
        return grid[y][x] if 0 <= x < W and 0 <= y < H else " "

    def is_floor(c):
        return c in IN_FLOOR + OUT_FLOOR

    def horiz(x, y):
        """Does the wall line through (x, y) run along u?"""
        l, r, u, dn = ch(x - 1, y), ch(x + 1, y), ch(x, y - 1), ch(x, y + 1)
        a = (l in WALLISH + "D") + (r in WALLISH + "D")
        b = (u in WALLISH + "D") + (dn in WALLISH + "D")
        if a != b:
            return a > b
        return is_floor(u) or is_floor(dn) or u == " " or dn == " "

    def garden(x, y):
        """Wall cell that only borders outdoor floor (no interior floor nearby)."""
        ns = [ch(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
        return not any(c in IN_FLOOR for c in ns) and any(c in OUT_FLOOR for c in ns)

    def door_floor(x, y):
        hz = horiz(x, y)
        cands = [ch(x, y + 1), ch(x, y - 1)] if hz else [ch(x + 1, y), ch(x - 1, y)]
        for c in cands:
            if c in IN_FLOOR and c != "D":
                return c
        for c in cands:
            if c in OUT_FLOOR and c != "w":
                return c
        return "."

    # Floors (one mesh, material per char).
    order = list(fm.keys())
    bm = bmesh.new()
    pool = []
    for y in range(H):
        for x in range(W):
            c = ch(x, y)
            if c == "w":
                pool.append((x, y))
                continue
            if c == "D":
                c = door_floor(x, y)
            if c not in fm:
                continue
            vs = [bm.verts.new(p) for p in (X(x, y + 1), X(x + 1, y + 1), X(x + 1, y), X(x, y))]
            f = bm.faces.new(vs)
            f.material_index = order.index(c)
    _obj("floor", bm, None, mats=[fm[k] for k in order])

    # Pool: basin, water, coping.
    if pool:
        pt = m_pooltile("pooltile")
        cop = m_plain("coping", "#e8e1d3", rough=0.6, var=0.06, bumpk=0.2, bscale=40)
        bm = bmesh.new()
        depth = -1.1
        for x, y in pool:
            bm.faces.new([bm.verts.new(p) for p in (X(x, y + 1, depth), X(x + 1, y + 1, depth), X(x + 1, y, depth), X(x, y, depth))])
            for dx, dy, a, b_ in ((1, 0, (x + 1, y), (x + 1, y + 1)), (-1, 0, (x, y + 1), (x, y)), (0, 1, (x + 1, y + 1), (x, y + 1)), (0, -1, (x, y), (x + 1, y))):
                if ch(x + dx, y + dy) != "w":
                    bm.faces.new([bm.verts.new(p) for p in (X(*a, depth), X(*b_, depth), X(*b_, 0), X(*a, 0))])
        _obj("pool", bm, pt)
        bm = bmesh.new()
        for x, y in pool:
            bm.faces.new([bm.verts.new(p) for p in (X(x, y + 1, -0.12), X(x + 1, y + 1, -0.12), X(x + 1, y, -0.12), X(x, y, -0.12))])
        _obj("water", bm, m_water("poolwater", "#9be3f0", deep="#2a9fc0", depth_w=0.3))
        cw = 0.2
        for x, y in pool:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if ch(x + dx, y + dy) == "w":
                    continue
                if dx == 1:
                    B(x + 1 - cw, y, x + 1, y + 1, -0.02, 0.05, cop, bev=0.02)
                elif dx == -1:
                    B(x, y, x + cw, y + 1, -0.02, 0.05, cop, bev=0.02)
                elif dy == 1:
                    B(x, y + 1 - cw, x + 1, y + 1, -0.02, 0.05, cop, bev=0.02)
                else:
                    B(x, y, x + 1, y + cw, -0.02, 0.05, cop, bev=0.02)

    # Walls: union meshes (shared verts) so bevels only round the outer edges.
    def union(cells, h, mat, name, bev, sub=0):
        if not cells:
            return None
        bm = bmesh.new()
        vk = {}

        def v(px, py, z):
            k = (px, py, z)
            if k not in vk:
                vk[k] = bm.verts.new(X(px, py, z))
            return vk[k]
        cs = set(cells)
        for x, y in cells:
            bm.faces.new([v(x, y + 1, h), v(x + 1, y + 1, h), v(x + 1, y, h), v(x, y, h)])
            for dx, dy, a, b_ in ((1, 0, (x + 1, y + 1), (x + 1, y)), (-1, 0, (x, y), (x, y + 1)), (0, 1, (x, y + 1), (x + 1, y + 1)), (0, -1, (x + 1, y), (x, y))):
                if (x + dx, y + dy) not in cs:
                    bm.faces.new([v(*a, 0), v(*b_, 0), v(*b_, h), v(*a, h)])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return _obj(name, bm, mat, bev=bev, seg=3, sub=sub)

    walls, gwalls = [], []
    for y in range(H):
        for x in range(W):
            c = ch(x, y)
            if c in "#W":
                (gwalls if c == "#" and garden(x, y) else walls).append((x, y))
    union(walls, WALL_H, wall_mat, "walls", 0.06)
    # Raised inset core: wall top cap, inset from every edge that faces floor (thickness read).
    ins = 0.16
    cells = set(walls) | {(x, y) for y in range(H) for x in range(W) if ch(x, y) == "E"}
    bm = bmesh.new()
    vk = {}

    def cv(px, py):
        k = (round(px, 4), round(py, 4))
        if k not in vk:
            vk[k] = bm.verts.new(X(px, py, WALL_H + 0.025))
        return vk[k]
    segs = ((0, ins), (ins, 1 - ins), (1 - ins, 1))
    for x, y in walls:
        for i in range(3):
            for j in range(3):
                dx, dy = i - 1, j - 1
                ok = True
                if dx and (x + dx, y) not in cells:
                    ok = False
                if dy and (x, y + dy) not in cells:
                    ok = False
                if dx and dy and (x + dx, y + dy) not in cells:
                    ok = False
                if not ok:
                    continue
                (a0, a1), (b0, b1) = segs[i], segs[j]
                bm.faces.new([cv(x + a0, y + b1), cv(x + a1, y + b1), cv(x + a1, y + b0), cv(x + a0, y + b0)])
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    bmesh.ops.translate(bm, vec=(0, 0, -0.05), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _obj("wallcap", bm, core_mat, bev=0.025, seg=2)
    gk = st["garden"]
    if gwalls:
        if gk == "hedge":
            hm = m_leaf("hedge", "#4c7f32", "#2b5520", rough=0.8)
            union(gwalls, 0.7, hm, "hedge", 0.15)
            for x, y in gwalls:  # leafy lumps on top
                for k in range(2):
                    rr = random.Random(x * 131 + y * 17 + k)
                    blob(x + rr.uniform(0.3, 0.7), y + rr.uniform(0.3, 0.7), 0.62, rr.uniform(0.34, 0.42), hm, seed=x * 7 + y * 3 + k, rough=0.3, squash=0.45, subd=2)
        elif gk == "stone":
            union(gwalls, GARDEN_H, m_plain("gwall_stone", "#dccbaa", rough=0.85, var=0.12, vscale=4.0, bumpk=0.35, bscale=25), "gwall", 0.06)
            for x, y in gwalls:
                if (x * 3 + y * 5) % 4 == 0:
                    blob(x + 0.5, y + 0.5, GARDEN_H, 0.3, m_leaf("shrub", "#5d8f3b", "#2f5a24"), seed=x + y * 13, rough=0.35, squash=0.55, subd=2)
        elif gk == "glass":
            # Low curb + glass balustrade with a steel handrail along each cell's centre line.
            union(gwalls, 0.12, m_plain("curb_" + sid, "#4a4947" if sid == "penthouse" else "#d9d6d0", rough=0.5, var=0.05), "curb", 0.03)
            gl = m_glass("railglass", "#cfeaf2", refl=0.4)
            steel = m_plain("steel", "#c9ccd0", rough=0.25, metal=1.0)
            for x, y in gwalls:
                if horiz(x, y):
                    B(x, y + 0.42, x + 1, y + 0.58, 0.12, 1.0, gl, bev=0)
                    B(x, y + 0.45, x + 1, y + 0.55, 1.0, 1.05, steel, bev=0.01)
                else:
                    B(x + 0.42, y, x + 0.58, y + 1, 0.12, 1.0, gl, bev=0)
                    B(x + 0.45, y, x + 0.55, y + 1, 1.0, 1.05, steel, bev=0.01)
        else:  # rendered garden wall (rental) / with shrubs (planter)
            union(gwalls, GARDEN_H, m_plain("gwall_render", "#cfc8bb", rough=0.85, var=0.08, bumpk=0.2, bscale=40), "gwall", 0.05)
            if gk == "planter":
                for x, y in gwalls:
                    if (x * 3 + y * 5) % 3 == 0:
                        blob(x + 0.5, y + 0.5, GARDEN_H, 0.33, m_leaf("shrub", "#5d8f3b", "#2f5a24"), seed=x + y * 13, rough=0.35, squash=0.55, subd=2)

    # Windows: glass strip set into the wall top, frame, and daylight spilling in.
    glass = m_glass("winglass", "#bfe3f2", refl=0.5, rough=0.02)
    sky = m_emit("winsky", "#cfe9ff", 0.8)
    frame = m_plain("frame_" + sid, st["frame"], rough=0.35, metal=0.3 if sid in ("loft", "penthouse", "modern") else 0.0)
    for y in range(H):
        for x in range(W):
            if ch(x, y) != "W":
                continue
            hz = horiz(x, y)
            gw = 0.3

            def wb(a0, b0, a1, b1, z0, z1, mat, bev=0.0):
                if hz:
                    return B(x + a0, y + b0, x + a1, y + b1, z0, z1, mat, bev=bev)
                return B(x + b0, y + a0, x + b1, y + a1, z0, z1, mat, bev=bev)
            lo_, hi_ = 0.5 - gw / 2, 0.5 + gw / 2
            zw = WALL_H + 0.03
            wb(-0.001, lo_ - 0.06, 1.001, hi_ + 0.06, zw - 0.02, zw + 0.012, frame, 0.01)
            wb(0, lo_, 1, hi_, zw + 0.013, zw + 0.016, sky)
            wb(0, lo_, 1, hi_, zw + 0.02, zw + 0.024, glass)
            wb(0.475, lo_, 0.525, hi_, zw + 0.012, zw + 0.03, frame, 0.004)
            wb(0, 0.49, 1, 0.51, zw + 0.012, zw + 0.027, frame)
            # daylight: an area light just inside, aimed down and into the room
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                if ch(x + dx, y + dy) in IN_FLOOR:
                    ld = bpy.data.lights.new("Day", "AREA")
                    ld.shape = "RECTANGLE"
                    ld.size, ld.size_y = (1.0, 0.25) if dy else (0.25, 1.0)
                    ld.energy = 22
                    ld.color = lin("#e3f0ff")
                    lo = _link(bpy.data.objects.new("Day", ld))
                    lo.location = X(x + 0.5 + dx * 0.55, y + 0.5 + dy * 0.55, WALL_H * 0.9)
                    tgt = X(x + 0.5 + dx * 1.6, y + 0.5 + dy * 1.6, 0)
                    lo.rotation_euler = (tgt - lo.location).to_track_quat("-Z", "Y").to_euler()
                    lo.visible_camera = False
                    lo.visible_glossy = False

    # Doors.
    door = m_wood("door_" + sid, st["door"], st["door"], scale=3.0, grain=0.3, coat=0.3)
    chrome = m_plain("chrome", "#e6e8ea", rough=0.12, metal=1.0)
    thr = m_plain("threshold_" + sid, "#b9b2a6" if sid not in ("penthouse", "loft") else "#3b3b3e", rough=0.45, var=0.05)
    alu = m_plain("alu", "#b8bcc2", rough=0.3, metal=1.0)
    glass2 = m_glass("doorglass", "#cfeaf2", refl=0.35)
    jt = 0.12  # jamb width along the wall
    for y in range(H):
        for x in range(W):
            c = ch(x, y)
            if c not in "ED":
                continue
            hz = horiz(x, y)

            def bx(a0, b0, a1, b1, z0, z1, mat, bev=0.01):
                """Box in wall-local coords: a along the wall, b across it (0..1)."""
                if hz:
                    return B(x + a0, y + b0, x + a1, y + b1, z0, z1, mat, bev=bev)
                return B(x + b0, y + a0, x + b1, y + a1, z0, z1, mat, bev=bev)
            prev_d = (ch(x - 1, y) if hz else ch(x, y - 1)) == c
            next_d = (ch(x + 1, y) if hz else ch(x, y + 1)) == c
            if c == "E":
                bx(0, 0, 1, 1, 0, 0.03, thr, bev=0.01)
                bx(0, 0, jt, 1, 0, WALL_H, wall_mat, bev=0.03)
                bx(1 - jt, 0, 1, 1, 0, WALL_H, wall_mat, bev=0.03)
                bx(jt, 0.3, 1 - jt, 0.7, 0, WALL_H - 0.03, frame, bev=0.01)               # frame / lintel
                bx(jt + 0.03, 0.36, 1 - jt - 0.03, 0.64, 0, WALL_H - 0.01, door, bev=0.015)  # door leaf (closed)
                bx(jt + 0.1, 0.4, 1 - jt - 0.1, 0.6, WALL_H - 0.01, WALL_H - 0.0, door, bev=0.01)  # raised panel
                for b0 in (0.31, 0.64):  # handles, both faces
                    bx(0.7, b0, 0.8, b0 + 0.05, WALL_H - 0.03, WALL_H + 0.01, chrome, bev=0.008)
                continue
            # D: interior doorway / patio opening. Floor already drawn; jambs + threshold.
            run = prev_d or next_d
            if not prev_d:
                bx(0, 0, jt, 1, 0, WALL_H, wall_mat, bev=0.03)
            if not next_d:
                bx(1 - jt, 0, 1, 1, 0, WALL_H, wall_mat, bev=0.03)
            a0 = 0 if prev_d else jt
            a1 = 1 if next_d else 1 - jt
            bx(a0, 0.42, a1, 0.58, 0, 0.012, alu if run else thr, bev=0.003)
            if not run:
                # open leaf hinged at the first jamb, swung ~55 deg into a floor side (wall-local a/b coords)
                fwd = ch(x, y + 1) if hz else ch(x + 1, y)
                side = 1 if fwd in IN_FLOOR + OUT_FLOOR else -1
                L, ang = 0.62, math.radians(58)
                ha, hb = jt + 0.02, 0.5
                ea, eb = ha + L * math.cos(ang), hb + side * L * math.sin(ang)
                # leaf as a thin prism along the hinge->end segment
                pa = Vector((ea - ha, eb - hb)).normalized()
                n2 = Vector((-pa.y, pa.x)) * 0.035
                quad = [(ha + n2.x, hb + n2.y), (ea + n2.x, eb + n2.y), (ea - n2.x, eb - n2.y), (ha - n2.x, hb - n2.y)]
                pts = [(x + a, y + b) if hz else (x + b, y + a) for a, b in quad]
                P(pts, 0, WALL_H * 0.85, door, bev=0.008)
                # handle
                mid = (ha + (ea - ha) * 0.85, hb + (eb - hb) * 0.85)
                hp = (x + mid[0], y + mid[1]) if hz else (x + mid[1], y + mid[0])
                S(hp[0], hp[1], WALL_H * 0.86, 0.03, 0.03, 0.015, chrome)
            else:
                # sliding glass panels parked at the run's ends
                if not prev_d:
                    bx(jt, 0.36, 0.8, 0.42, 0, WALL_H * 0.9, glass2, bev=0)
                    bx(jt, 0.35, 0.8, 0.43, WALL_H * 0.9, WALL_H * 0.93, alu, bev=0.003)
                if not next_d:
                    bx(0.2, 0.58, 1 - jt, 0.64, 0, WALL_H * 0.9, glass2, bev=0)
                    bx(0.2, 0.57, 1 - jt, 0.65, WALL_H * 0.9, WALL_H * 0.93, alu, bev=0.003)
    return W, H


def render_home(project, hid, out_dir, samples=128):
    d = json.load(open(os.path.join(project, "data", "homes", hid + ".json")))
    clear()
    W, H = build_shell(d)
    lights(key=2.6, angle=12)
    camera(W, H)
    bpy.context.scene.cycles.samples = samples
    return render(os.path.join(out_dir, hid + ".png"))


# --- props -----------------------------------------------------------------------

BUILDERS = {}

def prop(fn):
    BUILDERS[fn.__name__.lstrip("_")] = fn
    return fn


def ringP(outer, inner, z0, z1, mat, name="ring", bev=0.0, sub=0, smooth=True):
    """Prism with a hole: outer and inner outlines need the same point count and winding."""
    o = _ccw([(u, -v) for u, v in outer])
    i_ = _ccw([(u, -v) for u, v in inner])
    bm = bmesh.new()
    ob_, ot = [bm.verts.new((x, y, z0)) for x, y in o], [bm.verts.new((x, y, z1)) for x, y in o]
    ib, it_ = [bm.verts.new((x, y, z0)) for x, y in i_], [bm.verts.new((x, y, z1)) for x, y in i_]
    n = len(o)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new([ot[k], ot[k2], it_[k2], it_[k]])        # top
        bm.faces.new([ob_[k], ib[k], ib[k2], ob_[k2]])        # bottom
        bm.faces.new([ob_[k], ob_[k2], ot[k2], ot[k]])        # outer wall
        bm.faces.new([ib[k], it_[k], it_[k2], ib[k2]])        # inner wall
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, mat, bev=bev, sub=sub, smooth=smooth)


# shared palette (cached by name, so cheap to call anywhere)
def MAT():
    return {
        "oak": m_wood("oak", "#c9a275", "#a07850"),
        "walnut": m_wood("walnut", "#7d5539", "#4f3322"),
        "pine": m_wood("pine", "#dcbc8d", "#bb9563", grain=0.7),
        "dark": m_wood("darkwood", "#4b3427", "#2c1e15"),
        "white": m_plain("white_laq", "#efede9", rough=0.35, coat=0.3),
        "offwhite": m_plain("offwhite", "#e3ddd2", rough=0.5),
        "black": m_plain("black_pl", "#1c1d20", rough=0.45),
        "blackgloss": m_plain("black_gloss", "#0e0e10", rough=0.08, coat=1.0),
        "steel": m_plain("steel_br", "#b4b8be", rough=0.32, metal=1.0, var=0.04, vscale=60),
        "chrome": m_plain("chrome", "#e6e8ea", rough=0.12, metal=1.0),
        "gold": m_plain("gold", "#f2c04a", rough=0.18, metal=1.0, emit=0.15, ecol="#f2c04a"),
        "ceramic": m_plain("ceramic", "#f6f6f4", rough=0.12, coat=0.6),
        "glass": m_glass("propglass", "#dff1f6", refl=0.3),
        "cglass": m_plain("carglass", "#1b2633", rough=0.04, coat=1.0, spec=1.0),
        "rubber": m_plain("rubber", "#1a1a1a", rough=0.85),
        "linen": m_fabric("linen", "#f2efe8", weave=500, var=0.04),
        "soil": m_plain("soil", "#3b2a1d", rough=0.95, var=0.25, vscale=40, bumpk=0.4, bscale=80),
        "terracotta": m_plain("terracotta", "#b8623e", rough=0.8, var=0.08),
        "potwhite": m_plain("potwhite", "#e9e7e2", rough=0.4),
        "leaf": m_leaf("leaf", "#5c9a3f", "#2f6127"),
        "leafdark": m_leaf("leafdark", "#3f7a35", "#1f4a1d"),
        "screenblack": m_plain("screenoff", "#0b0c0e", rough=0.05, coat=1.0),
    }


def pot_plant(cu, cv, pr, ph, leaf_n, leaf_len, seed, pot="terracotta", big=False):
    M = MAT()
    C(cu, cv, pr, 0, ph, M[pot], segs=28, r2=pr * 0.8 if pot == "terracotta" else pr, bev=0.01)
    T(cu, cv, ph, pr - 0.012, 0.014, M[pot])
    C(cu, cv, pr - 0.02, ph - 0.05, ph - 0.03, M["soil"], segs=28)
    if big:
        for k, (dz, n, L) in enumerate(((0.9, 14, leaf_len), (1.15, 12, leaf_len * 0.85), (1.35, 9, leaf_len * 0.7))):
            leaves(cu, cv, dz, n, 0.0, 0.0, L, L * 0.45, M["leaf"] if k % 2 else M["leafdark"], seed=seed + k, lift=(0.05, 0.35), droop=0.35)
        C(cu, cv, 0.025, ph, 1.3, m_wood("trunk", "#6b4a32", "#4a3222"), segs=8)
    else:
        leaves(cu, cv, ph + 0.03, leaf_n, 0, 0, leaf_len, leaf_len * 0.42, M["leaf"], seed=seed, lift=(0.5, 1.1), droop=0.9)
        leaves(cu, cv, ph + 0.05, leaf_n // 2, 0, 0, leaf_len * 0.7, leaf_len * 0.35, M["leafdark"], seed=seed + 9, lift=(1.0, 1.6), droop=1.0)


def pillow(u0, v0, u1, v1, z0, mat, th=0.13, mtx=None):
    return cushion(u0, v0, u1, v1, z0, z0 + th, mat, puff=0.6, mtx=mtx, name="pillow")


def lampshade(cu, cv, z, r, h, mat_shade, glow="#ffd9a0"):
    ob = C(cu, cv, r, z, z + h, mat_shade, r2=r * 0.82, segs=32, caps=False)
    md = ob.modifiers.new("Solid", "SOLIDIFY")
    md.thickness = 0.008
    S(cu, cv, z + h * 0.45, r * 0.3, r * 0.3, r * 0.3, m_emit("bulb", glow, 6.0))
    C(cu, cv, r * 0.78, z + h * 0.3, z + h * 0.32, m_emit("shadeglow", "#ffd9a8", 0.6), r2=r * 0.78)


# ---- sleeping ----

@prop
def mattress(w, h):
    M = MAT()
    tick = m_fabric("ticking", "#e8e4dc", "#c9c2b5", weave=420, pattern="stripe", pscale=18)
    RB(0.12, 0.15, 1.88, 2.88, 0, 0.2, tick, r=0.06, bev=0.04)
    pillow(0.45, 0.3, 1.45, 0.72, 0.19, m_fabric("pillow_dingy", "#e4dfd2"), th=0.12)
    du = m_fabric("duvet_rent", "#7d8fa6", weave=380)
    cloth(0.08, 0.95, 1.95, 2.95, 0.3, du, amp=0.07, freq=2.6, droop=0.12, seed=3, edges="lrb", res=26)
    cloth(0.55, 0.85, 1.5, 1.35, 0.33, du, amp=0.06, freq=4, droop=0.0, seed=8, edges="", res=10)  # rumpled heap


@prop
def bed_single(w, h):
    M = MAT()
    wd = M["pine"]
    B(0.12, 0.1, 1.88, 2.92, 0.1, 0.32, wd, bev=0.02)
    B(0.08, 0.05, 1.92, 0.18, 0, 0.85, wd, bev=0.025)            # headboard
    B(0.08, 2.84, 1.92, 2.95, 0, 0.45, wd, bev=0.02)             # footboard
    RB(0.17, 0.2, 1.83, 2.82, 0.32, 0.5, M["linen"], r=0.05, bev=0.03)
    pillow(0.4, 0.27, 1.6, 0.7, 0.49, M["linen"])
    cloth(0.12, 0.85, 1.88, 2.82, 0.56, m_fabric("duvet_navy", "#2f4a73", "#e6e1d6", pattern="check", pscale=5), amp=0.025, droop=0.18, seed=1, edges="lr")
    cloth(0.12, 0.8, 1.88, 1.05, 0.6, M["linen"], amp=0.01, droop=0.18, seed=2, edges="lr", res=16)   # folded-back sheet


@prop
def bed_double(w, h):
    M = MAT()
    up = m_fabric("upholst_grey", "#8d8d91", weave=350)
    RB(0.12, 0.08, 2.88, 2.92, 0.05, 0.35, up, r=0.08, bev=0.04)
    RB(0.06, 0.03, 2.94, 0.28, 0, 1.15, up, r=0.08, bev=0.06)
    for k in range(6):  # tufting buttons
        S(0.35 + k * 0.46, 0.155, 1.15, 0.025, 0.025, 0.012, m_fabric("upholst_dk", "#6f6f73"))
    RB(0.16, 0.3, 2.84, 2.86, 0.35, 0.56, M["linen"], r=0.06, bev=0.03)
    for u in (0.3, 1.55):
        pillow(u, 0.36, u + 1.15, 0.82, 0.55, M["linen"], th=0.15)
    pillow(1.1, 0.75, 1.9, 1.05, 0.6, m_fabric("cush_sage", "#7f9a7a"), th=0.12)
    du = m_fabric("duvet_cream", "#e9e2d3", weave=420)
    cloth(0.1, 1.0, 2.9, 2.9, 0.6, du, amp=0.02, droop=0.2, seed=4, edges="lrb")
    cloth(0.08, 2.25, 2.92, 2.7, 0.64, m_fabric("throw_mustard", "#c9952f", "#a8741d", pattern="stripe", pscale=40), amp=0.01, droop=0.22, seed=5, edges="lr", res=20)


@prop
def bed_king(w, h):
    M = MAT()
    vel = m_fabric("velvet_navy", "#24324f", weave=600, sheen=1.0, rough=0.7)
    RB(0.15, 0.2, 3.85, 3.92, 0.05, 0.38, vel, r=0.1, bev=0.05)
    for k in range(8):  # channel-tufted tall headboard
        u0 = 0.05 + k * 0.4875
        cushion(u0, 0.03, u0 + 0.48, 0.32, 0.0, 1.35, vel, puff=0.25)
    silk = m_plain("silk_champ", "#d9c6a2", rough=0.28, sheen=0.8, coat=0.2, var=0.05, vscale=6)
    RB(0.2, 0.34, 3.8, 3.86, 0.38, 0.62, M["linen"], r=0.08, bev=0.04)
    for u in (0.35, 1.35, 2.35):
        pillow(u + 0.0, 0.4, u + 0.95 + (0.35 if u > 2 else 0), 0.9, 0.61, M["linen"], th=0.17)
    for u in (0.55, 2.05):
        pillow(u, 0.82, u + 1.4, 1.2, 0.66, silk, th=0.14)
    pillow(1.6, 1.12, 2.4, 1.42, 0.7, m_fabric("cush_gold", "#b8913f", sheen=1.0), th=0.1)
    cloth(0.12, 1.35, 3.88, 3.9, 0.68, silk, amp=0.02, droop=0.26, seed=6, edges="lrb")
    cloth(0.1, 3.0, 3.9, 3.55, 0.72, vel, amp=0.012, droop=0.3, seed=7, edges="lr", res=26)


@prop
def nightstand(w, h):
    M = MAT()
    RB(0.2, 0.2, 0.8, 0.82, 0, 0.55, M["walnut"], r=0.03, bev=0.015)
    B(0.3, 0.82, 0.7, 0.85, 0.36, 0.4, M["gold"], bev=0.005)
    C(0.42, 0.42, 0.07, 0.55, 0.85, m_plain("lampbase", "#d8cfc0", rough=0.3, coat=0.4), r2=0.04, segs=24)
    lampshade(0.42, 0.42, 0.78, 0.16, 0.2, m_fabric("shade_linen", "#efe4cc", weave=500))
    B(0.6, 0.6, 0.76, 0.76, 0.55, 0.565, m_plain("phone", "#141416", rough=0.1, coat=1.0), bev=0.01, mtx=mt_rz(15, 0.68, 0.68))


@prop
def wardrobe(w, h):
    M = MAT()
    B(0.06, 0.05, 2.94, 0.78, 0, 2.0, M["oak"], bev=0.02)
    B(0.03, 0.03, 2.97, 0.8, 1.96, 2.02, M["oak"], bev=0.015)  # cornice
    for u in (0.99, 1.98):
        B(u - 0.006, 0.05, u + 0.006, 0.79, 2.02, 2.025, m_plain("groove", "#5a4330"), bev=0)
    for u in (0.85, 1.13, 1.84, 2.12):
        B(u - 0.015, 0.79, u + 0.015, 0.83, 1.2, 1.5, M["steel"], bev=0.005)
    bx = m_fabric("storage_box", "#c9b79c", weave=200)
    RB(0.2, 0.15, 0.85, 0.65, 2.02, 2.32, bx, r=0.03)
    RB(0.95, 0.2, 1.45, 0.62, 2.02, 2.25, m_plain("box_grey", "#8f9aa3", rough=0.7), r=0.02)
    cloth(1.9, 0.2, 2.75, 0.68, 2.12, m_fabric("blanket_rust", "#a85a3a", "#e6d5b8", pattern="check", pscale=12), amp=0.02, droop=0.05, seed=2, edges="", res=14)


@prop
def dresser(w, h):
    M = MAT()
    B(0.08, 0.15, 1.92, 0.82, 0, 0.85, M["walnut"], bev=0.015)
    for u in (0.5, 1.5):
        S(u, 0.84, 0.6, 0.025, 0.02, 0.025, M["gold"])
    B(0.2, 0.3, 0.55, 0.55, 0.85, 0.95, m_wood("jbox", "#9a6b45", "#6d482c"), bev=0.012)
    B(0.75, 0.3, 1.05, 0.34, 0.85, 1.12, m_plain("frame_blk", "#222", rough=0.4), bev=0.005, mtx=mt_back(20, 0.34, 0.85))
    B(0.77, 0.34, 1.03, 0.345, 0.87, 1.1, m_screen("photo", "tv", 0.3), bev=0, mtx=mt_back(20, 0.34, 0.85))
    for k, (u, v, col) in enumerate(((1.25, 0.45, "#e9b3c2"), (1.38, 0.5, "#c9e0f0"), (1.3, 0.62, "#f2d68a"))):
        C(u, v, 0.04, 0.85, 1.0 + 0.03 * k, m_plain("perf%d" % k, col, rough=0.05, coat=1.0), segs=16)
        C(u, v, 0.018, 1.0 + 0.03 * k, 1.04 + 0.03 * k, M["gold"], segs=12)
    pot_plant(1.68, 0.48, 0.09, 0.15, 10, 0.16, 5, pot="potwhite")
    for c in bpy.data.objects:
        if c.location.z == 0 and False:
            pass


# ---- living ----

def _sofa_parts(u0, v0, u1, v1, fab, seats, back_h=0.85, arm=0.3, depth_back=0.38, cush=None, mtx=None):
    """Straight sofa occupying [u0,u1]x[v0,v1], back along v0, facing +v."""
    cush = cush or fab
    RB(u0, v0, u1, v1, 0.08, 0.42, fab, r=0.05, bev=0.04, mtx=mtx)
    cushion(u0, v0, u1, v0 + depth_back, 0.3, back_h, fab, puff=0.15, mtx=mtx)
    for a0, a1 in ((u0, u0 + arm), (u1 - arm, u1)):
        cushion(a0, v0 + 0.05, a1, v1, 0.3, 0.66, fab, puff=0.2, mtx=mtx)
    sw = (u1 - u0 - 2 * arm) / seats
    for k in range(seats):
        a = u0 + arm + k * sw
        cushion(a + 0.01, v0 + depth_back, a + sw - 0.01, v1 - 0.03, 0.38, 0.55, cush, puff=0.35, mtx=mtx)
        cushion(a + 0.02, v0 + depth_back - 0.14, a + sw - 0.02, v0 + depth_back + 0.12, 0.5, back_h - 0.02, cush, puff=0.5,
                mtx=(mtx or Matrix()) @ mt_back(-12, v0 + depth_back, 0.5))


@prop
def sofa(w, h):
    fab = m_fabric("sofa_teal", "#3f6e73", weave=380)
    _sofa_parts(0.05, 0.12, 3.95, 1.9, fab, 3)
    acc = m_fabric("pillow_mustard", "#d4a03a", weave=300)
    for u, rot in ((0.62, 30), (3.38, -30)):
        pillow(u - 0.24, 0.55, u + 0.24, 0.95, 0.56, acc, th=0.16, mtx=mt_rz(rot, u, 0.75))
    cloth(2.4, 0.5, 3.3, 1.4, 0.58, m_fabric("throw_knit", "#e8e0d0", weave=120), amp=0.03, droop=0.1, seed=3, edges="b", res=14)


@prop
def sofa_corner(w, h):
    fab = m_fabric("sofa_grey", "#7b7e84", weave=380)
    cushc = m_fabric("sofa_grey_c", "#878a90", weave=380)
    # long part along the top
    RB(0.08, 0.1, 4.95, 1.25, 0.08, 0.42, fab, r=0.05, bev=0.04)
    RB(0.08, 0.1, 1.25, 2.95, 0.08, 0.42, fab, r=0.05, bev=0.04)
    cushion(0.08, 0.1, 4.95, 0.48, 0.3, 0.85, fab, puff=0.12)
    cushion(0.08, 0.1, 0.46, 2.95, 0.3, 0.85, fab, puff=0.12)
    cushion(4.65, 0.15, 4.95, 1.25, 0.3, 0.66, fab, puff=0.2)
    cushion(0.08, 2.65, 1.25, 2.95, 0.3, 0.66, fab, puff=0.2)
    for a in (1.25, 2.38, 3.51):
        cushion(a + 0.01, 0.48, a + 1.12, 1.22, 0.38, 0.55, cushc, puff=0.35)
        cushion(a + 0.02, 0.36, a + 1.1, 0.6, 0.5, 0.83, cushc, puff=0.5, mtx=mt_back(-12, 0.48, 0.5))
    cushion(0.46, 0.48, 1.25, 1.25, 0.38, 0.55, cushc, puff=0.35)
    for b in (1.25, 1.95):
        cushion(0.48, b + 0.01, 1.22, b + 0.69, 0.38, 0.55, cushc, puff=0.35)
        cushion(0.36, b + 0.02, 0.6, b + 0.68, 0.5, 0.83, cushc, puff=0.5, mtx=mt_side(-12, 0.48, 0.5))
    for (u, v, c, r) in ((0.75, 0.75, "#c06a4a", 45), (4.25, 0.75, "#e3d9c6", -20), (0.75, 2.3, "#2f4a5c", 10)):
        pillow(u - 0.24, v - 0.2, u + 0.24, v + 0.2, 0.56, m_fabric("cp" + c, c), th=0.16, mtx=mt_rz(r, u, v))


@prop
def armchair(w, h):
    fab = m_fabric("armchair_rust", "#a65a3c", weave=380)
    _sofa_parts(0.2, 0.15, 1.8, 1.85, fab, 1, back_h=0.95, arm=0.28)
    pillow(0.75, 0.55, 1.25, 0.95, 0.57, m_fabric("cush_cream", "#e9e1d0"), th=0.15, mtx=mt_rz(8, 1.0, 0.75))


@prop
def beanbag(w, h):
    lea = m_fabric("beanbag_char", "#3b3f48", weave=300, sheen=0.7, rough=0.8)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        r = 1 + 0.06 * mnoise.noise(Vector((x * 3, y * 3, z * 3)))
        zz = z * 0.55 + (0.25 * (y + 0.2) if z > 0 else 0)   # back (top of image) higher
        if z > 0.3 and abs(x) < 0.6 and -0.5 < y < 0.4:
            zz -= 0.15 * (1 - abs(x) / 0.6)                     # seat dent
        v.co = Vector((0.5 + x * 0.47 * r, -0.5 + y * 0.47 * r, 0.2 + max(-0.2, zz * 0.32)))
    _obj("beanbag", bm, lea, smooth=True, sub=1)
    S(0.5, 0.5, 0.36, 0.12, 0.12, 0.02, m_emit("bb_logo", "#d2262b", 0.6))


@prop
def coffee_table(w, h):
    M = MAT()
    RB(0.12, 0.18, 1.88, 0.82, 0.36, 0.42, M["oak"], r=0.1, bev=0.015)
    for u, v in ((0.22, 0.28), (1.78, 0.28), (0.22, 0.72), (1.78, 0.72)):
        C(u, v, 0.025, 0, 0.36, M["black"], segs=12)
    B(0.35, 0.33, 0.75, 0.62, 0.42, 0.428, m_screen("magazine", "tv", 0.15), bev=0.002, mtx=mt_rz(-12, 0.55, 0.47))
    C(1.35, 0.45, 0.05, 0.42, 0.51, M["ceramic"], segs=24, caps=True)
    C(1.35, 0.45, 0.042, 0.505, 0.512, m_plain("coffee", "#3a2214", rough=0.1), segs=24)
    T(1.41, 0.45, 0.47, 0.025, 0.008, M["ceramic"], segs=16, rsegs=6)
    C(1.6, 0.6, 0.06, 0.42, 0.44, m_plain("remote", "#222", rough=0.3), segs=4)


def tv(cu, v_hinge, z0, width, height, tilt, kind="tv", bezel=0.02):
    M = MAT()
    mt = mt_back(tilt, v_hinge, z0)
    B(cu - width / 2, v_hinge - 0.05, cu + width / 2, v_hinge, z0, z0 + height, M["black"], bev=0.008, mtx=mt)
    B(cu - width / 2 + bezel, v_hinge, cu + width / 2 - bezel, v_hinge + 0.004, z0 + bezel, z0 + height - bezel, m_screen("scr_" + kind, kind), bev=0, mtx=mt)


@prop
def tv_stand(w, h):
    M = MAT()
    B(0.1, 0.38, 3.9, 0.95, 0, 0.48, M["white"], bev=0.015)
    B(0.12, 0.4, 3.88, 0.93, 0.48, 0.5, M["oak"], bev=0.01)
    B(1.5, 0.7, 2.5, 0.82, 0.5, 0.52, M["black"], bev=0.005)  # TV foot
    tv(2.0, 0.78, 0.52, 1.7, 0.9, 58)
    B(0.35, 0.55, 0.75, 0.85, 0.5, 0.58, m_plain("console", "#f2f2f2", rough=0.3), bev=0.02)
    S(0.95, 0.7, 0.53, 0.08, 0.05, 0.025, m_plain("pad", "#1d1d20", rough=0.4))
    pot_plant(3.55, 0.65, 0.1, 0.16, 12, 0.18, 2, pot="potwhite")


@prop
def tv_big(w, h):
    M = MAT()
    B(0.1, 0.3, 5.9, 0.95, 0, 0.45, M["walnut"], bev=0.015)
    for k in range(4):
        B(0.1 + k * 1.45 + 0.02, 0.95, 0.1 + (k + 1) * 1.45 - 0.02, 0.952, 0.05, 0.42, M["dark"], bev=0)
    B(2.6, 0.62, 3.4, 0.72, 0.45, 0.47, M["black"], bev=0.005)
    tv(3.0, 0.68, 0.48, 3.0, 1.1, 58, kind="game")
    B(1.9, 0.78, 4.1, 0.9, 0.45, 0.53, m_fabric("soundbar", "#2a2b2e", weave=600), bev=0.02)
    B(0.4, 0.5, 0.9, 0.85, 0.45, 0.55, M["black"], bev=0.02)
    B(0.45, 0.5, 0.85, 0.85, 0.551, 0.553, m_emit("console_led", "#3aa0ff", 2.0), bev=0)
    pot_plant(5.45, 0.62, 0.12, 0.2, 12, 0.22, 7, pot="potwhite")
    S(1.2, 0.72, 0.48, 0.08, 0.05, 0.025, m_plain("pad", "#1d1d20", rough=0.4))


@prop
def bookshelf(w, h):
    M = MAT()
    wd = M["walnut"]
    H_ = 0.95
    B(0.05, 0.08, 2.95, 0.14, 0, H_, wd, bev=0.01)                  # back
    for u in (0.05, 0.98, 1.98, 2.92):
        B(u, 0.08, u + 0.04 if u < 2.9 else 2.95, 0.85, 0, H_, wd, bev=0.01)   # uprights
    B(0.05, 0.1, 2.95, 0.85, 0, 0.05, wd, bev=0.005)
    books = m_random("books", ["#8e2b25", "#24476b", "#2e5c3a", "#c9a227", "#5b3a6e", "#d9d2c0", "#1f1f22", "#b75a2b", "#3f7f8c", "#7a1f3d"], rough=0.55)
    pages = m_plain("pages", "#efe6d0", rough=0.8)
    rng = random.Random(4)
    for c0, c1 in ((0.09, 0.98), (1.02, 1.98), (2.02, 2.92)):
        u = c0 + 0.01
        lean = rng.random() < 0.5
        while u < c1 - 0.04:
            t = rng.uniform(0.035, 0.07)
            if u + t > c1 - 0.01:
                break
            d = rng.uniform(0.5, 0.68)
            hh = rng.uniform(0.6, 0.85)
            if rng.random() < 0.12 and c1 - u > 0.3:   # a lying stack
                for s in range(rng.randint(2, 4)):
                    B(u, 0.2, u + 0.24, 0.2 + rng.uniform(0.45, 0.6), 0.05 + s * 0.04, 0.09 + s * 0.04, books, bev=0.004)
                u += 0.27
                continue
            B(u, 0.16, u + t, 0.16 + d, 0.05, 0.05 + hh, books, bev=0.004)
            B(u + 0.006, 0.17, u + t - 0.006, 0.16 + d - 0.012, 0.06, 0.05 + hh + 0.003, pages, bev=0)
            u += t + rng.uniform(0.0, 0.006)
    pot_plant(2.75, 0.45, 0.08, 0.86, 10, 0.18, 3, pot="potwhite") if False else None


@prop
def lamp(w, h):
    M = MAT()
    C(0.5, 0.5, 0.17, 0, 0.03, M["black"], segs=32, bev=0.01)
    C(0.5, 0.5, 0.015, 0.03, 1.45, M["gold"], segs=12)
    lampshade(0.5, 0.5, 1.4, 0.27, 0.32, m_fabric("shade_cream", "#f1e6cf", weave=500), glow="#ffd49a")


@prop
def plant(w, h):
    pot_plant(0.5, 0.5, 0.17, 0.32, 18, 0.33, 11)


@prop
def plant_big(w, h):
    pot_plant(0.5, 0.5, 0.2, 0.45, 0, 0.72, 21, pot="potwhite", big=True)


def _rug_base(u0, v0, u1, v1, field, border, bw, inner=None, fringe=True):
    B(u0, v0, u1, v1, 0, 0.012, border, bev=0.004)
    B(u0 + bw, v0 + bw, u1 - bw, v1 - bw, 0, 0.016, field, bev=0.002)
    if inner:
        bw2 = bw * 0.5
        ringP(rrect(u0 + bw + bw2, v0 + bw + bw2, u1 - bw - bw2, v1 - bw - bw2, 0.001, 1), rrect(u0 + bw + bw2 + 0.03, v0 + bw + bw2 + 0.03, u1 - bw - bw2 - 0.03, v1 - bw - bw2 - 0.03, 0.001, 1), 0, 0.018, inner, smooth=False)
    if fringe:
        fr = m_fabric("fringe", "#ece3cf", "#c9bfa9", pattern="stripe", pscale=60, weave=100)
        for uu in ((u0 - 0.06, u0), (u1, u1 + 0.06)):
            B(uu[0], v0 + 0.02, uu[1], v1 - 0.02, 0, 0.006, fr, bev=0)


@prop
def rug_small(w, h):
    field = m_fabric("rug_persian", "#9b2f2a", "#6e1f1c", pattern="check", pscale=14, weave=200)
    _rug_base(0.12, 0.08, 2.88, 1.92, field, m_fabric("rug_navy", "#23324d", weave=200), 0.2, inner=m_fabric("rug_cream", "#e6d8b8", weave=200))
    P(ell(1.5, 1.0, 0.55, 0.38, 6), 0, 0.02, m_fabric("rug_navy", "#23324d", weave=200), bev=0)
    P(ell(1.5, 1.0, 0.3, 0.2, 6), 0, 0.022, m_fabric("rug_cream", "#e6d8b8", weave=200), bev=0)
    P(ell(1.5, 1.0, 0.12, 0.08, 6), 0, 0.024, m_fabric("rug_gold", "#c9952f", weave=200), bev=0)


@prop
def rug_big(w, h):
    field = m_fabric("rug_modern", "#cfc4b0", "#b3a68d", pattern="stripe", pscale=4, weave=200)
    _rug_base(0.1, 0.1, 4.9, 3.9, field, m_fabric("rug_charcoal", "#3b3d42", weave=200), 0.18, inner=m_fabric("rug_terra", "#b4643f", weave=200), fringe=False)
    for k in range(3):  # bold geometric bands
        u = 1.2 + k * 1.3
        P([(u, 0.6), (u + 0.5, 2.0), (u, 3.4), (u - 0.5, 2.0)], 0, 0.02, m_fabric("rug_terra", "#b4643f", weave=200), bev=0)
        P([(u, 1.2), (u + 0.25, 2.0), (u, 2.8), (u - 0.25, 2.0)], 0, 0.022, m_fabric("rug_charcoal", "#3b3d42", weave=200), bev=0)


@prop
def rug_round(w, h):
    for k, (r, c) in enumerate(((1.45, "#2f5f6b"), (1.25, "#e6dcc6"), (1.15, "#2f5f6b"), (0.8, "#d29a3a"), (0.7, "#e6dcc6"), (0.35, "#2f5f6b"))):
        C(1.5, 1.5, r, 0, 0.012 + k * 0.002, m_fabric("rr%d" % k, c, weave=220), segs=64)


@prop
def piano(w, h):
    M = MAT()
    out = [(0.78, 1.52), (0.78, 0.3)] + ell(1.55, 0.55, 0.77, 0.32, 10, 180, 270)[1:] + ell(1.85, 0.45, 0.45, 0.4, 10, 270, 360)[1:] + \
        [(2.3, 0.6), (2.28, 1.1), (2.22, 1.52)]
    P(out, 0.3, 0.98, M["blackgloss"], bev=0.02)
    inner = [(u + (1.5 - u) * 0.14, v + (0.9 - v) * 0.14) for u, v in out]
    P(inner, 0.97, 0.99, m_plain("strings", "#9c7430", rough=0.35, metal=0.7), bev=0)
    for k in range(18):
        B(0.95 + k * 0.07, 0.35, 0.955 + k * 0.07, 1.45, 0.99, 0.995, M["chrome"], bev=0)
    B(0.75, 1.48, 2.25, 1.72, 0.65, 0.78, M["blackgloss"], bev=0.01)
    keys = m_tiles("keys", "#f4f2ec", "#202022", size=0.0225, rect=1.0, rough=0.3, var=0.0, gw=0.06)
    B(0.83, 1.52, 2.17, 1.68, 0.78, 0.8, keys, bev=0)
    for k in range(36):
        if k % 7 in (2, 6):
            continue
        u = 0.85 + k * 0.0375 + 0.025
        B(u, 1.52, u + 0.015, 1.6, 0.8, 0.82, M["black"], bev=0.002)
    B(1.2, 1.4, 1.8, 1.47, 0.98, 1.2, M["blackgloss"], bev=0.004, mtx=mt_back(18, 1.47, 0.98))
    B(1.25, 1.47, 1.75, 1.475, 1.0, 1.18, m_plain("sheet", "#f4f0e6", rough=0.8), bev=0, mtx=mt_back(18, 1.47, 0.98))
    RB(1.1, 1.78, 1.9, 1.98, 0.3, 0.48, m_plain("bench_leather", "#1b1b1d", rough=0.35, coat=0.4), r=0.04, bev=0.03)


@prop
def aquarium(w, h):
    M = MAT()
    B(0.05, 0.1, 2.95, 0.9, 0, 0.75, M["black"], bev=0.015)
    B(0.12, 0.17, 2.88, 0.83, 0.75, 0.82, m_plain("gravel", "#c9b48a", var=0.3, vscale=90, rough=0.9, bumpk=0.5, bscale=120), bev=0)
    rng = random.Random(5)
    for k in range(9):
        u = rng.uniform(0.25, 2.75)
        leaves(u, rng.uniform(0.3, 0.7), 0.82, 7, 0, 0, rng.uniform(0.18, 0.3), 0.05, m_leaf("aqplant", "#4fb34a", "#1f6a2b"), seed=k, lift=(2.0, 3.5), droop=0.4)
    for k in range(4):
        blob(rng.uniform(0.3, 2.7), rng.uniform(0.3, 0.7), 0.85, rng.uniform(0.06, 0.1), m_plain("rock", "#6e6a64", rough=0.8, var=0.2, vscale=20), seed=k, squash=0.6, subd=2)
    for k in range(9):
        u, v, a = rng.uniform(0.3, 2.7), rng.uniform(0.3, 0.7), rng.uniform(0, 360)
        col = rng.choice(["#ff7a1a", "#ffd21a", "#ff3b3b", "#3fb8ff"])
        fm = m_plain("fish" + col, col, rough=0.3, emit=0.4)
        S(u, v, 1.0 + rng.uniform(-0.1, 0.1), 0.045, 0.018, 0.02, fm, mtx=mt_rz(a, u, v))
        P([(u - 0.04, v), (u - 0.075, v - 0.025), (u - 0.075, v + 0.025)], 1.0, 1.006, fm, bev=0, mtx=mt_rz(a, u, v))
    B(0.12, 0.17, 2.88, 0.83, 1.15, 1.16, m_water("aqwater", "#a8e6f5", deep="#2f9fc4", depth_w=0.22), bev=0)
    fr = M["black"]
    ringP(rrect(0.08, 0.13, 2.92, 0.87, 0.001, 1), rrect(0.12, 0.17, 2.88, 0.83, 0.001, 1), 0.75, 1.2, fr, smooth=False)
    B(0.12, 0.17, 2.88, 0.24, 1.17, 1.2, m_emit("aqlight", "#cfefff", 3.0), bev=0)


@prop
def arcade(w, h):
    M = MAT()
    side = m_plain("arc_purple", "#4b1f7a", rough=0.35, coat=0.5)
    for u0 in (0.12, 0.83):
        P([(u0, 0.08), (u0, 0.9), (u0 + 0.05, 0.9), (u0 + 0.05, 0.08)], 0, 1.75, side, bev=0.01)
        B(u0 + 0.005, 0.1, u0 + 0.045, 0.88, 1.75, 1.76, m_emit("arc_trim", "#ff3fa0", 2.5), bev=0)
    B(0.17, 0.08, 0.83, 0.42, 0, 1.75, M["black"], bev=0.01)
    B(0.17, 0.08, 0.83, 0.42, 1.75, 1.77, m_screen("marquee", "arcade", 1.2), bev=0)
    tv(0.5, 0.62, 1.0, 0.6, 0.55, 40, kind="arcade", bezel=0.03)
    B(0.17, 0.62, 0.83, 0.9, 0.9, 0.98, M["black"], bev=0.01)
    S(0.32, 0.74, 1.05, 0.035, 0.035, 0.035, m_plain("ball_red", "#e02020", rough=0.2, coat=1))
    C(0.32, 0.74, 0.008, 0.98, 1.04, M["chrome"], segs=8)
    for k, c in enumerate(("#ff3b3b", "#ffd21a", "#3fb8ff", "#3fe07a")):
        C(0.5 + (k % 2) * 0.08 + (k // 2) * 0.04, 0.7 + (k // 2) * 0.08, 0.022, 0.98, 1.0, m_plain("btn" + c, c, rough=0.2, emit=0.6), segs=16)


@prop
def bar_counter(w, h):
    M = MAT()
    B(0.05, 0.06, 3.95, 0.5, 0, 1.0, M["dark"], bev=0.01)
    B(0.02, 0.03, 3.98, 0.58, 1.0, 1.05, m_marble("bar_top", "#e8e4dc", "#9c958a", tile=0), bev=0.012)
    B(0.05, 0.56, 3.95, 0.6, 0.05, 0.08, M["gold"], bev=0.005)  # foot rail
    rng = random.Random(9)
    bott = m_random("bottles", ["#2e6b2e", "#7a3b12", "#d9d2b0", "#1f3c6b", "#8a1c1c", "#c9a227"], rough=0.06)
    for k in range(9):
        u, v = rng.uniform(0.2, 1.4) if k < 6 else rng.uniform(3.0, 3.8), rng.uniform(0.12, 0.3)
        r = rng.uniform(0.035, 0.05)
        C(u, v, r, 1.05, 1.3, bott, segs=16)
        C(u, v, r, 1.3, 1.36, bott, r2=0.013, segs=16)
        C(u, v, 0.014, 1.36, 1.42, M["gold"] if k % 2 else M["black"], segs=10)
    for u in (1.8, 2.05, 2.3):
        C(u, 0.25, 0.035, 1.05, 1.15, M["glass"], segs=16, caps=False)
    C(2.7, 0.3, 0.12, 1.05, 1.07, M["chrome"], segs=24)   # tray
    for u in (0.6, 2.0, 3.4):
        C(u, 0.8, 0.02, 0, 0.75, M["chrome"], segs=10)
        C(u, 0.8, 0.13, 0.02, 0.04, M["chrome"], segs=24)
        cushion(u - 0.18, 0.62, u + 0.18, 0.98, 0.72, 0.8, m_plain("stool_leather", "#7a3b1f", rough=0.4, coat=0.3), puff=0.3)


@prop
def telescope(w, h):
    M = MAT()
    for a in (90, 210, 330):
        ex, ey = 0.5 + 0.36 * math.cos(math.radians(a)), 0.55 + 0.36 * math.sin(math.radians(a))
        bm = bmesh.new()
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.025, radius2=0.02, depth=1.0)
        top, bot = X(0.5, 0.55, 1.05), X(ex, ey, 0)
        d = top - bot
        q = d.to_track_quat("Z", "Y")
        bmesh.ops.transform(bm, matrix=Matrix.Translation((top + bot) / 2) @ q.to_matrix().to_4x4() @ Matrix.Scale(d.length, 4, Vector((0, 0, 1))), verts=bm.verts)
        _obj("leg", bm, M["black"], smooth=True)
    tube = m_plain("scope_white", "#f1f1ee", rough=0.25, coat=0.6)
    bm = bmesh.new()
    r = bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.09, radius2=0.1, depth=1.1)
    mt = Matrix.Translation(X(0.5, 0.55, 1.15)) @ Matrix.Rotation(math.radians(-45), 4, "Z") @ Matrix.Rotation(math.radians(-62), 4, "X")
    bmesh.ops.transform(bm, matrix=mt, verts=bm.verts)
    _obj("tube", bm, tube, smooth=True)
    end = mt @ Vector((0, 0, 0.55))
    C(end.x, -end.y, 0.085, end.z - 0.01, end.z + 0.02, m_plain("lens", "#10233a", rough=0.02, coat=1.0, metal=0.3), segs=24)
    S(0.5, 0.55, 1.12, 0.06, 0.06, 0.06, M["black"])


# ---- gaming / work ----

@cached
def m_keys(name, cap="#1d1e22", gap="#0a0a0c", rgb=False, legend="#e8e8e8"):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    br = nd(nt, "ShaderNodeTexBrick", props={"offset": 0.25}, Vector=co, Color1=lin(cap), Color2=lin(cap), Mortar=lin(gap),
            Scale=1.0, Mortar_Size=0.0025, Brick_Width=0.019, Row_Height=0.019, Bias=0)
    setsock(nt, b.inputs["Base Color"], br.outputs["Color"])
    b.inputs["Roughness"].default_value = 0.45
    if rgb:
        sep = nd(nt, "ShaderNodeSeparateXYZ", Vector=coords(nt, (2.2, 2.2, 2.2)))
        col = ramp(nt, math_(nt, "FRACT", sep.outputs["X"]), [(0.0, (1, 0, 0.3)), (0.25, (1, 0.6, 0)), (0.45, (0.1, 1, 0.3)), (0.65, (0, 0.6, 1)), (0.85, (0.6, 0, 1)), (1.0, (1, 0, 0.3))])
        setsock(nt, b.inputs["Emission Color"], col)
        setsock(nt, b.inputs["Emission Strength"], math_(nt, "MULTIPLY", math_(nt, "SUBTRACT", 1.0, br.outputs["Fac"]), 1.6))
    bump(nt, b, br.outputs["Fac"], 0.3, 0.004)
    return m


def monitor(cu, v_base, width, height, z, kind, tilt=48, yaw=0.0, stand=True, curve=0.0):
    M = MAT()
    rz = mt_rz(yaw, cu, v_base)
    mt = rz @ mt_back(tilt, v_base, z + 0.12)
    if stand:
        RB(cu - 0.12, v_base - 0.14, cu + 0.12, v_base + 0.04, z, z + 0.015, M["black"], r=0.03, mtx=rz)
        B(cu - 0.025, v_base - 0.1, cu + 0.025, v_base - 0.06, z, z + 0.3, M["black"], bev=0.005, mtx=rz)
    if curve:
        n = 5
        for k in range(n):
            a0 = -0.5 + k / n
            seg_w = width / n
            ang = (a0 + 0.5 / n) * curve
            u0 = cu - width / 2 + k * seg_w
            m2 = mt_rz(ang, u0 + seg_w / 2, v_base) @ mt
            vb = v_base + abs(ang) / 90.0 * 0.12
            mm = mt_rz(ang, u0 + seg_w / 2, v_base) @ Matrix.Translation((0, -(vb - v_base), 0)) @ mt
            B(u0 - 0.002, v_base - 0.03, u0 + seg_w + 0.002, v_base, z + 0.12, z + 0.12 + height, M["black"], bev=0.004, mtx=mm)
            B(u0 + (0.012 if k == 0 else 0), v_base, u0 + seg_w - (0.012 if k == n - 1 else 0), v_base + 0.003, z + 0.13, z + 0.11 + height, m_screen("scr_" + kind, kind), bev=0, mtx=mm)
        return
    B(cu - width / 2, v_base - 0.035, cu + width / 2, v_base, z + 0.12, z + 0.12 + height, M["black"], bev=0.006, mtx=mt)
    B(cu - width / 2 + 0.012, v_base, cu + width / 2 - 0.012, v_base + 0.003, z + 0.13, z + 0.11 + height, m_screen("scr_" + kind, kind), bev=0, mtx=mt)


def keyboard(cu, cv, z, width, cap="#1d1e22", rgb=False, case="#151517"):
    B(cu - width / 2, cv - 0.075, cu + width / 2, cv + 0.075, z, z + 0.022, m_plain("kbcase" + case, case, rough=0.4), bev=0.006)
    B(cu - width / 2 + 0.012, cv - 0.065, cu + width / 2 - 0.012, cv + 0.065, z + 0.02, z + 0.03, m_keys("keys_%s_%d" % (cap, rgb), cap, rgb=rgb), bev=0.002)


def mouse(cu, cv, z, col="#1b1b1d", rgb=False):
    S(cu, cv, z + 0.012, 0.032, 0.055, 0.02, m_plain("mouse" + col, col, rough=0.3, coat=0.4))
    if rgb:
        S(cu, cv + 0.04, z + 0.014, 0.02, 0.012, 0.012, m_rgb("rgbstrip"))


def chair(cu, cv, kind="gaming", main="#1c1c1f", acc="#c0262b"):
    """Desk chair facing -v (towards a desk above it)."""
    M = MAT()
    if kind == "folding":
        fr = m_plain("fold_frame", "#7d8288", rough=0.35, metal=0.8)
        for u in (cu - 0.21, cu + 0.21):
            B(u - 0.012, cv - 0.25, u + 0.012, cv + 0.28, 0.0, 0.45, fr, bev=0.005, mtx=mt_back(-8, cv, 0))
        B(cu - 0.22, cv - 0.22, cu + 0.22, cv + 0.18, 0.43, 0.46, m_plain("fold_seat", "#5d6168", rough=0.5), bev=0.01)
        B(cu - 0.22, cv + 0.2, cu + 0.22, cv + 0.25, 0.55, 0.85, m_plain("fold_seat", "#5d6168", rough=0.5), bev=0.01, mtx=mt_back(-14, cv + 0.22, 0.55))
        return
    big = kind == "premium"
    mm = m_plain("chair_" + main, main, rough=0.4, coat=0.2, bumpk=0.05, bscale=200) if kind != "mesh" else m_fabric("chair_mesh", main, weave=900)
    ac = m_plain("chair_acc" + acc, acc, rough=0.4, coat=0.2)
    for k in range(5):  # star base
        a = math.radians(90 + k * 72)
        ex, ey = cu + 0.32 * math.cos(a), cv + 0.32 * math.sin(a)
        B(cu - 0.02, cv - 0.02, cu + 0.32, cv + 0.02, 0.06, 0.1, M["black"], bev=0.01, mtx=mt_rz(-math.degrees(a), cu, cv))
        S(ex, ey, 0.04, 0.03, 0.03, 0.03, M["black"])
    sw = 0.27 if not big else 0.29
    cushion(cu - sw, cv - 0.25, cu + sw, cv + 0.2, 0.42, 0.52, mm, puff=0.4)
    if kind == "gaming":
        cushion(cu - sw * 0.55, cv - 0.22, cu + sw * 0.55, cv + 0.18, 0.5, 0.54, ac, puff=0.3)
    back = mt_back(-22, cv + 0.25, 0.5)
    cushion(cu - sw, cv + 0.18, cu + sw, cv + 0.3, 0.5, 1.3 if kind != "basic" else 1.0, mm, puff=0.3, mtx=back)
    if kind in ("gaming", "premium"):
        for s in (-1, 1):  # bolsters / wings
            cushion(cu + s * sw - 0.06, cv + 0.14, cu + s * sw + 0.06, cv + 0.3, 0.55, 1.15, ac if kind == "gaming" else mm, puff=0.3, mtx=back)
        pillow(cu - 0.12, cv + 0.12, cu + 0.12, cv + 0.2, 1.05, ac if kind == "premium" else mm, th=0.1, mtx=back)
    for s in (-1, 1):
        B(cu + s * (sw + 0.03) - 0.035, cv - 0.15, cu + s * (sw + 0.03) + 0.035, cv + 0.15, 0.62, 0.66, M["black"], bev=0.012)


def desk(u0, u1, v0, v1, z, top, legs, edge=None):
    M = MAT()
    B(u0, v0, u1, v1, z - 0.03, z, top, bev=0.008)
    for u in (u0 + 0.05, u1 - 0.09):
        B(u, v0 + 0.05, u + 0.04, v1 - 0.05, 0, z - 0.03, legs, bev=0.005)
    if edge:
        B(u0, v1 - 0.004, u1, v1 + 0.004, z - 0.025, z - 0.006, edge, bev=0)


@prop
def desk_pc_0(w, h):
    M = MAT()
    desk(0.8, 2.2, 0.15, 0.85, 0.72, m_plain("laminate", "#d9cbb0", rough=0.55, var=0.05), m_plain("tablelegs", "#8a8d92", metal=0.6, rough=0.4))
    # laptop: base + lid leaning back
    B(1.32, 0.48, 1.68, 0.72, 0.72, 0.735, m_plain("alu_laptop", "#a7abb0", rough=0.35, metal=0.8), bev=0.006)
    B(1.35, 0.55, 1.65, 0.66, 0.735, 0.738, m_keys("laptopkeys", "#2a2b2e"), bev=0)
    mt = mt_back(55, 0.48, 0.735)
    B(1.32, 0.47, 1.68, 0.48, 0.735, 0.97, m_plain("alu_laptop", "#a7abb0", rough=0.35, metal=0.8), bev=0.004, mtx=mt)
    B(1.34, 0.48, 1.66, 0.483, 0.745, 0.96, m_screen("scr_laptop", "laptop", 1.6), bev=0, mtx=mt)
    C(1.95, 0.4, 0.033, 0.72, 0.84, m_plain("can_green", "#3db34a", rough=0.25, metal=0.8), segs=16)
    C(1.95, 0.4, 0.025, 0.84, 0.845, M["steel"], segs=16)
    C(1.05, 0.55, 0.06, 0.72, 0.8, m_plain("noodle", "#f0e6d0", rough=0.6), r2=0.075, segs=20)
    C(1.05, 0.55, 0.068, 0.8, 0.805, m_plain("noodle_lid", "#d13a2a", rough=0.5), segs=20)
    B(1.75, 0.6, 2.05, 0.8, 0.72, 0.723, m_plain("paper", "#f4f2ee", rough=0.9), bev=0, mtx=mt_rz(12, 1.9, 0.7))
    chair(1.5, 1.4, "folding")


@prop
def desk_pc_1(w, h):
    M = MAT()
    red = m_emit("red_trim", "#e0262b", 1.2)
    desk(0.6, 2.4, 0.12, 0.88, 0.74, m_plain("desk_black", "#1f2023", rough=0.35, var=0.05, vscale=30), M["black"], edge=red)
    monitor(1.5, 0.36, 0.66, 0.38, 0.74, "game")
    B(0.85, 0.52, 2.25, 0.84, 0.74, 0.745, m_fabric("mousepad", "#141416", weave=900), bev=0.004)
    keyboard(1.4, 0.66, 0.745, 0.44)
    mouse(1.95, 0.68, 0.745)
    T(0.85, 0.35, 0.79, 0.07, 0.022, M["black"], sy=1.2)   # headphones
    C(2.2, 0.32, 0.04, 0.74, 0.88, m_plain("cup_red", "#c42a2a", rough=0.4), segs=16)
    chair(1.5, 1.42, "gaming", "#1c1c1f", "#c0262b")


@prop
def desk_pc_2(w, h):
    M = MAT()
    desk(0.35, 2.65, 0.1, 0.9, 0.75, m_wood("desk_walnut", "#6b4a33", "#4a3222", coat=0.4), M["black"], edge=m_emit("purple_led", "#9b4dff", 3.0))
    B(0.35, 0.1, 2.65, 0.13, 0.7, 0.72, m_emit("purple_led", "#9b4dff", 3.0), bev=0)
    monitor(1.12, 0.38, 0.62, 0.36, 0.75, "game", yaw=-14)
    monitor(1.88, 0.38, 0.62, 0.36, 0.75, "desktop", yaw=14)
    B(0.8, 0.52, 2.2, 0.86, 0.75, 0.754, m_fabric("mousepad_xl", "#1a1530", weave=900), bev=0.004)
    B(0.8, 0.52, 2.2, 0.525, 0.754, 0.756, m_rgb("rgbstrip", 3.0, 2.0), bev=0)
    keyboard(1.4, 0.68, 0.754, 0.44, cap="#1b1b1e", rgb=True)
    mouse(1.95, 0.7, 0.754, rgb=True)
    # mic arm from the back-left corner reaching in, mic + pop filter
    C(0.55, 0.25, 0.03, 0.75, 0.8, M["black"], segs=12)
    B(0.55, 0.23, 0.95, 0.27, 1.0, 1.03, M["black"], bev=0.008, mtx=mt_rz(-35, 0.55, 0.25))
    C(0.88, 0.48, 0.035, 0.95, 1.05, M["black"], segs=16, r2=0.035)
    S(0.88, 0.48, 1.06, 0.04, 0.04, 0.05, m_fabric("mic_mesh", "#2a2a2e", weave=800))
    C(2.4, 0.35, 0.05, 0.75, 0.77, M["black"], segs=16)
    C(2.4, 0.35, 0.01, 0.77, 1.0, M["black"], segs=8)
    T(2.4, 0.35, 1.0, 0.08, 0.025, m_plain("headset_white", "#e8e8ea", rough=0.35), sy=1.25)
    pot_plant(2.45, 0.7, 0.07, 0.12, 9, 0.13, 4, pot="potwhite")
    chair(1.5, 1.42, "gaming", "#ecebed", "#7a3cff")


@prop
def desk_pc_3(w, h):
    M = MAT()
    top = m_plain("desk_carbon", "#16171a", rough=0.25, coat=0.6, var=0.08, vscale=200)
    desk(0.08, 2.92, 0.08, 0.95, 0.76, top, M["black"], edge=m_rgb("rgbstrip_e", 4.0, 1.5))
    B(0.08, 0.06, 2.92, 0.09, 0.7, 0.73, m_rgb("rgbstrip_b", 4.0, 1.5), bev=0)
    monitor(1.5, 0.36, 1.15, 0.38, 0.76, "game", curve=24)
    monitor(0.62, 0.38, 0.55, 0.32, 0.76, "code", yaw=-28)
    monitor(2.38, 0.38, 0.55, 0.32, 0.76, "desktop", yaw=28)
    B(0.75, 0.55, 2.25, 0.9, 0.76, 0.764, m_fabric("mousepad_xl3", "#0f0f12", weave=900), bev=0.004)
    B(0.75, 0.55, 2.25, 0.555, 0.764, 0.766, m_rgb("rgbstrip", 3.0, 2.0), bev=0)
    B(0.75, 0.895, 2.25, 0.9, 0.764, 0.766, m_rgb("rgbstrip", 3.0, 2.0), bev=0)
    keyboard(1.38, 0.72, 0.764, 0.42, cap="#e9e9ec", rgb=True, case="#e9e9ec")
    mouse(1.92, 0.73, 0.764, "#f0f0f2", rgb=True)
    # tower PC with a glass top showing RGB fans
    B(2.45, 0.42, 2.85, 0.92, 0.76, 1.25, M["black"], bev=0.01)
    B(2.48, 0.45, 2.82, 0.89, 1.25, 1.252, m_glass("pcglass", "#202530", refl=0.4), bev=0)
    for v in (0.55, 0.78):
        T(2.65, v, 1.2, 0.08, 0.012, m_rgb("rgbstrip_f", 6.0, 3.0), segs=24, rsegs=6)
        C(2.65, v, 0.07, 1.18, 1.2, m_plain("fan", "#202124", rough=0.4), segs=16)
    B(0.18, 0.62, 0.32, 0.78, 0.76, 1.0, M["black"], bev=0.01)   # speakers
    C(0.25, 0.7, 0.05, 1.0, 1.005, m_fabric("spk", "#2c2c30"), segs=20)
    B(0.95, 0.42, 1.12, 0.52, 0.764, 0.785, m_keys("streamdeck", "#30343a", rgb=True), bev=0.004)
    C(0.48, 0.75, 0.05, 0.76, 0.86, m_plain("can_mon", "#151515", rough=0.25, metal=0.8), segs=16)
    C(0.48, 0.75, 0.038, 0.86, 0.865, m_emit("can_lime", "#7dff3a", 1.5), segs=16)
    chair(1.5, 1.45, "premium", "#18181b", "#ff7a1a")


@prop
def studio_rig(w, h):
    M = MAT()
    green = m_fabric("greenscreen", "#2fb84a", weave=500, sheen=0.2, rough=0.95)
    # green screen pulled down from its roll and leaning back (reads as a big green sheet from above)
    B(0.2, 0.9, 2.8, 0.93, 0.0, 1.05, green, bev=0, mtx=mt_back(48, 0.93, 0.0))
    B(0.1, 0.08, 2.9, 0.2, 0.68, 0.8, M["black"], bev=0.02)
    for u in (0.12, 2.88):
        C(u, 0.15, 0.02, 0, 0.8, M["black"], segs=8)
    for u, a in ((0.4, -35), (2.6, 35)):  # softboxes on stands, aimed at the centre-front
        C(u, 1.45, 0.022, 0, 1.6, M["black"], segs=8)
        mt = mt_rz(a, u, 1.45) @ mt_back(55, 1.6, 1.4)
        B(u - 0.3, 1.45, u + 0.3, 1.6, 1.4, 1.85, M["black"], bev=0.02, mtx=mt)
        B(u - 0.27, 1.6, u + 0.27, 1.605, 1.42, 1.83, m_emit("softbox", "#fffaf0", 4.0), bev=0, mtx=mt)
    for a in (90, 210, 330):  # camera tripod
        ex, ey = 1.5 + 0.25 * math.cos(math.radians(a)), 1.65 + 0.25 * math.sin(math.radians(a))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.015, radius2=0.012, depth=1.0)
        top, bot = X(1.5, 1.65, 1.3), X(ex, ey, 0)
        d = top - bot
        bmesh.ops.transform(bm, matrix=Matrix.Translation((top + bot) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4() @ Matrix.Scale(d.length, 4, Vector((0, 0, 1))), verts=bm.verts)
        _obj("leg", bm, M["black"], smooth=True)
    B(1.4, 1.55, 1.6, 1.75, 1.3, 1.44, M["black"], bev=0.02)
    C(1.5, 1.5, 0.05, 1.32, 1.42, m_plain("lens", "#10233a", rough=0.02, coat=1.0, metal=0.3), segs=20)
    S(1.57, 1.6, 1.45, 0.012, 0.012, 0.012, m_emit("rec", "#ff2020", 20))
    C(2.2, 1.0, 0.012, 0, 1.4, M["black"], segs=8)  # mic stand + mic
    C(2.2, 1.0, 0.035, 1.38, 1.55, M["black"], segs=16)
    S(2.2, 1.0, 1.56, 0.04, 0.04, 0.05, m_fabric("mic_mesh", "#2a2a2e", weave=800))


@prop
def trophy_cabinet(w, h):
    M = MAT()
    wd = M["walnut"]
    B(0.05, 0.08, 2.95, 0.85, 0, 0.2, wd, bev=0.01)
    B(0.05, 0.08, 2.95, 0.85, 0.2, 0.22, m_emit("cab_led", "#fff0d0", 1.5), bev=0)
    for u, v in ((0.05, 0.08), (2.89, 0.08), (0.05, 0.79), (2.89, 0.79)):
        B(u, v, u + 0.06, v + 0.06, 0, 1.0, M["gold"], bev=0.005)
    B(0.05, 0.08, 2.95, 0.14, 0.2, 1.0, wd, bev=0.005)
    gold = M["gold"]
    silver = m_plain("silver", "#d9dce0", rough=0.18, metal=1.0)
    bronze = m_plain("bronze", "#b0703a", rough=0.25, metal=1.0)
    for k, (u, v, s, mat) in enumerate(((0.42, 0.47, 1.3, silver), (0.98, 0.5, 1.5, gold), (1.5, 0.45, 1.8, gold), (2.02, 0.5, 1.45, silver), (2.58, 0.47, 1.25, bronze))):
        C(u, v, 0.09 * s, 0.22, 0.27, m_plain("plinth", "#1a1a1c", rough=0.3), segs=6)
        C(u, v, 0.015 * s, 0.27, 0.27 + 0.18 * s, mat, segs=12)
        C(u, v, 0.12 * s, 0.27 + 0.18 * s, 0.27 + 0.36 * s, mat, r2=0.05 * s, segs=24) if False else None
        S(u, v, 0.27 + 0.32 * s, 0.1 * s, 0.1 * s, 0.13 * s, mat)
        T(u, v, 0.27 + 0.44 * s, 0.09 * s, 0.012 * s, mat, segs=24)
        for sd in (-1, 1):
            T(u + sd * 0.12 * s, v, 0.27 + 0.33 * s, 0.045 * s, 0.01 * s, mat, segs=16, rsegs=6, mtx=mt_side(90, u + sd * 0.12 * s, 0.27 + 0.33 * s))
    for u in (0.7, 2.25):  # plaques leaning on the back
        B(u - 0.12, 0.16, u + 0.12, 0.2, 0.22, 0.55, wd, bev=0.006, mtx=mt_back(15, 0.2, 0.22))
        B(u - 0.09, 0.2, u + 0.09, 0.205, 0.27, 0.5, gold, bev=0, mtx=mt_back(15, 0.2, 0.22))
    B(0.05, 0.08, 2.95, 0.85, 1.0, 1.012, m_glass("cabglass", "#eef9fc", refl=0.06), bev=0)
    ringP(rrect(0.05, 0.08, 2.95, 0.85, 0.001, 1), rrect(0.09, 0.12, 2.91, 0.81, 0.001, 1), 1.0, 1.03, gold, smooth=False)


@prop
def home_gym(w, h):
    M = MAT()
    B(0.05, 0.05, 3.95, 2.95, 0, 0.02, m_plain("gymmat", "#2a2b2d", rough=0.9, var=0.08, vscale=60, bumpk=0.3, bscale=150), bev=0.01)
    # treadmill
    B(0.2, 0.3, 1.1, 2.85, 0.02, 0.18, m_plain("tm_frame", "#3a3d42", rough=0.4, metal=0.3), bev=0.02)
    B(0.32, 0.6, 0.98, 2.8, 0.18, 0.2, m_fabric("belt", "#151515", weave=120), bev=0.004)
    for u in (0.22, 1.02):
        B(u, 0.35, u + 0.06, 1.0, 0.02, 1.0, M["steel"], bev=0.01, mtx=mt_back(-8, 0.6, 0.02))
    B(0.22, 0.25, 1.08, 0.55, 1.05, 1.15, m_plain("tm_console", "#2a2c30", rough=0.3), bev=0.02, mtx=mt_back(35, 0.4, 1.1))
    B(0.45, 0.28, 0.85, 0.5, 1.15, 1.16, m_screen("scr_tm", "desktop", 1.2), bev=0, mtx=mt_back(35, 0.4, 1.1))
    # bench + rack + barbell
    cushion(2.05, 0.95, 2.45, 2.4, 0.4, 0.5, m_plain("benchpad", "#1b1b1d", rough=0.4, coat=0.2), puff=0.2)
    B(2.2, 1.0, 2.3, 2.3, 0.02, 0.4, M["black"], bev=0.01)
    for u in (1.55, 2.95):
        B(u - 0.04, 0.55, u + 0.04, 0.63, 0.02, 1.6, m_plain("rack_red", "#b42020", rough=0.35, metal=0.5), bev=0.01)
        B(u - 0.15, 0.45, u + 0.15, 0.73, 0.02, 0.06, M["black"], bev=0.01)
    C(2.25, 0.75, 0.016, 0.0, 2.3, M["chrome"], axis="X", segs=12, mtx=Matrix.Translation((-1.15, 0, 1.25)))
    for u in (1.3, 1.38, 3.12, 3.2):
        C(u, 0.75, 0.22 if u in (1.3, 3.2) else 0.18, 0.0, 0.05, m_plain("plate", "#1d1d1f", rough=0.5), axis="X", segs=32, mtx=Matrix.Translation((-0.025, 0, 1.25)))
    # dumbbell rack
    B(3.25, 1.0, 3.85, 2.85, 0.02, 0.5, M["black"], bev=0.01)
    for k in range(5):
        v = 1.15 + k * 0.33
        s = 0.05 + k * 0.008
        C(3.55, v, 0.012, 0, 0.36, M["chrome"], axis="X", segs=8, mtx=Matrix.Translation((-0.18, 0, 0.56)))
        for u in (3.4, 3.7):
            C(u, v, s, 0, 0.09, m_plain("db_rubber", "#202022", rough=0.6), axis="X", segs=6, mtx=Matrix.Translation((-0.045, 0, 0.56)))
    S(2.7, 2.6, 0.18, 0.12, 0.12, 0.12, m_plain("kettle_bell", "#2a2a2c", rough=0.5))
    T(2.7, 2.6, 0.3, 0.06, 0.018, m_plain("kettle_bell", "#2a2a2c", rough=0.5), mtx=mt_back(90, 2.6, 0.3))
    B(1.3, 2.4, 1.9, 2.95, 0.02, 0.025, m_fabric("yoga", "#6a3fb5", weave=200), bev=0.002)


# ---- kitchen ----

def worktop_run(u0, u1, carcass, top, splash=None, depth=0.65):
    B(u0, 0.08, u1, depth, 0, 0.88, carcass, bev=0.01)
    B(u0 - 0.01, 0.04, u1 + 0.01, depth + 0.03, 0.88, 0.92, top, bev=0.008)
    if splash:
        B(u0, 0.0, u1, 0.05, 0.92, 1.35, splash, bev=0.004)
    for u in [u0 + (u1 - u0) * k / round((u1 - u0) / 0.6) for k in range(1, round((u1 - u0) / 0.6))]:
        B(u - 0.004, depth - 0.002, u + 0.004, depth + 0.004, 0.05, 0.86, m_plain("gap", "#222"), bev=0)


def sink_basin(u0, v0, u1, v1, z, steel):
    ringP(rrect(u0, v0, u1, v1, 0.05), rrect(u0 + 0.03, v0 + 0.03, u1 - 0.03, v1 - 0.03, 0.04), z - 0.01, z + 0.004, steel)
    RB(u0 + 0.03, v0 + 0.03, u1 - 0.03, v1 - 0.03, z - 0.2, z - 0.15, m_plain("sinkbasin", "#8f9399", rough=0.35, metal=1.0), r=0.04, bev=0.02)
    C((u0 + u1) / 2, (v0 + v1) / 2, 0.02, z - 0.16, z - 0.15, m_plain("drain", "#3a3a3c", metal=1, rough=0.3), segs=16)
    cu = (u0 + u1) / 2
    C(cu, v0 - 0.03, 0.022, z, z + 0.3, MAT()["chrome"], segs=16)
    B(cu - 0.015, v0 - 0.03, cu + 0.015, v0 + 0.13, z + 0.27, z + 0.3, MAT()["chrome"], bev=0.01)


def hob(u0, v0, u1, v1, z, rings):
    B(u0, v0, u1, v1, z, z + 0.008, m_plain("hobglass", "#0d0d0f", rough=0.05, coat=1.0), bev=0.004)
    for cu, cv, r in rings:
        T(cu, cv, z + 0.009, r, 0.004, m_plain("hobring", "#5a5d62", rough=0.4), segs=32, rsegs=6)
        T(cu, cv, z + 0.009, r * 0.55, 0.003, m_plain("hobring", "#5a5d62", rough=0.4), segs=24, rsegs=6)


@prop
def kitchenette(w, h):
    M = MAT()
    worktop_run(0.05, 2.95, m_plain("cheap_carcass", "#e8e2d4", rough=0.5), m_plain("laminate_top", "#c9b99a", rough=0.5, var=0.06, vscale=30),
                m_tiles("splash_rent", "#e8e4da", "#b9b2a4", size=0.12))
    hob(0.25, 0.15, 0.95, 0.6, 0.92, ((0.42, 0.37, 0.11), (0.78, 0.37, 0.09)))
    sink_basin(1.3, 0.14, 1.95, 0.58, 0.92, M["steel"])
    B(2.25, 0.2, 2.75, 0.55, 0.92, 0.94, M["oak"], bev=0.008)
    C(2.45, 0.32, 0.075, 0.94, 1.12, m_plain("kettle_white", "#f0efec", rough=0.25, coat=0.4), segs=20)
    C(2.45, 0.32, 0.03, 1.12, 1.15, M["black"], segs=12)
    C(2.62, 0.48, 0.04, 0.94, 1.03, m_plain("mug_red", "#b53a2c", rough=0.3), segs=16)


@prop
def kitchen_line(w, h):
    M = MAT()
    top = m_marble("quartz_top", "#ecebe7", "#b8b4ac", tile=0, rough=0.15)
    worktop_run(0.05, 4.95, m_plain("kit_navy", "#2c3e55", rough=0.4, coat=0.2), top, m_tiles("splash_metro", "#f2f1ee", "#c4c0b8", size=0.075, rect=2.0, offset=0.5))
    sink_basin(0.4, 0.14, 1.3, 0.58, 0.92, M["steel"])
    hob(2.7, 0.12, 3.55, 0.62, 0.92, ((2.92, 0.28, 0.1), (3.33, 0.28, 0.08), (2.92, 0.48, 0.08), (3.33, 0.48, 0.1)))
    C(3.12, 0.38, 0.15, 0.93, 1.05, M["steel"], segs=28)       # pot on the hob
    C(3.12, 0.38, 0.135, 1.05, 1.052, m_plain("soup", "#c4582a", rough=0.2), segs=28)
    B(1.7, 0.25, 2.2, 0.55, 0.92, 0.945, M["oak"], bev=0.01)   # chopping board + veg
    for k, c in enumerate(("#d93a2a", "#e8a020", "#3aa53a")):
        S(1.82 + k * 0.12, 0.4, 0.97, 0.04, 0.04, 0.035, m_plain("veg" + c, c, rough=0.3))
    C(4.1, 0.3, 0.07, 0.92, 1.1, M["steel"], segs=20)           # kettle
    C(4.5, 0.38, 0.15, 0.92, 0.98, M["ceramic"], r2=0.18, segs=28)   # fruit bowl
    for k in range(5):
        S(4.5 + 0.08 * math.cos(k * 1.3), 0.38 + 0.08 * math.sin(k * 1.3), 1.0, 0.045, 0.045, 0.045, m_plain("fruit%d" % (k % 3), ("#e8a020", "#c9302a", "#9cc23a")[k % 3], rough=0.3))
    C(2.45, 0.2, 0.05, 0.92, 1.1, M["ceramic"], segs=16)   # utensil jar
    for k in range(4):
        C(2.45 + 0.02 * math.cos(k * 1.6), 0.2 + 0.02 * math.sin(k * 1.6), 0.008, 1.1, 1.25, M["dark"], segs=6)


@prop
def kitchen_island(w, h):
    M = MAT()
    B(0.12, 0.12, 2.88, 0.95, 0, 0.9, m_plain("kit_white", "#f1efea", rough=0.35, coat=0.2), bev=0.01)
    B(0.05, 0.05, 2.95, 1.15, 0.9, 0.95, m_marble("island_top", "#eeece6", "#a59f94", tile=0, rough=0.12), bev=0.012)
    C(1.0, 0.5, 0.18, 0.95, 1.05, m_plain("bowl_wood", "#9c6b40", rough=0.4), r2=0.2, segs=28)
    for k in range(6):
        S(1.0 + 0.1 * math.cos(k), 0.5 + 0.1 * math.sin(k), 1.05, 0.05, 0.05, 0.05, m_plain("fruit%d" % (k % 3), ("#e8a020", "#c9302a", "#9cc23a")[k % 3], rough=0.3))
    C(2.2, 0.45, 0.06, 0.95, 1.25, m_glass("vase", "#cfe8e0", refl=0.4), segs=20)
    leaves(2.2, 0.45, 1.25, 9, 0, 0, 0.16, 0.06, m_leaf("eucalyptus", "#8fae9a", "#5c7f6c"), seed=3, lift=(0.6, 1.2), droop=0.6)
    for u in (0.6, 1.5, 2.4):
        C(u, 1.45, 0.025, 0, 0.7, M["black"], segs=10)
        T(u, 1.45, 0.25, 0.17, 0.012, M["black"])
        cushion(u - 0.2, 1.27, u + 0.2, 1.63, 0.68, 0.76, m_plain("stool_tan", "#b0784a", rough=0.45, coat=0.3), puff=0.3)


@prop
def fridge(w, h):
    M = MAT()
    B(0.08, 0.08, 0.92, 0.84, 0, 1.85, M["steel"], bev=0.02)
    B(0.495, 0.79, 0.505, 0.85, 0.05, 1.85, m_plain("gap", "#222"), bev=0)
    for u in (0.44, 0.56):
        B(u - 0.015, 0.84, u + 0.015, 0.9, 0.9, 1.6, M["chrome"], bev=0.008)
    B(0.12, 0.12, 0.88, 0.8, 1.85, 1.855, m_plain("steel_top", "#9ea3a9", rough=0.45, metal=1.0), bev=0)
    B(0.3, 0.86, 0.42, 0.865, 1.2, 1.35, m_emit("fridge_disp", "#5ad1ff", 1.5), bev=0)
    B(0.18, 0.2, 0.42, 0.34, 1.855, 2.15, m_plain("cereal", "#e0a020", rough=0.6), bev=0.006)
    B(0.18, 0.2, 0.42, 0.205, 1.9, 2.1, m_plain("cereal_f", "#c0302a", rough=0.6), bev=0)
    RB(0.5, 0.25, 0.82, 0.62, 1.855, 1.95, m_fabric("basket", "#b08a5a", weave=150), r=0.04)
    for k in range(3):
        S(0.6 + k * 0.1, 0.42, 1.97, 0.045, 0.045, 0.045, m_plain("fruit%d" % k, ("#e8a020", "#c9302a", "#9cc23a")[k], rough=0.3))


@prop
def dining_table(w, h):
    M = MAT()
    wd = m_wood("dining_oak", "#b98b5e", "#8c6440", coat=0.3)
    seat = m_fabric("chair_beige", "#cbbba0", weave=380)

    def ch_(cu, cv, rot):
        mt = mt_rz(rot, cu, cv)
        B(cu - 0.22, cv - 0.2, cu + 0.22, cv + 0.22, 0.42, 0.46, wd, bev=0.015, mtx=mt)
        cushion(cu - 0.2, cv - 0.18, cu + 0.2, cv + 0.18, 0.46, 0.5, seat, puff=0.3, mtx=mt)
        B(cu - 0.22, cv - 0.24, cu + 0.22, cv - 0.19, 0.46, 0.92, wd, bev=0.012, mtx=mt @ mt_back(8, cv - 0.2, 0.46))
    for u in (1.35, 2.65):
        ch_(u, 0.5, 180)
        ch_(u, 2.5, 0)
    ch_(0.45, 1.5, 90)
    ch_(3.55, 1.5, 270)
    RB(0.65, 0.85, 3.35, 2.15, 0.72, 0.76, wd, r=0.06, bev=0.012)
    runner = m_fabric("runner", "#4f6d5a", weave=300)
    B(1.0, 1.3, 3.0, 1.7, 0.76, 0.763, runner, bev=0)
    for (u, v) in ((1.35, 1.08), (2.65, 1.08), (1.35, 1.92), (2.65, 1.92), (0.9, 1.5), (3.1, 1.5)):
        C(u, v, 0.13, 0.76, 0.775, M["ceramic"], segs=32)
        C(u, v, 0.08, 0.775, 0.778, m_plain("plate_in", "#e8e4dc", rough=0.2), segs=32)
        C(u + 0.17, v - 0.12 if v < 1.5 else v + 0.12, 0.035, 0.76, 0.88, M["glass"], segs=16, caps=False)
    C(2.0, 1.5, 0.08, 0.763, 0.95, m_plain("vase_white", "#efeee9", rough=0.2, coat=0.6), segs=24)
    for k in range(7):
        a = k * 0.9
        S(2.0 + 0.07 * math.cos(a), 1.5 + 0.07 * math.sin(a), 1.0, 0.045, 0.045, 0.03, m_plain("flower%d" % (k % 3), ("#e26a8a", "#f0c040", "#f4f0e8")[k % 3], rough=0.6))
    leaves(2.0, 1.5, 0.95, 8, 0, 0, 0.15, 0.05, M["leaf"], seed=2, lift=(0.2, 0.6), droop=0.4)


# ---- bathroom ----

@prop
def toilet(w, h):
    M = MAT()
    B(0.22, 0.05, 0.78, 0.27, 0, 0.82, M["ceramic"], bev=0.025)
    C(0.5, 0.16, 0.03, 0.82, 0.83, M["chrome"], segs=16)
    o = ell(0.5, 0.56, 0.2, 0.3, 32)
    i_ = ell(0.5, 0.56, 0.12, 0.2, 32)
    P(o, 0, 0.4, M["ceramic"], bev=0.02, smooth=True)
    P(i_, 0.32, 0.405, m_water("toiletwater", "#d6f2f8", deep="#9fd0de", depth_w=0.5), bev=0)
    ringP(ell(0.5, 0.56, 0.205, 0.305, 32), ell(0.5, 0.56, 0.125, 0.21, 32), 0.4, 0.44, m_plain("seat", "#fafaf8", rough=0.25, coat=0.5))
    B(0.3, 0.27, 0.7, 0.3, 0.44, 0.75, m_plain("seat", "#fafaf8", rough=0.25, coat=0.5), bev=0.02, mtx=mt_back(10, 0.3, 0.44))


@prop
def sink(w, h):
    M = MAT()
    B(0.1, 0.06, 0.9, 0.62, 0, 0.8, M["oak"], bev=0.01)
    B(0.08, 0.04, 0.92, 0.64, 0.8, 0.85, m_marble("vanity_top", "#f0eee9", "#bdb7ad", tile=0), bev=0.01)
    P(ell(0.5, 0.38, 0.27, 0.19, 32), 0.85, 0.86, M["ceramic"], bev=0.004, smooth=True)
    P(ell(0.5, 0.39, 0.22, 0.15, 32), 0.86, 0.862, m_plain("basin_in", "#dfe3e4", rough=0.1, coat=0.6), bev=0, smooth=True)
    C(0.5, 0.41, 0.02, 0.861, 0.864, m_plain("drain", "#3a3a3c", metal=1, rough=0.3), segs=16)
    C(0.5, 0.12, 0.022, 0.85, 1.05, M["chrome"], segs=16)
    B(0.485, 0.12, 0.515, 0.25, 1.02, 1.05, M["chrome"], bev=0.01)
    B(0.08, 0.0, 0.92, 0.04, 0.95, 1.8, m_plain("mirror", "#c9d6dc", rough=0.02, metal=1.0), bev=0.004)
    C(0.22, 0.17, 0.035, 0.85, 1.0, m_plain("soap", "#e8b3c8", rough=0.1, coat=1.0), segs=16)
    C(0.78, 0.17, 0.04, 0.85, 0.95, M["ceramic"], segs=16)


@prop
def shower(w, h):
    M = MAT()
    B(0.06, 0.06, 1.94, 1.94, 0, 0.06, m_tiles("showertray", "#f2f1ed", "#cfccc5", size=0.15, rough=0.1), bev=0.012)
    C(1.0, 1.0, 0.05, 0.06, 0.065, M["chrome"], segs=24)
    gl = m_glass("showerglass", "#e2f3f7", refl=0.35)
    B(0.06, 1.9, 1.3, 1.94, 0.06, 2.0, gl, bev=0)
    B(1.9, 0.06, 1.94, 1.94, 0.06, 2.0, gl, bev=0)
    for (a, b_, c_, d_) in ((0.06, 1.89, 1.3, 1.95), (1.89, 0.06, 1.95, 1.95)):
        B(a, b_, c_, d_, 2.0, 2.02, M["chrome"], bev=0.004)
    C(1.0, 0.13, 0.02, 0.06, 1.95, M["chrome"], segs=12)
    C(1.0, 0.38, 0.13, 1.95, 1.98, M["chrome"], segs=32)
    B(0.985, 0.13, 1.015, 0.38, 1.98, 2.0, M["chrome"], bev=0.004)
    B(0.12, 0.1, 0.5, 0.22, 1.0, 1.02, M["chrome"], bev=0.004)
    for k, c in enumerate(("#3a8fd1", "#f2f2f2", "#e8a020")):
        C(0.18 + k * 0.11, 0.16, 0.035, 1.02, 1.2, m_plain("bottle" + c, c, rough=0.2, coat=0.5), segs=16)


@prop
def bathtub(w, h):
    M = MAT()
    o = rrect(0.1, 0.1, 1.9, 2.9, 0.25, 6)
    i_ = rrect(0.25, 0.25, 1.75, 2.75, 0.25, 6)
    ringP(o, i_, 0, 0.58, M["ceramic"], bev=0.02)
    RB(0.25, 0.25, 1.75, 2.75, 0.1, 0.15, M["ceramic"], r=0.25)
    P(rrect(0.25, 0.25, 1.75, 2.75, 0.25, 6), 0.42, 0.425, m_water("bathwater", "#d8f4fa", deep="#86c9db", depth_w=0.3), bev=0)
    for k in range(7):  # foam
        rr = random.Random(k)
        S(rr.uniform(1.0, 1.5), rr.uniform(2.0, 2.4), 0.43, rr.uniform(0.04, 0.08), rr.uniform(0.04, 0.08), 0.02, m_plain("foam", "#ffffff", rough=0.6), segs=12, rings=6)
    C(1.0, 0.17, 0.03, 0.58, 0.68, M["chrome"], segs=16)
    B(0.985, 0.17, 1.015, 0.36, 0.65, 0.68, M["chrome"], bev=0.01)
    for u in (0.8, 1.2):
        C(u, 0.17, 0.035, 0.58, 0.63, M["chrome"], segs=16)
    pillow(0.7, 2.55, 1.3, 2.78, 0.5, m_plain("bathpillow", "#e8e8e6", rough=0.4), th=0.1)
    B(1.55, 1.2, 1.85, 1.75, 0.58, 0.6, m_fabric("towel", "#8fb8c4", weave=150), bev=0.01)


@prop
def washer(w, h):
    M = MAT()
    B(0.1, 0.08, 0.9, 0.86, 0, 0.85, m_plain("washer_white", "#f3f3f1", rough=0.3, coat=0.4), bev=0.025)
    B(0.12, 0.7, 0.88, 0.84, 0.85, 0.86, m_plain("panel_grey", "#d9dbdd", rough=0.3), bev=0.005)
    C(0.72, 0.77, 0.045, 0.86, 0.88, M["chrome"], segs=24)
    B(0.3, 0.74, 0.5, 0.8, 0.86, 0.862, m_emit("washer_disp", "#3ad1ff", 1.5), bev=0)
    B(0.14, 0.72, 0.26, 0.82, 0.86, 0.865, m_plain("drawer", "#e8e8e6", rough=0.3), bev=0.003)
    T(0.5, 0.4, 0.86, 0.22, 0.03, M["chrome"], segs=40)
    P(ell(0.5, 0.4, 0.2, 0.2, 40), 0.85, 0.86, m_plain("porthole", "#3a5866", rough=0.05, coat=1.0), bev=0)


# ---- outdoor ----

@prop
def tree(w, h):
    C(1.0, 1.0, 0.1, 0, 1.6, m_wood("bark", "#5b4330", "#3a2a1e"), segs=12)
    lf = m_leaf("treeleaf", "#5f9a3a", "#2f5f24", rough=0.7)
    lf2 = m_leaf("treeleaf2", "#76ad45", "#3c6f2b", rough=0.7)
    for k, (u, v, z, r) in enumerate(((1.0, 1.0, 2.2, 0.72), (0.62, 0.72, 2.0, 0.4), (1.38, 0.7, 2.05, 0.42), (0.7, 1.35, 1.95, 0.42), (1.35, 1.35, 2.0, 0.42), (1.0, 0.95, 2.55, 0.48))):
        blob(u, v, z, r, lf if k % 2 == 0 else lf2, seed=k + 3, rough=0.22, squash=0.75, subd=4)
    rng = random.Random(3)
    for k in range(40):  # leaf clumps breaking the silhouette
        a, r = rng.uniform(0, 6.28), rng.uniform(0.3, 0.85)
        blob(1.0 + r * math.cos(a), 1.0 + r * math.sin(a), 2.1 + rng.uniform(0, 0.5) - r * 0.4, rng.uniform(0.1, 0.17), lf2 if k % 3 else lf, seed=k + 50, rough=0.35, subd=2)


@prop
def hot_tub(w, h):
    M = MAT()
    deck = m_planks("tub_deck", "#9b6c46", "#80563a", plank_w=0.12, plank_l=3.2, gap="#2b1b10", rough=0.6, coat=0.1, gapw=0.01)
    ringP(rrect(0.05, 0.05, 2.95, 2.95, 0.08, 6), rrect(0.4, 0.4, 2.6, 2.6, 0.35, 6), 0, 0.85, deck, bev=0.015)
    ringP(rrect(0.36, 0.36, 2.64, 2.64, 0.38, 6), rrect(0.4, 0.4, 2.6, 2.6, 0.35, 6), 0.4, 0.87, m_plain("tub_rim", "#e9edef", rough=0.2, coat=0.6))
    RB(0.4, 0.4, 2.6, 2.6, 0.0, 0.3, m_plain("tub_shell", "#cfe3ea", rough=0.15, coat=0.6), r=0.35)
    B(0.8, 0.8, 2.2, 2.2, 0.3, 0.45, m_plain("tub_seat", "#c2dbe3", rough=0.2), bev=0.05)
    for k in range(8):
        a = k * math.pi / 4
        S(1.5 + 0.95 * math.cos(a), 1.5 + 0.95 * math.sin(a), 0.55, 0.03, 0.03, 0.03, M["chrome"])
    P(rrect(0.4, 0.4, 2.6, 2.6, 0.35, 6), 0.72, 0.725, m_water("tubwater", "#bfeef8", deep="#2fb3d6", depth_w=0.35), bev=0)
    rng = random.Random(2)
    for k in range(60):
        a, r = rng.uniform(0, 6.28), rng.uniform(0.75, 1.05)
        S(1.5 + r * math.cos(a), 1.5 + r * math.sin(a), 0.73, rng.uniform(0.01, 0.025), rng.uniform(0.01, 0.025), 0.008, m_plain("bubble", "#ffffff", rough=0.3, alpha=0.8), segs=8, rings=4)
    for (u, v) in ((0.55, 0.55), (2.45, 0.55)):
        pillow(u - 0.17, v - 0.12, u + 0.17, v + 0.12, 0.83, m_plain("headrest", "#3a3d42", rough=0.5), th=0.08, mtx=mt_rz(45 if u < 1 else -45, u, v))
    B(1.1, 2.7, 1.9, 2.95, 0.85, 0.9, m_fabric("towel2", "#f2efe8", weave=150), bev=0.01)


@prop
def lounger(w, h):
    M = MAT()
    fr = m_plain("lounger_frame", "#f2f0ec", rough=0.3, coat=0.3)
    RB(0.1, 0.1, 0.9, 1.92, 0.15, 0.3, fr, r=0.06, bev=0.02)
    cush = m_fabric("lounger_cush", "#3d7f95", "#eef0ec", pattern="stripe", pscale=7, weave=300)
    cushion(0.14, 0.75, 0.86, 1.88, 0.3, 0.38, cush, puff=0.2)
    cushion(0.14, 0.12, 0.86, 0.78, 0.3, 0.38, cush, puff=0.2, mtx=mt_back(-50, 0.78, 0.32) if False else mt_back(40, 0.78, 0.32))
    B(0.2, 1.25, 0.8, 1.65, 0.38, 0.41, m_fabric("towel3", "#f2c94a", weave=150), bev=0.01)
    for v in (0.12, 1.88):
        for u in (0.12, 0.88):
            C(u, v, 0.035, 0, 0.15, M["steel"], segs=12, axis="X", mtx=Matrix.Translation((-0.02, 0, 0.04))) if False else None


@prop
def bbq(w, h):
    M = MAT()
    B(0.5, 0.15, 1.5, 0.85, 0, 0.88, m_plain("bbq_body", "#1d1e20", rough=0.35, metal=0.5), bev=0.02)
    for u0, u1 in ((0.05, 0.5), (1.5, 1.95)):
        B(u0, 0.2, u1, 0.8, 0.86, 0.9, M["steel"], bev=0.008)
    B(0.55, 0.2, 1.45, 0.8, 0.88, 0.9, m_plain("embers", "#2a1208", emit=1.0, ecol="#ff5a1a"), bev=0)
    for k in range(13):
        u = 0.58 + k * 0.068
        B(u, 0.22, u + 0.014, 0.78, 0.9, 0.915, m_plain("grate", "#3a3a3c", rough=0.5, metal=0.8), bev=0)
    for (u, v) in ((0.78, 0.38), (1.05, 0.62), (1.25, 0.36)):
        C(u, v, 0.09, 0.915, 0.95, m_plain("patty", "#5a2e18", rough=0.6, var=0.2, vscale=40, bumpk=0.4), segs=24)
    for k in range(3):
        C(0.7 + k * 0.08, 0.62, 0.025, 0, 0.26, m_plain("sausage", "#a4482a", rough=0.35), axis="Y", segs=12, mtx=Matrix.Translation((0, 0.13, 0.94)))
    B(0.5, 0.06, 1.5, 0.15, 0.85, 1.4, M["black"], bev=0.02, mtx=mt_back(10, 0.15, 0.88))   # open lid at the back
    for u in (0.7, 1.0, 1.3):
        C(u, 0.87, 0.03, 0.75, 0.8, M["chrome"], segs=12)
    C(1.75, 0.5, 0.06, 0.9, 0.94, m_plain("plate_blue", "#2f5fa0", rough=0.3), segs=24)
    B(0.1, 0.35, 0.45, 0.42, 0.9, 0.91, M["steel"], bev=0.003)


@prop
def patio_set(w, h):
    M = MAT()
    rattan = m_fabric("rattan", "#7a5a3a", weave=120, sheen=0.1, rough=0.8)
    cush = m_fabric("patio_cush", "#ece6d8", weave=300)
    for a in (0, 90, 180, 270):
        r = 1.08
        cu, cv = 1.5 + r * math.sin(math.radians(a)), 1.5 + r * math.cos(math.radians(a))
        mt = mt_rz(a, cu, cv)
        RB(cu - 0.3, cv - 0.25, cu + 0.3, cv + 0.32, 0.0, 0.42, rattan, r=0.06, bev=0.02, mtx=mt)
        cushion(cu - 0.26, cv - 0.22, cu + 0.26, cv + 0.2, 0.42, 0.5, cush, puff=0.3, mtx=mt)
        cushion(cu - 0.3, cv + 0.2, cu + 0.3, cv + 0.34, 0.4, 0.82, rattan, puff=0.1, mtx=mt)
    C(1.5, 1.5, 0.55, 0.72, 0.75, m_glass("patioglass", "#cfe6e0", refl=0.4), segs=48)
    C(1.5, 1.5, 0.025, 0, 2.3, M["steel"], segs=12)
    # parasol: 8 panels, alternating colours
    bm = bmesh.new()
    top = bm.verts.new(X(1.5, 1.5, 2.35))
    rim = []
    R = 1.0
    for k in range(16):
        a = k * math.pi / 8
        rim.append(bm.verts.new(X(1.5 + R * math.cos(a), 1.5 + R * math.sin(a), 1.95 if k % 2 == 0 else 2.0)))
    for k in range(16):
        f = bm.faces.new([top, rim[k], rim[(k + 1) % 16]])
        f.material_index = (k // 2) % 2
    _obj("parasol", bm, None, mats=[m_fabric("parasol_a", "#f2ece0", weave=300), m_fabric("parasol_b", "#2f6f8a", weave=300)], solid=0.01)
    C(1.5, 1.5, 0.06, 2.35, 2.42, M["steel"], segs=12)


@prop
def doormat(w, h):
    coir = m_fabric("coir", "#9a7448", "#7a5733", weave=160, var=0.2, rough=1.0)
    RB(0.1, 0.12, 1.9, 0.88, 0, 0.025, m_plain("mat_rubber", "#2a2622", rough=0.9), r=0.04, bev=0.006)
    RB(0.15, 0.17, 1.85, 0.83, 0, 0.032, coir, r=0.03, bev=0.004)
    text("HOME", 1.0, 0.5, 0.03, 0.34, m_plain("mat_text", "#2d1f14", rough=1.0), ext=0.003)


# ---- pets ----

@prop
def pet_bed(w, h):
    fab = m_fabric("petbed", "#8a6e5a", weave=200)
    T(0.5, 0.5, 0.1, 0.33, 0.1, fab, segs=40, rsegs=14)
    C(0.5, 0.5, 0.36, 0.0, 0.06, fab, segs=40)
    cushion(0.25, 0.25, 0.75, 0.75, 0.04, 0.12, m_fabric("petcush", "#e6dccb", "#c9b8a0", pattern="check", pscale=12, weave=200), puff=0.4,
            mtx=None)
    T(0.62, 0.42, 0.14, 0.04, 0.015, m_plain("bone", "#f1ead8", rough=0.5), segs=12, rsegs=6)


@cached
def m_fur(name, c0, c1, stripes=0.0, stripe_col=None, scale=3.0):
    m, nt, b, _ = _new(name)
    co = coords(nt)
    n = noise(nt, co, scale, 4)
    col = ramp(nt, n.outputs["Fac"], [(0.3, lin(c1)), (0.7, lin(c0))])
    if stripes:
        wv = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Y"}, Vector=co, Scale=stripes, Distortion=3.0, Detail=2.0)
        col = mixc(nt, math_(nt, "GREATER_THAN", wv.outputs["Fac"], 0.62), col, lin(stripe_col))
    setsock(nt, b.inputs["Base Color"], col)
    b.inputs["Roughness"].default_value = 0.85
    b.inputs["Sheen Weight"].default_value = 0.8
    fine = nd(nt, "ShaderNodeTexWave", props={"wave_type": "BANDS", "bands_direction": "Y"}, Vector=coords(nt, (1, 0.2, 1)), Scale=200.0, Distortion=4.0)
    bump(nt, b, fine.outputs["Fac"], 0.2, 0.003)
    return m


@prop
def dog(w, h):
    fur = m_fur("goldfur", "#dca65c", "#b57c36", scale=6.0)
    dark = m_fur("darkfur", "#b9813f", "#8f5f2b", scale=6.0)
    # lying down, head up front (toward -v), front paws forward, tail out behind
    S(0.5, 0.6, 0.15, 0.19, 0.29, 0.14, fur, sub=1)               # body
    S(0.5, 0.4, 0.18, 0.17, 0.14, 0.15, fur, sub=1)               # chest
    for s_ in (-1, 1):
        S(0.5 + s_ * 0.13, 0.73, 0.11, 0.1, 0.14, 0.09, fur, sub=1)    # haunches
        S(0.5 + s_ * 0.09, 0.15, 0.04, 0.045, 0.11, 0.04, fur, sub=1)  # front legs
        S(0.5 + s_ * 0.09, 0.06, 0.035, 0.04, 0.035, 0.03, fur)         # paws
    S(0.5, 0.25, 0.27, 0.12, 0.12, 0.11, fur, sub=1)              # head
    S(0.5, 0.13, 0.24, 0.065, 0.08, 0.06, fur, sub=1)             # muzzle
    for s_ in (-1, 1):
        S(0.5 + s_ * 0.12, 0.27, 0.28, 0.045, 0.09, 0.035, dark, mtx=mt_rz(s_ * 15, 0.5 + s_ * 0.12, 0.27))
        S(0.5 + s_ * 0.05, 0.2, 0.36, 0.014, 0.012, 0.01, m_plain("eye", "#120c08", rough=0.05, coat=1.0))
    S(0.5, 0.055, 0.27, 0.028, 0.02, 0.02, m_plain("nose", "#1a1412", rough=0.2, coat=1.0))
    S(0.66, 0.92, 0.1, 0.035, 0.12, 0.035, fur, mtx=mt_rz(-40, 0.66, 0.92), sub=1)  # tail
    T(0.5, 0.35, 0.26, 0.11, 0.016, m_plain("collar", "#c0262b", rough=0.4), segs=24, rsegs=6, sy=0.55)


@prop
def cat(w, h):
    fur = m_fur("gingerfur", "#e3913f", "#cc7229", stripes=14.0, stripe_col="#a8521a", scale=8.0)
    S(0.5, 0.6, 0.12, 0.17, 0.24, 0.12, fur, sub=1)               # body (loaf)
    S(0.5, 0.38, 0.15, 0.13, 0.1, 0.12, fur, sub=1)
    S(0.5, 0.27, 0.22, 0.11, 0.1, 0.09, fur, sub=1)               # head
    for s_ in (-1, 1):
        C(0.5 + s_ * 0.065, 0.25, 0.04, 0.27, 0.36, fur, r2=0.0, segs=3, mtx=mt_rz(s_ * 25, 0.5 + s_ * 0.065, 0.25))
        S(0.5 + s_ * 0.04, 0.19, 0.27, 0.018, 0.013, 0.012, m_plain("cateye", "#7bbf3a", rough=0.05, coat=1.0, emit=0.3))
        S(0.5 + s_ * 0.07, 0.38, 0.04, 0.04, 0.06, 0.035, fur)         # front paws
    S(0.5, 0.17, 0.24, 0.014, 0.01, 0.01, m_plain("catnose", "#d47a7a", rough=0.3))
    for k in range(7):  # tail curling round the bottom
        a = math.radians(-20 + k * 28)
        S(0.5 + 0.2 * math.cos(a), 0.72 + 0.17 * math.sin(a), 0.05, 0.04, 0.04, 0.035, fur)


# ---- cars (nose toward -v) ----

def _interp(keys, t):
    for (t0, *a), (t1, *b_) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            f = (t - t0) / (t1 - t0) if t1 > t0 else 0
            f = f * f * (3 - 2 * f)
            return [x + (y - x) * f for x, y in zip(a, b_)]
    return keys[-1][1:]


def _loft(stations, mats_fn=None, name="loft"):
    """stations: list of rings (each a list of (u, v, z) points, same count). Closed ends."""
    bm = bmesh.new()
    rings = [[bm.verts.new(X(*p)) for p in ring] for ring in stations]
    n = len(rings[0])
    for a, b_ in zip(rings, rings[1:]):
        for k in range(n):
            f = bm.faces.new([a[k], a[(k + 1) % n], b_[(k + 1) % n], b_[k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if mats_fn:
        bm.normal_update()
        for f in bm.faces:
            f.material_index = mats_fn(f)
    return bm


def car(paint, L, Wd, body_keys, cabin_keys, roof_paint=True, glass_roof=False, accents=None, mirror_col=None, wheel_r=0.33, wheel_w=0.24,
        intake=False, vents=False, spoiler=False):
    """body_keys: (t, half-width, top-z, bottom-z) along t in [0, 1] nose->tail.
    cabin_keys: (t, half-width bottom, half-width top, height above body) over the greenhouse span."""
    M = MAT()
    cu, v0 = 1.5, 2.5 - L / 2
    nst = 28
    secs = []
    for i in range(nst + 1):
        t = i / nst
        hw, zt, zb = _interp(body_keys, t)
        v = v0 + L * t
        r = 0.12
        ring = []
        for (a, b_) in ((-1, 0.35), (-1, 0.75), (-0.82, 1.0), (0.82, 1.0), (1, 0.75), (1, 0.35), (0.9, 0.0), (-0.9, 0.0)):
            ring.append((cu + a * hw, v, zb + (zt - zb) * b_))
        secs.append(ring)
    bm = _loft(secs)
    ob = _obj("body", bm, paint, smooth=True)
    md = ob.modifiers.new("Sub", "SUBSURF")
    md.levels = md.render_levels = 2
    # greenhouse
    t0, t1 = cabin_keys[0][0], cabin_keys[-1][0]
    secs = []
    for i in range(17):
        t = t0 + (t1 - t0) * i / 16
        hwb, hwt, hh = _interp(cabin_keys, t)
        hw, zt, zb = _interp(body_keys, t)
        v = v0 + L * t
        z0 = zt - 0.04
        secs.append([(cu - hwb, v, z0), (cu - hwt, v, z0 + hh), (cu + hwt, v, z0 + hh), (cu + hwb, v, z0)])
    bm = _loft(secs)
    ob = _obj("cabin", bm, M["cglass"], smooth=True)
    md = ob.modifiers.new("Sub", "SUBSURF")
    md.levels = md.render_levels = 1
    # roof panel on the flat part of the greenhouse
    flat = [k for k in cabin_keys if k[3] >= max(c[3] for c in cabin_keys) - 0.01]
    ta, tb = flat[0][0], flat[-1][0]
    hw_r = min(k[2] for k in flat)
    zr = max(c[3] for c in cabin_keys)
    zt_mid = _interp(body_keys, (ta + tb) / 2)[1] - 0.04
    if glass_roof:
        mat_r = m_plain("glassroof", "#0f1620", rough=0.03, coat=1.0, spec=1.0)
    else:
        mat_r = paint
    cushion(cu - hw_r + 0.02, v0 + L * ta + 0.03, cu + hw_r - 0.02, v0 + L * tb - 0.03, zt_mid + zr - 0.03, zt_mid + zr + 0.025, mat_r, puff=0.2)
    if glass_roof:  # rails
        for s in (-1, 1):
            B(cu + s * (hw_r - 0.04) - 0.025, v0 + L * ta, cu + s * (hw_r - 0.04) + 0.025, v0 + L * tb, zt_mid + zr, zt_mid + zr + 0.05, M["black"], bev=0.01)
    # wheels peeking out
    hw_mid = max(k[1] for k in body_keys)
    for t in (0.2, 0.8):
        v = v0 + L * t
        for s in (-1, 1):
            C(cu + s * (0.92 * hw_mid - wheel_w / 2 + 0.01), v, wheel_r, 0, wheel_w, M["rubber"], axis="X", segs=24,
              mtx=Matrix.Translation((-wheel_w / 2, 0, wheel_r)))
    # mirrors at the windscreen base
    tm = t0 + 0.03
    hw, zt, zb = _interp(body_keys, tm)
    for s in (-1, 1):
        cushion(cu + s * hw - 0.02 * s - (0.14 if s > 0 else 0) + (0 if s > 0 else 0), v0 + L * tm - 0.05, cu + s * hw + (0.14 if s > 0 else -0.14) * 0 + s * 0.12,
                v0 + L * tm + 0.06, zt - 0.05, zt + 0.06, mirror_col or paint, puff=0.4) if False else \
            cushion(min(cu + s * (hw - 0.02), cu + s * (hw + 0.13)), v0 + L * tm - 0.05, max(cu + s * (hw - 0.02), cu + s * (hw + 0.13)),
                    v0 + L * tm + 0.06, zt - 0.06, zt + 0.06, m_paint("mirror" + mirror_col, mirror_col) if mirror_col else paint, puff=0.4)
    # lights
    hw, zt, zb = _interp(body_keys, 0.03)
    for s in (-1, 1):
        S(cu + s * (hw - 0.2), v0 + 0.1, zt - 0.06, 0.15, 0.06, 0.05, m_emit("headlight", "#f4f8ff", 3.0))
    hw, zt, zb = _interp(body_keys, 0.98)
    for s in (-1, 1):
        S(cu + s * (hw - 0.2), v0 + L - 0.07, zt - 0.06, 0.17, 0.05, 0.05, m_emit("taillight", "#ff2a1a", 3.0))
    if accents:
        acc = m_plain("accent" + accents, accents, rough=0.3, coat=0.5)
        for s in (-1, 1):  # racing stripes on the hood
            B(cu + s * 0.12 - 0.04, v0 + 0.1, cu + s * 0.12 + 0.04, v0 + L * t0 + 0.02, 0, 2, acc, bev=0, mtx=None) if False else None
    if intake:
        for s in (-1, 1):
            hw, zt, zb = _interp(body_keys, 0.62)
            B(cu + s * hw - 0.08, v0 + L * 0.55, cu + s * hw + 0.08 * (-1 if s > 0 else 1) * 0 + s * 0.0, v0 + L * 0.68, zt - 0.1, zt + 0.02, M["black"], bev=0.02) if False else None
    if vents:
        hw, zt, zb = _interp(body_keys, 0.82)
        for k in range(6):
            v = v0 + L * (0.72 + k * 0.035)
            B(cu - 0.4, v, cu + 0.4, v + 0.025, zt - 0.03, zt + 0.015, M["black"], bev=0.004)
    if spoiler:
        hw, zt, zb = _interp(body_keys, 0.95)
        B(cu - hw + 0.05, v0 + L - 0.3, cu + hw - 0.05, v0 + L - 0.12, zt + 0.12, zt + 0.16, paint if not accents else M["black"], bev=0.02)
        for s in (-1, 1):
            B(cu + s * 0.5 - 0.02, v0 + L - 0.25, cu + s * 0.5 + 0.02, v0 + L - 0.17, zt - 0.05, zt + 0.13, M["black"], bev=0.005)


@cached
def m_paint(name, col, rough=0.15, flake=0.0, matte=False):
    m, nt, b, _ = _new(name)
    b.inputs["Base Color"].default_value = (*lin(col), 1)
    b.inputs["Metallic"].default_value = 0.5 if not matte else 0.2
    b.inputs["Roughness"].default_value = rough if not matte else 0.55
    b.inputs["Coat Weight"].default_value = 1.0 if not matte else 0.0
    b.inputs["Coat Roughness"].default_value = 0.03
    return m


@prop
def car_hatchback(w, h):
    car(m_paint("paint_dullblue", "#4b6a8f", rough=0.35), 3.95, 1.72,
        [(0.0, 0.7, 0.62, 0.22), (0.08, 0.8, 0.72, 0.18), (0.28, 0.84, 0.82, 0.18), (0.75, 0.84, 0.86, 0.18), (0.95, 0.8, 0.88, 0.2), (1.0, 0.74, 0.85, 0.25)],
        [(0.3, 0.76, 0.6, 0.0), (0.44, 0.74, 0.6, 0.55), (0.88, 0.72, 0.6, 0.55), (0.96, 0.74, 0.62, 0.15), (0.985, 0.75, 0.62, 0.0)],
        mirror_col="#202226")


@prop
def car_sports(w, h):
    car(m_paint("paint_red", "#c4161c"), 4.4, 1.9,
        [(0.0, 0.76, 0.48, 0.18), (0.08, 0.88, 0.58, 0.14), (0.35, 0.92, 0.68, 0.14), (0.62, 0.95, 0.72, 0.14), (0.9, 0.92, 0.72, 0.16), (1.0, 0.86, 0.66, 0.2)],
        [(0.36, 0.8, 0.55, 0.0), (0.47, 0.76, 0.6, 0.42), (0.7, 0.74, 0.58, 0.42), (0.88, 0.74, 0.5, 0.06), (0.9, 0.75, 0.5, 0.0)],
        mirror_col="#111113", spoiler=False)


@prop
def car_suv(w, h):
    car(m_paint("paint_white", "#eceeee", rough=0.2), 4.7, 1.95,
        [(0.0, 0.82, 0.82, 0.3), (0.08, 0.92, 0.95, 0.26), (0.3, 0.96, 1.05, 0.26), (0.85, 0.96, 1.08, 0.26), (0.97, 0.92, 1.05, 0.3), (1.0, 0.86, 1.0, 0.35)],
        [(0.3, 0.86, 0.72, 0.0), (0.42, 0.84, 0.74, 0.62), (0.9, 0.84, 0.74, 0.62), (0.97, 0.86, 0.74, 0.15), (0.99, 0.86, 0.74, 0.0)],
        glass_roof=True, mirror_col="#15171a")


@prop
def car_super(w, h):
    paint = m_paint("paint_matteblack", "#1b1c1f", matte=True)
    car(paint, 4.6, 2.0,
        [(0.0, 0.8, 0.38, 0.12), (0.1, 0.92, 0.5, 0.1), (0.3, 0.96, 0.58, 0.1), (0.6, 1.0, 0.68, 0.1), (0.85, 1.0, 0.68, 0.12), (1.0, 0.95, 0.62, 0.15)],
        [(0.28, 0.72, 0.5, 0.0), (0.42, 0.7, 0.5, 0.42), (0.56, 0.68, 0.46, 0.42), (0.68, 0.66, 0.4, 0.06), (0.7, 0.66, 0.4, 0.0)],
        mirror_col="#e86a10", vents=True, spoiler=True)
    org = m_plain("orange_acc", "#ff6a10", rough=0.3, coat=0.6, emit=0.3)
    cu, v0 = 1.5, 2.5 - 2.3
    for s in (-1, 1):  # orange side blades + hood stripe
        B(cu + s * 0.12 - 0.035, v0 + 0.15, cu + s * 0.12 + 0.035, v0 + 1.25, 0.45, 0.58, org, bev=0.01, mtx=mt_back(-5, v0 + 0.15, 0.45))
        B(cu + s * 0.93 - 0.05, v0 + 2.6, cu + s * 0.93 + 0.05, v0 + 3.3, 0.5, 0.7, org, bev=0.02)


# --- entry -----------------------------------------------------------------------

def render_prop(kind, w, h, out_dir, samples=64):
    clear()
    BUILDERS[kind](w, h)
    lights(key=3.0, angle=20)
    camera(w, h)
    bpy.context.scene.cycles.samples = samples
    return render(os.path.join(out_dir, kind + ".png"))


def main(argv):
    project = os.path.abspath(argv[0])
    out = os.path.join(project, "assets", "homes")
    ids, do_props, do_all, samples, only = [], False, False, None, None
    it_ = iter(argv[1:])
    for a in it_:
        if a == "--out":
            out = os.path.abspath(next(it_))
        elif a == "--props":
            do_props = True
        elif a == "--all":
            do_all = True
        elif a == "--samples":
            samples = int(next(it_))
        elif a == "--only-props":
            only = next(it_).split(",")
            do_props = True
        else:
            ids.append(a)
    print("device:", _gpu())
    setup_scene(64)
    hd = os.path.join(project, "data", "homes")
    if do_all or do_props:
        cat = json.load(open(os.path.join(hd, "props.json")))["props"]
        for k, v in cat.items():
            if only and k not in only:
                continue
            if k not in BUILDERS:
                print("!! no builder for", k)
                continue
            try:
                print("prop", k, render_prop(k, v["w"], v["h"], os.path.join(out, "props"), samples or 64))
            except Exception:
                import traceback
                traceback.print_exc()
                print("!! prop failed", k)
    if do_all:
        ids = sorted(f[:-5] for f in os.listdir(hd) if f.endswith(".json") and f != "props.json")
    for hid in ids:
        print("home", hid, render_home(project, hid, out, samples or 128))


if __name__ == "__main__" and "--" in sys.argv:
    main(sys.argv[sys.argv.index("--") + 1:])
