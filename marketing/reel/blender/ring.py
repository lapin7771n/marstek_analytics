"""Battery ETA reel: a glass gauge ring floats in a blackout, light flows in and fills it to 58 %.

The whole reel is one continuous shot; the Remotion composition draws the UI over it.
Run from the project root: blender --factory-startup -b -P blender/ring.py -- --cycles-device CUDA [--preview]
Env: RING_FRAMES=a-b renders only Blender frames a..b. Blender frame = Remotion frame + 1.
"""

import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gd_kit

bpy = gd_kit.bpy
from mathutils import Vector

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "public", "3d")

import json

SPEC = json.load(open(os.path.join(ROOT, "public", "audio", "BatteryEtaReel.cues.json")))
FPS = int(SPEC["fps"])
DURATION = float(SPEC["duration"])
STILL = os.environ.get("RING_STILL")
FRAMES = int(round(DURATION * FPS))
EV = SPEC["events"]
SC = SPEC["scenes"]

GREEN = "#3DDC97"
RED = "#FF6B5E"
BG = "#0F0F12"
TRACK = "#24242A"

R = 1.0
GLASS_R = 0.14
TRACK_R = 0.09
LIQUID_R = 0.096
START_DEG = 225.0
SWEEP_DEG = 270.0


# ---------------------------------------------------------------- pure time functions


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def prog(t, start, dur):
    return clamp((t - start) / dur)


def out_cubic(x):
    return 1 - (1 - x) ** 3


def in_out(x):
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def smooth(x):
    return x * x * (3 - 2 * x)


def lerp(a, b, p):
    return a + (b - a) * p


def fill_at(t):
    return EV["fillTo"] * out_cubic(prog(t, EV["fillStart"], EV["fillDur"]))


def red_mix(t):
    up = in_out(prog(t, EV["red"][0], EV["red"][1] - EV["red"][0]))
    down = in_out(prog(t, EV["green"][0], EV["green"][1] - EV["green"][0]))
    return up * (1 - down)


def pulse(t, at, tau=0.28, amp=0.4):
    return amp * math.exp(-(t - at) / tau) if t >= at else 0.0


def warm_mix(t):
    """0 while the ring shows percent only, 1 once Battery ETA has lit it."""
    return in_out(prog(t, EV["warm"][0], EV["warm"][1] - EV["warm"][0]))


def alive(t):
    """Light level of the room: dim in the blackout, brighter once the ring fills, full once Battery ETA answers."""
    return 0.3 + 0.3 * smooth(prog(t, SC["problem"][0], 1.0)) + 0.4 * warm_mix(t)


def cta_blend(t):
    return in_out(prog(t, EV["ctaFace"][0], EV["ctaFace"][1] - EV["ctaFace"][0]))


def cam_distance(t):
    hook = 5.2 + 0.18 * prog(t, 0, SC["hook"][1])
    glide = in_out(prog(t, EV["glide"][0], EV["glide"][1] - EV["glide"][0]))
    return lerp(hook, 6.0, glide)


def ring_center_px(t):
    glide = in_out(prog(t, EV["glide"][0], EV["glide"][1] - EV["glide"][0]))
    return lerp(1020.0, 880.0, glide)


def ring_pose(t):
    k = 1 - cta_blend(t)
    yaw = math.radians(16) * math.sin(0.5 * t + 0.6) * k
    pitch = (math.radians(-12) + math.radians(4) * math.sin(0.37 * t)) * k
    roll = math.radians(3) * math.sin(0.22 * t + 1.0) * k
    return pitch, roll, yaw


# ---------------------------------------------------------------- scene


gd_kit.reset(fps=FPS, width=1080, height=1920, frames=FRAMES)
gd_kit.render_settings(samples=48)
scene = bpy.context.scene
scene.render.film_transparent = False
scene.render.image_settings.file_format = "JPEG"
scene.render.image_settings.color_mode = "RGB"
scene.render.image_settings.quality = 96
cycles = scene.cycles
cycles.max_bounces = 12
cycles.transmission_bounces = 10
cycles.glossy_bounces = 5
cycles.sample_clamp_indirect = 3.0
cycles.sample_clamp_direct = 0.0
cycles.caustics_reflective = False
cycles.caustics_refractive = False
cycles.blur_glossy = 0.6
scene.render.filter_size = 1.3

