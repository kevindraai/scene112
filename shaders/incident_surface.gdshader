shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Static house-local fields: no TIME, particles, inference or incident mutation.
uniform mat4 house_inverse;
uniform vec4 cell_front; // local x,z; actual accumulated burned; actual wet
uniform vec4 cell_origin;
uniform vec4 cell_side;
uniform sampler2D incident_mask : repeat_enable, filter_linear_mipmap;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D base_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D base_metallic : filter_linear_mipmap, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 base_colour : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float dry_roughness = 0.8;
uniform float dry_metallic = 0.0;
uniform float normal_depth = 1.0;
uniform int roughness_channel = 0;
uniform int metallic_channel = 0;
uniform bool has_albedo = false;
uniform bool has_roughness = false;
uniform bool has_metallic = false;
uniform bool has_normal = false;
uniform bool use_vertex_colour = false;
varying vec3 house_position;
varying vec3 house_normal;

float channel(vec4 value, int index) {
	if (index == 1) { return value.g; }
	if (index == 2) { return value.b; }
	if (index == 3) { return value.a; }
	if (index == 4) { return dot(value.rgb,vec3(0.333333)); }
	return value.r;
}

vec3 cell_field(vec3 point, vec4 cell) {
	vec2 offset = point.xz-cell.xy;
	float radius2 = dot(offset,offset);
	// A visual gain on accumulated model fuel consumption; zero stays zero.
	float damage = sqrt(clamp(cell.z*24.0,0.0,1.0));
	float rise = smoothstep(0.2,2.5,point.y);
	float plume_radius = 1.15+rise*1.4;
	float deposit = damage*exp(-radius2/(plume_radius*plume_radius))*(0.18+rise*0.82);
	float dy = (point.y-0.55)*0.65;
	float scorch = damage*exp(-(radius2+dy*dy)/2.8);
	float low = 1.0-smoothstep(0.06,0.65,point.y);
	float water = clamp(cell.w,0.0,1.0)*exp(-radius2/3.7)*low;
	return vec3(deposit,scorch,water);
}

void vertex() {
	house_position = (house_inverse*MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	house_normal = normalize(mat3(house_inverse)*mat3(MODEL_MATRIX)*NORMAL);
}

void fragment() {
	vec2 primary_uv = UV*uv_scale+uv_offset;
	vec3 colour = base_colour.rgb;
	if (has_albedo) { colour *= texture(base_albedo,primary_uv).rgb; }
	if (use_vertex_colour) { colour *= COLOR.rgb; }
	float roughness = dry_roughness;
	if (has_roughness) { roughness *= channel(texture(base_roughness,primary_uv),roughness_channel); }
	float metallic = dry_metallic;
	if (has_metallic) { metallic *= channel(texture(base_metallic,primary_uv),metallic_channel); }
	if (has_normal) { NORMAL_MAP = texture(base_normal,primary_uv).rgb; NORMAL_MAP_DEPTH = normal_depth; }

	vec3 weights = pow(abs(normalize(house_normal)),vec3(5.0));
	weights /= max(dot(weights,vec3(1.0)),0.0001);
	vec4 mask = texture(incident_mask,house_position.zy*0.78)*weights.x;
	mask += texture(incident_mask,house_position.xz*0.78)*weights.y;
	mask += texture(incident_mask,house_position.xy*0.78)*weights.z;
	vec3 field = cell_field(house_position,cell_front)+cell_field(house_position,cell_origin)+cell_field(house_position,cell_side);
	float soot = clamp(field.x*(0.35+mask.r*0.9)*(0.75+mask.g*0.5),0.0,0.84);
	float char = clamp(field.y*(0.30+mask.r*0.60)*(0.88+mask.b*0.12),0.0,0.78);
	float wet = clamp(field.z*(0.45+mask.a*0.85),0.0,0.95);
	vec3 deposited = mix(colour,vec3(0.031,0.028,0.023),soot);
	deposited = mix(deposited,vec3(0.042,0.029,0.019),char*0.72);
	ALBEDO = deposited*(1.0-wet*0.27);
	ROUGHNESS = mix(clamp(roughness+char*0.12,0.04,1.0),0.09,wet);
	METALLIC = metallic*(1.0-max(soot,char)*0.5);
	SPECULAR = 0.5+wet*0.16;
}
