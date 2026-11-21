"""Procedural volumetric explosion (fireball -> rolling smoke). -- <name> <px> <nframes> [smokeonly] [f0 f1]"""
import bpy, math, os, sys, random
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfxlib import *

A = args()
name, px, NFR = A[0], int(A[1]), int(A[2])
smokeonly = len(A) > 3 and A[3] == "smokeonly"
F0 = int(A[4]) if len(A) > 5 else 0
F1 = int(A[5]) if len(A) > 5 else NFR - 1
D = SCRATCH + "/" + name
os.makedirs(D, exist_ok=True)
scene = clear_scene()
setup_gpu(scene, samples=96)
scene.cycles.volume_bounces = 2
scene.cycles.max_bounces = 6
scene.cycles.volume_step_rate = 0.5
scene.render.resolution_x = scene.render.resolution_y = px
world(scene, 0.25, (0.85, 0.9, 1.0))
s = sun(scene, energy=6.5, angle=6)
s.rotation_euler = Vector((1.0, -1.0, -0.9)).normalized().to_track_quat('-Z', 'Y').to_euler()
top_camera(scene, 4.4)
bpy.ops.mesh.primitive_cube_add(size=4.4, location=(0, 0, 0))
cube = bpy.context.object

rnd = random.Random(42)
NB = 22
blobs = [((0, 0, 0.1), 0.0, 1.0)]
for i in range(NB - 1):
    a = (i + rnd.uniform(-0.4, 0.4)) / (NB - 1) * 6.283
    el = rnd.uniform(-0.05, 0.6)
    d = Vector((math.cos(a), math.sin(a), el)).normalized()
    blobs.append((tuple(d), rnd.uniform(0.5, 1.0), rnd.uniform(0.4, 0.7)))

mat = bpy.data.materials.new("Exp")
mat.use_nodes = True
nt = mat.node_tree
N, L = nt.nodes, nt.links
for n in list(N):
    N.remove(n)
out = N.new("ShaderNodeOutputMaterial")
pv = N.new("ShaderNodeVolumePrincipled")
L.new(pv.outputs[0], out.inputs["Volume"])
pv.inputs["Anisotropy"].default_value = 0.1
tc = N.new("ShaderNodeTexCoord")


def noise(vec, scale, detail, rough=0.5, w=0.0):
    n = N.new("ShaderNodeTexNoise")
    n.noise_dimensions = '4D'
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    n.inputs["W"].default_value = w
    L.new(vec, n.inputs["Vector"])
    return n


def vmath(op, a, b=None, val=None):
    m = N.new("ShaderNodeVectorMath"); m.operation = op
    L.new(a, m.inputs[0])
    if b is not None:
        L.new(b, m.inputs[1])
    if val is not None:
        if op == 'SCALE':
            m.inputs["Scale"].default_value = val
        else:
            m.inputs[1].default_value = val
    return m


def math_(op, a, b=None, val=None):
    m = N.new("ShaderNodeMath"); m.operation = op
    if isinstance(a, float):
        m.inputs[0].default_value = a
    else:
        L.new(a, m.inputs[0])
    if b is not None:
        L.new(b, m.inputs[1])
    if val is not None:
        m.inputs[1].default_value = val
    return m


P = tc.outputs["Object"]
wn = noise(P, 1.3, 3)
warp = vmath('SCALE', vmath('SUBTRACT', wn.outputs["Color"], val=(0.5, 0.5, 0.5)).outputs[0], val=0.5)
pw = vmath('ADD', P, warp.outputs[0]).outputs[0]
ctrl = {"wn": wn, "warp": warp, "blobs": []}
acc = None
for (d, rad, r) in blobs:
    dist = vmath('DISTANCE', pw)
    mr = N.new("ShaderNodeMapRange"); mr.interpolation_type = 'SMOOTHERSTEP'
    L.new(dist.outputs["Value"], mr.inputs["Value"])
    ctrl["blobs"].append((dist, mr, d, rad, r))
    acc = mr.outputs[0] if acc is None else math_('ADD', acc, mr.outputs[0]).outputs[0]
