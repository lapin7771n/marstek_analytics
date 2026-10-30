"""Golden Delta Blender kit: the building blocks of a headless social-video 3D shot.

A scene script puts its own folder on sys.path and imports this module:

    HERE = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, HERE)
    import gd_kit

Run it with:
    blender --factory-startup -b -P <script>.py -- --cycles-device CUDA [--preview]

The pure helpers (easing, frame_of, load_cues, args, enable_gpus) work without Blender so they can be tested on any machine.
"""

import argparse
import json
import math
import os
import sys
import time

try:
    import bpy
    import bmesh
    from mathutils import Matrix, Vector
except ImportError:
    bpy = None

FPS = 30
_args = None
_keys = {}


# ---------------------------------------------------------------- pure helpers


def frame_of(t, fps=None):
    """Blender frame of video time t in seconds; frame 1 is t = 0."""
    return int(math.floor(t * (fps or FPS) + 0.5)) + 1


def load_cues(path):
    """The cue list of a cues.json written by `gd-social cues`; set FPS from the file."""
    global FPS
    with open(path) as handle:
        spec = json.load(handle)
    FPS = int(spec.get("fps", FPS))
    return spec["cues"]


def back(overshoot):
    def ease(x):
        return 1 + (overshoot + 1) * (x - 1) ** 3 + overshoot * (x - 1) ** 2

    return ease


EASES = {
    "linear": lambda x: x,
    "out_cubic": lambda x: 1 - (1 - x) ** 3,
    "out_back": back(1.2),
    "in_cubic": lambda x: x ** 3,
    "in_out_cubic": lambda x: 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2,
}


def _ease(ease):
    if callable(ease):
        return ease
    return EASES[ease]


def _mix(a, b, p):
    if isinstance(a, (tuple, list)):
        return tuple(x + (y - x) * p for x, y in zip(a, b))
    return a + (b - a) * p


