class_name UTCommon
extends "res://addons/gut/test.gd"

# TODO: I should make 2 scenes just for UT so I don't rely on these which
# might get deleted
const MAIN_SCENE = preload("res://tests/UTMain.tscn")
var BOARD_SCENE = load("res://tests/UTBoard.tscn")
const MOUSE_SPEED := {
	"fast": [10,0.3],
	"slow": [3,0.6],
	"debug": [1,2],
}


var main
var board: Board
var hand: Hand
var deck: Pile
var discard: Pile


# Godot 4 no longer exposes the GDScriptFunctionState of an unfinished
# coroutine (Godot 3's `var state = coroutine()` +
# `if state is GDScriptFunctionState: yield(state, "completed")`).
# This wraps a coroutine call so that tests can check whether it is still
# running and await its completion, without awaiting it right away.
class CoroutineState:
	extends RefCounted
	signal completed(result)
	var is_running := true
	var result
	# Keeps this object alive while the coroutine runs, even if the caller
	# does not hold a reference to it.
	var _keepalive

	func _init(coroutine: Callable) -> void:
		_keepalive = self
		_run(coroutine)

	func _run(coroutine: Callable) -> void:
		result = await coroutine.call()
		is_running = false
		set_deferred("_keepalive", null)
		completed.emit(result)


