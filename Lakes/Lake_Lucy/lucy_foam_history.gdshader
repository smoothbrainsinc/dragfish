shader_type canvas_item;

// Attach the SAME shader to both History A and History B ColorRects
// (Full Rect, Local to Scene ON). Each SubViewport needs HDR2D enabled.
// Fades the previous frame's foam and combines with fresh foam so foam
// persists and dissipates instead of popping with the wave.

uniform sampler2D current_foam; // always points at the foam_calc SubViewport
uniform sampler2D history_foam; // points at the OTHER history buffer
uniform float delta = 0.016;
uniform float fade_rate = 3.5;

void fragment() {
	float current = texture(current_foam, UV).r;
	float history = texture(history_foam, UV).r;

	history *= exp(-fade_rate * delta);
	history = max(history, 0.0);

	float result = max(current, history);
	COLOR = vec4(result, result, result, 1.0);
}