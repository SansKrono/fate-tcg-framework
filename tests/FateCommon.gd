extends "res://tests/UTcommon.gd"
# Shared setup and helpers for the Fate rules tests (tests/integration/test_fate_*.gd).
# Extend it with: extends "res://tests/FateCommon.gd"
#
# before_each() builds the Fate table and waits until the game has started: turn 1,
# player 1, ENERGY phase (maintenance and draw already ran). Helpers put cards in zones
# without playing them, so a test can set up any situation.

const FATE_MAIN := preload("res://src/custom/fate/FateMain.tscn")

var game: FateGame


func before_each():
	force_test_viewport()
	cfc.is_testing = true
	cfc._setup()
	cfc.game_settings.fancy_movement = false
	main = autoqfree(FATE_MAIN.instantiate())
	get_tree().get_root().add_child(main)
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	board = cfc.NMAP.board
	game = board.game
	if not game.is_started:
		await wait_for_signal(game.game_started, 30)
	await wait_seconds(0.2)


func after_all():
	cfc.game_settings.fancy_movement = true


# First card in a player's hand matching the predicate
func find_in_hand(pid: int, predicate: Callable) -> Card:
	for c in FateZones.container("hand", pid).get_all_cards():
		if predicate.call(c):
			return c
	return null


# Moves all cards of a player's hand to their removed pile, so that tests control the hand
func empty_hand(pid: int) -> void:
	for c in FateZones.container("hand", pid).get_all_cards():
		c.move_to(FateZones.container("removed", pid), -1, null, ["Scripted"])
	await wait_seconds(0.3)


# Creates a card in a player's hand (it is taken from nowhere, not from the deck)
func put_in_hand(pid: int, card_name: String) -> Card:
	var card: Card = cfc.instance_card(card_name)
	var deck_pile: Pile = FateZones.container("deck", pid)
	deck_pile.add_child(card)
	card.assign_owner(pid)
	card._determine_idle_state()
	card.move_to(FateZones.container("hand", pid), -1, null, ["Scripted"])
	await wait_seconds(0.3)
	return card


# Creates a card on a zone of the table ("creatures", "relics", "occupied", ...), upright
func put_on_table(pid: int, card_name: String, zone: String) -> Card:
	var card := game.place_card_on_table(card_name, pid, zone)
	await get_tree().process_frame
	return card


# Creates a face-down energy card for a player. `card_name` decides its domain
func put_energy(pid: int, card_name: String, tapped := false) -> Card:
	var card := game.place_card_on_table(card_name, pid, "energy")
	card.is_energy = true
	card.set_is_faceup(false, true)
	if tapped:
		card.set_card_rotation(90)
	await get_tree().process_frame
	return card


# Total mana of a pool
func total_mana(pool: Dictionary) -> int:
	var total := 0
	for v in pool.values():
		total += v
	return total


# Advances the game to the MAIN phase of the active player (making the energy choice by
# drawing, unless it was made already)
func go_to_main() -> void:
	if game.phase == FateGame.Phase.ENERGY:
		game.draw_extra_card()
	assert_eq(game.phase, FateGame.Phase.MAIN, "Test setup: reached the main phase")


# Gives a player untapped energy: `per_domain` cards of each of their two domains (6 mana
# by default; the dearest cards cost 7)
func fill_mana(pid: int, per_domain := 3) -> void:
	for domain in game.player(pid).domains:
		var card_name := _energy_card_of(domain)
		for _i in range(per_domain):
			await put_energy(pid, card_name)


# A card name of a domain, used as an energy card
func _energy_card_of(domain: String) -> String:
	for n in FateData.CARDS:
		if FateData.CARDS[n].Domain == domain and FateData.CARDS[n].Type == "Relic":
			return n
	return ""


# --- creatures and combat ------------------------------------------------------------------------

# Defines a test creature card with the given stats and innate keywords and returns its name.
# It is a copy of a real creature, so it has a card face; it lives in cfc.card_definitions for
# this run only. The same stats and keywords always give the same name.
func define_creature(strike: int, guard: int, innate := {}) -> String:
	var card_name := "Test %d/%d" % [strike, guard]
	if not innate.is_empty():
		card_name += " " + str(innate)
	var def: Dictionary = FateData.CARDS["Moral Captain"].duplicate(true)
	def["Strike"] = strike
	def["Guard"] = guard
	def["_innate_keywords"] = innate.duplicate()
	cfc.card_definitions[card_name] = def
	return card_name


# Puts a creature with the given stats on the table without playing it. `zone` is "creatures"
# (default) or "occupied"; `tilted` puts a creature in the guard position (tilted 90 degrees).
# For a card from the real card list pass its name as `strike_or_name`.
func put_creature(pid: int, strike_or_name, guard := 1, innate := {}, tilted := false,
		zone := "creatures") -> Card:
	var card_name: String = strike_or_name if strike_or_name is String \
			else define_creature(strike_or_name, guard, innate)
	var card := game.place_card_on_table(card_name, pid, zone)
	assert_not_null(card, "Test setup: room in the %s zone" % zone)
	if tilted or zone == "occupied":
		card.set_card_rotation(90)
	await get_tree().process_frame
	return card


# Brings the game to the declare step of the active player's combat phase (through the energy
# and main phases). The end phase waits for the player, so that damage taken during this turn is
# still there to look at after the combat resolved (the next maintenance would reset it).
func start_combat() -> void:
	game.turn.end_phase_waits_for_player = true
	if game.phase == FateGame.Phase.ENERGY:
		game.draw_extra_card()
	if game.phase == FateGame.Phase.MAIN:
		game.advance_phase()
	assert_eq(game.phase, FateGame.Phase.COMBAT_DECLARE, "Test setup: declare step reached")


# Runs the rest of a combat phase with the attacks already declared: confirm the attackers, the
# blocks (declare them before) and let everything resolve. Ends in the END phase.
func run_combat() -> void:
	game.combat.confirm_attackers()
	if game.phase == FateGame.Phase.COMBAT_INTERCEPT:
		game.combat.confirm_blocks()
