shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4  shallow_color : source_color = vec4(0.05, 0.45, 0.65, 0.72);
uniform vec4  deep_color    : source_color = vec4(0.0,  0.08, 0.28, 0.97);
uniform float depth_scale   : hint_range(0.0, 200.0) = 30.0;
uniform float roughness      : hint_range(0.0, 1.0) = 0.05;
uniform float metallic       : hint_range(0.0, 1.0) = 0.0;
uniform float specular       : hint_range(0.0, 1.0) = 1.0;
uniform float wave_height    : hint_range(0.0, 2.0) = 0.25;
uniform float wave_speed     : hint_range(0.0, 4.0) = 1.0;
uniform float chop           : hint_range(0.0, 1.0) = 0.5;
uniform float foam_depth     : hint_range(0.0, 5.0) = 1.2;
uniform vec4  foam_color     : source_color = vec4(0.92, 0.96, 1.0, 1.0);

// Lake floor depth map - rendered from above, white=deep, black=shallow
uniform sampler2D lake_depth_map : hint_default_black, filter_linear;
// World-space XZ bounds of the depth map coverage
uniform vec2 lake_origin = vec2(-750.0, -750.0); // bottom-left XZ corner
uniform vec2 lake_size   = vec2(1500.0, 1500.0); // total XZ extents
// World Y of water surface and maximum depth below it
uniform float water_surface_y : hint_range(-100.0, 100.0) = -5.0;
uniform float max_depth       : hint_range(1.0, 300.0) = 150.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying vec3 world_pos;

vec3 gerstner_wave(vec4 w, vec2 xz, float time, inout vec3 tangent, inout vec3 binormal) {
	float wavelength = w.z;
	float steepness  = w.w * chop;
	vec2  dir        = normalize(w.xy);
	float k          = 2.0 * 3.14159 / wavelength;
	float c          = sqrt(9.8 / k) * wave_speed;
	float f          = k * (dot(dir, xz) - c * time);
	float a          = steepness / k;
	tangent += vec3(
		-dir.x * dir.x * steepness * sin(f),
		dir.x * steepness * cos(f),
		-dir.x * dir.y * steepness * sin(f)
	);
	binormal += vec3(
		-dir.x * dir.y * steepness * sin(f),
		dir.y * steepness * cos(f),
		-dir.y * dir.y * steepness * sin(f)
	);
	return vec3(
		dir.x * a * cos(f),
		a * sin(f) * wave_height,
		dir.y * a * cos(f)
	);
}

void vertex() {
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	world_pos     = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 tangent  = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 offset   = vec3(0.0);

	offset += gerstner_wave(vec4( 1.0,  0.2, 18.0, 0.6), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 0.9,  0.3, 11.0, 0.5), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 0.8,  0.4,  7.0, 0.4), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 1.0, -0.2,  5.0, 0.5), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 0.7,  0.5,  3.5, 0.3), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 0.9, -0.3,  2.5, 0.3), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 0.8,  0.2,  1.8, 0.2), world_xz, TIME, tangent, binormal);
	offset += gerstner_wave(vec4( 1.0,  0.1,  1.2, 0.2), world_xz, TIME, tangent, binormal);

	NORMAL = normalize(cross(binormal, tangent));
	UV     = world_xz * 0.01;
}

void fragment() {
	// Project world XZ into lake depth map UV space
	vec2 lake_uv = (world_pos.xz - lake_origin) / lake_size;

	// Sample depth map: white = deep (floor far below), black = shallow (floor near surface)
	float encoded_depth = texture(lake_depth_map, lake_uv).r;

	// Convert to actual world-space water depth in metres
	float water_depth = encoded_depth * max_depth;

	float depth_blend = clamp(water_depth / depth_scale, 0.0, 1.0);
	depth_blend = depth_blend * depth_blend;

	vec4 water_color = mix(shallow_color, deep_color, depth_blend);

	float ndotv   = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0);

	vec2 refract_offset = NORMAL.xz * 0.015;
	vec4 refract_color  = texture(screen_texture, SCREEN_UV + refract_offset);

	float foam_blend = clamp(1.0 - water_depth / foam_depth, 0.0, 1.0);
	foam_blend = pow(foam_blend, 2.0);

	vec4 final_color = mix(
		mix(refract_color, water_color, water_color.a),
		foam_color,
		foam_blend
	);

	ALBEDO    = final_color.rgb;
	ALPHA     = clamp(water_color.a + fresnel * 0.5 + foam_blend, 0.0, 1.0);
	ROUGHNESS = roughness;
	METALLIC  = metallic;
	SPECULAR  = specular;
}