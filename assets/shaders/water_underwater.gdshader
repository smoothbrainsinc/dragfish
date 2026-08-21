// ============================================================
//  UNDERWATER SCREEN-SPACE SHADER — Godot 4.x
//
//  SETUP:
//    1. Create a large MeshInstance3D using a BoxMesh or
//       QuadMesh scaled to fully surround/enclose the camera
//       (e.g. a huge cube, ~2000x2000x2000 units).
//    2. Apply a ShaderMaterial using this shader.
//    3. Keep sea_height / sea_choppy / sea_speed / sea_freq
//       EXACTLY in sync with your water_surface.gdshader.
//    4. Tune height_offset so the cut-off matches the surface.
//
//  HOW IT WORKS:
//    Each fragment reconstructs the REAL scene position under
//    it from the depth buffer (not the box mesh's own surface
//    position). If that position is above the water surface
//    (computed from the same wave math as the surface shader),
//    the pixel is discarded. Below the surface, Beer-Lambert
//    absorption + refraction wobble is applied, with a near-field
//    haze floor so close-range geometry never reads fully clear.
// ============================================================
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

// ---- Wave params: MUST match water_surface.gdshader ----
uniform float sea_height : hint_range(0.0, 5.0)  = 1.3;
uniform float sea_choppy : hint_range(0.0, 10.0) = 4.0;
uniform float sea_speed  : hint_range(0.0, 5.0)  = 1.5;
uniform float sea_freq   : hint_range(0.0, 0.5)  = 0.08;
uniform float height_offset = 0.0;

// ---- Underwater look ----
uniform vec3  underwater_color    : source_color = vec3(0.10, 0.26, 0.13);
uniform float absorption_strength : hint_range(0.0, 2.0) = 0.15;
uniform float max_clarity         : hint_range(0.0, 1.0) = 0.55;
// max_clarity is the highest transmittance ever allowed, even at
// zero thickness. Lower = hazier close to camera. 1.0 = old behavior
// (clear glass up close). Start around 0.5-0.6 to match murky lake refs.

// ---- Screen wobble / refraction ----
uniform float refraction_amount : hint_range(0.0, 0.015) = 0.004;
uniform float refraction_speed  : hint_range(0.0, 3.0)   = 0.7;

// ---- Surface alignment fudge ----
uniform float water_level_fudge : hint_range(-1.5, 1.5) = 0.0;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture,  filter_linear_mipmap;

// ---- Constants ----
const int  ITER_GEOMETRY = 3;
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

// ---- Varying ----
varying vec3 world_pos;

// ============================================================
//  NOISE & WAVE FUNCTIONS  (mirrors surface shader)
// ============================================================

float hash12(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return -1.0 + 2.0 * mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float sea_octave(vec2 uv, float choppy) {
	uv += noise(uv);
	vec2 wv  = 1.0 - abs(sin(uv));
	vec2 swv = abs(cos(uv));
	wv = mix(wv, swv, wv);
	return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

// ============================================================
//  VERTEX
// ============================================================

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ============================================================
//  FRAGMENT
// ============================================================

void fragment() {
	
	float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;

	vec3 camera_world_pos = INV_VIEW_MATRIX[3].xyz;

	vec2 cam_uv = camera_world_pos.xz;
	cam_uv.x   *= 0.75;
	float cam_freq   = sea_freq;
	float cam_amp    = sea_height;
	float cam_chop   = sea_choppy;
	float cam_height = 0.0;
	for (int i = 0; i < ITER_GEOMETRY; i++) {
		float d  = sea_octave((cam_uv + TIME * sea_speed) * cam_freq, cam_chop);
		d       += sea_octave((cam_uv - TIME * sea_speed) * cam_freq, cam_chop);
		cam_height += d * cam_amp;
		cam_uv   *= octave_m;
		cam_freq *= 1.9;
		cam_amp  *= 0.22;
		cam_chop  = mix(cam_chop, 1.0, 0.2);
	}
	float surface_y_at_camera = cam_height + height_offset + water_level_fudge;
	bool camera_is_underwater = camera_world_pos.y < surface_y_at_camera;

	if (raw_depth >= 0.999) {
		if (camera_is_underwater) {
			ALBEDO = underwater_color;
			ALPHA = 0.95;
		} else {
			discard;
		}
	} else {
		vec3 ndc_discard = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc_discard.z = raw_depth * 2.0 - 1.0;
#endif
		vec4 view_space_discard = INV_PROJECTION_MATRIX * vec4(ndc_discard, 1.0);
		view_space_discard.xyz /= view_space_discard.w;
		vec3 scene_world_pos = (INV_VIEW_MATRIX * vec4(view_space_discard.xyz, 1.0)).xyz;

		vec2 uv   = scene_world_pos.xz;
		uv.x     *= 0.75;
		float freq = sea_freq;
		float amp  = sea_height;
		float chop = sea_choppy;
		float height = 0.0;
		for (int i = 0; i < ITER_GEOMETRY; i++) {
			float d  = sea_octave((uv + TIME * sea_speed) * freq, chop);
			d       += sea_octave((uv - TIME * sea_speed) * freq, chop);
			height  += d * amp;
			uv      *= octave_m;
			freq    *= 1.9;
			amp     *= 0.22;
			chop     = mix(chop, 1.0, 0.2);
		}

		float surface_y = height + height_offset + water_level_fudge;

		if (scene_world_pos.y > surface_y) {
			discard;
		} else {
			vec2 uv_screen = SCREEN_UV;
			vec2 noise_dir = vec2(
				noise(uv_screen * 12.0 + TIME * refraction_speed * vec2(1.0, 0.4)),
				noise(uv_screen * 12.0 + TIME * refraction_speed * vec2(0.6, 1.0))
			) * 2.0 - 1.0;

			vec2 uv_distorted = uv_screen + noise_dir * refraction_amount;
			vec3 scene_color  = texture(SCREEN_TEXTURE, uv_distorted).rgb;

			float thickness = length(scene_world_pos - camera_world_pos);

			// --- Beer-Lambert absorption with near-field haze floor
			float transmittance = exp(-thickness * absorption_strength);
			transmittance = min(transmittance, max_clarity);
			vec3  final_color = mix(underwater_color, scene_color, transmittance);

			ALBEDO = final_color;
			ALPHA = 0.95; 
		}
	}
}