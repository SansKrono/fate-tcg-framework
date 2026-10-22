// Recolours the accent pixels of the pixel-art card pieces (assets/fantasy-tcg-cards-pixel-art,
// "Cards_color1": blue accents, gold filigree, slate background) to another colour.
//
// Pixels whose hue lies in the accent band (the blue of the art) and that are saturated enough take
// the hue and saturation of `tint`, keeping their own shading. The gold filigree (another hue) and the
// greyish slate (too little saturation) stay as they are; `background_tint` pulls the slate a little
// towards the tint too. With the band set to the whole hue circle and min_saturation 0, the whole
// texture is recoloured (used for icons).
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.38, 0.62, 0.83, 1.0);
uniform float hue_min = 0.52;
uniform float hue_max = 0.66;
uniform float min_saturation = 0.47;
uniform float background_tint : hint_range(0.0, 1.0) = 0.0;
// The saturation and value of the art's own accent colour: the tint is applied relative to them
uniform float source_saturation = 0.6;
uniform float source_value = 0.75;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	vec3 hsv = rgb2hsv(color.rgb);
	vec3 target = rgb2hsv(tint.rgb);
	float in_band = step(hue_min, hsv.x) * step(hsv.x, hue_max);
	float accent = in_band * smoothstep(min_saturation - 0.04, min_saturation + 0.04, hsv.y);
	vec3 recoloured = hsv2rgb(vec3(target.x,
			clamp(hsv.y * target.y / source_saturation, 0.0, 1.0),
			clamp(hsv.z * max(target.z, 0.35) / source_value, 0.0, 1.0)));
	float slate = in_band * (1.0 - accent) * background_tint;
	vec3 slate_tinted = hsv2rgb(vec3(target.x, hsv.y * mix(1.0, target.y + 0.15, 0.6), hsv.z));
	color.rgb = mix(color.rgb, recoloured, accent);
	color.rgb = mix(color.rgb, slate_tinted, slate);
	COLOR = color;
}
