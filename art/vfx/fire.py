"""Mantaflow ground fire. -- bake <name> <res> | render <name> <px> <f0> <f1> <step>"""
import bpy, math, os, sys, time, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfxlib import *

A = args()
mode, name = A[0], A[1]
D = SCRATCH + "/" + name
os.makedirs(D, exist_ok=True)
BLEND = D + "/scene.blend"
NF = 190
EMIT = float(os.environ.get("EMIT", "16"))
FLAMEDENS = float(os.environ.get("FLAMEDENS", "3"))


def build(res):
    scene = clear_scene()
    scene.frame_start, scene.frame_end = 1, NF
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.5))
    dom = bpy.context.object
    dom.name = "Domain"
    dom.scale = (4, 4, 3)
    bpy.ops.object.transform_apply(scale=True)
    m = dom.modifiers.new("Fluid", 'FLUID')
    m.fluid_type = 'DOMAIN'
    ds = m.domain_settings
    ds.domain_type = 'GAS'
    ds.resolution_max = res
    ds.cache_directory = D + "/cache"
    ds.cache_type = 'ALL'
    ds.cache_frame_start = 1
    ds.cache_frame_end = NF
    ds.use_noise = False
    ds.noise_scale = 2
    ds.noise_strength = 1.5
    ds.vorticity = 0.6
    ds.beta = 1.0
    ds.alpha = 0.5
    ds.burning_rate = 0.95
    ds.flame_smoke = 0.25
    ds.flame_vorticity = 2.2
    ds.flame_ignition = 1.25
    ds.flame_max_temp = 1.75
    ds.flame_smoke_color = (0.1, 0.09, 0.08)
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 18
    ds.use_collision_border_top = False
    for side in ('front', 'back', 'left', 'right'):
        setattr(ds, "use_collision_border_" + side, False)
    # irregular burning patch from several flat discs
    rnd = random.Random(7)
    objs = []
    for i in range(34):
        a = rnd.random() * 6.283; r = 1.0 * math.sqrt(rnd.random())
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=rnd.uniform(0.07, 0.17), depth=0.08,
                                            location=(math.cos(a) * r, math.sin(a) * r, 0.06))
        objs.append(bpy.context.object)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    fl = bpy.context.object
    fl.name = "Flow"
    tex = bpy.data.textures.new("ft", 'CLOUDS')
    tex.noise_scale = 0.15
    tex.noise_depth = 3
    f = fl.modifiers.new("Fluid", 'FLUID')
    f.fluid_type = 'FLOW'
    fs = f.flow_settings
    fs.flow_type = 'FIRE'
    fs.flow_behavior = 'INFLOW'
    fs.flow_source = 'MESH'
    fs.surface_distance = 0.12
    fs.volume_density = 1.0
    fs.fuel_amount = 1.2
    fs.temperature = 1.5
    fs.use_initial_velocity = True
    fs.velocity_coord = (0, 0, 1.4)
    fs.use_texture = True
    fs.noise_texture = tex
    fs.texture_map_type = 'AUTO'
    fs.texture_size = 1.0
    fs.texture_offset = 0.0
    fs.keyframe_insert("texture_offset", frame=1)
    fs.texture_offset = 3.0
    fs.keyframe_insert("texture_offset", frame=NF)
    fl.hide_render = True
    bpy.ops.object.effector_add(type='TURBULENCE', location=(0, 0, 0.8))
    tu = bpy.context.object
    tu.field.strength = 9.0
    tu.field.size = 0.45
    tu.field.flow = 0.0
    tu.field.noise = 0.0
    tu.field.use_max_distance = False
    tu.location = (0, 0, 0.8)
    tu.keyframe_insert("location", frame=1)
    tu.location = (1.3, 0.9, 1.6)
    tu.keyframe_insert("location", frame=NF)
    return scene, dom


def material(dom):
    mat = bpy.data.materials.new("Vol")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    nt.links.new(pv.outputs[0], out.inputs["Volume"])
    dens = nt.nodes.new("ShaderNodeAttribute"); dens.attribute_name = "density"
    flame = nt.nodes.new("ShaderNodeAttribute"); flame.attribute_name = "flame"
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 2.5
    fa = nt.nodes.new("ShaderNodeMath"); fa.operation = 'MULTIPLY_ADD'
    nt.links.new(flame.outputs["Fac"], fa.inputs[0]); fa.inputs[1].default_value = FLAMEDENS
    nt.links.new(dens.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], fa.inputs[2])
    nt.links.new(fa.outputs[0], pv.inputs["Density"])
    try:
        mat.cycles.volume_interpolation = 'CUBIC'
    except Exception as e:
        print('interp', e)
    pv.inputs["Color"].default_value = (0.1, 0.09, 0.08, 1)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0; cr.elements[0].color = (0, 0, 0, 1)
    cr.elements[1].position = 1.0; cr.elements[1].color = (1.0, 0.72, 0.22, 1)
    for p, c in ((0.12, (0.3, 0.02, 0.0, 1)), (0.35, (0.9, 0.12, 0.005, 1)), (0.65, (1.0, 0.42, 0.05, 1))):
        e = cr.elements.new(p); e.color = c
    nt.links.new(flame.outputs["Fac"], ramp.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 1.5
    nt.links.new(flame.outputs["Fac"], pw.inputs[0])
    st = nt.nodes.new("ShaderNodeMath"); st.operation = 'MULTIPLY'; st.inputs[1].default_value = EMIT
    nt.links.new(pw.outputs[0], st.inputs[0])
    nt.links.new(ramp.outputs[0], pv.inputs["Emission Color"])
    nt.links.new(st.outputs[0], pv.inputs["Emission Strength"])
    dom.data.materials.clear()
    dom.data.materials.append(mat)


if mode == "bake":
    scene, dom = build(int(A[2]))
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    t = time.time()
    with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom]):
        r = bpy.ops.fluid.bake_all()
    print("BAKE", r, time.time() - t)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
else:
    px, f0, f1, step = int(A[2]), int(A[3]), int(A[4]), int(A[5])
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    scene = bpy.context.scene
    dom = bpy.data.objects["Domain"]
    material(dom)
    setup_gpu(scene, samples=64)
    scene.cycles.volume_bounces = 1
    scene.render.resolution_x = scene.render.resolution_y = px
    world(scene, 0.4)
    sun(scene, energy=2.0)
    top_camera(scene, 4.0)
    os.makedirs(D + "/render", exist_ok=True)
    for fr in range(f0, f1 + 1, step):
        scene.frame_set(fr)
        p = D + f"/render/f{fr:04d}.exr"
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        exr_to_npy(p, p.replace(".exr", ".npy"))
        print("RENDERED", fr, flush=True)
