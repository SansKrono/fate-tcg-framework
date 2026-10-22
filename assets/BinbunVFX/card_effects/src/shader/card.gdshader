shader_type spatial;
render_mode unshaded;

#include "util/card_util.gdshaderinc"
#include "util/rgb_util.gdshaderinc"

uniform sampler2D main_texture : filter_nearest;

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
uniform float replace_amount : hint_range(0.0, 1.0, 0.01) = 0.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec4 color = texture(main_texture, UV);
	
	vec2 tex_size = vec2(textureSize(main_texture,0));
	vec2 pixel_uv = floor(UV * tex_size) / tex_size;
	
	color.rgb = invert_value(color.rgb, value_pre_inversion);
	
	vec3 holo = holo_effect(
		color.rgb, 
		pixel_uv, 
		NORMAL, 
		effect_steps, 
		effect_size,
		view_affect
	);
	
	color.rgb = mix(color.rgb, holo, holo_amount);
	
	color.rgb = shimmer_effect(
		color.rgb, 
		pixel_uv, 
		NORMAL, 
		effect_steps, 
		effect_size,
		view_affect,
		shimmer_strength
	);
	
	color.rgb = invert_value(color.rgb, value_post_inversion);
	
	float color_mask = texture(color_mask_texture, UV).r;
	color.rgb = mix(color.rgb, replace_color(color.rgb, color_replace), color_mask * replace_amount);
	
	
	ALBEDO = color.rgb;
}
