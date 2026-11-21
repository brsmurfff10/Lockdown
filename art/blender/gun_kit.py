"""Gun modelling kit (Blender 5.x): parts are side profiles (X forward, Z up)
drawn as 2D outlines with real curves, extruded to thickness and bevelled, plus
lathed round parts (barrels, brakes, drums). 1 unit = 1 m.

    ns = {}; exec(open(r"<project>/art/blender/gun_kit.py").read(), ns)
    ns["showcase"](["kodiak", "hammer"], out_dir)
"""
import bpy, bmesh, math
from mathutils import Matrix, Vector

# --- Materials ------------------------------------------------------------------

def _mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])
    return m, nt, b


def mat_metal(name, color, rough=0.32, metallic=0.9, wear=0.0):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    # Roughness breakup so the metal isn't plastic-flat.
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 60.0
    n.inputs["Detail"].default_value = 8.0
    r = nt.nodes.new("ShaderNodeMapRange")
    r.inputs["To Min"].default_value = rough * 0.75
    r.inputs["To Max"].default_value = rough * 1.3
    nt.links.new(n.outputs["Fac"], r.inputs["Value"])
    nt.links.new(r.outputs["Result"], b.inputs["Roughness"])
    return m


def mat_poly(name, color, rough=0.62):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 400.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = rough
    return m


def mat_wood(name, c0, c1):
    m, nt, b = _mat(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, 6.0, 6.0)  # grain runs along X
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = "Z"
    w.inputs["Scale"].default_value = 18.0
    w.inputs["Distortion"].default_value = 6.0
    w.inputs["Detail"].default_value = 3.0
    nt.links.new(mp.outputs["Vector"], w.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c0, 1)
    ramp.color_ramp.elements[1].color = (*c1, 1)
    nt.links.new(w.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Coat Weight"].default_value = 0.3
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.05
    nt.links.new(w.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], b.inputs["Normal"])
    return m


def mat_rubber(name, color):
    """Grippy rubber with a fine pebbled (voronoi) texture."""
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.78
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 900.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(v.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], b.inputs["Normal"])
    return m


def materials():
    return {
        "satin": mat_metal("GK_Satin", (0.62, 0.62, 0.64), 0.16, 1.0),
        "coat": mat_metal("GK_Coated", (0.028, 0.03, 0.032), 0.55, 0.55),
        "rubber": mat_rubber("GK_Rubber", (0.011, 0.012, 0.01)),
        "rubber_od": mat_rubber("GK_RubberOD", (0.04, 0.05, 0.022)),
        "steel": mat_metal("GK_Steel", (0.018, 0.018, 0.02), 0.3),
        "parked": mat_metal("GK_Parkerized", (0.03, 0.03, 0.032), 0.5, 0.75),
        "bright": mat_metal("GK_Bright", (0.5, 0.5, 0.52), 0.2, 1.0),
        "poly": mat_poly("GK_Polymer", (0.022, 0.022, 0.024)),
        "poly_od": mat_poly("GK_PolyOD", (0.035, 0.045, 0.02)),
        "poly_tan": mat_poly("GK_PolyTan", (0.32, 0.25, 0.15)),
        "bakelite": mat_poly("GK_Bakelite", (0.07, 0.018, 0.008), 0.35),
        "wood": mat_wood("GK_Wood", (0.06, 0.018, 0.005), (0.15, 0.05, 0.014)),
        "wood_lt": mat_wood("GK_WoodLight", (0.16, 0.07, 0.025), (0.3, 0.14, 0.05)),
        "alu": mat_metal("GK_Anodized", (0.035, 0.035, 0.04), 0.42, 0.85),
        "alu_tan": mat_metal("GK_AnodizedTan", (0.3, 0.24, 0.15), 0.45, 0.6),
        "glass": mat_glass("GK_Lens"),
        "smoke": mat_smoke("GK_Smoke"),
        "clay": mat_poly("GK_Clay", (0.42, 0.38, 0.28), 0.85),
        "tape": mat_poly("GK_Tape", (0.04, 0.045, 0.05), 0.4),
        "wire_r": mat_poly("GK_WireRed", (0.5, 0.02, 0.02), 0.35),
        "wire_b": mat_poly("GK_WireBlue", (0.02, 0.08, 0.45), 0.35),
        "wire_y": mat_poly("GK_WireYellow", (0.6, 0.45, 0.02), 0.35),
        "pcb": mat_poly("GK_PCB", (0.01, 0.12, 0.05), 0.4),
        "lcd": mat_emit("GK_LCD", (0.25, 0.9, 0.3), 3.0),
        "led": mat_emit("GK_LED", (1.0, 0.05, 0.03), 12.0),
        "key": mat_poly("GK_Keys", (0.55, 0.56, 0.58), 0.5),
    }


def mat_glass(name):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (0.02, 0.05, 0.12, 1)
    b.inputs["Roughness"].default_value = 0.03
    b.inputs["Coat Weight"].default_value = 1.0
    return m


def mat_smoke(name):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (0.32, 0.2, 0.08, 1)
    b.inputs["Roughness"].default_value = 0.18
    b.inputs["Transmission Weight"].default_value = 0.65
    return m


def mat_emit(name, color, strength):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Emission Color"].default_value = (*color, 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


# --- Curves --------------------------------------------------------------------

def arc(cx, cz, r, a0, a1, n=8):
    """Points on a circle, degrees, from a0 to a1 inclusive."""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bez(p0, p1, p2, n=6):
    """Quadratic bezier from p0 to p2 pulled toward p1 (excludes p0)."""
    out = []
    for i in range(1, n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return out


def path(*segs):
    """Joins point lists / single points into one outline."""
    out = []
    for s in segs:
        if isinstance(s, tuple):
            out.append(s)
        else:
            out.extend(s)
    return out


# --- Mesh builders ---------------------------------------------------------------

class Gun:
    def __init__(self, name, coll, loc=(0, 0, 0), rot=(0, 0, 0)):
        self.coll = coll
        self.root = bpy.data.objects.new("Gun_" + name, None)
        self.root.empty_display_size = 0.05
        self.root.location = loc
        self.root.rotation_euler = [math.radians(a) for a in rot]
        coll.objects.link(self.root)
        self.name = name

    def _obj(self, nm, me, material, bevel, segs=3, smooth=False):
        ob = bpy.data.objects.new("%s_%s" % (self.name, nm), me)
        ob.data.materials.append(material)
        self.coll.objects.link(ob)
        ob.parent = self.root
        if bevel > 0:
            bv = ob.modifiers.new("Bevel", "BEVEL")
            bv.width = bevel
            bv.segments = segs
            bv.limit_method = "ANGLE"
            bv.angle_limit = math.radians(35)
            bv.harden_normals = True
        for p in me.polygons:
            p.use_smooth = True
        wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        if not smooth:
            sm = ob.modifiers.new("Smooth", "NODES") if False else None
        return ob

    def profile(self, nm, material, pts, width, y=0.0, bevel=0.0025, holes=()):
        """Extrude a side outline (list of (x, z)) to `width` along Y, centred on y."""
        me = bpy.data.meshes.new(nm)
        bm = bmesh.new()
        # Remove duplicate consecutive points.
        clean = [pts[0]]
        for p in pts[1:]:
            if (abs(p[0] - clean[-1][0]) > 1e-5 or abs(p[1] - clean[-1][1]) > 1e-5):
                clean.append(p)
        if abs(clean[0][0] - clean[-1][0]) < 1e-5 and abs(clean[0][1] - clean[-1][1]) < 1e-5:
            clean.pop()
        vs = [bm.verts.new((x, y - width / 2, z)) for x, z in clean]
        f = bm.faces.new(vs)
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, width, 0), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # Concave ngons render badly when bevelled; triangulate caps beautifully.
        caps = [fc for fc in bm.faces if abs(fc.normal.y) > 0.9]
        bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="BEAUTY")
        bm.to_mesh(me)
        bm.free()
        ob = self._obj(nm, me, material, bevel)
        for p in me.polygons:
            if abs(p.normal.y) > 0.9:
                p.use_smooth = False
        return ob

    def lathe(self, nm, material, rings, axis_z=0.0, y=0.0, segs=24, bevel=0.0, axis="X"):
        """Round part along X: rings = [(x, radius), ...]."""
        me = bpy.data.meshes.new(nm)
        bm = bmesh.new()
        loops = []
        for x, r in rings:
            loop = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                if axis == "X":
                    loop.append(bm.verts.new((x, y + r * math.cos(a), axis_z + r * math.sin(a))))
                elif axis == "Z":  # vertical: centre (axis_z, y), rings give (z, r)
                    loop.append(bm.verts.new((axis_z + r * math.cos(a), y + r * math.sin(a), x)))
                else:  # Y axis: x/z circle, rings give (y, r)
                    loop.append(bm.verts.new((axis_z + r * math.cos(a), x, y + r * math.sin(a))))
            loops.append(loop)
        for a, b in zip(loops, loops[1:]):
            for i in range(segs):
                bm.faces.new([a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]])
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        return self._obj(nm, me, material, bevel, smooth=True)

    def box(self, nm, material, size, loc, bevel=0.0015):
        me = bpy.data.meshes.new(nm)
        bm = bmesh.new()
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=r["verts"])
        bmesh.ops.translate(bm, vec=loc, verts=r["verts"])
        bm.to_mesh(me)
        bm.free()
        return self._obj(nm, me, material, bevel)

    def rail(self, nm, material, x0, x1, z, width=0.021):
        """Picatinny rail: base plus cross teeth every 10 mm."""
        self.box(nm, material, (x1 - x0, width, 0.006), ((x0 + x1) / 2, 0, z + 0.003))
        x = x0 + 0.004
        i = 0
        while x < x1 - 0.004:
            self.box("%s_t%d" % (nm, i), material, (0.0052, width, 0.0045), (x, 0, z + 0.0082), 0.0006)
            x += 0.01
            i += 1


# --- Shared parts -----------------------------------------------------------------

def curved_mag(g, nm, material, top_x, top_z, length, depth_top, depth_bot, radius, width, ribs=True):
    """Banana magazine: the spine follows an arc curving forward as it drops."""
    th = length / radius
    cx, cz = top_x + depth_top / 2 + radius, top_z
    n = 14
    back, front = [], []
    for i in range(n + 1):
        t = i / n
        a = math.pi + th * t
        px, pz = cx + radius * math.cos(a), cz + radius * math.sin(a)
        # Normal pointing to the curve centre (forward-ish).
        nx, nz = -math.cos(a), -math.sin(a)
        half = (depth_top + (depth_bot - depth_top) * t) / 2
        back.append((px - nx * half, pz - nz * half))
        front.append((px + nx * half, pz + nz * half))
    pts = back + list(reversed(front))
    ob = g.profile(nm, material, pts, width, bevel=0.002)
    # Floorplate and ribs.
    a = math.pi + th
    px, pz = cx + radius * math.cos(a), cz + radius * math.sin(a)
    bp = g.profile(nm + "_base", material, [(px - 0.03, pz - 0.004), (px + 0.032, pz - 0.004), (px + 0.03, pz + 0.008), (px - 0.028, pz + 0.008)], width + 0.004, bevel=0.0015)
    bp.rotation_euler = (0, -(th * 0.95), 0)
    bp.location = (0, 0, 0)
    # Rotate the base around its own centre.
    me = bp.data
    c = Vector((px, 0, pz))
    for v in me.vertices:
        v.co = (Matrix.Rotation(-th, 3, "Y") @ (v.co - c)) + c
    bp.rotation_euler = (0, 0, 0)
    if ribs:
        for k, t in enumerate((0.3, 0.55, 0.8)):
            a = math.pi + th * t
            px, pz = cx + radius * math.cos(a), cz + radius * math.sin(a)
            nx, nz = -math.cos(a), -math.sin(a)
            half = (depth_top + (depth_bot - depth_top) * t) / 2 * 0.8
            rib = [(px - nx * half - nz * 0.004, pz - nz * half + nx * 0.004), (px + nx * half - nz * 0.004, pz + nz * half + nx * 0.004),
                   (px + nx * half + nz * 0.004, pz + nz * half - nx * 0.004), (px - nx * half + nz * 0.004, pz - nz * half - nx * 0.004)]
            g.profile("%s_rib%d" % (nm, k), material, rib, width + 0.003, bevel=0.001)
    return ob


