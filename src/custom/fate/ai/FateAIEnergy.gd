# The ENERGY phase of the Fate AI: play a card face-down as energy, or draw an extra card
# (docs/FATE_RULES_SPEC.md D3: one of the two, never neither).
#
# This is the "land drop" decision of the game. The reasoning, as a human would put it:
#   * Energy is the only way to pay for anything, and the energy zone only grows, so early on every
#     turn is an energy turn until the deck's curve is covered (profile.energy_target).
#   * A card that cannot do anything for the player (a "dead" card: the engine runs no effect for
#     most spells and relics, see FateAIEval.LIVE_EFFECTS) is the best energy there is: it costs
#     nothing to give up.
#   * Once there is enough energy, more cards beat more energy: draw. Exceptions: the hand is nearly
#     full (a card drawn into a full hand is discarded) or +1 energy lets a good card be played now.
#   * Which card to give up: the one the player would miss least (FateAIEval.keep_value).
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const Eval := preload("res://src/custom/fate/ai/FateAIEval.gd")

const HAND_LIMIT := 10
# Draw an extra card only with at least this many cards left in the deck
const DECK_SAFETY := 4


# Decides the choice of the phase. Returns {"kind": "energy" | "draw", "card": Card or null,
# "why": String}. `state` is a snapshot of the AI's seat.
static func decide(game: FateGame, state: Dictionary, profile) -> Dictionary:
	var me: int = state.me
	var hand: Array = state.hand_me
	var energy_count: int = state.mana[me].total
	if hand.is_empty():
		return {"kind": "draw", "card": null, "why": "no card to give up"}
	var cards: Array = []
	var dead: Array = []
	for c in hand:
		if Eval.role(game, c) == "dead":
			dead.append(c)
		else:
			cards.append(c)
	var hand_size := hand.size()
	# An empty deck loses the game (FateLibrary): never draw the deck away. The turn's own draw still needs a card
	# next turn, so an extra draw needs a few cards to spare.
	var deck_left: int = state.deck_count[me]
	if deck_left < DECK_SAFETY:
		return {"kind": "energy", "card": _least_missed(game, hand, energy_count, profile),
				"why": "only %d cards left in the deck: no extra draw" % deck_left}
	var target: int = profile.energy_target
	var want_energy := energy_count < target
	var why := "below the energy target (%d < %d)" % [energy_count, target]
	if energy_count >= profile.max_energy:
		want_energy = false
		why = "enough energy"
	if energy_count < 2:
		want_energy = true
		why = "too little energy to play anything"
	if not want_energy:
		# Past the target: only when a good card needs exactly one more, or the hand overflows
		if _enables_play(game, cards, energy_count):
			want_energy = true
			why = "one more energy lets a card be played now"
		elif hand_size >= HAND_LIMIT - 1 and energy_count < profile.max_energy + 2:
			want_energy = true
			why = "the hand is nearly full"
		elif not dead.is_empty() and hand_size >= HAND_LIMIT - 2:
			want_energy = true
			why = "a dead card is free energy and the hand is full"
	if not want_energy:
		return {"kind": "draw", "card": null, "why": "enough energy, draw for cards"}
	var pick := _least_missed(game, hand, energy_count, profile)
	return {"kind": "energy", "card": pick, "why": why}


# Does one more energy let a live card of the hand be played this turn when it could not be before?
static func _enables_play(game: FateGame, cards: Array, energy_count: int) -> bool:
	for c in cards:
		if Eval.role(game, c) == "creature" and c.mana_value() == energy_count + 1:
			return true
	return false


# The card to put in the energy zone: dead cards first, then the lowest keep value; with ties the
# one that is hardest to cast soon goes first (the early curve stays in hand)
static func _least_missed(game: FateGame, hand: Array, energy_count: int, profile) -> Card:
	var best: Card = null
	var best_value := INF
	for c in hand:
		var v := Eval.keep_value(game, c, energy_count)
		if profile.noise > 0.0:
			v += profile.rng.randf_range(0.0, profile.noise * 0.5)
		# A dead card that costs a lot is the best of the dead ones: nobody will ever cast it
		v -= 0.01 * float(c.mana_value())
		if v < best_value:
			best_value = v
			best = c
	return best