dn = noise(P, 4.0, 6, 0.55)
ctrl["dn"] = dn
dm = N.new("ShaderNodeMapRange")
dm.inputs["From Min"].default_value = 0.3; dm.inputs["From Max"].default_value = 0.7
dm.inputs["To Min"].default_value = 0.2; dm.inputs["To Max"].default_value = 1.5
L.new(dn.outputs["Fac"], dm.inputs["Value"])
shape = math_('MULTIPLY', acc, dm.outputs[0])
dens = N.new("ShaderNodeMapRange"); dens.interpolation_type = 'SMOOTHSTEP'
L.new(shape.outputs[0], dens.inputs["Value"])
dens.inputs["From Max"].default_value = 1.5
L.new(dens.outputs[0], pv.inputs["Density"])
ctrl["dens"] = dens
# fire: hot pockets where shape is high, modulated by a separate noise
fn = noise(pw, 2.6, 4, 0.6)
ctrl["fn"] = fn
hot = math_('MULTIPLY', shape.outputs[0], fn.outputs["Fac"])
hm = N.new("ShaderNodeMapRange"); hm.interpolation_type = 'SMOOTHSTEP'
L.new(hot.outputs[0], hm.inputs["Value"])
ctrl["hm"] = hm
ramp = N.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position = 0.0; cr.elements[0].color = (0.25, 0.02, 0.0, 1)
cr.elements[1].position = 1.0; cr.elements[1].color = (1.0, 0.8, 0.45, 1)
for p, c in ((0.25, (0.8, 0.08, 0.0, 1)), (0.55, (1.0, 0.28, 0.02, 1)), (0.82, (1.0, 0.55, 0.12, 1))):
    e = cr.elements.new(p); e.color = c
L.new(hm.outputs[0], ramp.inputs[0])
pw2 = math_('POWER', hm.outputs[0], val=2.0)
est = math_('MULTIPLY', pw2.outputs[0], val=1.0)
ctrl["est"] = est
L.new(ramp.outputs[0], pv.inputs["Emission Color"])
L.new(est.outputs[0], pv.inputs["Emission Strength"])
cube.data.materials.append(mat)


def ss(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


for i in range(F0, F1 + 1):
    t = i / (NFR - 1)
    R = 1.55 * (1 - math.exp(-t * 7.0)) + 0.4 * t + 0.12   # cloud radius
    grow = R / 1.85
    ctrl["wn"].inputs["W"].default_value = t * 2.2
    ctrl["wn"].inputs["Scale"].default_value = 1.3 / max(grow, 0.35)
    ctrl["warp"].inputs["Scale"].default_value = 0.18 + 0.4 * grow
    ctrl["dn"].inputs["W"].default_value = 10 + t * 1.5
    ctrl["dn"].inputs["Scale"].default_value = 4.0 / max(grow, 0.45)
    ctrl["fn"].inputs["W"].default_value = 20 + t * 3.0
    for (dist, mr, d, rad, r) in ctrl["blobs"]:
        c = Vector(d) * rad * R * 0.62
        c.z = c.z * 0.6 + 0.05 + 0.25 * grow
        dist.inputs[1].default_value = c
        rr = r * (0.35 + 0.75 * grow)
        mr.inputs["From Min"].default_value = rr * 1.1
        mr.inputs["From Max"].default_value = rr * 0.2
    # density thins out with time (threshold rises, scale falls)
    heat = math.exp(-t / 0.15)
    fade = (1 - ss((t - 0.35) / 0.65)) ** 1.3
    ctrl["dens"].inputs["From Min"].default_value = 0.06 + 0.25 * ss((t - 0.4) / 0.6)
    ctrl["dens"].inputs["To Max"].default_value = 30.0 * fade * (1 - 0.5 * heat) + 0.3
    col = 0.13 + 0.17 * ss(t / 0.6)
    pv.inputs["Color"].default_value = (col, col, col * 0.98, 1)
    ctrl["hm"].inputs["From Min"].default_value = 0.8 - 0.75 * heat
    ctrl["hm"].inputs["From Max"].default_value = 1.7 - 1.2 * heat
    ctrl["est"].inputs[1].default_value = 0.0 if smokeonly else 400.0 * heat ** 1.3
    p = D + f"/f{i:03d}.exr"
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    exr_to_npy(p, p.replace(".exr", ".npy"))
    print("FRAME", i, flush=True)
