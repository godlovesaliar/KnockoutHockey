# Builds assets/zamboni/zamboni.glb from assets/ZAMBONI5.stl ("Zamboni" by marsmodels,
# CC BY, Thingiverse thing:5555849).
#
# Run headless:
#   blender -b --factory-startup -P tools/blender/zamboni.py
#
# The STL is a print kit in millimetres: the machine, its four wheels (each a hub plus a
# ring of tread blocks), and loose extras laid flat beside it (two steering wheels and a
# bar). This keeps the machine, mounts the larger steering wheel in front of the seat,
# drops the rest, and splits out each wheel and the steering wheel as its own object with
# its origin on its axis, so the game can spin and steer them.
#
# Out: Y-up (glTF), metres, front toward -Z in Godot, the ice at y = 0, centred on the
# wheelbase. Objects: Body, WheelFL, WheelFR, WheelRL, WheelRR, Steering. Materials:
# Paint (the machine's body: the game tints it), Trim, Tire, Hub, Seat.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "ZAMBONI5.stl")
OUT = os.path.join(ROOT, "assets", "zamboni", "zamboni.glb")

LENGTH_M = 4.2          # metres, front bumper to the back of the conditioner
DECIMATE = 0.35         # the tread blocks alone are ~75k triangles

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.stl_import(filepath=SRC)
src = bpy.context.selected_objects[0]
bm = bmesh.new()
bm.from_mesh(src.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bm.to_mesh(src.data)
bm.free()
bpy.context.view_layer.objects.active = src
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')


def bounds(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def mat(name, color, rough=0.5, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


PAINT = mat("Paint", (0.92, 0.92, 0.9), 0.35)
TRIM = mat("Trim", (0.16, 0.16, 0.17), 0.6)
TIRE = mat("Tire", (0.05, 0.05, 0.05), 0.85)
HUB = mat("Hub", (0.62, 0.63, 0.65), 0.35, 0.6)
SEAT = mat("Seat", (0.08, 0.08, 0.09), 0.7)

# --- Sort the loose parts --------------------------------------------------------------
body_parts, wheel_parts, extras = [], {}, []
biggest = max(bpy.context.scene.objects, key=lambda o: len(o.data.polygons))
for o in list(bpy.context.scene.objects):
    mn, mx = bounds(o)
    c = (mn + mx) * 0.5
    if o is biggest:
        body_parts.append(o)
    elif mx.y < 90.0:
        extras.append(o)   # the kit's loose extras, laid out beside the machine
    elif c.z < 10 and (100 < c.y < 105 or 118 < c.y < 123) and (76 < c.x < 87 or 102 < c.x < 113):
        key = ("R" if c.x > 95 else "F") + ("L" if c.y < 111 else "R")
        wheel_parts.setdefault(key, []).append(o)
    else:
        body_parts.append(o)

# Keep the larger steering wheel (the widest of the extras); drop the rest.
steering = max(extras, key=lambda o: (bounds(o)[1] - bounds(o)[0]).x)
for o in extras:
    if o is not steering:
        bpy.data.objects.remove(o, do_unlink=True)
print("body parts", len(body_parts), "wheels", {k: len(v) for k, v in wheel_parts.items()}, "steering", steering.name)


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


# --- Body materials, by region (the print has no parts or colors) -----------------------
body = join(body_parts, "Body")
for m in (PAINT, TRIM, TIRE, SEAT):
    body.data.materials.append(m)
bmn, bmx = bounds(body)
for p in body.data.polygons:
    c = p.center
    slot = 0
    if c.x > 118.0 and c.z < 3.5:
        slot = 1      # the conditioner (the board trailing on the ice)
    elif c.z < 2.2:
        slot = 1      # the skirt along the bottom
    elif 119.5 < c.x < 124.5 and c.z > 19.0 and c.y < 113.0:
        slot = 3      # the seat cushion
    elif c.x > 112.5 and c.z < 16.0 and 108 < c.y < 123 and c.x < 119.5:
        slot = 1      # the footwell
    p.material_index = slot

# --- Wheels: one object each, origin on the axle ---------------------------------------
wheels = {}
for key, parts in wheel_parts.items():
    w = join(parts, "Wheel" + key)
    w.data.materials.clear()
    w.data.materials.append(TIRE)
    w.data.materials.append(HUB)
    mn, mx = bounds(w)
    axle = (mn + mx) * 0.5
    r = (mx.z - mn.z) * 0.5
    for p in w.data.polygons:
        d = math.hypot(p.center.x - axle.x, p.center.z - axle.z)
        p.material_index = 1 if d < r * 0.62 else 0
    wheels[key] = (w, axle)

# --- Steering wheel: stood up on its column in front of the seat ------------------------
mn, mx = bounds(steering)
ring_c = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mx.z))
steering.data.materials.clear()
steering.data.materials.append(SEAT)
# The kit lays it flat, rim up, hub stalk down. Tilt the rim toward the seat (+x, the
# driver faces -x) and set it over the footwell.
seat_y = 106.5
mount = Vector((115.6, seat_y, 17.2))
steering.data.transform(Matrix.Translation(-ring_c))
steering.data.transform(Matrix.Rotation(math.radians(52.0), 4, 'Y'))
steering.location = mount
steering.name = "Steering"

# --- Pivots, scale, axes ---------------------------------------------------------------
for key, (w, axle) in wheels.items():
    w.data.transform(Matrix.Translation(-axle))
    w.location = axle
# (The steering wheel's data is centred on its rim already; its location is the mount.)

# Lighter mesh: the tread blocks are dense.
for o in [body] + [w for w, _ in wheels.values()]:
    d = o.modifiers.new("dec", 'DECIMATE')
    d.ratio = DECIMATE
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")

# Centre on the wheelbase, scale to metres, and turn the front (-x, where the driver faces)
# to +y, which glTF makes Godot's -z.
ax = [a for _, a in wheels.values()]
centre = Vector((sum(a.x for a in ax) / 4, sum(a.y for a in ax) / 4, 0.0))
s = LENGTH_M / (bmx.x - bmn.x)
lin = Matrix.Rotation(math.radians(-90.0), 4, 'Z') @ Matrix.Scale(s, 4)
G = lin @ Matrix.Translation(-centre)
body.data.transform(G)
for o in [steering] + [w for w, _ in wheels.values()]:
    o.data.transform(lin)
    o.location = G @ o.location
bpy.context.view_layer.update()
low = min((w.matrix_world @ v.co).z for w, _ in wheels.values() for v in w.data.vertices)
body.data.transform(Matrix.Translation((0, 0, -low)))
for o in [steering] + [w for w, _ in wheels.values()]:
    o.location.z -= low
bpy.context.view_layer.update()
print("faces", sum(len(o.data.polygons) for o in bpy.context.scene.objects))
for o in bpy.context.scene.objects:
    mn, mx = bounds(o)
    print("OBJ", o.name, [round(v, 3) for v in o.location], [round(v, 2) for v in mn], [round(v, 2) for v in mx])

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=False, export_apply=True)
print("wrote", OUT)
