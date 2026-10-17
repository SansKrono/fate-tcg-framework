extends CardLibrary

@onready var back_button := $VBC/HBC/MC/AvailableCards/Settings/Back
var abilities_header : RichTextLabel

func _ready() -> void:
	# Godot 4 does not call the parent _ready() automatically
	super._ready()
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))

# Populates the list of available cards, with all defined cards in the game
func populate_available_cards() -> void:
	super.populate_available_cards()
	abilities_header = _card_headers.get_node("Abilities")
	abilities_header.custom_minimum_size.x = get_viewport().get_visible_rect().size.x / 2

# Resizes the abilities header to match the window size.
# So that the abilities have the most space to show.
func _on_viewport_resized() -> void:
	# On resize down, for some reason, the name doesn't automatically resize properly
	# Only manually tweaking the window size fixes it. I haven't found a proper solution yet
	abilities_header.custom_minimum_size.x = get_viewport().get_visible_rect().size.x / 2

	
