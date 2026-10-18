# Moving cards between the hidden and the public zones: draw, look, search, bottom, discard, energy.
# Assigned to `game.library`. No class_name (FateGame loads it by path). OWNER: the "library" session.
#
# The "effect verbs" of docs/FATE_TCG_DESIGN.md Section 9.4 as code: one function per verb, all moving
# cards with the "Scripted" tag (rules checks off) and all raising the right signals. Also owns the rule
# that an empty deck loses the game (FateGame.draw_extra_card / FateTurn._draw call `draw`) and the
# hand-size rule (the hand itself discards what does not fit: FateBoard sets DISCARD_DRAWN, so a card
# that goes to a full hand lands in its owner's discard pile).
#
# Piles keep their cards as children: the LAST card is the top, the first the bottom.
extends RefCounted

const SCRIPTED := ["Scripted"]

var game: FateGame


func _init(owner_game: FateGame) -> void:
	game = owner_game


# --- reading ------------------------------------------------------------------------------------

# "Draw N cards": returns the cards drawn (also those a full hand sent straight to the discard pile).
# Drawing from an empty deck loses the game for that player (game.deck_empty, then defeat_player) and
# stops the drawing.
func draw(player_id: int, count := 1) -> Array:
	var drawn := []
	var player: FatePlayer = game.player(player_id)
	if player == null or player.hand() == null:
		return drawn
	for _i in count:
		var card: Card = player.draw_card()
		if card == null:
			game.deck_empty.emit(player_id)
			game.defeat_player(player_id)
			break
		drawn.append(card)
	return drawn


# "Look at the top N cards of target player's deck": the cards, top first, without moving them
func look_top(player_id: int, count: int) -> Array:
	var cards := _cards_of("deck", player_id)
	cards.reverse()
	return cards.slice(0, maxi(count, 0))


# "Search your deck for a card matching `filter`": returns the matching cards (a Callable taking the card,
# returning bool; an invalid one matches everything), top first. `zone` is any pile or the hand ("deck",
# "discard", "removed", "hand"). The caller picks (game.choices) and calls to_hand / to_table, then
# shuffle().
func search(player_id: int, filter := Callable(), zone := "deck") -> Array:
	var found := []
	for card in _cards_of(zone, player_id):
		if not filter.is_valid() or filter.call(card):
			found.append(card)
	found.reverse()
	return found


# Shuffles a deck with the game's seeded RNG (cfc.game_rng), so that seeded games repeat. No animation.
func shuffle(player_id: int) -> void:
	var pile: Pile = FateZones.container("deck", player_id)
	if pile == null:
		return
	pile.shuffle_cards(false)


# --- moving -------------------------------------------------------------------------------------

# Moves a card to its owner's (or `player_id`'s) hand / the bottom or top of a deck / the discard pile /
# the removed pile / the face-down energy zone. All return whether the card moved. A card that cannot go
# to a full hand is discarded by the hand (hand limit 10) and to_hand returns false.
func to_hand(card: Card, player_id := 0) -> bool:
	var hand = FateZones.container("hand", _target_player(card, player_id))
	if not _can_move(card) or hand == null:
		return false
	if _is_token(card):
		_cease_to_exist(card)
		return false
	card.move_to(hand, -1, null, SCRIPTED)
	return card.get_parent() == hand


func to_deck_bottom(card: Card, player_id := 0) -> bool:
	return _to_pile(card, "deck", _target_player(card, player_id), 0)


func to_deck_top(card: Card, player_id := 0) -> bool:
	return _to_pile(card, "deck", _target_player(card, player_id), -1)


func to_discard(card: Card) -> bool:
	return _to_pile(card, "discard", _target_player(card, 0), -1)


func to_removed(card: Card) -> bool:
	return _to_pile(card, "removed", _target_player(card, 0), -1)