# World: camera rays see the flat brand background, every other ray sees a faint cool environment.
world = scene.world
tree = world.node_tree
tree.nodes.clear()
w_out = tree.nodes.new("ShaderNodeOutputWorld")
w_mix = tree.nodes.new("ShaderNodeMixShader")
w_env = tree.nodes.new("ShaderNodeBackground")
w_bg = tree.nodes.new("ShaderNodeBackground")
w_path = tree.nodes.new("ShaderNodeLightPath")
w_env.inputs["Color"].default_value = (0.35, 0.45, 0.5, 1)
w_env.inputs["Strength"].default_value = 0.12
w_bg.inputs["Color"].default_value = (*gd_kit._linear(BG), 1)
w_bg.inputs["Strength"].default_value = 1.0
tree.links.new(w_path.outputs["Is Camera Ray"], w_mix.inputs["Fac"])
tree.links.new(w_env.outputs[0], w_mix.inputs[1])
tree.links.new(w_bg.outputs[0], w_mix.inputs[2])
tree.links.new(w_mix.outputs[0], w_out.inputs[0])


def principled(name, base, rough, **inputs):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    sh = nt.nodes.new("ShaderNodeBsdfPrincipled")
    sh.inputs["Base Color"].default_value = base
    sh.inputs["Roughness"].default_value = rough
    for key, value in inputs.items():
        sh.inputs[key.replace("_", " ")].default_value = value
    nt.links.new(sh.outputs[0], out.inputs[0])
    return mat


glass_mat = principled(
    "Glass", (0.92, 0.98, 0.97, 1), 0.035,
    Transmission_Weight=1.0, IOR=1.46, Specular_IOR_Level=0.7,
)
track_mat = principled("Track", (*gd_kit._linear(TRACK), 1), 0.22, Specular_IOR_Level=0.5)

# Liquid: emission with a slow flowing noise, colour and strength keyed per frame.
liquid_mat = bpy.data.materials.new("Liquid")
liquid_mat.use_nodes = True
lt = liquid_mat.node_tree
lt.nodes.clear()
l_out = lt.nodes.new("ShaderNodeOutputMaterial")
l_emit = lt.nodes.new("ShaderNodeEmission")
l_coord = lt.nodes.new("ShaderNodeTexCoord")
l_map = lt.nodes.new("ShaderNodeMapping")
l_noise = lt.nodes.new("ShaderNodeTexNoise")
l_range = lt.nodes.new("ShaderNodeMapRange")
l_mul = lt.nodes.new("ShaderNodeMath")
l_noise.inputs["Scale"].default_value = 3.2
l_noise.inputs["Detail"].default_value = 3.0
l_range.inputs["From Min"].default_value = 0.3
l_range.inputs["From Max"].default_value = 0.7
l_range.inputs["To Min"].default_value = 0.65
l_range.inputs["To Max"].default_value = 1.45
l_mul.operation = "MULTIPLY"
lt.links.new(l_coord.outputs["Object"], l_map.inputs["Vector"])
lt.links.new(l_map.outputs[0], l_noise.inputs["Vector"])
lt.links.new(l_noise.outputs["Fac"], l_range.inputs["Value"])
lt.links.new(l_range.outputs[0], l_mul.inputs[0])
lt.links.new(l_mul.outputs[0], l_emit.inputs["Strength"])
lt.links.new(l_emit.outputs[0], l_out.inputs[0])

# Tip: the bright head of the liquid.
tip_mat = bpy.data.materials.new("Tip")
tip_mat.use_nodes = True
tt = tip_mat.node_tree
tt.nodes.clear()
t_out = tt.nodes.new("ShaderNodeOutputMaterial")
t_emit = tt.nodes.new("ShaderNodeEmission")
tt.links.new(t_emit.outputs[0], t_out.inputs[0])

# Threads and dust.
thread_mat = bpy.data.materials.new("Thread")
thread_mat.use_nodes = True
tht = thread_mat.node_tree
tht.nodes.clear()
th_out = tht.nodes.new("ShaderNodeOutputMaterial")
th_emit = tht.nodes.new("ShaderNodeEmission")
th_emit.inputs["Color"].default_value = (*gd_kit._linear("#7CF0BC"), 1)
th_emit.inputs["Strength"].default_value = 4.0
tht.links.new(th_emit.outputs[0], th_out.inputs[0])

