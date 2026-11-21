"""Lockdown character and weapon models (Blender 5.x), stylised low-poly.

Builds the scene "LD_models": the CT and T soldiers holding their starting
rifles, and a display of all 21 guns grouped like the buy menu, each labelled.
Guns face +X; 1 unit = 1 m (real-world sizes).

Run inside Blender:
    ns = {}; exec(open(r"<project>/art/blender/build_models.py").read(), ns); ns["build"]()
"""
import bpy, bmesh, math
from mathutils import Matrix

# --- Materials ----------------------------------------------------------------

def mat(name, color, metallic=0.0, rough=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m


def mats():
    return {
        "polymer": mat("LDG_Polymer", (0.025, 0.025, 0.028), 0.0, 0.55),
        "steel": mat("LDG_Steel", (0.05, 0.05, 0.055), 0.85, 0.35),
        "silver": mat("LDG_Silver", (0.55, 0.56, 0.58), 1.0, 0.22),
        "wood": mat("LDG_Wood", (0.22, 0.09, 0.03), 0.0, 0.5),
        "tan": mat("LDG_Tan", (0.36, 0.28, 0.16), 0.0, 0.6),
        "od": mat("LDG_OD", (0.09, 0.12, 0.05), 0.0, 0.6),
        "grey": mat("LDG_Grey", (0.12, 0.13, 0.14), 0.3, 0.45),
        "glass": mat("LDG_Glass", (0.02, 0.06, 0.08), 0.5, 0.05),
        "red": mat("LDG_RedDot", (0.9, 0.05, 0.02), 0.0, 0.3),
        "label": mat("LDG_Label", (0.85, 0.85, 0.8), 0.0, 0.8),
        "table": mat("LDG_Table", (0.08, 0.085, 0.09), 0.0, 0.7),
        # Characters.
        "skin": mat("LDC_Skin", (0.55, 0.36, 0.25), 0.0, 0.6),
        "ct_cloth": mat("LDC_CT_Cloth", (0.045, 0.06, 0.10), 0.0, 0.8),
        "ct_vest": mat("LDC_CT_Vest", (0.09, 0.12, 0.17), 0.0, 0.7),
        "ct_helmet": mat("LDC_CT_Helmet", (0.07, 0.09, 0.12), 0.1, 0.5),
        "ct_accent": mat("LDC_CT_Accent", (0.10, 0.35, 0.90), 0.0, 0.4),
        "t_cloth": mat("LDC_T_Cloth", (0.22, 0.17, 0.10), 0.0, 0.85),
        "t_jacket": mat("LDC_T_Jacket", (0.10, 0.07, 0.045), 0.0, 0.8),
        "t_mask": mat("LDC_T_Mask", (0.02, 0.02, 0.02), 0.0, 0.9),
        "t_accent": mat("LDC_T_Accent", (0.85, 0.40, 0.08), 0.0, 0.6),
        "boots": mat("LDC_Boots", (0.03, 0.025, 0.02), 0.0, 0.6),
        "gloves": mat("LDC_Gloves", (0.02, 0.02, 0.02), 0.0, 0.7),
        "goggles": mat("LDC_Goggles", (0.05, 0.25, 0.30), 0.6, 0.1),
    }


# --- Geometry helpers -----------------------------------------------------------

def part(coll, parent, name, material, size, loc, rot=(0, 0, 0), shape="box", bevel=0.0, segs=16, taper=1.0):
    """size: box (x, y, z); cyl (radius, length) along X; sphere (rx, ry, rz)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    if shape == "box":
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=r["verts"])
    elif shape == "cyl":
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=size[0], radius2=size[0] * taper, depth=size[1])
        bmesh.ops.rotate(bm, verts=r["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif shape == "zcyl":
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=size[0], radius2=size[0] * taper, depth=size[1])
    elif shape == "sphere":
        r = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=1.0)
        bmesh.ops.scale(bm, vec=size, verts=r["verts"])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = shape in ("cyl", "zcyl", "sphere")
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    ob.data.materials.append(material)
    coll.objects.link(ob)
    ob.parent = parent
    if bevel > 0:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        m.limit_method = "ANGLE"
    return ob


def empty(coll, name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    e.location = loc
    e.rotation_euler = [math.radians(a) for a in rot]
    coll.objects.link(e)
    e.parent = parent
    return e


def label(coll, text, loc, size=0.045, material=None):
    cu = bpy.data.curves.new("Label_" + text, "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("Label_" + text, cu)
    ob.location = loc
    ob.rotation_euler = (math.radians(90), 0, 0)
    if material:
        ob.data.materials.append(material)
    coll.objects.link(ob)
    return ob


# --- Guns -------------------------------------------------------------------
# Long guns: receiver centred on the root; barrel and handguard forward (+X),
# stock back, grip and magazine below. Bullpups swap grip and magazine.

GUNS = [
    # Pistols
    {"key": "pk9", "name": "PK-9", "kind": "pistol", "len": 0.19, "body": "polymer", "slide": "steel"},
    {"key": "sentry", "name": "Sentry .45", "kind": "pistol", "len": 0.21, "body": "tan", "slide": "steel"},
    {"key": "duster", "name": "Duster P7", "kind": "pistol", "len": 0.20, "body": "polymer", "slide": "silver"},
    {"key": "viper", "name": "Viper MP", "kind": "pistol", "len": 0.22, "body": "polymer", "slide": "steel", "ext_mag": True, "stub_stock": True},
    {"key": "falcon", "name": "Falcon 5.7", "kind": "pistol", "len": 0.215, "body": "grey", "slide": "grey"},
    {"key": "magnum", "name": "Magnum .50", "kind": "pistol", "len": 0.27, "body": "silver", "slide": "silver", "big": True},
    # SMGs
    {"key": "hornet", "name": "Hornet M10", "kind": "long", "rec": (0.22, 0.10, 0.05), "barrel": 0.06, "guard": 0.0, "stock": "wire",
     "stock_len": 0.18, "mag": "grip", "body": "polymer", "muzzle": "none"},
    {"key": "kestrel", "name": "Kestrel K9", "kind": "long", "rec": (0.26, 0.075, 0.05), "barrel": 0.10, "guard": 0.14, "stock": "skeleton",
     "stock_len": 0.20, "mag": "curved_short", "body": "polymer", "muzzle": "none"},
    {"key": "bulldog", "name": "Bulldog .45", "kind": "long", "rec": (0.30, 0.085, 0.055), "barrel": 0.09, "guard": 0.12, "stock": "full",
     "stock_len": 0.22, "mag": "straight", "body": "tan", "muzzle": "none"},
    {"key": "swarm", "name": "Swarm 50", "kind": "long", "rec": (0.46, 0.11, 0.07), "barrel": 0.04, "guard": 0.0, "stock": "none",
     "stock_len": 0.0, "mag": "top", "body": "od", "bullpup": True, "muzzle": "none"},
    # Shotguns
    {"key": "breacher", "name": "Breacher Pump", "kind": "long", "rec": (0.24, 0.07, 0.045), "barrel": 0.48, "barrel_r": 0.013, "guard": 0.20,
     "stock": "wood", "stock_len": 0.34, "mag": "tube", "body": "steel", "furniture": "wood", "muzzle": "none"},
    {"key": "tempest", "name": "Tempest Auto-12", "kind": "long", "rec": (0.30, 0.09, 0.055), "barrel": 0.36, "barrel_r": 0.013, "guard": 0.22,
     "stock": "full", "stock_len": 0.28, "mag": "box_big", "body": "polymer", "muzzle": "brake"},
    # Machine gun
    {"key": "hammer", "name": "Hammer LMG", "kind": "long", "rec": (0.36, 0.11, 0.07), "barrel": 0.46, "barrel_r": 0.014, "guard": 0.18,
     "stock": "full", "stock_len": 0.30, "mag": "drum", "body": "od", "muzzle": "brake", "bipod": True, "handle": True},
    # Rifles
    {"key": "kodiak", "name": "Kodiak AR", "kind": "long", "rec": (0.30, 0.075, 0.05), "barrel": 0.30, "guard": 0.16, "stock": "wood",
     "stock_len": 0.30, "mag": "curved", "body": "steel", "furniture": "wood", "muzzle": "brake"},
    {"key": "lancer", "name": "Lancer F2", "kind": "long", "rec": (0.52, 0.09, 0.06), "barrel": 0.18, "guard": 0.0, "stock": "none",
     "stock_len": 0.0, "mag": "straight", "body": "grey", "bullpup": True, "handle_long": True, "muzzle": "none"},
    {"key": "raptor", "name": "Raptor 762", "kind": "long", "rec": (0.32, 0.08, 0.05), "barrel": 0.32, "guard": 0.20, "stock": "full",
     "stock_len": 0.30, "mag": "straight", "body": "polymer", "muzzle": "brake", "optic": "red"},
    {"key": "guardian", "name": "Guardian 556", "kind": "long", "rec": (0.28, 0.075, 0.05), "barrel": 0.28, "guard": 0.20, "stock": "adjust",
     "stock_len": 0.26, "mag": "straight", "body": "polymer", "muzzle": "none", "optic": "red"},
    {"key": "talon", "name": "Talon SR", "kind": "long", "rec": (0.50, 0.09, 0.06), "barrel": 0.24, "guard": 0.0, "stock": "none",
     "stock_len": 0.0, "mag": "straight", "body": "od", "bullpup": True, "optic": "scope_short", "muzzle": "none"},
    {"key": "overwatch", "name": "Overwatch SR", "kind": "long", "rec": (0.30, 0.08, 0.05), "barrel": 0.32, "guard": 0.18, "stock": "adjust",
     "stock_len": 0.26, "mag": "straight", "body": "tan", "optic": "scope_short", "muzzle": "supp"},
    # Snipers
    {"key": "pathfinder", "name": "Pathfinder", "kind": "long", "rec": (0.26, 0.06, 0.04), "barrel": 0.46, "barrel_r": 0.009, "guard": 0.22,
     "stock": "thumb", "stock_len": 0.30, "mag": "box_small", "body": "grey", "optic": "scope", "muzzle": "brake", "bolt": True},
    {"key": "longbow", "name": "Longbow .338", "kind": "long", "rec": (0.36, 0.09, 0.06), "barrel": 0.56, "barrel_r": 0.013, "guard": 0.26,
     "stock": "thumb", "stock_len": 0.36, "mag": "box_small", "body": "od", "optic": "scope_big", "muzzle": "brake", "bolt": True, "bipod": True},
]


def build_pistol(coll, root, m, g):
    L = g["len"] * (1.15 if g.get("big") else 1.0)
    h = 0.038 if not g.get("big") else 0.05
    w = 0.03 if not g.get("big") else 0.038
    n = g["key"]
    part(coll, root, n + "_slide", m[g["slide"]], (L, w, h), (L * 0.1, 0, 0.025), bevel=0.004)
    part(coll, root, n + "_frame", m[g["body"]], (L * 0.8, w * 0.92, 0.025), (L * 0.05, 0, -0.005), bevel=0.003)
    part(coll, root, n + "_grip", m[g["body"]], (0.034, w * 0.95, 0.11), (-L * 0.22, 0, -0.06), (0, -14, 0), bevel=0.006)
    part(coll, root, n + "_guard", m[g["body"]], (0.045, w * 0.4, 0.008), (-L * 0.02, 0, -0.04), bevel=0.002)
    part(coll, root, n + "_muzzle", m["steel"], (0.006, 0.02), (L * 0.6, 0, 0.03), shape="cyl", segs=12)
    if g.get("big"):
        part(coll, root, n + "_barrel", m["silver"], (0.012, 0.06), (L * 0.62, 0, 0.022), shape="cyl", segs=12)
    if g.get("ext_mag"):
        part(coll, root, n + "_mag", m["steel"], (0.028, w * 0.8, 0.12), (-L * 0.26, 0, -0.16), (0, -14, 0), bevel=0.003)
    if g.get("stub_stock"):
        part(coll, root, n + "_stock", m["polymer"], (0.12, 0.012, 0.014), (-L * 0.55, 0, 0.0), bevel=0.003)


def build_long(coll, root, m, g):
    n = g["key"]
    rl, rh, rw = g["rec"]
    body = m[g["body"]]
    furn = m[g.get("furniture", g["body"])]
    bull = g.get("bullpup", False)
    front = rl / 2
    # Receiver.
    part(coll, root, n + "_receiver", body, (rl, rw, rh), (0, 0, 0), bevel=0.006)
    part(coll, root, n + "_rail", m["steel"], (rl * 0.7, rw * 0.5, 0.012), (rl * 0.05, 0, rh / 2 + 0.006), bevel=0.002)
    # Handguard and barrel.
    gl = g.get("guard", 0.0)
    if gl > 0:
        part(coll, root, n + "_guard", furn, (gl, rw * 1.1, rh * 0.8), (front + gl / 2, 0, -rh * 0.05), bevel=0.008)
    br = g.get("barrel_r", 0.010)
    bl = g["barrel"] + gl
    part(coll, root, n + "_barrel", m["steel"], (br, bl), (front + bl / 2, 0, rh * 0.12), shape="cyl", segs=14)
    tip = front + bl
    mz = g.get("muzzle", "none")
    if mz == "brake":
        part(coll, root, n + "_brake", m["steel"], (br * 1.7, 0.06), (tip + 0.03, 0, rh * 0.12), shape="cyl", segs=12, bevel=0.002)
    elif mz == "supp":
        part(coll, root, n + "_supp", m["polymer"], (br * 2.2, 0.16), (tip + 0.08, 0, rh * 0.12), shape="cyl", segs=16)
    # Stock.
    sl = g.get("stock_len", 0.0)
    st = g.get("stock", "none")
    back = -rl / 2
    if st in ("full", "wood"):
        part(coll, root, n + "_stock", furn if st == "wood" else body, (sl, rw * 0.9, rh * 1.15), (back - sl / 2, 0, -rh * 0.25), (0, 4, 0), bevel=0.01)
        part(coll, root, n + "_butt", m["polymer"], (0.02, rw, rh * 1.45), (back - sl, 0, -rh * 0.35), bevel=0.004)
    elif st == "thumb":
        part(coll, root, n + "_stock", body, (sl, rw * 0.9, rh * 1.0), (back - sl / 2, 0, -rh * 0.15), bevel=0.01)
        part(coll, root, n + "_cheek", body, (sl * 0.5, rw * 0.8, 0.03), (back - sl * 0.55, 0, rh * 0.45), bevel=0.006)
        part(coll, root, n + "_butt", m["polymer"], (0.025, rw, rh * 1.9), (back - sl, 0, -rh * 0.3), bevel=0.005)
    elif st == "adjust":
        part(coll, root, n + "_tube", m["steel"], (0.016, sl), (back - sl / 2, 0, 0), shape="cyl", segs=12)
        part(coll, root, n + "_stock", body, (sl * 0.45, rw * 0.9, rh * 1.25), (back - sl * 0.8, 0, -rh * 0.2), bevel=0.008)
    elif st in ("skeleton", "wire"):
        for z in (rh * 0.25, -rh * 0.35):
            part(coll, root, n + "_strut%d" % int(z * 1000), m["steel"], (sl, 0.01, 0.01), (back - sl / 2, 0, z), bevel=0.002)
        part(coll, root, n + "_butt", m["polymer"], (0.015, rw * 0.9, rh * 1.0), (back - sl, 0, -rh * 0.05), bevel=0.003)
    # Grip and magazine.
    grip_x = rl * 0.18 if bull else -rl * 0.3
    mag_x = -rl * 0.22 if bull else rl * 0.12
    part(coll, root, n + "_grip", m["polymer"], (0.035, rw * 0.85, 0.11), (grip_x, 0, -rh / 2 - 0.045), (0, -16, 0), bevel=0.006)
    mg = g.get("mag", "straight")
    if mg == "curved":
        for i in range(3):
            part(coll, root, n + "_mag%d" % i, m["steel"], (0.034, rw * 0.7, 0.07), (mag_x + 0.02 * i, 0, -rh / 2 - 0.035 - 0.055 * i), (0, 10 + 10 * i, 0), bevel=0.003)
    elif mg == "curved_short":
        for i in range(2):
            part(coll, root, n + "_mag%d" % i, m["steel"], (0.03, rw * 0.6, 0.07), (mag_x + 0.015 * i, 0, -rh / 2 - 0.035 - 0.055 * i), (0, 8 + 10 * i, 0), bevel=0.003)
    elif mg == "straight":
        part(coll, root, n + "_mag", m["steel"], (0.032, rw * 0.7, 0.14), (mag_x, 0, -rh / 2 - 0.06), (0, 6, 0), bevel=0.003)
    elif mg == "box_small":
        part(coll, root, n + "_mag", m["steel"], (0.06, rw * 0.7, 0.05), (mag_x, 0, -rh / 2 - 0.02), bevel=0.003)
    elif mg == "box_big":
        part(coll, root, n + "_mag", m["polymer"], (0.07, rw * 0.8, 0.12), (mag_x, 0, -rh / 2 - 0.05), bevel=0.005)
    elif mg == "drum":
        part(coll, root, n + "_drum", m["polymer"], (0.07, 0.06), (mag_x, 0, -rh / 2 - 0.06), rot=(0, 0, 90), shape="cyl", segs=24)
    elif mg == "tube":
        part(coll, root, n + "_tube", m["steel"], (0.011, g["barrel"] * 0.85), (front + g["barrel"] * 0.42, 0, rh * 0.12 - 0.026), shape="cyl", segs=12)
    elif mg == "top":
        part(coll, root, n + "_topmag", m["glass"], (rl * 0.75, rw * 0.9, 0.03), (rl * 0.05, 0, rh / 2 + 0.018), bevel=0.006)
    elif mg == "grip":
        part(coll, root, n + "_mag", m["steel"], (0.03, rw * 0.7, 0.06), (grip_x - 0.012, 0, -rh / 2 - 0.12), (0, -16, 0), bevel=0.003)
    # Optics and extras.
    opt = g.get("optic", "")
    top = rh / 2 + 0.012
    if opt == "red":
        part(coll, root, n + "_dot", m["polymer"], (0.05, 0.03, 0.035), (rl * 0.05, 0, top + 0.02), bevel=0.004)
        part(coll, root, n + "_dotlens", m["red"], (0.002, 0.02, 0.02), (rl * 0.05 + 0.026, 0, top + 0.024))
    elif opt.startswith("scope"):
        sl2 = {"scope": 0.28, "scope_short": 0.2, "scope_big": 0.36}[opt]
        sr = {"scope": 0.016, "scope_short": 0.017, "scope_big": 0.021}[opt]
        z = top + sr + 0.02
        part(coll, root, n + "_scope", m["polymer"], (sr, sl2), (0, 0, z), shape="cyl", segs=16)
        part(coll, root, n + "_bell_f", m["polymer"], (sr * 1.4, 0.06), (sl2 / 2, 0, z), shape="cyl", segs=16, taper=0.75)
        part(coll, root, n + "_bell_r", m["polymer"], (sr * 1.25, 0.05), (-sl2 / 2, 0, z), shape="cyl", segs=16, taper=0.8)
        part(coll, root, n + "_lens", m["glass"], (sr * 1.3, 0.004), (sl2 / 2 + 0.031, 0, z), shape="cyl", segs=16)
        for x in (-sl2 * 0.25, sl2 * 0.25):
            part(coll, root, n + "_ring%d" % int(x * 1000), m["steel"], (0.015, 0.02, sr + 0.02), (x, 0, top + (sr + 0.02) / 2), bevel=0.003)
    if g.get("handle"):
        part(coll, root, n + "_handle", m["steel"], (0.09, 0.015, 0.035), (0, 0, top + 0.03), bevel=0.004)
    if g.get("handle_long"):
        part(coll, root, n + "_handle", body, (rl * 0.75, 0.018, 0.03), (rl * 0.1, 0, top + 0.035), bevel=0.006)
        for x in (-rl * 0.25, rl * 0.42):
            part(coll, root, n + "_hpost%d" % int(x * 1000), body, (0.025, 0.018, 0.04), (x, 0, top + 0.012), bevel=0.003)
    if g.get("bolt"):
        part(coll, root, n + "_bolt", m["steel"], (0.008, 0.05), (-rl * 0.15, rw / 2 + 0.025, rh * 0.15), rot=(0, 0, 90), shape="cyl", segs=10)
        part(coll, root, n + "_knob", m["steel"], (0.013, 0.013, 0.013), (-rl * 0.15, rw / 2 + 0.05, rh * 0.15), shape="sphere", segs=10)
    if g.get("bipod"):
        for s in (-1, 1):
            part(coll, root, n + "_leg%d" % s, m["steel"], (0.007, 0.22), (front + gl * 0.7, s * 0.03, -rh / 2 - 0.09), rot=(s * 18, 90, 0), shape="cyl", segs=8)


def build_gun(coll, m, g, loc, rot=(0, 0, 0), parent=None):
    root = empty(coll, "Gun_" + g["key"], loc, parent, rot)
    (build_pistol if g["kind"] == "pistol" else build_long)(coll, root, m, g)
    return root


# --- Characters -----------------------------------------------------------------
# Standing at the origin, facing +X, holding a rifle at the ready.

def build_soldier(coll, m, side, loc, gun_key):
    ct = side == "CT"
    root = empty(coll, "Player_" + side, loc)
    cloth = m["ct_cloth"] if ct else m["t_cloth"]
    top = m["ct_vest"] if ct else m["t_jacket"]
    acc = m["ct_accent"] if ct else m["t_accent"]
    n = side + "_"
    # Legs and boots (slight stride).
    for s, fx in ((-1, 0.06), (1, -0.05)):
        part(coll, root, n + "leg%d" % s, cloth, (0.17, 0.15, 0.78), (fx, s * 0.1, 0.48), (0, -4 * s, 0), bevel=0.04)
        part(coll, root, n + "boot%d" % s, m["boots"], (0.28, 0.13, 0.11), (fx + 0.05, s * 0.1, 0.06), bevel=0.03)
        part(coll, root, n + "knee%d" % s, m["boots"] if ct else cloth, (0.06, 0.12, 0.1), (fx + 0.09, s * 0.1, 0.5), bevel=0.02)
    part(coll, root, n + "belt", m["boots"], (0.26, 0.38, 0.07), (0, 0, 0.9), bevel=0.02)
    # Torso and vest / jacket.
    part(coll, root, n + "torso", cloth, (0.24, 0.40, 0.5), (0, 0, 1.18), bevel=0.06)
    part(coll, root, n + "vest", top, (0.30, 0.44, 0.42), (0.01, 0, 1.2), bevel=0.05)
    for i, y in enumerate((-0.12, 0.0, 0.12)):
        part(coll, root, n + "pouch%d" % i, top, (0.07, 0.1, 0.12), (0.17, y, 1.1), bevel=0.015)
    part(coll, root, n + "shoulder_l", acc, (0.06, 0.04, 0.1), (0.0, 0.25, 1.33), bevel=0.01)  # team patch
    if not ct:
        part(coll, root, n + "pack", m["t_jacket"], (0.16, 0.32, 0.36), (-0.22, 0, 1.2), bevel=0.04)
        part(coll, root, n + "scarf", acc, (0.2, 0.24, 0.07), (0.02, 0, 1.43), bevel=0.03)
    else:
        part(coll, root, n + "pack", m["ct_vest"], (0.08, 0.36, 0.32), (-0.18, 0, 1.22), bevel=0.03)
    # Head.
    part(coll, root, n + "neck", m["skin"] if ct else m["t_mask"], (0.06, 0.08), (0, 0, 1.48), shape="zcyl", segs=12)
    part(coll, root, n + "head", m["skin"] if ct else m["t_mask"], (0.11, 0.1, 0.12), (0.01, 0, 1.62), shape="sphere", segs=16)
    if ct:
        part(coll, root, n + "helmet", m["ct_helmet"], (0.135, 0.125, 0.095), (-0.005, 0, 1.68), shape="sphere", segs=18)
        part(coll, root, n + "goggles", m["goggles"], (0.04, 0.17, 0.035), (0.1, 0, 1.64), bevel=0.012)
        part(coll, root, n + "nvg", m["steel"], (0.05, 0.04, 0.05), (0.12, 0, 1.74), bevel=0.01)
    else:
        part(coll, root, n + "eyes", m["skin"], (0.02, 0.14, 0.03), (0.1, 0, 1.64), bevel=0.01)
        part(coll, root, n + "cap", m["t_cloth"], (0.12, 0.115, 0.06), (0.0, 0, 1.71), shape="sphere", segs=16)
        part(coll, root, n + "brim", m["t_cloth"], (0.09, 0.14, 0.012), (0.11, 0, 1.70), bevel=0.005)
    # Arms reaching to the rifle (right hand on grip, left on handguard).
    sh_r, sh_l = (0.02, -0.24, 1.32), (0.02, 0.24, 1.32)
    part(coll, root, n + "uarm_r", top, (0.3, 0.1, 0.1), (0.08, -0.25, 1.2), (0, 55, 20), bevel=0.03)
    part(coll, root, n + "farm_r", cloth, (0.26, 0.085, 0.085), (0.22, -0.18, 1.12), (0, -10, 35), bevel=0.025)
    part(coll, root, n + "hand_r", m["gloves"], (0.07, 0.06, 0.08), (0.32, -0.1, 1.12), bevel=0.02)
    part(coll, root, n + "uarm_l", top, (0.3, 0.1, 0.1), (0.1, 0.25, 1.2), (0, 50, -25), bevel=0.03)
    part(coll, root, n + "farm_l", cloth, (0.34, 0.085, 0.085), (0.34, 0.13, 1.17), (0, -5, -38), bevel=0.025)
    part(coll, root, n + "hand_l", m["gloves"], (0.07, 0.06, 0.07), (0.5, 0.02, 1.2), bevel=0.02)
    # The rifle, held across the chest at the ready, muzzle forward.
    g = next(x for x in GUNS if x["key"] == gun_key)
    build_gun(coll, m, g, (0.42, -0.05, 1.22), (0, 4, 0), root)
    return root


def build():
    sc = bpy.data.scenes.get("LD_models") or bpy.data.scenes.new("LD_models")
    bpy.context.window.scene = sc
    for ob in list(sc.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    coll = sc.collection
    m = mats()
    # Floor.
    me = bpy.data.meshes.new("Floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6)
    bm.to_mesh(me)
    bm.free()
    fl = bpy.data.objects.new("Floor", me)
    fl.data.materials.append(m["table"])
    coll.objects.link(fl)
    # Players.
    build_soldier(coll, m, "CT", (0, 0.8, 0), "guardian")
    build_soldier(coll, m, "T", (0, -0.8, 0), "kodiak")
    label(coll, "Counter-Terrorist", (0, 0.8, 1.95), 0.12, m["label"])
    label(coll, "Terrorist", (0, -0.8, 1.95), 0.12, m["label"])
    # Gun display: rows by buy-menu column, upright like they're on a wall rack.
    rows = [["pk9", "sentry", "duster", "viper", "falcon", "magnum"], ["hornet", "kestrel", "bulldog", "swarm"],
            ["kodiak", "lancer", "raptor", "guardian"], ["talon", "overwatch", "pathfinder", "longbow"], ["breacher", "tempest", "hammer"]]
    by_key = {g["key"]: g for g in GUNS}
    for ri, row in enumerate(rows):
        z = 2.9 - ri * 0.55
        spacing = 0.45 if ri == 0 else 1.45
        for ci, k in enumerate(row):
            x = 2.2 + ci * spacing + (0.2 if ri == 0 else 0.7)
            build_gun(coll, m, by_key[k], (x, 0, z))
            label(coll, by_key[k]["name"], (x, 0.0, z - (0.12 if ri == 0 else 0.27)), 0.045, m["label"])
    # Lights and camera.
    for nm, rot, e in (("Key", (50, 0, -40), 4.0), ("Fill", (60, 0, 150), 1.2)):
        ld = bpy.data.lights.new(nm, "SUN")
        ld.energy = e
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = [math.radians(a) for a in rot]
        coll.objects.link(lo)
    world = sc.world or bpy.data.worlds.new("LD_ModelsWorld")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.065, 1)
    cam_d = bpy.data.cameras.new("ShowCam")
    cam_d.lens = 35
    cam = bpy.data.objects.new("ShowCam", cam_d)
    cam.location = (3.4, -6.2, 2.2)
    cam.rotation_euler = (math.radians(84), 0, math.radians(18))
    coll.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.device = "GPU"
    sc.cycles.samples = 64
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.view_settings.view_transform = "AgX"
    return {"guns": len(GUNS), "objects": len(sc.objects)}
