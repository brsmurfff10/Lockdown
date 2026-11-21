import bpy, math, os, sys
import numpy as np

SCRATCH = "C:/Users/lucas/AppData/Local/Temp/claude/eec82e66440eb993/cdba2fb7-a320-4560-b81d-5ae8c6cce097/scratchpad/vfx"


def args():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def setup_gpu(scene, samples=64, denoise=True):
    scene.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    ok = False
    for t in ('OPTIX', 'CUDA'):
        try:
            prefs.compute_device_type = t
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == t]
            if devs:
                for d in prefs.devices:
                    d.use = (d.type == t)
                ok = True
                print("GPU:", t, [d.name for d in devs])
                break
        except Exception as e:
            print("gpu fail", t, e)
    scene.cycles.device = 'GPU' if ok else 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = denoise
    scene.cycles.use_adaptive_sampling = True
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.file_format = 'OPEN_EXR'
    scene.render.image_settings.color_depth = '16'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.exr_codec = 'ZIP'


def top_camera(scene, ortho, z=20.0, cx=0.0, cy=0.0):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho
    cam_data.clip_end = 200
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (cx, cy, z)
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    return cam


def world(scene, strength=0.3, color=(0.8, 0.85, 1.0)):
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*color, 1)
    bg.inputs[1].default_value = strength


def sun(scene, rot=(math.radians(50), 0, math.radians(135)), energy=4.0, angle=8.0):
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = energy
    ld.angle = math.radians(angle)
    o = bpy.data.objects.new("Sun", ld)
    scene.collection.objects.link(o)
    o.rotation_euler = rot
    return o


def exr_to_npy(path_exr, path_npy):
    img = bpy.data.images.load(path_exr)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[::-1]
    np.save(path_npy, px.astype(np.float16))
    bpy.data.images.remove(img)
