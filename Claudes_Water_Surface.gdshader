shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D foam_texture;

uniform vec4 shallow_color : source_color = vec4(0.1, 0.5, 0.5, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.08, 0.15, 1.0);
uniform float depth_fade_distance = 8.0;

uniform float wave_steepness = 0.5;
uniform vec2 wave_dir_1 = vec2(1.0, 0.3);
uniform float wave_length_1 = 12.0;
uniform float wave_speed_1 = 1.0;

uniform vec2 wave_dir_2 = vec2(0.7, -0.7);
uniform float wave_length_2 = 6.0;
uniform float wave_speed_2 = 1.3;

uniform vec2 wave_dir_3 = vec2(-0.4, 0.9);
uniform float wave_length_3 = 3.0;
uniform float wave_speed_3 = 1.8;

uniform vec2 wave_dir_4 = vec2(0.9, 0.4);
uniform float wave_length_4 = 1.2;
uniform float wave_speed_4 = 2.5;

uniform float foam_distance = 1.0;
uniform float foam_scale = 4.0;
uniform float foam_speed = 0.15;
uniform float crest_foam_threshold = 0.6;

varying vec3 world_pos;
varying vec3 wave_normal;

vec3 gerstner_wave(vec2 dir, float wavelength, float steepness, float speed, vec3 pos, float time, inout vec3 tangent, inout vec3 binormal) {
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k) * speed;
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos.xz) - c * time);
    float a = steepness / k;

    tangent += vec3(-d.x * d.x * steepness * sin(f), d.x * steepness * cos(f), -d.x * d.y * steepness * sin(f));
    binormal += vec3(-d.x * d.y * steepness * sin(f), d.y * steepness * cos(f), -d.y * d.y * steepness * sin(f));

    return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float t = TIME;

    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    vec3 offset = vec3(0.0);

    offset += gerstner_wave(wave_dir_1, wave_length_1, wave_steepness, wave_speed_1, world_pos, t, tangent, binormal);
    offset += gerstner_wave(wave_dir_2, wave_length_2, wave_steepness * 0.7, wave_speed_2, world_pos, t, tangent, binormal);
    offset += gerstner_wave(wave_dir_3, wave_length_3, wave_steepness * 0.5, wave_speed_3, world_pos, t, tangent, binormal);
    offset += gerstner_wave(wave_dir_4, wave_length_4, wave_steepness * 0.3, wave_speed_4, world_pos, t, tangent, binormal);

    VERTEX += offset;
    wave_normal = normalize(cross(binormal, tangent));
    NORMAL = wave_normal;
}

void fragment() {
    float depth_raw = texture(depth_texture, SCREEN_UV).r;
    vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
    upos.xyz /= upos.w;
    float scene_depth = -upos.z;
    float pixel_depth = -VERTEX.z;
    float depth_diff = scene_depth - pixel_depth;

    float depth_fade = clamp(depth_diff / depth_fade_distance, 0.0, 1.0);
    vec4 water_color = mix(shallow_color, deep_color, depth_fade);

    float shore_foam = 1.0 - clamp(depth_diff / foam_distance, 0.0, 1.0);
    vec2 foam_uv1 = UV * foam_scale + vec2(TIME * foam_speed, 0.0);
    vec2 foam_uv2 = UV * foam_scale * 1.7 - vec2(0.0, TIME * foam_speed * 0.8);
    float foam_tex = texture(foam_texture, foam_uv1).r * texture(foam_texture, foam_uv2).r;
    float shore_foam_mask = smoothstep(0.3, 0.9, shore_foam) * foam_tex;

    float wave_steep = 1.0 - dot(NORMAL, vec3(0.0, 1.0, 0.0));
    float crest_foam_mask = smoothstep(crest_foam_threshold, 1.0, wave_steep) * foam_tex;

    float total_foam = clamp(shore_foam_mask + crest_foam_mask, 0.0, 1.0);

    vec3 screen_col = texture(screen_texture, SCREEN_UV + NORMAL.xz * 0.02).rgb;
    vec3 refracted = mix(screen_col, water_color.rgb, 0.6);

    ALBEDO = mix(refracted, vec3(1.0), total_foam);
    METALLIC = 0.0;
    ROUGHNESS = mix(0.05, 0.6, total_foam);
    SPECULAR = 0.5;
    ALPHA = mix(water_color.a, 1.0, total_foam);
}