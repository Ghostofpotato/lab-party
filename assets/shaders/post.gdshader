shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size = 1.5;
uniform float grain = 0.045;
uniform float vignette = 0.55;
uniform float levels = 28.0;
uniform float tint_strength = 0.12;
uniform vec3 tint : source_color = vec3(0.86, 0.93, 0.82);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(SCREEN_UV * res / pixel_size) * pixel_size + pixel_size * 0.5;
	vec3 c = texture(screen_tex, cell / res).rgb;
	float bayer = hash(floor(cell / pixel_size)) - 0.5;
	c = floor(c * levels + bayer + 0.5) / levels;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, lum * tint * 1.1, tint_strength);
	c += (hash(cell + fract(TIME) * 61.0) - 0.5) * grain;
	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - dot(v, v) * vignette * 1.6;
	COLOR = vec4(c, 1.0);
}
