# Original civilian traffic hatchback

Self-contained original SCÈNE112 compact five-door hatchback, without a real brand or external model. The curved longitudinal body/roof, actual wheel clearances, doors/seams/flush pulls, framed glazing, mirror supports/housings, seats/dashboard/steering wheel/parcel shelf, flush light clusters/indicators, rear inserts, wipers, short antenna and fictional yellow `NK-026` plates are authored in `build_hatchback.py`. The same folder's `assetkit.py` authors all PBR maps and exports the embedded-image GLBs. No service-vehicle mesh was serialized or copied into this body.

Runtime paths:

- `assets/models/traffic/civilian_hatchback.glb` —17,084 triangles.
- `assets/models/traffic/civilian_hatchback_lod.glb` —11,468 triangles; genuinely fewer profile/bevel/tube/sphere/cylinder segments.
- `assets/textures/traffic` —nine original512² PNGs (three opaque materials × albedo/roughness/normal).
- `source/3d/traffic` —builder/helper, both packed .blend files and `.gdignore`.

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python /absolute/repository/source/3d/traffic/build_hatchback.py
```

Requires Blender4.3.2/glTF addon and NumPy. All paths resolve from `__file__.parents[3]`, so CWD is arbitrary. The builder regenerates both meshes/maps/manifests; default builds perform zero renders. Optional `-- --preview` writes under ignored source/previews. Every .blend packs all nine512px images and uses final-layout relative paths; both were reopened/exported from a texture-free relocation, reproducing each accepted GLB byte-for-byte. Native builds need no Blender, and `.gdignore` prevents source import attempts.

The full independent builder was also run in a fresh normalized layout: scene/material/image/vertex/normal/UV/color data match exactly and oriented triangle sets/winding are equal. Blender can rotate the cyclic order of triangle indices; **byte-identical full source generation is not claimed**. The explicit LOD avoids the discarded prototype's automatic decimation tie decisions. Manifests retain accepted runtime hashes plus the source-rebuild comparison.

Each file uses four shared materials: bluegray paint, rubber/polymer, alloy/lenses, automotive glass. Authored vertex tints carry red/amber optics and yellow plates on the shared opaque PBR surface. Export explicitly requests `export_vertex_color='ACTIVE'`, keeping the standard glTF `COLOR_0` on every primitive; inactive extra color channels must not substitute for it. Only glass has alpha blending (.22); other surfaces remain opaque. Default Godot4.7.2 imports the glazing as ALPHA_DEPTH_PRE_PASS, which is a valid transparent mode. Actual native-import tests verify colors/maps/transparency, not merely that a color attribute exists.

Metre scale, front-Z/up+Y, wheel bottoms atY0. Envelope including mirrors/plates/antenna:2.01×1.682×3.723m; body width≈1.72m. Five meshes: body plus four wheels, each wheel behind a real centered empty named `Wheel_LF`, `Wheel_RF`, `Wheel_LR`, `Wheel_RR`. Spin localX and steer front roots localY. Radius.315m, half-track.755m, front axleZ−1.09/rear axleZ+1.12. LOD nodes/positions are identical and dimensions differ by under.3mm vertically. No lights/cameras/physics/driver logic/colliders are exported.

Original project-private/proprietary source under `docs/LICENSES.md`; no bought/downloaded asset content, trademarks or real registration identity is claimed. Integrated reactive traffic, target-GPU/frame-rate behavior and native platform quality remain root gameplay/QA ownership.
