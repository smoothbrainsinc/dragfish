shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

group_uniforms Colors;
uniform vec4 water_color        : source_color = vec4(0.0, 0.32, 0.43, 0.7);
uniform vec4 fog_color          : source_color = vec4(0.0, 0.20, 0.30, 1.0);
uniform vec4 intersection_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms Thresholds;
uniform float fog_threshold          : hint_range(0.0, 50.0) = 6.0;
uniform float intersection_threshold : hint_range(0.0, 10.0) = 1.0;
uniform float foam_threshold         : hint_range(0.0, 10.0) = 1.5;

group_uniforms NormalMaps;
uniform sampler2D normal_a : repeat_enable, filter_linear;
uniform sampler2D normal_b : repeat_enable, filter_linear;
uniform vec2  normal_a_st           = vec2(0.1, 0.1);
uniform vec2  normal_b_st           = vec2(0.13, 0.13);
uniform float normal_strength       : hint_range(0.0, 4.0) = 1.0;
uniform vec4  normal_panning_speeds = vec4(0.01, 0.0, 0.0, 0.01);

group_uniforms Foam;
uniform sampler2D foam_texture : repeat_enable, filter_linear;
uniform vec2  foam_tex_st      = vec2(0.1, 0.1);
uniform float foam_tex_speed_x = 0.01;
uniform float foam_tex_speed_y = 0.01;
uniform float foam_lines_speed = 0.5;
uniform float foam_intensity   : hint_range(0.0, 8.0) = 1.0;

group_uniforms Misc;
uniform float glossiness    : hint_range(0.0, 1.0) = 0.9;
uniform float fresnel_power : hint_range(0.1, 10.0) = 4.0;

// Ripple-RT stubs (interactive system not yet implemented).
// Defaults to black -> all ripple math degrades to identity.
uniform sampler2D ripple_render_texture : hint_default_black;
uniform vec3  ripple_cam_position   = vec3(0.0);
uniform float ripple_ortho_cam_size = 50.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 unpack_normal_scaled(vec4 s, float scale) {
	vec3 n;
	n.xy = (s.xy * 2.0 - 1.0) * scale;
	n.z  = sqrt(max(0.0, 1.0 - dot(n.xy, n.xy)));
	return n;
}

void fragment() {
	// Ripple render-texture (no-op: rt = (0,0,0,0) with black default)
	vec2 rt_uv = (world_pos.xz - ripple_cam_position.xz) / (ripple_ortho_cam_size * 2.0) + 0.5;
	vec4 rt = texture(ripple_render_texture, rt_uv);

	// Linear eye depth of opaque scene behind this fragment. Unity has a built-in function for this,
	// but Godot doesn't. This is needed for depth-based fog, shore intersection effects, and foam lines.
	// 1. Get the raw depth (0.0 to 1.0, non-linear)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	// 2. Transform from Screen Space/NDC back to View Space.
	vec4  view_pos  = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	// 3. The Perspective Divide
	view_pos.xyz   /= view_pos.w;
	// 4. Calculate the distance (the "Linear Depth")
	float diff = (-view_pos.z) - (-VERTEX.z);

	float fog_diff          = clamp(diff / fog_threshold,          0.0, 1.0);
	float intersection_diff = clamp(diff / intersection_threshold, 0.0, 1.0);
	float foam_diff         = clamp(diff / foam_threshold,         0.0, 1.0);
	foam_diff *= (1.0 - rt.b);

	// Three-level depth color: intersection -> water -> fog
	vec4 c = mix(mix(intersection_color, water_color, intersection_diff), fog_color, fog_diff);

	// Animated sine foam lines along shore intersections
	vec2  foam_uv  = world_pos.xz * foam_tex_st + TIME * vec2(foam_tex_speed_x, foam_tex_speed_y);
	float foam_tex = texture(foam_texture, foam_uv).r;
	float foam_cut = foam_diff
		- clamp(sin((foam_diff - TIME * foam_lines_speed) * 8.0 * PI), 0.0, 1.0)
		  * (1.0 - foam_diff);
	float foam = step(foam_cut, foam_tex);

	// Dual world-XZ normal maps; fresnel uses the geometric normal (pre-perturbation)
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0),
	                    fresnel_power);

	vec3 nA = unpack_normal_scaled(
		texture(normal_a, world_pos.xz * normal_a_st + TIME * normal_panning_speeds.xy + rt.rg),
		normal_strength);
	vec3 nB = unpack_normal_scaled(
		texture(normal_b, world_pos.xz * normal_b_st + TIME * normal_panning_speeds.zw + rt.rg),
		normal_strength);
	// Tangent-space (x,y,z) -> world for a +Y-up plane: tangent=+X, bitangent=+Z
	vec3 n_ts    = normalize(nA + nB);
	vec3 n_world = vec3(n_ts.x, n_ts.z, n_ts.y);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	ROUGHNESS = 1.0 - glossiness;
	METALLIC  = 0.0;

	// Alpha: fresnel transparency in shallow areas; foam and deep water are opaque
	float alpha = mix(mix(c.a * fresnel, 1.0, foam), fog_color.a, fog_diff);
	ALBEDO = c.rgb;
	PREMUL_ALPHA_FACTOR = alpha;
	ALPHA    = alpha;
	EMISSION = vec3(foam * foam_intensity);
}