def trigger_group(g, mat_guard, mat_trig, x, z, size=1.0):
    """Trigger guard (open C below the receiver) and a curved trigger."""
    s = size
    outer = path((x - 0.032 * s, z), arc(x - 0.022 * s, z - 0.03 * s, 0.012 * s, 180, 270, 4), (x + 0.03 * s, z - 0.042 * s), arc(x + 0.03 * s, z - 0.03 * s, 0.012 * s, 270, 360, 4), (x + 0.042 * s, z))
    inner = path((x + 0.036 * s, z), arc(x + 0.03 * s, z - 0.03 * s, 0.006 * s, 0, -90, 4), (x - 0.022 * s, z - 0.036 * s), arc(x - 0.022 * s, z - 0.03 * s, 0.006 * s, 270, 180, 4), (x - 0.026 * s, z))
    g.profile("guard", mat_guard, outer + inner, 0.012, bevel=0.0012)
    trig = path((x + 0.004 * s, z), arc(x + 0.016 * s, z - 0.012 * s, 0.014 * s, 160, 245, 5), (x - 0.0 * s, z - 0.026 * s), arc(x + 0.012 * s, z - 0.012 * s, 0.009 * s, 235, 165, 5))
    g.profile("trigger", mat_trig, trig, 0.007, bevel=0.0008)


# --- Guns -----------------------------------------------------------------------

def kodiak(coll, M, loc=(0, 0, 0)):
    """Kodiak AR: stamped-steel AK-pattern rifle, wood furniture, banana mag."""
    g = Gun("kodiak", coll, loc)
    # Receiver with the dust cover rounding off at the back.
    rec = path((0.14, -0.022), (0.14, 0.028), (0.11, 0.034), (-0.12, 0.034), arc(-0.12, 0.016, 0.018, 90, 150, 4), (-0.16, 0.008), (-0.16, -0.022))
    g.profile("receiver", M["steel"], rec, 0.046, bevel=0.003)
    g.profile("dustcover", M["steel"], path((0.105, 0.03), (0.105, 0.046), arc(-0.115, 0.03, 0.016, 90, 180, 5), (-0.131, 0.03)), 0.04, bevel=0.004)
    for i, x in enumerate((-0.09, -0.06, -0.03)):
        g.box("cover_rib%d" % i, M["steel"], (0.004, 0.042, 0.004), (x, 0, 0.046))
    g.profile("rearsight", M["steel"], [(0.105, 0.03), (0.145, 0.03), (0.145, 0.052), (0.125, 0.056), (0.105, 0.05)], 0.03, bevel=0.002)
    g.profile("selector", M["steel"], path((-0.01, 0.005), (0.06, 0.012), (0.075, 0.004), (0.065, -0.002), (-0.012, -0.004)), 0.05, bevel=0.001)
    g.box("charging", M["steel"], (0.012, 0.016, 0.01), (0.075, 0.03, 0.024), 0.003)
    # Magwell lip.
    g.box("magwell", M["steel"], (0.06, 0.048, 0.01), (0.062, 0, -0.022))
    # Barrel, gas tube, front sight, slant brake.
    g.lathe("barrel", M["steel"], [(0.14, 0.0095), (0.5, 0.0095), (0.5, 0.0085), (0.56, 0.0085)], axis_z=0.0)
    g.lathe("gastube", M["steel"], [(0.13, 0.011), (0.36, 0.011)], axis_z=0.032)
    g.profile("gasblock", M["steel"], path((0.33, -0.012), (0.37, -0.012), (0.37, 0.044), (0.355, 0.048), (0.33, 0.044)), 0.026, bevel=0.002)
    g.profile("frontsight", M["steel"], path((0.49, -0.012), (0.525, -0.012), (0.525, 0.02), arc(0.512, 0.04, 0.016, 0, 180, 8), (0.49, 0.02)), 0.022, bevel=0.0015)
    g.lathe("brake", M["steel"], [(0.56, 0.0125), (0.6, 0.0125), (0.6, 0.009), (0.605, 0.009)], axis_z=0.0)
    g.box("brake_cut", M["parked"], (0.02, 0.026, 0.004), (0.59, 0, 0.012))
    # Wood handguards (lower is chunkier with finger grooves, upper rides on the gas tube).
    lo = path((0.14, 0.012), (0.33, 0.012), (0.335, -0.004), arc(0.31, -0.024, 0.02, 0, -60, 4), (0.22, -0.042), (0.16, -0.04), (0.14, -0.028))
    g.profile("handguard_lo", M["wood"], lo, 0.054, bevel=0.005)
    for i, x in enumerate((0.19, 0.235, 0.28)):
        g.box("groove%d" % i, M["wood"], (0.004, 0.056, 0.024), (x, 0, -0.018), 0.0015)
    up = path((0.155, 0.014), (0.325, 0.014), arc(0.31, 0.03, 0.016, -10, 90, 5), (0.17, 0.046), arc(0.17, 0.03, 0.016, 90, 190, 5))
    g.profile("handguard_up", M["wood"], up, 0.034, bevel=0.006)
    # Wood stock with a comb and a drop to the butt, steel buttplate.
    st = path((-0.155, 0.028), bez((-0.155, 0.028), (-0.28, 0.026), (-0.40, 0.006), 6), (-0.408, -0.09), bez((-0.408, -0.09), (-0.3, -0.07), (-0.24, -0.06), 5),
              bez((-0.24, -0.06), (-0.19, -0.04), (-0.155, -0.026), 5))
    g.profile("stock", M["wood"], st, 0.042, bevel=0.012)
    g.profile("buttplate", M["steel"], [(-0.408, 0.008), (-0.418, 0.006), (-0.418, -0.094), (-0.408, -0.092)], 0.046, bevel=0.002)
    # Pistol grip with a finger swell, raked back.
    grip = path((-0.108, -0.02), (-0.066, -0.02), bez((-0.066, -0.02), (-0.075, -0.07), (-0.088, -0.13), 6), (-0.122, -0.132), bez((-0.122, -0.132), (-0.12, -0.08), (-0.108, -0.02), 6))
    g.profile("grip", M["bakelite"], grip, 0.032, bevel=0.005)
    trigger_group(g, M["steel"], M["steel"], -0.045, -0.022)
    # The banana magazine.
    curved_mag(g, "mag", M["parked"], 0.04, -0.024, 0.22, 0.05, 0.04, 0.32, 0.028)
    return g


def hammer(coll, M, loc=(0, 0, 0)):
    """Hammer LMG: heavy belt-style receiver, drum magazine, bipod, carry handle."""
    g = Gun("hammer", coll, loc)
    rec = path((0.18, -0.03), (0.18, 0.045), (0.16, 0.055), (-0.17, 0.055), arc(-0.17, 0.02, 0.035, 90, 180, 5), (-0.205, -0.03))
    g.profile("receiver", M["poly_od"], rec, 0.07, bevel=0.004)
    g.profile("feedcover", M["parked"], path((0.12, 0.05), (0.12, 0.07), arc(-0.07, 0.05, 0.02, 90, 180, 5), (-0.09, 0.05)), 0.066, bevel=0.004)
    g.rail("toprail", M["parked"], -0.07, 0.11, 0.07)
    for i, x in enumerate((-0.12, -0.09, 0.14)):
        g.box("rivet%d" % i, M["bright"], (0.006, 0.072, 0.006), (x, 0, -0.012), 0.002)
    # Heavy barrel with cooling flutes, gas block, flash hider.
    g.lathe("barrel", M["steel"], [(0.18, 0.016), (0.62, 0.016), (0.62, 0.012), (0.66, 0.012)])
    for i in range(6):
        g.box("flute%d" % i, M["parked"], (0.05, 0.034, 0.004), (0.24 + i * 0.06, 0, 0.0))
    g.profile("gasblock", M["parked"], path((0.5, -0.03), (0.54, -0.03), (0.54, 0.03), (0.5, 0.03)), 0.04, bevel=0.003)
    g.lathe("gastube", M["parked"], [(0.18, 0.012), (0.52, 0.012)], axis_z=-0.03)
    fh = [(0.66, 0.014), (0.70, 0.016), (0.72, 0.016), (0.72, 0.01)]
    g.lathe("flash", M["steel"], fh, segs=8)
    g.profile("frontpost", M["steel"], path((0.6, 0.012), (0.62, 0.012), (0.618, 0.05), (0.603, 0.05)), 0.008, bevel=0.001)
    # Handguard.
    hg = path((0.18, 0.035), (0.44, 0.035), arc(0.44, 0.0, 0.035, 90, -90, 8), (0.18, -0.035))
    g.profile("handguard", M["poly"], hg, 0.07, bevel=0.006)
    for i in range(5):
        g.box("vent%d" % i, M["steel"], (0.025, 0.072, 0.008), (0.215 + i * 0.045, 0, 0.012), 0.002)
    # Carry handle.
    for i, x in enumerate((-0.035, 0.035)):
        g.profile("handle_post%d" % i, M["parked"], [(x - 0.008, 0.068), (x + 0.008, 0.068), (x + 0.006, 0.112), (x - 0.006, 0.112)], 0.014, bevel=0.002)
    g.profile("handle_bar", M["poly"], path((-0.05, 0.108), (0.05, 0.108), arc(0.05, 0.118, 0.01, -90, 90, 5), (-0.05, 0.128), arc(-0.05, 0.118, 0.01, 90, 270, 5)), 0.02, bevel=0.003)
    # Skeleton stock.
    st = path((-0.2, 0.045), bez((-0.2, 0.045), (-0.33, 0.045), (-0.45, 0.03), 6), (-0.45, -0.1), (-0.41, -0.104),
              bez((-0.41, -0.104), (-0.33, -0.07), (-0.27, -0.04), 6), bez((-0.27, -0.04), (-0.23, -0.03), (-0.2, -0.03), 4))
    g.profile("stock", M["poly"], st, 0.044, bevel=0.01)
    g.profile("stock_cheek", M["poly_od"], path((-0.26, 0.045), (-0.42, 0.034), (-0.42, 0.054), bez((-0.42, 0.054), (-0.34, 0.062), (-0.27, 0.058), 4)), 0.036, bevel=0.006)
    g.profile("eject", M["steel"], [(0.02, 0.01), (0.1, 0.01), (0.1, 0.03), (0.02, 0.03)], 0.072, bevel=0.002)
    g.profile("buttpad", M["poly_od"], [(-0.45, 0.032), (-0.47, 0.03), (-0.47, -0.105), (-0.45, -0.103)], 0.05, bevel=0.004)
    grip = path((-0.13, -0.03), (-0.085, -0.03), bez((-0.085, -0.03), (-0.095, -0.08), (-0.108, -0.14), 6), (-0.145, -0.142), bez((-0.145, -0.142), (-0.142, -0.09), (-0.13, -0.03), 6))
    g.profile("grip", M["poly"], grip, 0.034, bevel=0.006)
    trigger_group(g, M["poly"], M["steel"], -0.06, -0.032)
    # Drum magazine: a flat disc on its side, with a feed neck into the receiver.
    dx, dz, dr = 0.04, -0.16, 0.085
    g.profile("drum_neck", M["parked"], path((0.015, -0.032), (0.075, -0.032), (0.07, -0.085), (0.02, -0.085)), 0.05, bevel=0.003)
    g.lathe("drum", M["poly"], [(-0.034, dr * 0.92), (-0.03, dr), (0.03, dr), (0.034, dr * 0.92)], axis_z=dx, y=dz, segs=40, axis="Y")
    g.lathe("drum_rim_l", M["parked"], [(-0.036, dr * 0.95), (-0.03, dr * 0.95)], axis_z=dx, y=dz, segs=40, axis="Y")
    g.lathe("drum_rim_r", M["parked"], [(0.03, dr * 0.95), (0.036, dr * 0.95)], axis_z=dx, y=dz, segs=40, axis="Y")
    g.lathe("drum_hub", M["bright"], [(0.034, 0.022), (0.044, 0.018)], axis_z=dx, y=dz, segs=24, axis="Y")
    g.lathe("drum_key", M["parked"], [(0.044, 0.006), (0.05, 0.006)], axis_z=dx, y=dz, segs=12, axis="Y")
    for s2 in (-1, 1):
        g.lathe("drum_step%d" % s2, M["poly"], [(s2 * 0.030, dr * 0.7), (s2 * 0.036, dr * 0.7)], axis_z=dx, y=dz, segs=40, axis="Y", bevel=0.002)
        g.lathe("drum_ring%d" % s2, M["parked"], [(s2 * 0.036, dr * 0.45), (s2 * 0.039, dr * 0.45)], axis_z=dx, y=dz, segs=32, axis="Y")
    # Turn the drum 90 degrees so its faces point fore and aft (edge-on from the side).
    turn = Matrix.Translation((dx, 0, dz)) @ Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Translation((-dx, 0, -dz))
    for ob in g.root.children:
        if ob.name.split("_", 1)[1].startswith("drum") and not ob.name.endswith("drum_neck"):
            ob.data.transform(turn)
    # Bipod folded up: hinged at the gas block, legs stowed forward under the barrel.
    g.profile("bipod_hinge", M["parked"], path((0.505, -0.034), (0.535, -0.034), (0.535, -0.016), (0.505, -0.016)), 0.04, bevel=0.002)
    for s in (-1, 1):
        g.lathe("bipod%d" % s, M["parked"], [(0.52, 0.0055), (0.675, 0.0055)], axis_z=-0.026, y=s * 0.013, segs=12)
        g.lathe("foot%d" % s, M["poly"], [(0.665, 0.009), (0.69, 0.009)], axis_z=-0.026, y=s * 0.013, segs=12)
    return g