dust_mat = bpy.data.materials.new("Dust")
dust_mat.use_nodes = True
dt = dust_mat.node_tree
dt.nodes.clear()
d_out = dt.nodes.new("ShaderNodeOutputMaterial")
d_emit = dt.nodes.new("ShaderNodeEmission")
d_emit.inputs["Color"].default_value = (0.7, 0.85, 1.0, 1)
d_emit.inputs["Strength"].default_value = 1.4
dt.links.new(d_emit.outputs[0], d_out.inputs[0])

# Halo: a big radial glow plane behind the ring.
halo_mat = bpy.data.materials.new("Halo")
halo_mat.use_nodes = True
ht = halo_mat.node_tree
ht.nodes.clear()
h_out = ht.nodes.new("ShaderNodeOutputMaterial")
h_emit = ht.nodes.new("ShaderNodeEmission")
h_coord = ht.nodes.new("ShaderNodeTexCoord")
h_sub = ht.nodes.new("ShaderNodeVectorMath")
h_len = ht.nodes.new("ShaderNodeVectorMath")
h_range = ht.nodes.new("ShaderNodeMapRange")
h_pow = ht.nodes.new("ShaderNodeMath")
h_mul = ht.nodes.new("ShaderNodeMath")
h_sub.operation = "SUBTRACT"
h_sub.inputs[1].default_value = (0.5, 0.5, 0.0)
h_len.operation = "LENGTH"
h_range.inputs["From Min"].default_value = 0.0
h_range.inputs["From Max"].default_value = 0.5
h_range.inputs["To Min"].default_value = 1.0
h_range.inputs["To Max"].default_value = 0.0
h_pow.operation = "POWER"
h_pow.inputs[1].default_value = 5.0
h_mul.operation = "MULTIPLY"
ht.links.new(h_coord.outputs["UV"], h_sub.inputs[0])
ht.links.new(h_sub.outputs[0], h_len.inputs[0])
ht.links.new(h_len.outputs["Value"], h_range.inputs["Value"])
ht.links.new(h_range.outputs[0], h_pow.inputs[0])
ht.links.new(h_pow.outputs[0], h_mul.inputs[0])
ht.links.new(h_mul.outputs[0], h_emit.inputs["Strength"])
h_trans = ht.nodes.new("ShaderNodeBsdfTransparent")
h_add = ht.nodes.new("ShaderNodeAddShader")
ht.links.new(h_emit.outputs[0], h_add.inputs[0])
ht.links.new(h_trans.outputs[0], h_add.inputs[1])
ht.links.new(h_add.outputs[0], h_out.inputs[0])


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


pivot = link(bpy.data.objects.new("Pivot", None))


def arc_points(radius, n):
    pts = []
    for k in range(n + 1):
        ang = math.radians(START_DEG - SWEEP_DEG * k / n)
        pts.append((radius * math.cos(ang), 0.0, radius * math.sin(ang)))
    return pts


def poly_curve(name, pts, bevel, resolution=6):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_mode = "ROUND"
    data.bevel_depth = bevel
    data.bevel_resolution = resolution
    data.resolution_u = 2
    data.use_fill_caps = False
    spline = data.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for p, co in zip(spline.points, pts):
        p.co = (co[0], co[1], co[2], 1.0)
    obj = link(bpy.data.objects.new(name, data))
    return obj


