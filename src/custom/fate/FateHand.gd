# The hand of a Fate player.
#
# The hand of the player whose turn it is sits at the bottom of the screen, full size, face-up,
# half off-screen (hover a card to lift it). The other player's hand is a small face-down fan
# hanging from the top edge: its cards cannot be hovered or read (concealed), except while a
# reaction window gives that player priority (FateBoard reveals it). See FateLayout.apply_seats.
extends Hand

# How much of the small top hand shows below the top edge of the screen
const TOP_PEEK := 40.0

# True for the hand at the top of the screen
@export var mirrored := false
var seat := "bottom"
# The cards are face-down and ignore the mouse
var concealed := false


func _ready() -> void:
	super._ready()
	# The player plates show the hand size
	$Counters.visible = false
	child_entered_tree.connect(_on_card_entered)
	child_exiting_tree.connect(_on_card_leaving)


func set_seat(new_seat: String) -> void:
	seat = new_seat
	mirrored = seat == "top"
	var hand_scale: float = FateLayout.TOP_HAND_SCALE if mirrored else FateLayout.BOTTOM_HAND_SCALE
	scale = Vector2(hand_scale, hand_scale)
	set_concealed(mirrored)
	re_place()


# Turns the cards of the hand face-down (and unreadable) or face-up
func set_concealed(value: bool) -> void:
	concealed = value
	for card in get_all_cards():
		_apply_concealment(card)


func _apply_concealment(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	if "concealed" in card:
		card.concealed = concealed
	card.set_is_faceup(not concealed, true)
	card.set_control_mouse_filters(not concealed)


func _on_card_entered(node: Node) -> void:
	if node is Card and "concealed" in node:
		node.concealed = concealed


# A card moving into a hand is turned face-up by the framework at the end of its move, at no
# fixed time, so a concealed hand turns its cards back down as soon as they settle
func _process(delta: float) -> void:
	super._process(delta)
	if not concealed:
		return
	for card in get_all_cards():
		if card.is_faceup and card.state in [Card.CardState.IN_HAND, Card.CardState.REORGANIZING]:
			_apply_concealment(card)


func _on_card_leaving(node: Node) -> void:
	if node is Card and "concealed" in node:
		# It was face-down in here: it must not stay so on the table (FateCardTemplate)
		if node.concealed and "reveal_on_table" in node:
			node.reveal_on_table = true
		node.concealed = false


func re_place() -> void:
	await super.re_place()
	if mirrored:
		position.y = -(card_size.y * scale.y - TOP_PEEK)
	# A scaled hand spreads its cards over its wrapper's width (the framework sizes the hand to it
	# at the end of the frame, without the scale)
	_fit_to_wrapper.call_deferred()


func _fit_to_wrapper() -> void:
	if not is_inside_tree():
		return
	$Control.size = get_parent().size / scale.x
	call_deferred("_adjust_collision_area")
	# Cards still moving into the hand would finish on a target computed for the old size
	for c in get_all_cards():
		c.interruptTweening()
		c.reorganize_self()
