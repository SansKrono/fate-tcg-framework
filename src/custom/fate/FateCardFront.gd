# Front of a Fate card.
#
# Maps the Fate card properties to their labels. Creatures show Strike and
# Guard; relics, spells and doctrines hide them (has_combat_stats = false).
extends CardFront

# Set on the per-type front scenes (CreatureFront, RelicFront etc.)
@export var has_combat_stats := true


func _ready() -> void:
	_card_text = find_child("CardText")
	card_labels["Name"] = find_child("Name")
	card_labels["Type"] = find_child("Type")
	card_labels["Tags"] = find_child("Tags")
	card_labels["Domain"] = find_child("Domain")
	card_labels["Abilities"] = find_child("Abilities")
	card_labels["Cost"] = find_child("Cost")
	card_labels["Pips"] = find_child("Pips")
	card_labels["Strike"] = find_child("Strike")
	card_labels["Guard"] = find_child("Guard")

	card_label_min_sizes["Name"] = Vector2(CFConst.CARD_SIZE.x - 4, 19)
	card_label_min_sizes["Type"] = Vector2(CFConst.CARD_SIZE.x - 4, 13)
	card_label_min_sizes["Tags"] = Vector2(CFConst.CARD_SIZE.x - 4, 17)
	card_label_min_sizes["Domain"] = Vector2(CFConst.CARD_SIZE.x - 4, 11)
	card_label_min_sizes["Abilities"] = Vector2(CFConst.CARD_SIZE.x - 4, 120)
	card_label_min_sizes["Cost"] = Vector2(16, 16)
	card_label_min_sizes["Pips"] = Vector2(16, 16)
	card_label_min_sizes["Strike"] = Vector2(16, 16)
	card_label_min_sizes["Guard"] = Vector2(16, 16)

	for l in card_label_min_sizes:
		card_labels[l].custom_minimum_size = card_label_min_sizes[l]

	for label in card_labels:
		match label:
			"Cost", "Pips", "Strike", "Guard":
				original_font_sizes[label] = 15
			"Domain":
				original_font_sizes[label] = 11
			"Abilities":
				original_font_sizes[label] = 25
			_:
				original_font_sizes[label] = 16

	if not has_combat_stats:
		for node_name in ["StrikeIcon", "Strike", "GuardIcon", "Guard"]:
			find_child(node_name).visible = false
