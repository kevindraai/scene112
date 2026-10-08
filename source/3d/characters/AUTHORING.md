# Original SCÈNE 112 adults — M5 refinement

`build_characters.py`, local `assetkit.py` and `character_polish.py` author original adult geometry, clothing, faces, 512px PBR maps and the Scene112 eighteen-bone rig. No purchased kit, downloaded scan, likeness or official crest. Private/proprietary project content under `docs/LICENSES.md`.

The refinement broadens shoulders/torso, overlaps neck/garment joins, shortens the long facial mass, replaces intersecting hair strips with a fitted scalp, and adds clothing volume at vest, pockets, elbows and knees. Skin warmth and cloth variation use editable vertex color. Fabric/hair no longer inherit the vehicle helper's clearcoat. Removing oversampled tiny details offsets new useful forms: officer 29,198 triangles (formerly 39,896), civilian 24,862 (formerly 35,780). Godot's existing importer continues to generate mesh LODs.

Run Blender 4.3.2 with its standard glTF addon and NumPy:

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python /absolute/repository/source/3d/characters/build_characters.py
```

Paths resolve from `__file__`; the local helper replaces the former vehicle-helper dependency. Default rebuilding performs no renders. It exports GLBs, manifests, PNG maps and packed editable `.blend` sources. Optional `-- --preview` writes internal authoring previews only. Each `.blend` embeds 15 maps with relative fallback paths; GLBs independently embed used images. Retain `source/3d/.gdignore`. Native players need no Blender/Python/NumPy.

One skinned mesh per adult, 18 original named bones/hierarchy/rest transforms/inverse binds. All four original clips and every channel/keyframe are preserved: idle 3s, walk 1.6s, run 0.8s, carry 1.6s. Metres, feet at Godot Y≈0, front -Z. Assets have no lights, cameras, collision or behavior. Player/NPC gameplay roots remain unchanged.

The editable `AuthoredMaterialVariation` layer is explicitly exported as single active `COLOR_0`. Constant material colors are folded into it; textured colors multiply their existing albedo map. Values must remain within 0..1: Blender 4.3.2 active-color UNORM export wraps values above one to dark values. Do not revert to implicit material-selected colors, which can emit fake white `COLOR_0` before intended `COLOR_1`.

Validation compares rig/animations to accepted GLBs, checks skin weights/512px PBR maps, and re-exports relocated packed sources without image sidecars. Actual Godot before/after captures use identical day-light settings and cameras at 3.5m/5.5m. These isolated checks do not claim full integrated/native acceptance or showreel quality.