# Puts a card face-down in `player_id`'s energy zone (from any zone, any owner): "place in your energy
# zone". The card becomes an energy card (1 mana of its first domain), untapped, face-down, owner_id
# unchanged, controller = that player. Emits energy_played only when it came from the hand. A token ceases
# to exist instead (returns false). Returns false when the energy grid has no free slot.
func to_energy(card: Card, player_id: int) -> bool:
	if not _can_move(card) or not game.players.has(player_id):
		return false
	if _is_token(card):
		_cease_to_exist(card)
		return false
	var zone: String = FateZones.zone_of(card)
	if zone == "energy" and card.controller_id == player_id:
		return false
	var grid: BoardPlacementGrid = FateZones.grid("energy", player_id)
	if grid == null:
		return false
	var slot: BoardPlacementSlot = grid.find_available_slot()
	if slot == null:
		return false
	var from_hand: bool = card.get_parent() is Hand
	var old_controller: int = card.controller_id
	var was_on_table_not_energy: bool = card.get_parent() == cfc.NMAP.board and zone != "energy"
	# Before the move: a card entering the table with is_energy set is not "entered" (no on_enter)
	card.is_energy = true
	card.controller_id = player_id
	if was_on_table_not_energy:
		game.card_effects.card_left(card, "energy")
		game.stats.clear_card(card)
		card.set_card_rotation(0)
	card.move_to(cfc.NMAP.board, -1, slot, SCRIPTED)
	card.set_is_faceup(false, true)
	card.set_card_rotation(0)
	if from_hand:
		game.energy_played.emit(card)
	game.mana_changed.emit(player_id)
	if old_controller != player_id:
		game.mana_changed.emit(old_controller)
	return true


# "Discard a card from your hand": the player picks (game.choices) unless a card list is given in
# `cards`. Returns the discarded cards (fewer when the hand is smaller). Awaitable.
func discard_from_hand(player_id: int, count := 1, cards := []) -> Array:
	var hand = FateZones.container("hand", player_id)
	if hand == null:
		return []
	var chosen: Array = cards.duplicate()
	if chosen.is_empty():
		var options: Array = hand.get_all_cards()
		var answer = await game.choices.pick("card to discard", player_id, null, options, count)
		if answer is Array:
			chosen = answer
		elif answer != null:
			chosen = [answer]
	var discarded := []
	for card in chosen:
		if is_instance_valid(card) and to_discard(card):
			discarded.append(card)
	return discarded


# --- helpers ------------------------------------------------------------------------------------

# The cards of a pile or hand in node order (bottom first, top last)
func _cards_of(zone: String, player_id: int) -> Array:
	var container = FateZones.container(zone, player_id)
	if container == null:
		return []
	return container.get_all_cards()


func _target_player(card: Card, player_id: int) -> int:
	if player_id != 0:
		return player_id
	return card.owner_id if card is FateCardTemplate else game.active_id


func _can_move(card: Card) -> bool:
	return is_instance_valid(card) and card is FateCardTemplate and card.get_parent() != null


# Token cards (FateData.TOKENS) cease to exist when they leave the table
func _is_token(card: Card) -> bool:
	return bool(card.properties.get("_token", false))


# Moves into a pile at `index` (0 bottom, -1 top). Tokens cease to exist instead.
func _to_pile(card: Card, zone: String, player_id: int, index: int) -> bool:
	var pile: Pile = FateZones.container(zone, player_id)
	if not _can_move(card) or pile == null:
		return false
	if _is_token(card):
		_cease_to_exist(card)
		return false
	if card.get_parent() == pile:
		# Already there: only the order changes
		pile.move_child(card, pile.get_card(0).get_index() if index == 0 else pile.get_child_count() - 1)
		pile.reorganize_stack()
		return true
	_free_slot(card)
	card.move_to(pile, index, null, SCRIPTED)
	return card.get_parent() == pile


# A card on the table that goes into a pile: the framework frees its slot only after the pile animation
# finished, and the next card may want the slot before that (as FateEffects.destroy does)
func _free_slot(card: Card) -> void:
	if card.get_parent() != cfc.NMAP.board:
		return
	var slot: BoardPlacementSlot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	card.set_card_rotation(0)


# A token card leaves the game: its slot is freed, its script hears it left, the node goes away
func _cease_to_exist(card: Card) -> void:
	if card.get_parent() == cfc.NMAP.board:
		_free_slot(card)
		if not card.is_energy:
			game.card_effects.card_left(card, "gone")
		game.stats.clear_card(card)
	card.queue_free()
