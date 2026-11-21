"""Player models, quick pass (CT / T), built for the game's top-down view:
rounded plate carrier with pouches and shoulder straps, shoulder pads, helmet
or cap, backpack, and both arms in a compact rifle-ready pose (right hand at
the grip, left on the handguard). No gun: the game draws the held gun itself.

Headless:
    blender -b --python art/blender/player_quick.py -- <out_dir> [preview_dir]
writes <out_dir>/ct_top.png, t_top.png (+ _dead) and players.json, and with a
preview_dir also 3/4 renders holding their starting rifles.
"""
import bpy, math, os, sys, json
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_bm = {}
exec(open(os.path.join(HERE, "build_models.py")).read(), _bm)
part, mats, empty = _bm["part"], _bm["mats"], _bm["empty"]

PPM = 300  # Sprite pixels per metre.
EXTENT = 0.9  # Square sprite covers +-0.45 m around the body centre.
HANDS = {"grip": (0.2, -0.08, 1.18), "fore": (0.38, 0.0, 1.2)}


def limb(coll, root, name, material, a, b, r, r2=None):
    """Tapered cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    v = b - a
    ob = part(coll, root, name, material, (r, v.length), (0, 0, 0), shape="zcyl", segs=14, taper=(r2 or r) / r)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = v.to_track_quat("Z", "Y")
    ob.location = (a + b) / 2
    return ob


def soldier(coll, m, side):
    ct = side == "CT"
    n = side + "_"
    root = empty(coll, "Player_" + side)
    cloth = m["ct_cloth"] if ct else m["t_cloth"]
    top = m["ct_vest"] if ct else m["t_jacket"]
    acc = m["ct_accent"] if ct else m["t_accent"]
    dark = m["boots"]
    # Legs (mostly hidden from above): left foot forward in a shooting stance.
    for s, fx in ((-1, -0.04), (1, 0.1)):
        part(coll, root, n + "leg%d" % s, cloth, (0.17, 0.16, 0.82), (fx, s * 0.12, 0.45), bevel=0.06)
        part(coll, root, n + "boot%d" % s, dark, (0.29, 0.14, 0.12), (fx + 0.05, s * 0.12, 0.06), bevel=0.04)
    part(coll, root, n + "belt", dark, (0.28, 0.42, 0.08), (0, 0, 0.9), bevel=0.03)
    for s in (-1, 1):
        part(coll, root, n + "holster%d" % s, dark, (0.1, 0.06, 0.16), (-0.02, s * 0.23, 0.86), bevel=0.02)
    # Torso and the plate carrier / jacket.
    part(coll, root, n + "torso", cloth, (0.27, 0.42, 0.54), (0, 0, 1.18), bevel=0.1)
    part(coll, root, n + "vest", top, (0.33, 0.46, 0.44), (0.01, 0, 1.2), bevel=0.08)
    for i, y in enumerate((-0.13, 0.0, 0.13)):
        part(coll, root, n + "mag%d" % i, top, (0.07, 0.1, 0.14), (0.19, y, 1.1), bevel=0.02)
    part(coll, root, n + "radio", dark, (0.08, 0.07, 0.14), (0.0, 0.25, 1.12), bevel=0.02)
    for s in (-1, 1):  # Shoulder straps: what you see most of from above.
        part(coll, root, n + "strap%d" % s, top, (0.34, 0.08, 0.04), (0.0, s * 0.13, 1.44), bevel=0.015)
        part(coll, root, n + "pad%d" % s, top if ct else cloth, (0.1, 0.1, 0.075), (0.0, s * 0.255, 1.37), shape="sphere", segs=16)
    part(coll, root, n + "patch", acc, (0.07, 0.03, 0.07), (0.0, 0.29, 1.3), bevel=0.01)
    part(coll, root, n + "patch_top", acc, (0.09, 0.07, 0.012), (0.0, -0.255, 1.452), bevel=0.004)
    if ct:
        part(coll, root, n + "pack", top, (0.1, 0.34, 0.36), (-0.2, 0, 1.22), bevel=0.04)
        part(coll, root, n + "pack_tube", dark, (0.012, 0.3), (-0.14, -0.1, 1.32), rot=(0, -20, 70), shape="cyl", segs=8)
    else:
        part(coll, root, n + "pack", m["t_jacket"], (0.2, 0.36, 0.4), (-0.25, 0, 1.22), bevel=0.06)
        part(coll, root, n + "pack_roll", acc, (0.06, 0.34), (-0.25, 0, 1.45), rot=(0, 0, 90), shape="cyl", segs=14)
        part(coll, root, n + "scarf", acc, (0.22, 0.26, 0.07), (0.02, 0, 1.45), bevel=0.03)
    # Head.
    skin = m["skin"] if ct else m["t_mask"]
    part(coll, root, n + "neck", skin, (0.06, 0.08), (0, 0, 1.5), shape="zcyl", segs=12)
    part(coll, root, n + "head", skin, (0.11, 0.1, 0.12), (0.02, 0, 1.62), shape="sphere", segs=18)
    if ct:
        part(coll, root, n + "helmet", m["ct_helmet"], (0.14, 0.13, 0.1), (0.0, 0, 1.69), shape="sphere", segs=20)
        part(coll, root, n + "helmet_rail_l", dark, (0.12, 0.02, 0.03), (0.0, 0.125, 1.68), bevel=0.008)
        part(coll, root, n + "helmet_rail_r", dark, (0.12, 0.02, 0.03), (0.0, -0.125, 1.68), bevel=0.008)
        part(coll, root, n + "goggles", m["goggles"], (0.04, 0.17, 0.035), (0.11, 0, 1.64), bevel=0.012)
        part(coll, root, n + "nvg_mount", m["steel"], (0.05, 0.05, 0.04), (0.12, 0, 1.75), bevel=0.01)
        part(coll, root, n + "strobe", acc, (0.03, 0.03, 0.02), (-0.08, 0, 1.79), bevel=0.006)
    else:
        part(coll, root, n + "eyes", m["skin"], (0.02, 0.14, 0.03), (0.11, 0, 1.64), bevel=0.01)
        part(coll, root, n + "beanie", m["t_cloth"], (0.125, 0.12, 0.08), (0.0, 0, 1.69), shape="sphere", segs=18)
        part(coll, root, n + "beanie_fold", m["t_jacket"], (0.13, 0.125, 0.03), (0.0, 0, 1.655), shape="sphere", segs=18)
    # Arms in a compact ready pose.
    sh_r, el_r, ha_r = (0.0, -0.25, 1.35), (0.06, -0.27, 1.12), HANDS["grip"]
    sh_l, el_l, ha_l = (0.0, 0.25, 1.35), (0.2, 0.22, 1.14), HANDS["fore"]
    for nm, sh, el, ha in (("r", sh_r, el_r, ha_r), ("l", sh_l, el_l, ha_l)):
        limb(coll, root, n + "uarm_" + nm, top if not ct else cloth, sh, el, 0.055, 0.048)
        limb(coll, root, n + "farm_" + nm, cloth, el, ha, 0.046, 0.04)
        part(coll, root, n + "elbow_" + nm, dark, (0.05, 0.05, 0.05), el, shape="sphere", segs=12)
        part(coll, root, n + "hand_" + nm, m["gloves"], (0.045, 0.04, 0.04), ha, shape="sphere", segs=12)
    return root


def _studio(sc):
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = sc.world or bpy.data.worlds.new("LDP_World")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.35, 0.37, 0.4, 1)
    bg.inputs[1].default_value = 0.6
    for nm, rot, e in (("Key", (35, 15, -30), 3.5), ("Fill", (60, 0, 150), 0.8)):
        ld = bpy.data.lights.new(nm, "SUN")
        ld.energy = e
        ld.angle = math.radians(10)
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(lo)
    cam_d = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def _clear(sc):
    for ob in list(sc.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def render_sprites(out_dir, preview_dir=None):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    _clear(sc)
    cam = _studio(sc)
    m = mats()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = EXTENT
    cam.location = (0, 0, 3.0)
    cam.rotation_euler = (0, 0, 0)
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x = sc.render.resolution_y = int(EXTENT * PPM)
    sc.render.resolution_percentage = 100
    out = {}
    for side in ("CT", "T"):
        root = soldier(sc.collection, m, side)
        sc.render.filepath = os.path.join(out_dir, "%s_top.png" % side.lower())
        bpy.ops.render.render(write_still=True)
        out[side.lower()] = os.path.basename(sc.render.filepath)
        for ob in list(root.children_recursive) + [root]:
            bpy.data.objects.remove(ob, do_unlink=True)
    meta = {"ppm": PPM, "extent_m": EXTENT, "size": int(EXTENT * PPM), "hands": HANDS, "files": out}
    json.dump(meta, open(os.path.join(out_dir, "players.json"), "w"), indent=1)
    if preview_dir:
        gk = {}
        exec(open(os.path.join(HERE, "gun_kit.py")).read(), gk)
        GM = gk["materials"]()
        os.makedirs(preview_dir, exist_ok=True)
        cam.data.type = "PERSP"
        cam.data.lens = 50
        sc.render.film_transparent = False
        sc.render.resolution_x, sc.render.resolution_y = 1400, 900
        for side, gun in (("CT", "guardian"), ("T", "kodiak")):
            root = soldier(sc.collection, m, side)
            g = gk["GUNS"][gun](sc.collection, GM, loc=(HANDS["grip"][0] + 0.02, HANDS["grip"][1], HANDS["grip"][2] - 0.02))
            for nm, loc in (("34", (2.2, -2.6, 2.4)), ("top", (0.25, -0.6, 3.2))):
                cam.location = loc
                cam.rotation_euler = (Vector((0.1, 0, 1.15)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
                sc.render.filepath = os.path.join(preview_dir, "player_%s_%s.png" % (side.lower(), nm))
                bpy.ops.render.render(write_still=True)
            for ob in list(root.children_recursive) + [root] + list(g.root.children_recursive) + [g.root]:
                bpy.data.objects.remove(ob, do_unlink=True)
    return meta


if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    render_sprites(args[0], args[1] if len(args) > 1 else None)
