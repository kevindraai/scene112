"""Original SCENE112 Blender authoring helpers, deterministic PBR maps and previews.

No downloaded assets: geometry, texture fields and artwork are authored here.
Blender 4.3.2 / standard glTF metal-roughness; +Y is vehicle/character forward.
"""
from pathlib import Path
import math
import json
import hashlib
import sys
import bpy
import numpy as np
from mathutils import Vector


def clean():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in [bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images, bpy.data.actions, bpy.data.armatures]:
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)
    bpy.context.scene.unit_settings.system = 'METRIC'


def parent(obj, root):
    matrix = obj.matrix_world.copy()
    obj.parent = root
    obj.matrix_world = matrix
    return obj


def material(name, color, roughness=0.45, metallic=0.0, texture_dir=None, kind='paint', alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, alpha)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Alpha'].default_value = alpha
    if kind == 'paint':
        shader.inputs['Coat Weight'].default_value = 0.5
        shader.inputs['Coat Roughness'].default_value = 0.18
    if alpha < 1:
        mat.surface_render_method = 'DITHERED'
    if texture_dir:
        texture_dir = Path(texture_dir)
        texture_dir.mkdir(parents=True, exist_ok=True)
        n = 512
        x, y = np.meshgrid(np.arange(n), np.arange(n))
        rng = np.random.default_rng(sum(ord(c) for c in name) + 112)
        noise = rng.random((n, n)).astype(np.float32) - 0.5
        if kind in ['fabric', 'rubber']:
            field = np.sin(x * math.pi / 2) * np.sin(y * math.pi / 2) * 0.65 + noise * 0.25
        elif kind == 'wood':
            field = np.sin(y * .045 + np.sin(x * .012) * 7) * .65 + np.sin(y * .31 + np.sin(x * .027) * 2.4) * .16 + noise * .08
        elif kind == 'skin':
            field = noise * 0.15 + np.sin(x * 0.21 + np.cos(y * 0.13)) * 0.1
        else:
            field = noise * 0.12 + np.sin(x * 0.05) * np.cos(y * 0.04) * 0.08
        dx, dy = np.gradient(field)
        normal = np.dstack((-dx * 0.14, -dy * 0.14, np.ones_like(field)))
        normal /= np.linalg.norm(normal, axis=2, keepdims=True)
        maps = {'albedo': np.clip(np.array(color)[None, None, :] * (1 + field[:, :, None] * (0.22 if kind == 'wood' else 0.04)), 0, 1),
                'roughness': np.repeat(np.clip(roughness + field * 0.08, 0.03, 1)[:, :, None], 3, axis=2),
                'normal': normal * 0.5 + 0.5}
        for suffix, values in maps.items():
            img = bpy.data.images.new(name + '_' + suffix, width=n, height=n, alpha=True)
            if suffix != 'albedo': img.colorspace_settings.name = 'Non-Color'
            rgba = np.ones((n, n, 4), dtype=np.float32)
            rgba[:, :, :3] = values
            img.pixels.foreach_set(rgba.ravel())
            img.filepath_raw = str(texture_dir / (name + '_' + suffix + '.png'))
            img.file_format = 'PNG'
            img.save()
            node = mat.node_tree.nodes.new('ShaderNodeTexImage')
            node.image = img
            if suffix == 'albedo': mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
            elif suffix == 'roughness': mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Roughness'])
            else:
                conversion = mat.node_tree.nodes.new('ShaderNodeNormalMap')
                conversion.inputs['Strength'].default_value = 0.55
                mat.node_tree.links.new(node.outputs['Color'], conversion.inputs['Color'])
                mat.node_tree.links.new(conversion.outputs['Normal'], shader.inputs['Normal'])
    return mat


def assign(obj, mat, smooth=True):
    obj.data.materials.append(mat)
    if obj.type == 'MESH':
        for face in obj.data.polygons: face.use_smooth = smooth
    return obj


