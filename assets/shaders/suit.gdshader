shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D suit_mask : hint_default_black, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 suit_color : source_color = vec3(0.8, 0.3, 0.2);
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform int pattern = 0;
uniform vec3 pattern_color : source_color = vec3(0.9, 0.72, 0.08);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float stripe(float x) {
	float tri = abs(fract(x) - 0.5) * 2.0;
	float w = fwidth(x) * 1.5 + 0.0001;
	return smoothstep(0.5 - w, 0.5 + w, tri);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec2 m = texture(suit_mask, UV).rg;
	float shade = mix(0.55, 1.35, m.g);
	vec3 suit = suit_color * shade;
	float rough_s = 0.85;
	float metal_s = 0.0;
	float dirt_k = 1.0;
	vec3 emit = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	if (pattern == 1) {
		float s = stripe((UV.x + UV.y) * 16.0);
		suit = mix(vec3(0.03, 0.03, 0.025) * shade, pattern_color * shade, s);
	} else if (pattern == 2) {
		float n1 = fbm(UV * 11.0);
		float n2 = fbm(UV * 11.0 + vec2(23.0, 7.0));
		suit = mix(suit, suit * 0.42, smoothstep(0.48, 0.53, n1));
		suit = mix(suit, pattern_color * shade, smoothstep(0.52, 0.57, n2));
	} else if (pattern == 3) {
		float n = fbm(UV * 14.0);
		float spots = smoothstep(0.42, 0.66, n + fbm(UV * 40.0) * 0.25);
		vec3 rust = vec3(0.34, 0.14, 0.05) * (0.55 + n * 0.9) * shade;
		suit = mix(suit, rust, spots);
		rough_s = 0.95;
	} else if (pattern == 4) {
		float splat = smoothstep(0.5, 0.58, fbm(UV * 8.0));
		float drip = smoothstep(0.62, 0.7, fbm(vec2(UV.x * 46.0, UV.y * 3.0))) * smoothstep(0.35, 0.6, fbm(UV * 5.0));
		float b = clamp(splat + drip, 0.0, 1.0);
		suit = mix(suit, vec3(0.13, 0.0, 0.005) * shade, b);
		rough_s = mix(0.85, 0.22, b);
	} else if (pattern == 5) {
		float n = fbm(UV * 9.0);
		suit = mix(suit, vec3(0.13, 0.11, 0.08), clamp(n * 0.95, 0.0, 0.75));
		dirt_k = 2.2;
	} else if (pattern == 6) {
		float g = smoothstep(0.53, 0.64, fbm(UV * 10.0));
		suit = mix(suit, vec3(0.05, 0.35, 0.04), g);
		emit = vec3(0.15, 0.85, 0.1) * g * 0.7;
	} else if (pattern == 7) {
		float band = smoothstep(0.35, 0.65, fbm(vec2(UV.x * 3.0, UV.y * 26.0)));
		suit = mix(vec3(0.1, 0.11, 0.13), vec3(0.85, 0.88, 0.94), band) * shade;
		metal_s = 0.6;
		rough_s = 0.12;
		dirt_k = 0.2;
		emit = vec3(0.55, 0.65, 0.8) * fres * 1.4;
	} else if (pattern == 8) {
		float band = smoothstep(0.35, 0.65, fbm(vec2(UV.x * 3.0, UV.y * 26.0)));
		suit = mix(vec3(0.32, 0.15, 0.0), vec3(0.95, 0.62, 0.08), band) * shade;
		metal_s = 0.6;
		rough_s = 0.2;
		dirt_k = 0.2;
		emit = vec3(0.9, 0.45, 0.0) * fres * 1.2;
	} else if (pattern == 9) {
		float s = stripe(UV.y * 22.0);
		suit = mix(suit, pattern_color * shade, s);
	}
	float dirt = (1.0 - smoothstep(0.0, 0.35, dot(base, vec3(0.333)))) * grime * dirt_k;
	suit = mix(suit, suit * 0.45 + vec3(0.03, 0.025, 0.02), clamp(dirt, 0.0, 1.0));
	float weave_fade = 1.0 - smoothstep(0.004, 0.02, length(fwidth(UV)));
	float weave = (vnoise(UV * 380.0) - 0.5) * 0.14 * weave_fade * m.r;
	suit *= 1.0 + weave;
	ALBEDO = mix(base, suit, m.r);
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = mix(orm.g, rough_s, m.r);
	METALLIC = mix(orm.b, metal_s, m.r);
	EMISSION = emit * m.r + ALBEDO * 0.07 * m.r;
	SPECULAR = mix(0.4, mix(0.32, 0.55, metal_s), m.r);
	RIM = mix(0.18, 0.4, m.r) * (1.0 - metal_s);
	RIM_TINT = 0.55;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
