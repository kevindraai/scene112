"""Authored Dutch terrace, streetscape and furniture source for Blender 4.3+.

Run blender --background --factory-startup --python author_street_models.py.
The stored .blend is editable production source; exported GLBs are runtime assets.
"""

from __future__ import annotations
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/models/house24"
EDITABLE = ROOT / "source/3d/house24"
TEXTURES = ROOT / "assets/textures/house24"


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

