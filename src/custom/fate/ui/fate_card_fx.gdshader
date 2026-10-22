// The card effects overlay of a Fate card (FateCardFx).
//
// The overlay is drawn over the card, right after a BackBufferCopy of the card's area. It re-draws
// that copy as a card tilted in perspective (looking at it from cam_dist pixels away) and applies the
// foil / holo / shimmer of the card's rarity. The colour effects are the BinbunVFX card effects
// (assets/BinbunVFX/card_effects), with the card's tilt standing in for the 3D surface normal.
//
// The tilted card is scaled by fit_scale (computed by FateCardFx) so that it always covers the flat
// card under it: no part of the untilted card shows around its edges.
shader_type canvas_item;
render_mode unshaded;

#include "res://assets/BinbunVFX/card_effects/src/shader/util/card_util.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Card geometry, in the card's own pixels
uniform vec2 card_size = vec2(150.0, 240.0);
uniform float corner_radius = 10.0;
// Radians around the card's y axis (x) and x axis (y): the edge in that direction goes away
uniform vec2 tilt = vec2(0.0);
uniform float cam_dist = 600.0;
uniform float fit_scale = 1.0;

// 0 shows the card as it is (face-down cards, common rarity), 1 the full rarity effects
uniform float fx_amount = 1.0;
// Extra slant of the surface normal for the colour effects only (the idle sweep)
uniform vec2 sweep = vec2(0.0);

group_uniforms holo;
uniform int effect_steps : hint_range(0, 64, 1) = 16;
uniform vec2 effect_size = vec2(1.0, 1.0);
uniform float holo_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float shimmer_strength : hint_range(0.0, 8.0, 0.01) = 0.0;
uniform float view_affect = 4.0;

group_uniforms rim;
uniform vec3 rim_color : source_color = vec3(1.0, 0.81, 0.38);
uniform float rim_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float rim_width = 9.0;

group_uniforms glare;
uniform float glare = 0.0;

// The glow around a card that can be played: a crisp border with a soft halo, around the tilted card
group_uniforms glow;
uniform vec3 glow_color : source_color = vec3(0.35, 0.72, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glow_width = 3.0;
uniform float glow_halo = 9.0;
// The framework's focus / target highlight (Highlight.gd), drawn here so that it tilts with the card
uniform vec4 highlight_color = vec4(1.0);
uniform float highlight_amount : hint_range(0.0, 1.0, 0.01) = 0.0;

// Parts of the card where the colour effects are toned down to protect what must stay readable
// (the domain pips, the rules text, the stats). Rects as (x, y, x2, y2) in the card's 0..1 space.
group_uniforms protect;
uniform vec4 protect_0 = vec4(0.0);
uniform vec4 protect_1 = vec4(0.0);
uniform vec4 protect_2 = vec4(0.0);
uniform vec4 protect_3 = vec4(0.0);
uniform float protect_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float in_rect(vec2 p, vec4 rect) {
	return step(rect.x, p.x) * step(rect.y, p.y) * step(p.x, rect.z) * step(p.y, rect.w);
}

void fragment() {
	// How the card's pixels map to the screen: the overlay is flat in the card's space, so the
	// derivatives give that (affine) mapping. Taken before any branching.
	mat2 to_screen = mat2(dFdx(SCREEN_UV), dFdy(SCREEN_UV)) * inverse(mat2(dFdx(local_px), dFdy(local_px)));

	// Cast a ray from the eye through this point and find where it meets the tilted card
	vec2 half_size = card_size * 0.5;
	vec2 q = (local_px - half_size) / fit_scale;
	vec3 n = normalize(vec3(tan(tilt.x), tan(tilt.y), 1.0));
	vec3 u = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 v = cross(n, u);
	vec3 eye = vec3(0.0, 0.0, cam_dist);
	vec3 ray = vec3(q, -cam_dist);
	vec3 hit = eye + ray * (-(n.z * cam_dist) / dot(n, ray));
	vec2 card_px = vec2(dot(hit, u), dot(hit, v)) + half_size;

	float edge = rounded_box(card_px - half_size, half_size, corner_radius);
	float alpha = 1.0 - smoothstep(-0.75, 0.75, edge);

	vec2 screen_uv = SCREEN_UV + to_screen * (card_px - local_px);
	vec3 color = textureLod(screen_tex, screen_uv, 0.0).rgb;

	vec2 card_uv = card_px / card_size;
	float mask = fx_amount;
	float protect = max(max(in_rect(card_uv, protect_0), in_rect(card_uv, protect_1)),
			max(in_rect(card_uv, protect_2), in_rect(card_uv, protect_3)));
	mask *= mix(1.0, protect_amount, protect);

	// The BinbunVFX effects expect a view-space normal (y up)
	vec3 normal = normalize(vec3(n.x + sweep.x, -n.y - sweep.y, n.z));
	vec2 pixel_uv = floor(card_px) / card_size;
	vec3 holo = holo_effect(color, pixel_uv, normal, effect_steps, effect_size, view_affect);
	color = mix(color, holo, holo_amount * mask);
	vec3 shimmer = shimmer_effect(color, pixel_uv, normal, effect_steps, effect_size, view_affect,
			shimmer_strength);
	color = mix(color, shimmer, mask);

	// Gold rim along the edge (legendary)
	float rim = (1.0 - smoothstep(rim_width * 0.4, rim_width, -edge)) * rim_amount * fx_amount;
	vec3 rim_tint = replace_color(color, rim_color) * 1.15;
	vec3 rim_shine = shimmer_effect(rim_tint, pixel_uv, normal, 8, vec2(1.0, 2.0), 4.0, 1.2);
	color = mix(color, rim_shine, rim);

	// A soft highlight on the raised side, stronger the more the card tilts
	vec2 light = -vec2(n.x, n.y) / max(length(n.xy), 1e-4);
	float lean = clamp(length(n.xy) * 6.0, 0.0, 1.0);
	float glow = smoothstep(0.2, 1.0, dot((card_uv - 0.5) * 2.0, light)) * lean;
	color += vec3(glow * glare);

	// Playable glow outside the card's edge, gently pulsing
	float border = 1.0 - smoothstep(glow_width - 0.75, glow_width + 0.75, edge);
	float halo = 0.35 * (1.0 - smoothstep(glow_width, glow_halo, edge));
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	float glow_alpha = max(border, halo) * glow_amount * pulse;
	float ring = border * highlight_amount;
	vec3 outside = mix(glow_color, highlight_color.rgb, ring);
	float outside_alpha = max(glow_alpha, ring * highlight_color.a);
	COLOR = vec4(mix(outside, color, alpha), max(alpha, outside_alpha));
}
