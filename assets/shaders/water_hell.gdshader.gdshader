shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ─── Water Color ───────────────────────────────────────────────────────────────
uniform vec4 shallow_color : source_color = vec4(0.05, 0.45, 0.65, 0.72);
uniform vec4 deep_color    : source_color = vec4(0.0,  0.08, 0.28, 0.97);
uniform float depth_scale  : hint_range(0.0, 50.0) = 10.0;

// ─── Surface ───────────────────────────────────────────────────────────────────
uniform float roughness      : hint_range(0.0, 1.0) = 0.05;
uniform float metallic       : hint_range(0.0, 1.0) = 0.0;
uniform float specular       : hint_range(0.0, 1.0) = 1.0;

// ─── Waves ─────────────────────────────────────────────────────────────────────
uniform float wave_speed     : hint_range(0.0, 4.0)  = 0.6;
uniform float wave_strength  : hint_range(0.0, 2.0)  = 0.35;
uniform float wave_scale     : hint_range(0.1, 20.0) = 5.0;
uniform float chop           : hint_range(0.0, 1.0)  = 0.6;

// ─── Fresnel ───────────────────────────────────────────────────────────────────
uniform float fresnel_power  : hint_range(1.0, 10.0) = 3.0;

// ─── Foam ──────────────────────────────────────────────────────────────────────
uniform float foam_depth     : hint_range(0.0, 5.0)  = 1.5;
uniform vec4  foam_color     : source_color = vec4(0.92, 0.96, 1.0, 1.0);

// ─── Depth texture ─────────────────────────────────────────────────────────────
uniform sampler2D depth_texture   : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture  : hint_screen_texture, filter_linear_mipmap;

// ─── Noise ─────────────────────────────────────────────────────────────────────
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(hash2(i),                    f - vec2(0.0, 0.0));
	float b = dot(hash2(i + vec2(1.0, 0.0)),   f - vec2(1.0, 0.0));
	float c = dot(hash2(i + vec2(0.0, 1.0)),   f - vec2(0.0, 1.0));
	float d = dot(hash2(i + vec2(1.0, 1.0)),   f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

// ─── Layered wave normals ──────────────────────────────────────────────────────
vec3 water_normal(vec2 uv, float time) {
	float t = time * wave_speed;
	float s = wave_scale;

	// 4 octaves at different scales and directions
	vec2 uv1 = uv * s        + vec2( t * 0.7,  t * 0.4);
	vec2 uv2 = uv * s * 1.9  + vec2(-t * 0.5,  t * 0.9);
	vec2 uv3 = uv * s * 0.4  + vec2( t * 0.3, -t * 0.6);
	vec2 uv4 = uv * s * 3.1  + vec2(-t * 0.8, -t * 0.3);

	float eps = 0.005;

	float n1x = noise(uv1 + vec2(eps, 0.0)) - noise(uv1 - vec2(eps, 0.0));
	float n1y = noise(uv1 + vec2(0.0, eps)) - noise(uv1 - vec2(0.0, eps));

	float n2x = noise(uv2 + vec2(eps, 0.0)) - noise(uv2 - vec2(eps, 0.0));
	float n2y = noise(uv2 + vec2(0.0, eps)) - noise(uv2 - vec2(0.0, eps));

	float n3x = noise(uv3 + vec2(eps, 0.0)) - noise(uv3 - vec2(eps, 0.0));
	float n3y = noise(uv3 + vec2(0.0, eps)) - noise(uv3 - vec2(0.0, eps));

	float n4x = noise(uv4 + vec2(eps, 0.0)) - noise(uv4 - vec2(eps, 0.0));
	float n4y = noise(uv4 + vec2(0.0, eps)) - noise(uv4 - vec2(0.0, eps));

	float dx = (n1x * 1.0 + n2x * 0.6 + n3x * 0.3 + n4x * 0.15) * wave_strength;
	float dy = (n1y * 1.0 + n2y * 0.6 + n3y * 0.3 + n4y * 0.15) * wave_strength;

	// Chop — sharpen the peaks
	float peak = noise(uv1) * noise(uv2);
	dx += (peak - 0.5) * chop * wave_strength;
	dy += (peak - 0.5) * chop * wave_strength;

	return normalize(vec3(dx, 1.0, dy));
}

void fragment() {
	// ── Depth ──────────────────────────────────────────────────────────────────
	float raw_depth  = texture(depth_texture, SCREEN_UV).r;
	vec3  ndc        = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4  view_pos   = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz    /= view_pos.w;
	float water_depth = -view_pos.z + VERTEX.z;
	float depth_blend = clamp(water_depth / depth_scale, 0.0, 1.0);
	// smooth it
	depth_blend = depth_blend * depth_blend;

	// ── Color ──────────────────────────────────────────────────────────────────
	vec4 water_color = mix(shallow_color, deep_color, depth_blend);

	// ── Normals ────────────────────────────────────────────────────────────────
	vec3 norm = water_normal(UV, TIME);

	// ── Refraction ────────────────────────────────────────────────────────────
	vec2 refract_offset = norm.xz * 0.02 * (1.0 - depth_blend * 0.5);
	vec4 refract_color  = texture(screen_texture, SCREEN_UV + refract_offset);

	// ── Caustics (cheap) ───────────────────────────────────────────────────────
	float t = TIME * wave_speed * 0.8;
	float c1 = noise(UV * wave_scale * 2.0 + vec2(t, t * 0.7));
	float c2 = noise(UV * wave_scale * 2.0 + vec2(-t * 0.8, t * 1.1));
	float caustic = pow(c1 * c2, 2.0) * 0.4 * (1.0 - depth_blend);
	water_color.rgb += caustic * vec3(0.1, 0.25, 0.35);

	// ── Fresnel ────────────────────────────────────────────────────────────────
	float ndotv   = clamp(dot(norm, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power);

	// ── Foam ───────────────────────────────────────────────────────────────────
	float foam_blend = clamp(1.0 - water_depth / foam_depth, 0.0, 1.0);
	float foam_noise = noise(UV * 14.0 + vec2(TIME * 0.4, TIME * 0.25));
	foam_blend = foam_blend * step(0.48, foam_noise);

	// ── Horizon haze ───────────────────────────────────────────────────────────
	vec4 horizon = vec4(0.35, 0.6, 0.85, 1.0);
	float horizon_blend = pow(1.0 - clamp(ndotv, 0.0, 1.0), 6.0);
	water_color = mix(water_color, horizon, horizon_blend * 0.5);

	// ── Combine ────────────────────────────────────────────────────────────────
	vec4 final_color = mix(
		mix(refract_color, water_color, water_color.a),
		foam_color,
		foam_blend
	);

	ALBEDO      = final_color.rgb;
	ALPHA       = clamp(water_color.a + fresnel * 0.4 + foam_blend, 0.0, 1.0);
	ROUGHNESS   = roughness;
	METALLIC    = metallic;
	SPECULAR    = specular;
	NORMAL_MAP  = norm * 0.5 + 0.5;
}