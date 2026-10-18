extends FateKeyword
# Evolve / Evolution X (Name) (docs/FATE_TCG_DESIGN.md Section 9.1 and Section 12 item 6; Beetle Brawler:
# "Evolution 2 (Ironside Beetle)"). In its controller's MAIN phase a creature with the ability can be
# evolved: pay X generic mana, the creature is consumed (it goes to its owner's discard pile, it does not
# die: no death triggers), the owner's deck is searched for the named card, that card is put on the
# creature zone (it entered play this turn, so it is summoning sick) and has Charge until end of turn, and
# the deck is shuffled.
#
# Universal on purpose: Beetle Brawler lists "Evolution" in its `_keywords` display list only (no
# `_innate_keywords` entry), so the registry would never call a normal keyword's hooks for it. Each hook
# leaves at once for cards without the ability (has_ability()).
#
# Where the ability comes from, in this order
#   * the Abilities text: "Evolution 2 (Ironside Beetle)" / "Evolve (Ironside Beetle)" (X is optional, 0
#     if absent)
#   * a keyword "Evolution" or "Evolve" on the card (innate or granted; its value is X); then the target
#     name must come from the card's `_evolves_into` property or the text
#
# Decisions beyond the docs
# * The deck is searched for the first card with the exact name; if there is none the action is not
#   offered and `evolve()` changes nothing (nothing is charged), so a player cannot throw a creature away
#   for nothing.
# * The evolved card lands in the OWNER's creature zone; only a creature the player owns and controls can
#   evolve. A creature stolen from the opponent cannot (its owner's deck and discard are not the
#   controller's business).
# * The creature may be in the creature or the occupied zone. The replacement goes to the creature zone
#   (upright, strike position), so a free creature slot is needed unless the evolving creature stands
#   there itself.
# * The search, move and shuffle are low-level on purpose (they do not depend on game.library). They can
#   be switched to game.library.search / to_table / shuffle later.
# * "Pay X" is generic mana (game.mana.pay_generic).

const NAME := "Evolution"
const ALIAS := "Evolve"
const ACTION_ID := "evolve"
# "Evolution 2 (Ironside Beetle)", "Evolution (Name)", "Evolve (Name)"
const TEXT_PATTERN := "Evol(?:ution|ve)(?:\\s+(\\d+))?\\s*\\(([^)]+)\\)"


func _init() -> void:
	keyword_name = NAME
	universal = true


# --- queries -------------------------------------------------------------------------------------------

func _match(card: Card) -> RegExMatch:
	return RegEx.create_from_string(TEXT_PATTERN).search(str(card.properties.get("Abilities", "")))


# Does this card have an Evolve ability that names a card?
func has_ability(card: Card) -> bool:
	return is_instance_valid(card) and evolves_into(card) != ""


# The name of the card it evolves into, "" if none
func evolves_into(card: Card) -> String:
	if not is_instance_valid(card):
		return ""
	var named := str(card.properties.get("_evolves_into", ""))
	if named != "":
		return named
	var found := _match(card)
	return found.get_string(2).strip_edges() if found != null else ""


# X: the generic mana the ability costs (the keyword value, else the number in the text, else 0)
func cost_of(card: Card) -> int:
	var x := maxi(game.keywords.value(card, NAME), game.keywords.value(card, ALIAS))
	if x > 0:
		return x
	var found := _match(card)
	if found != null and found.get_string(1) != "":
		return int(found.get_string(1))
	return 0


# The card in the owner's deck that would be fetched (the first with the name), or null
func target_in_deck(card: Card) -> Card:
	var wanted := evolves_into(card)
	if wanted == "" or not card is FateCardTemplate:
		return null
	var deck = FateZones.container("deck", card.owner_id)
	if deck == null:
		return null
	for candidate in deck.get_all_cards():
		if candidate.canonical_name == wanted:
			return candidate
	return null


