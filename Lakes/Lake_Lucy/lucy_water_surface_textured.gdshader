shader_type spatial;

uniform vec4 color : source_color;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.01;
uniform float rim_amount : hint_range(0.0, 16.0) = 3.0;
uniform vec2 mesh_min = vec2(-655.5166, -639.6473);
uniform vec2 mesh_size = vec2(1365.878, 1323.194);
uniform float sample_distance : hint_range(0.001, 0.5) = 0.05;

// ViewportTexture from the displacement SubViewport (HDR2D, repeat enabled)
uniform sampler2D displacement_map;
// ViewportTexture from the foam ping-pong history buffer currently "live"
uniform sampler2D foam_map;
uniform vec4 foam_color : source_color = vec4(0.8, 0.9, 0.9, 1.0);

vec3 get_displacement(vec2 uv) {
	return texture(displacement_map, uv).rgb;
}

void vertex() {
	vec3 original_position = VERTEX.xyz;
	vec2 uv = (original_position.xz - mesh_min) / mesh_size;

	VERTEX += get_displacement(uv);

	vec3 forward_pos = original_position + vec3(0.0, 0.0, -1.0) * sample_distance;
	vec3 left_pos     = original_position + vec3(-1.0, 0.0, 0.0) * sample_distance;

	vec2 forward_uv = (forward_pos.xz - mesh_min) / mesh_size;
	vec2 left_uv     = (left_pos.xz - mesh_min) / mesh_size;

	vec3 wave_forward = forward_pos + get_displacement(forward_uv);
	vec3 wave_left    = left_pos + get_displacement(left_uv);

	vec3 forward_vec = wave_forward - VERTEX;
	vec3 left_vec    = wave_left - VERTEX;

	NORMAL = normalize(cross(forward_vec, left_vec));

	UV = uv;
}

void fragment() {
	float foam = texture(foam_map, UV).r;
	ALBEDO = mix(color.rgb, foam_color.rgb, foam);
	ROUGHNESS = roughness_val;
	RIM = rim_amount;
}