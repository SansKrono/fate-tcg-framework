vec3 rgb2hsv(vec3 color_rgb) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(color_rgb.bg, k.wz), vec4(color_rgb.gb, k.xy), step(color_rgb.b, color_rgb.g));
	vec4 q = mix(vec4(p.xyw, color_rgb.r), vec4(color_rgb.r, p.yzx), step(p.x, color_rgb.r));

	float d = q.x - min(q.w, q.y);
	float e = 1e-10;

	return vec3(
		abs(q.z + (q.w - q.y) / (6.0 * d + e)),
		d / (q.x + e),
		q.x
	);
}

vec3 hsv2rgb(vec3 color_hsv) {
	vec3 rgb = clamp(
		abs(mod(color_hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
		0.0,
		1.0
	);
	return color_hsv.z * mix(vec3(1.0), rgb, color_hsv.y);
}

vec3 replace_color(vec3 color, vec3 replace) {
	vec3 color_hsv = rgb2hsv(color);
	vec3 replace_hsv  = rgb2hsv(replace);
	
	color = hsv2rgb(vec3(replace_hsv.r, color_hsv.g, color_hsv.b * replace_hsv.b));
	
	return color;
}

vec3 invert_value(vec3 color, float amount) {
	vec3 color_hsv = rgb2hsv(color);
	
	vec3 hsv_inv = vec3(
		color_hsv.rg,
		mix(color_hsv.b, 1.0 - color_hsv.b, amount)
	);
	
	color = hsv2rgb(hsv_inv);
	
	return color;
}