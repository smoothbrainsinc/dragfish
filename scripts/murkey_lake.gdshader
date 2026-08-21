shader_type canvas_item;

// DECLARE THE SCREEN TEXTURE (Godot 4.7+ requirement)
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// ON/OFF SWITCH - Set this to true/false from your script
uniform bool underwater = false;

// Your adjustable settings
uniform float wave_strength : hint_range(0.0, 0.05) = 0.015;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.8;
uniform float murkiness : hint_range(0.0, 1.0) = 0.85;
uniform vec3 water_tint : source_color = vec3(0.05, 0.25, 0.3);

// Wave function for distortion
float wave(vec2 uv, float time) {
    float w1 = sin(uv.x * 12.0 + time * 1.3) * cos(uv.y * 10.0 + time * 0.9);
    float w2 = sin(uv.y * 15.0 - time * 1.1) * cos(uv.x * 18.0 + time * 0.7);
    return (w1 * 0.6 + w2 * 0.4);
}

void fragment() {
    if (underwater) {
        // --- UNDERWATER EFFECT ---
        
        // 1. Generate wavy distortion
        float time = TIME * wave_speed;
        vec2 wave_offset = vec2(
            wave(UV * 1.5 + 0.2, time),
            wave(UV * 1.5 - 0.3, time * 0.8)
        ) * wave_strength;

        // 2. Sample the screen with distortion
        vec2 distorted_uv = SCREEN_UV + wave_offset;
        vec3 underwater_view = textureLod(SCREEN_TEXTURE, distorted_uv, 0.0).rgb;

        // 3. Murky blur (5-sample cheap blur)
        float blur_amount = murkiness * 0.005;
        vec3 blurred_view = underwater_view;
        blurred_view += textureLod(SCREEN_TEXTURE, distorted_uv + vec2(blur_amount, 0.0), 0.0).rgb;
        blurred_view += textureLod(SCREEN_TEXTURE, distorted_uv - vec2(blur_amount, 0.0), 0.0).rgb;
        blurred_view += textureLod(SCREEN_TEXTURE, distorted_uv + vec2(0.0, blur_amount), 0.0).rgb;
        blurred_view += textureLod(SCREEN_TEXTURE, distorted_uv - vec2(0.0, blur_amount), 0.0).rgb;
        blurred_view /= 5.0;

        // 4. Apply water tint (75% tint for murky lake)
        vec3 final_color = mix(blurred_view, water_tint, 0.75);

        // 5. Vignette for depth feeling
        float dist_to_center = distance(UV, vec2(0.5));
        float vignette = 1.0 - (dist_to_center * 0.3);
        final_color *= vignette;

        COLOR = vec4(final_color, 1.0);
    } else {
        // --- NOT UNDERWATER - Just show the normal screen ---
        COLOR = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0);
    }
}