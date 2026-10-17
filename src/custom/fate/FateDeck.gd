# A Fate deck. Clicking it asks the game to draw a card for its owner.
extends Pile

signal draw_requested(deck)


func _ready() -> void:
	super._ready()
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	# warning-ignore:return_value_discarded
	$Control.connect("gui_input", Callable(self, "_on_Deck_input_event"))


func _on_Deck_input_event(event) -> void:
	if event is InputEventMouseButton and event.is_pressed()\
			and not cfc.game_paused\
			and event.get_button_index() == 1:
		draw_requested.emit(self)
