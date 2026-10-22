# Card rarity, and the card effects (FateCardFx) each rarity gets.
#
# Rarity is cosmetic: it never changes the rules. FateData is generated from the design document, so
# rarity is not stored there; it is derived from the card definition (mana value, uniqueness, doctrine
# tier), unless the definition sets "_rarity" or the card is named in OVERRIDES.
#
# What each rarity looks like (the shader parameters follow the BinbunVFX card effect materials in
# assets/BinbunVFX/card_effects/materials):
#   Common     tilt, lift and shadow only
#   Uncommon   a faint shimmer band that follows the tilt
#   Rare       foil: banded colour shift and a bright shimmer (foil_01)
#   Epic       holographic: a full rainbow sheen (holo_02)
#   Legendary  holographic sheen with a gold rim (holo_01 + tiers/legendary)
class_name FateRarity
extends RefCounted

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const COLORS := [
	Color(0.62, 0.64, 0.7),
	Color(0.36, 0.81, 0.55),
	Color(0.35, 0.62, 1.0),
	Color(0.72, 0.42, 0.98),
	Color(1.0, 0.8, 0.38),
]

# Hand-picked rarities, by card name: "Card Name": FateRarity.EPIC
const OVERRIDES := {}

# Shader parameters per rarity (see fate_card_fx.gdshader)
const FX := [
	# Common
	{"fx": false, "holo_amount": 0.0, "shimmer_strength": 0.0, "effect_steps": 16,
			"effect_size": Vector2(1, 1), "view_affect": 4.0, "glare": 0.06, "rim_amount": 0.0,
			"protect_amount": 1.0, "idle_sweep": 0.0},
	# Uncommon
	{"fx": true, "holo_amount": 0.0, "shimmer_strength": 0.35, "effect_steps": 16,
			"effect_size": Vector2(1, 1), "view_affect": 4.0, "glare": 0.08, "rim_amount": 0.0,
			"protect_amount": 0.6, "idle_sweep": 0.04},
	# Rare
	{"fx": true, "holo_amount": 0.3, "shimmer_strength": 1.0, "effect_steps": 4,
			"effect_size": Vector2(3, 9), "view_affect": 4.0, "glare": 0.1, "rim_amount": 0.0,
			"protect_amount": 0.35, "idle_sweep": 0.06},
	# Epic
	{"fx": true, "holo_amount": 0.55, "shimmer_strength": 1.5, "effect_steps": 8,
			"effect_size": Vector2(1, 2), "view_affect": 4.0, "glare": 0.12, "rim_amount": 0.0,
			"protect_amount": 0.25, "idle_sweep": 0.08},
	# Legendary
	{"fx": true, "holo_amount": 0.6, "shimmer_strength": 1.5, "effect_steps": 16,
			"effect_size": Vector2(0.2, 2), "view_affect": 1.0, "glare": 0.14, "rim_amount": 1.0,
			"rim_color": Color(1.0, 0.81, 0.38), "protect_amount": 0.25, "idle_sweep": 0.1},
]


# The rarity of a card definition (FateData.CARDS / TOKENS / DOCTRINES entry)
static func of(card_name: String, props: Dictionary) -> int:
	if OVERRIDES.has(card_name):
		return OVERRIDES[card_name]
	if props.has("_rarity"):
		var named := NAMES.find(str(props["_rarity"]).capitalize())
		if named != -1:
			return named
	if props.get("_token", false) or "Token" in props.get("Tags", []):
		return COMMON
	if props.get("Type") == "Doctrine":
		# Tier 1 to 3 (its cost)
		return clampi(RARE + int(props.get("Cost", 1)) - 1, RARE, LEGENDARY)
	if props.get("_unique", false):
		return LEGENDARY
	var mana_value := int(props.get("Cost", 0)) + str(props.get("Pips", "")).length()
	if mana_value >= 5:
		return EPIC
	if mana_value == 4:
		return RARE
	if mana_value == 3:
		return UNCOMMON
	return COMMON


static func of_card(card: Card) -> int:
	return of(card.canonical_name, card.properties)


static func name_of(rarity: int) -> String:
	return NAMES[clampi(rarity, COMMON, LEGENDARY)]


static func color_of(rarity: int) -> Color:
	return COLORS[clampi(rarity, COMMON, LEGENDARY)]


static func fx_of(rarity: int) -> Dictionary:
	return FX[clampi(rarity, COMMON, LEGENDARY)]
