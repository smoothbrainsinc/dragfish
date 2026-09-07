					shader_type spatial;



render_mode blend_mix, depth_draw_always, cull_back,

	diffuse_burley, specular_schlick_ggx;



uniform sampler2D screen_texture

	: hint_screen_texture, repeat_disable, filter_linear_mipmap;



uniform sampler2D depth_texture

	: hint_depth_texture, repeat_disable, filter_nearest;



uniform vec3 cor_rasa : source_color = vec3(0.08, 0.36, 0.38);

uniform vec3 cor_profunda : source_color = vec3(0.015, 0.08, 0.12);

uniform vec3 cor_espuma : source_color = vec3(0.82, 0.90, 0.84);



uniform float altura_ondas : hint_range(0.0, 2.0, 0.01) = 0.35;

uniform float velocidade_ondas : hint_range(0.0, 3.0, 0.01) = 0.75;

uniform float escala_ondas : hint_range(0.05, 3.0, 0.01) = 0.55;



uniform float distancia_profundidade

	: hint_range(0.1, 30.0, 0.1) = 7.0;



uniform float largura_espuma

	: hint_range(0.05, 5.0, 0.05) = 1.2;



uniform float forca_refracao

	: hint_range(0.0, 0.1, 0.001) = 0.018;



uniform float transparencia_rasa

	: hint_range(0.0, 1.0, 0.01) = 0.58;



uniform float transparencia_profunda

	: hint_range(0.0, 1.0, 0.01) = 0.94;



varying vec3 posicao_mundo;





float altura_da_onda(vec2 ponto, float tempo) {

	float onda_a = sin(

		(ponto.x * 0.85 + ponto.y * 0.35) * escala_ondas

		+ tempo * velocidade_ondas

	);



	float onda_b = sin(

		(ponto.x * -0.30 + ponto.y * 1.10)

		* escala_ondas * 1.45

		+ tempo * velocidade_ondas * 1.25

	);



	float ondulacao = sin(

		(ponto.x + ponto.y) * escala_ondas * 3.5

		- tempo * velocidade_ondas * 1.8

	);



	return (

		onda_a * 0.52

		+ onda_b * 0.33

		+ ondulacao * 0.15

	) * altura_ondas;

}





float profundidade_linear(

	vec2 uv,

	float depth,

	mat4 matriz_projecao_inversa

) {

	float profundidade_ndc = depth;



	// Forward+ e Mobile usam NDC de 0 a 1.

	// Compatibility (OpenGL) usa NDC de -1 a 1.

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY

	profundidade_ndc = depth * 2.0 - 1.0;

#endif



	vec3 ndc = vec3(uv * 2.0 - 1.0, profundidade_ndc);

	vec4 posicao_view = matriz_projecao_inversa * vec4(ndc, 1.0);

	posicao_view.xyz /= posicao_view.w;



	return -posicao_view.z;

}





float hash_2d(vec2 ponto) {

	return fract(

		sin(dot(ponto, vec2(12.9898, 78.233)))

		* 43758.5453

	);

}





float ruido_suave(vec2 ponto) {

	vec2 celula = floor(ponto);

	vec2 local = fract(ponto);

	vec2 curva = local * local * (3.0 - 2.0 * local);



	float a = hash_2d(celula);

	float b = hash_2d(celula + vec2(1.0, 0.0));

	float c = hash_2d(celula + vec2(0.0, 1.0));

	float d = hash_2d(celula + vec2(1.0, 1.0));



	return mix(

		mix(a, b, curva.x),

		mix(c, d, curva.x),

		curva.y

	);

}





void vertex() {

	vec2 ponto = VERTEX.xz;

	float altura = altura_da_onda(ponto, TIME);



	VERTEX.y += altura;

	posicao_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;



	// Derivada aproximada da onda para inclinar corretamente a normal.

	float passo = 0.12;

	float altura_x = altura_da_onda(

		ponto + vec2(passo, 0.0),

		TIME

	);

	float altura_z = altura_da_onda(

		ponto + vec2(0.0, passo),

		TIME

	);



	NORMAL = normalize(vec3(

		altura - altura_x,

		passo,

		altura - altura_z

	));

}





void fragment() {

	float depth_cena_raw = texture(

		depth_texture,

		SCREEN_UV

	).r;



	float depth_cena = profundidade_linear(

		SCREEN_UV,

		depth_cena_raw,

		INV_PROJECTION_MATRIX

	);



	// No fragment shader espacial, VERTEX está no espaço da câmera.

	float depth_agua = -VERTEX.z;

	float profundidade = max(depth_cena - depth_agua, 0.0);



	float fator_profundo = clamp(

		profundidade / max(distancia_profundidade, 0.001),

		0.0,

		1.0

	);



	float fator_refracao = clamp(

		profundidade / max(largura_espuma, 0.001),

		0.0,

		1.0

	);



	vec2 distorcao = NORMAL.xy

		* forca_refracao

		* fator_refracao;



	vec2 uv_refratada = clamp(

		SCREEN_UV + distorcao,

		vec2(0.001),

		vec2(0.999)

	);



	vec3 cena_refratada = textureLod(

		screen_texture,

		uv_refratada,

		0.0

	).rgb;



	vec3 cor_agua = mix(

		cor_rasa,

		cor_profunda,

		fator_profundo

	);



	float fresnel = pow(

		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),

		5.0

	);



	vec3 resultado = mix(

		cena_refratada * mix(vec3(1.0), cor_rasa * 1.8, 0.28),

		cor_agua,

		0.28 + fator_profundo * 0.62

	);



	// Clareia os ângulos rasantes e reforça o reflexo especular.

	resultado = mix(resultado, cor_rasa * 1.25, fresnel * 0.22);



	// Espuma por proximidade com o fundo e objetos opacos.

	float espuma_margem = 1.0 - smoothstep(

		0.05,

		max(largura_espuma, 0.051),

		profundidade

	);



	vec2 movimento_espuma = vec2(TIME * 0.22, TIME * -0.18);

	float ruido_espuma = ruido_suave(

		posicao_mundo.xz * 2.8 + movimento_espuma

	);



	float espuma = espuma_margem

		* smoothstep(0.34, 0.72, ruido_espuma);



	ALBEDO = mix(resultado, cor_espuma, espuma * 0.88);

	ROUGHNESS = mix(0.075, 0.38, espuma);

	METALLIC = 0.0;

	SPECULAR = 0.92;

	ALPHA = mix(

		transparencia_rasa,

		transparencia_profunda,

		fator_profundo

	);

	EMISSION = cor_espuma * espuma * 0.14;

}
