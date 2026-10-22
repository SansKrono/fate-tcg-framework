shader_type spatial;
render_mode unshaded;

#include "util/card_util.gdshaderinc"

group_uniforms layers;
uniform sampler2D layer_01_texture : filter_nearest;
uniform float layer_01_emission = 1.0;

uniform sampler2D layer_02_texture : filter_nearest;
uniform float layer_02_emission = 1.0;

uniform sampler2D layer_03_texture : filter_nearest;
uniform float layer_03_emission = 1.0;

uniform sampler2D layer_04_texture : filter_nearest;
uniform float layer_04_emission = 1.0;

uniform sampler2D layer_05_texture : filter_nearest;
uniform float layer_05_emission = 1.0;

//uniform sampler2D layer_06_texture : filter_nearest;
//uniform float layer_06_emission = 1.0;

const int layer_amount = 5;

group_uniforms depth;
uniform float depth_amount = 0.4;

group_uniforms holo;
uniform int effect_steps : hint_range(0, 64, 1) = 16;
uniform vec2 effect_size = vec2(1.0,1.0);
uniform float holo_amount : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float shimmer_strength : hint_range(0.0, 8.0, 0.01) = 1.5;
uniform float view_affect = 1.0;

group_uniforms color;
group_uniforms color.invert;
uniform float value_pre_inversion : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float value_post_inversion : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms color.replace;
uniform sampler2D color_mask_texture;
uniform vec3 color_replace : source_color;
uniform float replace_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

vec2 parallax(float depth, vec3 n, vec3 t, vec3 v) {
	vec3 normal = normalize(n);
	vec3 tangent = normalize(t);
	vec3 bitangent = cross(normal, tangent);
	vec3 view = normalize(v);
	vec3 view_tangent = vec3(dot(view, tangent), dot(view, bitangent), dot(view, normal));
	vec2 offset = (view_tangent.xy / max(view_tangent.z, 0.001)) * depth;
	offset = vec2(-offset.x, offset.y);
	
	return offset;
}

vec4 sample_layer(sampler2D tex, vec2 uv, float depth, vec3 n, vec3 t, vec3 v){
	uv = uv + parallax(depth, n, t, v);
	
	vec2 tex_size = vec2(textureSize(tex,0));
	vec2 pixel_uv = floor(uv * tex_size) / tex_size;
	
	uv = clamp(uv,0.0,0.999);
	vec4 layer = texture(tex, uv);
	
	layer.rgb = invert_value(layer.rgb, value_pre_inversion);
	
	vec3 holo = holo_effect(
		layer.rgb, 
		pixel_uv, 
		n, 
		effect_steps, 
		effect_size,
		view_affect
	);
	
	layer.rgb = mix(layer.rgb, holo, holo_amount);
	
	layer.rgb = shimmer_effect(
		layer.rgb, 
		pixel_uv, 
		n, 
		effect_steps, 
		effect_size,
		view_affect,
		shimmer_strength
	);
	
	return layer;
}

void fragment() {
	vec4 color = vec4(0.0);
	int cur_layer = layer_amount - 1;
	
	//float depth = float(cur_layer) / float(layer_amount);
	//vec4 layer_06 = sample_layer(layer_06_texture, UV, depth, NORMAL, TANGENT, VIEW) * layer_06_emission;
	//color = mix(color, layer_06, layer_06.a);
	//cur_layer--;
	
	float depth = float(cur_layer) / float(layer_amount);
	vec4 layer_05 = sample_layer(layer_05_texture, UV, depth * depth_amount, NORMAL, TANGENT, VIEW) * layer_05_emission;
	color = mix(color, layer_05, layer_05.a);
	cur_layer--;
	
	depth = float(cur_layer) / float(layer_amount);
	vec4 layer_04 = sample_layer(layer_04_texture, UV, depth * depth_amount, NORMAL, TANGENT, VIEW) * layer_04_emission;
	color = mix(color, layer_04, layer_04.a);
	cur_layer--;
	
	depth = float(cur_layer) / float(layer_amount);
	vec4 layer_03 = sample_layer(layer_03_texture, UV, depth * depth_amount, NORMAL, TANGENT, VIEW) * layer_03_emission;
	color = mix(color, layer_03, layer_03.a);
	cur_layer--;
	
	depth = float(cur_layer) / float(layer_amount);
	vec4 layer_02 = sample_layer(layer_02_texture, UV, depth * depth_amount, NORMAL, TANGENT, VIEW) * layer_02_emission;
	color = mix(color, layer_02, layer_02.a);
	cur_layer--;
	
	depth = float(cur_layer) / float(layer_amount);
	vec4 layer_01 = sample_layer(layer_01_texture, UV, depth * depth_amount, NORMAL, TANGENT, VIEW) * layer_01_emission;
	color = mix(color, layer_01, layer_01.a);
	cur_layer--;
	
	color.rgb = invert_value(color.rgb, value_post_inversion);
	
	float color_mask = texture(color_mask_texture, UV).r;
	color.rgb = mix(color.rgb, replace_color(color.rgb, color_replace), color_mask * replace_amount);
	
	ALBEDO = color.rgb;
}
