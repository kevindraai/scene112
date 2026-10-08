shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled;
// Apple Software Renderer only: one albedo sample, vertex lighting, world-XZ UV.
// Source geometry, actual lights and camera transforms stay unchanged.
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 planar_scale = vec2(1.0);
uniform vec2 planar_offset = vec2(0.0);
uniform bool vertex_color_albedo = false;
varying vec2 ground_uv;
void vertex() {
	ground_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * planar_scale + planar_offset;
}
void fragment() {
	ALBEDO = base_color.rgb * texture(albedo_texture, ground_uv).rgb;
	if (vertex_color_albedo) { ALBEDO *= COLOR.rgb; }
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