def sphere(name, radius, location, mat, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=segments // 2, location=location)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.materials.append(mat)
    return obj


N_ARC = 220
arc = arc_points(R, N_ARC)

glass = poly_curve("Glass", arc, GLASS_R, 10)
glass.data.materials.append(glass_mat)
glass.parent = pivot
track = poly_curve("TrackTube", arc, TRACK_R, 8)
track.data.materials.append(track_mat)
track.parent = pivot
liquid = poly_curve("Liquid", arc, LIQUID_R, 8)
liquid.data.materials.append(liquid_mat)
liquid.data.bevel_factor_mapping_start = "SPLINE"
liquid.data.bevel_factor_mapping_end = "SPLINE"
liquid.data.bevel_factor_start = 0.0
liquid.data.bevel_factor_end = 0.0
liquid.parent = pivot

end_a = (R * math.cos(math.radians(START_DEG)), 0.0, R * math.sin(math.radians(START_DEG)))
end_b = (R * math.cos(math.radians(START_DEG - SWEEP_DEG)), 0.0, R * math.sin(math.radians(START_DEG - SWEEP_DEG)))
caps = [
    sphere("GlassCapA", GLASS_R, end_a, glass_mat, 32),
    sphere("GlassCapB", GLASS_R, end_b, glass_mat, 32),
    sphere("TrackCapA", TRACK_R, end_a, track_mat),
    sphere("TrackCapB", TRACK_R, end_b, track_mat),
]
liq_cap = sphere("LiquidCap", LIQUID_R, end_a, liquid_mat)
tip = sphere("Tip", LIQUID_R * 1.0, end_a, tip_mat)
for obj in caps + [liq_cap, tip]:
    obj.parent = pivot

# Threads of light that flow into the start of the arc.
rng = random.Random(11)
THREADS = []
for i in range(9):
    v0 = Vector((rng.uniform(-1, 1), rng.uniform(-1.4, 0.8), rng.uniform(-0.3, 1.0))).normalized()
    axis = v0.cross(Vector((0, 0, 1)) if abs(v0.z) < 0.9 else Vector((1, 0, 0))).normalized()
    r0 = rng.uniform(3.4, 4.6)
    turns = rng.uniform(0.3, 0.6) * rng.choice((-1, 1))
    pts = []
    for k in range(90):
        u = k / 89
        rr = r0 * (1 - u) ** 1.7
        ang = turns * 2 * math.pi * (1 - u)
        rot = v0 * math.cos(ang) + axis.cross(v0) * math.sin(ang) + axis * axis.dot(v0) * (1 - math.cos(ang))
        c = Vector(end_a) + rot * rr
        pts.append((c.x, c.y, c.z))
    obj = poly_curve("Thread%d" % i, pts, 0.02 + 0.008 * rng.random(), 3)
    obj.data.bevel_factor_mapping_start = "SPLINE"
    obj.data.bevel_factor_mapping_end = "SPLINE"
    obj.data.bevel_factor_start = 0.0
    obj.data.bevel_factor_end = 0.0
    obj.data.materials.append(thread_mat)
    obj.parent = pivot
    THREADS.append((obj, EV["threadStart"] + 0.11 * i, rng.uniform(0.95, 1.25)))

# Dust: tiny emitters that read as soft bokeh through the depth of field.
DUST = []
for i in range(45):
    p = (rng.uniform(-4.2, 4.2), rng.uniform(-1.5, 5.0), rng.uniform(-6.0, 5.0))
    obj = sphere("Dust%d" % i, rng.uniform(0.012, 0.03), p, dust_mat, 8)
    DUST.append((obj, p, rng.uniform(0.05, 0.14), rng.uniform(-0.04, 0.04)))

# Halo plane behind the ring.
bpy.ops.mesh.primitive_plane_add(size=15, location=(0, 3.2, 0), rotation=(math.pi / 2, 0, 0))
halo = bpy.context.view_layer.objects.active
halo.name = "Halo"
halo.data.materials.append(halo_mat)
halo.visible_shadow = False

# Lights: softboxes for glass edges.
LIGHTS = []


def area(name, loc, power, size, size_y=None, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.color = color
    if size_y is None:
        data.shape = "SQUARE"
        data.size = size
    else:
        data.shape = "RECTANGLE"
        data.size = size
        data.size_y = size_y
    obj = link(bpy.data.objects.new(name, data))
    obj.location = loc
    gd_kit._aim(obj, (0, 0, 0))
    LIGHTS.append((obj, power))
    return obj


area("Key", (-3.6, -4.6, 3.4), 900, 3.2, color=(0.9, 0.96, 1.0))
area("StripR", (4.4, -2.4, 0.6), 800, 0.7, 5.0, color=(0.85, 1.0, 0.95))
area("StripL", (-4.6, -1.0, -1.2), 500, 0.6, 4.5, color=(0.8, 0.9, 1.0))
area("Top", (0.5, -2.6, 4.8), 650, 5.0, 0.8, color=(1.0, 1.0, 1.0))
area("Rim", (2.4, 4.4, 2.2), 380, 2.4, color=(0.7, 1.0, 0.9))

# Camera.
cam = gd_kit.camera((0, -5.2, 0), (0, 0, 0), 50)
cam.rotation_euler = (math.pi / 2, 0, 0)
cam.data.dof.use_dof = True
cam.data.dof.aperture_fstop = 0.9

SHIFT_SIGN = 1.0


def set_key(owner, path, frame, value=None):
    owner.keyframe_insert(path, frame=frame)


def shift_for(px):
    return SHIFT_SIGN * (px - 960.0) / 1080.0


COLD = "#7C93AD"


def tint(t):
    if STILL == "warn":
        return gd_kit._linear("#FF8A55")
    w = warm_mix(t)
    m = red_mix(t)
    cold = gd_kit._linear(COLD)
    g = gd_kit._linear(GREEN)
    r = gd_kit._linear(RED)
    base = tuple(lerp(a, b, w) for a, b in zip(cold, g))
    return tuple(lerp(a, b, m) for a, b in zip(base, r))


def pose_frame(frame):
    t = (frame - 1) / FPS
    scene.frame_set(frame)
    # ring
    pitch, roll, yaw = ring_pose(t)
    pivot.rotation_euler = (pitch, roll, yaw)
    pivot.keyframe_insert("rotation_euler", frame=frame)
    # camera
    d = 4.5 if STILL else cam_distance(t)
    cam.location = (0, -d, 0)
    cam.keyframe_insert("location", frame=frame)
    cam.data.shift_y = 0.0 if STILL else shift_for(ring_center_px(t))
    cam.data.keyframe_insert("shift_y", frame=frame)
    cam.data.dof.use_dof = not STILL
    cam.data.dof.focus_distance = d
    cam.data.dof.keyframe_insert("focus_distance", frame=frame)
    # liquid
    f = fill_at(t)
    liquid.data.bevel_factor_end = f
    liquid.data.keyframe_insert("bevel_factor_end", frame=frame)
    ang = math.radians(START_DEG - SWEEP_DEG * f)
    tip.location = (R * math.cos(ang), 0.0, R * math.sin(ang))
    tip.keyframe_insert("location", frame=frame)
    vis = 1.0 if f > 0.002 else 0.0
    for obj in (tip, liq_cap):
        obj.scale = (vis, vis, vis)
        obj.keyframe_insert("scale", frame=frame)
    col = tint(t)
    boost = (
        pulse(t, SC["answer"][0] + 0.3, 0.35, 0.7)
        + pulse(t, EV["red"][0], 0.25, 0.5)
        + pulse(t, EV["green"][0], 0.3, 0.35)
        + pulse(t, EV["ctaFace"][0], 0.35, 0.3)
    )
    w_ = 1.0 if STILL else warm_mix(t)
    base = lerp(0.5, 1.25, w_) * (1 + boost)
    l_emit.inputs["Color"].default_value = (*col, 1)
    l_emit.inputs["Color"].keyframe_insert("default_value", frame=frame)
    l_mul.inputs[1].default_value = base
    l_mul.inputs[1].keyframe_insert("default_value", frame=frame)
    t_emit.inputs["Color"].default_value = tuple(lerp(c, 1.0, 0.15) for c in col) + (1,)
    t_emit.inputs["Color"].keyframe_insert("default_value", frame=frame)
    t_emit.inputs["Strength"].default_value = lerp(0.7, 1.8, w_) * (1 + boost)
    t_emit.inputs["Strength"].keyframe_insert("default_value", frame=frame)
    # flow
    l_map.inputs["Location"].default_value = (0.0, t * 0.9, t * 0.35)
    l_map.inputs["Location"].keyframe_insert("default_value", frame=frame)
    # halo
    a = alive(t)
    halo_level = (0.06 * (f / EV["fillTo"]) + 0.94 * w_) * (1 + 0.8 * boost)
    h_emit.inputs["Color"].default_value = (*col, 1)
    h_emit.inputs["Color"].keyframe_insert("default_value", frame=frame)
    h_mul.inputs[1].default_value = 0.36 * halo_level
    h_mul.inputs[1].keyframe_insert("default_value", frame=frame)
    # lights
    level = 1.0 if STILL else a
    for obj, power in LIGHTS:
        obj.data.energy = power * level
        obj.data.keyframe_insert("energy", frame=frame)
    # threads
    for obj, ts, dur in THREADS:
        head = in_out(prog(t, ts, dur))
        tail = in_out(prog(t, ts + 0.24, dur))
        obj.data.bevel_factor_end = head
        obj.data.bevel_factor_start = tail
        obj.data.keyframe_insert("bevel_factor_end", frame=frame)
        obj.data.keyframe_insert("bevel_factor_start", frame=frame)


if STILL:
    scene.render.resolution_x = 2600
    scene.render.resolution_y = 2600
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 15
    cycles.samples = 400
    for obj in [halo] + [o for o, _, _ in THREADS] + [o for o, _, _, _ in DUST]:
        obj.hide_render = True
    STILL_FRAME = int((SC["verdict"][0] + 1.0) * FPS) + 1
    pose_frame(STILL_FRAME)
    if STILL == "warn":
        mix = lt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        sep = lt.nodes.new("ShaderNodeSeparateXYZ")
        ramp = lt.nodes.new("ShaderNodeMapRange")
        lt.links.new(l_coord.outputs["Object"], sep.inputs[0])
        lt.links.new(sep.outputs["X"], ramp.inputs["Value"])
        ramp.inputs["From Min"].default_value = -0.9
        ramp.inputs["From Max"].default_value = 0.9
        mix.inputs["A"].default_value = (*gd_kit._linear("#FFB547"), 1)
        mix.inputs["B"].default_value = (*gd_kit._linear("#FF6B5E"), 1)
        lt.links.new(ramp.outputs[0], mix.inputs["Factor"])
        for link_ in list(lt.links):
            if link_.to_socket == l_emit.inputs["Color"]:
                lt.links.remove(link_)
        lt.links.new(mix.outputs["Result"], l_emit.inputs["Color"])
    scene.frame_set(STILL_FRAME)
    os.makedirs(os.path.join(OUT, "stills"), exist_ok=True)
    scene.render.filepath = os.path.join(OUT, "stills", "ring-%s" % ("green" if STILL == "green" else "warn"))
    bpy.ops.render.render(write_still=True)
    print("LAYER still %s rendered=1 skipped=0" % STILL, flush=True)
    sys.exit(0)

for frame in range(1, FRAMES + 1):
    pose_frame(frame)

for obj, p, speed, sway in DUST:
    for frame in list(range(1, FRAMES + 1, 30)) + [FRAMES]:
        t = (frame - 1) / FPS
        obj.location = (p[0] + 0.3 * math.sin(t * 0.4 + p[1]), p[1], p[2] + speed * t)
        obj.keyframe_insert("location", frame=frame)

# ---------------------------------------------------------------- render


def render_all():
    preview = gd_kit.args().preview
    if preview:
        frames = [int(t * FPS) + 1 for t in (1.5, EV["fillStart"] + 1.3, EV["threadStart"] + 0.6, SC["verdict"][0] + 3.0, SC["tension"][0] + 3.0, SC["cta"][1] - 0.5)]
        folder = os.path.join(OUT, "preview", "ring")
    else:
        lo, hi = 1, FRAMES
        spec = os.environ.get("RING_FRAMES")
        if spec:
            lo, hi = (int(x) for x in spec.split("-"))
        frames = list(range(lo, hi + 1))
        folder = os.path.join(OUT, "ring")
    os.makedirs(folder, exist_ok=True)
    done = skipped = 0
    started = time.time()
    for frame in frames:
        target = os.path.join(folder, "f_%04d" % frame)
        if not preview and os.path.exists(target + ".jpg"):
            skipped += 1
            continue
        scene.frame_set(frame)
        scene.render.filepath = target
        begun = time.time()
        bpy.ops.render.render(write_still=True)
        if not os.path.exists(target + ".jpg"):
            raise RuntimeError("the render wrote no file: " + target)
        done += 1
        print("FRAME ring %d %.2fs" % (frame, time.time() - begun), flush=True)
    print("LAYER ring rendered=%d skipped=%d seconds=%.1f" % (done, skipped, time.time() - started), flush=True)


render_all()
