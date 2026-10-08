"""Authored Dutch terrace, streetscape and furniture source for Blender 4.3+.

Run blender --background --factory-startup --python author_street_models.py.
The stored .blend is editable production source; exported GLBs are runtime assets.
"""

from __future__ import annotations
import json
import hashlib
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/street"
EDITABLE = ROOT / "source/3d/street"
TEXTURES = ROOT / "assets/textures/street"


def point(value):
    x, y, z = value
    return (x, -z, y)


def material(name, colour, rough=0.8, metal=0.0, texture=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*colour, 1)
    shader.inputs["Roughness"].default_value = rough
    shader.inputs["Metallic"].default_value = metal
    if texture:
        for suffix, socket in [
            ("albedo", "Base Color"),
            ("roughness", "Roughness"),
            ("normal", "Normal"),
        ]:
            image = bpy.data.images.load(
                str(TEXTURES / f"{texture}_{suffix}.png"), check_existing=True
            )
            if suffix != "albedo":
                image.colorspace_settings.name = "Non-Color"
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = image
            tex.extension = "REPEAT"
            if suffix == "normal":
                normal = nodes.new("ShaderNodeNormalMap")
                normal.inputs["Strength"].default_value = 0.75
                mat.node_tree.links.new(tex.outputs["Color"], normal.inputs["Color"])
                mat.node_tree.links.new(normal.outputs["Normal"], shader.inputs[socket])
            else:
                mat.node_tree.links.new(tex.outputs["Color"], shader.inputs[socket])
    return mat


def unwrap(obj, tile=2):
    if obj.type != "MESH":
        return
    # Primitive operators create a default 0..1 UV layer. Replace it so the
    # material/exporter's primary coordinates use physical surface metres.
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    uv = obj.data.uv_layers.new(name="Surface metres")
    obj.data.uv_layers.active_index = 0
    uv.active_render = True
    for polygon in obj.data.polygons:
        axis = max(range(3), key=lambda i: abs(polygon.normal[i]))
        for loop in polygon.loop_indices:
            co = (
                obj.matrix_world
                @ obj.data.vertices[obj.data.loops[loop].vertex_index].co
            )
            indices = [i for i in range(3) if i != axis]
            uv.data[loop].uv = (co[indices[0]] / tile, co[indices[1]] / tile)


def box(name, at, size, mat, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(at))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("Crafted edge bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    unwrap(obj)
    return obj


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    unwrap(obj)
    return obj


def tube(name, start, end, radius, mat, segments=12):
    a, b = Vector(point(start)), Vector(point(end))
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=segments, radius=radius, depth=(b - a).length, location=(a + b) / 2
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = abs(polygon.normal.z) < 0.99
    unwrap(obj)
    return obj


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def export(name):
    # Join static parts by material: retain crafted geometry with bounded draw calls.
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH":
            groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for label, items in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in items:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = items[0]
        bpy.ops.object.join()
        bpy.context.object.name = label
        triangulate = bpy.context.object.modifiers.new(
            "Runtime triangles", "TRIANGULATE"
        )
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE / f"{name}.blend"))
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        export_format="GLB",
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    triangles = sum(
        len(obj.data.loop_triangles)
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
    )
    print(
        "SCENE112_AUTHORED_GLB",
        name,
        "materials=",
        len(groups),
        "triangles=",
        triangles,
    )
    return {
        "name": name,
        "materials": len(groups),
        "triangles": triangles,
        "source": "tools/art/author_street_models.py",
        "editable": "source/3d/street/" + name + ".blend",
        "runtime": "assets/models/street/" + name + ".glb",
        "author": "SCENE112 original Blender authoring",
        "blender": bpy.app.version_string,
        "glb_sha256": hashlib.sha256((OUT / f"{name}.glb").read_bytes()).hexdigest(),
        "packed_images": True,
        "license": "Original SCÈNE 112 project asset; private/proprietary; no third-party geometry",
    }


def window(x, y, width, height, mats, lit=False):
    z = -3.52
    # Real recessed opening, masonry reveals, deep frame, sill and curtain/interior.
    box("Recess darkness", (x, y, z + 0.23), (width, height, 0.04), mats["dark"], 0)
    for dx in [-width / 2, width / 2]:
        box(
            "Masonry reveal",
            (x + dx, y, z + 0.08),
            (0.12, height + 0.2, 0.32),
            mats["brick"],
        )
        box(
            "Painted frame stile",
            (x + dx, y, z - 0.05),
            (0.095, height + 0.12, 0.13),
            mats["cream"],
        )
    for dy in [-height / 2, height / 2]:
        box(
            "Painted frame rail",
            (x, y + dy, z - 0.05),
            (width + 0.14, 0.09, 0.13),
            mats["cream"],
        )
    box(
        "Glazed panes",
        (x, y, z + 0.025),
        (width - 0.10, height - 0.10, 0.025),
        mats["glass"],
        0,
    )
    box("Window mullion", (x, y, z - 0.04), (0.045, height, 0.11), mats["cream"], 0.005)
    box(
        "Upper transom",
        (x, y + height * 0.24, z - 0.04),
        (width, 0.045, 0.11),
        mats["cream"],
        0.005,
    )
    box(
        "Concrete sill",
        (x, y - height / 2 - 0.09, z - 0.11),
        (width + 0.30, 0.12, 0.35),
        mats["stone"],
    )
    box(
        "Lintel",
        (x, y + height / 2 + 0.11, z - 0.005),
        (width + 0.22, 0.12, 0.20),
        mats["stone"],
    )
    for side in [-1, 1]:
        box(
            "Curtain folds",
            (x + side * width * 0.32, y, z + 0.055),
            (width * 0.25, height - 0.18, 0.035),
            mats["curtain"],
            0.008,
        )


