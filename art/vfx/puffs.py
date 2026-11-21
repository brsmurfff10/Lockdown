"""Procedural volumetric smoke puffs. -- <name> <px>"""
import bpy, math, os, sys, random
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfxlib import *

A = args()
name, px = A[0], int(A[1])
D = SCRATCH + "/" + name
os.makedirs(D, exist_ok=True)
scene = clear_scene()
setup_gpu(scene, samples=128)
scene.cycles.volume_bounces = 2
scene.cycles.max_bounces = 6
scene.cycles.volume_step_rate = 0.5
scene.render.resolution_x = scene.render.resolution_y = px
world(scene, 0.22, (0.85, 0.9, 1.0))
s = sun(scene, energy=7.0, angle=6)
d = Vector((1.0, -1.0, -0.85)).normalized()  # light travels toward lower-right (from upper-left)
s.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
top_camera(scene, 3.0)

bpy.ops.mesh.primitive_cube_add(size=4, location=(0, 0, 0))
cube = bpy.context.object


def make_mat(seed):
    rnd = random.Random(seed)
    mat = bpy.data.materials.new(f"P{seed}")
    mat.use_nodes = True
    nt = mat.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    pv = N.new("ShaderNodeVolumePrincipled")
    L.new(pv.outputs[0], out.inputs["Volume"])
    pv.inputs["Color"].default_value = (0.9, 0.9, 0.89, 1)
    pv.inputs["Anisotropy"].default_value = 0.15
    tc = N.new("ShaderNodeTexCoord")
    # domain warp
    wn = N.new("ShaderNodeTexNoise")
    wn.inputs["Scale"].default_value = 1.1 + rnd.random() * 0.5
    wn.inputs["Detail"].default_value = 3
    wn.noise_dimensions = '4D'
    wn.inputs["W"].default_value = rnd.random() * 100
    L.new(tc.outputs["Object"], wn.inputs["Vector"])
    sub = N.new("ShaderNodeVectorMath"); sub.operation = 'SUBTRACT'
    sub.inputs[1].default_value = (0.5, 0.5, 0.5)
    L.new(wn.outputs["Color"], sub.inputs[0])
    sc = N.new("ShaderNodeVectorMath"); sc.operation = 'SCALE'
    sc.inputs["Scale"].default_value = 0.55
    L.new(sub.outputs[0], sc.inputs[0])
    add = N.new("ShaderNodeVectorMath"); add.operation = 'ADD'
    L.new(tc.outputs["Object"], add.inputs[0])
    L.new(sc.outputs[0], add.inputs[1])
    pw = add.outputs[0]
    # blobs
    nb = rnd.randint(6, 10)
    acc = None
    for i in range(nb):
        if i == 0:
            c = (rnd.uniform(-.1, .1), rnd.uniform(-.1, .1), 0.0); r = rnd.uniform(0.8, 0.95)
        else:
            ang = rnd.random() * 6.283; rad = rnd.uniform(0.3, 0.62)
            c = (math.cos(ang) * rad, math.sin(ang) * rad, rnd.uniform(-0.2, 0.25)); r = rnd.uniform(0.35, 0.6)
        dist = N.new("ShaderNodeVectorMath"); dist.operation = 'DISTANCE'
        L.new(pw, dist.inputs[0]); dist.inputs[1].default_value = c
        mr = N.new("ShaderNodeMapRange"); mr.interpolation_type = 'SMOOTHERSTEP'
        mr.inputs["From Min"].default_value = r * 1.15
        mr.inputs["From Max"].default_value = r * 0.2
        L.new(dist.outputs["Value"], mr.inputs["Value"])
        if acc is None:
            acc = mr.outputs[0]
        else:
            m = N.new("ShaderNodeMath"); m.operation = 'ADD'
            L.new(acc, m.inputs[0]); L.new(mr.outputs[0], m.inputs[1]); acc = m.outputs[0]
    # billow detail
    dn = N.new("ShaderNodeTexNoise")
    dn.inputs["Scale"].default_value = 3.5 + rnd.random()
    dn.inputs["Detail"].default_value = 6
    dn.inputs["Roughness"].default_value = 0.55
    dn.noise_dimensions = '4D'
    dn.inputs["W"].default_value = rnd.random() * 100
    L.new(tc.outputs["Object"], dn.inputs["Vector"])
    dm = N.new("ShaderNodeMapRange")
    dm.inputs["From Min"].default_value = 0.3; dm.inputs["From Max"].default_value = 0.7
    dm.inputs["To Min"].default_value = 0.2; dm.inputs["To Max"].default_value = 1.5
    L.new(dn.outputs["Fac"], dm.inputs["Value"])
    m1 = N.new("ShaderNodeMath"); m1.operation = 'MULTIPLY'
    L.new(acc, m1.inputs[0]); L.new(dm.outputs[0], m1.inputs[1])
    # threshold so edges are wispy rather than sphere-shaped
    m2 = N.new("ShaderNodeMapRange")
    m2.inputs["From Min"].default_value = 0.05; m2.inputs["From Max"].default_value = 1.4
    m2.inputs["To Min"].default_value = 0.0; m2.inputs["To Max"].default_value = 14.0
    m2.interpolation_type = 'SMOOTHSTEP'
    L.new(m1.outputs[0], m2.inputs["Value"])
    L.new(m2.outputs[0], pv.inputs["Density"])
    return mat


for i in range(16):
    cube.data.materials.clear()
    cube.data.materials.append(make_mat(1000 + i * 17))
    cube.rotation_euler = (0, 0, 0)
    p = D + f"/p{i:02d}.exr"
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    exr_to_npy(p, p.replace(".exr", ".npy"))
    print("PUFF", i, flush=True)
