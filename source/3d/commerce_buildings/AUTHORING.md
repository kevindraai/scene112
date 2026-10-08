# Original compact commerce shells

The existing closed bakery and workshop become original render geometry inside the current building, roof and awning footprints. They add no town area, interior gameplay, physics, lights, camera, floor, door controller or real business branding. The world retains its existing StaticBody colliders, original signs and ShopAwning.

Build with Blender 4.3.2 and NumPy:

```sh
blender --background --factory-startup --threads 1 --python-use-system-env --python-exit-code 1 --python /absolute/repository/source/3d/commerce_buildings/build_commerce.py
```

Paths derive from the source location, so current working directory is irrelevant. The complete helper and original texture-field generator are included locally. Default execution performs no renders. Optional `-- --preview` writes only source/previews. The original project-private/proprietary license applies to code, geometries and textures. There are no downloaded assets, photos, commercial materials or external libraries of models.

Both runtime GLBs embed their image data. Both editable `.blend` files pack nine original 512px PNGs: albedo, tangent-space normal and roughness for brick, aged coated metal and painted details. Transparent recessed glass is a separate material. Native COLOR_0 stores original detail colours; all used primary UVs are explicitly authored in surface metres. Coated sheet metal has low metallic response and high roughness, matching its painted surface. Real shallow ribs, seams and folded edges produce the larger highlights; procedural grain is restrained.

Godot coordinates are metres, +Y up, local frontage −Z. The bakery root goes at `(46,0,31)` with zero yaw. It contains 3,524 triangles, four shared materials and four consolidated meshes. Framed recessed shop glazing, split brick piers, a closed front door with actual handle/kickplate, shallow non-enterable bread display, masonry sills, coping strips, drainage and original canopy brackets replace the blockout renderer. The existing world ShopAwning remains visible. The existing bakery sign at `(46,3.1,26.38)` remains outside the fascia and is not part of the GLB. The shop's closed StaticBody remains at `(46,2,31)` with size `(13,4,9)`.

The workshop root goes at `(24,0,-44)` with yaw `PI`; this maps the local front −Z to the existing world front +Z. Local door centre X+1 maps to existing world X23. Its 6,282 triangles, three shared materials and three consolidated meshes contain brick plinths, ribbed coated panels, a closed loading shutter and guide rails, shallow roof profile/seams, gutters, drains and original low ventilation hoods. The current roof envelope is 25×17m; minor gutter thickness stays within 25×17.056m. The existing sign at `(24,6.3,-35.9)` remains separate and readable. Its original closed StaticBody remains at `(24,3.8,-44)` with size `(24,7.6,16)`.

Render group names are BakeryFacade, BakeryRoof, WindowDisplayClosed, ClosedFrontDoor; WorkshopFacade, WorkshopRoof, ClosedLoadingDoor. Each has one clearly named consolidated mesh child. No renderer name carries a Godot collision-generation suffix.

Use the integration JSON for exact renderer hide lists. Hide old MeshInstance descendants only; hiding/removing a StaticBody parent would remove other context and is not intended. Preserve all floors, signs, existing awning, interaction IDs and physics. The mesh shells are closed visual detail, not a promise of newly enterable rooms.

The isolated Godot driver uses actual native glTF import, verifies PBR/UV/COLOR_0/material and triangle budgets, verifies the original building collision planes, and captures four player-height views with actual world placements, signs and retained awning. This is Linux Compatibility evidence, not full-world gameplay, native-platform or physical-GPU performance proof. The fixture's day sun/ambient/filmic white point match the established street values; pictures are not postprocessed.

Packed-source relocation and independent Python rebuild comparisons are recorded separately in validation evidence. Exact GLB bytes may differ by oriented triangle ordering from Blender's evaluation; geometry/material/image/UV equivalence is checked explicitly. Do not package `.blend1`, Python caches, validation scene data or Godot imports with authoring sources.
