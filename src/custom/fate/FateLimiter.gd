# Limiter and "once per turn": how often an ability may be used. Assigned to `game.limiter`.
# No class_name (FateGame loads it by path). OWNER: the "keywords" session.
# docs/FATE_TCG_DESIGN.md Section 9.1 (Limiter X: assumed to limit the uses per turn).
#
# Every use is counted under a SCOPE and a key:
#   * a card (per card instance, the default): two copies of a card have their own counts, and the
#     counts of a card are forgotten when it leaves the table (hand, a pile, ...): a card that comes
#     back is a fresh card. Moving between table zones (occupy, control change) keeps them.
#   * a player (`*_player`): shared by all the cards of the player under one key, for texts such as
#     "the first spell you cast each turn" or "once during your turn" written on a static effect.
# and a MODE:
#   * TURN (the default): the counts reset when any turn starts
#   * GAME: "once per game", they never reset (except when a board state is loaded or the game is reset)
#
#   game.limiter.can_use(card, "recruit")             # at most once this turn
#   game.limiter.use(card, "recruit", 2)              # Limiter 2: a second use is still allowed
#   game.limiter.use(card, "wish", 1, FateLimiter.GAME)
#   game.limiter.use_player(pid, "first_spell")
#   game.limiter.remaining(card, "recruit", 2)
#   game.limiter.reset(card)                          # forget a card's counts (all keys)
#
# Card scripts normally use it through the costs game.costs.once_per_turn(key, uses, scope) and
# game.costs.once_per_game(key). The limiter counts a use when `use` is called, so list that cost LAST in
# an ability's costs: costs are paid in order and an earlier cost that stays paid when a later one fails
# is the lesser loss.
extends RefCounted

const TURN := "turn"
const GAME := "game"

var game: FateGame
# mode -> {owner key -> {key: uses}}; the owner key is a card's instance id or "p<player id>"
var _uses := {TURN: {}, GAME: {}}
var _watched := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game
	game.turn_started.connect(func(_pid, _n): _uses[TURN].clear())
	if game.has_signal("board_state_loaded"):
		game.board_state_loaded.connect(func(_name): reset_all())


# --- per card ------------------------------------------------------------------------------------------

# May this card still use the ability `key` (at most `limit` times a turn, or a game)?
func can_use(card: Card, key := "ability", limit := 1, mode := TURN) -> bool:
	return uses(card, key, mode) < limit


# Records one use. Returns whether it was allowed (nothing is recorded when it was not).
func use(card: Card, key := "ability", limit := 1, mode := TURN) -> bool:
	if not is_instance_valid(card) or not can_use(card, key, limit, mode):
		return false
	_record(card.get_instance_id(), key, mode)
	_watch(card)
	return true


func uses(card: Card, key := "ability", mode := TURN) -> int:
	if not is_instance_valid(card):
		return 0
	return _count(card.get_instance_id(), key, mode)


# How many uses are left under `limit`
func remaining(card: Card, key := "ability", limit := 1, mode := TURN) -> int:
	return maxi(0, limit - uses(card, key, mode))


# Gives one use back (an ability that was cancelled after it was paid)
func refund(card: Card, key := "ability", mode := TURN) -> void:
	_unrecord(card.get_instance_id(), key, mode)


# Forgets the counts of a card: of `key` only, or of every key. Both modes.
func reset(card: Card, key := "") -> void:
	if not is_instance_valid(card):
		return
	_forget(card.get_instance_id(), key)


# --- per player ------------------------------------------------------------------------------------------

func can_use_player(player_id: int, key: String, limit := 1, mode := TURN) -> bool:
	return uses_player(player_id, key, mode) < limit


func use_player(player_id: int, key: String, limit := 1, mode := TURN) -> bool:
	if not can_use_player(player_id, key, limit, mode):
		return false
	_record(_player_key(player_id), key, mode)
	return true


func uses_player(player_id: int, key: String, mode := TURN) -> int:
	return _count(_player_key(player_id), key, mode)


func refund_player(player_id: int, key: String, mode := TURN) -> void:
	_unrecord(_player_key(player_id), key, mode)


# --- everything ---------------------------------------------------------------------------------------------

# Forgets every count of every mode (a new game, a loaded board state)
func reset_all() -> void:
	_uses = {TURN: {}, GAME: {}}


# --- internals -------------------------------------------------------------------------------------------------

func _player_key(player_id: int) -> String:
	return "p%d" % player_id


func _count(owner_key, key: String, mode: String) -> int:
	return int(_uses.get(mode, {}).get(owner_key, {}).get(key, 0))


func _record(owner_key, key: String, mode: String) -> void:
	var table: Dictionary = _uses[mode]
	var entry: Dictionary = table.get(owner_key, {})
	entry[key] = int(entry.get(key, 0)) + 1
	table[owner_key] = entry


func _unrecord(owner_key, key: String, mode: String) -> void:
	var entry: Dictionary = _uses.get(mode, {}).get(owner_key, {})
	if int(entry.get(key, 0)) > 1:
		entry[key] = int(entry[key]) - 1
	else:
		entry.erase(key)


func _forget(owner_key, key: String) -> void:
	for mode in _uses:
		var entry: Dictionary = _uses[mode].get(owner_key, {})
		if key == "":
			_uses[mode].erase(owner_key)
		else:
			entry.erase(key)


# A card is forgotten when it leaves the table, so a copy that returns starts fresh. Connected the first
# time the card uses an ability.
func _watch(card: Card) -> void:
	if _watched.has(card.get_instance_id()):
		return
	_watched[card.get_instance_id()] = true
	for sig in [card.card_moved_to_pile, card.card_moved_to_hand]:
		sig.connect(_on_card_left)


func _on_card_left(card: Card, _trigger: String, _details: Dictionary) -> void:
	if is_instance_valid(card) and card.get_parent() != cfc.NMAP.get("board"):
		_forget(card.get_instance_id(), "")
