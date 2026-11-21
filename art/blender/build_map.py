"""Lockdown map builder for Blender (5.x).

Builds a 3D version of a grid map from art/maps/<name>.json (made by
art/export_map.py) in its own scene, then renders it straight down with an
orthographic camera at 32 px per cell, so the image lines up 1:1 with the
game's collision grid (Arena.CELL = 32).

Headless (see the bottom of this file):
    blender -b art/blender/maps.blend --python art/blender/build_map.py -- <project> harbor foundry cage --save
Run inside Blender:
    exec(open(r"<project>/art/blender/build_map.py").read(), {"PROJECT": r"<project>", "MAP": "dustline"})
Then call render(PROJECT, MAP) (also defined here) to write assets/maps/<map>.png.

Coordinates: cell (x, y) covers Blender x..x+1, -(y+1)..-y; z is up. 1 cell = 1 m.
"""
import bpy, bmesh, json, os, math, random

PX_PER_CELL = 32
H_WALL = 2.0   # walls that line walkable space
H_MASS = 2.4   # solid blocks further in (rooftops)
H_CRATE = 0.95

# Theme per map: colours are linear RGB.
THEMES = {
    "dustline": {
        "sand": [(0.15, 0.115, 0.08), (0.10, 0.08, 0.055)],
        "paving": (0.13, 0.12, 0.105),
        "wall": (0.38, 0.32, 0.23),
        "roofs": [("tiles", (0.22, 0.07, 0.035)), ("concrete", (0.12, 0.115, 0.105)), ("tar", (0.035, 0.035, 0.04)),
                  ("tiles", (0.16, 0.08, 0.05)), ("concrete", (0.17, 0.15, 0.12))],
        "crate": (0.16, 0.09, 0.035),
        "paint": (0.55, 0.08, 0.03),
        "sun_rot": (math.radians(40), math.radians(-22), math.radians(-35)),
        "sun_strength": 2.6,
        "sky": (0.45, 0.52, 0.65),
    },
    # Container port: concrete quays, sea along the north and south edges,
    # warehouses with corrugated roofs, shipping containers for cover.
    "harbor": {
        "tag": "_hb", "style": "docks", "ground": "slabs", "ground_col": (0.105, 0.105, 0.1),
        "sand": [(0.1, 0.1, 0.1), (0.08, 0.08, 0.08)],
        "paving": (0.135, 0.125, 0.105),
        "wall": (0.26, 0.26, 0.25), "wall_kind": "concrete",
        "roofs": [("corrugated", (0.24, 0.06, 0.035)), ("corrugated", (0.07, 0.13, 0.2)), ("corrugated", (0.17, 0.18, 0.19)),
                  ("tar", (0.035, 0.035, 0.04)), ("corrugated", (0.07, 0.14, 0.08))],
        "crate": (0.16, 0.09, 0.035),
        "paint": (0.72, 0.5, 0.03), "line": (0.62, 0.45, 0.03),
        "water": (0.012, 0.045, 0.055), "water_at": lambda x, y, W, H: y < 7 or y >= H - 6,
        "ships": [(8, 46, 3.0, 4.4, True), (18, 31, 65.2, 3.0, False), (62, 100, 65.4, 4.0, True)],
        "sun_rot": (math.radians(45), math.radians(-18), math.radians(25)),
        "sun_strength": 2.3,
        "sky": (0.5, 0.6, 0.75),
    },
    # Steelworks: dark concrete, steel-plate bomb sites, factory halls with
    # pipes, skylights and glowing smokestacks; machinery for cover.
    "foundry": {
        "tag": "_fd", "style": "industrial", "ground": "slabs", "ground_col": (0.075, 0.072, 0.068), "slab_scale": 0.33,
        "sand": [(0.08, 0.08, 0.08), (0.06, 0.06, 0.06)],
        "site": "plate", "paving": (0.15, 0.15, 0.155),
        "wall": (0.2, 0.19, 0.18), "wall_kind": "concrete",
        "roofs": [("corrugated", (0.13, 0.14, 0.15)), ("corrugated", (0.17, 0.075, 0.035)), ("tar", (0.03, 0.03, 0.032)),
                  ("corrugated", (0.05, 0.1, 0.1)), ("concrete", (0.1, 0.095, 0.09))],
        "crate": (0.14, 0.08, 0.03),
        "paint": (0.75, 0.42, 0.02), "line": (0.65, 0.48, 0.02),
        "sun_rot": (math.radians(38), math.radians(16), math.radians(125)),
        "sun_strength": 2.1,
        "sky": (0.6, 0.55, 0.5),
    },
    # Training yard: grey concrete, cinder-block walls, gravel roofs,
    # jersey barriers and sandbags for cover.
    "cage": {
        "tag": "_cg", "style": "yard", "ground": "slabs", "ground_col": (0.12, 0.12, 0.118), "slab_scale": 0.5,
        "sand": [(0.1, 0.1, 0.1), (0.08, 0.08, 0.08)],
        "paving": (0.09, 0.1, 0.115),
        "wall": (0.33, 0.33, 0.32),
        "roofs": [("gravel", (0.2, 0.16, 0.115)), ("tar", (0.05, 0.045, 0.045)), ("concrete", (0.19, 0.15, 0.12))],
        "crate": (0.15, 0.1, 0.045),
        "paint": (0.75, 0.75, 0.72), "line": (0.75, 0.75, 0.72),
        "sun_rot": (math.radians(38), math.radians(-25), math.radians(-60)),
        "sun_strength": 2.7,
        "sky": (0.45, 0.55, 0.7),
    },
}


def _mat(name, build):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    build(nt, bsdf)
    return m


def _coord(nt):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    return tc.outputs["Object"]


def _noise(nt, scale, detail=4.0, src=None):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if src is not None:
        nt.links.new(src, n.inputs["Vector"])
    return n


def _ramp(nt, fac, c0, c1, p0=0.35, p1=0.65):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = p0
    r.color_ramp.elements[0].color = (*c0, 1)
    r.color_ramp.elements[1].position = p1
    r.color_ramp.elements[1].color = (*c1, 1)
    nt.links.new(fac, r.inputs[0])
    return r


def _bump(nt, bsdf, height, strength):
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    nt.links.new(height, b.inputs["Height"])
    nt.links.new(b.outputs[0], bsdf.inputs["Normal"])


