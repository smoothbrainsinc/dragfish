shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;   // keep depth_draw_always

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;

// Wave settings (keep your current values or tweak)
uniform float amplitude : hint_range(0.0, 1.2) = 0.45;
uniform float wavelength : hint_range(8.0, 50.0) = 22.0;
uniform float wave_speed : hint_range(0.2, 3.0) = 1.05;
uniform float steepness : hint_range(0.0, 0.8) = 0.5;

// Color - made stronger
uniform vec3 deep_color : source_color = vec3(0.0, 0.008, 0.045);   // very dark blue-black
uniform vec3 shallow_color : source_color = vec3(0.3, 0.65, 0.9);
uniform float depth_scale : hint_range(5.0, 60.0) = 35.0;          // much stronger

uniform float refraction_strength : hint_range(0.0, 0.2) = 0.05;
uniform float transparency : hint_range(0.2, 0.8) = 0.55;
uniform float foam_width : hint_range(0.0, 6.0) = 2.0;

vec3 gerstner_offset(vec3 world_pos, vec2 dir, float t) {
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.81 / k);
    float f = k * (dot(dir, world_pos.xz) - c * t * wave_speed);
    float a = steepness / k;
    return vec3(a * dir.x * cos(f), a * sin(f) * amplitude, a * dir.y * cos(f));
}

vec3 gerstner_normal_contrib(vec3 world_pos, vec2 dir, float t) {
    float k = 2.0 * PI / wavelength;
    float f = k * (dot(dir, world_pos.xz) - sqrt(9.81 / k) * t * wave_speed);
    float wa = steepness * amplitude;
    return vec3(-dir.x * wa * cos(f), 1.0 - steepness * sin(f), -dir.y * wa * cos(f));
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    vec2 dir1 = normalize(vec2(1.0, 0.38));
    vec2 dir2 = normalize(vec2(-0.65, 1.0));

    VERTEX += gerstner_offset(world_pos, dir1, TIME);
    VERTEX += gerstner_offset(world_pos * 0.68, dir2, TIME * 1.32);

    vec3 n = gerstner_normal_contrib(world_pos, dir1, TIME) + gerstner_normal_contrib(world_pos * 0.68, dir2, TIME * 1.32);
    NORMAL = normalize(n);
}

void fragment() {
    // Refraction
    vec2 refr_uv = SCREEN_UV + NORMAL.xz * refraction_strength;
    vec3 bg = texture(SCREEN_TEXTURE, refr_uv).rgb;

    // Improved depth calculation for imported + displaced meshes
    float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    float scene_depth = -view_pos.z / view_pos.w;

    // Use VERTEX.z from water surface + bias to help large meshes
    float water_depth = max(0.0, scene_depth - (VERTEX.z - 0.5)) * depth_scale;   // added bias

    vec3 tint = mix(shallow_color, deep_color, clamp(water_depth / 10.0, 0.0, 1.0));
    float edge_foam = 1.0 - smoothstep(0.0, foam_width, water_depth);

    vec3 color = mix(bg * tint, vec3(0.95, 0.97, 1.0), edge_foam);

    float fresnel = pow(1.0 - max(0.0, dot(normalize(NORMAL), normalize(VIEW))), 5.0);

    ALBEDO = mix(color, vec3(1.0), fresnel * 0.22);
    ROUGHNESS = 0.04;
    METALLIC = 0.0;
    ALPHA = transparency;
}