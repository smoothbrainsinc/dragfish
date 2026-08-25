shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Standalone deep-water ocean: 8 Gerstner (trochoidal) wave components with
// full horizontal displacement, analytic normals, and Jacobian whitecaps.
// No simulation textures required; everything derives from the uniforms below.
//
// Background: Gerstner's 1802 trochoidal wave is the exact solution for a
// deep-water surface particle moving in a circle. The GPU form used here
// follows Finch, "Effective Water Simulation from Physical Models",
// GPU Gems 1, chapter 1. Deep-water dispersion ties speed to wavelength:
// omega = sqrt(g * k), so long waves travel faster, which is what makes a
// multi-component sum read as a real sea instead of a looping pattern.
//
// The 8 components are derived from a few art-directable knobs: a base
// wavelength with a geometric series below it, a wind direction with a
// directional spread, and a global steepness. Steepness Q is the trochoid
// sharpness; the sum of Q_i * k_i * A_i must stay below 1 or crests loop
// over themselves (the shader clamps this).

// --- sea state ---
uniform float base_wavelength : hint_range(10.0, 400.0) = 90.0; // longest component (m)
uniform float amplitude : hint_range(0.0, 8.0) = 1.1;           // longest component amplitude (m)
uniform float steepness : hint_range(0.0, 1.2) = 0.75;          // global trochoid sharpness
uniform float wind_dir_deg : hint_range(-180.0, 180.0) = 0.0;   // where waves travel toward
uniform float spread_deg : hint_range(0.0, 60.0) = 28.0;        // directional spread of components
uniform float speed_scale : hint_range(0.0, 3.0) = 1.0;         // 1 = physical dispersion speed
uniform float amp_falloff : hint_range(0.4, 1.0) = 0.72;        // amplitude ratio per component

// --- shading ---
uniform vec3 water_color : source_color = vec3(0.018, 0.075, 0.105);
uniform vec3 sss_color : source_color = vec3(0.05, 0.28, 0.24); // thin-crest light bleed
uniform float roughness_base : hint_range(0.0, 0.3) = 0.06;
uniform float foam_threshold : hint_range(0.0, 1.5) = 0.62;     // Jacobian value where whitecaps start
uniform float foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec3 foam_albedo : source_color = vec3(0.78, 0.80, 0.80);
uniform float detail_normal_strength : hint_range(0.0, 2.0) = 0.4;
uniform float detail_scale : hint_range(0.5, 30.0) = 6.5;       // metres per ripple tile
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D lace_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 v_world_pos;    // displaced world position
varying vec2 v_undisp_xz;    // pre-displacement grid position (stable UVs)

// fixed per-component variation (direction offset within the spread, phase)
const vec4 DIR_JITTER_A = vec4(0.00, 0.83, -0.61, 0.37);
const vec4 DIR_JITTER_B = vec4(-0.92, 0.18, 0.66, -0.29);
const vec4 PHASE_A = vec4(0.0, 2.4, 4.1, 1.2);
const vec4 PHASE_B = vec4(3.3, 5.0, 0.7, 2.0);

// accumulate one Gerstner component; returns displacement, adds derivatives
vec3 gerstner(vec2 xz, float t, float wl, float amp, float q_over, vec2 dir,
		float phase, inout vec3 dPdx, inout vec3 dPdz, inout float jac_acc) {
	float k = 6.28318530718 / wl;
	float c = sqrt(9.81 / k) * speed_scale; // deep-water phase speed
	float ph = k * dot(dir, xz) - k * c * t + phase;
	float q = q_over; // per-component steepness share, pre-normalized
	float s = sin(ph);
	float co = cos(ph);
	// derivatives for normal + Jacobian (Finch, GPU Gems 1, eq. 10-12)
	float wa = k * amp;
	dPdx += vec3(-q * dir.x * dir.x * wa * s, dir.x * wa * co, -q * dir.x * dir.y * wa * s);
	dPdz += vec3(-q * dir.x * dir.y * wa * s, dir.y * wa * co, -q * dir.y * dir.y * wa * s);
	jac_acc += q * wa * s;
	return vec3(q * amp * dir.x * co, amp * s, q * amp * dir.y * co);
}