# --- More shared parts --------------------------------------------------------------

def pgrip(g, mat, xf, xb, z, h, rake, nm="grip", w=0.032, swell=0.006):
    """Pistol grip: top front/back x at height z, dropping h and raked back by `rake`."""
    bf, bb = xf - rake, xb - rake
    pts = path((xb, z), (xf, z), bez((xf, z), (xf - rake * 0.4 + swell, z - h * 0.45), (bf, z - h), 6), (bb, z - h - 0.002),
               bez((bb, z - h - 0.002), (xb - rake * 0.55 - swell * 0.5, z - h * 0.5), (xb, z), 6))
    return g.profile(nm, mat, pts, w, bevel=0.005)


def scope(g, M, x0, x1, z, mount_z, tube=0.0127, obj=0.024, eye=0.02, mat=None, rings=(0.3, 0.68)):
    """Riflescope along X at height z: eye bell, tube, turrets, objective bell, lenses, rings."""
    mat = mat or M["steel"]
    L = x1 - x0
    g.lathe("scope", mat, [(x0, eye * 0.82), (x0 + 0.004, eye), (x0 + 0.2 * L, eye), (x0 + 0.3 * L, tube), (x0 + 0.62 * L, tube),
                            (x0 + 0.8 * L, obj), (x1, obj), (x1, obj * 0.9)], axis_z=z, segs=36)
    g.lathe("scope_lens_f", M["glass"], [(x1 - 0.002, obj * 0.86), (x1 + 0.0004, obj * 0.86)], axis_z=z, segs=36)
    g.lathe("scope_lens_r", M["glass"], [(x0 - 0.0004, eye * 0.78), (x0 + 0.002, eye * 0.78)], axis_z=z, segs=36)
    g.lathe("scope_eyering", M["poly"], [(x0 + 0.004, eye * 1.04), (x0 + 0.03, eye * 1.04)], axis_z=z, segs=36)
    tx = x0 + 0.46 * L
    g.lathe("scope_turret_t", mat, [(z + tube * 0.5, 0.012), (z + tube + 0.008, 0.012), (z + tube + 0.009, 0.0105), (z + tube + 0.016, 0.0105), (z + tube + 0.017, 0.009)],
            axis_z=tx, y=0.0, segs=24, axis="Z")
    g.lathe("scope_turret_s", mat, [(-(tube + 0.016), 0.009), (-(tube + 0.015), 0.0105), (-(tube + 0.008), 0.0105), (-(tube * 0.5), 0.012)],
            axis_z=tx, y=z, segs=24, axis="Y")
    g.lathe("scope_saddle", mat, [(tx - 0.022, tube * 1.25), (tx + 0.022, tube * 1.25)], axis_z=z, segs=36)
    for i, f in enumerate(rings):
        rx = x0 + f * L
        h = z - mount_z
        g.box("scope_ring%d" % i, M["parked"], (0.014, 2 * tube + 0.007, tube + 0.004 + h * 0.5), (rx, 0, mount_z + (tube + 0.004 + h * 0.5) / 2), 0.002)
        g.lathe("scope_band%d" % i, M["parked"], [(rx - 0.007, tube + 0.0035), (rx + 0.007, tube + 0.0035)], axis_z=z, segs=36)
        g.box("scope_base%d" % i, M["parked"], (0.024, 0.026, 0.008), (rx, 0, mount_z + 0.004), 0.0015)


def ar_stock(g, M, x, z, mat, nm="stock"):
    """Buffer tube with a sliding stock and rubber pad."""
    g.lathe(nm + "_tube", M["alu"], [(x, 0.0145), (x - 0.24, 0.0145), (x - 0.24, 0.012)], axis_z=z, segs=24)
    g.lathe(nm + "_nut", M["alu"], [(x - 0.004, 0.018), (x - 0.016, 0.018)], axis_z=z, segs=12)
    body = path((x - 0.12, z + 0.022), (x - 0.25, z + 0.027), (x - 0.268, z + 0.032), (x - 0.268, z - 0.1), (x - 0.245, z - 0.1),
                bez((x - 0.245, z - 0.1), (x - 0.19, z - 0.05), (x - 0.135, z - 0.022), 5), (x - 0.12, z - 0.018))
    g.profile(nm, mat, body, 0.04, bevel=0.006)
    g.profile(nm + "_pad", M["poly"], [(x - 0.268, z + 0.033), (x - 0.282, z + 0.031), (x - 0.282, z - 0.101), (x - 0.268, z - 0.1)], 0.044, bevel=0.004)
    g.box(nm + "_latch", M["parked"], (0.03, 0.044, 0.008), (x - 0.15, 0, z - 0.024), 0.002)


def flash_hider(g, M, x, z, r=0.0105, length=0.05, slots=4):
    g.lathe("flash", M["steel"], [(x, r * 0.85), (x + 0.008, r), (x + length, r), (x + length, r * 0.75)], axis_z=z, segs=20)
    for i in range(slots):
        g.box("flash_slot%d" % i, M["poly"], (length * 0.5, 2 * r + 0.0005, 0.0025), (x + length * 0.6, 0, z + (i - (slots - 1) / 2) * r * 0.55), 0.0004)