def house(mats):
    reset()
    # The facade is laid around real openings rather than pasted onto a solid box.
    box("Brick plinth", (0, 0.34, 0), (6.8, 0.68, 7), mats["brick"], 0.03)
    box("Rear masonry", (0, 2.96, 3.35), (6.8, 4.64, 0.3), mats["brick"], 0.01)
    for side in [-1, 1]:
        box("Side masonry", (side * 3.25, 2.96, 0), (0.3, 4.64, 7), mats["brick"], 0.01)
    for bottom, top in [(0.68, 1.0), (2.48, 3.24), (4.74, 5.4)]:
        box(
            "Facade masonry course",
            (0, (bottom + top) / 2, -3.35),
            (6.8, top - bottom, 0.3),
            mats["brick"],
            0.01,
        )
    for x, width in [(-2.94, 0.92), (-0.655, 0.45), (0.655, 0.45), (2.94, 0.92)]:
        box(
            "Ground brick pier",
            (x, 1.72, -3.35),
            (width, 1.44, 0.3),
            mats["brick"],
            0.01,
        )
    for x, width in [(-2.94, 0.92), (0, 1.76), (2.94, 0.92)]:
        box(
            "Upper brick pier", (x, 3.99, -3.35), (width, 1.5, 0.3), mats["brick"], 0.01
        )
    for x in [-1.68, 1.68]:
        window(x, 1.74, 1.6, 1.45, mats)
        window(x, 4.0, 1.6, 1.45, mats)
    box("Door alcove", (0, 1.1, -3.35), (0.96, 2.2, 0.10), mats["dark"], 0)
    box("Oak painted door", (0, 1.06, -3.55), (0.86, 2.08, 0.10), mats["navy"], 0.025)
    for y in [0.40, 0.93, 1.5]:
        box(
            "Recessed door panel",
            (0, y, -3.612),
            (0.62, 0.38, 0.024),
            mats["door_inset"],
            0.012,
        )
    for x in [-0.49, 0.49]:
        box("Door casing", (x, 1.13, -3.58), (0.095, 2.26, 0.16), mats["cream"])
    box("Door lintel", (0, 2.25, -3.53), (1.08, 0.11, 0.24), mats["cream"])
    box("Letter slot", (0, 0.84, -3.632), (0.28, 0.065, 0.02), mats["metal"], 0.006)
    tube("Door handle", (0.3, 1.08, -3.64), (0.17, 1.08, -3.64), 0.014, mats["metal"])
    box("Door step", (0, 0.10, -3.68), (1.08, 0.18, 0.50), mats["stone"], 0.025)
    box("Floor and interior", (0, 0.69, 0), (6.2, 0.10, 6.4), mats["wood"])
    # Gables and two pitched, textured clay-tile slopes.
    for z in [-3.36, 3.36]:
        mesh(
            "Gable brickwork",
            [(-3.4, 5.4, z), (3.4, 5.4, z), (0, 7.05, z)],
            [(0, 2, 1) if z < 0 else (0, 1, 2)],
            mats["brick"],
        )
    for side in [-1, 1]:
        mesh(
            "Clay tile roof",
            [
                (0, 7.12, -3.75),
                (0, 7.12, 3.75),
                (side * 3.65, 5.33, 3.75),
                (side * 3.65, 5.33, -3.75),
            ],
            [(0, 1, 2, 3) if side > 0 else (3, 2, 1, 0)],
            mats["roof"],
        )
        tube(
            "Zinc rain gutter",
            (side * 3.65, 5.29, -3.74),
            (side * 3.65, 5.29, 3.74),
            0.055,
            mats["metal"],
        )
        tube(
            "Downpipe",
            (side * 3.31, 5.25, -3.54),
            (side * 3.31, 0.08, -3.54),
            0.036,
            mats["metal"],
        )
    for z in [i * 0.42 - 3.55 for i in range(18)]:
        tube(
            "Individual clay ridge cap",
            (0, 7.12, z),
            (0, 7.12, z + 0.40),
            0.12,
            mats["roof"],
            12,
        )
    box("Chimney brickwork", (2.0, 6.3, 1.8), (0.7, 1.75, 0.8), mats["brick"], 0.025)
    box("Chimney stone crown", (2, 7.20, 1.8), (0.82, 0.12, 0.92), mats["stone"])
    for z in [1.62, 1.99]:
        tube("Ceramic chimney pot", (2, 7.24, z), (2, 7.50, z), 0.11, mats["roof"])
    box("Eaves fascia", (0, 5.38, -3.68), (7.2, 0.16, 0.14), mats["cream"])
    return export("dutch_terrace")


