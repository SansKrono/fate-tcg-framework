# One deck of the catalogue on the deck selection screen: a toggle button with the deck's domain orb,
# its name in the domain's colour and its tier. FateDeckPanel adds one per preset.
class_name FateDeckTile
extends Button

var preset_id := ""


func setup(preset: Dictionary, group: ButtonGroup) -> void:
	preset_id = preset.id
	button_group = group
	var color := FateTheme.domain_color(preset.domain)
	(%Orb as FatePip).color = color
	%DeckName.text = preset.name
	%DeckName.add_theme_color_override("font_color", color.lightened(0.35))
	%Tier.text = "%s  ·  %s" % [preset.domain, preset.tier]
	tooltip_text = preset.blurb
