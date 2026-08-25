// Beach terrain shader: layered PBR sand driven by the shallow-water sim.
// Layers: coast_sand_01 base, aerial_beach_01 large-scale variation,
// coast_sand_rocks_02 on steep/high ground, damp_sand in the mid-wet band.
// Sim inputs: tx_ground (r=wetness, g=stranded foam), tx_state (r=free surface w),
// caustics_tex + lace_tex helpers. All sim textures may be black early on;
// every effect degrades to a no-op in that case.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;


// --- world / sim ---
uniform float domain_size = 30.4;
uniform sampler2D tx_ground : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D tx_state : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D caustics_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D lace_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

// --- PBR texture sets (arm = AO/rough/metal packed: r=AO, g=rough) ---
uniform sampler2D sand_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aerial_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D damp_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D damp_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D damp_arm : filter_linear_mipmap_anisotropic, repeat_enable;

// --- tiling (meters per texture repeat) ---
uniform float tile_sand : hint_range(1.0, 60.0) = 15.0;
uniform float tile_aerial : hint_range(2.0, 120.0) = 30.0;
uniform float tile_rocks : hint_range(1.0, 60.0) = 9.0;
uniform float tile_damp : hint_range(1.0, 60.0) = 11.0;
uniform float tile_lace : hint_range(0.1, 8.0) = 0.9;
uniform float tile_caustic_a : hint_range(0.2, 10.0) = 1.7;
uniform float tile_caustic_b : hint_range(0.2, 10.0) = 2.3;

// --- tunables ---
uniform float aerial_mix : hint_range(0.0, 1.0) = 0.25;
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.18;
uniform float rock_slope_full : hint_range(0.0, 1.0) = 0.45;
uniform float rock_height_start : hint_range(-1.0, 3.0) = 0.5;
uniform float rock_height_full : hint_range(-1.0, 3.0) = 0.9;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.9;
uniform float caustic_strength : hint_range(0.0, 4.0) = 1.4;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wxz = v_world_pos.xz;
	vec4 ground = texture(tx_ground, wxz / domain_size);
	float wetness = clamp(ground.r, 0.0, 1.0);
	float stranded = clamp(ground.g, 0.0, 1.0);

	// Base sand.
	vec2 uv_s = wxz / tile_sand;
	vec3 alb = texture(sand_diff, uv_s).rgb;
	vec3 nrm = texture(sand_nor, uv_s).rgb;
	vec3 arm = texture(sand_arm, uv_s).rgb;

	// Large-scale variation: aerial_beach_01 luma normalized around mid grey,
	// so the overlay redistributes brightness without shifting the average.
	float aer_l = dot(texture(aerial_diff, wxz / tile_aerial).rgb, vec3(0.2126, 0.7152, 0.0722));
	alb *= mix(1.0, aer_l * 2.0, aerial_mix);

	// Rocky blend near boulders: steep geometry or above the height band.
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float rock_m = clamp(
			smoothstep(rock_slope_start, rock_slope_full, slope)
			+ smoothstep(rock_height_start, rock_height_full, v_world_pos.y),
			0.0, 1.0);
	if (rock_m > 0.001) {
		vec2 uv_r = wxz / tile_rocks;
		alb = mix(alb, texture(rocks_diff, uv_r).rgb, rock_m);
		nrm = mix(nrm, texture(rocks_nor, uv_r).rgb, rock_m);
		arm = mix(arm, texture(rocks_arm, uv_r).rgb, rock_m);
	}

	// Damp sand in the mid-wetness band (suppressed on rock).
	float damp_m = smoothstep(0.3, 0.7, wetness) * (1.0 - rock_m * 0.7);
	if (damp_m > 0.001) {
		vec2 uv_d = wxz / tile_damp;
		alb = mix(alb, texture(damp_diff, uv_d).rgb, damp_m);
		nrm = mix(nrm, texture(damp_nor, uv_d).rgb, damp_m);
		arm = mix(arm, texture(damp_arm, uv_d).rgb, damp_m);
	}

	// Wetness: darken + saturate, drop roughness; near-saturated wetness forms
	// a mirror film (SSR then reflects sky) and flattens the normal map.
	// darken ~2.4x with slight desaturation (albedo-squared turns this sand
	// mahogany-red; the references show grayish dark brown wet sand)
	vec3 wet_alb = alb * 0.42;
	wet_alb = mix(vec3(dot(wet_alb, vec3(0.3333))), wet_alb, 0.72);
	alb = mix(alb, wet_alb, wetness);
	float rough = mix(arm.g, 0.25, wetness);
	float film = smoothstep(0.85, 1.0, wetness);
	rough = mix(rough, 0.04, film);
	float n_depth = normal_strength * mix(1.0, 0.25, film);

	// Stranded foam: Voronoi black-point erosion of lace_tex by foam amount.
	// lace_tex black or stranded 0 -> mask 0 (safe default).
	float lace = texture(lace_tex, wxz / tile_lace).r;
	float foam_m = smoothstep(1.0 - stranded, 1.0 - stranded + 0.3, lace) * foam_strength;
	alb = mix(alb, vec3(0.82), foam_m);
	rough = mix(rough, 0.85, foam_m);

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.0;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = n_depth;
}

void light() {
	// Custom light() replaces the built-in per-light pass, so redo a compact
	// Lambert + GGX before adding the caustic term.
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndotl * ATTENUATION * LIGHT_COLOR / PI;

	vec3 h = normalize(VIEW + LIGHT);
	float ndoth = clamp(dot(NORMAL, h), 0.0, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float dd = ndoth * ndoth * (a2 - 1.0) + 1.0;
	float dist_ggx = a2 / (PI * dd * dd);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(h, VIEW), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += dist_ggx * fres * 0.25 * ndotl * ATTENUATION * LIGHT_COLOR;

	// Underwater caustics: two counter-drifting samples, min() combine,
	// +-1 texel chromatic fringe, gated + attenuated by local water depth.
	float wsurf = texture(tx_state, v_world_pos.xz / domain_size).r;
	float depth = max(wsurf - v_world_pos.y, 0.0);
	float inten = smoothstep(0.02, 0.15, depth) * exp(-1.5 * depth) * caustic_strength;
	if (inten > 0.0005) {
		vec2 wxz = v_world_pos.xz;
		vec2 px = 1.0 / vec2(textureSize(caustics_tex, 0));
		vec2 uv1 = wxz / tile_caustic_a + vec2(TIME * 0.021, TIME * -0.013);
		vec2 uv2 = wxz / tile_caustic_b + vec2(TIME * -0.017, TIME * 0.011);
		vec2 ox = vec2(px.x, 0.0);
		float cr = min(texture(caustics_tex, uv1 + ox).r, texture(caustics_tex, uv2 - ox).r);
		float cg = min(texture(caustics_tex, uv1).g, texture(caustics_tex, uv2).g);
		float cb = min(texture(caustics_tex, uv1 - ox).b, texture(caustics_tex, uv2 + ox).b);
		// caustics_tex black -> c = 0 -> no-op.
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * ATTENUATION * inten * vec3(cr, cg, cb);
	}
}
