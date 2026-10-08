shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D wisp_texture : filter_linear, repeat_disable;
uniform float sim_clock = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float core_mix : hint_range(0.0, 1.0) = 0.0;
uniform float phase_offset = 0.0;
uniform float ceiling_y = 2.72;
uniform float floor_y = 0.035;
varying vec3 world_position;

void vertex() {
    // Particle matrices retain their own translation and size. No TIME: pause
    // leaves both this displacement and the CPU emitter stationary.
    vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(particle_scale.x, 0.0, 0.0, 0.0), vec4(0.0, particle_scale.y, 0.0, 0.0), vec4(0.0, 0.0, particle_scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
    float tip = clamp(1.0 - UV.y, 0.0, 1.0);
    VERTEX.x += sin(sim_clock * 5.1 + phase_offset + VERTEX.y * 7.0) * 0.055 * tip;
    world_position = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 field = texture(wisp_texture, UV);
    float edge = field.a * COLOR.a * intensity;
    float room_clip = smoothstep(floor_y, floor_y + 0.06, world_position.y) * (1.0 - smoothstep(ceiling_y - 0.12, ceiling_y, world_position.y));
    vec3 ember = vec3(0.78, 0.115, 0.012);
    vec3 gold = vec3(1.0, 0.50, 0.055);
    vec3 hot = vec3(1.0, 0.89, 0.49);
    vec3 tint = mix(ember, gold, smoothstep(0.10, 0.8, field.b));
    tint = mix(tint, hot, core_mix * field.b * (1.0 - field.g * 0.5));
    // GLES Compatibility's unshaded pass returns ALBEDO and omits EMISSION.
    // Put the self-lit HDR energy in ALBEDO so both renderers show hot fire.
    ALBEDO = tint * (0.9 + intensity * 1.5);
    ALPHA = edge * room_clip;
}
