"""A made-up film frame for the README's SDR/HDR illustration, built from scratch and rendered
by Cycles to scene-linear OpenEXR (real highlight values: sun, neon, engines, city lights).

Usage: Blender -b --factory-startup -P hdr_scene.py -- <out.exr> <width> <height> <samples>
grade_illustration.py turns the EXR into the SDR and HDR renditions.
"""
import math
import random
import sys

import bpy
from mathutils import Vector

out, W, H, SAMPLES = sys.argv[sys.argv.index("--") + 1:][:4]
W, H, SAMPLES = int(W), int(H), int(SAMPLES)
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def material(name, base=(0.02, 0.02, 0.02), rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def node(m, kind, **props):
    n = m.node_tree.nodes.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def box(name, loc, size, mat):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    o.data.materials.append(mat)
    return o


# ---------------------------------------------------------------- sky: dusk gradient, sun, stars
SUN_AZ, SUN_EL = math.radians(0.0), math.radians(1.6)
sun_dir = Vector((math.sin(SUN_AZ) * math.cos(SUN_EL), math.cos(SUN_AZ) * math.cos(SUN_EL), math.sin(SUN_EL)))

world = bpy.data.worlds.new("dusk")
scene.world = world
world.use_nodes = True
try:
    world.cycles.sample_map_resolution = 4096  # the sun disc is tiny and very bright
except AttributeError:
    pass
nt = world.node_tree
nt.nodes.clear()
tc = nt.nodes.new("ShaderNodeTexCoord")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(tc.outputs["Generated"], sep.inputs[0])
ramp = nt.nodes.new("ShaderNodeValToRGB")
mr = nt.nodes.new("ShaderNodeMapRange")
mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = -0.05, 0.6
nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
cr = ramp.color_ramp
cr.elements[0].position, cr.elements[0].color = 0.0, (0.85, 0.28, 0.07, 1)
cr.elements[1].position, cr.elements[1].color = 1.0, (0.002, 0.004, 0.016, 1)
for pos, col in ((0.08, (0.62, 0.12, 0.10, 1)), (0.2, (0.16, 0.035, 0.12, 1)), (0.42, (0.015, 0.015, 0.05, 1))):
    e = cr.elements.new(pos)
    e.color = col
dot = nt.nodes.new("ShaderNodeVectorMath")
dot.operation = "DOT_PRODUCT"
dot.inputs[1].default_value = sun_dir
nt.links.new(tc.outputs["Generated"], dot.inputs[0])
clamp = nt.nodes.new("ShaderNodeMath"); clamp.operation = "MAXIMUM"; clamp.inputs[1].default_value = 0.0
nt.links.new(dot.outputs["Value"], clamp.inputs[0])
disc = nt.nodes.new("ShaderNodeMath"); disc.operation = "GREATER_THAN"; disc.inputs[1].default_value = math.cos(math.radians(0.75))
nt.links.new(clamp.outputs[0], disc.inputs[0])
halo = nt.nodes.new("ShaderNodeMath"); halo.operation = "POWER"; halo.inputs[1].default_value = 900.0
nt.links.new(clamp.outputs[0], halo.inputs[0])
wide = nt.nodes.new("ShaderNodeMath"); wide.operation = "POWER"; wide.inputs[1].default_value = 40.0
nt.links.new(clamp.outputs[0], wide.inputs[0])
sun_amt = nt.nodes.new("ShaderNodeMath"); sun_amt.operation = "MULTIPLY_ADD"
sun_amt.inputs[1].default_value = 400.0
nt.links.new(disc.outputs[0], sun_amt.inputs[0])
halo_amt = nt.nodes.new("ShaderNodeMath"); halo_amt.operation = "MULTIPLY_ADD"
halo_amt.inputs[1].default_value = 9.0
nt.links.new(halo.outputs[0], halo_amt.inputs[0])
wide_amt = nt.nodes.new("ShaderNodeMath"); wide_amt.operation = "MULTIPLY"; wide_amt.inputs[1].default_value = 0.6
nt.links.new(wide.outputs[0], wide_amt.inputs[0])
nt.links.new(wide_amt.outputs[0], halo_amt.inputs[2])
nt.links.new(halo_amt.outputs[0], sun_amt.inputs[2])
sun_col = nt.nodes.new("ShaderNodeVectorMath"); sun_col.operation = "ADD"
nt.links.new(ramp.outputs["Color"], sun_col.inputs[0])
warm = nt.nodes.new("ShaderNodeVectorMath"); warm.operation = "SCALE"
warm.inputs[0].default_value = (1.0, 0.72, 0.42)
nt.links.new(sun_amt.outputs[0], warm.inputs["Scale"])
nt.links.new(warm.outputs["Vector"], sun_col.inputs[1])
# stars: sparse bright points high in the sky
st = nt.nodes.new("ShaderNodeTexWhiteNoise"); st.noise_dimensions = "3D"
scale = nt.nodes.new("ShaderNodeVectorMath"); scale.operation = "SCALE"; scale.inputs["Scale"].default_value = 900.0
nt.links.new(tc.outputs["Generated"], scale.inputs[0])
snap = nt.nodes.new("ShaderNodeVectorMath"); snap.operation = "SNAP"; snap.inputs[1].default_value = (1, 1, 1)
nt.links.new(scale.outputs[0], snap.inputs[0])
nt.links.new(snap.outputs[0], st.inputs["Vector"])
star = nt.nodes.new("ShaderNodeMath"); star.operation = "GREATER_THAN"; star.inputs[1].default_value = 0.9985
nt.links.new(st.outputs["Value"], star.inputs[0])
high = nt.nodes.new("ShaderNodeMapRange")
high.inputs["From Min"].default_value, high.inputs["From Max"].default_value = 0.12, 0.35
high.inputs["To Min"].default_value, high.inputs["To Max"].default_value = 0.0, 6.0
nt.links.new(sep.outputs["Z"], high.inputs["Value"])
starv = nt.nodes.new("ShaderNodeMath"); starv.operation = "MULTIPLY"
nt.links.new(star.outputs[0], starv.inputs[0]); nt.links.new(high.outputs["Result"], starv.inputs[1])
sky = nt.nodes.new("ShaderNodeVectorMath"); sky.operation = "ADD"
nt.links.new(sun_col.outputs["Vector"], sky.inputs[0])
nt.links.new(starv.outputs[0], sky.inputs[1])
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.0
nt.links.new(sky.outputs["Vector"], bg.inputs["Color"])
wout = nt.nodes.new("ShaderNodeOutputWorld")
nt.links.new(bg.outputs[0], wout.inputs["Surface"])

# a real sun for the light it casts (backlight on the skyline, rim on the planet)
bpy.ops.object.light_add(type="SUN")
sun = bpy.context.object
sun.data.energy = 4.0
sun.data.color = (1.0, 0.62, 0.36)
sun.data.angle = math.radians(1.5)
sun.rotation_euler = (-sun_dir).to_track_quat("-Z", "Y").to_euler()

# ---------------------------------------------------------------- wet ground with puddles
bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 1500, 0))
ground = bpy.context.object
gm = material("wet", base=(0.010, 0.011, 0.014), rough=0.08)
noise = node(gm, "ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 0.06
gpos = node(gm, "ShaderNodeNewGeometry")
gm.node_tree.links.new(gpos.outputs["Position"], noise.inputs["Vector"])
noise.inputs["Detail"].default_value = 6.0
gr = node(gm, "ShaderNodeMapRange")
gr.inputs["From Min"].default_value, gr.inputs["From Max"].default_value = 0.45, 0.62
gr.inputs["To Min"].default_value, gr.inputs["To Max"].default_value = 0.015, 0.2
gm.node_tree.links.new(noise.outputs["Fac"], gr.inputs["Value"])
gm.node_tree.links.new(gr.outputs["Result"], gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"])
ground.data.materials.append(gm)

# ---------------------------------------------------------------- skyline with lit windows
def window_material(name, warmth):
    m = material(name, base=(0.012, 0.012, 0.016), rough=0.6)
    t = m.node_tree
    geo = node(m, "ShaderNodeNewGeometry")
    xyz = node(m, "ShaderNodeSeparateXYZ")
    t.links.new(geo.outputs["Position"], xyz.inputs[0])
    facade = node(m, "ShaderNodeMath", operation="ADD")
    t.links.new(xyz.outputs["X"], facade.inputs[0]); t.links.new(xyz.outputs["Y"], facade.inputs[1])
    comb = node(m, "ShaderNodeCombineXYZ")
    sx = node(m, "ShaderNodeMath", operation="MULTIPLY"); sx.inputs[1].default_value = 0.5
    sz = node(m, "ShaderNodeMath", operation="MULTIPLY"); sz.inputs[1].default_value = 0.42
    t.links.new(facade.outputs[0], sx.inputs[0]); t.links.new(xyz.outputs["Z"], sz.inputs[0])
    t.links.new(sx.outputs[0], comb.inputs["X"]); t.links.new(sz.outputs[0], comb.inputs["Y"])
    cell = node(m, "ShaderNodeVectorMath", operation="FLOOR")
    frac = node(m, "ShaderNodeVectorMath", operation="FRACTION")
    t.links.new(comb.outputs[0], cell.inputs[0]); t.links.new(comb.outputs[0], frac.inputs[0])
    rnd = node(m, "ShaderNodeTexWhiteNoise", noise_dimensions="3D")
    t.links.new(cell.outputs[0], rnd.inputs["Vector"])
    lit = node(m, "ShaderNodeMath", operation="GREATER_THAN"); lit.inputs[1].default_value = 0.62
    t.links.new(rnd.outputs["Value"], lit.inputs[0])
    fsep = node(m, "ShaderNodeSeparateXYZ")
    t.links.new(frac.outputs[0], fsep.inputs[0])
    fx = node(m, "ShaderNodeMath", operation="LESS_THAN"); fx.inputs[1].default_value = 0.7
    fz = node(m, "ShaderNodeMath", operation="LESS_THAN"); fz.inputs[1].default_value = 0.62
    t.links.new(fsep.outputs["X"], fx.inputs[0]); t.links.new(fsep.outputs["Y"], fz.inputs[0])
    pane = node(m, "ShaderNodeMath", operation="MULTIPLY")
    t.links.new(fx.outputs[0], pane.inputs[0]); t.links.new(fz.outputs[0], pane.inputs[1])
    on = node(m, "ShaderNodeMath", operation="MULTIPLY")
    t.links.new(pane.outputs[0], on.inputs[0]); t.links.new(lit.outputs[0], on.inputs[1])
    level = node(m, "ShaderNodeMath", operation="MULTIPLY_ADD")
    level.inputs[1].default_value = 3.0
    level.inputs[2].default_value = 0.0
    bright = node(m, "ShaderNodeMath", operation="MULTIPLY")
    t.links.new(rnd.outputs["Color"], level.inputs[0])
    t.links.new(level.outputs[0], bright.inputs[0]); t.links.new(on.outputs[0], bright.inputs[1])
    bsdf = t.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = warmth
    t.links.new(bright.outputs[0], bsdf.inputs["Emission Strength"])
    return m


win_warm = window_material("windows-warm", (1.0, 0.62, 0.30, 1))
win_cool = window_material("windows-cool", (0.55, 0.80, 1.0, 1))
for i in range(150):
    x = random.uniform(-420, 420)
    y = random.uniform(260, 700)
    if abs(x) < 60:
        continue  # keep the sunset and its reflection open in the middle
    w, d = random.uniform(10, 30), random.uniform(10, 30)
    h = random.uniform(25, 120) * (1.4 if abs(x) > 200 else 1.0)
    box(f"tower{i}", (x, y, h / 2), (w, d, h), win_warm if random.random() < 0.7 else win_cool)

# ---------------------------------------------------------------- red aircraft lights on the tallest towers
red = material("aircraft-red", base=(0, 0, 0), emit=(1.0, 0.05, 0.03), strength=150)
for o in [o for o in scene.objects if o.name.startswith("tower") and o.dimensions.z > 85]:
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.8, location=(o.location.x, o.location.y, o.dimensions.z + 0.8))
    bpy.context.object.data.materials.append(red)

# ---------------------------------------------------------------- buildings framing the plaza, with neon
dark = material("facade", base=(0.015, 0.014, 0.016), rough=0.45)
neon = {
    "magenta": material("neon-magenta", base=(0, 0, 0), emit=(1.0, 0.08, 0.55), strength=60),
    "cyan": material("neon-cyan", base=(0, 0, 0), emit=(0.10, 0.85, 1.0), strength=55),
    "amber": material("neon-amber", base=(0, 0, 0), emit=(1.0, 0.55, 0.08), strength=50),
    "white": material("led-white", base=(0, 0, 0), emit=(1.0, 0.97, 0.92), strength=45),
}
for side, x_face, cols in ((-1, -40.0, ("magenta", "cyan", "amber")), (1, 42.0, ("cyan", "amber", "magenta"))):
    box(f"edge{side}", (x_face + side * 8, 100, 29), (16, 40, 58), win_warm if side < 0 else win_cool)
    bx = x_face - side * 1.8  # a blade sign standing out over the plaza
    box(f"blade{side}", (bx, 86, 16), (2.8, 0.5, 22), dark)
    for k in range(7):
        box(f"glyph{side}{k}", (bx, 85.7, 7.5 + k * 2.7), (1.7, 0.12, 1.4 if k % 3 else 0.45), neon["white" if k == 3 else cols[k % 3]])
    for e in (-1, 1):
        box(f"outline{side}{e}", (bx + e * 1.4, 85.7, 16), (0.18, 0.18, 22), neon[cols[0]])
    for k in range(4):
        box(f"strip{side}{k}", (x_face - side * 0.15, 100 + (k - 1.5) * 7, 4 + k * 8), (0.2, 5 + k, 0.25), neon[cols[(k + 1) % 3]])

# ---------------------------------------------------------------- a giant ringed planet
bpy.ops.mesh.primitive_uv_sphere_add(radius=160, segments=128, ring_count=64, location=(-260, 1500, 330))
planet = bpy.context.object
bpy.ops.object.shade_smooth()
pm = material("planet", base=(0.55, 0.42, 0.36), rough=0.9)
bands = node(pm, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z")
bands.inputs["Scale"].default_value = 3.0
bands.inputs["Distortion"].default_value = 6.0
bands.inputs["Detail"].default_value = 4.0
pr = node(pm, "ShaderNodeValToRGB")
pr.color_ramp.elements[0].color = (0.32, 0.17, 0.16, 1)
pr.color_ramp.elements[1].color = (0.95, 0.74, 0.55, 1)
pm.node_tree.links.new(bands.outputs["Fac"], pr.inputs["Fac"])
pbsdf = pm.node_tree.nodes["Principled BSDF"]
pm.node_tree.links.new(pr.outputs["Color"], pbsdf.inputs["Base Color"])
pm.node_tree.links.new(pr.outputs["Color"], pbsdf.inputs["Emission Color"])
pbsdf.inputs["Emission Strength"].default_value = 0.55
planet.data.materials.append(pm)
planet.rotation_euler = (math.radians(14), math.radians(-18), 0)

import bmesh
ring_mesh = bpy.data.meshes.new("rings")
bm = bmesh.new()
outer, inner = [], []
for i in range(256):
    a = 2 * math.pi * i / 256
    outer.append(bm.verts.new((400 * math.cos(a), 400 * math.sin(a), 0)))
    inner.append(bm.verts.new((215 * math.cos(a), 215 * math.sin(a), 0)))
for i in range(256):
    j = (i + 1) % 256
    bm.faces.new((inner[i], outer[i], outer[j], inner[j]))
bm.to_mesh(ring_mesh)
bm.free()
ring = bpy.data.objects.new("rings", ring_mesh)
scene.collection.objects.link(ring)
ring.location = planet.location
ring.rotation_euler = (math.radians(13), math.radians(-9), math.radians(-16))
rm = material("rings", base=(0.8, 0.66, 0.5), rough=0.7, emit=(1.0, 0.78, 0.55), strength=0.9)
rt = rm.node_tree
rtc = node(rm, "ShaderNodeTexCoord")
rlen = node(rm, "ShaderNodeVectorMath", operation="LENGTH")
rt.links.new(rtc.outputs["Object"], rlen.inputs[0])
rnoise = node(rm, "ShaderNodeTexNoise")
rnoise.noise_dimensions = "1D"
rnoise.inputs["Scale"].default_value = 0.05
rnoise.inputs["Detail"].default_value = 8.0
rt.links.new(rlen.outputs["Value"], rnoise.inputs["W"])
ra = node(rm, "ShaderNodeMapRange")
ra.inputs["From Min"].default_value, ra.inputs["From Max"].default_value = 0.38, 0.66
rt.links.new(rnoise.outputs["Fac"], ra.inputs["Value"])
rt.links.new(ra.outputs["Result"], rt.nodes["Principled BSDF"].inputs["Alpha"])
ring.data.materials.append(rm)

# ---------------------------------------------------------------- two ships with engine trails
hull = material("hull", base=(0.05, 0.055, 0.06), rough=0.25, metal=0.8)
engine = material("engine", base=(0, 0, 0), emit=(0.55, 0.78, 1.0), strength=240)
trail = material("trail", base=(0, 0, 0), emit=(0.45, 0.7, 1.0), strength=12)
for name, (x, y, z), size, heading in (("ship-a", (52, 240, 50), 1.0, -1), ("ship-b", (-150, 650, 112), 0.7, 1)):
    hullobj = box(name, (x, y, z), (22 * size, 5 * size, 2.6 * size), hull)
    hullobj.rotation_euler = (0, math.radians(-4 * heading), math.radians(-6 * heading))
    box(name + "-wing", (x + 3 * heading * size, y, z - 0.4), (8 * size, 16 * size, 0.6 * size), hull).rotation_euler = hullobj.rotation_euler
    for dy in (-1.6 * size, 1.6 * size):
        ex = x + heading * 11.5 * size
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.1 * size, location=(ex, y + dy, z + 0.4))
        bpy.context.object.data.materials.append(engine)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.2 * size, depth=45 * size, location=(ex + heading * 22.5 * size, y + dy, z + 0.4 + 1.5 * heading * size))
        t = bpy.context.object
        t.rotation_euler = (0, math.radians(90 - 3.8 * heading), 0)
        t.data.materials.append(trail)

