# Where everything goes on the Fate table (1280x720).
#
# The table has two seats: the player whose turn it is sits at the bottom, the other one at the top
# (see apply_seats()). Positions are given for the bottom seat; the top seat mirrors them.
#
#   x 0-230    left rail: the card detail dock (Main's magnifier) and the combat log
#   x 240-1050 the table: for each seat a front row (creatures, relics, field spell) next to the
#              midline and a back row (occupied creatures, energy) next to the edge, the hand
#              beyond it; the status bar with the phase strip on the midline
#   x 1056+    right rail: for each seat the player plate, the piles and the doctrines; between
#              the two seats the world spell slot and the action panel
#
# The table rows mirror around the midline (y 312); the rail mirrors around the middle of the
# screen, so each plate sits in its corner.
class_name FateLayout
extends RefCounted

const SCREEN := Vector2(1280, 720)
# The size of a Fate card: the native size of its pixel art (assets/fantasy-tcg-cards-pixel-art), which
# the card scenes are laid out at. The framework's CFConst.CARD_SIZE stays the framework default; the
# Fate cards (FateCardTemplate.tscn canonical_size) and the Fate containers (FateBoard) use this one.
const CARD_SIZE := Vector2(195, 284)
# Scale of the cards in each zone (FateBoard.TABLE_SCALE for the zones not listed)
const ZONE_SCALES := {"energy": 0.25, "doctrines": 0.25, "world": 0.25}
const COLUMNS := {
	"creatures": 6, "occupied": 6, "relics": 99, "field": 1, "doctrines": 3, "energy": 99,
}
# The zones with no limit on the number of cards: the grid grows a slot whenever it is full
const UNLIMITED_ZONES := ["energy", "relics"]
# The relic zone has no limit either: it starts with RELIC_START_SLOTS slots, grows like the energy row and
# squeezes its cards together past RELIC_ROW_WIDTH (FateBoard._squeeze_rows)
const RELIC_START_SLOTS := 3
const RELIC_ROW_WIDTH := 216.0
# The energy zone is one row that never wraps: past ENERGY_START_SLOTS cards the cards squeeze
# together (FateBoard._squeeze_energy) to stay within ENERGY_ROW_WIDTH, and a counter beside the
# row says how much energy there is, ready and tapped
const ENERGY_START_SLOTS := 5
const ENERGY_ROW_WIDTH := 226.0
const ENERGY_COUNTER_SIZE := Vector2(48, 76)
# Gap between the slots of the creature rows: a tilted creature (guarding, or occupied) is as
# wide as a card is tall, so it needs about this much room on each side not to cover its
# neighbours
const SLOT_GAPS := {"creatures": 14, "occupied": 14}
# Top-left corner of each zone for the bottom seat
const BOTTOM_GRIDS := {
	"creatures": Vector2(248, 348),
	"relics": Vector2(755, 348),
	"field": Vector2(979, 348),
	"occupied": Vector2(248, 468),
	"energy": Vector2(755, 468),
	"doctrines": Vector2(1066, 438),
}
const BOTTOM_PILES := {
	"deck": Vector2(1066, 520),
	"discard": Vector2(1138, 520),
	"removed": Vector2(1210, 520),
}
# Piles are drawn as small stacks
const PILE_SCALE := 0.34
const RAIL_ZONES := ["doctrines"]
const TABLE_MIDLINE := 312.0
const HAND_RECT := Rect2(240, 480, 810, 240)
# The top hand is a small face-down fan
const TOP_HAND_SCALE := 0.38
# The active player's hand, a little under full size so the cards fit HAND_RECT
const BOTTOM_HAND_SCALE := 0.85
const TOP_HAND_RECT := Rect2(380, 0, 540, 44)
const PLATE_RECT := Rect2(1062, 624, 212, 88)
const STATUS_RECT := Rect2(240, 284, 810, 42)
const WORLD_POSITION := Vector2(1064, 322)
const ACTION_RECT := Rect2(1120, 290, 154, 142)
const LOG_RECT := Rect2(8, 548, 214, 164)
# The debug tools button, just above the log
const DEBUG_BUTTON_RECT := Rect2(8, 510, 214, 30)
# Where the card detail dock (Main's magnifier) sits, and its scale
const DOCK_POSITION := Vector2(4, 4)
const DOCK_SCALE := 0.75
const LEFT_RAIL_WIDTH := 230.0
const RIGHT_RAIL_X := 1056.0


