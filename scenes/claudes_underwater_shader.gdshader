shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D caustic_texture;

uniform vec4 water_tint : source_color = vec4(0.05, 0.25, 0.35, 1.0);
uniform float tint_strength = 0.55;
uniform float fog_density = 0.04;

uniform float caustic_scale = 6.0;
uniform float caustic_speed = 0.3;
uniform float caustic_strength = 0.25;

uniform float distortion_strength = 0.006;
uniform float distortion_speed = 0.6;

uniform float vignette_strength = 0.35;

void fragment() {
    vec2 uv = SCREEN_UV;

    vec2 distort = vec2(
        sin(uv.y * 40.0 + TIME * distortion_speed),
        cos(uv.x * 40.0 + TIME * distortion_speed)
    ) * distortion_strength;

    vec3 scene = texture(screen_texture, uv + distort).rgb;

    float fog = 1.0 - exp(-fog_density * 10.0);
    vec3 col = mix(scene, water_tint.rgb, tint_strength);
    col = mix(col, water_tint.rgb, fog * 0.3);

    vec2 caustic_uv1 = uv * caustic_scale + vec2(TIME * caustic_speed, TIME * caustic_speed * 0.6);
    vec2 caustic_uv2 = uv * caustic_scale * 1.3 - vec2(TIME * caustic_speed * 0.7, TIME * caustic_speed * 0.4);
    float caustics = texture(caustic_texture, caustic_uv1).r * texture(caustic_texture, caustic_uv2).r;
    col += caustics * caustic_strength * water_tint.rgb * 2.0;

    float vig = distance(uv, vec2(0.5));
    col *= 1.0 - vig * vignette_strength;

    COLOR = vec4(col, 1.0);
}