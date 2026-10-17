# Pops up a dialogie for the player to enter an integer.
# Typically called by a card script that needs that player
# to provide a value
extends AcceptDialog

# Godot 3 popups emitted "popup_hide" when hidden. Godot 4 AcceptDialogs
# (which are Windows) do not, so we emit it ourselves to keep the same API
# (the ScriptingEngine awaits this signal)
signal popup_hide

var number: int

func _ready() -> void:
	# warning-ignore:return_value_discarded
	get_ok_button().text = "Submit"
	# warning-ignore:return_value_discarded
	visibility_changed.connect(_on_visibility_changed)
	$IntegerLineEdit.connect("int_changed_ok", Callable(self, "_switch_green"))
	# warning-ignore:return_value_discarded
	$IntegerLineEdit.connect("int_changed_nok", Callable(self, "_switch_red"))
	# warning-ignore:return_value_discarded
	$IntegerLineEdit.connect("int_entered", Callable(self, "_on_number_entered"))


# Prepares the window to request the integer from the player
# in the correct range and bring the popup to the front.
func prep(title_reference: String, min_req: int, max_req : int) -> void:
		title = "Please enter number for the effect of " + title_reference
		$IntegerLineEdit.placeholder_text = \
				"Enter number between " + str(min_req) + " and " + str(max_req)
		$IntegerLineEdit.minimum = min_req
		$IntegerLineEdit.maximum = max_req
		#$LineEdit.text = str(minimum)
		cfc.NMAP.board.add_child(self)
		popup_centered()
		# One again we need two different Panels due to
		# https://github.com/godotengine/godot/issues/32030
		# In Godot 4 the window decoration is drawn outside the
		# dialog's own viewport, so the highlight can only cover
		# the whole content area of the window.
		$HorizontalHighlights.size = Vector2(size)
		$VecticalHighlights.size = Vector2(size)
		$HorizontalHighlights.position = Vector2(0,0)
		$VecticalHighlights.position = Vector2(0,0)
		_switch_red()
		#print($HorizontalHighlights.rect_size)
		# We spawn the dialogue at the middle of the screen.


func _on_number_entered(new_text: int) -> void:
		number = new_text
		hide()


func _switch_red() -> void:
	$HorizontalHighlights.modulate = Color(1.4,0,0)
	$VecticalHighlights.modulate = Color(1.2,0,0)


func _switch_green() -> void:
	$HorizontalHighlights.modulate = Color(0,1.6,0)
	$VecticalHighlights.modulate = Color(0,1.4,0)


func _on_visibility_changed() -> void:
	if not visible:
		emit_signal("popup_hide")


func _on_AskInteger_confirmed() -> void:
	$IntegerLineEdit._on_IntegerLineEdit_text_entered($IntegerLineEdit.text)