def apply(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def bevel(obj, amount=0.02, segments=3):
    mod = obj.modifiers.new('Authored edge radii', 'BEVEL')
    mod.width = amount
    mod.segments = segments
    apply(obj, mod)
    mod = obj.modifiers.new('Surface normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    apply(obj, mod)
    return obj


def uv(obj):
    if obj.type != 'MESH': return
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.025)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def box(name, at, size, mat, root, radius=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if radius: bevel(obj, radius)
    uv(obj)
    return parent(obj, root)


def cylinder(name, at, radius, depth, mat, root, axis=(0, 0, 1), vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    assign(obj, mat)
    bevel(obj, min(radius * 0.1, 0.016), 2)
    uv(obj)
    return parent(obj, root)


def sphere(name, at, size, mat, root, segments=32, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    return parent(obj, root)


def mesh(name, vertices, faces, mat, root, radius=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    assign(obj, mat)
    if radius: bevel(obj, radius)
    uv(obj)
    return parent(obj, root)


def tube(name, points, radius, mat, root):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions = '3D'
    data.resolution_u = 12
    data.bevel_depth = radius
    data.bevel_resolution = 3
    spline = data.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for point, coord in zip(spline.points, points): point.co = (*coord, 1)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    obj.select_set(False)
    uv(obj)
    return parent(obj, root)


def label(name, text, at, scale, mat, root, rotation=(math.pi / 2, 0, 0)):
    data = bpy.data.curves.new(name, 'FONT')
    data.body = text
    data.align_x = 'CENTER'
    data.size = scale
    data.extrude = 0.0008
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    obj.rotation_euler = rotation
    data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    obj.select_set(False)
    return parent(obj, root)


def empty(name, at=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    bpy.context.view_layer.update()
    return obj


def studio(radius, height):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.22, 0.28, 0.33, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.5
    floor = material('Preview_floor', (0.10, 0.14, 0.15), roughness=0.7)
    box('Preview_floor', (0, 0, -0.06), (40, 40, 0.1), floor, empty('Preview_only'), radius=0)
    for name, pos, watts, size in [('Key', (4, 3, 7), 1800, 5), ('Fill', (-4, 1, 4), 900, 4), ('Rim', (0, -4, 6), 1500, 3)]:
        data = bpy.data.lights.new('Preview_' + name, 'AREA')
        data.energy = watts
        data.shape = 'DISK'
        data.size = size
        obj = bpy.data.objects.new(data.name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (Vector((0, 0, height * 0.6)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.object.camera_add(location=(radius * 0.95, radius * 1.15, height * 0.75 + radius * 0.4))
    camera = bpy.context.object
    camera.name = 'Preview_camera'
    camera.rotation_euler = (Vector((0, 0, height * 0.5)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.lens = 52
    scene.camera = camera


def finish(root, folder, name, radius, height, render=False):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    studio(radius, height)
    bpy.ops.object.select_all(action='DESELECT')
    objects = [root] + list(root.children_recursive)
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(folder / (name + '.glb')), export_format='GLB',
        use_selection=True, export_cameras=False, export_lights=False, export_animations=True,
        export_animation_mode='ACTIONS', export_nla_strips=True, export_skins=True, export_yup=True)
    repo_root = Path(__file__).resolve().parents[3]
    source_folder = repo_root / 'source/3d/interiors'
    source_folder.mkdir(parents=True, exist_ok=True)
    for image in bpy.data.images:
        if image.filepath:
            image.pack()
            image.filepath = bpy.path.relpath(image.filepath, start=str(source_folder))
    bpy.ops.wm.save_as_mainfile(filepath=str(source_folder / (name + '.blend')))
    scene = bpy.context.scene
    if render or '--preview' in sys.argv:
        preview_folder = source_folder / 'previews'
        preview_folder.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(preview_folder / (name + '_authoring_preview.png'))
        bpy.ops.render.render(write_still=True)
    meshes = [obj for obj in objects if obj.type == 'MESH']
    stats = {'asset': name, 'author': 'SCENE112 original authoring', 'blender': bpy.app.version_string,
             'meshes': len(meshes), 'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
             'animations': [a.name for a in bpy.data.actions], 'coordinate_convention': 'Blender +Y forward, +Z up; glTF/Godot -Z forward, +Y up',
             'license': 'SCENE112 original private/proprietary project content; docs/LICENSES.md',
             'source_blend': str((source_folder / (name + '.blend')).relative_to(repo_root)),
             'source_builder': 'source/3d/interiors/build_interiors.py',
             'source_helper': 'source/3d/interiors/assetkit.py',
             'texture_directory': 'assets/textures/interiors',
             'runtime_glb': str((folder / (name + '.glb')).relative_to(repo_root)),
             'glb_sha256': hashlib.sha256((folder / (name + '.glb')).read_bytes()).hexdigest(),
             'packed_editable_images': True, 'preview_rendered': bool(render or '--preview' in sys.argv)}
    (folder / (name + '_manifest.json')).write_text(json.dumps(stats, indent=2))
    print('SCENE112_ASSET_OK', json.dumps(stats), flush=True)
