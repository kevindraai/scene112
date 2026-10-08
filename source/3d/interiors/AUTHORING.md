# Original training interiors source

Runtime: `assets/models/interiors/training_interiors.glb`. Editable source: `source/3d/interiors/training_interiors.blend`; builder `build_interiors.py` with the isolated local `assetkit.py`. Maps: `assets/textures/interiors`.

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python /absolute/repository/source/3d/interiors/build_interiors.py
```

Requires Blender4.3.2/glTF addon and NumPy. Paths resolve from `__file__`, independent of current directory or other asset families. Default builds perform zero renders; optional `-- --preview` remains under ignored `source/3d/interiors/previews`. The packed .blend retains all12 original512px PBR maps with final-layout relative paths and works from a texture-free relocated directory. `.gdignore` excludes authoring files from Godot imports. Native builds use the embedded-image GLB without Blender; do not copy .blend1/cache files.

The GLB contains four independent prop roots: `TrainingLocker`, `RadioDesk`, `BureauChair`, `EvidenceBench`, each with one consolidated mesh. Total28,620 triangles/four shared PBR materials (powder coating, brushed steel, laminated oak, upholstery/polymer), all with original albedo/normal/roughness maps. Feet Y≈0/front-Z/metre scale. Reset a chosen prop's showroom root X offset to0 when extracting it; retain its mesh child's local transform. No collision/light/camera/script/interactive state is exported. Root's station/controller keeps all gameplay and physics ownership.

Bounds including open locker leaf/task lamps: locker1.255×2.173×1.120m, desk1.8×1.239×.85m, chair.654×1.005×.687m, bench1.58×1.425×.74m. The modeled radio/phone/scanner/storage are decor; they never complete interactions by themselves.

Handoff runtime GLB bytes are the accepted asset, SHA256 `b8368afe6442fce0d6f0a70dfc92451194505d9aeb9b658daa93b7ce391307a4`. The real source rebuild preserves JSON/materials/images/positions/UV and equivalent oriented triangle sets; Blender's cyclic triangle ordering can differ. No geometry/material edits or byte-identical rebuild claim accompanies path normalization. Both hashes/audit are in the manifest.

Original private/proprietary SCÈNE112 content under `docs/LICENSES.md`. No third-party models/textures, purchased samples or official marks. Integrated/native visual acceptance remains root QA.
