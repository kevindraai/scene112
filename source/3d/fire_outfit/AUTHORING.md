# Original fire officer source — M5 refinement

Runtime: `assets/models/characters/fire_officer.glb`. Packed source: `source/3d/fire_outfit/fire_officer.blend`; builder `build_fire_officer.py`, geometry/rig builder `character_base.py`, local `assetkit.py`. Shared original refinement: `../characters/character_polish.py`; include it when rebuilding. Maps: `assets/textures/fire_outfit`.

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python /absolute/repository/source/3d/fire_outfit/build_fire_officer.py
```

Requires Blender 4.3.2/glTF addon and NumPy. Paths resolve from `__file__`; default builds perform zero renders. Optional `-- --preview` creates authoring previews only. `.gdignore` keeps Blender out of native Godot requirements. The `.blend` packs all 36 original 512px maps and can re-export from a relocated directory without sidecars; GLB embeds its 30 used maps. Do not distribute `.blend1` or Python caches.

One skinned mesh, 35,410 triangles (formerly 48,028), 18 original bones with exactly preserved rest transforms/inverse binds. Original idle 3s, walk 1.6s, run 0.8s and carry 1.6s channels/keyframes unchanged. Feet Y≈0/front -Z. Existing Godot importer generates LODs; runtime adapter selects/loops clips.

Existing helmet/visor/face seal/regulator/gloves/tan coat/trousers/bands/SCBA/harness remain articulated on the same rig. Refinement improves torso/neck overlap, adult head proportions and garment volume, adds knee/glove reinforcement, and uses bounded editable skin/fabric vertex tint. Helmet/mask follow the same head refinement. No extra skeleton, collision, behavior, light or camera.

`AuthoredMaterialVariation` must export as single active `COLOR_0`, bounded to 0..1 to avoid Blender UNORM overflow. See shared character authoring document. Packed-source relocation/re-export and Godot before/after captures validate source/asset interfaces; integrated/native acceptance is separate.

Fictional PPE visuals without brand/certification/performance claims. Original SCÈNE112 private/proprietary project content under `docs/LICENSES.md`; no downloaded/purchased content.
