shader_type spatial;
render_mode depth_draw_never, cull_disabled, blend_mix, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// Waves
uniform vec4 wave_1 : source_color = vec4(0.3, 4.0, 0.2, 0.6);
uniform vec4 wave_2 : source_color = vec4(-0.26, -0.19, 0.01, 0.47);
uniform vec4 wave_3 : source_color = vec4(-7.67, 5.63, 0.1, 0.38);
uniform vec4 wave_4 : source_color = vec4(-0.42, -1.63, 0.1, 0.28);
uniform vec4 wave_5 : source_color = vec4(1.66, 0.07, 0.15, 1.81);
uniform vec4 wave_6 : source_color = vec4(1.20, 1.14, 0.01, 0.33);
uniform vec4 wave_7 : source_color = vec4(-1.6, 7.3, 0.11, 0.73);
uniform vec4 wave_8 : source_color = vec4(-0.42, -1.63, 0.15, 1.52);
uniform float time_factor : hint_range(0.1, 10.0) = 2.5;
uniform float wave_scale : hint_range(0.001, 0.1) = 0.01;

// Lake mask (tune these to your lake world position)
uniform vec2 lake_center = vec2(0.0, 0.0);  // World XZ center of lake
uniform float lake_radius : hint_range(1.0, 1000.0) = 50.0;  // Lake size

// Water colors + depth
uniform vec3 base_color : source_color = vec3(0.0, 0.3, 0.6);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.5, 0.8);
uniform vec3 deep_color : source_color = vec3(0.0, 0.1, 0.3);
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float depth_near : hint_range(1.0, 50.0) = 7.0;
uniform float depth_far : hint_range(50.0, 1000.0) = 100.0;

// Foam + details
uniform sampler2D foam_tex;
uniform sampler2D normal_a;
uniform sampler2D normal_b;
uniform float foam_scale : hint_range(0.1, 5.0) = 1.0;
uniform float normal_speed : hint_range(0.0, 2.0) = 0.1;
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.8;

struct WaveResult {
    vec3 displacement;
    vec3 normal;
};

WaveResult gerstner(vec4 params, vec2 pos, float time) {
    float k = 2.0 * 3.14159 / params.w;
    float c = sqrt(9.81 / k);
    vec2 d = normalize(params.xy);
    float f = k * (dot(d, pos) - c * time);
    float a = params.z / k;

    vec3 disp = vec3(
        d.x * (a * cos(f)),
        a * sin(f),
        d.y * (a * cos(f))
    );

    float cos_f = cos(f);
    float sin_f = sin(f);
    vec3 norm = vec3(
        1.0 - params.z * d.x * d.x * sin_f,
        k * a * cos_f,
        -params.z * d.x * d.y * sin_f
    );

    return WaveResult(disp, normalize(norm));
}

WaveResult waves(vec2 pos, float time) {
    WaveResult r;
    r.displacement = vec3(0.0);
    r.normal = vec3(0.0, 1.0, 0.0);

    r.displacement += gerstner(wave_1, pos, time).displacement;
    r.normal += gerstner(wave_1, pos, time).normal;
    r.displacement += gerstner(wave_2, pos, time).displacement;
    r.normal += gerstner(wave_2, pos, time).normal;
    r.displacement += gerstner(wave_3, pos, time).displacement;
    r.normal += gerstner(wave_3, pos, time).normal;
    r.displacement += gerstner(wave_4, pos, time).displacement;
    r.normal += gerstner(wave_4, pos, time).normal;

    return r;
}

varying vec3 world_pos;
varying float wave_height;
varying vec3 wave_normal;

void vertex() {
    float t = TIME * time_factor;
    vec2 wave_coords = VERTEX.xz * wave_scale;

    WaveResult w = waves(wave_coords, t);
    VERTEX += w.displacement;
    NORMAL = w.normal;

    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wave_height = w.displacement.y;
    wave_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float edge(float depth) {
    depth = 2.0 * depth - 1.0;
    return depth_near * depth_far / (depth_far - depth * (depth_near - depth_far));
}

void fragment() {
    // Lake mask - discard outside lake bounds
    vec2 lake_dist = world_pos.xz - lake_center;
    float lake_mask = 1.0 - smoothstep(lake_radius - 5.0, lake_radius + 5.0, length(lake_dist));
    if (lake_mask <= 0.0) {
        discard;
    }

    // Depth-based coloring
    float scene_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).r);
    float frag_depth = edge(FRAGCOORD.z);
    float depth_factor = smoothstep(0.0, 20.0, scene_depth - frag_depth);
    vec3 water_color = mix(shallow_color, deep_color, depth_factor);

    // Screen space refraction
    vec3 refract_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, 1.0).rgb;
    ALBEDO = mix(refract_color, water_color, 0.7);

    // Foam on wave peaks + edges
    float foam = smoothstep(foam_threshold, 1.0, wave_height);
    foam += (1.0 - lake_mask) * 0.5;  // Edge foam
    foam *= texture(foam_tex, world_pos.xz * foam_scale + TIME * 0.1).r;
    ALBEDO = mix(ALBEDO, foam_color, foam);

    // Simple animated normals
    vec2 uv1 = world_pos.xz * 0.1 + TIME * normal_speed;
    vec2 uv2 = world_pos.xz * 0.2 - TIME * normal_speed * 0.7;
    vec3 n1 = texture(normal_a, uv1).rgb * 2.0 - 1.0;
    vec3 n2 = texture(normal_b, uv2).rgb * 2.0 - 1.0;
    NORMAL = normalize(mix(n1, n2, 0.5) * wave_normal);

    ROUGHNESS = 0.05;
    METALLIC = 0.0;

    ALPHA = lake_mask * 0.9;
}