def furniture(mats):
    reset()
    for x in [-0.65, 0.65]:
        box("Bench steel foot", (x, 0.24, 0), (0.075, 0.48, 0.50), mats["navy"], 0.01)
        box(
            "Bench back support",
            (x, 0.64, 0.20),
            (0.055, 0.80, 0.055),
            mats["navy"],
            0.01,
        )
    for z in [-0.19, -0.07, 0.05, 0.17]:
        box("Oak seat slat", (0, 0.49, z), (1.6, 0.045, 0.10), mats["wood"], 0.009)
    for y in [0.71, 0.84, 0.97]:
        box("Oak backrest slat", (0, y, 0.225), (1.6, 0.10, 0.045), mats["wood"], 0.009)
    return export("street_bench")


def lamp(mats):
    reset()
    tube("Cast base", (0, 0, 0), (0, 0.40, 0), 0.105, mats["navy"])
    tube("Tapered street lamp post", (0, 0.32, 0), (0, 4.5, 0), 0.052, mats["metal"])
    tube("Outreach support", (0, 4.49, 0), (0.8, 4.49, 0), 0.035, mats["metal"])
    box("Luminaire housing", (0.71, 4.43, 0), (0.68, 0.13, 0.27), mats["navy"], 0.055)
    box(
        "Luminaire diffuser", (0.73, 4.355, 0), (0.48, 0.025, 0.20), mats["cream"], 0.02
    )
    return export("street_lamp")


def bicycle(mats):
    reset()
    for x in [-0.57, 0.57]:
        # Toroidal wheels, spokes, hub and a recognisable Dutch bicycle silhouette.
        bpy.ops.mesh.primitive_torus_add(
            major_segments=32,
            minor_segments=8,
            location=point((x, 0.34, 0)),
            major_radius=0.315,
            minor_radius=0.022,
            rotation=(math.pi / 2, 0, 0),
        )
        tyre = bpy.context.object
        tyre.name = "Bicycle rubber tyre"
        tyre.data.materials.append(mats["dark"])
        for poly in tyre.data.polygons:
            poly.use_smooth = True
        tube("Wheel hub", (x, 0.34, -0.04), (x, 0.34, 0.04), 0.028, mats["metal"])
        for angle in [i * math.tau / 12 for i in range(12)]:
            tube(
                "Wheel spoke",
                (x, 0.34, 0),
                (x + math.cos(angle) * 0.30, 0.34 + math.sin(angle) * 0.30, 0),
                0.0025,
                mats["metal"],
                6,
            )
    nodes = {
        "rear": (-0.57, 0.34, 0),
        "crank": (-0.03, 0.33, 0),
        "seat": (-0.17, 0.87, 0),
        "head": (0.34, 0.90, 0),
        "front": (0.57, 0.34, 0),
    }
    for a, b in [
        ("rear", "crank"),
        ("rear", "seat"),
        ("crank", "seat"),
        ("seat", "head"),
        ("crank", "head"),
        ("head", "front"),
    ]:
        tube("Bicycle frame tube", nodes[a], nodes[b], 0.025, mats["navy"])
    box("Bicycle saddle", (-0.17, 0.96, 0), (0.25, 0.045, 0.16), mats["dark"], 0.02)
    tube("Handlebar stem", (0.34, 0.90, 0), (0.36, 1.07, 0), 0.017, mats["metal"])
    tube("Handlebar", (0.36, 1.07, -0.22), (0.36, 1.07, 0.22), 0.017, mats["metal"])
    return export("dutch_bicycle")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    EDITABLE.mkdir(parents=True, exist_ok=True)
    bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    mats = {
        "brick": material(
            "Noorderkade red brick PBR", (0.5, 0.2, 0.1), texture="brick"
        ),
        "roof": material("Clay roof tiles PBR", (0.5, 0.2, 0.1), texture="roof"),
        "wood": material("Weathered oak PBR", (0.5, 0.3, 0.1), texture="wood"),
        "cream": material("Painted timber frames", (0.78, 0.75, 0.64), 0.54),
        "stone": material("Cast concrete sills", (0.50, 0.52, 0.48), 0.91),
        "navy": material("Navy powder coating", (0.022, 0.060, 0.085), 0.46, 0.12),
        "door_inset": material("Painted inset panels", (0.013, 0.035, 0.043), 0.60),
        "metal": material("Weathered zinc metal", (0.30, 0.34, 0.35), 0.34, 0.82),
        "dark": material("Recess and rubber", (0.012, 0.016, 0.017), 0.91),
        "glass": material("Window reflection", (0.08, 0.17, 0.21), 0.12, 0.28),
        "curtain": material("Natural linen curtains", (0.53, 0.51, 0.44), 0.98),
    }
    records = [house(mats), furniture(mats), lamp(mats), bicycle(mats)]
    (OUT / "manifest.json").write_text(json.dumps(records, indent=2) + "\n")
    print("SCENE112_STREET_SOURCE_EXPORT_OK")


if __name__ == "__main__":
    main()