# ---------------------------------------------------------------- lamps along the waterfront
lamp = material("lamp", base=(0, 0, 0), emit=(1.0, 0.78, 0.5), strength=90)
post = material("post", base=(0.03, 0.03, 0.035), rough=0.4, metal=0.6)
for side in (-1, 1):
    for k in range(8):
        y = 30 + k * 26
        x = side * (24 + k * 1.5)
        box(f"post{side}{k}", (x, y, 2.2), (0.15, 0.15, 4.4), post)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(x, y, 4.6))
        bpy.context.object.data.materials.append(lamp)

# ---------------------------------------------------------------- thin haze, camera, render
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 450, 70))
haze = bpy.context.object
haze.scale = (1400, 900, 140)
hm = bpy.data.materials.new("haze")
hm.use_nodes = True
hm.node_tree.nodes.clear()
vol = hm.node_tree.nodes.new("ShaderNodeVolumePrincipled")
vol.inputs["Density"].default_value = 0.00015
vol.inputs["Anisotropy"].default_value = 0.6
vol.inputs["Color"].default_value = (1.0, 0.9, 0.85, 1)
mo = hm.node_tree.nodes.new("ShaderNodeOutputMaterial")
hm.node_tree.links.new(vol.outputs[0], mo.inputs["Volume"])
haze.data.materials.append(hm)

bpy.ops.object.camera_add(location=(0, -6, 1.4), rotation=(math.radians(91.8), 0, 0))
cam = bpy.context.object
cam.data.lens = 26
cam.data.clip_end = 20000
cam.data.sensor_width = 36
scene.camera = cam

scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
try:
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for dev in prefs.devices:
        dev.use = True
    scene.cycles.device = "GPU"
except Exception as e:  # CPU still renders, only slower
    print("GPU unavailable:", e)
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 6
scene.cycles.volume_bounces = 1
scene.render.resolution_x, scene.render.resolution_y = W, H
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.render.image_settings.file_format = "OPEN_EXR"
scene.render.image_settings.color_depth = "32"
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("rendered", out)
