shader_type canvas_item;

// Attach to a ColorRect (Full Rect, Local to Scene ON) inside a SubViewport.
// Detects where the displaced wave surface is compressing (crests folding)
// via the Jacobian determinant of the XZ displacement field, and writes
// a foam mask to the red channel.

uniform sampler2D displacement_map; // ViewportTexture from displacement SubViewport
uniform vec2 texture_size = vec2(1024.0, 1024.0);
uniform vec2 mesh_min = vec2(-655.5166, -639.6473);
uniform vec2 mesh_size = vec2(1365.878, 1323.194);
uniform float compression_low : hint_range(0.0, 1.0) = 0.0;
uniform float compression_high : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	vec2 texel = 1.0 / texture_size;
	vec2 sampling_distance = texel * mesh_size;
vec2 position = mesh_min + UV * mesh_size;

	vec2 disp_current = texture(displacement_map, UV).xz;
	vec2 disp_right    = texture(displacement_map, UV + vec2(texel.x, 0.0)).xz;
	vec2 disp_down     = texture(displacement_map, UV + vec2(0.0, texel.y)).xz;

	vec2 wave_current = position + disp_current;
	vec2 wave_right    = position + vec2(sampling_distance.x, 0.0) + disp_right;
	vec2 wave_down     = position + vec2(0.0, sampling_distance.y) + disp_down;

	vec2 dx = wave_right - wave_current;
	vec2 dz = wave_down - wave_current;

	float cross_z = cross(vec3(dx, 0.0), vec3(dz, 0.0)).z;
	float area = sampling_distance.x * sampling_distance.y;
	float jacobian = cross_z / area;

	float compression = 1.0 - jacobian;
	compression = smoothstep(compression_low, compression_high, compression);

	COLOR = vec4(compression, compression, compression, 1.0);
}