# Why the creature cannot evolve now: "" if it can. `free` skips the phase and the payment (an effect that
# evolves for nothing, outside the main phase).
func evolve_problem(card: Card, free := false) -> String:
	if game.is_over or not game.is_started:
		return "The game is not going on"
	if not is_instance_valid(card) or not card is FateCardTemplate or not has_ability(card):
		return "No Evolve ability"
	if not FateZones.is_creature_in_play(card):
		return "Only a creature in play can evolve"
	if card.owner_id != card.controller_id:
		return "You do not own this creature"
	if target_in_deck(card) == null:
		return "%s is not in your deck" % evolves_into(card)
	var zone := FateZones.zone_of(card)
	if zone != "creatures" and game.player(card.controller_id).grid("creatures").find_available_slot() == null:
		return "The creature zone is full"
	if free:
		return ""
	if card.controller_id != game.active_id:
		return "It is not your creature"
	if game.phase != FateGame.Phase.MAIN:
		return "You can only evolve in your main phase"
	if not game.mana.can_pay_generic(card.controller_id, cost_of(card)):
		return "Not enough mana"
	return ""


func can_evolve(card: Card, free := false) -> bool:
	return evolve_problem(card, free) == ""


# --- doing it ----------------------------------------------------------------------------------------------

# Evolves the creature: pays X, consumes it, puts the named card from the deck on the creature zone with
# Charge until end of turn and shuffles the deck. Returns the new creature, or null (nothing changed) if
# it is not legal (see evolve_problem). `free`: no phase check and no payment.
func evolve(card: Card, free := false) -> Card:
	if evolve_problem(card, free) != "":
		return null
	var pid: int = card.owner_id
	var fetched := target_in_deck(card)
	if not free:
		game.mana.pay_generic(card.controller_id, cost_of(card))
	# 1. consume the evolving creature: it goes to its owner's discard pile (not destroyed) and its slot is
	#    free at once (game.costs.consume)
	game.costs.consume(card)
	# 2. the fetched card onto the creature zone. A scripted move is never refused by the play rules; the
	#    framework reports the entry (FateCardTemplate.common_post_move_scripts -> card_entered), so its
	#    on_enter runs once, without a call from here
	var slot := game.player(pid).grid("creatures").find_available_slot()
	if slot == null:
		# Cannot happen after evolve_problem (the evolving creature's own slot, or a free one, exists)
		return null
	fetched.move_to(cfc.NMAP.board, -1, slot, ["Scripted"])
	if FateZones.zone_of(fetched) != "creatures":
		return null
	if fetched is FateCardTemplate:
		fetched.apply_zone_look("creatures", "up", false)
		fetched.entered_turn = game.turn_number
	game.stats.grant_keyword(fetched, "Charge", 1, FateStats.EXPIRY_END_OF_TURN, fetched)
	# 3. shuffle (cfc.game_rng, no animation). Could be game.library.shuffle(pid)
	_shuffle_deck(pid)
	return fetched


func _shuffle_deck(player_id: int) -> void:
	var deck = FateZones.container("deck", player_id)
	if deck == null:
		return
	var cards: Array = deck.get_all_cards().duplicate()
	CFUtils.shuffle_array(cards)
	for i in range(cards.size()):
		deck.move_child(cards[i], i)
	deck.reorganize_stack()


# --- the hover button -------------------------------------------------------------------------------------------

# Offered when the card has the ability and it is legal now (the buttons are rebuilt whenever they appear)
func actions(card: Card) -> Array:
	if not has_ability(card) or not can_evolve(card):
		return []
	var x := cost_of(card)
	return [{
		"id": ACTION_ID,
		"label": "Evolve (pay %d)" % x if x > 0 else "Evolve",
		"tooltip": ("Pay %d: discard this creature, search your deck for %s and put it on the field. "
				+ "It has Charge until end of turn") % [x, evolves_into(card)],
		"enabled": true,
		"run": _run_evolve,
	}]


func _run_evolve(card: Card) -> bool:
	return evolve(card) != null
