shader_type canvas_item;

// Renders wave displacement (XYZ) into RGB of a texture.
// Attach to a ColorRect (set to Full Rect) inside a SubViewport.
// Enable "HDR 2D" on the SubViewport — displacement values exceed 0..1.
// Enable texture repeat on this ColorRect's output — edges break without it.

uniform vec2 mesh_min = vec2(-655.5166, -639.6473);
uniform vec2 mesh_size = vec2(1365.878, 1323.194);
uniform float steepness : hint_range(0.0, 1.0) = 0.2;
uniform sampler2D noise : repeat_enable;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.25;

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

	vec3 displacement = gerstner(position, vec2(1.0, 0.0),  6.0,  steepness, 0.008, t);
	displacement      += gerstner(position, vec2(-1.0, 1.0), 2.5, steepness, 0.010, t);
	displacement      += gerstner(position, vec2(1.0, 1.0),  2.5, steepness, 0.014, t);

	vec2 noise_uv = (position - mesh_min) / mesh_size;
	noise_uv += normalize(vec2(1.0, 0.0)) * t * 0.05;
	float noise_value = texture(noise, noise_uv).r;
	// subtract half the intensity back out so noise doesn't bias the whole
	// mesh up/down when you tune noise_intensity
	displacement.y += noise_value * noise_intensity - noise_intensity * 0.5;

	return displacement;
}

void fragment() {
	// UV [0,1] -> mesh space [-size/2, size/2]
	vec2 position = mesh_min + UV * mesh_size;
	vec3 displacement = wave(position);
	COLOR = vec4(displacement, 1.0);
}