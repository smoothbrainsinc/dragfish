shader_type spatial;

uniform vec4 color : source_color;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.01;
uniform float steepness : hint_range(0.0, 1.0) = 0.2;
uniform float sample_distance = 0.01;
uniform sampler2D noise;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float rim_amount : hint_range(0.0, 16.0) = 3.0;

// -- Gerstner wave: displaces a point along a circular path.
// XZ displacement moves particles toward/away from the wave crest (the
// "steepness" pinch), Y displacement is the up/down bob.
vec3 gerstner(vec2 position, vec2 direction, float amplitude, float steep, float frequency, float t) {
	direction = normalize(direction);
	float phase = dot(direction, position) * frequency + t;

	vec3 displacement;
	displacement.y = sin(phase) * amplitude;
	displacement.x = cos(phase) * direction.x * steep;
	displacement.z = cos(phase) * direction.y * steep;
	return displacement;
}

// -- Sums multiple Gerstner waves + a scrolling noise texture for chop.
// position: XZ vertex position (object space)
vec3 wave(vec2 position) {
	float t = TIME;

	vec3 displacement = gerstner(position, vec2(1.0, 0.0),  0.6,  steepness, 1.0, t);
	displacement      += gerstner(position, vec2(-1.0, 1.0), 0.25, steepness, 1.3, t);
	displacement      += gerstner(position, vec2(1.0, 1.0),  0.25, steepness, 1.8, t);

	// noise: mesh is assumed 10x10, so divide by mesh size + 0.5 to map to UV [0,1]
	vec2 noise_uv = position / 10.0 + 0.5;
	noise_uv += normalize(vec2(1.0, 0.0)) * t * 0.05; // scroll noise in wave direction
	float noise_value = texture(noise, noise_uv).r;
	displacement.y += noise_value * noise_intensity;

	return displacement;
}

void vertex() {
	vec3 original_position = VERTEX.xyz;

	// -- Displace the actual vertex
	VERTEX += wave(original_position.xz);

	// -- Finite-difference normal: sample two neighboring points, see where
	// they land after the same wave displacement, and cross the resulting
	// forward/left vectors to get the surface normal of the deformed mesh.
	vec3 forward_pos = original_position + vec3(0.0, 0.0, -1.0) * sample_distance;
	vec3 left_pos     = original_position + vec3(-1.0, 0.0, 0.0) * sample_distance;

	vec3 wave_forward = forward_pos + wave(forward_pos.xz);
	vec3 wave_left    = left_pos + wave(left_pos.xz);

	vec3 forward_vec = wave_forward - VERTEX;
	vec3 left_vec    = wave_left - VERTEX;

	NORMAL = normalize(cross(forward_vec, left_vec));
}

void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_val;
	RIM = rim_amount;
}