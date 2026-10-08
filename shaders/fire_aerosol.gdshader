shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D field_texture : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.35, 0.35, 0.34, 0.20);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float ceiling_y = 2.72;
uniform float floor_y = 0.035;
uniform bool room_clip = true;
uniform bool align_to_stream = false;
uniform vec3 stream_direction = vec3(0.0, 1.0, 0.0);
varying vec3 world_position;

void vertex() {
    // Orient the narrow water drop along the projected real nozzle direction.
    // Smoke and steam retain their full soft billboard envelope.
    if (align_to_stream) {
        vec3 view_direction = (VIEW_MATRIX * vec4(stream_direction, 0.0)).xyz;
        float angle = atan(view_direction.x, view_direction.y);
        float c = cos(angle);
        float s = sin(angle);
        VERTEX.xy = vec2(VERTEX.x * c + VERTEX.y * s, -VERTEX.x * s + VERTEX.y * c);
    }
    vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(particle_scale.x, 0.0, 0.0, 0.0), vec4(0.0, particle_scale.y, 0.0, 0.0), vec4(0.0, 0.0, particle_scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
    world_position = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 field = texture(field_texture, UV);
    float bounds = 1.0;
    if (room_clip) {
        bounds = smoothstep(floor_y, floor_y + 0.06, world_position.y) * (1.0 - smoothstep(ceiling_y - 0.18, ceiling_y, world_position.y));
    }
    ALBEDO = field.rgb * tint.rgb;
    ALPHA = field.a * COLOR.a * tint.a * intensity * bounds;
}
