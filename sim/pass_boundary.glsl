#[compute]
#version 450

// Ghost-cell boundary pass, run in-place on the freshly written state.
// mode 0: closed box (mirror walls on all 4 edges)
// mode 1: west wavemaker + sponge, other edges mirror walls
// Interior threads exit immediately; ghost threads only READ interior cells,
// so the in-place read/write is race-free.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D img_state;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D img_bottom;

layout(push_constant) uniform Push {
	float time;
	float mode;
	float amp;       // primary wave amplitude (m)
	float period;    // primary wave period (s)
	float depth0;    // offshore still-water depth (m), positive
	float ramp_t;    // cold-start ramp duration (s)
	float dx;
	float g;
} pc;


const int RELAX_W = 80; // relaxation-zone width in cells (4 m)

// irregular short-crested sea: 4 components around the primary, each with its
// own approach angle so fronts cross instead of marching in parallel
// (amp fraction, period fraction, phase, direction in radians about +X)
const vec4 COMP_AMP = vec4(1.0, 0.45, 0.30, 0.22);
const vec4 COMP_PER = vec4(1.0, 0.62, 1.53, 0.81);
const vec4 COMP_PHI = vec4(0.0, 2.1, 4.4, 1.3);
const vec4 COMP_ANG = vec4(0.0, 0.31, -0.24, 0.14);

// analytic incident wave component at world position xz.
// Returns (eta, Px, Pz): the FULL depth-integrated momentum vector. Forcing
// hv = 0 for oblique components injects shear at the boundary and blows the
// solver up; the boundary must impose a consistent (eta, P) pair.
vec3 waveComponent(vec2 xz, float ampf, float perf, float phi, float ang) {
	float A = pc.amp * ampf;
	float omega = 6.28318530718 / (pc.period * perf);
	// Eckart dispersion approximation
	float kwn = omega * omega / (pc.g * sqrt(tanh(omega * omega * pc.depth0 / pc.g)));
	vec2 dir = vec2(cos(ang), sin(ang));
	float e = A * sin(omega * pc.time - kwn * dot(dir, xz) + phi);
	return vec3(e, (omega / kwn) * e * dir.x, (omega / kwn) * e * dir.y);
}

// unrolled: dynamic vec4 indexing emits OpVectorExtractDynamic, which some
// pipeline paths reject
vec3 incidentWave(vec2 xz) {
	vec3 s = waveComponent(xz, COMP_AMP.x, COMP_PER.x, COMP_PHI.x, COMP_ANG.x)
		+ waveComponent(xz, COMP_AMP.y, COMP_PER.y, COMP_PHI.y, COMP_ANG.y)
		+ waveComponent(xz, COMP_AMP.z, COMP_PER.z, COMP_PHI.z, COMP_ANG.z)
		+ waveComponent(xz, COMP_AMP.w, COMP_PER.w, COMP_PHI.w, COMP_ANG.w);
	float ramp = min(1.0, pc.time / max(pc.ramp_t, 1e-3));
	return s * ramp;
}

void main() {
	int N = imageSize(img_state).x;
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= N || id.y >= N) {
		return;
	}
	bool gw = id.x < 2;
	bool ge = id.x > N - 3;
	bool gs = id.y < 2;
	bool gn = id.y > N - 3;

	// --- west wavemaker ghosts ---
	if (gw && pc.mode > 0.5) {
		vec3 inc = incidentWave(vec2(float(id.x), float(id.y)) * pc.dx);
		float B = imageLoad(img_bottom, id).r; // = -depth0 offshore
		imageStore(img_state, id, vec4(max(inc.x, B), inc.y, inc.z, 0.0));
		return;
	}

	if (!(gw || ge || gs || gn)) {
		if (pc.mode < 0.5) {
			return;
		}
		vec4 q = imageLoad(img_state, id);
		float B = imageLoad(img_bottom, id).r;
		bool touched = false;
		// --- west relaxation zone: pull the state toward the analytic incident
		// wave, strongest at the boundary. Generates the incoming sea AND
		// absorbs outgoing waves.
		if (id.x < 2 + RELAX_W) {
			float D = float(id.x - 2);
			float wgt = 1.0 - D / float(RELAX_W);
			float alpha = 0.06 * wgt * wgt; // per-substep pull, ~33 ms tau at the edge
			vec3 inc = incidentWave(vec2(float(id.x), float(id.y)) * pc.dx);
			q.x = mix(q.x, max(inc.x, B), alpha);
			q.y = mix(q.y, inc.y, alpha);
			q.z = mix(q.z, inc.z, alpha);
			q.w *= 1.0 - alpha;
			touched = true;
		}
		// --- ocean mode: absorb strips toward rest at east/north/south so map
		// edges never build standing reflections.
		if (pc.mode > 1.5) {
			int de = min(N - 3 - id.x, min(id.y - 2, N - 3 - id.y));
			if (de < 60) {
				float wgt2 = 1.0 - float(de) / 60.0;
				float a2 = 0.05 * wgt2 * wgt2;
				q.x = mix(q.x, max(B, 0.0), a2);
				q.y = mix(q.y, 0.0, a2);
				q.z = mix(q.z, 0.0, a2);
				q.w *= 1.0 - a2;
				touched = true;
			}
		}
		if (touched) {
			imageStore(img_state, id, q);
		}
		return;
	}

	// --- mirror walls ---
	ivec2 src = id;
	vec4 flip = vec4(1.0);
	if (gw) {
		src.x = 3 - id.x;
		flip.y = -1.0;
	} else if (ge) {
		src.x = 2 * N - 5 - id.x;
		flip.y = -1.0;
	}
	if (gs) {
		src.y = 3 - id.y;
		flip.z = -1.0;
	} else if (gn) {
		src.y = 2 * N - 5 - id.y;
		flip.z = -1.0;
	}
	vec4 q = imageLoad(img_state, src);
	float B_src = imageLoad(img_bottom, src).r;
	float B_dst = imageLoad(img_bottom, id).r;
	float h = max(q.x - B_src, 0.0);
	imageStore(img_state, id, vec4(B_dst + h, q.y * flip.y, q.z * flip.z, q.w));
}
