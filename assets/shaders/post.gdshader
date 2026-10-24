shader_type canvas_item;
// Full-resolution film pass: warm tint, per-pixel film grain, vignette and a sub-LSB dither against banding.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grain = 0.05;
uniform float vignette = 0.55;
uniform float tint_strength = 0.12;
uniform vec3 tint : source_color = vec3(0.86, 0.93, 0.82);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, lum * tint * 1.1, tint_strength);
	vec2 px = FRAGCOORD.xy;
	float t = floor(TIME * 24.0);
	float g = hash(px + t * 17.13) + hash(px * 1.37 + t * 5.71) - 1.0;
	c += g * grain * (0.55 + 0.9 * smoothstep(0.0, 0.5, lum) * (1.0 - 0.5 * smoothstep(0.7, 1.0, lum)));
	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - dot(v, v) * vignette * 1.6;
	c += (hash(px + 91.7) - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}
