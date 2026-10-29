shader_type canvas_item;
render_mode unshaded;

uniform float scene_time = 0.0;
uniform float energy = 0.0;
uniform vec4 glow_tint : source_color = vec4(0.49, 0.07, 0.29, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	vec2 q = (uv - vec2(0.485, 0.48)) * vec2(1.55, 1.0);
	float falloff = exp(-dot(q, q) * 6.8);
	float fog = noise(uv * vec2(5.0, 8.0) + vec2(scene_time * 0.018, -scene_time * 0.009));
	fog += noise(uv * vec2(12.0, 14.0) - vec2(scene_time * 0.012, scene_time * 0.007)) * 0.45;
	float shaft = exp(-pow((uv.x - 0.48) + (uv.y - 0.35) * 0.18, 2.0) * 28.0);
	vec3 base = mix(vec3(0.013, 0.016, 0.025), vec3(0.043, 0.025, 0.048), falloff);
	base += glow_tint.rgb * falloff * (0.075 + fog * 0.078 + energy * 0.16);
	base += vec3(0.18, 0.16, 0.23) * shaft * (1.0 - uv.y) * 0.075;
	float floor_light = exp(-pow((uv.y - 0.77) * 10.0, 2.0)) * exp(-pow((uv.x - 0.48) * 3.5, 2.0));
	base += glow_tint.rgb * floor_light * 0.05;
	float vignette = (1.0 - smoothstep(0.20, 0.88, length((uv - 0.5) * vec2(1.1, 0.9))));
	float grain = (hash(FRAGCOORD.xy + floor(scene_time * 8.0)) - 0.5) * 0.005;
	COLOR = vec4(base * vignette + grain, 1.0);
}
