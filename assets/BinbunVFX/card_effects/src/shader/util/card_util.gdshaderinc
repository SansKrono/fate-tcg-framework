#include "hsv_util.gdshaderinc"

float sample_shine(vec2 uv, vec2 size, int steps, vec3 normal, float view_affect){
	float shine = (dot(uv, size) + ((normal.y - normal.x)*(view_affect * 0.1))) * 0.3;
	
	if(steps > 0){
		shine = floor(shine * float(steps)) / float(steps);
	}
	
	return shine;
}

vec3 holo_effect(vec3 rgb, vec2 uv, vec3 normal, int steps, vec2 size, float view_affect) {
	float shine = sample_shine(uv, size, steps, normal, view_affect);
	
	vec3 hsv = rgb2hsv(rgb);
	hsv.r = hsv.r + view_affect;
	hsv.r += shine;
	
	return hsv2rgb(hsv);
}

vec3 shimmer_effect(vec3 rgb, vec2 uv, vec3 normal, int steps, vec2 size, float view_affect, float strength){
	float shine = sample_shine(uv, size, steps, normal, view_affect);
	
	float shimmer = 1.0 + (max(sin(shine * 16.0 + ((normal.y - normal.x) * view_affect)),0.0) * strength);
	
	vec3 hsv = rgb2hsv(rgb);
	hsv.b = hsv.b * shimmer;
	
	return hsv2rgb(hsv);
}
