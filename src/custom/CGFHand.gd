extends Hand


func _ready() -> void:
	# Godot 4 no longer calls the parent _ready() automatically
	super._ready()
	# warning-ignore:return_value_discarded
	$Control/ManipulationButtons/DiscardRandom.connect("pressed", Callable(self, '_on_DiscardRandom_Button_pressed'))

