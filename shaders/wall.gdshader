// Quay wall shader: world-space triplanar medieval_blocks_02 with a
// noise-broken mossy_sandstone band near the waterline. Wetness comes from
// tx_ground: r = wetness at the wall base, b = wave impact, which wets the
// wall upward as splash. tx_ground may be black early on -> dry wall.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// --- world / sim ---
uniform float domain_size = 30.4;
uniform float wall_base_x = 22.0; // sample tx_ground just seaward of the face
uniform sampler2D tx_ground : hint_default_black, filter_linear, repeat_disable;

// --- PBR texture sets (arm: r=AO, g=rough) ---
uniform sampler2D blocks_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D blocks_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D blocks_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_arm : filter_linear_mipmap_anisotropic, repeat_enable;

// --- tunables ---
uniform float tile_blocks : hint_range(0.5, 8.0) = 1.5; // blocks tile is 1.5 m
uniform float tile_moss : hint_range(0.5, 8.0) = 2.0;
uniform float moss_band_lo : hint_range(-1.0, 2.0) = 0.05;
uniform float moss_band_hi : hint_range(-1.0, 2.0) = 0.55;
uniform float moss_edge_noise : hint_range(0.0, 1.0) = 0.35;
uniform float wet_darken : hint_range(0.0, 1.0) = 0.45;
uniform float wet_rough : hint_range(0.0, 1.0) = 0.12;
uniform float splash_gain : hint_range(0.0, 10.0) = 3.0;
uniform float splash_bottom : hint_range(0.0, 3.0) = 0.3;
uniform float splash_top : hint_range(0.0, 5.0) = 2.2;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

// Triplanar tangent-space normals swizzled straight into world space
// (per-axis basis, blended by the same weights).
vec3 tri_normal_ws(sampler2D tex, vec3 p, vec3 w, vec3 n) {
	vec3 tx = texture(tex, p.zy).rgb * 2.0 - 1.0;
	vec3 ty = texture(tex, p.xz).rgb * 2.0 - 1.0;
	vec3 tz = texture(tex, p.xy).rgb * 2.0 - 1.0;
	float sx = n.x >= 0.0 ? 1.0 : -1.0;
	float sy = n.y >= 0.0 ? 1.0 : -1.0;
	float sz = n.z >= 0.0 ? 1.0 : -1.0;
	vec3 nx = vec3(tx.z * sx, tx.y, tx.x); // U -> Z, V -> Y
	vec3 ny = vec3(ty.x, ty.z * sy, ty.y); // U -> X, V -> Z
	vec3 nz = vec3(tz.x, tz.y, tz.z * sz); // U -> X, V -> Y
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}

void fragment() {
	vec3 wp = v_world_pos;
	vec3 gn = normalize(v_world_normal);
	vec3 w = tri_weights(gn);

	vec3 p_blocks = wp / tile_blocks;
	vec3 alb = tri_sample(blocks_diff, p_blocks, w).rgb;
	vec3 arm = tri_sample(blocks_arm, p_blocks, w).rgb;
	vec3 n_ws = tri_normal_ws(blocks_nor, p_blocks, w, gn);

	// Moss band near the waterline, edges broken by the block luma as noise.
	float noise = dot(alb, vec3(0.2126, 0.7152, 0.0722)) - 0.5;
	float yb = wp.y + noise * moss_edge_noise;
	float moss_m = smoothstep(moss_band_lo, moss_band_lo + 0.12, yb)
			* (1.0 - smoothstep(moss_band_hi - 0.15, moss_band_hi, yb));
	if (moss_m > 0.001) {
		vec3 p_moss = wp / tile_moss;
		alb = mix(alb, tri_sample(moss_diff, p_moss, w).rgb, moss_m);
		arm = mix(arm, tri_sample(moss_arm, p_moss, w).rgb, moss_m);
		n_ws = normalize(mix(n_ws, tri_normal_ws(moss_nor, p_moss, w, gn), moss_m));
	}

	// Wetness: ground wetness at the wall base plus impact splash climbing up.
	vec2 guv = vec2(min(wp.x, wall_base_x - 0.15), wp.z) / domain_size;
	vec4 ground = texture(tx_ground, guv);
	float splash = clamp(ground.b * splash_gain, 0.0, 1.0)
			* (1.0 - smoothstep(splash_bottom, splash_top, wp.y));
	float wet = max(clamp(ground.r, 0.0, 1.0), splash);

	alb *= mix(1.0, wet_darken, wet);
	float rough = mix(arm.g, wet_rough, wet);

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.0;
	// Triplanar UVs don't match mesh tangents, so write the perturbed normal
	// in view space directly instead of NORMAL_MAP.
	vec3 n_final = normalize(mix(gn, n_ws, clamp(normal_strength, 0.0, 1.0)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_final, 0.0)).xyz);
}
