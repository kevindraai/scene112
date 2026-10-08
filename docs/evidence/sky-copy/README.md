# Godot 4.7.2 Sky copy lifetime evidence

This self-contained one-box scene reproduces the integrated street's Compatibility/OpenGL texture leak without game assets, weather shaders, audio or gameplay. It retains an original Environment with a default256 ProceduralSky, duplicates the Environment, then replaces the clone's sky with a new128 incremental ProceduralSky. Only the deep/shallow copy choice differs.

The recorded Linux/X11 Mesa25.0.7 llvmpipe run shows two349524-byte texture leaks with `duplicate(true)` and no errors with `duplicate(false)`. Exit0 alone is insufficient: the deep case deliberately demonstrates renderer errors after its completion marker. This identifies the application trigger under this pinned renderer; it does not claim a complete upstream engine diagnosis or native-platform result. The separate full integrated street run was subsequently clean with the shallow-copy fix.

Reproduce with installed Xvfb and an actual Godot4.7.2 Compatibility renderer:

```sh
python3 run_sky_copy.py --godot /path/to/godot --output /tmp/scene112-sky-copy-output
```

Supply the ordinary graphics runtime library environment when required by the host. The script requires real rendering and rejects headless evidence. `logs/deep.log`, `logs/shallow.log` and `logs/summary.json` retain actual renderer/version, commands and source/log hashes. Extra focused variants in the original investigation ruled out wet sampler hints, SSAO, glow and a standalone ReflectionProbe; deliberate free/frame delays did not fix deep-copy replacement. Shallow Environment copying is appropriate in the street module because its Environment changes are scalar, while it explicitly creates a new unique Sky/material.
