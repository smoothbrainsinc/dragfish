shader_type canvas_item;

// False-color view of the sim state texture: water depth as blue->white ramp,
// speed as red tint, ignores alpha (RGBA32F data texture).

uniform sampler2D tx_bottom : filter_nearest, repeat_disable;
uniform float h_scale = 1.2;
uniform float uv_scale = 0.5;

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	float b = texture(tx_bottom, UV).r;
	float h = max(s.r - b, 0.0);
	float spd = length(s.gb) / max(h, 0.05);
	vec3 col = mix(vec3(0.02, 0.03, 0.10), vec3(0.3, 0.55, 1.0), clamp(h * h_scale, 0.0, 1.0));
	col = mix(col, vec3(1.0), clamp((h * h_scale - 1.0) * 0.6, 0.0, 0.35));
	col += vec3(1.0, 0.1, 0.0) * clamp(spd * uv_scale, 0.0, 1.0) * 0.6;
	col += vec3(0.9, 0.95, 0.8) * clamp(s.a * 3.0, 0.0, 1.0); // foam channel
	if (h <= 0.0005) {
		col = mix(vec3(0.35, 0.28, 0.18), vec3(0.55, 0.45, 0.3), clamp(b * 0.5 + 0.5, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
