extends "res://scripts/street_atmosphere.gd"
## Explicit local test fixture; leaves actual backend and adapter unchanged.
func _create_reflection() -> void:
	if not software_gl:
		_original_render_scale=get_viewport().scaling_3d_scale
		_original_scaling_mode=get_viewport().scaling_3d_mode
		_original_mesh_lod_threshold=get_viewport().mesh_lod_threshold
	_environment.sky.radiance_size=Sky.RADIANCE_SIZE_32
	software_gl=true
	apple_software_basic=true
	_apply_software_viewport()