def wire(g, nm, mat, pts, radius=0.0016):
    """A smooth wire through `pts` (x, y, z)."""
    cu = bpy.data.curves.new(nm, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (*c, 1)
    sp.order_u = 3
    sp.use_endpoint_u = True
    sp.resolution_u = 10
    ob = bpy.data.objects.new("%s_%s" % (g.name, nm), cu)
    ob.data.materials.append(mat)
    g.coll.objects.link(ob)
    ob.parent = g.root
    return ob


# --- Pistols ------------------------------------------------------------------------

def _pistol(g, M, L=0.19, H=0.033, W=0.025, slide="steel", frame="poly", grip=None, gh=0.11, rake=0.03, hammer=False, ser=7):
    """Common handgun: slide with serrations and sights, frame with rail, raked grip."""
    x0 = -0.075
    x1 = x0 + L
    S, F, G = M[slide], M[frame], M[grip or frame]
    g.profile("slide", S, path((x0, 0.0), (x1, 0.0), (x1, H * 0.7), (x1 - 0.012, H), (x0 + 0.006, H), (x0, H - 0.006)), W, bevel=0.002)
    for i in range(ser):
        g.box("ser%d" % i, M["parked"], (0.0022, W + 0.0012, H * 0.62), (x0 + 0.01 + i * 0.0055, 0, H * 0.5), 0.0004)
    g.box("port", M["parked"], (0.034, W + 0.0008, H * 0.36), (x0 + 0.09, 0, H * 0.74), 0.0004)
    g.lathe("muzzle", M["steel"], [(x1 - 0.002, 0.0064), (x1 + 0.0015, 0.0064), (x1 + 0.0015, 0.0042)], axis_z=H * 0.5)
    g.box("fsight", M["steel"], (0.006, 0.005, 0.006), (x1 - 0.012, 0, H + 0.003), 0.001)
    g.profile("rsight", M["steel"], [(x0 + 0.008, H - 0.001), (x0 + 0.022, H - 0.001), (x0 + 0.02, H + 0.007), (x0 + 0.008, H + 0.007)], 0.02, bevel=0.001)
    fx1 = x1 - 0.01
    g.profile("frame", F, path((x0 + 0.004, 0.001), (fx1, 0.001), (fx1, -0.012), (fx1 - 0.01, -0.017), (0.04, -0.017), (-0.03, -0.015), (x0 + 0.004, -0.01)), W - 0.002, bevel=0.0025)
    for i in range(3):
        g.box("frail%d" % i, F, (0.004, W - 0.004, 0.003), (fx1 - 0.03 + i * 0.009, 0, -0.0185), 0.0005)
    pgrip(g, G, -0.03, x0 - 0.008, -0.008, gh, rake, w=W + 0.005)
    g.profile("tail", F, [(x0 + 0.012, 0.0), (x0 - 0.004, 0.0), (x0 - 0.016, -0.01), (x0 - 0.006, -0.014)], W - 0.004, bevel=0.002)
    g.box("slidestop", M["steel"], (0.022, W + 0.003, 0.004), (-0.01, 0, -0.004), 0.0012)
    trigger_group(g, F, M["steel"], 0.0, -0.015, 0.85)
    bz = -0.008 - gh
    bf, bb = -0.03 - rake, x0 - 0.008 - rake
    g.profile("baseplate", F, [(bb - 0.003, bz + 0.003), (bf + 0.003, bz + 0.003), (bf + 0.002, bz - 0.006), (bb - 0.004, bz - 0.006)], W + 0.006, bevel=0.0012)
    if hammer:
        g.profile("hammer", M["steel"], path((x0 - 0.002, H * 0.45), (x0 + 0.004, H * 0.75), arc(x0 - 0.006, H * 0.82, 0.007, 10, 180, 5), (x0 - 0.011, H * 0.45)), 0.008, bevel=0.001)
    return x0, x1, bz, bf, bb


def pk9(coll, M, loc=(0, 0, 0)):
    """PK-9: polymer striker-fired 9 mm."""
    g = Gun("pk9", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M)
    for i in range(4):  # Grip texture panels.
        g.box("stipple%d" % i, M["parked"], (0.034, 0.0312, 0.003), (-0.062 - i * 0.0065, 0, -0.035 - i * 0.02), 0.001)
    return g


def sentry(coll, M, loc=(0, 0, 0)):
    """Sentry .45: all-steel single-action with walnut panels and a hammer."""
    g = Gun("sentry", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M, L=0.205, H=0.031, W=0.023, frame="parked", grip="wood", gh=0.105, rake=0.022, hammer=True, ser=8)
    for i, (sx, sz) in enumerate(((-0.065, -0.03), (-0.078, -0.09))):
        g.lathe("screw%d" % i, M["bright"], [(-0.0175, 0.0035), (-0.0152, 0.0035)], axis_z=sx, y=sz, segs=12, axis="Y")
    g.box("safety", M["steel"], (0.014, 0.027, 0.005), (x0 + 0.02, 0, -0.003), 0.0015)
    return g


def duster(coll, M, loc=(0, 0, 0)):
    """Duster P7: compact with a tan frame, lightened slide and compensator."""
    g = Gun("duster", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M, L=0.18, H=0.034, frame="poly_tan", gh=0.1, rake=0.026)
    for i in range(3):
        g.box("cut%d" % i, M["parked"], (0.016, 0.014, 0.004), (x1 - 0.05 - i * 0.022, 0, 0.033), 0.0015)
    g.profile("comp", M["steel"], path((x1, 0.0), (x1 + 0.03, 0.0), (x1 + 0.03, 0.026), (x1 + 0.024, 0.033), (x1, 0.033)), 0.027, bevel=0.002)
    for i in range(2):
        g.box("comp_port%d" % i, M["poly"], (0.006, 0.02, 0.006), (x1 + 0.01 + i * 0.011, 0, 0.033), 0.001)
    return g


def viper(coll, M, loc=(0, 0, 0)):
    """Viper MP: machine pistol, extended magazine, compensator and selector."""
    g = Gun("viper", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M, L=0.19, frame="poly", gh=0.11, rake=0.03)
    drop = 0.07
    sh = drop * 0.03 / 0.11
    g.profile("extmag", M["parked"], [(bb + 0.002, bz - 0.005), (bf - 0.002, bz - 0.005), (bf - 0.002 - sh, bz - drop), (bb + 0.002 - sh, bz - drop)], 0.024, bevel=0.0015)
    g.profile("extmag_base", M["poly"], [(bb - sh - 0.002, bz - drop + 0.002), (bf - sh + 0.002, bz - drop + 0.002), (bf - sh + 0.002, bz - drop - 0.007), (bb - sh - 0.003, bz - drop - 0.007)], 0.028, bevel=0.0015)
    g.profile("comp", M["parked"], path((x1, -0.002), (x1 + 0.034, -0.002), (x1 + 0.034, 0.03), (x1, 0.034)), 0.027, bevel=0.002)
    for i in range(3):
        g.box("comp_port%d" % i, M["steel"], (0.005, 0.0285, 0.012), (x1 + 0.008 + i * 0.009, 0, 0.022), 0.001)
    g.box("selector", M["bright"], (0.012, 0.03, 0.006), (x0 + 0.03, 0, 0.012), 0.002)
    return g


def falcon(coll, M, loc=(0, 0, 0)):
    """Falcon 5.7: long slim slide, OD frame, long grip for the 20-round mag."""
    g = Gun("falcon", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M, L=0.205, H=0.03, W=0.023, frame="poly_od", gh=0.122, rake=0.026, ser=9)
    g.profile("slide_chamfer", M["steel"], path((x1 - 0.07, 0.03), (x1 - 0.012, 0.03), (x1, 0.021), (x1 - 0.07, 0.024)), 0.019, bevel=0.002)
    return g


def magnum(coll, M, loc=(0, 0, 0)):
    """Magnum .50: big bright steel gas pistol with a fluted triangular barrel."""
    g = Gun("magnum", coll, loc)
    x0, x1, bz, bf, bb = _pistol(g, M, L=0.27, H=0.044, W=0.03, slide="bright", frame="bright", grip="poly", gh=0.12, rake=0.032, hammer=True, ser=0)
    g.profile("barrel_top", M["bright"], path((x0 + 0.1, 0.044), (x1 - 0.004, 0.044), (x1 - 0.004, 0.052), (x0 + 0.1, 0.052)), 0.016, bevel=0.003)
    g.box("top_rail", M["parked"], (0.15, 0.012, 0.004), (x0 + 0.17, 0, 0.054), 0.001)
    for i in range(2):
        g.box("flute%d" % i, M["parked"], (0.11, 0.0304, 0.002), (x1 - 0.075, 0, 0.026 + i * 0.008), 0.0006)
    for i in range(6):
        g.box("mser%d" % i, M["parked"], (0.0025, 0.0306, 0.026), (x0 + 0.012 + i * 0.006, 0, 0.022), 0.0004)
    return g


# --- SMGs ---------------------------------------------------------------------------

def hornet(coll, M, loc=(0, 0, 0)):
    """Hornet M10: stamped box machine pistol, mag in the grip, collapsed wire stock."""
    g = Gun("hornet", coll, loc)
    rec = path((-0.1, -0.03), (0.12, -0.03), (0.12, 0.028), arc(0.11, 0.028, 0.01, 0, 90, 3), (-0.09, 0.038), arc(-0.09, 0.028, 0.01, 90, 180, 3))
    g.profile("receiver", M["parked"], rec, 0.052, bevel=0.003)
    g.box("bolt_slot", M["poly"], (0.11, 0.012, 0.004), (0.0, 0, 0.037))
    g.box("bolt_knob", M["steel"], (0.012, 0.016, 0.014), (0.05, 0, 0.044), 0.004)
    g.profile("rsight", M["parked"], [(-0.085, 0.036), (-0.06, 0.036), (-0.064, 0.05), (-0.08, 0.05)], 0.03, bevel=0.0015)
    g.profile("fsight", M["parked"], [(0.09, 0.036), (0.11, 0.036), (0.106, 0.052), (0.094, 0.052)], 0.03, bevel=0.0015)
    rings = [(0.12, 0.011), (0.135, 0.011), (0.135, 0.008)]
    for i in range(10):
        rings.append((0.137 + i * 0.004, 0.0088 if i % 2 == 0 else 0.008))
    rings += [(0.18, 0.008), (0.18, 0.0055)]
    g.lathe("barrel", M["steel"], rings, axis_z=0.012, segs=20)
    g.profile("grip", M["poly"], path((-0.035, -0.028), (0.012, -0.028), (0.008, -0.13), (-0.04, -0.13)), 0.046, bevel=0.005)
    for i in range(4):
        g.box("grip_tex%d" % i, M["parked"], (0.046, 0.047, 0.004), (-0.014, 0, -0.045 - i * 0.02), 0.001)
    g.profile("mag", M["parked"], [(-0.034, -0.13), (0.004, -0.13), (0.002, -0.205), (-0.036, -0.205)], 0.03, bevel=0.0015)
    g.profile("mag_base", M["poly"], [(-0.039, -0.2), (0.007, -0.2), (0.006, -0.211), (-0.04, -0.211)], 0.034, bevel=0.0015)
    trigger_group(g, M["parked"], M["steel"], 0.044, -0.03)
    g.profile("strap", M["parked"], path((0.096, -0.03), (0.12, -0.03), (0.12, -0.05), (0.112, -0.058), (0.1, -0.058), (0.1, -0.052), (0.11, -0.05), (0.112, -0.036), (0.096, -0.036)), 0.02, bevel=0.001)
    for s in (-1, 1):
        g.lathe("wire%d" % s, M["steel"], [(-0.118, 0.004), (0.06, 0.004)], axis_z=-0.006, y=s * 0.03, segs=10)
    g.profile("butt", M["steel"], path((-0.112, 0.032), (-0.122, 0.032), (-0.122, -0.042), (-0.112, -0.042)), 0.07, bevel=0.002)
    g.profile("butt_pad", M["poly"], path((-0.122, 0.028), (-0.13, 0.028), (-0.13, -0.038), (-0.122, -0.038)), 0.066, bevel=0.003)
    return g


def kestrel(coll, M, loc=(0, 0, 0)):
    """Kestrel K9: slim roller-delayed SMG, curved mag, drum rear sight, sliding stock."""
    g = Gun("kestrel", coll, loc)
    rec = path((-0.14, -0.018), (0.16, -0.018), (0.16, 0.026), arc(0.14, 0.026, 0.02, 0, 90, 4), (-0.12, 0.046), arc(-0.12, 0.026, 0.02, 90, 180, 4))
    g.profile("receiver", M["steel"], rec, 0.046, bevel=0.003)
    g.lathe("cocking_tube", M["steel"], [(0.1, 0.012), (0.3, 0.012), (0.3, 0.009)], axis_z=0.035)
    g.box("cocking_handle", M["poly"], (0.01, 0.03, 0.01), (0.22, -0.024, 0.04), 0.003)
    g.profile("handguard", M["poly"], path((0.16, 0.03), (0.29, 0.024), arc(0.29, 0.002, 0.022, 90, -90, 6), (0.17, -0.03), (0.16, -0.026)), 0.05, bevel=0.008)
    for i in range(4):
        g.box("hg_groove%d" % i, M["steel"], (0.004, 0.0505, 0.022), (0.19 + i * 0.024, 0, -0.004), 0.0012)
    g.lathe("barrel", M["steel"], [(0.29, 0.008), (0.335, 0.008), (0.335, 0.0095), (0.348, 0.0095), (0.348, 0.007), (0.36, 0.007), (0.36, 0.0045)], axis_z=0.002)
    for i in range(3):
        g.box("lug%d" % i, M["steel"], (0.008, 0.024, 0.004), (0.33, 0, 0.002 + (i - 1) * 0.008), 0.001)
    g.lathe("fsight_hood", M["steel"], [(0.262, 0.011), (0.282, 0.011)], axis_z=0.058)
    g.profile("fsight_base", M["steel"], [(0.262, 0.04), (0.282, 0.04), (0.28, 0.05), (0.264, 0.05)], 0.016, bevel=0.001)
    g.profile("rsight_base", M["steel"], [(-0.115, 0.044), (-0.085, 0.044), (-0.088, 0.054), (-0.112, 0.054)], 0.024, bevel=0.0015)
    g.lathe("rsight_drum", M["steel"], [(-0.013, 0.011), (0.013, 0.011)], axis_z=-0.1, y=0.064, segs=10, axis="Y", bevel=0.0012)
    g.profile("trigger_housing", M["poly"], path((-0.08, -0.016), (0.05, -0.016), (0.05, -0.03), (-0.08, -0.03)), 0.04, bevel=0.003)
    pgrip(g, M["poly"], -0.034, -0.078, -0.026, 0.1, 0.026)
    trigger_group(g, M["poly"], M["steel"], 0.005, -0.028)
    g.box("magwell", M["steel"], (0.045, 0.034, 0.016), (0.096, 0, -0.024), 0.002)
    curved_mag(g, "mag", M["parked"], 0.078, -0.018, 0.2, 0.032, 0.03, 0.42, 0.024)
    g.profile("endcap", M["poly"], path((-0.135, 0.04), (-0.165, 0.036), (-0.165, -0.014), (-0.135, -0.018)), 0.044, bevel=0.004)
    for s in (-1, 1):
        g.lathe("stock_rod%d" % s, M["steel"], [(-0.165, 0.0045), (-0.32, 0.0045)], axis_z=0.018, y=s * 0.02, segs=10)
    g.profile("buttplate", M["poly"], path((-0.31, 0.042), (-0.34, 0.04), bez((-0.34, 0.04), (-0.348, -0.01), (-0.338, -0.064), 5), (-0.31, -0.06)), 0.062, bevel=0.005)
    return g


def bulldog(coll, M, loc=(0, 0, 0)):
    """Bulldog .45: boxy polymer SMG, straight mag, skeleton side-folding stock."""
    g = Gun("bulldog", coll, loc)
    g.profile("receiver", M["poly"], path((-0.17, -0.03), (0.18, -0.03), (0.2, -0.01), (0.2, 0.038), (0.18, 0.048), (-0.15, 0.048), (-0.17, 0.035)), 0.06, bevel=0.006)
    for i in range(3):
        g.box("vent%d" % i, M["steel"], (0.03, 0.0605, 0.008), (0.1 + i * 0.035, 0, 0.0), 0.002)
    g.rail("toprail", M["parked"], -0.11, 0.16, 0.048)
    g.lathe("barrel", M["steel"], [(0.2, 0.01), (0.24, 0.01), (0.24, 0.012), (0.255, 0.012), (0.255, 0.008)], axis_z=0.01)
    g.box("cocking", M["steel"], (0.016, 0.068, 0.012), (0.13, 0, 0.032), 0.003)
    pgrip(g, M["poly"], -0.065, -0.11, -0.028, 0.105, 0.028)
    trigger_group(g, M["poly"], M["steel"], -0.032, -0.03)
    g.profile("magwell", M["poly"], [(0.025, -0.028), (0.085, -0.028), (0.08, -0.052), (0.03, -0.052)], 0.044, bevel=0.003)
    curved_mag(g, "mag", M["poly"], 0.034, -0.05, 0.17, 0.042, 0.038, 1.6, 0.03)
    g.box("hinge", M["parked"], (0.014, 0.05, 0.06), (-0.172, 0, 0.004), 0.003)
    g.profile("stock_top", M["poly"], path((-0.17, 0.04), (-0.39, 0.04), (-0.39, 0.022), (-0.17, 0.022)), 0.032, bevel=0.004)
    g.profile("stock_low", M["poly"], [(-0.17, -0.008), (-0.17, -0.026), (-0.385, -0.088), (-0.385, -0.066)], 0.03, bevel=0.004)
    g.profile("stock_butt", M["poly"], path((-0.38, 0.045), (-0.41, 0.045), (-0.41, -0.095), (-0.38, -0.095)), 0.04, bevel=0.006)
    return g


def swarm(coll, M, loc=(0, 0, 0)):
    """Swarm 50: bullpup PDW with a translucent top-mounted 50-round magazine."""
    g = Gun("swarm", coll, loc)
    body = path((-0.25, 0.03), (-0.25, -0.09), bez((-0.25, -0.09), (-0.19, -0.088), (-0.15, -0.04), 5), (0.2, -0.032),
                (0.25, -0.005), (0.25, 0.03), (0.2, 0.036), (-0.22, 0.036))
    g.profile("body", M["poly"], body, 0.056, bevel=0.009)
    g.box("seam", M["parked"], (0.38, 0.0565, 0.003), (0.0, 0, -0.004), 0.0008)
    pgrip(g, M["poly"], -0.02, -0.065, -0.03, 0.1, 0.022, w=0.04)
    trigger_group(g, M["poly"], M["steel"], 0.012, -0.032)
    g.profile("handstop", M["poly"], path((0.15, -0.03), (0.185, -0.03), (0.175, -0.062), (0.16, -0.062)), 0.04, bevel=0.005)
    g.profile("mag", M["smoke"], path((-0.2, 0.034), (0.16, 0.034), (0.17, 0.048), (0.16, 0.062), (-0.19, 0.062), (-0.2, 0.05)), 0.05, bevel=0.004)
    for i in range(14):  # Rounds visible through the mag.
        g.box("round%d" % i, M["bright"], (0.004, 0.044, 0.012), (-0.17 + i * 0.024, 0, 0.048), 0.0015)
    g.box("mag_latch", M["poly"], (0.02, 0.052, 0.01), (-0.205, 0, 0.05), 0.003)
    g.profile("optic", M["poly"], path((0.0, 0.062), (0.07, 0.062), (0.07, 0.092), (0.06, 0.098), (0.01, 0.098), (0.0, 0.092)), 0.03, bevel=0.003)
    g.box("optic_glass", M["glass"], (0.002, 0.024, 0.024), (0.071, 0, 0.08), 0.0005)
    g.lathe("muzzle", M["steel"], [(0.25, 0.009), (0.29, 0.009), (0.29, 0.006)], axis_z=0.006)
    g.box("charger", M["steel"], (0.016, 0.064, 0.008), (0.17, 0, 0.022), 0.002)
    g.profile("buttpad", M["poly_od"], path((-0.25, 0.03), (-0.262, 0.028), (-0.262, -0.092), (-0.25, -0.095)), 0.058, bevel=0.004)
    return g


# --- Shotguns -----------------------------------------------------------------------

def breacher(coll, M, loc=(0, 0, 0)):
    """Breacher Pump: steel receiver, tube magazine, ribbed wood pump and stock."""
    g = Gun("breacher", coll, loc)
    g.profile("receiver", M["steel"], path((-0.1, -0.03), (0.12, -0.03), (0.12, 0.03), (-0.08, 0.032), (-0.1, 0.02)), 0.044, bevel=0.003)
    g.box("eject_port", M["parked"], (0.05, 0.0448, 0.018), (0.03, 0, 0.01), 0.002)
    g.box("loadport", M["parked"], (0.07, 0.03, 0.004), (0.03, 0, -0.03), 0.0015)
    g.lathe("barrel", M["steel"], [(0.12, 0.0125), (0.66, 0.0125), (0.66, 0.0105)], axis_z=0.014, segs=28)
    g.lathe("bead", M["bright"], [(0.0265, 0.0025), (0.031, 0.0025), (0.032, 0.0015)], axis_z=0.652, y=0.0, segs=12, axis="Z")
    g.lathe("tube", M["steel"], [(0.12, 0.011), (0.58, 0.011), (0.58, 0.012), (0.6, 0.012), (0.6, 0.009)], axis_z=-0.013, segs=24)
    g.profile("clamp", M["parked"], path((0.555, -0.026), (0.57, -0.026), (0.57, 0.028), (0.555, 0.028)), 0.03, bevel=0.002)
    g.profile("pump", M["wood"], path((0.22, 0.0), (0.42, 0.0), (0.428, -0.012), (0.42, -0.032), (0.22, -0.032), (0.212, -0.012)), 0.054, bevel=0.008)
    for i in range(7):
        g.box("pump_rib%d" % i, M["wood"], (0.005, 0.056, 0.02), (0.24 + i * 0.026, 0, -0.016), 0.0015)
    for s in (-1, 1):
        g.box("action_bar%d" % s, M["steel"], (0.11, 0.003, 0.006), (0.17, s * 0.0235, -0.008), 0.0006)
    st = path((-0.1, 0.026), bez((-0.1, 0.026), (-0.25, 0.02), (-0.44, 0.002), 6), (-0.44, -0.12), bez((-0.44, -0.12), (-0.3, -0.085), (-0.16, -0.05), 6), (-0.1, -0.03))
    g.profile("stock", M["wood"], st, 0.042, bevel=0.012)
    g.profile("pad", M["poly"], [(-0.438, 0.004), (-0.465, 0.004), (-0.465, -0.124), (-0.438, -0.12)], 0.046, bevel=0.005)
    trigger_group(g, M["steel"], M["steel"], -0.03, -0.03)
    return g


def tempest(coll, M, loc=(0, 0, 0)):
    """Tempest Auto-12: semi-auto polymer shotgun with a box magazine and AR-style stock."""
    g = Gun("tempest", coll, loc)
    g.profile("receiver", M["poly"], path((-0.12, -0.035), (0.14, -0.035), (0.14, 0.035), (-0.11, 0.035), (-0.12, 0.025)), 0.05, bevel=0.005)
    g.rail("toprail", M["parked"], -0.1, 0.13, 0.035)
    g.box("eject", M["steel"], (0.06, 0.0505, 0.02), (0.02, 0, 0.012), 0.002)
    g.box("charger", M["steel"], (0.012, 0.064, 0.012), (0.1, 0, 0.012), 0.004)
    g.profile("handguard", M["poly"], path((0.14, 0.03), (0.4, 0.028), (0.41, 0.015), (0.41, -0.02), (0.4, -0.03), (0.14, -0.033)), 0.056, bevel=0.006)
    for i in range(5):
        g.box("hg_slot%d" % i, M["steel"], (0.028, 0.0565, 0.007), (0.18 + i * 0.045, 0, -0.004), 0.002)
    g.lathe("barrel", M["steel"], [(0.41, 0.013), (0.58, 0.013), (0.58, 0.017), (0.62, 0.017), (0.62, 0.0135)], axis_z=0.01, segs=28)
    for i in range(3):
        g.box("choke_port%d" % i, M["poly"], (0.006, 0.035, 0.008), (0.588 + i * 0.01, 0, 0.022), 0.001)
    g.profile("fsight", M["steel"], [(0.39, 0.028), (0.408, 0.028), (0.404, 0.052), (0.394, 0.052)], 0.016, bevel=0.0015)
    g.box("magwell", M["poly"], (0.08, 0.06, 0.012), (0.06, 0, -0.038), 0.002)
    curved_mag(g, "mag", M["poly"], 0.022, -0.04, 0.11, 0.072, 0.068, 3.0, 0.052, ribs=False)
    pgrip(g, M["poly"], -0.055, -0.1, -0.032, 0.105, 0.028)
    trigger_group(g, M["poly"], M["steel"], -0.024, -0.035)
    ar_stock(g, M, -0.12, 0.012, M["poly"])
    return g


# --- Rifles -------------------------------------------------------------------------

def raptor(coll, M, loc=(0, 0, 0)):
    """Raptor 762: modernised AK with railed polymer furniture and a side-folding stock."""
    g = Gun("raptor", coll, loc)
    rec = path((0.14, -0.022), (0.14, 0.028), (0.11, 0.034), (-0.12, 0.034), arc(-0.12, 0.016, 0.018, 90, 150, 4), (-0.16, 0.008), (-0.16, -0.022))
    g.profile("receiver", M["parked"], rec, 0.046, bevel=0.003)
    g.profile("dustcover", M["parked"], path((0.105, 0.03), (0.105, 0.046), arc(-0.115, 0.03, 0.016, 90, 180, 5), (-0.131, 0.03)), 0.04, bevel=0.004)
    g.rail("cover_rail", M["steel"], -0.1, 0.09, 0.046)
    g.profile("selector", M["steel"], path((-0.01, 0.005), (0.06, 0.012), (0.075, 0.004), (0.065, -0.002), (-0.012, -0.004)), 0.05, bevel=0.001)
    g.box("charging", M["steel"], (0.012, 0.016, 0.01), (0.075, 0.03, 0.024), 0.003)
    g.box("magwell", M["parked"], (0.06, 0.048, 0.01), (0.062, 0, -0.022))
    g.lathe("barrel", M["steel"], [(0.14, 0.0095), (0.47, 0.0095)])
    g.lathe("gastube", M["parked"], [(0.13, 0.011), (0.36, 0.011)], axis_z=0.032)
    g.profile("gasblock", M["parked"], path((0.34, -0.012), (0.37, -0.012), (0.37, 0.044), (0.355, 0.048), (0.34, 0.044)), 0.026, bevel=0.002)
    g.profile("frontsight", M["parked"], path((0.43, -0.012), (0.46, -0.012), (0.46, 0.02), arc(0.447, 0.038, 0.014, 0, 180, 8), (0.433, 0.02)), 0.022, bevel=0.0015)
    g.profile("hg_lo", M["poly"], path((0.14, 0.012), (0.33, 0.012), (0.338, -0.004), (0.338, -0.03), (0.328, -0.04), (0.14, -0.04)), 0.05, bevel=0.005)
    for i in range(4):
        g.box("hg_slot%d" % i, M["steel"], (0.026, 0.0505, 0.007), (0.17 + i * 0.042, 0, -0.016), 0.002)
    g.profile("hg_up", M["poly"], path((0.155, 0.014), (0.33, 0.014), (0.33, 0.044), (0.155, 0.044)), 0.04, bevel=0.004)
    g.rail("hg_rail", M["parked"], 0.16, 0.32, 0.044)
    g.lathe("brake", M["steel"], [(0.47, 0.0145), (0.565, 0.0145), (0.565, 0.0105)], axis_z=0.0, segs=24)
    for i in range(3):
        g.box("brake_port%d" % i, M["poly"], (0.012, 0.0295, 0.02), (0.49 + i * 0.024, 0, 0.0), 0.002)
    g.box("hinge", M["parked"], (0.014, 0.05, 0.05), (-0.16, 0, 0.002), 0.003)
    g.profile("stock_top", M["poly"], path((-0.155, 0.03), (-0.4, 0.024), (-0.4, 0.006), (-0.155, 0.01)), 0.032, bevel=0.004)
    g.profile("stock_low", M["poly"], [(-0.155, -0.008), (-0.155, -0.026), (-0.39, -0.085), (-0.39, -0.064)], 0.03, bevel=0.004)
    g.profile("stock_butt", M["poly"], path((-0.39, 0.03), (-0.418, 0.03), (-0.418, -0.096), (-0.39, -0.096)), 0.04, bevel=0.006)
    grip = path((-0.108, -0.02), (-0.066, -0.02), bez((-0.066, -0.02), (-0.075, -0.07), (-0.088, -0.13), 6), (-0.122, -0.132), bez((-0.122, -0.132), (-0.12, -0.08), (-0.108, -0.02), 6))
    g.profile("grip", M["poly"], grip, 0.034, bevel=0.005)
    trigger_group(g, M["parked"], M["steel"], -0.045, -0.022)
    curved_mag(g, "mag", M["bakelite"], 0.04, -0.024, 0.21, 0.05, 0.042, 0.28, 0.028)
    return g


def _ar(g, M, furn, hg=0.3, barrel=0.15, scoped=False, mag="parked"):
    """AR pattern: flat-top upper, lower with flared magwell, free-float handguard, stock."""
    U, F = M["alu"], M[furn]
    g.profile("upper", U, path((-0.12, -0.004), (0.12, -0.004), (0.12, 0.03), (-0.12, 0.03)), 0.04, bevel=0.003)
    g.rail("toprail", U, -0.115, 0.12 + hg, 0.03)
    g.box("fwd_assist", U, (0.03, 0.014, 0.014), (-0.075, -0.022, 0.014), 0.004)
    g.box("port_cover", M["steel"], (0.06, 0.0412, 0.016), (0.0, 0, 0.013), 0.0015)
    g.profile("deflector", U, [(-0.045, 0.0), (-0.025, 0.0), (-0.03, 0.028), (-0.045, 0.028)], 0.046, bevel=0.003)
    g.box("charging", U, (0.022, 0.032, 0.01), (-0.13, 0, 0.026), 0.002)
    g.profile("lower", U, path((-0.13, -0.004), (0.1, -0.004), (0.1, -0.03), (0.092, -0.06), (0.03, -0.06), (0.024, -0.038), (-0.12, -0.034), (-0.13, -0.02)), 0.038, bevel=0.003)
    g.box("magwell_flare", U, (0.068, 0.044, 0.008), (0.062, 0, -0.058), 0.002)
    g.box("mag_release", M["steel"], (0.01, 0.042, 0.01), (0.015, 0, -0.022), 0.003)
    g.box("selector", M["steel"], (0.014, 0.042, 0.006), (-0.05, 0, -0.018), 0.002)
    trigger_group(g, U, M["steel"], -0.02, -0.035)
    pgrip(g, F, -0.06, -0.105, -0.032, 0.1, 0.03)
    curved_mag(g, "mag", M[mag], 0.033, -0.056, 0.16, 0.062, 0.058, 0.9, 0.03)
    xe = 0.12 + hg
    g.profile("handguard", F, path((0.12, 0.03), (xe, 0.03), (xe + 0.005, 0.022), (xe + 0.005, -0.024), (xe, -0.032), (0.12, -0.032)), 0.048, bevel=0.004)
    for i in range(int(hg / 0.045)):
        g.box("mlok%d" % i, M["steel"], (0.026, 0.0485, 0.007), (0.145 + i * 0.045, 0, -0.006), 0.002)
    g.lathe("barrel", M["steel"], [(xe, 0.0092), (xe + barrel, 0.0085)], axis_z=0.013, segs=20)
    flash_hider(g, M, xe + barrel, 0.013)
    ar_stock(g, M, -0.13, 0.013, F)
    if scoped:
        scope(g, M, -0.12, 0.2, 0.078, 0.039, tube=0.0127, obj=0.026, eye=0.02)
    else:
        g.profile("rsight", U, [(-0.105, 0.037), (-0.075, 0.037), (-0.08, 0.06), (-0.1, 0.06)], 0.022, bevel=0.002)
        g.profile("fsight", U, [(xe - 0.03, 0.037), (xe - 0.005, 0.037), (xe - 0.01, 0.062), (xe - 0.025, 0.062)], 0.022, bevel=0.002)
    return g


def guardian(coll, M, loc=(0, 0, 0)):
    """Guardian 556: AR-pattern carbine."""
    return _ar(Gun("guardian", coll, loc), M, "poly")


def overwatch(coll, M, loc=(0, 0, 0)):
    """Overwatch SR: tan AR-pattern rifle with a long handguard and a 4x scope."""
    return _ar(Gun("overwatch", coll, loc), M, "poly_tan", hg=0.34, barrel=0.2, scoped=True, mag="poly_tan")


def lancer(coll, M, loc=(0, 0, 0)):
    """Lancer F2: bullpup with a long carry handle and the magazine behind the grip."""
    g = Gun("lancer", coll, loc)
    body = path((-0.42, 0.035), (-0.42, -0.085), (-0.34, -0.09), (-0.21, -0.05), (-0.05, -0.04), (0.14, -0.035), (0.16, -0.02), (0.16, 0.03), (0.12, 0.04), (-0.39, 0.04))
    g.profile("body", M["poly"], body, 0.054, bevel=0.008)
    for i in range(5):
        g.box("hg_rib%d" % i, M["parked"], (0.006, 0.0545, 0.024), (0.04 + i * 0.022, 0, -0.012), 0.002)
    g.profile("handle", M["poly"], path((-0.26, 0.038), (-0.22, 0.038), (-0.2, 0.07), (0.05, 0.07), (0.07, 0.038), (0.1, 0.038), (0.1, 0.088), (0.08, 0.1), (-0.24, 0.1), (-0.26, 0.088)), 0.024, bevel=0.004)
    g.profile("rsight", M["steel"], [(-0.23, 0.1), (-0.21, 0.1), (-0.212, 0.108), (-0.228, 0.108)], 0.014, bevel=0.001)
    g.profile("fsight", M["steel"], [(0.07, 0.1), (0.085, 0.1), (0.083, 0.11), (0.072, 0.11)], 0.01, bevel=0.001)
    g.box("cocking", M["steel"], (0.016, 0.014, 0.012), (-0.06, 0, 0.068), 0.003)
    g.box("eject", M["parked"], (0.05, 0.0545, 0.016), (-0.27, 0, 0.012), 0.002)
    g.profile("cheek", M["poly_od"], path((-0.38, 0.039), (-0.28, 0.039), (-0.29, 0.054), (-0.37, 0.056)), 0.04, bevel=0.006)
    g.profile("pad", M["poly_od"], [(-0.42, 0.035), (-0.432, 0.033), (-0.432, -0.083), (-0.42, -0.085)], 0.058, bevel=0.004)
    g.lathe("barrel", M["steel"], [(0.16, 0.009), (0.38, 0.0085), (0.38, 0.0075), (0.4, 0.0075)], axis_z=0.008, segs=20)
    flash_hider(g, M, 0.4, 0.008, length=0.04)
    curved_mag(g, "mag", M["parked"], -0.19, -0.046, 0.16, 0.05, 0.046, 0.9, 0.026)
    pgrip(g, M["poly"], 0.02, -0.025, -0.036, 0.1, 0.024)
    trigger_group(g, M["poly"], M["steel"], 0.055, -0.037)
    return g


def talon(coll, M, loc=(0, 0, 0)):
    """Talon SR: smooth OD bullpup with an integrated optic and translucent mag."""
    g = Gun("talon", coll, loc)
    body = path((-0.4, 0.03), (-0.4, -0.08), bez((-0.4, -0.08), (-0.3, -0.09), (-0.22, -0.05), 5), (-0.06, -0.045), (0.12, -0.04),
                bez((0.12, -0.04), (0.17, -0.035), (0.18, 0.0), 4), (0.18, 0.025), bez((0.18, 0.025), (0.1, 0.04), (-0.05, 0.04), 4), (-0.38, 0.04))
    g.profile("body", M["poly_od"], body, 0.056, bevel=0.01)
    g.profile("optic_mount", M["poly_od"], path((-0.18, 0.038), (0.06, 0.038), (0.04, 0.058), (-0.16, 0.058)), 0.03, bevel=0.005)
    scope(g, M, -0.19, 0.1, 0.074, 0.058, tube=0.014, obj=0.021, eye=0.019, mat=M["poly_od"], rings=())
    g.lathe("barrel", M["steel"], [(0.18, 0.009), (0.36, 0.0085), (0.36, 0.0075), (0.38, 0.0075)], axis_z=0.006, segs=20)
    flash_hider(g, M, 0.38, 0.006, length=0.04)
    curved_mag(g, "mag", M["smoke"], -0.17, -0.048, 0.16, 0.05, 0.046, 0.9, 0.026)
    pgrip(g, M["poly_od"], 0.0, -0.045, -0.042, 0.1, 0.022)
    trigger_group(g, M["poly_od"], M["steel"], 0.04, -0.042, 1.2)
    g.profile("foregrip", M["poly"], path((0.1, -0.038), (0.17, -0.04), (0.17, -0.058), (0.1, -0.056)), 0.032, bevel=0.005)
    g.box("cocking", M["steel"], (0.012, 0.064, 0.012), (0.1, 0, 0.018), 0.004)
    g.profile("pad", M["poly"], [(-0.4, 0.03), (-0.412, 0.028), (-0.412, -0.078), (-0.4, -0.08)], 0.058, bevel=0.004)
    return g


def _bolt(g, M, x, z, knob=0.0095):
    """Bolt handle sticking out of the left (-Y) side with a ball knob."""
    g.lathe("bolt_arm", M["steel"], [(-0.012, 0.004), (-0.05, 0.004)], axis_z=x, y=z, segs=10, axis="Y")
    k = knob
    g.lathe("bolt_knob", M["steel"], [(-0.044, 0.003), (-0.048, k * 0.8), (-0.056, k), (-0.064, k * 0.8), (-0.068, 0.002)], axis_z=x - 0.004, y=z - 0.004, segs=16, axis="Y")


def pathfinder(coll, M, loc=(0, 0, 0)):
    """Pathfinder: light bolt-action with an OD sporter stock and a fluted barrel."""
    g = Gun("pathfinder", coll, loc)
    st = path((0.36, -0.006), (0.36, -0.028), (0.34, -0.036), (0.06, -0.04), (0.03, -0.044), (-0.055, -0.044),
              bez((-0.055, -0.044), (-0.065, -0.08), (-0.078, -0.12), 5), (-0.115, -0.122), bez((-0.115, -0.122), (-0.12, -0.08), (-0.14, -0.06), 4),
              bez((-0.14, -0.06), (-0.3, -0.075), (-0.46, -0.115), 6), (-0.46, 0.014), bez((-0.46, 0.014), (-0.3, 0.024), (-0.16, 0.006), 5), (-0.11, -0.004))
    g.profile("stock", M["poly_od"], st, 0.044, bevel=0.01)
    g.profile("pad", M["poly"], [(-0.46, 0.014), (-0.476, 0.012), (-0.476, -0.116), (-0.46, -0.115)], 0.048, bevel=0.004)
    g.lathe("receiver", M["steel"], [(-0.12, 0.014), (-0.118, 0.016), (0.1, 0.016), (0.104, 0.014)], axis_z=0.012, segs=28)
    g.lathe("shroud", M["steel"], [(-0.15, 0.008), (-0.145, 0.011), (-0.12, 0.011)], axis_z=0.012, segs=20)
    _bolt(g, M, -0.085, 0.012)
    g.lathe("barrel", M["steel"], [(0.1, 0.012), (0.16, 0.011), (0.6, 0.0085), (0.6, 0.0065)], axis_z=0.012, segs=24)
    for i in range(4):
        g.box("flute%d" % i, M["parked"], (0.26, 0.0205, 0.0025), (0.32, 0, 0.012 + (i - 1.5) * 0.0045), 0.0005)
    g.lathe("thread_cap", M["steel"], [(0.6, 0.01), (0.615, 0.01), (0.615, 0.008)], axis_z=0.012, segs=16)
    scope(g, M, -0.13, 0.17, 0.062, 0.027, tube=0.0127, obj=0.022, eye=0.019)
    trigger_group(g, M["parked"], M["steel"], -0.02, -0.042)
    g.box("mag", M["parked"], (0.05, 0.032, 0.02), (0.055, 0, -0.048), 0.002)
    return g


def longbow(coll, M, loc=(0, 0, 0)):
    """Longbow .338: heavy chassis sniper, big scope and brake, folded bipod, adjustable stock."""
    g = Gun("longbow", coll, loc)
    g.lathe("receiver", M["steel"], [(-0.16, 0.018), (-0.158, 0.02), (0.12, 0.02), (0.124, 0.018)], axis_z=0.02, segs=32)
    g.rail("rail", M["alu"], -0.16, 0.12, 0.038)
    g.lathe("shroud", M["steel"], [(-0.195, 0.01), (-0.19, 0.013), (-0.16, 0.013)], axis_z=0.02, segs=20)
    _bolt(g, M, -0.12, 0.018, knob=0.012)
    g.profile("chassis", M["alu"], path((-0.17, 0.006), (0.12, 0.006), (0.12, -0.05), (0.004, -0.05), (-0.04, -0.048), (-0.17, -0.044)), 0.05, bevel=0.003)
    g.profile("forend", M["alu"], path((0.12, 0.006), (0.5, 0.006), (0.51, -0.004), (0.51, -0.04), (0.5, -0.05), (0.12, -0.05)), 0.06, bevel=0.004)
    for i in range(7):
        g.box("forend_slot%d" % i, M["poly"], (0.032, 0.0605, 0.01), (0.16 + i * 0.048, 0, -0.022), 0.002)
    g.profile("mag", M["parked"], [(0.004, -0.048), (0.084, -0.048), (0.082, -0.115), (0.006, -0.115)], 0.04, bevel=0.002)
    g.profile("mag_base", M["poly"], [(0.0, -0.112), (0.088, -0.112), (0.088, -0.122), (0.0, -0.122)], 0.044, bevel=0.002)
    pgrip(g, M["poly"], -0.07, -0.115, -0.044, 0.105, 0.03)
    trigger_group(g, M["alu"], M["steel"], -0.04, -0.048)
    g.box("hinge", M["alu"], (0.016, 0.056, 0.05), (-0.178, 0, -0.016), 0.003)
    g.profile("stock_top", M["alu"], path((-0.18, 0.004), (-0.5, 0.004), (-0.5, -0.016), (-0.18, -0.016)), 0.034, bevel=0.003)
    g.profile("stock_low", M["alu"], [(-0.18, -0.03), (-0.18, -0.044), (-0.48, -0.12), (-0.48, -0.104)], 0.03, bevel=0.003)
    g.profile("cheek", M["poly_od"], path((-0.27, 0.012), (-0.45, 0.012), (-0.45, 0.04), bez((-0.45, 0.04), (-0.36, 0.046), (-0.28, 0.04), 4)), 0.04, bevel=0.007)
    for i, x in enumerate((-0.3, -0.42)):
        g.lathe("cheek_post%d" % i, M["steel"], [(0.0, 0.004), (0.013, 0.004)], axis_z=x, y=0.0, segs=10, axis="Z")
    g.profile("butt", M["poly"], path((-0.5, 0.022), (-0.528, 0.022), (-0.528, -0.135), (-0.5, -0.135)), 0.05, bevel=0.006)
    g.lathe("monopod", M["steel"], [(-0.12, 0.006), (-0.03, 0.006)], axis_z=-0.43, y=0.0, segs=12, axis="Z")
    g.lathe("monopod_foot", M["poly"], [(-0.13, 0.011), (-0.118, 0.011)], axis_z=-0.43, y=0.0, segs=16, axis="Z")
    g.lathe("barrel", M["steel"], [(0.12, 0.0165), (0.75, 0.014)], axis_z=0.02, segs=28)
    g.lathe("brake", M["steel"], [(0.75, 0.02), (0.84, 0.02), (0.84, 0.016)], axis_z=0.02, segs=28)
    for i in range(3):
        g.box("brake_port%d" % i, M["poly"], (0.012, 0.0405, 0.026), (0.768 + i * 0.024, 0, 0.02), 0.002)
    scope(g, M, -0.2, 0.21, 0.088, 0.047, tube=0.017, obj=0.03, eye=0.022)
    g.profile("bipod_hinge", M["alu"], path((0.46, -0.05), (0.5, -0.05), (0.5, -0.064), (0.46, -0.064)), 0.05, bevel=0.002)
    for s in (-1, 1):
        g.lathe("bipod%d" % s, M["alu"], [(0.3, 0.006), (0.48, 0.006)], axis_z=-0.058, y=s * 0.016, segs=12)
        g.lathe("bipod_foot%d" % s, M["poly"], [(0.285, 0.0095), (0.305, 0.0095)], axis_z=-0.058, y=s * 0.016, segs=12)
    return g


# --- The bomb -----------------------------------------------------------------------

def c4(coll, M, loc=(0, 0, 0)):
    """Planted bomb, lying flat (Z up): six taped charges, a keypad/timer unit,
    detonators and wires. Origin on the ground at its centre."""
    g = Gun("c4", coll, loc)
    bw, bd, bh = 0.11, 0.05, 0.034
    for i in range(3):
        for j in range(2):
            g.box("block%d%d" % (i, j), M["clay"], (bd - 0.002, bw - 0.002, bh), ((i - 1) * bd, (j - 0.5) * bw, bh / 2), 0.004)
    for j, y in enumerate((-0.085, -0.025, 0.025, 0.085)):
        g.box("tape%d" % j, M["tape"], (bd * 3 + 0.004, 0.018, bh + 0.003), (0, y, bh / 2), 0.002)
    # Control unit on top.
    g.box("unit", M["poly"], (0.11, 0.09, 0.022), (0.0, -0.018, bh + 0.011), 0.003)
    g.box("unit_pcb", M["pcb"], (0.1, 0.03, 0.004), (0.0, 0.042, bh + 0.002), 0.001)
    g.box("lcd_bezel", M["steel"], (0.07, 0.024, 0.003), (0.0, -0.042, bh + 0.0225), 0.001)
    g.box("lcd", M["lcd"], (0.062, 0.018, 0.001), (0.0, -0.042, bh + 0.0242), 0.0)
    for r in range(4):
        for c in range(3):
            g.box("key%d%d" % (r, c), M["key"], (0.012, 0.009, 0.004), ((c - 1) * 0.018, -0.02 + r * 0.013, bh + 0.0235), 0.0012)
    g.lathe("led", M["led"], [(bh + 0.021, 0.004), (bh + 0.025, 0.004), (bh + 0.027, 0.0025), (bh + 0.028, 0.0)], axis_z=0.042, y=-0.06, segs=12, axis="Z")
    g.lathe("antenna", M["steel"], [(bh + 0.02, 0.0018), (bh + 0.065, 0.0012)], axis_z=-0.045, y=0.022, segs=8, axis="Z")
    g.lathe("antenna_tip", M["poly"], [(bh + 0.063, 0.003), (bh + 0.07, 0.003)], axis_z=-0.045, y=0.022, segs=8, axis="Z")
    # Detonators pushed into the end blocks, wired back to the unit.
    dets = [(-0.065, 0.075), (0.065, 0.075), (-0.065, -0.085), (0.065, -0.085)]
    cols = [M["wire_r"], M["wire_b"], M["wire_y"], M["wire_r"]]
    for k, ((dx, dy), wm) in enumerate(zip(dets, cols)):
        g.lathe("det%d" % k, M["bright"], [(bh - 0.01, 0.004), (bh + 0.012, 0.004), (bh + 0.012, 0.0025)], axis_z=dx, y=dy, segs=12, axis="Z")
        tx, ty = (0.03 if dx > 0 else -0.03), (0.045 if dy > 0 else -0.06)
        wire(g, "wire%d" % k, wm, [(dx, dy, bh + 0.012), (dx, dy, bh + 0.022), ((dx + tx) / 2, (dy + ty) / 2, bh + 0.03), (tx, ty, bh + 0.018)])
    wire(g, "wire_loop", M["wire_b"], [(0.05, 0.03, bh + 0.004), (0.07, 0.0, bh + 0.008), (0.06, -0.04, bh + 0.012), (0.05, -0.05, bh + 0.016)], radius=0.0014)
    return g



# --- Grenades -----------------------------------------------------------------------
# Upright (Z up, origin at the centre of the body); `sprites` renders them like guns.

def _spoon_pin(g, M, top, r, side=-1):
    """Fuze head with a spoon down one side and a pull ring."""
    g.lathe("fuze", M["steel"], [(top, r * 0.55), (top + 0.012, r * 0.55), (top + 0.016, r * 0.42), (top + 0.022, r * 0.42), (top + 0.024, r * 0.2)], axis_z=0.0, y=0.0, segs=20, axis="Z")
    g.profile("spoon", M["bright"], path((r * 0.2, top + 0.02), (r * 0.6, top + 0.02), (r * 1.05, top - 0.01), (r * 1.08, top - 0.07), (r * 0.98, top - 0.07), (r * 0.94, top - 0.012), (r * 0.5, top + 0.012), (r * 0.2, top + 0.012)), 0.012, y=0.0, bevel=0.001)
    ring = [(-0.026 + 0.012 * math.cos(math.radians(a)), side * 0.012, top + 0.012 + 0.012 * math.sin(math.radians(a))) for a in range(0, 361, 30)]
    wire(g, "pin_ring", M["bright"], ring, radius=0.0014)
    wire(g, "pin", M["bright"], [(-0.014, side * 0.012, top + 0.012), (0.0, side * 0.006, top + 0.012), (0.012, 0.0, top + 0.012)], radius=0.0011)


def frag(coll, M, loc=(0, 0, 0)):
    """Frag grenade: ribbed olive egg body, fuze, spoon and pin."""
    g = Gun("frag", coll, loc)
    r = 0.029
    rings = [(-0.045, 0.004)] + [(-0.042 + 0.084 * i / 12, r * math.sin(math.pi * (0.06 + 0.88 * i / 12)) ** 0.7) for i in range(13)] + [(0.045, 0.01)]
    g.lathe("body", M["poly_od"], rings, axis_z=0.0, y=0.0, segs=28, axis="Z")
    for i, z in enumerate((-0.022, -0.007, 0.008, 0.023)):  # Fragmentation grooves.
        rr = r * math.sin(math.pi * (0.5 + z / 0.09)) ** 0.7 + 0.0008
        g.lathe("groove%d" % i, M["poly"], [(z - 0.0012, rr), (z + 0.0012, rr)], axis_z=0.0, y=0.0, segs=28, axis="Z")
    for i in range(8):  # Vertical grooves follow the egg's curve.
        a = i * math.pi / 4
        pts = []
        for j in range(11):
            z = -0.036 + 0.072 * j / 10
            rr = r * math.sin(math.pi * (0.5 + z / 0.09)) ** 0.7 + 0.0002
            pts.append((math.cos(a) * rr, math.sin(a) * rr, z))
        wire(g, "vgroove%d" % i, M["poly"], pts, radius=0.0012)
    _spoon_pin(g, M, 0.043, 0.02)
    return g


def flashbang(coll, M, loc=(0, 0, 0)):
    """Flashbang: steel cylinder with rows of vent holes and a white band."""
    g = Gun("flash", coll, loc)
    r, h = 0.021, 0.11
    g.lathe("body", M["steel"], [(-h / 2, r * 0.9), (-h / 2 + 0.004, r), (h / 2 - 0.004, r), (h / 2, r * 0.9)], axis_z=0.0, y=0.0, segs=28, axis="Z")
    g.lathe("band", M["key"], [(-0.012, r + 0.0006), (0.012, r + 0.0006)], axis_z=0.0, y=0.0, segs=28, axis="Z")
    for row, z in enumerate((-0.035, 0.03)):
        for i in range(8):
            a = i * math.pi / 4 + row * 0.39
            ob = g.lathe("vent%d_%d" % (row, i), M["poly"], [(r - 0.002, 0.0035), (r + 0.0008, 0.0035)], segs=10)
            ob.data.transform(Matrix.Translation((0, 0, z)) @ Matrix.Rotation(a, 4, "Z"))
    _spoon_pin(g, M, h / 2, 0.018)
    return g


def smoke(coll, M, loc=(0, 0, 0)):
    """Smoke grenade: tall grey-green canister, emission holes on top, label band."""
    g = Gun("smoke", coll, loc)
    r, h = 0.026, 0.12
    g.lathe("body", M["poly_od"], [(-h / 2, r * 0.92), (-h / 2 + 0.004, r), (h / 2 - 0.006, r), (h / 2, r * 0.85)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    g.lathe("band", M["key"], [(0.01, r + 0.0006), (0.03, r + 0.0006)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    g.lathe("band2", M["poly"], [(-0.035, r + 0.0006), (-0.028, r + 0.0006)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    for i in range(4):
        a = i * math.pi / 2 + 0.4
        g.lathe("hole%d" % i, M["poly"], [(h / 2 - 0.001, 0.004), (h / 2 + 0.0005, 0.004)], axis_z=math.cos(a) * 0.016, y=math.sin(a) * 0.016, segs=10, axis="Z")
    _spoon_pin(g, M, h / 2, 0.016)
    return g


def incendiary(coll, M, loc=(0, 0, 0)):
    """Incendiary (CT): squat red-banded canister."""
    g = Gun("incendiary", coll, loc)
    r, h = 0.027, 0.1
    g.lathe("body", M["parked"], [(-h / 2, r * 0.9), (-h / 2 + 0.005, r), (h / 2 - 0.005, r), (h / 2, r * 0.88)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    for i, z in enumerate((-0.02, 0.02)):
        g.lathe("band%d" % i, M["wire_r"], [(z - 0.005, r + 0.0006), (z + 0.005, r + 0.0006)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    _spoon_pin(g, M, h / 2, 0.017)
    return g


def molotov(coll, M, loc=(0, 0, 0)):
    """Molotov: brown glass bottle half full, a rag stuffed in the neck."""
    g = Gun("molotov", coll, loc)
    rings = [(-0.1, 0.03), (-0.098, 0.032), (0.02, 0.032), (0.045, 0.024), (0.06, 0.013), (0.1, 0.012), (0.105, 0.0135), (0.11, 0.012)]
    g.lathe("bottle", M["smoke"], rings, axis_z=0.0, y=0.0, segs=32, axis="Z")
    g.lathe("fuel", M["wire_y"], [(-0.097, 0.029), (-0.02, 0.029)], axis_z=0.0, y=0.0, segs=28, axis="Z")
    g.lathe("label", M["clay"], [(-0.06, 0.0325), (-0.02, 0.0325)], axis_z=0.0, y=0.0, segs=32, axis="Z")
    # Crumpled rag: a few twisted strips stuffed in the neck, flopping over.
    for i, (dx, dy, tip) in enumerate(((0.0, 0.0, (0.04, 0.004, 0.13)), (0.003, -0.004, (0.028, -0.014, 0.148)), (-0.003, 0.004, (0.012, 0.016, 0.152)))):
        rag = [(dx, dy, 0.092), (dx * 2, dy * 2, 0.115), ((dx + tip[0]) / 2, (dy + tip[1]) / 2, 0.142 + i * 0.004), tip]
        wire(g, "rag%d" % i, M["clay"], rag, radius=0.0075 - i * 0.0012)
    g.lathe("rag_knot", M["clay"], [(0.1, 0.0145), (0.112, 0.0155), (0.118, 0.012)], axis_z=0.0, y=0.0, segs=12, axis="Z")
    return g


# --- Melee --------------------------------------------------------------------------

def knife(coll, M, loc=(0, 0, 0)):
    """Combat knife: clip-point blade (satin flat grind, dark-coated flats with a
    sharpened swedge), small guard, pebbled finger-groove grip, pommel with a
    lanyard hole. Origin at the guard, tip along +X."""
    g = Gun("knife", coll, loc)
    tip = (0.182, 0.001)
    spine = [(0.003 + 0.109 * i / 8, 0.0105 + 0.001 * i / 8) for i in range(9)]
    clip = bez(spine[-1], (0.152, 0.0105), tip, 8)
    edge = path(bez(tip, (0.17, -0.0175), (0.12, -0.0175), 8), [(0.12 - 0.102 * i / 7, -0.0175 + 0.001 * i / 7) for i in range(1, 8)],
                (0.0155, -0.0135), (0.003, -0.0135))
    blade = path(spine, clip, edge)
    ob = g.profile("blade", M["satin"], blade, 0.0064, bevel=0.0006)
    # Taper the slab into a full flat grind: thin along the edge and the clip.
    cut = list(reversed(edge[:16])) + [tip] + list(reversed(clip))
    def dist(x, z):
        d = 1.0
        for (ax, az), (bx, bz) in zip(cut, cut[1:]):
            vx, vz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * vx + (z - az) * vz) / (vx * vx + vz * vz + 1e-12)))
            d = min(d, math.hypot(x - ax - t * vx, z - az - t * vz))
        return d
    for v in ob.data.vertices:
        f = max(0.12, min(1.0, dist(v.co.x, v.co.z) / 0.016))
        v.co.y *= f
    # Coated flats above the grind line, stopping short of the swedge.
    gl = -0.0085
    flat = path((0.003, 0.0108), (0.112, 0.0118), bez((0.112, 0.0118), (0.142, 0.0085), (0.16, 0.0005), 6),
                bez((0.16, 0.0005), (0.15, gl), (0.12, gl), 6), (0.034, gl), bez((0.034, gl), (0.02, gl), (0.0155, -0.0125), 4),
                (0.003, -0.0125))
    g.profile("blade_flat", M["coat"], flat, 0.0068, bevel=0.0009)
    # Guard: short upper quillon, longer lower one swept forward.
    guard = path((0.003, 0.016), arc(-0.0005, 0.018, 0.004, 30, 170, 4), (-0.0055, 0.012), (-0.0055, -0.016),
                 bez((-0.0055, -0.016), (-0.004, -0.027), (0.004, -0.031), 4), (0.009, -0.029), (0.0045, -0.024), (0.004, -0.016))
    g.profile("guard", M["steel"], guard, 0.02, bevel=0.0016)
    # Grip with four finger grooves along the bottom and a gentle palm swell on top.
    x0, x1 = -0.0055, -0.112
    top = path((x0, 0.0125), bez((x0, 0.0125), ((x0 + x1) / 2, 0.0185), (x1, 0.0135), 8))
    gx = [x0 - 0.008 - i * 0.022 for i in range(5)]
    fwd = [(x0, -0.0145), (gx[0], -0.016)]
    for a, b in zip(gx, gx[1:]):
        fwd += bez((a, -0.016), ((a + b) / 2, -0.0075), (b, -0.016), 6)
    fwd.append((x1, -0.0155))
    grip = path(top, list(reversed(fwd)))
    g.profile("grip", M["rubber"], grip, 0.0255, bevel=0.0045)
    for i in range(7):  # Raised traction bands across the palm side.
        x = -0.022 - i * 0.012
        zt = 0.0125 + 0.006 * (1 - ((x - (x0 + x1) / 2) / ((x0 - x1) / 2)) ** 2) - 0.004
        g.box("grip_rib%d" % i, M["rubber_od"], (0.004, 0.0265, 0.016), (x, 0, zt - 0.006), 0.0012)
    g.profile("grip_ferrule", M["steel"], [(x0 + 0.001, 0.0135), (x0 - 0.004, 0.0135), (x0 - 0.004, -0.0155), (x0 + 0.001, -0.0155)], 0.0265, bevel=0.0012)
    # Pommel with a lanyard hole (boolean through Y).
    px0, px1 = x1 + 0.001, x1 - 0.019
    pom = path((px0, 0.0135), (px1 + 0.005, 0.0125), arc(px1 + 0.006, 0.0, 0.0125, 90, 270, 8), (px1 + 0.005, -0.0125), (px0, -0.0155))
    pob = g.profile("pommel", M["steel"], pom, 0.022, bevel=0.0015)
    cut_ob = g.lathe("lanyard_cut", M["steel"], [(-0.012, 0.0042), (0.012, 0.0042)], axis_z=px1 + 0.008, y=0.0, segs=20, axis="Y")
    cut_ob.hide_render = True
    cut_ob.hide_viewport = True
    cut_ob.display_type = "WIRE"
    bo = pob.modifiers.new("Lanyard", "BOOLEAN")
    bo.object = cut_ob
    bo.operation = "DIFFERENCE"
    pob.modifiers.move(len(pob.modifiers) - 1, 0)
    return g


GRENADES = {"frag": frag, "flash": flashbang, "smoke": smoke, "incendiary": incendiary, "molotov": molotov}

GUNS = {"pk9": pk9, "sentry": sentry, "duster": duster, "viper": viper, "falcon": falcon, "magnum": magnum,
        "hornet": hornet, "kestrel": kestrel, "bulldog": bulldog, "swarm": swarm,
        "breacher": breacher, "tempest": tempest, "hammer": hammer,
        "kodiak": kodiak, "lancer": lancer, "raptor": raptor, "guardian": guardian, "talon": talon, "overwatch": overwatch,
        "pathfinder": pathfinder, "longbow": longbow, "c4": c4, "knife": knife}
GUNS.update({"g_" + k: f for k, f in GRENADES.items()})


def _frame(cam, root, dirv, fill=1.08):
    """Points `cam` at the model under `root` from direction `dirv`, sized to fit."""
    bpy.context.view_layer.update()
    pts = []
    for ob in root.children_recursive:
        if ob.type in ("MESH", "CURVE"):
            pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2
    dv = Vector(dirv).normalized()
    rot = (-dv).to_track_quat("-Z", "Y")
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    rh = max(abs((p - c).dot(right)) for p in pts)
    rv = max(abs((p - c).dot(up)) for p in pts)
    sc = bpy.context.scene
    aspect = sc.render.resolution_x / sc.render.resolution_y
    th = math.tan(cam.data.angle / 2)
    d = max(rh / th, rv / (th / aspect)) * fill + max(rh, rv) * 0.3
    cam.location = c + dv * d
    cam.rotation_euler = rot.to_euler()


VIEWS = {"side": (0.0, -1.0, 0.0), "34": (0.5, -0.85, 0.3), "top": (0.0, -0.25, 1.0)}


def showcase(keys, out_dir, views=("side", "34"), res=(1600, 800), samples=96):
    """Builds the guns in scene LD_guns and renders a side and a 3/4 shot of each."""
    if bpy.context.window is not None:
        sc = bpy.data.scenes.get("LD_guns") or bpy.data.scenes.new("LD_guns")
        bpy.context.window.scene = sc
    else:  # Headless (blender -b): render with the current scene.
        sc = bpy.context.scene
    for ob in list(sc.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    M = materials()
    coll = sc.collection
    sc.render.engine = "CYCLES"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = sc.world or bpy.data.worlds.new("GK_World")
    sc.world = world
    world.use_nodes = True
    wt = world.node_tree
    wt.nodes.clear()
    wo = wt.nodes.new("ShaderNodeOutputWorld")
    tc = wt.nodes.new("ShaderNodeTexCoord")
    sep = wt.nodes.new("ShaderNodeSeparateXYZ")
    wt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = wt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.4
    ramp.color_ramp.elements[0].color = (0.01, 0.01, 0.012, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.9, 0.92, 1.0, 1)
    wt.links.new(sep.outputs["Z"], ramp.inputs[0])
    refl = wt.nodes.new("ShaderNodeBackground")
    refl.inputs[1].default_value = 1.2
    wt.links.new(ramp.outputs[0], refl.inputs[0])
    flat = wt.nodes.new("ShaderNodeBackground")
    flat.inputs[0].default_value = (0.06, 0.065, 0.075, 1)
    lp = wt.nodes.new("ShaderNodeLightPath")
    mix = wt.nodes.new("ShaderNodeMixShader")
    wt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    wt.links.new(refl.outputs[0], mix.inputs[1])
    wt.links.new(flat.outputs[0], mix.inputs[2])
    wt.links.new(mix.outputs[0], wo.inputs[0])
    for nm, loc, e, size in (("Key", (0.6, -1.2, 1.2), 70, 1.2), ("Rim", (-1.2, 1.0, 0.8), 70, 1.0), ("Fill", (0.0, -1.5, -0.3), 12, 1.5)):
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = e
        ld.size = size
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        coll.objects.link(lo)
    cam_d = bpy.data.cameras.new("GunCam")
    cam_d.lens = 85
    cam = bpy.data.objects.new("GunCam", cam_d)
    coll.objects.link(cam)
    sc.camera = cam
    outs = []
    for k in keys:
        for ob in list(coll.objects):
            if ob.type in ("MESH", "EMPTY", "CURVE"):
                bpy.data.objects.remove(ob, do_unlink=True)
        g = GUNS[k](coll, M)
        for nm in (("top", "34") if k == "c4" else views):
            _frame(cam, g.root, VIEWS[nm])
            sc.render.filepath = "%s/gun_%s_%s.png" % (out_dir, k, nm)
            bpy.ops.render.render(write_still=True)
            outs.append(sc.render.filepath)
    return outs


# --- Game sprites ---------------------------------------------------------------------

def grip_point(g):
    """Where a right hand closes on the gun (model coords): the upper middle of
    its pistol grip, or just behind the trigger for guns without one."""
    bpy.context.view_layer.update()
    for ob in g.root.children:
        if ob.name.split(".")[0] == g.name + "_grip":
            pts = [g.root.matrix_world.inverted() @ (ob.matrix_world @ Vector(c)) for c in ob.bound_box]
            x = sum(p.x for p in pts) / len(pts)
            top = max(p.z for p in pts)
            return Vector((x + 0.006, 0.0, top - 0.032))
    return Vector((-0.04, 0.0, -0.045))


def _bbox(root):
    bpy.context.view_layer.update()
    pts = []
    for ob in root.children_recursive:
        if ob.type in ("MESH", "CURVE"):
            pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def _silhouette(src, dst):
    """White copy of a transparent render, keeping its alpha (kill feed / buy icons)."""
    import numpy as np
    img = bpy.data.images.load(src, check_existing=False)
    px = np.empty(len(img.pixels), dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    px[:, :3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = dst
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def sprites(keys, out_dir, ppm=400, samples=64):
    """Transparent orthographic renders for the game, at `ppm` pixels per metre:
    <key>_side.png (lying on its side: floor drops and icons), <key>_icon.png
    (its white silhouette) and <key>_top.png
    (seen from above, muzzle to +x: held guns). Writes guns.json with each image's
    size, the pixel of the model origin (the grip/trigger, ax/ay) and the length."""
    import json, os
    os.makedirs(out_dir, exist_ok=True)
    showcase([], out_dir, samples=samples)
    sc = bpy.context.scene
    coll = sc.collection
    cam = sc.camera
    cam.data.type = "ORTHO"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sun_d = bpy.data.lights.new("SpriteSun", "SUN")
    sun_d.energy = 2.5
    sun_d.angle = math.radians(8)
    sun = bpy.data.objects.new("SpriteSun", sun_d)
    sun.rotation_euler = (math.radians(30), math.radians(-20), 0)
    coll.objects.link(sun)
    M = materials()
    path_json = os.path.join(out_dir, "guns.json")
    meta = json.load(open(path_json)) if os.path.exists(path_json) else {}
    pad = 0.008
    for k in keys:
        for ob in list(coll.objects):
            if ob.type in ("MESH", "EMPTY", "CURVE"):
                bpy.data.objects.remove(ob, do_unlink=True)
        g = GUNS[k](coll, M)
        lo, hi = _bbox(g.root)
        info = {"len_m": round(hi.x - lo.x, 4)}
        gp = grip_point(g)
        for view in ("side", "top"):
            if view == "side":
                w, h = hi.x - lo.x + 2 * pad, hi.z - lo.z + 2 * pad
                cx, cy = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
                cam.location = (cx, -2.0, cy)
                cam.rotation_euler = (math.radians(90), 0, 0)
            else:
                w, h = hi.x - lo.x + 2 * pad, hi.y - lo.y + 2 * pad
                cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
                cam.location = (cx, cy, 2.0)
                cam.rotation_euler = (0, 0, 0)
            rx, ry = max(4, round(w * ppm)), max(4, round(h * ppm))
            sc.render.resolution_x, sc.render.resolution_y = rx, ry
            sc.render.resolution_percentage = 100
            cam.data.ortho_scale = max(rx, ry) / ppm
            sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (k, view))
            bpy.ops.render.render(write_still=True)
            info[view] = {"w": rx, "h": ry, "ax": round((0 - (cx - w / 2)) * ppm, 1), "ay": round(((cy + h / 2) - 0) * ppm, 1)}
            info[view]["gx"] = round((gp.x - (cx - w / 2)) * ppm, 1)  # Grip (right hand) x in this image.
            if view == "side":
                _silhouette(sc.render.filepath, os.path.join(out_dir, "%s_icon.png" % k))
        meta[k] = info
    json.dump(meta, open(path_json, "w"), indent=1, sort_keys=True)
    bpy.data.objects.remove(sun, do_unlink=True)
    sc.render.film_transparent = False
    cam.data.type = "PERSP"
    return meta
