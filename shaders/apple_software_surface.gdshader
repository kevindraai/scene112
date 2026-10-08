shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
// Apple CPU interpreter only. Geometry, skinning, textures and camera are real;
// sun, two street lamps and distance haze are evaluated once per vertex.
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool planar_world = false;
uniform bool vertex_color_albedo = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_energy = 1.0;
uniform vec3 ambient_color : source_color = vec3(0.6);
uniform float ambient_energy = 0.32;
uniform vec4 lamp0 = vec4(0.0);
uniform vec4 lamp1 = vec4(0.0);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.8, 0.6);
uniform float lamp_range = 10.0;
uniform vec3 haze_color : source_color = vec3(0.7, 0.8, 0.85);
uniform float haze_density = 0.0013;
varying vec2 surface_uv;
varying vec3 illumination;
varying float haze;

float local_light(vec3 point, vec3 normal, vec4 lamp) {
	vec3 offset = lamp.xyz - point;
	float distance_to_light = max(length(offset), 0.01);
	float falloff = max(1.0 - distance_to_light / lamp_range, 0.0);
	return lamp.w * falloff * falloff * max(dot(normal, offset / distance_to_light), 0.0);
}

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	surface_uv = (planar_world ? point.xz : UV) * uv_scale + uv_offset;
	illumination = ambient_color * ambient_energy;
	illumination += sun_color * sun_energy * max(dot(normal, sun_direction), 0.0);
	illumination += lamp_color * (local_light(point, normal, lamp0) + local_light(point, normal, lamp1));
	haze = clamp(length((VIEW_MATRIX * vec4(point, 1.0)).xyz) * haze_density, 0.0, 0.8);
}

void fragment() {
	vec4 surface = texture(albedo_texture, surface_uv) * base_color;
	if (vertex_color_albedo) { surface *= COLOR; }
	ALBEDO = mix(surface.rgb * illumination + emission_color * emission_energy, haze_color, haze);
	// ALPHA_OUTPUT
}