def materials(th):
    tag = th.get("tag", "")  # Keeps each map's materials apart in maps.blend.
    def sand(nt, bsdf):
        co = _coord(nt)
        big = _noise(nt, 0.08, 3, co)
        fine = _noise(nt, 6.0, 8, co)
        r = _ramp(nt, big.outputs["Fac"], th["sand"][1], th["sand"][0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.25
        nt.links.new(r.outputs[0], mix.inputs["A"])
        nt.links.new(fine.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.95
        _bump(nt, bsdf, fine.outputs["Fac"], 0.25)

    def paving(nt, bsdf):
        co = _coord(nt)
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Brick Width"].default_value = 1.0
        br.inputs["Row Height"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.04
        br.offset = 0.0
        c = th["paving"]
        br.inputs["Color1"].default_value = (*c, 1)
        br.inputs["Color2"].default_value = (c[0] * 0.85, c[1] * 0.85, c[2] * 0.85, 1)
        br.inputs["Mortar"].default_value = (c[0] * 0.5, c[1] * 0.5, c[2] * 0.5, 1)
        nt.links.new(co, br.inputs["Vector"])
        dirt = _noise(nt, 1.5, 6, co)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.35
        nt.links.new(br.outputs["Color"], mix.inputs["A"])
        nt.links.new(dirt.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        _bump(nt, bsdf, br.outputs["Fac"], 0.4)

    def wall(nt, bsdf):
        co = _coord(nt)
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = 2.0
        br.inputs["Mortar Size"].default_value = 0.03
        c = th["wall"]
        br.inputs["Color1"].default_value = (*c, 1)
        br.inputs["Color2"].default_value = (c[0] * 0.9, c[1] * 0.88, c[2] * 0.85, 1)
        br.inputs["Mortar"].default_value = (c[0] * 0.6, c[1] * 0.6, c[2] * 0.6, 1)
        nt.links.new(co, br.inputs["Vector"])
        nt.links.new(br.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.9
        _bump(nt, bsdf, br.outputs["Fac"], 0.3)

    def roof_maker(style, col):
        def roof(nt, bsdf):
            co = _coord(nt)
            dirt = _noise(nt, 0.6, 6, co)
            if style == "tiles":
                pat = nt.nodes.new("ShaderNodeTexWave")
                pat.inputs["Scale"].default_value = 2.2
                pat.inputs["Distortion"].default_value = 0.0
                pat.wave_profile = "SAW"
                strength = 0.6
            elif style == "corrugated":
                pat = nt.nodes.new("ShaderNodeTexWave")
                pat.wave_type = "BANDS"
                pat.bands_direction = "Y"
                pat.wave_profile = "SIN"
                pat.inputs["Scale"].default_value = 1.1  # ~0.29 m between ridges
                pat.inputs["Distortion"].default_value = 0.0
                strength = 0.8
            elif style == "gravel":
                pat = nt.nodes.new("ShaderNodeTexVoronoi")
                pat.inputs["Scale"].default_value = 18.0
                strength = 0.35
            elif style == "concrete":
                pat = nt.nodes.new("ShaderNodeTexBrick")
                pat.inputs["Scale"].default_value = 0.5
                pat.inputs["Brick Width"].default_value = 1.0
                pat.inputs["Row Height"].default_value = 1.0
                pat.inputs["Mortar Size"].default_value = 0.015
                strength = 0.25
            else:
                pat = _noise(nt, 4.0, 10)
                strength = 0.15
            nt.links.new(co, pat.inputs["Vector"])
            r = _ramp(nt, dirt.outputs["Fac"], tuple(c * 0.7 for c in col), col, 0.3, 0.7)
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 0.35
            nt.links.new(r.outputs[0], mix.inputs["A"])
            nt.links.new(pat.outputs["Color"], mix.inputs["B"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 0.85
            _bump(nt, bsdf, pat.outputs["Fac"] if "Fac" in pat.outputs else pat.outputs["Distance"], strength)
        return roof

    def metal(nt, bsdf):
        bsdf.inputs["Base Color"].default_value = (0.32, 0.33, 0.34, 1)
        bsdf.inputs["Metallic"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.45

    def crate(nt, bsdf):
        co = _coord(nt)
        planks = nt.nodes.new("ShaderNodeTexBrick")
        planks.inputs["Scale"].default_value = 3.0
        planks.inputs["Brick Width"].default_value = 4.0
        planks.inputs["Row Height"].default_value = 0.25
        planks.inputs["Mortar Size"].default_value = 0.025
        c = th["crate"]
        planks.inputs["Color1"].default_value = (*c, 1)
        planks.inputs["Color2"].default_value = (c[0] * 1.25, c[1] * 1.2, c[2] * 1.1, 1)
        planks.inputs["Mortar"].default_value = (c[0] * 0.35, c[1] * 0.35, c[2] * 0.35, 1)
        nt.links.new(co, planks.inputs["Vector"])
        nt.links.new(planks.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.75
        _bump(nt, bsdf, planks.outputs["Fac"], 0.5)

    def paint(nt, bsdf):
        co = _coord(nt)
        wear = _noise(nt, 3.0, 10, co)
        r = nt.nodes.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position = 0.30
        r.color_ramp.elements[0].color = (0, 0, 0, 1)
        r.color_ramp.elements[1].position = 0.36
        r.color_ramp.elements[1].color = (0.85, 0.85, 0.85, 1)
        nt.links.new(wear.outputs["Fac"], r.inputs[0])
        bsdf.inputs["Base Color"].default_value = (*th["paint"], 1)
        bsdf.inputs["Roughness"].default_value = 0.7
        nt.links.new(r.outputs[0], bsdf.inputs["Alpha"])

    def slabs(nt, bsdf):
        """Poured concrete in big slabs with oil stains and tyre grime."""
        co = _coord(nt)
        c = th["ground_col"]
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = th.get("slab_scale", 0.25)
        br.inputs["Brick Width"].default_value = 1.0
        br.inputs["Row Height"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.012
        br.offset = 0.0
        br.inputs["Color1"].default_value = (*c, 1)
        br.inputs["Color2"].default_value = (c[0] * 0.88, c[1] * 0.88, c[2] * 0.88, 1)
        br.inputs["Mortar"].default_value = (c[0] * 0.45, c[1] * 0.45, c[2] * 0.45, 1)
        nt.links.new(co, br.inputs["Vector"])
        stain = _noise(nt, 0.35, 6, co)
        sr = _ramp(nt, stain.outputs["Fac"], (0.72, 0.72, 0.72), (1, 1, 1), 0.4, 0.62)
        fine = _noise(nt, 9.0, 8, co)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(br.outputs["Color"], mix.inputs["A"])
        nt.links.new(sr.outputs[0], mix.inputs["B"])
        mix2 = nt.nodes.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        mix2.blend_type = "MULTIPLY"
        mix2.inputs["Factor"].default_value = 0.2
        nt.links.new(mix.outputs["Result"], mix2.inputs["A"])
        nt.links.new(fine.outputs["Color"], mix2.inputs["B"])
        nt.links.new(mix2.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.9
        _bump(nt, bsdf, br.outputs["Fac"], 0.3)

    def plate(nt, bsdf):
        """Steel floor plates (Foundry bomb sites)."""
        co = _coord(nt)
        c = th["paving"]
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = 0.5
        br.inputs["Brick Width"].default_value = 1.0
        br.inputs["Row Height"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.01
        br.offset = 0.5
        br.inputs["Color1"].default_value = (*c, 1)
        br.inputs["Color2"].default_value = (c[0] * 0.85, c[1] * 0.85, c[2] * 0.85, 1)
        br.inputs["Mortar"].default_value = (0.02, 0.02, 0.02, 1)
        nt.links.new(co, br.inputs["Vector"])
        tread = nt.nodes.new("ShaderNodeTexWave")
        tread.wave_type = "BANDS"
        tread.bands_direction = "DIAGONAL"
        tread.inputs["Scale"].default_value = 14.0
        tread.inputs["Distortion"].default_value = 0.0
        nt.links.new(co, tread.inputs["Vector"])
        rust = _noise(nt, 0.8, 6, co)
        rr = _ramp(nt, rust.outputs["Fac"], (1, 1, 1), (0.55, 0.32, 0.18), 0.55, 0.75)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(br.outputs["Color"], mix.inputs["A"])
        nt.links.new(rr.outputs[0], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = 0.7
        bsdf.inputs["Roughness"].default_value = 0.5
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "ADD"
        nt.links.new(br.outputs["Fac"], add.inputs[0])
        nt.links.new(tread.outputs["Fac"], add.inputs[1])
        _bump(nt, bsdf, add.outputs[0], 0.25)

    def concrete_wall(nt, bsdf):
        """Cast concrete panels (Harbor, Foundry walls)."""
        co = _coord(nt)
        c = th["wall"]
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = 0.5
        br.inputs["Brick Width"].default_value = 1.0
        br.inputs["Row Height"].default_value = 0.5
        br.inputs["Mortar Size"].default_value = 0.01
        br.inputs["Color1"].default_value = (*c, 1)
        br.inputs["Color2"].default_value = (c[0] * 0.92, c[1] * 0.92, c[2] * 0.92, 1)
        br.inputs["Mortar"].default_value = (c[0] * 0.5, c[1] * 0.5, c[2] * 0.5, 1)
        nt.links.new(co, br.inputs["Vector"])
        dirt = _noise(nt, 1.2, 6, co)
        dr = _ramp(nt, dirt.outputs["Fac"], (0.6, 0.6, 0.6), (1, 1, 1), 0.35, 0.65)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(br.outputs["Color"], mix.inputs["A"])
        nt.links.new(dr.outputs[0], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.88
        _bump(nt, bsdf, br.outputs["Fac"], 0.25)

    def water(nt, bsdf):
        co = _coord(nt)
        w1 = nt.nodes.new("ShaderNodeTexWave")
        w1.inputs["Scale"].default_value = 0.35
        w1.inputs["Distortion"].default_value = 6.0
        w1.inputs["Detail"].default_value = 4.0
        nt.links.new(co, w1.inputs["Vector"])
        n = _noise(nt, 2.5, 6, co)
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "ADD"
        nt.links.new(w1.outputs["Fac"], add.inputs[0])
        nt.links.new(n.outputs["Fac"], add.inputs[1])
        c = th["water"]
        r = _ramp(nt, n.outputs["Fac"], c, tuple(v * 1.6 for v in c), 0.35, 0.7)
        nt.links.new(r.outputs[0], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.06
        bsdf.inputs["Specular IOR Level"].default_value = 0.6
        _bump(nt, bsdf, add.outputs[0], 0.12)

    def line(nt, bsdf):
        co = _coord(nt)
        wear = _noise(nt, 2.5, 10, co)
        r = nt.nodes.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position = 0.36
        r.color_ramp.elements[0].color = (0, 0, 0, 1)
        r.color_ramp.elements[1].position = 0.42
        r.color_ramp.elements[1].color = (0.9, 0.9, 0.9, 1)
        nt.links.new(wear.outputs["Fac"], r.inputs[0])
        bsdf.inputs["Base Color"].default_value = (*th.get("line", (0.6, 0.45, 0.03)), 1)
        bsdf.inputs["Roughness"].default_value = 0.6
        nt.links.new(r.outputs[0], bsdf.inputs["Alpha"])

    ground_kind = th.get("ground", "sand")
    site_kind = th.get("site", "paving")
    return {
        "sand": _mat("LD_Sand" + tag, sand), "paving": _mat("LD_Paving" + tag, paving), "wall": _mat("LD_Wall" + tag, wall),
        "crate": _mat("LD_Crate" + tag, crate), "paint": _mat("LD_Paint" + tag, paint), "metal": _mat("LD_Metal" + tag, metal),
        "roofs": [(st, _mat("LD_Roof%s_%d" % (tag, i), roof_maker(st, c))) for i, (st, c) in enumerate(th["roofs"])],
        "ground": _mat("LD_Sand" + tag, sand) if ground_kind == "sand" else _mat("LD_Slabs" + tag, slabs),
        "site": {"paving": lambda: _mat("LD_Paving" + tag, paving), "plate": lambda: _mat("LD_Plate" + tag, plate)}[site_kind](),
        "wall_mat": _mat("LD_Wall" + tag, wall) if th.get("wall_kind", "brick") == "brick" else _mat("LD_WallC" + tag, concrete_wall),
        "water": _mat("LD_Water" + tag, water) if th.get("water") else None,
        "line": _mat("LD_Line" + tag, line),
    }


def _box_mesh(name, boxes, coll, mat, bevel=0.0):
    """boxes: list of (x0, y0, x1, y1, z0, z1) in Blender coords."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for x0, y0, x1, y1, z0, z1 in boxes:
        v = [bm.verts.new(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
        for f in [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]:
            bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    coll.objects.link(ob)
    if bevel > 0:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        m.limit_method = "ANGLE"
    return ob


def _simple_mat(name, color, metallic=0.0, rough=0.6, stripes=None):
    """Plain (or striped: stripes=(color2, scale[, direction])) material, cached by name."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]

    def b(nt, bsdf):
        if stripes:
            co = _coord(nt)
            wv = nt.nodes.new("ShaderNodeTexWave")
            wv.wave_type = "BANDS"
            wv.bands_direction = stripes[2] if len(stripes) > 2 else "X"
            wv.wave_profile = "SAW"
            wv.inputs["Scale"].default_value = stripes[1]
            wv.inputs["Distortion"].default_value = 0.0
            nt.links.new(co, wv.inputs["Vector"])
            r = nt.nodes.new("ShaderNodeValToRGB")
            r.color_ramp.interpolation = "CONSTANT"
            r.color_ramp.elements[0].color = (*color, 1)
            r.color_ramp.elements[1].position = 0.5
            r.color_ramp.elements[1].color = (*stripes[0], 1)
            nt.links.new(wv.outputs["Fac"], r.inputs[0])
            nt.links.new(r.outputs[0], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = rough
    return _mat(name, b)


def _mesh_obj(name, coll, build_fn, mat, loc=(0, 0, 0), rot_z=0.0, bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build_fn(bm)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = (0, 0, rot_z)
    ob.data.materials.append(mat)
    coll.objects.link(ob)
    if bevel > 0:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
        m.limit_method = "ANGLE"
    return ob


def _cube(bm, sx, sy, sz, cx=0.0, cy=0.0, cz=0.0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=r["verts"])
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=r["verts"])


def _cyl(bm, radius, depth, cx=0.0, cy=0.0, cz=0.0, segs=16, axis="Z", caps=True):
    r = bmesh.ops.create_cone(bm, cap_ends=caps, segments=segs, radius1=radius, radius2=radius, depth=depth)
    if axis == "Y":
        bmesh.ops.rotate(bm, verts=r["verts"], cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.radians(90), 3, "X"))
    elif axis == "X":
        bmesh.ops.rotate(bm, verts=r["verts"], cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=r["verts"])


CAR_PAINTS = [(0.42, 0.05, 0.03), (0.06, 0.12, 0.30), (0.55, 0.50, 0.40), (0.05, 0.05, 0.05), (0.30, 0.32, 0.10), (0.60, 0.40, 0.05)]
BARREL_PAINTS = [(0.55, 0.10, 0.04), (0.08, 0.20, 0.45), (0.15, 0.35, 0.10), (0.75, 0.55, 0.05)]


def _car(coll, mats, rng, x, y, w, h, i):
    """An old sedan filling a w x h cover footprint, facing along the long side."""
    length, width = max(w, h) - 0.25, min(w, h) - 0.3
    rot = 0.0 if w >= h else math.radians(90)
    rot += math.radians(rng.uniform(-4, 4))
    cx, cy = x + w / 2, -(y + h / 2)
    paint = _simple_mat("LD_CarPaint_%d" % (i % len(CAR_PAINTS)), CAR_PAINTS[i % len(CAR_PAINTS)], 0.4, 0.35)
    glass = _simple_mat("LD_Glass", (0.01, 0.015, 0.02), 0.2, 0.08)
    tyre = _simple_mat("LD_Tyre", (0.015, 0.015, 0.015), 0.0, 0.9)
    light = _simple_mat("LD_Lamp", (0.9, 0.85, 0.6), 0.0, 0.2)
    _mesh_obj("Car_%d_body" % i, coll, lambda bm: _cube(bm, length, width, 0.55, 0, 0, 0.55), paint, (cx, cy, 0), rot, 0.12)
    _mesh_obj("Car_%d_cabin" % i, coll, lambda bm: _cube(bm, length * 0.5, width * 0.86, 0.5, -length * 0.05, 0, 1.05), glass, (cx, cy, 0), rot, 0.1)
    _mesh_obj("Car_%d_roof" % i, coll, lambda bm: _cube(bm, length * 0.4, width * 0.8, 0.06, -length * 0.07, 0, 1.31), paint, (cx, cy, 0), rot, 0.03)
    def wheels(bm):
        for sx in (-1, 1):
            for sy in (-1, 1):
                _cyl(bm, 0.33, 0.22, sx * length * 0.32, sy * width * 0.47, 0.33, 14, "Y")
    _mesh_obj("Car_%d_wheels" % i, coll, wheels, tyre, (cx, cy, 0), rot)
    def lamps(bm):
        for sy in (-1, 1):
            _cube(bm, 0.05, 0.3, 0.12, length / 2, sy * width * 0.32, 0.65)
    _mesh_obj("Car_%d_lamps" % i, coll, lamps, light, (cx, cy, 0), rot)


def _barrel(coll, mats, rng, cx, cy, i):
    paint = BARREL_PAINTS[rng.randrange(len(BARREL_PAINTS))]
    m = _simple_mat("LD_Barrel_%d" % BARREL_PAINTS.index(paint), paint, 0.15, 0.55)
    rim = _simple_mat("LD_BarrelRim", (0.12, 0.12, 0.12), 0.7, 0.4)
    ox, oy = rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05)
    _mesh_obj("Barrel_%d" % i, coll, lambda bm: _cyl(bm, 0.4, 1.0, 0, 0, 0.5, 20), m, (cx + ox, cy + oy, 0), 0, 0.02)
    def rims(bm):
        for z in (0.33, 0.66, 1.0):
            _cyl(bm, 0.415, 0.04, 0, 0, z, 20, caps=False)
        _cyl(bm, 0.07, 0.03, 0.2, 0.1, 1.01, 10)  # bung cap
    _mesh_obj("Barrel_%d_rims" % i, coll, rims, rim, (cx + ox, cy + oy, 0))


AWNING_COLS = [((0.40, 0.04, 0.02), (0.30, 0.27, 0.20)), ((0.03, 0.14, 0.20), (0.30, 0.27, 0.20)), ((0.40, 0.22, 0.02), (0.12, 0.07, 0.03)),
               ((0.07, 0.18, 0.05), (0.30, 0.27, 0.20))]


def _awning(coll, mats, rng, i, x, y, dx, dy, ax, ay):
    """3 cells of striped canvas sloping out from a wall face into the street."""
    c1, c2 = AWNING_COLS[rng.randrange(len(AWNING_COLS))]
    mat = _simple_mat("LD_Awning_%d" % AWNING_COLS.index((c1, c2)), c1, 0.0, 0.85, (c2, 1.6))
    # Wall face position (between wall cell and street cell), in Blender coords.
    fx = x + 0.5 + dx * 0.5
    fy = -(y + 0.5) - dy * 0.5
    depth = 1.25
    z_top, z_low = 1.9, 1.35
    # Span along the wall (3 cells) and out into the street.
    a0 = (-0.5, 2.5)
    pts = []
    for along in a0:
        for out, z in ((0.0, z_top), (depth, z_low)):
            px = fx + ax * (along) + dx * out
            py = fy - ay * (along) - dy * out
            pts.append((px, py, z))
    def build_fn(bm):
        v = [bm.verts.new(p) for p in pts]
        bm.faces.new([v[0], v[1], v[3], v[2]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in bm.faces:
            if f.normal.z < 0:
                f.normal_flip()
    ob = _mesh_obj("Awning_%d" % i, coll, build_fn, mat)
    sol = ob.modifiers.new("Thick", "SOLIDIFY")
    sol.thickness = 0.04


def _set_scene(sc):
    """Make `sc` current (no window when running headless with -b)."""
    if bpy.context.window is not None:
        bpy.context.window.scene = sc


def _emit_mat(name, color, strength):
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]

    def b(nt, bsdf):
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return _mat(name, b)


def _corr_mat(name, color, scale=2.2):
    """Corrugated painted steel with grime and rust (containers, sheds)."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]

    def b(nt, bsdf):
        co = _coord(nt)
        wv = nt.nodes.new("ShaderNodeTexWave")
        wv.wave_type = "BANDS"
        wv.bands_direction = "X"
        wv.wave_profile = "SIN"
        wv.inputs["Scale"].default_value = scale
        wv.inputs["Distortion"].default_value = 0.0
        nt.links.new(co, wv.inputs["Vector"])
        grime = _noise(nt, 1.4, 8, co)
        gr = _ramp(nt, grime.outputs["Fac"], tuple(c * 0.55 for c in color), color, 0.3, 0.7)
        rust = _noise(nt, 4.0, 10, co)
        rr = _ramp(nt, rust.outputs["Fac"], (1, 1, 1), (0.35, 0.17, 0.07), 0.6, 0.72)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(gr.outputs[0], mix.inputs["A"])
        nt.links.new(rr.outputs[0], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = 0.35
        bsdf.inputs["Roughness"].default_value = 0.55
        _bump(nt, bsdf, wv.outputs["Fac"], 0.5)
    return _mat(name, b)


def _prism(bm, pts, z0, z1):
    """Vertical prism from an XY outline (counter-clockwise)."""
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    n = len(pts)
    for k in range(n):
        bm.faces.new([lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]])


def _extrude_x(bm, prof, length):
    """Prism along X from a YZ profile (counter-clockwise seen from +X)."""
    a = [bm.verts.new((-length / 2, y, z)) for y, z in prof]
    b = [bm.verts.new((length / 2, y, z)) for y, z in prof]
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    n = len(prof)
    for k in range(n):
        bm.faces.new([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]])


def _footprint(rng, x, y, w, h, jitter=2.0):
    """Centre (Blender coords), long side, short side and yaw of a cover rect."""
    rot = (0.0 if w >= h else math.radians(90)) + math.radians(rng.uniform(-jitter, jitter))
    return x + w / 2, -(y + h / 2), max(w, h), min(w, h), rot


# --- Harbor ------------------------------------------------------------------

CONTAINER_COLS = [(0.36, 0.04, 0.02), (0.03, 0.11, 0.3), (0.04, 0.19, 0.09), (0.55, 0.21, 0.02), (0.22, 0.23, 0.24),
                  (0.42, 0.3, 0.04), (0.28, 0.04, 0.11), (0.5, 0.5, 0.48)]


def _container(coll, rng, cx, cy, length, width, rot, i, z0=0.0, hgt=2.0, col=None):
    col = col or CONTAINER_COLS[rng.randrange(len(CONTAINER_COLS))]
    m = _corr_mat("LD_Cont_%d" % CONTAINER_COLS.index(col), col)
    frame = _simple_mat("LD_ContFrame", (0.04, 0.04, 0.045), 0.5, 0.5)
    _mesh_obj("Cont_%s" % i, coll, lambda bm: _cube(bm, length, width, hgt, 0, 0, z0 + hgt / 2), m, (cx, cy, 0), rot, 0.02)

    def fr(bm):
        for sx in (-1, 1):
            _cube(bm, 0.12, width + 0.02, 0.05, sx * (length / 2 - 0.06), 0, z0 + hgt + 0.01)
            for sy in (-1, 1):
                _cube(bm, 0.22, 0.22, 0.08, sx * (length / 2 - 0.11), sy * (width / 2 - 0.11), z0 + hgt + 0.02)
    _mesh_obj("Cont_%s_frame" % i, coll, fr, frame, (cx, cy, 0), rot)


def _spool(coll, rng, cx, cy, r, i):
    """Wooden cable drum standing on end."""
    wood = _simple_mat("LD_SpoolWood", (0.2, 0.11, 0.045), 0.0, 0.8, ((0.13, 0.07, 0.03), 5.0))
    cable = _simple_mat("LD_Cable", (0.02, 0.02, 0.02), 0.2, 0.5)
    _mesh_obj("Spool_%d" % i, coll, lambda bm: (_cyl(bm, r, 0.12, 0, 0, 0.06, 28), _cyl(bm, r, 0.12, 0, 0, 1.0, 28)), wood, (cx, cy, 0), rng.uniform(0, 3))
    _mesh_obj("Spool_%d_cable" % i, coll, lambda bm: (_cyl(bm, r * 0.82, 0.9, 0, 0, 0.53, 28), _cyl(bm, r * 0.25, 0.04, 0, 0, 1.07, 16)), cable, (cx, cy, 0))


def _ship(coll, rng, x0, x1, yc, beam, i, cargo=True):
    """A ship along +x (cell coords, bow at x1) with a bridge at the stern and
    containers stacked on deck."""
    cy = -yc
    hull = _simple_mat("LD_Hull_%d" % (i % 3), [(0.17, 0.025, 0.02), (0.015, 0.035, 0.08), (0.03, 0.06, 0.04)][i % 3], 0.3, 0.45)
    deck = _simple_mat("LD_Deck", (0.06, 0.085, 0.06), 0.3, 0.7)
    white = _simple_mat("LD_ShipWhite", (0.55, 0.55, 0.52), 0.1, 0.45)
    dark = _simple_mat("LD_ShipDark", (0.02, 0.02, 0.025), 0.4, 0.3)
    b = beam / 2
    bow = min(beam * 1.3, (x1 - x0) * 0.3)
    outline = [(x0 + 0.3, -b), (x1 - bow, -b), (x1 - bow * 0.35, -b * 0.55), (x1, 0), (x1 - bow * 0.35, b * 0.55), (x1 - bow, b), (x0 + 0.3, b), (x0, b * 0.7), (x0, -b * 0.7)]
    _mesh_obj("Ship_%d_hull" % i, coll, lambda bm: _prism(bm, outline, -0.4, 1.0), hull, (0, cy, 0))
    inset = [(x + (0.25 if x < (x0 + x1) / 2 else -0.25), y * 0.86) for x, y in outline]
    _mesh_obj("Ship_%d_deck" % i, coll, lambda bm: _prism(bm, inset, 0.9, 1.04), deck, (0, cy, 0))
    L = x1 - x0
    bridge_len = max(2.2, L * (0.16 if cargo else 0.3))
    bx = x0 + 0.6 + bridge_len / 2 if cargo else x0 + L * 0.42
    _mesh_obj("Ship_%d_bridge" % i, coll, lambda bm: _cube(bm, bridge_len, beam * 0.8, 2.4, bx, 0, 2.2), white, (0, cy, 0), 0, 0.06)
    _mesh_obj("Ship_%d_wing" % i, coll, lambda bm: _cube(bm, 0.5, beam * 0.98, 0.12, bx + bridge_len / 2 - 0.25, 0, 3.0), white, (0, cy, 0))

    def fun(bm):
        _cyl(bm, beam * 0.13, 1.6, bx - bridge_len * 0.25, 0, 3.9, 20)
        _cube(bm, 0.12, 0.12, 0.6, bx + bridge_len * 0.2, 0, 3.7)  # radar mast
    _mesh_obj("Ship_%d_funnel" % i, coll, fun, dark, (0, cy, 0))
    band = _simple_mat("LD_FunnelBand_%d" % (i % 3), [(0.6, 0.35, 0.02), (0.5, 0.05, 0.03), (0.03, 0.15, 0.4)][i % 3], 0.2, 0.5)
    _mesh_obj("Ship_%d_band" % i, coll, lambda bm: _cyl(bm, beam * 0.135, 0.4, bx - bridge_len * 0.25, 0, 4.2, 20, caps=False), band, (0, cy, 0))
    if cargo:
        xa, xb = bx + bridge_len / 2 + 0.4, x1 - bow - 0.2
        n = 0
        x = xa
        while x + 4.0 <= xb:
            for side in (-1, 1):
                for lvl in range(rng.choice([1, 1, 2, 2, 3])):
                    _container(coll, rng, x + 2.0, cy + side * beam * 0.22, 3.9, beam * 0.42, 0.0, "S%d_%d" % (i, n), z0=1.04 + lvl * 1.0, hgt=1.0)
                    n += 1
            x += 4.1
    else:
        # Tug: a fender of black tyres all around.
        tyre = _simple_mat("LD_Tyre", (0.015, 0.015, 0.015), 0.0, 0.9)

        def fend(bm):
            for k in range(len(outline)):
                (ax, ay), (bx2, by) = outline[k], outline[(k + 1) % len(outline)]
                seg = math.hypot(bx2 - ax, by - ay)
                for t in range(int(seg / 0.7)):
                    f = (t + 0.5) * 0.7 / seg
                    _cyl(bm, 0.18, 0.16, ax + (bx2 - ax) * f, ay + (by - ay) * f, 0.8, 10)
        _mesh_obj("Ship_%d_fenders" % i, coll, fend, tyre, (0, cy, 0))


# --- Foundry -----------------------------------------------------------------

def _machine(coll, rng, x, y, w, h, i):
    """Factory machine: painted steel housing, a motor on top, a hazard plate."""
    cx, cy, lng, sht, rot = _footprint(rng, x, y, w, h, 1.0)
    body = _simple_mat("LD_MachBody_%d" % (i % 3), [(0.07, 0.1, 0.08), (0.12, 0.09, 0.04), (0.06, 0.07, 0.1)][i % 3], 0.45, 0.5)
    haz = _simple_mat("LD_Hazard", (0.6, 0.4, 0.02), 0.1, 0.6, ((0.015, 0.015, 0.015), 2.5, "DIAGONAL"))
    steel = _simple_mat("LD_Steel", (0.32, 0.33, 0.34), 0.85, 0.32)
    L, Wd = lng - 0.2, sht - 0.2
    _mesh_obj("Mach_%d" % i, coll, lambda bm: _cube(bm, L, Wd, 1.0, 0, 0, 0.5), body, (cx, cy, 0), rot, 0.05)
    _mesh_obj("Mach_%d_haz" % i, coll, lambda bm: _cube(bm, L * 0.28, Wd * 0.86, 0.04, L * 0.33, 0, 1.02), haz, (cx, cy, 0), rot)

    def motor(bm):
        r = Wd * 0.3
        _cyl(bm, r, L * 0.48, -L * 0.12, 0, 1.0 + r, 24, "X")
        _cyl(bm, r * 0.6, 0.12, -L * 0.12 - L * 0.26, 0, 1.0 + r, 20, "X")
        _cyl(bm, 0.1, 0.9, L * 0.1, Wd * 0.3, 1.45, 10)  # pipe stub
    _mesh_obj("Mach_%d_motor" % i, coll, motor, steel, (cx, cy, 0), rot, 0.02)


def _steel_crate(coll, rng, x, y, w, h, i):
    cx, cy, lng, sht, rot = _footprint(rng, x, y, w, h, 3.0)
    m = _simple_mat("LD_SteelCrate", (0.08, 0.1, 0.12), 0.6, 0.45)
    rib = _simple_mat("LD_Steel", (0.32, 0.33, 0.34), 0.85, 0.32)
    L, Wd = lng - 0.2, sht - 0.2
    _mesh_obj("SCrate_%d" % i, coll, lambda bm: _cube(bm, L, Wd, 1.1, 0, 0, 0.55), m, (cx, cy, 0), rot, 0.03)

    def ribs(bm):
        for f in (-0.3, 0.0, 0.3):
            _cube(bm, 0.08, Wd + 0.03, 1.12, L * f, 0, 0.56)
    _mesh_obj("SCrate_%d_ribs" % i, coll, ribs, rib, (cx, cy, 0), rot)


def _stack(coll, cx, cy, r, h, i):
    """Brick smokestack with a glowing throat."""
    brick = _simple_mat("LD_StackBrick", (0.17, 0.06, 0.035), 0.0, 0.85, ((0.1, 0.035, 0.02), 6.0, "Z"))
    dark = _simple_mat("LD_Soot", (0.015, 0.012, 0.01), 0.0, 0.9)
    glow = _emit_mat("LD_Glow", (0.85, 0.16, 0.02), 1.6)
    _mesh_obj("Stack_%d" % i, coll, lambda bm: _cyl(bm, r, h, 0, 0, h / 2, 32), brick, (cx, cy, 0))
    _mesh_obj("Stack_%d_rim" % i, coll, lambda bm: _cyl(bm, r * 1.08, 0.3, 0, 0, h - 0.1, 32), dark, (cx, cy, 0))
    _mesh_obj("Stack_%d_glow" % i, coll, lambda bm: _cyl(bm, r * 0.45, 0.02, 0, 0, h + 0.06, 24), glow, (cx, cy, 0))


def _pipes(coll, x0, x1, yc, z, i, vertical=False):
    """Two insulated pipes on stands along a roof (cell coords)."""
    steel = _simple_mat("LD_Pipe", (0.38, 0.38, 0.36), 0.7, 0.35)
    length = x1 - x0

    def b(bm):
        for off in (-0.3, 0.3):
            _cyl(bm, 0.2, length, 0, off, z, 16, "X")
        for t in range(int(length // 3) + 1):
            _cube(bm, 0.12, 1.0, z - H_MASS, -length / 2 + t * 3.0, 0, H_MASS + (z - H_MASS) / 2)
    if vertical:
        _mesh_obj("Pipes_%d" % i, coll, b, steel, (yc, -(x0 + length / 2), 0), math.radians(90))
    else:
        _mesh_obj("Pipes_%d" % i, coll, b, steel, (x0 + length / 2, -yc, 0))


# --- Cage --------------------------------------------------------------------

def _jersey(coll, rng, x, y, w, h, i):
    """Concrete jersey barrier(s) along the long side."""
    cx, cy, lng, sht, rot = _footprint(rng, x, y, w, h, 1.5)
    conc = _simple_mat("LD_Jersey", (0.3, 0.29, 0.27), 0.0, 0.9)
    stripe = _simple_mat("LD_JerseyStripe", (0.55, 0.06, 0.03), 0.0, 0.7, ((0.6, 0.6, 0.58), 1.5))
    hw = sht * 0.42
    prof = [(-hw, 0), (hw, 0), (hw, 0.1), (hw * 0.32, 0.32), (hw * 0.22, 0.85), (-hw * 0.22, 0.85), (-hw * 0.32, 0.32), (-hw, 0.1)]
    for k in range(int(round(lng / 2.0)) or 1):
        seg = lng / (int(round(lng / 2.0)) or 1)
        off = -lng / 2 + seg * (k + 0.5)
        ox, oy = math.cos(rot) * off, math.sin(rot) * off
        _mesh_obj("Jersey_%d_%d" % (i, k), coll, lambda bm: _extrude_x(bm, prof, seg - 0.08), conc, (cx + ox, cy + oy, 0), rot, 0.02)
        _mesh_obj("Jersey_%d_%d_s" % (i, k), coll, lambda bm: _cube(bm, seg - 0.1, hw * 0.46, 0.02, 0, 0, 0.86), stripe, (cx + ox, cy + oy, 0), rot)


def _sandbags(coll, rng, x, y, w, h, i):
    """Sandbags filling the footprint, two layers, staggered."""
    m = bpy.data.materials.get("LD_Sandbag")
    if m is None:
        def b(nt, bsdf):
            co = _coord(nt)
            n = _noise(nt, 14.0, 6, co)
            r = _ramp(nt, n.outputs["Fac"], (0.17, 0.14, 0.085), (0.26, 0.22, 0.14))
            nt.links.new(r.outputs[0], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 1.0
            _bump(nt, bsdf, n.outputs["Fac"], 0.3)
        m = _mat("LD_Sandbag", b)

    def bags(bm):
        bl, bw = 0.56, 0.34
        for lvl in range(3):
            z = 0.12 + lvl * 0.2
            rows = int((h - 0.1) / bw)
            for r in range(rows):
                yy = 0.05 + bw * (r + 0.5)
                stag = (bl / 2) if (r + lvl) % 2 else 0.0
                cols = int((w - 0.1 - stag) / bl)
                for c in range(cols):
                    xx = 0.05 + stag + bl * (c + 0.5)
                    sph = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.5)
                    bmesh.ops.scale(bm, vec=(bl * 0.98, bw * 0.98, 0.24), verts=sph["verts"])
                    bmesh.ops.rotate(bm, verts=sph["verts"], cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(rng.uniform(-0.12, 0.12), 3, "Z"))
                    bmesh.ops.translate(bm, vec=(xx, -yy, z), verts=sph["verts"])
    _mesh_obj("Sandbags_%d" % i, coll, bags, m, (x, -y, 0))


def build(project, map_name):
    d = json.load(open(os.path.join(project, "art", "maps", map_name + ".json"), encoding="utf-8"))
    th = THEMES.get(map_name, THEMES["dustline"])
    style = th.get("style", "desert")
    W, H = d["size"]
    grid = d["open"]
    cover = set()
    for x, y, w, h in d["cover"]:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                cover.add((xx, yy))

    sc = bpy.data.scenes.get("LD_" + map_name) or bpy.data.scenes.new("LD_" + map_name)
    _set_scene(sc)
    for ob in list(sc.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    coll = sc.collection
    mats = materials(th)
    rng = random.Random(7)

    def is_open(x, y):
        return 0 <= x < W and 0 <= y < H and grid[y][x] == "."

    def near_open(x, y):
        return any(is_open(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))

    # Ground.
    me = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in [(0, 0, 0), (W, 0, 0), (W, -H, 0), (0, -H, 0)]]
    bm.faces.new(vs)
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("Ground", me)
    g.data.materials.append(mats["ground"])
    coll.objects.link(g)

    # Bomb-site floors.
    for key, (x, y, w, h) in d["sites"].items():
        _box_mesh("Site_" + key, [(x, -(y + h), x + w, -y, 0.0, 0.01)], coll, mats["site"])

    # Walls (next to walkable space) and solid blocks, merged into row runs.
    wall_boxes, mass_cells = [], set()
    for y in range(H):
        x = 0
        while x < W:
            if is_open(x, y) or (x, y) in cover:
                x += 1
                continue
            kind = near_open(x, y)
            x0 = x
            while x < W and not is_open(x, y) and (x, y) not in cover and near_open(x, y) == kind:
                x += 1
            if kind:
                wall_boxes.append((x0, -(y + 1), x, -y, 0.0, H_WALL))
            else:
                for xx in range(x0, x):
                    mass_cells.add((xx, y))
    _box_mesh("Walls", wall_boxes, coll, mats["wall_mat"], bevel=0.06)

    # Sea: outer cells the theme marks as water (Harbor's north and south edges).
    water_cells = set()
    if th.get("water_at"):
        water_cells = {c for c in mass_cells if th["water_at"](c[0], c[1], W, H)}
        mass_cells -= water_cells
        runs = []
        for y in range(H):
            x = 0
            while x < W:
                if (x, y) not in water_cells:
                    x += 1
                    continue
                x0 = x
                while (x, y) in water_cells:
                    x += 1
                runs.append((x0, -(y + 1), x, -y, 0.0, 0.02))
        _box_mesh("Water", runs, coll, mats["water"])

    # Each connected block of solid cells is one building with its own roof.
    seen = set()
    blocks = []
    for c in sorted(mass_cells):
        if c in seen:
            continue
        stack, comp = [c], []
        seen.add(c)
        while stack:
            cx, cy = stack.pop()
            comp.append((cx, cy))
            for n in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if n in mass_cells and n not in seen:
                    seen.add(n)
                    stack.append(n)
        blocks.append(comp)
    prop_boxes, tanks, skylights = [], [], []
    n_stacks = n_pipes = 0
    for bi, comp in enumerate(blocks):
        style_r, mat = mats["roofs"][bi % len(mats["roofs"])]
        cells = set(comp)
        _box_mesh("Roof_%d" % bi, [(cx, -(cy + 1), cx + 1, -cy, 0.0, H_MASS) for (cx, cy) in comp], coll, mat)
        inner = sorted(c for c in comp if all((c[0] + dx, c[1] + dy) in cells for dx in (-1, 0, 1) for dy in (-1, 0, 1)))
        outer = any(cx in (0, W - 1) or cy in (0, H - 1) for cx, cy in comp)
        if style_r == "corrugated" and not outer:
            # Skylight strips across the roof sheets.
            for (cx, cy) in inner:
                if cy % 5 == 2 and cx % 7 != 0:
                    skylights.append((cx, -(cy + 0.8), cx + 1, -(cy + 0.2), H_MASS, H_MASS + 0.04))
        if style == "industrial" and inner:
            # Pipes along the longest straight run of roof, stacks on big halls.
            best = (0, None)
            for vertical in (False, True):
                lines = {}
                for (cx, cy) in inner:
                    lines.setdefault(cx if vertical else cy, []).append(cy if vertical else cx)
                for k, vals in lines.items():
                    vals.sort()
                    s0 = prev = vals[0]
                    for v in vals[1:] + [None]:
                        if v is not None and v == prev + 1:
                            prev = v
                            continue
                        if prev - s0 + 1 > best[0]:
                            best = (prev - s0 + 1, (vertical, k, s0, prev + 1))
                        if v is not None:
                            s0 = prev = v
            if best[0] >= 6 and rng.random() < 0.8:
                vertical, k, a, b = best[1]
                _pipes(coll, a + 0.3, b - 0.3, k + 0.5, H_MASS + 0.45, n_pipes, vertical)
                n_pipes += 1
            if len(inner) >= 30 and not outer:
                picks = rng.sample(inner, min(len(inner), 40))
                placed = []
                for (cx, cy) in picks:
                    if len(placed) >= (2 if len(inner) > 160 else 1):
                        break
                    if all(abs(cx - px) + abs(cy - py) > 8 for px, py in placed):
                        placed.append((cx, cy))
                        _stack(coll, cx + 0.5, -(cy + 0.5), rng.choice([0.8, 0.95, 1.1]), rng.choice([3.4, 4.0]), n_stacks)
                        n_stacks += 1
        # Props on flat roofs, away from the edges: AC units, vents, water tanks.
        if style_r in ("concrete", "tar", "gravel"):
            rng.shuffle(inner)
            for (cx, cy) in inner[:max(1, len(inner) // 18)]:
                if rng.random() < 0.3:
                    tanks.append((cx + 0.5, -(cy + 0.5)))
                else:
                    w = rng.choice([0.6, 0.8])
                    prop_boxes.append((cx + 0.5 - w / 2, -(cy + 0.5) - w / 2, cx + 0.5 + w / 2, -(cy + 0.5) + w / 2, H_MASS, H_MASS + 0.35))
    if prop_boxes:
        _box_mesh("RoofProps", prop_boxes, coll, mats["metal"], bevel=0.03)
    if skylights:
        _box_mesh("Skylights", skylights, coll, _simple_mat("LD_Skylight", (0.05, 0.07, 0.08), 0.3, 0.12), bevel=0.01)
    for i, (tx, ty) in enumerate(tanks):
        me = bpy.data.meshes.new("Tank_%d" % i)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.45, radius2=0.45, depth=0.6)
        bm.to_mesh(me)
        bm.free()
        t = bpy.data.objects.new("Tank_%d" % i, me)
        t.location = (tx, ty, H_MASS + 0.3)
        t.data.materials.append(mats["metal"])
        coll.objects.link(t)

    # Ships moored in the water (cell coords: x0, x1, centre row, beam, cargo).
    for si, sh in enumerate(th.get("ships", [])):
        _ship(coll, rng, *sh[:4], si, sh[4])

    # Cover (blocks movement and bullets in game), dressed per theme.
    crate_boxes = []
    counts = {}

    def bump(k):
        counts[k] = counts.get(k, 0) + 1
        return counts[k] - 1

    for ci, (x, y, w, h) in enumerate(d["cover"]):
        lng, sht = max(w, h), min(w, h)
        if style == "docks":
            if lng >= 3 and lng != sht:
                cx, cy, L, S, rot = _footprint(rng, x, y, w, h, 1.5)
                _container(coll, rng, cx, cy, L - 0.12, S - 0.14, rot, bump("cont"))
                continue
            if (w, h) == (2, 2) and rng.random() < 0.5:
                _spool(coll, rng, x + 1.0, -(y + 1.0), 0.92, bump("spool"))
                continue
        elif style == "industrial":
            if lng >= 3:
                _machine(coll, rng, x, y, w, h, bump("mach"))
                continue
            if rng.random() < 0.55:
                _steel_crate(coll, rng, x, y, w, h, bump("scrate"))
            else:
                for yy in range(y, y + h):
                    for xx in range(x, x + w):
                        _barrel(coll, mats, rng, xx + 0.5, -(yy + 0.5), bump("barrel"))
            continue
        elif style == "yard":
            if sht == 1:
                _jersey(coll, rng, x, y, w, h, bump("jersey"))
                continue
            if rng.random() < 0.55:
                _sandbags(coll, rng, x, y, w, h, bump("sandbags"))
                continue
        else:
            if (w, h) in ((3, 2), (2, 3), (2, 4), (4, 2)):
                _car(coll, mats, rng, x, y, w, h, bump("car"))
                continue
            if min(w, h) == 1 or (w * h <= 4 and rng.random() < 0.45):
                for yy in range(y, y + h):
                    for xx in range(x, x + w):
                        _barrel(coll, mats, rng, xx + 0.5, -(yy + 0.5), bump("barrel"))
                continue
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                hgt = H_CRATE * (1.0 if rng.random() < 0.7 else 1.35)
                crate_boxes.append((xx + 0.04, -(yy + 1) + 0.04, xx + 0.96, -yy - 0.04, 0.0, hgt))
    if crate_boxes:
        _box_mesh("Crates", crate_boxes, coll, mats["crate"], bevel=0.05)

    # Painted safety lines along the foot of the walls (not on desert sand).
    if style != "desert":
        strips = []
        for y in range(H):
            for x in range(W):
                if not is_open(x, y) or (x, y) in cover:
                    continue
                for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                    nx, ny = x + dx, y + dy
                    if is_open(nx, ny) or (nx, ny) in cover:
                        continue
                    if dy:
                        yy = -(y + (0.0 if dy < 0 else 1.0)) - dy * -0.32
                        strips.append((x, yy - 0.06, x + 1, yy + 0.06, 0.0, 0.012))
                    else:
                        xx = x + (0.0 if dx < 0 else 1.0) - dx * 0.32
                        strips.append((xx - 0.06, -(y + 1), xx + 0.06, -y, 0.0, 0.012))
        if strips:
            _box_mesh("Lines", strips, coll, mats["line"])

    # Awnings: striped canvas off building walls over wide streets (decoration
    # only; drawn under the players in game).
    awnings = []
    if style == "desert":
        taken = set()
        for y in range(H):
            for x in range(W):
                if is_open(x, y) or (x, y) in cover:
                    continue
                for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                    # Street must be open for 4 cells out from this wall.
                    if not all(is_open(x + dx * k, y + dy * k) for k in range(1, 5)):
                        continue
                    ax, ay = (1, 0) if dx == 0 else (0, 1)  # along the wall
                    span = [(x + ax * k, y + ay * k) for k in range(3)]
                    if not all(not is_open(sx, sy) and (sx, sy) not in cover and is_open(sx + dx, sy + dy) for sx, sy in span):
                        continue
                    if any((sx + ox, sy + oy) in taken for sx, sy in span for ox in range(-9, 10) for oy in range(-9, 10)):
                        continue
                    if rng.random() > 0.05:
                        continue
                    awnings.append((x, y, dx, dy, ax, ay))
                    taken.update(span)
        for i, a in enumerate(awnings):
            _awning(coll, mats, rng, i, *a)

    # Site letters painted on the floor.
    for key, (x, y, w, h) in d["sites"].items():
        cu = bpy.data.curves.new("Letter_" + key, "FONT")
        cu.body = key
        cu.size = min(w, h) * 0.55
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        ob = bpy.data.objects.new("Letter_" + key, cu)
        ob.location = (x + w / 2, -(y + h / 2), 0.02)
        ob.data.materials.append(mats["paint"])
        coll.objects.link(ob)

    # Light.
    sun_d = bpy.data.lights.new("Sun", "SUN")
    sun_d.energy = th["sun_strength"]
    sun_d.angle = math.radians(3)
    sun = bpy.data.objects.new("Sun", sun_d)
    sun.rotation_euler = th["sun_rot"]
    coll.objects.link(sun)
    world = bpy.data.worlds.get("LD_World" + th.get("tag", "")) or bpy.data.worlds.new("LD_World" + th.get("tag", ""))
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*th["sky"], 1)
    bg.inputs[1].default_value = 0.5

    # Camera: straight down, orthographic, the whole map.
    cam_d = bpy.data.cameras.new("TopCam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = max(W, H)
    cam_d.sensor_fit = "HORIZONTAL" if W >= H else "VERTICAL"
    cam_d.clip_end = 100
    cam = bpy.data.objects.new("TopCam", cam_d)
    cam.location = (W / 2, -H / 2, 30)
    coll.objects.link(cam)
    sc.camera = cam

    r = sc.render
    r.resolution_x = W * PX_PER_CELL
    r.resolution_y = H * PX_PER_CELL
    r.resolution_percentage = 100
    r.engine = "CYCLES"
    sc.cycles.device = "GPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    r.image_settings.file_format = "PNG"
    r.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    counts.update({"walls": len(wall_boxes), "blocks": len(blocks), "crates": len(crate_boxes), "stacks": n_stacks, "pipes": n_pipes,
                   "water": len(water_cells), "awnings": len(awnings), "res": [r.resolution_x, r.resolution_y]})
    return counts


def _gpu():
    """Use the GPU (OptiX, else CUDA) for Cycles when running headless."""
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


def render(project, map_name, percent=100, path=None):
    sc = bpy.data.scenes["LD_" + map_name]
    _set_scene(sc)
    sc.render.resolution_percentage = percent
    out = path or os.path.join(project, "assets", "maps", map_name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sc.render.filepath = out
    bpy.ops.render.render(scene=sc.name, write_still=True)
    sc.render.resolution_percentage = 100
    return out


# Headless: blender -b art/blender/maps.blend --python art/blender/build_map.py -- <project> <map>... [--percent N] [--out DIR] [--save]
if __name__ == "__main__" and "--" in __import__("sys").argv:
    _args = __import__("sys").argv[__import__("sys").argv.index("--") + 1:]
    _proj, _names, _pct, _out, _save = _args[0], [], 100, None, False
    _it = iter(_args[1:])
    for _a in _it:
        if _a == "--percent":
            _pct = int(next(_it))
        elif _a == "--out":
            _out = next(_it)
        elif _a == "--save":
            _save = True
        else:
            _names.append(_a)
    print("device:", _gpu())
    for _n in _names:
        print(_n, build(_proj, _n))
        print("wrote", render(_proj, _n, _pct, os.path.join(_out, _n + ".png") if _out else None))
    if _save:
        bpy.ops.wm.save_mainfile()
