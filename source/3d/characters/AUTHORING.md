# Original SCÈNE 112 adults — normalized source

`build_characters.py` authors original adult geometry, garment details, facial features,512px skin/cloth/rubber PBR maps and the Scene112 eighteen-bone rig. It imports `../vehicles/assetkit.py` from the sibling source family. No purchased kit, downloaded scan, likeness or official crest is used. Private/proprietary project content: [project licenses](../../../docs/LICENSES.md).

Final layout: editable packed .blend/builder in `source/3d/characters`, GLBs and manifests in `assets/models/characters`, authored PNGs in `assets/textures/characters`. Retain the shared helper at `source/3d/vehicles/assetkit.py` and the `source/3d/.gdignore` import exclusion.

Run Blender4.3.2 with the standard glTF addon and NumPy. All paths resolve from __file__, independently of current working directory. Use an absolute script path when invoking from outside the checkout:

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python source/3d/characters/build_characters.py
```

The default rebuild performs no renders. It exports `officer.glb`/`civilian.glb`, original maps, normalized manifests and packed editable sources. Optional `-- --preview` writes internal previews only under ignored `source/3d/characters/previews/`. Each .blend embeds its images with final-layout relative fallback paths `../../../assets/textures/characters/...`; GLBs independently embed the used images. Native players require no Blender or NumPy installation. The discarded temporary `characters/source` and `characters/models` layout is not a rebuild dependency.

Both meshes face Godot-Z, use metres and have feet at Y0; officer≈1.848m, civilian≈1.835m. One skinned render mesh per adult, eighteen named bones. Four in-place clips retain their existing names/durations: idle3s, walk1.6s, run.8s, carry1.6s. The runtime adapter sets loop mode and selects speed/carry poses. Keep player collision/camera and NPC routines on their existing gameplay roots; the assets contain no collision bodies or behavioral script.

Normalized validation checks the rebuild against the accepted GLBs, verifies all images packed, then opens source copies from a relocated texture-free directory and re-exports. Those checks prove source/path correctness; model quality and integrated/native gameplay acceptance come from actual runtime QA, not authoring thumbnails.
