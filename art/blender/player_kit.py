"""Player model kit (CT / T), the overhaul of player_quick.py.

Bodies are lofted low-poly cages smoothed with Subdivision Surface: horizontal
ring lofts (torso, head, helmet, packs) and tubes swept along a path (limbs,
straps, rolls, antenna). Gear is soft-boxed fabric. Materials are fabric with a
weave bump and a camo breakup, knit, webbing, rubber, skin.

Same contract as player_quick.py: facing +X, right side -Y, right hand at the
grip HANDS["grip"], left hand on the handguard HANDS["fore"], no gun in the
sprite (the game draws it on top, starting at the right hand).

Headless:
    blender -b --factory-startup --python art/blender/player_kit.py -- <out_dir> [preview_dir]
writes <out_dir>/ct_top.png, t_top.png, ct2_top.png, t2_top.png and
players.json; with a preview_dir also 3/4 and top renders holding the
starting rifles from gun_kit.

Casual (home) bodies, same sprite contract, no gear, arms at the sides:
    blender -b --factory-startup --python art/blender/player_kit.py -- --casual <out_dir>
writes <out_dir>/casual_<n>_top.png and casual.json.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))

PPM = 300  # Sprite pixels per metre.
EXTENT = 1.4  # Square sprite covers +-0.7 m around the body centre (room for the reach).
DX = -0.035  # Upper body offset (see soldier()).
# Arm poses. Rifles are shouldered: the stock sits in the right shoulder pocket
# and both hands are on the gun's line (y = -0.12). Pistols are held out in two
# hands. The game puts the held gun's grip on "grip" (its pistol-grip point).
POSES = {
    "rifle": {"sh_r": (-0.02, -0.2, 1.4), "el_r": (0.12, -0.34, 1.22), "grip": (0.33, -0.12, 1.36),
              "sh_l": (0.06, 0.19, 1.4), "el_l": (0.3, 0.07, 1.22), "fore": (0.55, -0.12, 1.4)},
    "pistol": {"sh_r": (DX, -0.205, 1.4), "el_r": (0.2, -0.2, 1.3), "grip": (0.42, -0.04, 1.38),
               "sh_l": (DX, 0.205, 1.4), "el_l": (0.22, 0.14, 1.28), "fore": (0.45, 0.0, 1.35)},
}
HANDS = POSES["rifle"]  # Back-compat for callers that read HANDS["grip"].
V = Vector

# --- Materials ------------------------------------------------------------------


def _new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])
    return m, nt, b


def _coords(nt, scale=1.0):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def fabric(name, colors, camo=10.0, weave=900.0, rough=0.85, bump=0.25, knit=False, check=None):
    """Cloth: colour ramp (constant steps = camo blotches) over distorted noise,
    a fine weave bump (two crossed wave textures) and a tiny value grain.
    knit=True swaps the weave for vertical ribs; check=(rgb, scale) adds a
    shemagh-style check pattern on top."""
    m, nt, b = _new_mat(name)
    vec = _coords(nt)
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = camo
    n.inputs["Detail"].default_value = 3.0
    n.inputs["Roughness"].default_value = 0.55
    n.inputs["Distortion"].default_value = 0.6
    nt.links.new(vec, n.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    if len(colors) > 2:
        cr.interpolation = "CONSTANT"
    for i, c in enumerate(colors):
        el = cr.elements[i] if i < 2 else cr.elements.new(0)
        el.position = [0.0, 0.43, 0.52, 0.61][i] if len(colors) > 2 else (0.3, 0.7)[i]
        el.color = (*c, 1)
    nt.links.new(n.outputs["Fac"], ramp.inputs[0])
    col = ramp.outputs[0]
    # Fine grain so flat areas aren't plastic.
    g = nt.nodes.new("ShaderNodeTexNoise")
    g.inputs["Scale"].default_value = 140.0
    nt.links.new(vec, g.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "OVERLAY"
    mix.inputs["Factor"].default_value = 0.25
    nt.links.new(col, mix.inputs[6])
    nt.links.new(g.outputs["Fac"], mix.inputs[7])
    col = mix.outputs[2]
    if check:
        cc, cs = check
        ck = nt.nodes.new("ShaderNodeTexChecker")
        ck.inputs["Scale"].default_value = cs
        ck.inputs["Color1"].default_value = (1, 1, 1, 1)
        ck.inputs["Color2"].default_value = (0, 0, 0, 1)
        nt.links.new(vec, ck.inputs["Vector"])
        mx2 = nt.nodes.new("ShaderNodeMix")
        mx2.data_type = "RGBA"
        nt.links.new(ck.outputs["Fac"], mx2.inputs["Factor"])
        nt.links.new(col, mx2.inputs[6])
        mx2.inputs[7].default_value = (*cc, 1)
        mxf = nt.nodes.new("ShaderNodeMix")
        mxf.data_type = "RGBA"
        mxf.inputs["Factor"].default_value = 0.45
        nt.links.new(col, mxf.inputs[6])
        nt.links.new(mx2.outputs[2], mxf.inputs[7])
        col = mxf.outputs[2]
    nt.links.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Sheen Weight"].default_value = 0.3
    # Weave / rib bump.
    if knit:
        w = nt.nodes.new("ShaderNodeTexVoronoi")
        w.inputs["Scale"].default_value = weave / 4
        nt.links.new(vec, w.inputs["Vector"])
        h = w.outputs["Distance"]
    else:
        wa = nt.nodes.new("ShaderNodeTexWave")
        wa.bands_direction = "X"
        wa.inputs["Scale"].default_value = weave
        wb = nt.nodes.new("ShaderNodeTexWave")
        wb.bands_direction = "Z"
        wb.inputs["Scale"].default_value = weave
        for w in (wa, wb):
            nt.links.new(vec, w.inputs["Vector"])
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "MULTIPLY"
        nt.links.new(wa.outputs["Fac"], add.inputs[0])
        nt.links.new(wb.outputs["Fac"], add.inputs[1])
        h = add.outputs[0]
    wr = nt.nodes.new("ShaderNodeTexNoise")
    wr.inputs["Scale"].default_value = 35.0
    nt.links.new(vec, wr.inputs["Vector"])
    hm = nt.nodes.new("ShaderNodeMath")
    hm.operation = "ADD"
    nt.links.new(h, hm.inputs[0])
    nt.links.new(wr.outputs["Fac"], hm.inputs[1])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.002
    nt.links.new(hm.outputs[0], bp.inputs["Height"])
    nt.links.new(bp.outputs[0], b.inputs["Normal"])
    return m


def solid(name, color, rough=0.5, metallic=0.0, bump=0.05, scale=300.0, sss=0.0):
    m, nt, b = _new_mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if sss:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.01, 0.004, 0.002)
        b.inputs["Subsurface Scale"].default_value = 1.0
    if bump:
        vec = _coords(nt)
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        nt.links.new(vec, n.inputs["Vector"])
        bp = nt.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = bump
        nt.links.new(n.outputs["Fac"], bp.inputs["Height"])
        nt.links.new(bp.outputs[0], b.inputs["Normal"])
    return m


def kit_mats():
    return {
        # Shared.
        "skin": solid("PK_Skin", (0.52, 0.33, 0.23), 0.55, bump=0.03, sss=0.15),
        "skin_dk": solid("PK_SkinDark", (0.33, 0.2, 0.13), 0.55, bump=0.03, sss=0.15),
        "rubber": solid("PK_Rubber", (0.02, 0.02, 0.02), 0.7, bump=0.2, scale=500),
        "steel": solid("PK_Steel", (0.05, 0.05, 0.055), 0.35, 0.85),
        "lens": solid("PK_Lens", (0.02, 0.04, 0.05), 0.05, 0.6, bump=0),
        "black": fabric("PK_Black", [(0.018, 0.018, 0.02), (0.03, 0.03, 0.032)], weave=700, bump=0.3),
        # CT: blue-grey / navy urban camo.
        "ct_cam": fabric("PK_CT_Camo", [(0.160, 0.196, 0.275), (0.275, 0.319, 0.406), (0.080, 0.102, 0.160), (0.406, 0.450, 0.522)], camo=9),
        "ct_cam2": fabric("PK_CT_Camo2", [(0.05, 0.065, 0.1), (0.1, 0.125, 0.17), (0.028, 0.035, 0.06), (0.16, 0.19, 0.23)], camo=11),
        "ct_navy": fabric("PK_CT_Navy", [(0.058, 0.080, 0.145), (0.087, 0.113, 0.189)], weave=800),
        "ct_web": fabric("PK_CT_Web", [(0.109, 0.138, 0.196), (0.138, 0.167, 0.232)], weave=450, bump=0.45),
        "ct_helm": fabric("PK_CT_HelmCover", [(0.189, 0.232, 0.319), (0.290, 0.334, 0.420), (0.109, 0.131, 0.189), (0.392, 0.435, 0.507)], camo=16, weave=1200),
        "ct_acc": solid("PK_CT_Accent", (0.06, 0.3, 0.95), 0.45, bump=0.1),
        "ct_glove": fabric("PK_CT_Glove", [(0.035, 0.038, 0.045), (0.05, 0.055, 0.065)], weave=1500, rough=0.7),
        # T: tan / brown / olive with orange accents.
        "t_cam": fabric("PK_T_Camo", [(0.32, 0.245, 0.14), (0.19, 0.13, 0.07), (0.13, 0.14, 0.065), (0.42, 0.34, 0.2)], camo=8),
        "t_jacket": fabric("PK_T_Jacket", [(0.13, 0.095, 0.055), (0.17, 0.125, 0.075)], weave=700),
        "t_olive": fabric("PK_T_Olive", [(0.1, 0.11, 0.05), (0.14, 0.15, 0.075)], weave=600),
        "t_pants": fabric("PK_T_Pants", [(0.24, 0.19, 0.11), (0.3, 0.24, 0.15)], weave=800),
        "t_web": fabric("PK_T_Web", [(0.17, 0.13, 0.075), (0.21, 0.165, 0.1)], weave=450, bump=0.45),
        "t_knit": fabric("PK_T_Knit", [(0.13, 0.085, 0.045), (0.17, 0.11, 0.06)], weave=900, knit=True, bump=0.4),
        "t_mask": fabric("PK_T_Balaclava", [(0.02, 0.02, 0.02), (0.035, 0.033, 0.03)], weave=900, knit=True, bump=0.4),
        "t_scarf": fabric("PK_T_Shemagh", [(0.8, 0.3, 0.04), (0.9, 0.38, 0.06)], weave=800, check=((0.35, 0.1, 0.02), 70.0)),
        "t_wrap": fabric("PK_T_Wrap", [(0.5, 0.42, 0.28), (0.56, 0.48, 0.32)], weave=800, check=((0.55, 0.15, 0.03), 70.0)),
        "t_acc": solid("PK_T_Accent", (0.9, 0.38, 0.05), 0.55, bump=0.1),
        "t_glove": solid("PK_T_Leather", (0.09, 0.055, 0.03), 0.5, bump=0.15, scale=200),
        "t_roll": fabric("PK_T_Roll", [(0.16, 0.17, 0.08), (0.2, 0.2, 0.1)], weave=500, bump=0.35),
        "boot_ct": solid("PK_BootCT", (0.025, 0.025, 0.028), 0.5, bump=0.15, scale=250),
        "boot_t": fabric("PK_BootT", [(0.2, 0.15, 0.085), (0.24, 0.18, 0.1)], weave=500),
    }


# --- Mesh builders -----------------------------------------------------------------


class Kit:
    def __init__(self, coll, name):
        self.coll = coll
        self.root = bpy.data.objects.new("Player_" + name, None)
        coll.objects.link(self.root)
        self.n = name + "_"

    def _obj(self, nm, bm, material, subd=2, smooth=True):
        me = bpy.data.meshes.new(self.n + nm)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = smooth
        ob = bpy.data.objects.new(self.n + nm, me)
        ob.data.materials.append(material)
        self.coll.objects.link(ob)
        ob.parent = self.root
        if subd:
            s = ob.modifiers.new("Subd", "SUBSURF")
            s.levels = subd
            s.render_levels = subd
        return ob

    def hloft(self, nm, material, rings, segs=16, subd=2, caps=(True, True)):
        """Horizontal ring loft. ring = (cx, cy, z, hx, hy[, n[, tilt]]): a
        superellipse (n=2 ellipse, bigger = boxier) centred (cx, cy) at height z;
        tilt raises the +X side by tilt and lowers the -X side."""
        bm = bmesh.new()
        loops = []
        for r in rings:
            cx, cy, z, hx, hy = r[:5]
            n = r[5] if len(r) > 5 else 2.0
            tilt = r[6] if len(r) > 6 else 0.0
            loop = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                c, s = math.cos(a), math.sin(a)
                px = cx + hx * math.copysign(abs(c) ** (2 / n), c)
                py = cy + hy * math.copysign(abs(s) ** (2 / n), s)
                loop.append(bm.verts.new((px, py, z + tilt * (px - cx) / max(hx, 1e-6))))
            loops.append(loop)
        self._skin(bm, loops, segs, caps)
        return self._obj(nm, bm, material, subd)

    def tube(self, nm, material, pts, radii, ref=(0, 0, 1), segs=10, subd=2, n=2.0, caps=(True, True)):
        """Sweep along pts. radii[i] = r or (a, b): a along `ref` projected off the
        path tangent, b along tangent x ref."""
        pts = [V(p) for p in pts]
        bm = bmesh.new()
        loops = []
        ref = V(ref).normalized()
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            side = ref - t * ref.dot(t)
            if side.length < 1e-4:
                side = t.orthogonal()
            side.normalize()
            up = t.cross(side)
            r = radii[i]
            ra, rb = (r, r) if not isinstance(r, (tuple, list)) else r
            loop = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                c, s = math.cos(a), math.sin(a)
                c = math.copysign(abs(c) ** (2 / n), c)
                s = math.copysign(abs(s) ** (2 / n), s)
                loop.append(bm.verts.new(p + side * ra * c + up * rb * s))
            loops.append(loop)
        self._skin(bm, loops, segs, caps)
        return self._obj(nm, bm, material, subd)

    def _skin(self, bm, loops, segs, caps):
        for a, b in zip(loops, loops[1:]):
            for i in range(segs):
                bm.faces.new([a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]])
        if caps[0]:
            bm.faces.new(list(reversed(loops[0])))
        if caps[1]:
            bm.faces.new(loops[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    def softbox(self, nm, material, size, loc, rot=(0, 0, 0), round_=0.3, subd=2):
        """Pillowy box: cube, bevelled edges, then subdivided. round_ = bevel as
        a fraction of the smallest dimension."""
        bm = bmesh.new()
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=r["verts"])
        ob = self._obj(nm, bm, material, 0)
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = min(size) * round_
        bv.segments = 1
        s = ob.modifiers.new("Subd", "SUBSURF")
        s.levels = s.render_levels = subd
        ob.location = loc
        ob.rotation_euler = [math.radians(a) for a in rot]
        return ob

    def ball(self, nm, material, radii, loc, segs=12):
        bm = bmesh.new()
        r = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=1.0)
        bmesh.ops.scale(bm, vec=radii, verts=r["verts"])
        bmesh.ops.translate(bm, vec=loc, verts=r["verts"])
        return self._obj(nm, bm, material, 1)


def arc_pts(c, u, v, r, a0, a1, n=8):
    """Points on a circle around c in the plane (u, v), degrees."""
    c, u, v = V(c), V(u).normalized(), V(v).normalized()
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append(c + (u * math.cos(a) + v * math.sin(a)) * r)
    return out


def bez3(p0, p1, p2, p3, n=8):
    p0, p1, p2, p3 = V(p0), V(p1), V(p2), V(p3)
    return [p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + p3 * t ** 3 for t in (i / n for i in range(n + 1))]


# --- Body parts ---------------------------------------------------------------------


def leg(k, M, s, fx, cloth, boot, pad=None, yaw=0.0):
    """s = +1 left / -1 right; fx = foot fore/aft offset."""
    hip = V((fx * 0.25, s * 0.095, 0.96))
    knee = V((fx * 0.75 + 0.05, s * 0.115, 0.52))
    ankle = V((fx, s * 0.12, 0.13))
    thigh_mid = hip.lerp(knee, 0.45) + V((0.012, s * 0.008, 0))
    calf = knee.lerp(ankle, 0.35) + V((-0.012, 0, 0))
    k.tube("leg%d" % s, cloth, [hip + V((0, 0, 0.06)), hip, thigh_mid, knee, calf, ankle + V((0, 0, 0.06)), ankle],
           [0.08, (0.098, 0.095), (0.09, 0.087), (0.066, 0.068), (0.07, 0.067), 0.056, 0.053], ref=(0, 1, 0), segs=10)
    # Trousers bloused over the boot top.
    k.hloft("blouse%d" % s, cloth, [(ankle.x, ankle.y, 0.17, 0.058, 0.056), (ankle.x, ankle.y, 0.2, 0.066, 0.064), (ankle.x, ankle.y, 0.24, 0.062, 0.06), (ankle.x - 0.004, ankle.y, 0.28, 0.056, 0.055)], segs=12)
    # Cargo pocket on the thigh side.
    k.softbox("cargo%d" % s, cloth, (0.11, 0.035, 0.13), thigh_mid + V((0.0, s * 0.082, -0.04)), (0, 0, 0), 0.35)
    if pad:
        k.softbox("kneepad%d" % s, pad, (0.05, 0.1, 0.11), knee + V((0.055, 0, 0.0)), (0, -8, 0), 0.45)
        k.softbox("kneestrap%d" % s, M["black"], (0.07, 0.125, 0.02), knee + V((0.0, 0, 0.03)), (0, 0, 0), 0.4)
    # Boot: shaft + foot swept heel to toe.
    yw = math.radians(yaw)
    fwd = V((math.cos(yw), math.sin(yw), 0))
    side = V((-fwd.y, fwd.x, 0))
    a = ankle
    k.hloft("bootshaft%d" % s, boot, [(a.x, a.y, 0.06, 0.06, 0.055), (a.x, a.y, 0.16, 0.06, 0.056), (a.x, a.y, 0.2, 0.058, 0.054)], segs=12)
    foot = [a + fwd * -0.075 + V((0, 0, -0.06)), a + fwd * -0.04 + V((0, 0, -0.06)), a + fwd * 0.05 + V((0, 0, -0.07)), a + fwd * 0.15 + V((0, 0, -0.085)),
            a + fwd * 0.185 + V((0, 0, -0.09))]
    k.tube("boot%d" % s, boot, foot, [(0.04, 0.035), (0.06, 0.05), (0.055, 0.05), (0.04, 0.05), (0.02, 0.03)], ref=(0, 0, 1), segs=10)
    k.softbox("sole%d" % s, M["rubber"], (0.255, 0.09, 0.028), a + fwd * 0.05 + V((0, 0, -0.112)), (0, 0, yaw), 0.4)
    _ = side


def arm(k, M, s, sh, el, hand, sleeve, glove, cuff, upper=None, pad=None):
    sh, el, hand = V(sh), V(el), V(hand)
    wrist = hand + (el - hand).normalized() * 0.075
    up_mid = sh.lerp(el, 0.45) + V((0, s * 0.012, 0))
    fa_mid = el.lerp(wrist, 0.35)
    # Deltoid cap blended into the sleeve.
    k.ball("delt%d" % s, upper or sleeve, (0.06, 0.056, 0.055), sh + V((0, s * 0.008, 0.0)), 12)
    k.tube("uarm%d" % s, upper or sleeve, [sh + V((0, 0, 0.02)), sh, up_mid, el],
           [0.045, 0.056, (0.054, 0.05), 0.047], ref=(0, 0, 1), segs=10)
    k.ball("elbow%d" % s, sleeve, (0.046, 0.046, 0.046), el, 10)
    k.tube("farm%d" % s, sleeve, [el, fa_mid, wrist], [0.049, (0.05, 0.045), 0.038], ref=(0, 0, 1), segs=10)
    if pad:
        k.softbox("elbowpad%d" % s, pad, (0.06, 0.06, 0.05), el + (el - sh).normalized() * 0.025 + V((0, s * 0.02, 0)), (0, 0, 0), 0.45)
    k.tube("cuff%d" % s, cuff, [wrist + (el - wrist).normalized() * 0.03, wrist + (hand - wrist).normalized() * 0.01],
           [0.039, 0.038], ref=(0, 0, 1), segs=10)
    return wrist


def grip_hand(k, glove, c, wrist, s):
    """Right hand closed around a near-vertical pistol grip through c."""
    c, wrist = V(c), V(wrist)
    axis = V((-0.25, 0, -1)).normalized()  # grip rakes back as it drops
    u = V((0, -1, 0))  # back of the hand faces outward (-Y)
    v = axis.cross(u).normalized()
    # Four fingers wrapped round the front of the grip, stacked down it, touching.
    for i, off in enumerate((0.012, -0.007, -0.026, -0.043)):
        ring = arc_pts(c + axis * off, u, v, 0.024, -10, 205 - 8 * i, 8)
        rr = 0.0105 if i < 3 else 0.009
        k.tube("fing%d_%d" % (s, i), glove, ring, [rr] * len(ring), ref=axis, segs=8, subd=1)
    # Back of the hand on the outer side, linking to the wrist.
    k.tube("palm%d" % s, glove, [wrist, wrist.lerp(c, 0.5) + u * 0.024, c + u * 0.026 + axis * -0.01, c + u * 0.022 + axis * 0.03],
           [(0.032, 0.024), (0.044, 0.024), (0.046, 0.022), (0.03, 0.018)], ref=axis, segs=10)
    # Thumb hooked over the top of the grip on the inner side.
    k.tube("thumb%d" % s, glove, [c + u * 0.022 + axis * -0.025 - v * 0.015, c - v * 0.022 + axis * -0.03, c - v * 0.026 - u * 0.015 + axis * -0.02],
           [0.0125, 0.0115, 0.0095], ref=axis, segs=8, subd=1)


def fore_hand(k, glove, c, wrist, s):
    """Left hand cupping the handguard (axis along X) at c."""
    c, wrist = V(c), V(wrist)
    axis = V((1, 0, 0))
    for i, off in enumerate((-0.026, -0.007, 0.012, 0.029)):
        ring = arc_pts(c + axis * off, V((0, 1, 0)), V((0, 0, -1)), 0.03, -10, 215 - 10 * abs(i - 1.5), 8)
        k.tube("fing%d_%d" % (s, i), glove, ring, [0.0105 if i < 3 else 0.009 for _ in ring], ref=axis, segs=8, subd=1)
    # Palm on the left/under side, back of hand faces +Y.
    k.tube("palm%d" % s, glove, [wrist, wrist.lerp(c, 0.55) + V((0, 0.03, -0.01)), c + V((0.0, 0.03, -0.012))],
           [(0.03, 0.02), (0.042, 0.022), (0.042, 0.02)], ref=axis, segs=10)
    k.tube("thumb%d" % s, glove, [c + V((-0.035, 0.03, 0.0)), c + V((-0.01, 0.025, 0.028)), c + V((0.025, 0.01, 0.034))],
           [0.012, 0.011, 0.009], ref=(0, 0, 1), segs=8, subd=1)


def head(k, M, skin, ears=True):
    k.tube("neck", skin, [(0.0, 0, 1.44), (0.01, 0, 1.52), (0.02, 0, 1.58)], [0.058, 0.055, 0.056], ref=(0, 1, 0), segs=10)
    rings = [(0.03, 0, 1.53, 0.04, 0.035), (0.035, 0, 1.555, 0.075, 0.062), (0.03, 0, 1.6, 0.095, 0.078),
             (0.022, 0, 1.65, 0.105, 0.085), (0.012, 0, 1.7, 0.1, 0.083), (0.005, 0, 1.745, 0.075, 0.064), (0.0, 0, 1.768, 0.03, 0.028)]
    k.hloft("head", skin, rings, segs=14)
    k.tube("nose", skin, [(0.115, 0, 1.655), (0.13, 0, 1.63), (0.128, 0, 1.615)], [0.012, 0.016, 0.014], ref=(0, 1, 0), segs=8, subd=1)
    if ears:
        for s in (-1, 1):
            k.softbox("ear%d" % s, skin, (0.035, 0.014, 0.05), (0.0, s * 0.086, 1.64), (0, 0, 0), 0.45)


# --- Gear -----------------------------------------------------------------------


def plate_carrier(k, M, shell, web, pouch, dark, acc, radio=True):
    # Front and back plate bags, slightly curved to the chest.
    k.hloft("plate_f", shell, [(0.135, 0, 1.06, 0.04, 0.155, 4), (0.15, 0, 1.12, 0.042, 0.16, 4), (0.15, 0, 1.3, 0.04, 0.155, 4), (0.13, 0, 1.41, 0.035, 0.135, 4)], segs=20)
    k.hloft("plate_b", shell, [(-0.145, 0, 1.07, 0.04, 0.155, 4), (-0.155, 0, 1.13, 0.042, 0.16, 4), (-0.155, 0, 1.32, 0.04, 0.155, 4), (-0.14, 0, 1.43, 0.035, 0.14, 4)], segs=20)
    # Cummerbund wrapping the sides.
    k.hloft("cummer", web, [(0, 0, 1.04, 0.155, 0.19, 3.2), (0, 0, 1.06, 0.165, 0.198, 3.2), (0, 0, 1.18, 0.165, 0.198, 3.2), (0, 0, 1.2, 0.155, 0.19, 3.2)], segs=24)
    # Shoulder straps over the top with pads.
    for s in (-1, 1):
        y = s * 0.11
        p = bez3((0.15, y, 1.39), (0.11, y, 1.485), (-0.12, y, 1.495), (-0.155, y, 1.41), 8)
        k.tube("strap%d" % s, web, p, [(0.042, 0.014)] * len(p), ref=(0, 1, 0), segs=8, n=3)
        k.softbox("strappad%d" % s, shell, (0.12, 0.075, 0.025), (-0.01, s * 0.112, 1.485), (0, 0, 0), 0.5)
    # Triple mag pouches on the front flap, mags peeking out the top.
    for i, y in enumerate((-0.095, 0.0, 0.095)):
        k.softbox("mag%d" % i, pouch, (0.055, 0.085, 0.11), (0.195, y, 1.085), (0, 4, 0), 0.3)
        k.softbox("magtop%d" % i, dark, (0.036, 0.07, 0.03), (0.195, y, 1.15), (0, 4, 0), 0.25)
        k.softbox("bungee%d" % i, dark, (0.06, 0.02, 0.012), (0.195, y, 1.158), (0, 4, 0), 0.4)
    # Admin pouch on the upper chest and the team patch.
    k.softbox("admin", pouch, (0.035, 0.16, 0.08), (0.18, 0, 1.3), (0, -8, 0), 0.35)
    k.softbox("patch", acc, (0.006, 0.07, 0.04), (0.199, 0, 1.31), (0, -8, 0), 0.2, subd=1)
    if radio:
        k.softbox("radio", dark, (0.055, 0.05, 0.12), (-0.04, 0.215, 1.13), (0, 0, 0), 0.3)
        k.tube("antenna", dark, bez3((-0.045, 0.215, 1.19), (-0.05, 0.215, 1.38), (-0.08, 0.2, 1.5), (-0.15, 0.17, 1.6), 8), [0.007] * 9, segs=6, subd=1)
        k.ball("ant_tip", dark, (0.01, 0.01, 0.01), (-0.15, 0.17, 1.6), 8)
        k.tube("ptt_cable", dark, bez3((-0.04, 0.19, 1.2), (0.05, 0.19, 1.32), (0.12, 0.13, 1.42), (0.14, 0.1, 1.38), 8), [0.005] * 9, segs=6, subd=1)
    # IFAK / dump pouch on the right side.
    k.softbox("ifak", pouch, (0.08, 0.05, 0.1), (-0.04, -0.215, 1.12), (0, 0, 0), 0.4)


def belt(k, M, web, dark, holster_side=-1):
    k.hloft("belt", web, [(0.0, 0, 0.88, 0.14, 0.175, 3), (0.0, 0, 0.9, 0.148, 0.183, 3), (0.0, 0, 0.96, 0.148, 0.183, 3), (0.0, 0, 0.975, 0.14, 0.175, 3)], segs=20)
    k.softbox("buckle", M["steel"], (0.02, 0.06, 0.045), (0.15, 0, 0.93), (0, 0, 0), 0.25, subd=1)
    s = holster_side
    k.softbox("holster", dark, (0.13, 0.05, 0.2), (-0.01, s * 0.2, 0.82), (0, 12, 0), 0.25)
    k.softbox("holster_strap", dark, (0.1, 0.11, 0.025), (0.0, s * 0.15, 0.72), (0, 0, 0), 0.4)
    k.softbox("dump", web, (0.09, 0.07, 0.11), (-0.13, -s * 0.12, 0.88), (0, 0, -s * 20), 0.4)


def ct_helmet(k, M, cover, acc, dark, nvg=True):
    rings = [(-0.005, 0, 1.65, 0.128, 0.118, 2, 0.03), (-0.005, 0, 1.67, 0.131, 0.121, 2, 0.025), (-0.005, 0, 1.72, 0.124, 0.114, 2, 0.012),
             (-0.008, 0, 1.77, 0.1, 0.094), (-0.01, 0, 1.8, 0.06, 0.056), (-0.01, 0, 1.812, 0.02, 0.02)]
    k.hloft("helmet", cover, rings, segs=16)
    # Rim edge trim.
    rim = [(-0.005 + 0.133 * math.cos(a), 0.123 * math.sin(a), 1.652 + 0.03 * math.cos(a)) for a in (math.radians(d) for d in range(0, 361, 20))]
    k.tube("rim", dark, rim, [0.007] * len(rim), segs=6, subd=1, caps=(False, False))
    # ARC side rails following the shell.
    for s in (-1, 1):
        pts = []
        for d in range(-40, 41, 10):
            a = math.radians(d)
            pts.append((-0.005 + 0.122 * math.sin(a), s * (0.12 * math.cos(a) + 0.006), 1.69 + 0.01 * math.sin(a)))
        k.tube("rail%d" % s, dark, pts, [(0.014, 0.006)] * len(pts), ref=(0, 0, 1), segs=8, n=4, subd=1)
        # Ear-pro cup under the rail.
        cup = [(0.0, s * 0.08, 1.625), (0.0, s * 0.1, 1.625), (0.0, s * 0.118, 1.625), (0.0, s * 0.124, 1.625)]
        k.tube("earcup%d" % s, dark, cup, [(0.034, 0.03), (0.04, 0.035), (0.038, 0.033), (0.026, 0.022)], ref=(0, 0, 1), segs=12)
    if nvg:
        k.softbox("shroud", dark, (0.025, 0.06, 0.045), (0.123, 0, 1.73), (0, -25, 0), 0.3)
        k.softbox("nvg_arm", M["steel"], (0.035, 0.03, 0.04), (0.15, 0, 1.71), (0, -15, 0), 0.3)
        k.softbox("battery", dark, (0.04, 0.09, 0.05), (-0.13, 0, 1.73), (0, 25, 0), 0.35)
    # Velcro top patch in team colour and a strobe.
    k.softbox("top_patch", acc, (0.06, 0.05, 0.012), (-0.01, 0, 1.808), (0, 0, 0), 0.3, subd=1)
    k.softbox("strobe", dark, (0.03, 0.025, 0.02), (-0.075, -0.04, 1.79), (0, 20, 0), 0.3, subd=1)
    # Eye pro.
    eyes = arc_pts((0.0, 0, 1.645), (1, 0, 0), (0, 1, 0), 0.115, -70, 70, 10)
    k.tube("eyepro", M["lens"], eyes, [(0.02, 0.006)] * len(eyes), ref=(0, 0, 1), segs=8, subd=1)


def beanie(k, M, knit, fold):
    rings = [(0.0, 0, 1.655, 0.112, 0.097, 2, 0.02), (0.0, 0, 1.7, 0.114, 0.099, 2, 0.01), (-0.005, 0, 1.75, 0.098, 0.086), (-0.01, 0, 1.785, 0.062, 0.055), (-0.012, 0, 1.8, 0.02, 0.02)]
    k.hloft("beanie", knit, rings, segs=16)
    k.hloft("beanie_fold", fold, [(0.0, 0, 1.645, 0.114, 0.099, 2, 0.02), (0.0, 0, 1.66, 0.12, 0.105, 2, 0.02), (0.0, 0, 1.69, 0.119, 0.104, 2, 0.015), (0.0, 0, 1.70, 0.112, 0.097, 2, 0.015)], segs=16)


def cap(k, M, cloth, acc):
    rings = [(0.0, 0, 1.68, 0.112, 0.099, 2, 0.015), (-0.005, 0, 1.73, 0.105, 0.093), (-0.01, 0, 1.77, 0.07, 0.064), (-0.012, 0, 1.785, 0.02, 0.02)]
    k.hloft("cap", cloth, rings, segs=16)
    k.hloft("brim", M["ct_helm"], [(0.15, 0, 1.69, 0.095, 0.105, 2.4, -0.012), (0.15, 0, 1.70, 0.095, 0.105, 2.4, -0.012)], segs=16, subd=1)
    k.softbox("cap_patch", acc, (0.01, 0.045, 0.03), (0.1, 0, 1.72), (0, -30, 0), 0.3, subd=1)


def shemagh(k, M, cloth, wrap_head=False, wrap=None):
    # Bulky wrap round the neck, sitting on the shoulders.
    # Draped collar: a wide flattened ring resting on the shoulders.
    k.hloft("scarf_drape", cloth, [(0.01, 0, 1.43, 0.15, 0.2, 2.2, 0.02), (0.01, 0, 1.46, 0.145, 0.19, 2.2, 0.02), (0.015, 0, 1.5, 0.1, 0.12, 2, 0.02), (0.02, 0, 1.53, 0.07, 0.075, 2, 0.02)], segs=16)
    ring = [(0.02 + 0.095 * math.cos(a), 0.105 * math.sin(a), 1.5 + 0.02 * math.cos(a)) for a in (math.radians(d) for d in range(0, 390, 30))]
    k.tube("scarf", cloth, ring, [(0.035, 0.04)] * len(ring), ref=(0, 0, 1), segs=8, caps=(False, False))
    k.tube("scarf_knot", cloth, [(0.07, -0.05, 1.47), (0.11, -0.03, 1.44), (0.13, -0.02, 1.38)], [0.035, 0.03, 0.02], segs=8)
    k.tube("scarf_tail", cloth, [(-0.06, 0.04, 1.49), (-0.13, 0.06, 1.46), (-0.17, 0.08, 1.36)], [(0.05, 0.012), (0.055, 0.012), (0.05, 0.01)], ref=(0, 1, 0), segs=8, n=3)
    if wrap_head:
        rings = [(0.005, 0, 1.6, 0.112, 0.1, 2, 0.04), (0.0, 0, 1.68, 0.12, 0.106, 2, 0.02), (-0.005, 0, 1.74, 0.113, 0.1), (-0.01, 0, 1.79, 0.08, 0.072), (-0.015, 0, 1.81, 0.025, 0.025)]
        cloth = wrap or cloth
        k.hloft("headwrap", cloth, rings, segs=16)
        band = [(0.0 + 0.123 * math.cos(a), 0.109 * math.sin(a), 1.69 + 0.035 * math.cos(a) + 0.012 * math.sin(a)) for a in (math.radians(d) for d in range(0, 390, 30))]
        k.tube("wrap_band", cloth, band, [(0.022, 0.016)] * len(band), ref=(0, 0, 1), segs=8, caps=(False, False))
        k.tube("wrap_tail", cloth, [(-0.1, 0.03, 1.72), (-0.15, 0.05, 1.62), (-0.17, 0.06, 1.5)], [(0.04, 0.01), (0.045, 0.01), (0.04, 0.01)], ref=(0, 1, 0), segs=8, n=3)


def chest_rig(k, M, rig, web, dark, acc):
    # Chicom-style rig: one wide pouch block across the stomach, X straps behind.
    k.hloft("rig", rig, [(0.165, 0, 0.99, 0.04, 0.17, 4), (0.18, 0, 1.02, 0.05, 0.18, 4), (0.18, 0, 1.13, 0.05, 0.18, 4), (0.165, 0, 1.16, 0.045, 0.17, 4)], segs=20)
    for i, y in enumerate((-0.12, -0.04, 0.04, 0.12)):
        k.softbox("flap%d" % i, rig, (0.065, 0.075, 0.045), (0.185, y, 1.16), (0, 10, 0), 0.4)
        k.softbox("toggle%d" % i, dark, (0.02, 0.015, 0.015), (0.228, y, 1.135), (0, 0, 0), 0.4, subd=1)
    for s in (-1, 1):
        p = bez3((0.19, s * 0.14, 1.15), (0.13, s * 0.13, 1.5), (-0.12, s * 0.12, 1.5), (-0.17, -s * 0.02, 1.22), 10)
        k.tube("rigstrap%d" % s, web, p, [(0.03, 0.01)] * len(p), ref=(0, 1, 0), segs=8, n=3)
    k.softbox("patch", acc, (0.006, 0.06, 0.04), (0.232, 0.11, 1.06), (0, 0, 0), 0.2, subd=1)
    k.softbox("grenade", M["t_olive"], (0.05, 0.05, 0.07), (0.05, 0.205, 1.1), (0, 0, 0), 0.45)


def backpack(k, M, pack, web, roll=None, rollstrap=None, big=True):
    if big:
        rings = [(-0.24, 0, 0.98, 0.075, 0.14, 3), (-0.255, 0, 1.02, 0.095, 0.155, 3), (-0.26, 0, 1.25, 0.1, 0.16, 3), (-0.25, 0, 1.4, 0.09, 0.15, 3), (-0.235, 0, 1.43, 0.07, 0.12, 3)]
        k.hloft("pack", pack, rings, segs=20)
        k.softbox("lid", pack, (0.18, 0.28, 0.06), (-0.25, 0, 1.425), (0, 0, 0), 0.45)
        k.softbox("front_pocket", pack, (0.06, 0.22, 0.2), (-0.355, 0, 1.12), (0, 0, 0), 0.4)
        for s in (-1, 1):
            k.softbox("side_pocket%d" % s, pack, (0.12, 0.05, 0.18), (-0.255, s * 0.165, 1.08), (0, 0, 0), 0.4)
            k.tube("packstrap%d" % s, web, bez3((-0.17, s * 0.085, 1.38), (-0.08, s * 0.085, 1.5), (0.11, s * 0.085, 1.485), (0.16, s * 0.1, 1.3), 8), [(0.035, 0.012)] * 9, ref=(0, 1, 0), segs=8, n=3)
        if roll:
            k.tube("roll", roll, [(-0.25, -0.24, 1.5), (-0.25, -0.22, 1.5), (-0.25, 0.22, 1.5), (-0.25, 0.24, 1.5)], [0.04, 0.062, 0.062, 0.04], ref=(0, 0, 1), segs=14)
            for s in (-1, 1):
                k.tube("rollstrap%d" % s, rollstrap, arc_pts((-0.25, s * 0.13, 1.5), (1, 0, 0), (0, 0, 1), 0.066, 0, 360, 12), [(0.016, 0.004)] * 13, ref=(0, 1, 0), segs=6, subd=1, caps=(False, False))
    else:
        rings = [(-0.215, 0, 1.06, 0.05, 0.12, 3), (-0.225, 0, 1.1, 0.065, 0.135, 3), (-0.225, 0, 1.33, 0.065, 0.135, 3), (-0.215, 0, 1.38, 0.05, 0.11, 3)]
        k.hloft("pack", pack, rings, segs=20)
        k.softbox("pack_pocket", pack, (0.04, 0.18, 0.14), (-0.29, 0, 1.15), (0, 0, 0), 0.4)


def ct_back(k, M, pack, web, dark):
    # Slim hydration / assault panel zipped to the back plate.
    k.hloft("panel", pack, [(-0.2, 0, 1.08, 0.03, 0.13, 3.5), (-0.21, 0, 1.11, 0.04, 0.14, 3.5), (-0.21, 0, 1.36, 0.04, 0.14, 3.5), (-0.2, 0, 1.4, 0.03, 0.12, 3.5)], segs=20)
    k.tube("drink_tube", dark, bez3((-0.2, -0.1, 1.4), (-0.12, -0.12, 1.53), (0.08, -0.14, 1.5), (0.17, -0.09, 1.36), 10), [0.008] * 11, segs=6, subd=1)
    k.softbox("breacher_tool", M["steel"], (0.03, 0.03, 0.3), (-0.245, 0.07, 1.25), (0, 0, 0), 0.3, subd=1)


# --- Soldiers ---------------------------------------------------------------------


def soldier(coll, M, side, variant=1, pose="rifle"):
    ct = side == "CT"
    k = Kit(coll, side + ("" if variant == 1 else str(variant)))
    if ct:
        sleeve, pants, top = M["ct_cam"], M["ct_cam"], M["ct_cam"]
        shell, web, pouch, dark, acc = M["ct_navy"], M["ct_web"], M["ct_web"], M["black"], M["ct_acc"]
        glove, boot = M["ct_glove"], M["boot_ct"]
    else:
        sleeve, pants, top = M["t_jacket"], M["t_pants"], M["t_cam"]
        web, dark, acc = M["t_web"], M["black"], M["t_acc"]
        glove, boot = M["t_glove"], M["boot_t"]
    # Legs: left foot forward in a shooting stance.
    leg(k, M, -1, -0.05, pants, boot, pad=M["black"] if ct else None, yaw=-22)
    leg(k, M, 1, 0.1, pants, boot, pad=M["black"] if ct else None, yaw=12)
    belt(k, M, web, dark if ct else M["t_web"])
    # Torso: shirt / jacket under the gear.
    tr = [(0.0, 0, 0.88, 0.12, 0.165), (0.005, 0, 1.0, 0.118, 0.16), (0.01, 0, 1.18, 0.128, 0.178), (0.005, 0, 1.33, 0.13, 0.2),
          (0.0, 0, 1.42, 0.11, 0.19), (0.0, 0, 1.47, 0.07, 0.11), (0.005, 0, 1.49, 0.05, 0.06)]
    if not ct:  # Loose jacket, slightly bulkier.
        tr = [(a, b, z, hx * 1.08, hy * 1.04) for a, b, z, hx, hy in tr]
    k.hloft("torso", top if not ct else sleeve, tr, segs=16)
    # Arms in the chosen pose; hands exactly on the gun points.
    P = POSES[pose]
    upper = None if ct else top
    wr = arm(k, M, -1, P["sh_r"], P["el_r"], P["grip"], sleeve, glove, glove if ct else sleeve, upper, pad=M["black"] if ct else None)
    grip_hand(k, glove, P["grip"], wr, -1)
    wl = arm(k, M, 1, P["sh_l"], P["el_l"], P["fore"], sleeve, glove, glove if ct else sleeve, upper, pad=M["black"] if ct else None)
    fore_hand(k, glove, P["fore"], wl, 1)
    if ct:
        plate_carrier(k, M, shell, web, pouch, dark, acc)
        k.softbox("shoulder_patch", acc, (0.05, 0.012, 0.04), (0.0, 0.272, 1.33), (0, 0, 0), 0.25, subd=1)
        head(k, M, M["skin"])
        if variant == 1:
            ct_helmet(k, M, M["ct_helm"], acc, dark, nvg=True)
            ct_back(k, M, M["ct_navy"], web, dark)
        else:
            cap(k, M, M["ct_navy"], acc)
            k.softbox("top_patch", acc, (0.05, 0.045, 0.01), (-0.01, 0, 1.783), (0, 0, 0), 0.3, subd=1)
            for s in (-1, 1):  # Comms headset over the cap.
                cup = [(0.0, s * 0.08, 1.635), (0.0, s * 0.1, 1.635), (0.0, s * 0.118, 1.635), (0.0, s * 0.124, 1.635)]
                k.tube("earcup%d" % s, dark, cup, [(0.034, 0.03), (0.04, 0.035), (0.038, 0.033), (0.026, 0.022)], ref=(0, 0, 1), segs=12)
            band = arc_pts((-0.01, 0, 1.635), (0, -1, 0), (0, 0, 1), 0.122, 0, 180, 12)
            k.tube("headband", dark, band, [(0.012, 0.02)] * len(band), ref=(1, 0, 0), segs=8, n=3, subd=1)
            eyes = arc_pts((0.0, 0, 1.65), (1, 0, 0), (0, 1, 0), 0.112, -70, 70, 10)
            k.tube("eyepro", M["lens"], eyes, [(0.02, 0.006)] * len(eyes), ref=(0, 0, 1), segs=8, subd=1)
            backpack(k, M, M["ct_cam2"], web, big=False)
            k.tube("drink_tube", dark, bez3((-0.2, -0.1, 1.38), (-0.12, -0.12, 1.53), (0.08, -0.14, 1.5), (0.17, -0.09, 1.36), 10), [0.008] * 11, segs=6, subd=1)
    else:
        head(k, M, M["t_mask"], ears=False)
        # Eye slit in the balaclava.
        k.tube("eyes", M["skin"], arc_pts((0.022, 0, 1.655), (1, 0, 0), (0, 1, 0), 0.093, -48, 48, 8), [(0.016, 0.006)] * 9, ref=(0, 0, 1), segs=8, subd=1)
        chest_rig(k, M, M["t_olive"], web, dark, acc)
        k.softbox("shoulder_patch", acc, (0.05, 0.012, 0.04), (0.0, 0.282, 1.33), (0, 0, 0), 0.25, subd=1)
        if variant == 1:
            shemagh(k, M, M["t_scarf"])
            beanie(k, M, M["t_knit"], M["t_knit"])
            backpack(k, M, M["t_cam"], web, roll=M["t_roll"], rollstrap=M["black"])
        else:
            shemagh(k, M, M["t_scarf"], wrap_head=True, wrap=M["t_wrap"])
            backpack(k, M, M["t_jacket"], web, big=False)
    # The grip sits close to the chest: set the upper body back a little so the
    # gear doesn't swallow the hands (arms, hands and legs stay put).
    fixed = ("blouse", "delt", "uarm", "elbow", "farm", "cuff", "fing", "palm", "thumb", "leg", "cargo", "knee", "boot", "sole")
    for ob in k.root.children:
        if not ob.name[len(k.n):].startswith(fixed):
            ob.location.x += DX
    return k.root


# --- Casual (home) bodies -------------------------------------------------------------
# Same sprite contract as the soldiers (facing +X, PPM, EXTENT) but no gear: arms
# relaxed at the sides, nothing in the hands. Used by the walkable homes.

CASUAL_ARMS = {"sh_r": (0.0, -0.2, 1.4), "el_r": (-0.015, -0.235, 1.13), "hand": (0.02, -0.24, 0.87)}


def casual_mats():
    return {
        "skin": solid("PK_Skin", (0.52, 0.33, 0.23), 0.55, bump=0.03, sss=0.15),
        "skin2": solid("PK_Skin2", (0.3, 0.18, 0.11), 0.55, bump=0.03, sss=0.15),
        "skin3": solid("PK_Skin3", (0.68, 0.48, 0.36), 0.55, bump=0.03, sss=0.15),
        "hoodie_grey": fabric("PK_C_HoodieGrey", [(0.2, 0.2, 0.21), (0.25, 0.25, 0.26)], weave=900, knit=True, bump=0.25),
        "hoodie_rib": fabric("PK_C_HoodieRib", [(0.16, 0.16, 0.17), (0.19, 0.19, 0.2)], weave=1200, knit=True, bump=0.4),
        "tee_white": fabric("PK_C_TeeWhite", [(0.75, 0.75, 0.73), (0.82, 0.82, 0.8)], weave=1400, bump=0.15),
        "bomber": fabric("PK_C_Bomber", [(0.12, 0.14, 0.07), (0.15, 0.17, 0.09)], weave=1100, bump=0.2, rough=0.6),
        "bomber_rib": fabric("PK_C_BomberRib", [(0.5, 0.18, 0.03), (0.55, 0.22, 0.04)], weave=1200, knit=True, bump=0.4),
        "jeans": fabric("PK_C_Jeans", [(0.06, 0.1, 0.2), (0.09, 0.14, 0.26)], weave=900, bump=0.35),
        "jeans_light": fabric("PK_C_JeansLt", [(0.2, 0.28, 0.42), (0.26, 0.34, 0.5)], weave=900, bump=0.35),
        "jeans_black": fabric("PK_C_JeansBlk", [(0.025, 0.025, 0.03), (0.04, 0.04, 0.045)], weave=900, bump=0.35),
        "sneaker_white": solid("PK_C_SneakW", (0.8, 0.8, 0.78), 0.45, bump=0.08),
        "sneaker_red": solid("PK_C_SneakR", (0.6, 0.04, 0.03), 0.45, bump=0.08),
        "sole": solid("PK_C_Sole", (0.85, 0.83, 0.78), 0.6, bump=0.05),
        "hair_dark": fabric("PK_C_HairDk", [(0.02, 0.015, 0.012), (0.04, 0.03, 0.022)], weave=2500, knit=True, bump=0.5, rough=0.5),
        "hair_brown": fabric("PK_C_HairBr", [(0.09, 0.05, 0.025), (0.14, 0.08, 0.04)], weave=2500, knit=True, bump=0.5, rough=0.5),
        "cap_red": fabric("PK_C_CapRed", [(0.5, 0.05, 0.04), (0.58, 0.08, 0.05)], weave=1000),
    }


def casual_leg(k, s, fx, cloth, shoe, sole, yaw=0.0):
    hip = V((fx * 0.25, s * 0.095, 0.96))
    knee = V((fx * 0.75 + 0.03, s * 0.105, 0.52))
    ankle = V((fx, s * 0.11, 0.13))
    k.tube("leg%d" % s, cloth, [hip + V((0, 0, 0.06)), hip, hip.lerp(knee, 0.45), knee, knee.lerp(ankle, 0.35), ankle + V((0, 0, 0.05)), ankle],
           [0.08, (0.094, 0.091), (0.084, 0.081), (0.064, 0.064), (0.064, 0.062), 0.06, 0.058], ref=(0, 1, 0), segs=10)
    yw = math.radians(yaw)
    fwd = V((math.cos(yw), math.sin(yw), 0))
    a = ankle
    foot = [a + fwd * -0.08 + V((0, 0, -0.06)), a + fwd * -0.04 + V((0, 0, -0.055)), a + fwd * 0.05 + V((0, 0, -0.07)), a + fwd * 0.15 + V((0, 0, -0.085)),
            a + fwd * 0.18 + V((0, 0, -0.09))]
    k.tube("shoe%d" % s, shoe, foot, [(0.04, 0.038), (0.058, 0.05), (0.052, 0.048), (0.04, 0.046), (0.02, 0.03)], ref=(0, 0, 1), segs=10)
    k.softbox("sole%d" % s, sole, (0.27, 0.095, 0.03), a + fwd * 0.05 + V((0, 0, -0.11)), (0, 0, yaw), 0.4)


def casual_arm(k, M, s, sleeve, lower, cuff, skin):
    P = CASUAL_ARMS
    sh, el, hand = V(P["sh_r"]), V(P["el_r"]), V(P["hand"])
    if s > 0:
        sh, el, hand = V((sh.x, -sh.y, sh.z)), V((el.x, -el.y, el.z)), V((hand.x, -hand.y, hand.z))
    wrist = arm(k, M, s, sh, el, hand, lower, skin, cuff, upper=sleeve)
    # Relaxed hand hanging below the wrist, fingers loosely together.
    d = (hand - wrist).normalized()
    k.tube("palm%d" % s, skin, [wrist, wrist + d * 0.05, wrist + d * 0.1 + V((0.008, 0, 0))],
           [(0.034, 0.02), (0.042, 0.02), (0.036, 0.016)], ref=(0, 1, 0), segs=10)
    k.tube("thumb%d" % s, skin, [wrist + d * 0.02 + V((0.025, 0, 0)), wrist + d * 0.055 + V((0.035, 0, 0))], [0.012, 0.01], ref=(0, 0, 1), segs=8, subd=1)


def civilian(coll, M, variant=1):
    """Casual-clothes body: 1 = grey hoodie + jeans, 2 = white tee + black jeans,
    3 = olive bomber over a tee + light jeans + backwards cap."""
    k = Kit(coll, "casual%d" % variant)
    skin = M[("skin", "skin2", "skin3")[(variant - 1) % 3]]
    if variant == 1:
        top, lower, cuff, legs, shoe = M["hoodie_grey"], M["hoodie_grey"], M["hoodie_rib"], M["jeans"], M["sneaker_white"]
    elif variant == 2:
        top, lower, cuff, legs, shoe = M["tee_white"], skin, skin, M["jeans_black"], M["sneaker_red"]
    else:
        top, lower, cuff, legs, shoe = M["bomber"], M["bomber"], M["bomber_rib"], M["jeans_light"], M["sneaker_white"]
    casual_leg(k, -1, -0.03, legs, shoe, M["sole"], yaw=-6)
    casual_leg(k, 1, 0.03, legs, shoe, M["sole"], yaw=6)
    bulk = {1: 1.1, 2: 1.0, 3: 1.12}[variant]
    tr = [(0.0, 0, 0.88, 0.12, 0.165), (0.005, 0, 1.0, 0.118, 0.16), (0.01, 0, 1.18, 0.125, 0.175), (0.005, 0, 1.33, 0.128, 0.198),
          (0.0, 0, 1.42, 0.108, 0.188), (0.0, 0, 1.47, 0.07, 0.11), (0.005, 0, 1.49, 0.05, 0.06)]
    tr = [(a, b, z, hx * bulk, hy * (1 + (bulk - 1) * 0.6)) for a, b, z, hx, hy in tr]
    k.hloft("torso", top, tr, segs=16)
    k.hloft("waistband", cuff if variant != 2 else legs, [(0.0, 0, 0.86, 0.122 * bulk, 0.168 * bulk), (0.0, 0, 0.92, 0.124 * bulk, 0.17 * bulk)], segs=16)
    casual_arm(k, M, -1, top, lower, cuff, skin)
    casual_arm(k, M, 1, top, lower, cuff, skin)
    head(k, M, skin)
    if variant == 1:
        # Hood lying on the upper back, kangaroo pocket, drawstrings.
        k.hloft("hood", top, [(-0.1, 0, 1.38, 0.05, 0.12), (-0.12, 0, 1.45, 0.07, 0.13), (-0.11, 0, 1.52, 0.06, 0.11), (-0.09, 0, 1.55, 0.03, 0.06)], segs=14)
        k.softbox("pocket", top, (0.03, 0.2, 0.12), (0.125, 0, 1.02), (0, 0, 0), 0.4)
        for s in (-1, 1):
            k.tube("string%d" % s, M["tee_white"], [(0.1, s * 0.03, 1.46), (0.13, s * 0.035, 1.38), (0.135, s * 0.035, 1.3)], [0.006] * 3, segs=6, subd=1)
    elif variant == 3:
        k.hloft("collar", M["bomber_rib"], [(0.0, 0, 1.46, 0.085, 0.12), (0.0, 0, 1.5, 0.07, 0.1)], segs=14)
        k.softbox("tee_v", M["tee_white"], (0.03, 0.12, 0.3), (0.118 * bulk, 0, 1.25), (0, 0, 0), 0.3)
    hair = M["hair_dark"] if variant != 2 else M["hair_brown"]
    k.hloft("hair", hair, [(-0.01, 0, 1.62, 0.112, 0.092), (0.0, 0, 1.69, 0.112, 0.092), (0.0, 0, 1.75, 0.086, 0.074), (-0.005, 0, 1.785, 0.035, 0.032)], segs=14)
    if variant == 3:  # backwards cap
        k.hloft("cap", M["cap_red"], [(-0.005, 0, 1.7, 0.114, 0.095), (-0.005, 0, 1.76, 0.1, 0.085), (-0.005, 0, 1.8, 0.05, 0.045)], segs=14)
        k.softbox("brim", M["cap_red"], (0.09, 0.15, 0.012), (-0.14, 0, 1.69), (0, 10, 0), 0.3)
    return k.root


CASUAL_VARIANTS = (1, 2, 3)


def render_casual(out_dir):
    """casual_<n>_top.png (same sprite contract as the soldier sprites) + casual.json."""
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    _clear(sc)
    cam = _studio(sc)
    M = casual_mats()
    M.update({k_: v for k_, v in kit_mats().items() if k_ not in M})
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = EXTENT
    cam.location = (0, 0, 3.0)
    cam.rotation_euler = (0, 0, 0)
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x = sc.render.resolution_y = int(EXTENT * PPM)
    sc.render.resolution_percentage = 100
    files = []
    for v in CASUAL_VARIANTS:
        root = civilian(sc.collection, M, v)
        fn = "casual_%d_top.png" % v
        sc.render.filepath = os.path.join(out_dir, fn)
        bpy.ops.render.render(write_still=True)
        files.append(fn)
        _remove(root)
    meta = {"ppm": PPM, "extent_m": EXTENT, "size": int(EXTENT * PPM), "facing": "+X", "files": files,
            "desc": {"casual_1_top.png": "grey hoodie + jeans", "casual_2_top.png": "white tee + black jeans",
                     "casual_3_top.png": "olive bomber + light jeans + backwards cap"}}
    json.dump(meta, open(os.path.join(out_dir, "casual.json"), "w"), indent=1)
    return meta


# --- Rendering ----------------------------------------------------------------------


def _gpu(sc):
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dev in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = dev
                prefs.get_devices()
                ok = [d for d in prefs.devices if d.type == dev]
                if ok:
                    for d in prefs.devices:
                        d.use = d.type == dev
                    sc.cycles.device = "GPU"
                    print("PK: rendering on", dev)
                    return
            except Exception:
                pass
    except Exception as e:
        print("PK: GPU unavailable", e)


def _studio(sc):
    sc.render.engine = "CYCLES"
    _gpu(sc)
    sc.cycles.samples = 64
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


def _remove(root):
    for ob in list(root.children_recursive) + [root]:
        bpy.data.objects.remove(ob, do_unlink=True)


VARIANTS = (("ct", "CT", 1), ("t", "T", 1), ("ct2", "CT", 2), ("t2", "T", 2))


def render_sprites(out_dir, preview_dir=None, only=None):
    """Top-down sprites for every variant in both poses: <key>_top.png (rifle)
    and <key>_pistol_top.png, plus players.json. With preview_dir, 3/4 and top
    previews of each variant holding a rifle and a pistol by their grips."""
    out_dir = os.path.abspath(out_dir)  # Blender resolves relative render paths oddly.
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    _clear(sc)
    cam = _studio(sc)
    M = kit_mats()
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
    for key, side, var in VARIANTS:
        if only and key not in only:
            continue
        out[key] = {}
        for pose in POSES:
            root = soldier(sc.collection, M, side, var, pose)
            fn = "%s_top.png" % key if pose == "rifle" else "%s_%s_top.png" % (key, pose)
            sc.render.filepath = os.path.join(out_dir, fn)
            bpy.ops.render.render(write_still=True)
            out[key][pose] = fn
            _remove(root)
    meta = {"ppm": PPM, "extent_m": EXTENT, "size": int(EXTENT * PPM), "hands": POSES, "files": out,
            "variants": {"T": [k for k, sd, v in VARIANTS if sd == "T"], "CT": [k for k, sd, v in VARIANTS if sd == "CT"]}}
    if not only:
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
        sc.cycles.samples = 96
        guns = {"CT": {"rifle": "guardian", "pistol": "sentry"}, "T": {"rifle": "kodiak", "pistol": "pk9"}}
        for key, side, var in VARIANTS:
            if only and key not in only:
                continue
            for pose in POSES:
                root = soldier(sc.collection, M, side, var, pose)
                g = gk["GUNS"][guns[side][pose]](sc.collection, GM)
                g.root.location = Vector(POSES[pose]["grip"]) - gk["grip_point"](g)
                for nm, loc, tgt in (("34", (2.0, -2.4, 2.2), (0.25, 0, 1.25)), ("top", (0.3, -0.5, 3.0), (0.25, 0, 1.2)), ("side", (0.3, -2.6, 1.45), (0.3, 0, 1.3))):
                    cam.location = loc
                    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
                    sc.render.filepath = os.path.join(preview_dir, "hold_%s_%s_%s.png" % (key, pose, nm))
                    bpy.ops.render.render(write_still=True)
                _remove(root)
                _remove(g.root)
    return meta


if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    if args and args[0] == "--casual":  # casual home bodies: -- --casual <out_dir>
        render_casual(args[1])
        sys.exit(0)
    only = args[2].split(",") if len(args) > 2 else None
    render_sprites(args[0], args[1] if len(args) > 1 and args[1] != "-" else None, only)