def _linear(hex_value):
    text = hex_value.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(text[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def enable_gpus(devices, requested):
    """Switch every device but the CPU on; raise unless one of the requested type is among them."""
    enabled = []
    for device in devices:
        device.use = device.type != "CPU"
        print("DEVICE", device.type, device.name, device.use)
        if device.use and device.type == requested:
            enabled.append(device.name)
    if not enabled:
        raise RuntimeError("no %s device is enabled: the render would run on the CPU" % requested)
    return enabled


# ---------------------------------------------------------------- arguments


def args():
    """Arguments after `--`: --cycles-device and --preview."""
    global _args
    if _args is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        parser = argparse.ArgumentParser()
        parser.add_argument("--cycles-device", dest="device", default="CUDA")
        parser.add_argument("--preview", action="store_true")
        _args = parser.parse_args(argv)
    return _args


# ---------------------------------------------------------------- scene


def reset(fps=30, width=1080, height=1920, frames=120):
    """Empty scene with the add-ons a shot needs, a black world and the frame range."""
    global FPS
    import addon_utils

    FPS = fps
    _keys.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name in ("cycles", "io_curve_svg"):
        addon_utils.enable(name, default_set=False)
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.frame_start = 1
    scene.frame_end = frames
    world = bpy.data.worlds.new("Dark")
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.8, 0.8, 0.8, 1)
    background.inputs["Strength"].default_value = 0.0
    scene.world = world
    return scene


def render_settings(samples=64, scale=100):
    """Cycles on the GPU, GPU denoise, transparent film, RGBA 8-bit PNG, flat colour."""
    scene = bpy.context.scene
    options = args()
    if options.preview:
        samples = 16
        scale = 50
    render = scene.render
    render.engine = "CYCLES"
    render.resolution_percentage = scale
    render.film_transparent = True
    render.image_settings.file_format = "PNG"
    render.image_settings.color_mode = "RGBA"
    render.image_settings.color_depth = "8"
    render.image_settings.compression = 15
    render.use_overwrite = True
    render.use_placeholder = False
    render.use_persistent_data = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.display_settings.display_device = "sRGB"
    cycles = scene.cycles
    cycles.samples = samples
    cycles.use_denoising = True
    cycles.denoiser = "OPENIMAGEDENOISE"
    cycles.denoising_use_gpu = True
    cycles.max_bounces = 6
    cycles.diffuse_bounces = 3
    cycles.glossy_bounces = 4
    cycles.device = "GPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = options.device
    prefs.get_devices()
    enable_gpus(prefs.devices, options.device)


def brand_material(name, hex_value, gloss=False):
    """Flat brand colour: under the Standard view transform a head-on face reads the hex."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    shader = tree.nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*_linear(hex_value), 1)
    shader.inputs["Metallic"].default_value = 0.0
    if gloss:
        shader.inputs["Roughness"].default_value = 0.3
        shader.inputs["Specular IOR Level"].default_value = 0.6
    else:
        shader.inputs["Roughness"].default_value = 0.9
        shader.inputs["Specular IOR Level"].default_value = 0.0
    tree.links.new(shader.outputs[0], output.inputs[0])
    return material


def mark_from_svg(path, width=2.0, depth=0.28, bevel=0.035):
    """A solid prism of the SVG outline, standing in the XZ plane, centred on the origin.

    The outline becomes one flat face, is extruded as a mesh and beveled by a modifier limited
    by angle, so the stroke ends stay square instead of the notched ends a curve bevel leaves.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=path)
    curves = [o for o in bpy.data.objects if o not in before and o.type == "CURVE"]
    if not curves:
        raise RuntimeError("the SVG import produced no curves: " + path)
    bpy.ops.object.select_all(action="DESELECT")
    for curve in curves:
        curve.select_set(True)
    bpy.context.view_layer.objects.active = curves[0]
    if len(curves) > 1:
        bpy.ops.object.join()
    flat = bpy.context.view_layer.objects.active
    flat.data.dimensions = "2D"
    flat.data.fill_mode = "FRONT"
    flat.data.resolution_u = 12
    flat.data.extrude = 0.0
    flat.data.bevel_depth = 0.0
    bpy.ops.object.convert(target="MESH")
    flat = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    builder = bmesh.new()
    builder.from_mesh(flat.data)
    bmesh.ops.remove_doubles(builder, verts=builder.verts, dist=1e-5)
    bmesh.ops.dissolve_limit(
        builder,
        angle_limit=math.radians(0.5),
        verts=builder.verts,
        edges=builder.edges,
    )
    xs = [v.co.x for v in builder.verts]
    ys = [v.co.y for v in builder.verts]
    scale = width / (max(xs) - min(xs))
    center = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, 0))
    for vert in builder.verts:
        vert.co = (vert.co - center) * scale
        vert.co.z = 0.0
    faces = list(builder.faces)
    extruded = bmesh.ops.extrude_face_region(builder, geom=faces)
    top = [g for g in extruded["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(builder, vec=(0, 0, depth), verts=top)
    bmesh.ops.translate(builder, vec=(0, 0, -depth / 2), verts=builder.verts)
    bmesh.ops.rotate(
        builder,
        cent=(0, 0, 0),
        matrix=Matrix.Rotation(math.radians(90), 3, "X"),
        verts=builder.verts,
    )
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    open_edges = [e for e in builder.edges if not e.is_manifold]
    if open_edges:
        raise RuntimeError("the mark mesh is not closed: %d open edges" % len(open_edges))

    mesh = bpy.data.meshes.new("Mark")
    builder.to_mesh(mesh)
    builder.free()
    bpy.data.objects.remove(flat)
    mark = bpy.data.objects.new("Mark", mesh)
    bpy.context.scene.collection.objects.link(mark)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(35))
    modifier = mark.modifiers.new("Bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 3
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(35)
    mark.modifiers.new("Normals", "WEIGHTED_NORMAL").keep_sharp = True
    return mark


def _aim(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _area(name, location, power, size, target, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    _aim(light, target)
    return light


def studio_lights(target, floor=None):
    """Key, fill and rim area lights; the floor is excluded from key and rim, so only the fill shadows it."""
    key_light = _area("Key", (-3.2, -4.2, 4.2), 490, 3.5, target)
    fill_light = _area("Fill", (3.6, -2.2, 3.2), 205, 4.0, target)
    rim_light = _area("Rim", (2.8, 4.5, 2.5), 500, 2.0, target, (1.0, 0.9, 0.75))
    if floor is not None:
        shield = bpy.data.collections.new("LightsSkipFloor")
        shield.objects.link(floor)
        shield.collection_objects[0].light_linking.link_state = "EXCLUDE"
        key_light.light_linking.receiver_collection = shield
        rim_light.light_linking.receiver_collection = shield
    return key_light, fill_light, rim_light


def shadow_floor(z):
    """A plane at height z that renders only the shadows falling on it."""
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, z))
    floor = bpy.context.view_layer.objects.active
    floor.name = "Floor"
    floor.is_shadow_catcher = True
    material = bpy.data.materials.new("FloorMat")
    material.use_nodes = True
    floor.data.materials.append(material)
    return floor


def camera(location, target, lens):
    data = bpy.data.cameras.new("Cam")
    data.lens = lens
    data.sensor_fit = "HORIZONTAL"
    data.sensor_width = 36
    cam = bpy.data.objects.new("Cam", data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = location
    _aim(cam, target)
    bpy.context.scene.camera = cam
    return cam


# ---------------------------------------------------------------- animation


def key(obj, data_path, frame, value, ease="linear"):
    """Key obj.<data_path> at frame; the frames since the previous key are baked with the easing."""
    curve = _ease(ease)
    if isinstance(value, (tuple, list)):
        value = tuple(value)
    slot = (obj.name, data_path)
    if slot in _keys:
        start, before = _keys[slot]
        for f in range(start + 1, frame):
            progress = curve((f - start) / (frame - start))
            setattr(obj, data_path, _mix(before, value, progress))
            obj.keyframe_insert(data_path, frame=f)
    setattr(obj, data_path, value)
    obj.keyframe_insert(data_path, frame=frame)
    _keys[slot] = (frame, value)


# ---------------------------------------------------------------- render


def _frames(preview_frames):
    scene = bpy.context.scene
    first = scene.frame_start
    last = scene.frame_end
    if not args().preview:
        return list(range(first, last + 1))
    if preview_frames:
        return list(preview_frames)
    return [first, (first + last) // 2, last]


def render_layer(name, out_dir, hide_from_camera=(), preview_frames=None):
    """Render the frame range to out_dir/<name>/f_####.png and skip the frames already on disk.

    Objects in hide_from_camera stay in the scene, so they still cast shadows and bounce light.
    A preview renders three frames into out_dir/preview/<name>/ and never skips.
    """
    scene = bpy.context.scene
    preview = args().preview
    folder = os.path.join(out_dir, "preview", name) if preview else os.path.join(out_dir, name)
    os.makedirs(folder, exist_ok=True)
    hidden = [(o, o.visible_camera) for o in hide_from_camera]
    for obj, _ in hidden:
        obj.visible_camera = False
    started = time.time()
    done = 0
    skipped = 0
    for frame in _frames(preview_frames):
        target = os.path.join(folder, "f_%04d" % frame)
        if not preview and os.path.exists(target + ".png"):
            skipped += 1
            continue
        scene.frame_set(frame)
        scene.render.filepath = target
        begun = time.time()
        bpy.ops.render.render(write_still=True)
        if not os.path.exists(target + ".png"):
            raise RuntimeError("the render wrote no file: " + target + ".png")
        done += 1
        print("FRAME %s %d %.2fs" % (name, frame, time.time() - begun))
    for obj, visible in hidden:
        obj.visible_camera = visible
    print("LAYER %s rendered=%d skipped=%d seconds=%.1f" % (name, done, skipped, time.time() - started))
