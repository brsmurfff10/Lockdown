"""Mantaflow explosion. usage: -- bake <name> <res> | render <name> <px> <f0> <f1> <step> [smokeonly]"""
import bpy, math, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfxlib import *

A = args()
mode, name = A[0], A[1]
D = SCRATCH + "/" + name
os.makedirs(D, exist_ok=True)
BLEND = D + "/scene.blend"
NF = 140
FS = float(os.environ.get("FS", "6"))


def build(res):
    scene = clear_scene()
    scene.frame_start, scene.frame_end = 1, NF
    scene.render.fps = 30
    # domain 8x8x6, bottom at z=0
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.3))
    dom = bpy.context.object
    dom.name = "Domain"
    dom.scale = (7, 7, 2.6)
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
    ds.cache_data_format = 'OPENVDB'
    ds.use_noise = False
    ds.noise_scale = 2
    ds.noise_strength = 1.2
    ds.vorticity = 0.35
    ds.alpha = 0.6       # smoke density buoyancy (positive = sinks less)
    ds.beta = 1.2        # heat buoyancy
    ds.burning_rate = 0.55
    ds.flame_smoke = 1.6
    ds.flame_vorticity = 1.3
    ds.flame_ignition = 1.25
    ds.flame_max_temp = 1.8
    ds.flame_smoke_color = (0.12, 0.11, 0.10)
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 70
    ds.use_dissolve_smoke_log = True
    ds.time_scale = 1.0
    ds.timesteps_max = 8
    ds.use_collision_border_bottom = True
    ds.use_collision_border_top = True
    # flow: lumpy sphere burst
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.5, location=(0, 0, 0.5))
    fl = bpy.context.object
    fl.name = "Flow"
    tex = bpy.data.textures.new("ft", 'CLOUDS')
    tex.noise_scale = 0.35
    dm = fl.modifiers.new("disp", 'DISPLACE')
    dm.texture = tex
    dm.strength = 0.35
    bpy.ops.object.modifier_apply(modifier="disp")
    f = fl.modifiers.new("Fluid", 'FLUID')
    f.fluid_type = 'FLOW'
    fs = f.flow_settings
    fs.flow_type = 'BOTH'
    fs.flow_behavior = 'INFLOW'
    fs.flow_source = 'MESH'
    fs.volume_density = 1.0
    fs.surface_distance = 0.3
    fs.fuel_amount = 2.8
    fs.temperature = 2.5
    fs.density = 1.0
    fs.smoke_color = (0.1, 0.09, 0.08)
    fs.use_initial_velocity = True
    fs.velocity_normal = 14.0
    fs.velocity_coord = (0, 0, 1.0)
    fs.subframes = 2
    fs.use_texture = True
    fs.noise_texture = tex
    fs.texture_map_type = 'AUTO'
    fs.texture_size = 1.0
    # burst for first frames, then stop emitting
    fs.use_inflow = True
    fs.keyframe_insert("use_inflow", frame=5)
    fs.use_inflow = False
    fs.keyframe_insert("use_inflow", frame=6)
    for fr, sc in ((1, 0.35), (3, 0.9), (5, 1.6)):
        fl.scale = (sc, sc, sc * 0.8)
        fl.keyframe_insert("scale", frame=fr)
    fl.hide_render = True
    # radial push so the cloud rolls outward along the ground
    bpy.ops.object.effector_add(type='FORCE', location=(0, 0, 0.0))
    fo = bpy.context.object
    fo.field.shape = 'POINT'
    fo.field.flow = 0.0
    for fr, st in ((1, 0.0), (2, FS * 1.0), (6, FS * 0.5), (15, FS * 0.15), (40, FS * 0.05), (140, FS * 0.02)):
        fo.field.strength = st
        fo.field.keyframe_insert("strength", frame=fr)
    bpy.ops.object.effector_add(type='TURBULENCE', location=(0, 0, 1))
    tu = bpy.context.object
    tu.field.strength = 6.0
    tu.field.size = 0.8
    tu.field.flow = 0.0
    tu.field.noise = 0.0
    return scene, dom, fl


def material(dom, smokeonly=False):
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
    # density scale with mild noise breakup
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 22.0
    nt.links.new(dens.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], pv.inputs["Density"])
    pv.inputs["Color"].default_value = (0.32, 0.30, 0.28, 1)
    pv.inputs["Anisotropy"].default_value = 0.2
    if not smokeonly:
        # flame -> colour ramp + strength
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.elements[0].position = 0.0; cr.elements[0].color = (0, 0, 0, 1)
        cr.elements[1].position = 1.0; cr.elements[1].color = (1.0, 0.95, 0.8, 1)
        for p, c in ((0.15, (0.35, 0.03, 0.0, 1)), (0.4, (1.0, 0.25, 0.02, 1)), (0.7, (1.0, 0.6, 0.15, 1))):
            e = cr.elements.new(p); e.color = c
        nt.links.new(flame.outputs["Fac"], ramp.inputs[0])
        pw = nt.nodes.new("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 1.6
        nt.links.new(flame.outputs["Fac"], pw.inputs[0])
        st = nt.nodes.new("ShaderNodeMath"); st.operation = 'MULTIPLY'; st.inputs[1].default_value = 30.0
        nt.links.new(pw.outputs[0], st.inputs[0])
        nt.links.new(ramp.outputs[0], pv.inputs["Emission Color"])
        nt.links.new(st.outputs[0], pv.inputs["Emission Strength"])
    dom.data.materials.clear()
    dom.data.materials.append(mat)


if mode == "bake":
    res = int(A[2])
    scene, dom, fl = build(res)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    t = time.time()
    with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom]):
        r = bpy.ops.fluid.bake_all()
    print("BAKE", r, time.time() - t)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
else:
    px, f0, f1, step = int(A[2]), int(A[3]), int(A[4]), int(A[5])
    smokeonly = len(A) > 6 and A[6] == "smokeonly"
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    scene = bpy.context.scene
    dom = bpy.data.objects["Domain"]
    material(dom, smokeonly)
    setup_gpu(scene, samples=96)
    scene.cycles.volume_bounces = 1
    scene.cycles.max_bounces = 4
    scene.render.resolution_x = scene.render.resolution_y = px
    world(scene, 0.35)
    sun(scene, rot=(math.radians(45), 0, math.radians(135)), energy=6.0)
    top_camera(scene, 7.0)
    sub = "render_smoke" if smokeonly else "render"
    os.makedirs(D + "/" + sub, exist_ok=True)
    for fr in range(f0, f1 + 1, step):
        scene.frame_set(fr)
        p = D + f"/{sub}/f{fr:04d}.exr"
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        exr_to_npy(p, p.replace(".exr", ".npy"))
        print("RENDERED", fr, flush=True)
