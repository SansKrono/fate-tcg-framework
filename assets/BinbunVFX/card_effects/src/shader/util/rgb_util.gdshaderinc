vec3 rgb_inverted(vec3 color, vec3 inversion) {
	return vec3(
		mix(color.r, 1.0 - color.r, inversion.r),
		mix(color.g, 1.0 - color.g, inversion.g),
		mix(color.b, 1.0 - color.b, inversion.b)
	);
}