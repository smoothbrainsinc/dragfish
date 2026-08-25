shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Archipelago terrain: a flat plane displaced in the vertex shader by the
// solver's bottom texture (no CPU mesh build). Splat by height and slope:
// underwater/beach sand, damp band, grass plateau, rocky steeps. Wetness and
// stranded foam come from tx_ground like the close-up sand shader.

uniform float DOMAIN_SIZE = 2048.0;
uniform float GRID_RES = 2048.0;
uniform sampler2D tx_bottom : filter_linear, repeat_disable;
uniform sampler2D tx_ground : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D lace_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D sand_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocks_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aerial_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float tile_sand : hint_range(2.0, 60.0) = 11.3; // non-round: hides tile-vs-overlay checker beat
uniform float tile_grass : hint_range(2.0, 60.0) = 13.0;
uniform float tile_rocks : hint_range(2.0, 60.0) = 12.0;
uniform float tile_aerial : hint_range(10.0, 400.0) = 120.0;
uniform float tile_lace : hint_range(0.5, 20.0) = 6.0;
uniform float grass_start : hint_range(0.0, 10.0) = 2.2;  // metres above SWL
uniform float grass_full : hint_range(0.0, 12.0) = 4.5;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_world_pos;

void vertex() {
	vec2 suv = (UV * (GRID_RES - 1.0) + 0.5) / GRID_RES;
	float bed = textureLod(tx_bottom, suv, 0.0).r;
	VERTEX.y = bed;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wxz = v_world_pos.xz;
	vec2 suv = clamp(wxz / DOMAIN_SIZE, vec2(0.0), vec2(1.0));

	// geometric normal from the bottom heightfield
	float texel = 1.0 / GRID_RES;
	float step_m = DOMAIN_SIZE / GRID_RES;
	float bl = texture(tx_bottom, suv - vec2(texel, 0.0)).r;
	float br = texture(tx_bottom, suv + vec2(texel, 0.0)).r;
	float bs = texture(tx_bottom, suv - vec2(0.0, texel)).r;
	float bn = texture(tx_bottom, suv + vec2(0.0, texel)).r;
	vec3 gn = normalize(vec3(bl - br, 2.0 * step_m, bs - bn));
	float steep = 1.0 - gn.y; // 0 flat .. ~1 cliff

	float y = v_world_pos.y;

	// splat masks; luma-noise breaks the regular blend band into organic patches
	float blend_noise = dot(texture(aerial_diff, wxz / 37.0).rgb, vec3(0.333));
	float m_grass = smoothstep(grass_start, grass_full, y + (blend_noise - 0.5) * 2.6)
			* (1.0 - smoothstep(0.06, 0.16, steep));
	float m_rock = smoothstep(0.05, 0.14, steep);

	vec3 alb = texture(sand_diff, wxz / tile_sand).rgb;
	vec3 nrm = texture(sand_nor, wxz / tile_sand).rgb;
	vec3 arm = texture(sand_arm, wxz / tile_sand).rgb;
	vec3 g_alb = texture(grass_diff, wxz / tile_grass).rgb;
	alb = mix(alb, g_alb, m_grass);
	nrm = mix(nrm, texture(grass_nor, wxz / tile_grass).rgb, m_grass);
	arm = mix(arm, texture(grass_arm, wxz / tile_grass).rgb, m_grass);
	alb = mix(alb, texture(rocks_diff, wxz / tile_rocks).rgb, m_rock);
	nrm = mix(nrm, texture(rocks_nor, wxz / tile_rocks).rgb, m_rock);
	arm = mix(arm, texture(rocks_arm, wxz / tile_rocks).rgb, m_rock);

	// two-scale brightness variation kills tiling at altitude
	float lum = dot(texture(aerial_diff, wxz / tile_aerial).rgb, vec3(0.333));
	float lum2 = dot(texture(aerial_diff, wxz / (tile_aerial * 4.7)).rgb, vec3(0.333));
	alb *= (0.78 + 0.35 * lum) * (0.85 + 0.3 * lum2);

	// wetness (from the sim ground field): darken, desaturate, gloss.
	// The lace modulation tears the 1 m-resolution wet line into an organic
	// edge instead of a sawtooth of sim texels.
	vec4 ground = texture(tx_ground, suv);
	float wet_edge_noise = texture(lace_tex, wxz / 11.0).r;
	float wetness = clamp(ground.r * (0.6 + 0.7 * wet_edge_noise), 0.0, 1.0) * (1.0 - m_grass * 0.6);
	vec3 wet_alb = alb * 0.42;
	wet_alb = mix(vec3(dot(wet_alb, vec3(0.3333))), wet_alb, 0.72);
	alb = mix(alb, wet_alb, wetness);
	float rough = mix(arm.g, 0.25, wetness);
	float film = smoothstep(0.85, 1.0, wetness);
	rough = mix(rough, 0.05, film);

	// stranded foam arcs on the waterline band
	float stranded = clamp(ground.g, 0.0, 1.0);
	float lace = texture(lace_tex, wxz / tile_lace).r;
	float foam_m = smoothstep(1.0 - stranded, 1.0 - stranded + 0.3, lace) * 0.85;
	alb = mix(alb, vec3(0.82), foam_m);
	rough = mix(rough, 0.85, foam_m);

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = 0.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.0;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength * mix(1.0, 0.3, film);
	NORMAL = normalize((VIEW_MATRIX * vec4(gn, 0.0)).xyz);
}
