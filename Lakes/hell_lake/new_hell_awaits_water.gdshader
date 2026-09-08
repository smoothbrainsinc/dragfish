shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// ---- Colors ----
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 fog_color : source_color = vec4(1.0);
uniform vec4 intersection_color : source_color = vec4(1.0);

// ---- Thresholds ----
uniform float intersection_threshold = 0.01;
uniform float fog_threshold = 0.01;
uniform float foam_threshold = 0.01;

// ---- Normal maps ----
uniform sampler2D normal_a : hint_normal;
uniform sampler2D normal_b : hint_normal;
uniform float normal_strength = 1.0;
uniform vec2 normal_a_tiling = vec2(1.0);
uniform vec2 normal_b_tiling = vec2(1.0);
uniform vec4 normal_panning_speeds = vec4(0.0);

// ---- Foam ----
uniform sampler2D foam_texture;
uniform vec2 foam_texture_tiling = vec2(1.0);
uniform float foam_texture_speed_x = 0.0;
uniform float foam_texture_speed_y = 0.0;
uniform float foam_lines_speed = 0.0;
uniform float foam_intensity = 1.0;

// ---- Misc ----
uniform float glossiness : hint_range(0.0, 1.0) = 0.5;
uniform float fresnel_power = 1.0;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw_depth * 2.0 - 1.0;
#endif
	vec4 view_space = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_space.xyz /= view_space.w;
	float scene_depth   = -view_space.z;
	float surface_depth = -VERTEX.z;

	float fog_diff          = clamp((scene_depth - surface_depth) / fog_threshold, 0.0, 1.0);
	float intersection_diff = clamp((scene_depth - surface_depth) / intersection_threshold, 0.0, 1.0);
	float foam_diff         = clamp((scene_depth - surface_depth) / foam_threshold, 0.0, 1.0);

	vec4 c = mix(mix(intersection_color, albedo_color, intersection_diff), fog_color, fog_diff);

	vec2 pan_a = TIME * normal_panning_speeds.xy;
	vec2 pan_b = TIME * normal_panning_speeds.zw;
	vec3 n_a = texture(normal_a, world_pos.xz * normal_a_tiling + pan_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(normal_b, world_pos.xz * normal_b_tiling + pan_b).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(vec3((n_a.xy + n_b.xy) * normal_strength, 1.0));

	float foam_tex = texture(foam_texture, world_pos.xz * foam_texture_tiling
			+ TIME * vec2(foam_texture_speed_x, foam_texture_speed_y)).r;
	float foam = step(foam_diff - (clamp(sin((foam_diff - TIME * foam_lines_speed) * 8.0 * PI), 0.0, 1.0)
			* (1.0 - foam_diff)), foam_tex);

	float fresnel = pow(1.0 - clamp(dot(blended_normal, normalize(VIEW)), 0.0, 1.0), fresnel_power);

	ALBEDO     = c.rgb;
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	ROUGHNESS  = 1.0 - glossiness;
	ALPHA      = mix(mix(c.a * fresnel, 1.0, foam), fog_color.a, fog_diff);
	EMISSION   = vec3(foam * foam_intensity);
}