static func zone_scale(zone: String) -> float:
	return ZONE_SCALES.get(zone, FateBoard.TABLE_SCALE)


# The size of an empty zone with its columns (one row)
static func grid_height(zone: String) -> float:
	return FateLayout.CARD_SIZE.y * zone_scale(zone) + 4.0


static func grid_position(zone: String, seat: String) -> Vector2:
	var pos: Vector2 = BOTTOM_GRIDS[zone]
	if seat == "top":
		pos.y = _mirror(pos.y, grid_height(zone), zone in RAIL_ZONES)
	return pos


static func pile_position(zone: String, seat: String) -> Vector2:
	var pos: Vector2 = BOTTOM_PILES[zone]
	if seat == "top":
		pos.y = _mirror(pos.y, FateLayout.CARD_SIZE.y * PILE_SCALE, true)
	return pos


static func plate_rect(seat: String) -> Rect2:
	var rect := PLATE_RECT
	if seat == "top":
		rect.position.y = _mirror(rect.position.y, rect.size.y, true)
	return rect


static func hand_rect(seat: String) -> Rect2:
	return HAND_RECT if seat == "bottom" else TOP_HAND_RECT


# The y of something of the given height, mirrored from the bottom seat to the top seat
static func _mirror(y: float, height: float, rail: bool) -> float:
	var axis: float = SCREEN.y / 2.0 if rail else TABLE_MIDLINE
	return 2.0 * axis - y - height


static func seat_of(player_id: int, bottom_id: int) -> String:
	return "bottom" if player_id == bottom_id else "top"


# Puts every zone of both players in its seat: bottom_id's zones at the bottom.
# Cards on the table follow their slots.
static func apply_seats(board: FateBoard, bottom_id: int) -> void:
	for pid in range(1, FateZones.PLAYER_COUNT + 1):
		var seat := seat_of(pid, bottom_id)
		for zone in BOTTOM_GRIDS:
			var grid := board.get_grid(FateZones.grid_name(zone, pid))
			if grid:
				grid.position = grid_position(zone, seat)
		for zone in BOTTOM_PILES:
			var wrapper: Control = board.get_node_or_null(
					"%sWrapper" % FateZones.node_name(zone, pid))
			if wrapper:
				wrapper.position = pile_position(zone, seat)
		var hand_wrapper: Control = board.get_node_or_null(
				"%sWrapper" % FateZones.node_name("hand", pid))
		if hand_wrapper:
			var rect := hand_rect(seat)
			hand_wrapper.position = rect.position
			hand_wrapper.custom_minimum_size = rect.size
			hand_wrapper.size = rect.size
			var hand = hand_wrapper.get_child(0)
			if hand.has_method("set_seat"):
				hand.set_seat(seat)
	snap_cards(board)


# Moves every card standing in a slot onto it (after the grids moved). A card that is still sliding
# to its slot (it was moved a moment ago, with the slot's old position as the target: the seat swap
# of a hotseat turn happens behind a short fade, after the maintenance step moved occupied creatures
# back to the creature zone) must be redirected too, or it keeps sliding to the old place and ends up
# in the other player's half of the table while its slot, and every click on it, belong to its owner.
static func snap_cards(board: FateBoard) -> void:
	for card in board.get_all_cards():
		var slot = card._placement_slot
		if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
			var target: Vector2 = slot.global_position - board.global_position
			# Only the slide: the same tween node animates the rotation of a tilted card and the scale
			card.get_node("Tween").remove(card, "position")
			card._target_position = target
			card.position = target