# Waits for a signal or for max_time seconds, whichever comes first.
# Used by the helpers below, which may run concurrently with the test
# (fire-and-forget), so they cannot share GUT's single awaiter.
class _SignalWaiter:
	extends RefCounted
	signal finished(fired)
	var _signal: Signal
	var _done := false
	var _keepalive

	func _init(sig: Signal, max_time: float, tree: SceneTree) -> void:
		_keepalive = self
		_signal = sig
		sig.connect(_on_signal)
		tree.create_timer(max_time).timeout.connect(_finish.bind(false))

	func _on_signal(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
		_finish(true)

	func _finish(fired: bool) -> void:
		if _done:
			return
		_done = true
		if is_instance_valid(_signal.get_object())\
				and _signal.is_connected(_on_signal):
			_signal.disconnect(_on_signal)
		set_deferred("_keepalive", null)
		finished.emit(fired)


# Starts a coroutine without awaiting it. See CoroutineState.
func start_coroutine(coroutine: Callable) -> CoroutineState:
	return CoroutineState.new(coroutine)


# Helper equivalent of wait_seconds() with its own timer
func _helper_wait(time: float) -> void:
	await get_tree().create_timer(time).timeout


# Helper equivalent of wait_for_signal() with its own timer.
# Like GUT's, after the signal fires it waits one more frame so that
# the signal can propagate to other objects.
func _helper_wait_for_signal(sig: Signal, max_time: float) -> bool:
	var waiter := _SignalWaiter.new(sig, max_time, get_tree())
	var fired = await waiter.finished
	if fired:
		await get_tree().process_frame
	return fired

func fake_click(pressed, position, flags=0) -> InputEvent:
	var ev := InputEventMouseButton.new()
	ev.button_index=MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = position
	ev.meta_pressed = flags
	return ev


func setup_main() -> void:
	# Headless runs give the root window a 64x64 size, which breaks layout maths
	get_tree().root.size = Vector2i(1280, 720)
	cfc.is_testing = true
	cfc._setup()
	main = autoqfree(MAIN_SCENE.instantiate())
	get_tree().get_root().add_child(main)
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	board = cfc.NMAP.board
	board.load_test_cards()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Always reveal the mouseon unclick
	hand = cfc.NMAP.hand
	deck = cfc.NMAP.deck
	discard = cfc.NMAP.discard


func setup_board() -> void:
	# Headless runs give the root window a 64x64 size, which breaks layout maths
	get_tree().root.size = Vector2i(1280, 720)
	cfc.is_testing = true
	cfc._setup()
	board = add_child_autofree(BOARD_SCENE.instantiate())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Always reveal the mouseon unclick
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	board.load_test_cards()
	hand = cfc.NMAP.hand
	deck = cfc.NMAP.deck
	discard = cfc.NMAP.discard

func teardown_board() -> void:
	cfc.flush_cache()
	cfc.are_all_nodes_mapped = false
	cfc.card_drag_ongoing = null
	cfc.NMAP.clear()


func draw_test_cards(count: int, fast := true) -> Array:
	var cards = []
	for _iter in range(count):
		if fast:
			var card = deck.get_top_card()
			deck.remove_child(card)
			hand.add_child(card)
			card.state = Card.CardState.IN_HAND
			cards.append(card)
		else:
			cards.append(hand.draw_card())
	for c in cards:
		c.interruptTweening()
		c.reorganize_self()
	return cards

func click_card(card: Card, _use_fake_mouse := true, offset:=Vector2(0,0)) -> void:
	var fc:= fake_click(true, offset)
	card._on_Card_gui_input(fc)

func unclick_card(card: Card) -> void:
	var fc:= fake_click(false, card.global_position)
	card._on_Card_gui_input(fc)

# We need this for targetting arrows which don't release back on the card gui
func unclick_card_anywhere(card: Card) -> void:
	var fc:= fake_click(false, card.global_position)
	card._input(fc)


# Waits until the card has stopped moving (e.g. a hand re-organization
# tween has finished), so that the virtual mouse can target it accurately.
func wait_card_settled(card: Card, max_time := 1.5) -> void:
	var elapsed := 0.0
	var last_pos := card.global_position
	var stable_frames := 0
	while elapsed < max_time and stable_frames < 3:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if card.global_position.is_equal_approx(last_pos):
			stable_frames += 1
		else:
			stable_frames = 0
			last_pos = card.global_position


func drag_card(card: Card, target_position: Vector2, interpolation_speed := "fast") -> void:
	await wait_card_settled(card)
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	var extra_offset = Vector2(20,20)
	if card.card_rotation in [90,270]:
		extra_offset = Vector2(10,60)
	board._UT_interpolate_mouse_move(card.global_position + extra_offset,
			board._UT_mouse_position,mouse_speed)
	await _helper_wait(mouse_yield_wait)
	click_card(card)
	if interpolation_speed == "debug":
		await _helper_wait(4) # Allow for review
	else:
		await _helper_wait(0.3) # Wait to allow dragging to start
	board._UT_interpolate_mouse_move(target_position,board._UT_mouse_position,mouse_speed)
	await _helper_wait(mouse_yield_wait)


func drop_card(card: Card, drop_location: Vector2) -> void:
	var fc:= fake_click(false, drop_location)
	card._on_Card_gui_input(fc)
	await _helper_wait_for_signal(card._tween.tween_all_completed, 1)


# Takes care of simple drag&drop requests
func drag_drop(card: Card, target_position: Vector2, interpolation_speed := "fast") -> void:
	await drag_card(card,target_position,interpolation_speed)
	await drop_card(card,board._UT_mouse_position)
	await _helper_wait(0.1) # Wait to allow dragging to start
	card._on_Card_mouse_exited()

# Interpolates the virtual mouse so that it correctly targets a card
func target_card(source: Card,
		target: Card, interpolation_speed := "fast") -> void:
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	if source == target:
		# If the target is the same as the source, we need to wait a bit
		# because otherwise the _is_targeted might not be set yet.
		await _helper_wait(0.6)
	# We need to offset a bit towards the card rect, to ensure the arrow
	# Area2D collides
	var extra_offset = Vector2(10,10)
	if target.card_rotation in [90,270]:
		extra_offset = Vector2(10,100)
	board._UT_interpolate_mouse_move(target.global_position + extra_offset,
			source.global_position,mouse_speed)
	await _helper_wait(mouse_yield_wait)
	var repeat := 0
	while not target.highlight.visible and repeat <= 3:
		board._UT_interpolate_mouse_move(target.global_position + extra_offset,
				board._UT_mouse_position,mouse_speed)
		await _helper_wait(mouse_yield_wait)
		repeat += 1
	unclick_card_anywhere(source)


func table_move(card: Card, pos: Vector2) -> void:
	card.move_to(board, -1, pos)
	await _helper_wait_for_signal(card._tween.tween_all_completed, 0.5)
#	if cfc.game_settings.fancy_movement:
#		yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)

func move_mouse(target_position: Vector2, interpolation_speed := "fast") -> void:
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	board._UT_interpolate_mouse_move(target_position,board._UT_mouse_position,mouse_speed)
	await _helper_wait(mouse_yield_wait)

func execute_with_yield(card: Card) -> void:
	var sceng := start_coroutine(card.execute_scripts)
	if sceng.is_running:
		await _helper_wait_for_signal(sceng.completed, 1)


func execute_with_target(card: Card, target: Card) -> void:
	var sceng := start_coroutine(card.execute_scripts)
	target_card(card,target,"slow")
	if sceng.is_running:
		await sceng.completed
	# The scripts finish from inside the targeting arrow's input handling.
	# We let that call stack unwind before returning to the test, as the test
	# might end and free the arrow while it's still being used.
	await get_tree().process_frame
