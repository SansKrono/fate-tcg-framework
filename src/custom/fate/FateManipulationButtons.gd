# Hover buttons of a Fate card: tilt (strike/guard), flip and view, plus the actions that the
# card's keywords offer (Occupy, Embody, ... see FateActions), refreshed each time the buttons
# appear.
extends ManipulationButtons


func _ready() -> void:
	super._ready()
	needed_buttons = {
		"Rot90": "T",
		"Flip": "F",
		"View": "V",
	}
	spawn_manipulation_buttons()


# Tilts the card between the upright (strike) and the sideways (guard) position. Players
# position their creatures in their own main phase (spec Section 1, step 5).
func _on_Rot90_pressed() -> void:
	var game: FateGame = owner_node._game()
	if game and not game.can_tilt(owner_node):
		return
	# warning-ignore:return_value_discarded
	owner_node.set_card_rotation(90, true)


func _on_Flip_pressed() -> void:
	# warning-ignore:return_value_discarded
	owner_node.set_is_faceup(not owner_node.is_faceup)


func _on_View_pressed() -> void:
	# warning-ignore:return_value_discarded
	owner_node.set_is_viewed(true)


# The extra buttons are rebuilt every time the hover buttons appear, because which actions exist
# and whether they are usable depends on the state of the game
func set_active(value = true) -> void:
	var was_active := _are_active
	super.set_active(value)
	if value and not was_active:
		_sync_action_buttons()


func _sync_action_buttons() -> void:
	for child in get_children():
		if str(child.name).begins_with("Action_"):
			remove_child(child)
			child.queue_free()
	var game: FateGame = owner_node._game()
	if game == null:
		return
	for action in game.actions.list(owner_node):
		var button = manipulation_button.instantiate()
		button.name = "Action_" + str(action.id)
		button.text = str(action.get("label", action.id))
		button.tooltip_text = str(action.get("tooltip", ""))
		button.disabled = not action.get("enabled", true)
		add_child(button)
		button.pressed.connect(_on_action_pressed.bind(str(action.id)))


func _on_action_pressed(action_id: String) -> void:
	var game: FateGame = owner_node._game()
	if game:
		game.actions.run(owner_node, action_id)
