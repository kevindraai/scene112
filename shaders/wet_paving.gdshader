shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool planar_world = false;
uniform float planar_scale = 0.5;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.82;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.75;
uniform bool has_normal = false;
uniform int roughness_channel = 0;
varying vec3 world_at;

float hash(vec2 at) {
	return fract(sin(dot(at, vec2(127.1, 311.7))) * 43758.5453123);
}
float noise(vec2 at) {
	vec2 cell = floor(at);
	vec2 t = fract(at);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), t.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), t.x), t.y);
}
void vertex() { world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 at = UV * uv_scale + uv_offset;
	if (planar_world) at = world_at.xz * planar_scale;
	float patch = noise(world_at.xz * 0.38) * 0.70 + noise(world_at.xz * 1.13) * 0.30;
	float puddle = smoothstep(0.42, 0.71, patch) * wetness;
	vec4 rough_sample = texture(roughness_texture, at);
	float source_roughness = rough_sample.r;
	if (roughness_channel == 1) source_roughness = rough_sample.g;
	if (roughness_channel == 2) source_roughness = rough_sample.b;
	if (roughness_channel == 3) source_roughness = rough_sample.a;
	ALBEDO = texture(albedo_texture, at).rgb * base_color.rgb * mix(0.82, 0.69, puddle);
	ROUGHNESS = mix(clamp(source_roughness * dry_roughness, 0.08, 1.0), 0.105, puddle);
	SPECULAR = 0.55;
	METALLIC = 0.0;
	CLEARCOAT = puddle * 0.45;
	CLEARCOAT_ROUGHNESS = 0.15;
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, at).rgb;
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - puddle * 0.72);
	}
}
