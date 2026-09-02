shader_type canvas_item;

// Renders wave displacement (XYZ) into RGB of a texture.
// Attach to a ColorRect (set to Full Rect) inside a SubViewport.
// Enable "HDR 2D" on the SubViewport — displacement values exceed 0..1.
// Enable texture repeat on this ColorRect's output — edges break without it.

uniform float mesh_size = 1366.0;
uniform float steepness : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D noise : repeat_enable;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.3;

vec3 gerstner(vec2 position, vec2 direction, float amplitude, float steep, float frequency, float t) {
	direction = normalize(direction);
	float phase = dot(direction, position) * frequency + t;

	vec3 displacement;
	displacement.y = sin(phase) * amplitude;
	displacement.x = cos(phase) * direction.x * steep;
	displacement.z = cos(phase) * direction.y * steep;
	return displacement;
}

vec3 wave(vec2 position) {
	float t = TIME;

	vec3 displacement = gerstner(position, vec2(1.0, 0.0),  20.0,  steepness, 1.42, t);
	displacement      += gerstner(position, vec2(-1.0, 1.0), 2.2, steepness, 1.785, t);
	displacement      += gerstner(position, vec2(1.0, 1.0),  11.5, steepness, 1.57, t);

	vec2 noise_uv = position / mesh_size + 2.5;
	noise_uv += normalize(vec2(1.0, 0.0)) * t * 1.25;
	float noise_value = texture(noise, noise_uv).r;
	// subtract half the intensity back out so noise doesn't bias the whole
	// mesh up/down when you tune noise_intensity
	displacement.y += noise_value * noise_intensity - noise_intensity * 5.5;

	return displacement;
}

void fragment() {
	// UV [0,1] -> mesh space [-size/2, size/2]
	vec2 position = (UV - 0.5) * mesh_size;
	vec3 displacement = wave(position);
	COLOR = vec4(displacement, 1.0);
}