// build the 8 components from the sea-state uniforms; i is unrolled manually
void ocean(vec2 xz, float t, out vec3 disp, out vec3 n, out float jac) {
	disp = vec3(0.0);
	vec3 dPdx = vec3(0.0);
	vec3 dPdz = vec3(0.0);
	float jac_acc = 0.0;
	float wind = radians(wind_dir_deg);
	float spread = radians(spread_deg);

	// geometric series of wavelengths; steepness normalized so the trochoid
	// never self-intersects: sum(q_i k_i A_i) <= steepness (clamped to 1)
	float wl = base_wavelength;
	float amp = amplitude;
	float q_total = min(steepness, 1.0);
	float q_each = q_total / 8.0;

	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_A.x), sin(wind + spread * DIR_JITTER_A.x));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_A.x, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_A.y), sin(wind + spread * DIR_JITTER_A.y));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_A.y, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_A.z), sin(wind + spread * DIR_JITTER_A.z));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_A.z, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_A.w), sin(wind + spread * DIR_JITTER_A.w));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_A.w, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_B.x), sin(wind + spread * DIR_JITTER_B.x));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_B.x, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_B.y), sin(wind + spread * DIR_JITTER_B.y));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_B.y, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_B.z), sin(wind + spread * DIR_JITTER_B.z));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_B.z, dPdx, dPdz, jac_acc);
	  wl *= 0.62; amp *= amp_falloff; }
	{ vec2 d = vec2(cos(wind + spread * DIR_JITTER_B.w), sin(wind + spread * DIR_JITTER_B.w));
	  disp += gerstner(xz, t, wl, amp, q_each / max(6.28318 / wl * amp, 1e-4), d, PHASE_B.w, dPdx, dPdz, jac_acc); }

	n = normalize(cross(vec3(0.0, dPdz.y, 1.0 + dPdz.z), vec3(1.0 + dPdx.x, dPdx.y, 0.0)));
	// horizontal-compression Jacobian proxy: 1 at rest, small on pinched crests
	jac = 1.0 - jac_acc;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_undisp_xz = wp.xz;
	vec3 disp;
	vec3 n_unused;
	float j_unused;
	ocean(wp.xz, TIME, disp, n_unused, j_unused);
	VERTEX += disp;
	v_world_pos = wp + disp;
}

void fragment() {
	// per-pixel normal + Jacobian: crisper than vertex interpolation
	vec3 disp;
	vec3 n_world;
	float jac;
	ocean(v_undisp_xz, TIME, disp, n_world, jac);

	// detail ripples, wind-aligned, two scales
	vec2 duv = v_undisp_xz / detail_scale;
	vec3 dn1 = texture(detail_normal_tex, duv).rgb * 2.0 - 1.0;
	vec3 dn2 = texture(detail_normal_tex, duv * 3.7 + vec2(0.31, 0.77)).rgb * 2.0 - 1.0;
	vec2 dxy = (dn1.xy + dn2.xy * 0.5) * detail_normal_strength;
	n_world = normalize(vec3(n_world.x + dxy.x, n_world.y, n_world.z + dxy.y));

	// whitecaps where the trochoid pinches (low Jacobian), torn by the lace
	float cap = smoothstep(foam_threshold, foam_threshold - 0.35, jac) * foam_amount;
	float lace = texture(lace_tex, v_undisp_xz / 9.0).r;
	float foam = smoothstep(1.0 - cap, 1.0 - cap + 0.42, lace) * min(cap * 1.4, 0.95);

	// thin-crest light bleed: crests between the eye and the sun glow green
	float crest = clamp(disp.y / max(amplitude, 1e-3), 0.0, 1.0);
	vec3 base = mix(water_color, sss_color, crest * crest * 0.35);

	ALBEDO = mix(base, foam_albedo, foam);
	ROUGHNESS = mix(roughness_base, 0.75, foam);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}
