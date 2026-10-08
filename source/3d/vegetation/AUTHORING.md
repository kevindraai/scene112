# Original pruned street tree

`build_street_tree.py` authors this street tree from custom tapered branched tubes and1,488 individual curved leaf cards. No purchased/downloaded mesh, scanned bark, stock vegetation bitmap or image-generation filter is used. All nine512px bark/leaf albedo, roughness and normal PNGs are authored mathematically in the builder. Leaf alpha is converted to a hard mask by a Math ROUND node, as described in [the official glTF exporter documentation](https://github.com/KhronosGroup/glTF-Blender-IO/blob/main/docs/blender_docs/scene_gltf2.rst#alpha-modes). The actual exported leaf materials are MASK/double-sided, then Godot imports them as Alpha Scissor.

Final layout: `source/3d/vegetation` holds the self-contained builder and packed editable street_tree.blend, `assets/models/vegetation/street_tree.glb` is the runtime asset, and `assets/textures/vegetation` retains authored PNG maps. Source/3d is excluded by .gdignore. All paths resolve from __file__; Blender4.3.2, NumPy and the standard glTF exporter are authoring dependencies only. Build from any current directory using an absolute script path:

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python source/3d/vegetation/build_street_tree.py
```

The builder executes zero rendering calls. It saves a fully packed editable source with final-layout relative texture fallback paths and an embedded-image GLB. Three materials, one render mesh,15,388 triangles,1,488 leaves. Pruned canopy begins at3.61m, overall height6.57m, crown radius≈2.15m; the narrow branched trunk replaces the existing .20m physical-trunk footprint. The two-metre viewing corridor is below foliage. Retain existing collision and placement on the game tree root; the asset has no collision or scripted behavior and adds no geography. Local Y is up in Godot; place feet at Y0. Branching is deliberately compact and asymmetrical, without botanical species/certification claims.

The separate Godot4.7.2 import test validates source UV0, all albedo/normal/roughness maps, actual Alpha Scissor/double-sided leaves, triangle budget, canopy height and finite imported geometry. This headless test proves artifact/import/bounds, not final visual quality or native playability. Root/D must judge the asset in the real street and its normal camera during runtime QA; no internal Blender rendering substitutes for that acceptance.

License: original SCÈNE112 private/proprietary project content under docs/LICENSES.md. The manifest records version, final source paths, budgets, zero renders and exact GLB SHA256.
