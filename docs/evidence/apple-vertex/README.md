# Apple Software Renderer vertex/albedo profile

Frozen candidate against canonical `092c33a519cc84dc2017dd502f84b5cceea2eedf`. No canonical edits, new PR, CI relaxation, gameplay/state/physics/asset change. Integrate `handoff/` files using `SHA256SUMS`, or `apple-vertex.patch`. Four production sources plus two new UID sidecars; four explicit verification fixtures plus their UIDs. Existing classification test remains unchanged.

## Behavior and evidence boundary

Only `apple_software_basic` selects these overrides. Ordinary GPU and llvmpipe/softpipe production paths keep existing materials, weather shader and environment. Apple's existing 0.25 3D scale / LOD8 remain. UI remains full resolution. This is an explicit software fallback, not the hardware visual quality target and not a native Intel pass.

- All current app mesh instances, including officer outside District and later added actors, receive instance-only vertex-lit StandardMaterial3D copies preserving source albedo texture/color/UV/vertex paint, alpha/culling/billboard behavior. Existing unshaded signals remain unshaded. Actual imported geometry, rigs, animations and actual lights are unchanged.
- Normal, roughness, metallic, AO and other extra maps/features are removed from these copies; only albedo texture is sampled. Specular/metallic are disabled. Ground world triplanar uses a one-sample world-XZ shader with actual vertex lighting, preserving metre-scale texture repetition. The existing world uses triplanar only for ground/paving.
- Apple wet material darkens source albedo instead of the custom puddle/noise/normal/specular fragment shader. Rain remains 72 particles; only this tier widens streaks to 0.04×0.32 m and alpha 0.35, visibly present in final rain image.
- Apple sky reflections are disabled and sky ambient contribution is zero. Ambient source remains COLOR, sun/spot lights and actual colored atmosphere remain. Native Godot source `drivers/gles3/rasterizer_scene_gles3.cpp:1626` proves COLOR sets `use_ambient_cubemap=false`; line 1633–1635 proves disabled reflection source sets `use_reflection_cubemap=false`. This also avoids residual samples still present with `specular_disabled` alone (`drivers/gles3/shaders/scene.glsl:2417`). Sky background remains.
- Strong references retain source/previous override while helper owns its replacement. Restores compare material identity and preserve later external overrides. Deferred node-added scan covers new actors without a per-frame full-tree walk. Atmosphere restores helper before its own weather overrides; shutdown also releases helper. Source mesh/material resources are never modified.
- `graphics_validation.gd` keeps the full original albedo/normal/roughness map coverage checks via retained source. Apple adds assertions that active imported materials actually use vertex/unshaded rendering, preserved albedo, no normal/roughness sample. Other profiles continue checking their active PBR materials. Unsupported shader count is explicit; canonical street+actors have zero.

## Verification

Godot4.7.2 stable Linux; explicit forced profile in test fixture, actual Mesa llvmpipe OpenGL4.5. Adapter identity is never spoofed.

- `validation/forced-graphics-no-reflection.log`: exit 0, **294 checks**, full actual app route: >10 m walking, >20 m drive, steering, braking, exit, roof camera, original rig clips, day/dusk/rain, pause, root save/load; audio teardown 2 synchronized mixes. No script/shader/resource/leak errors. Xvfb only warns unsupported VSync adjustment.
- `validation/forced-graphics-runtime.json`: all three conditions **666 vertex-albedo + 44 vertex-planar surfaces; zero unsupported**. Day/dusk101 drawcalls33304primitives; rain102/33448 at captured pose. These are local diagnostic samples, no native performance claim.
- `validation/captures/visual-street-{day,dusk,rain,high-rain}.png`: real1280×720 app output, reviewed. Sky/day/lamps/rain differences and textured assets remain readable within the admitted quarter-resolution limit. No image editing.
- `validation/material-tests-final.log`: **15 checks**, strong references, instance copies, original PBR unchanged, source lookup, repeat refresh, later player outside world, foreign override preservation, material+surface override precedence, deleted/reused actors and restoration.
- `validation/profile-classification.log`: **18 checks**, Apple-only selector, other hardware/software backends unchanged.
- `validation/normal-material-profile.log`: **110 PBR checks**, non-Apple path has no helper overrides.
- `validation/forced-headless-final.log`: **290 checks** full forced route before final reflection-only property change; exact final code verified in the graphics route above.
- `validation/import-final.log`: clean import and final UID sidecars.

Earlier failed fixture logs are retained: initial copy omitted design SVGs and a test-only inferred Variant failed strict parsing; headless forced fixture initially retained sky128. They were corrected before accepted runs and are not successes.

Run locally with standard temporary Godot XDG variables:
```
godot --headless --path PROJECT --script tests/apple_material_tests.gd
godot --headless --path PROJECT --script tests/apple_profile_tests.gd
godot --headless --path PROJECT --script tests/apple_normal_profile_test.gd
godot --headless --path PROJECT --script tests/apple_vertex_playthrough.gd
python3 tools/graphical_playthrough.py GODOT --project PROJECT --runtime-script tests/apple_vertex_playthrough.gd --timeout 150
```
Forced fixture explicitly replaces only the atmosphere in the same real app, leaving actual adapter unchanged. Production selector is automatic only on the real Apple software adapter. Root must rerun existing native macOS Intel/arm64 and Windows visual gates; no timeout increase or performance acceptance is claimed here. Independent review requested from quality agent on exact final source hashes.

Primary technical references: [Godot4.7 BaseMaterial3D](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html), [Godot4.7 spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html), and checked local official4.7.2 GLES3 source. Bootstrap inherited/rechecked central882ba834; local current workorder/plan and explicit parent isolated-prep scope respected.
