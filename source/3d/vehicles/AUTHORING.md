# Original SCÈNE 112 vehicles — normalized source

`build_vehicles.py` and shared `assetkit.py` author original shaped body shells, wheel apertures/rolled fenders, glazing, panel seams, interiors, lights, mirrors and fictional livery. The tankautospuit includes original equipment shutters, ladder, pump fittings, reels and crew seats. No purchased/copied vehicle mesh, protected manufacturer badge or official livery is used. Private/proprietary project content: [project licenses](../../../docs/LICENSES.md).

Keep the repository layout:

- `source/3d/vehicles/`: builder, shared helper and packed editable `police_car.blend`/`fire_truck.blend`.
- `source/3d/characters/`: character builder imports the sibling vehicle helper.
- `assets/models/vehicles/`: runtime `police_car.glb`, `fire_truck.glb` and normalized manifests.
- `assets/textures/vehicles/`: original authored512px albedo/normal/roughness PNGs.

Blender4.3.2, standard glTF addon and NumPy rebuild the assets. Paths resolve from __file__; the current directory is arbitrary. Replace the script argument below with its absolute path when running outside the checkout:

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python source/3d/vehicles/build_vehicles.py
```

The default rebuild exports both GLBs, maps, manifests and packed editable .blend files without rendering. Optional `-- --preview` after the script argument writes internal Cycles previews only to `source/3d/vehicles/previews/`, excluded from runtime import by `source/3d/.gdignore`. Rebuild source never writes old `vehicles/source`/`vehicles/models` temporary layouts. GLB embeds used images; source .blend also packs images and stores final-layout relative paths (`../../../assets/textures/vehicles/...`) as editable fallback. Blender/NumPy are authoring dependencies; native players need neither.

Godot units/front: +Y up/-Z front, feet Y0, metres. Bounds including mirrors: car≈2.46×1.72×4.47m, truck≈3.08×3.20×6.29m. No physics body is exported. Keep the existing ServiceVehicle collision/camera/state root. Separate wheel pivots `Wheel_LF/RF/LR/RR` lie on actual axles; spin localX using radii.39m/.54m. A steering parent may hold front wheels. Stop wheel animation when the controlled simulation is paused.

The normalized validation rebuilt all four existing street assets without cosmetic edits and compared GLB hashes/semantic content with the accepted files. Each packed source was subsequently reopened from a texture-free relocated directory and re-exported without renders. Provenance uses final repository paths, not temporary filesystem roots. Model import/animation/visual QA and integrated/native acceptance remain separately recorded.
