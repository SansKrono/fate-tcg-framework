extends FateKeyword
# Embody X (docs/FATE_RULES_SPEC.md, Section 4): by paying X generic mana in its controller's MAIN
# phase, the creature takes one of its controller's energy cards BENEATH itself. As long as the
# card stays there the creature gets +Strike and +Guard equal to that card's mana value (generic
# Cost + number of Pips). One card at a time: embodying again sends the old card to its owner's
# discard pile and the bonus follows the new card.
#
# Universal on purpose: Spirit Wielder lists "Embody" in its `_keywords` display list only (no
# `_innate_keywords` entry), so the registry would never call a normal keyword's hooks for it. A
# universal keyword is asked about every card; each hook leaves at once for cards without the
# ability (has_ability()).
#
# X: the keyword value if the card has one (innate or granted "Embody": 3), otherwise the number in
# an "Pay N: Embody" ability text, otherwise DEFAULT_X.
#
# How the card sits beneath the creature. It becomes a framework attachment (attach_to_host,
# ATTACH_BEHIND): face-down, upright, following the creature around the table (also into the
# occupied zone) and no longer an energy card. attach_to_host frees its grid slot in the energy zone
# (so it is no longer mana, and a new energy card can take the slot). The bonus is read from the
# attachment itself (stat_bonus), never stored on the keyword, so it is gone the moment the card
# stops being attached, however that happens.
#
# Decisions beyond the spec:
# * The creature leaves play (destroyed, bounced, removed): the embodied card goes to its OWNER's
#   discard pile, whatever the creature's own destination (Untethered sends the creature to the
#   removed pile, the card beneath it still goes to the discard pile). Nothing is left orphaned in a
#   grid slot or follows the creature into a pile or hand. This is hooked to the creature's
#   card_moved_to_pile / card_moved_to_hand signals, so it covers every way of leaving the table.
# * Tapped or untapped energy may be embodied. The X mana is paid by tapping OTHER untapped energy
#   cards (slot order); the card being embodied is tapped for the payment only when there are not
#   enough others (it then ends up beneath the creature, which is fine: it was spent).
# * The default chooser takes the energy card with the highest mana value; ties go to a tapped card
#   (embodying a spent card costs the player nothing) and then to slot order.
# * Embody has no once-per-turn limit; it can be repeated while mana lasts.
# * Nothing is charged unless the whole action is legal.
#
# Choosing the card. The hover action asks `chooser`, a static Callable that a later UI or AI
# replaces:
#
#   KwEmbody.chooser = func(creature: Card, candidates: Array) -> Card:
#       return candidates[0]   # one of the energy Cards in `candidates` (slot order), or null
#
# It may be a coroutine (the action awaits it, so a SelectionWindow can be used). null, or a card
# that is not a candidate, cancels the action and nothing is charged. An unset chooser uses
# default_chooser(). Tests and effects skip the chooser and call embody(creature, energy_card).

const NAME := "Embody"
const ACTION_ID := "embody"
# Used when neither the keyword value nor the ability text gives a cost
const DEFAULT_X := 3
# Marks an attachment as "embodied by this creature" (meta key on the energy card)
const META_HOST := "fate_embodied_by"

# See the header. An empty Callable means "use default_chooser".
static var chooser := Callable()


func _init() -> void:
	keyword_name = NAME
	universal = true


# --- queries -----------------------------------------------------------------------------------------

# Does this card have an Embody ability? Its display list names it, or it has the keyword (innate
# or granted, for example by an equipment)
func has_ability(card: Card) -> bool:
	if not is_instance_valid(card):
		return false
	var listed = card.properties.get("_keywords", [])
	return (listed is Array and NAME in listed) or game.keywords.has(card, NAME)


# X: the generic mana the ability costs
func cost_of(card: Card) -> int:
	var x := game.keywords.value(card, NAME)
	if x > 0:
		return x
	var found := RegEx.create_from_string("Pay (\\d+): Embody").search(
			str(card.properties.get("Abilities", "")))
	return int(found.get_string(1)) if found != null else DEFAULT_X


# The card currently beneath this creature, or null
func embodied_card(card: Card) -> Card:
	if not is_instance_valid(card):
		return null
	for attached in card.attachments:
		if is_instance_valid(attached) and attached.has_meta(META_HOST) \
				and attached.get_meta(META_HOST) == card and attached.current_host_card == card:
			return attached
	return null


# The energy cards (tapped or not) the creature's controller could embody, in slot order
func candidates(card: Card) -> Array:
	return game.player(card.controller_id).cards_in_grid("energy")


# Why the creature cannot embody now: "" if it can. `energy` (optional) is the card to embody;
# without it only the conditions that do not depend on the choice are checked. `free` skips the
# phase and the payment (an effect that embodies for nothing, outside the main phase).
func embody_problem(card: Card, energy: Card = null, free := false) -> String:
	if game.is_over or not game.is_started:
		return "The game is not going on"
	if not is_instance_valid(card) or not card is FateCardTemplate or not has_ability(card):
		return "No Embody ability"
	if not FateZones.is_creature_in_play(card):
		return "Only a creature in play can embody"
	var pool := candidates(card)
	if pool.is_empty():
		return "No energy card to embody"
	if energy != null and not energy in pool:
		return "Not one of your energy cards"
	if free:
		return ""
	if card.controller_id != game.active_id:
		return "It is not your creature"
	if game.phase != FateGame.Phase.MAIN:
		return "You can only embody in your main phase"
	if not game.mana.can_pay_generic(card.controller_id, cost_of(card), [energy], true):
		return "Not enough mana"
	return ""


func can_embody(card: Card, energy: Card = null, free := false) -> bool:
	return embody_problem(card, energy, free) == ""


# The default for `chooser`: highest mana value, then a tapped card, then slot order
static func default_chooser(_creature: Card, options: Array) -> Card:
	var best: FateCardTemplate = null
	for option in options:
		if best == null or _beats(option, best):
			best = option
	return best


static func _beats(a: FateCardTemplate, b: FateCardTemplate) -> bool:
	if a.mana_value() != b.mana_value():
		return a.mana_value() > b.mana_value()
	return a.card_rotation != 0 and b.card_rotation == 0


# --- doing it -----------------------------------------------------------------------------------------

# Embodies `energy` (one of the controller's energy cards) beneath the creature: pays X, replaces a
# card that was already beneath it (that one goes to its owner's discard pile), attaches the card
# face-down behind the creature and refreshes the stats. Returns false and changes nothing when it
# is not legal (see embody_problem). `free`: no phase check and no payment.
func embody(card: Card, energy: Card, free := false) -> bool:
	if energy == null or embody_problem(card, energy, free) != "":
		return false
	var pid: int = card.controller_id
	if not free:
		# Others first, the embodied card only if the rest cannot pay (see the header)
		game.mana.pay_generic(pid, cost_of(card), [energy], true)
	var previous := embodied_card(card)
	if previous != null:
		release(card)
	_connect(card, energy)
	energy.is_energy = false
	energy.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	energy.set_meta(META_HOST, card)
	energy.set_card_rotation(0)
	energy.attach_to_host(card, false, ["Scripted"])
	energy.set_is_faceup(false, true)
	game.stats.refresh(card)
	game.mana_changed.emit(pid)
	return true


# Sends the card beneath the creature to its owner's discard pile (it replaced, or the creature is
# leaving play). Returns whether there was one.
func release(card: Card) -> bool:
	var embodied := embodied_card(card)
	if embodied == null:
		return false
	# Detach by hand (what Card._clear_attachment_status does, without moving the host's other
	# attachments along): the card must go to ITS owner's discard, not follow the creature
	card.attachments.erase(embodied)
	card.state_finalized = false
	embodied.current_host_card = null
	embodied.remove_meta(META_HOST)
	embodied.card_unattached.emit(embodied, "card_unattached", {"host": card, "tags": ["Scripted"]})
	var owner_id: int = (embodied as FateCardTemplate).owner_id \
			if embodied is FateCardTemplate else (card as FateCardTemplate).owner_id
	embodied.move_to(FateZones.container("discard", owner_id), -1, null, ["Scripted"])
	game.stats.refresh(card)
	return true


# Hooks the signals that tell that the creature left the table, and that the card beneath it was
# detached by someone else (so the bonus on the card face follows)
func _connect(card: Card, energy: Card) -> void:
	for sig in [card.card_moved_to_pile, card.card_moved_to_hand]:
		if not sig.is_connected(_on_host_moved):
			sig.connect(_on_host_moved)
	if not energy.card_unattached.is_connected(_on_unattached):
		energy.card_unattached.connect(_on_unattached)


func _on_host_moved(card: Card, _trigger: String, _details: Dictionary) -> void:
	if is_instance_valid(card) and card.get_parent() != cfc.NMAP.board:
		release(card)


func _on_unattached(energy: Card, _trigger: String, details: Dictionary) -> void:
	# The framework emits this BEFORE it erases the card from the host's attachments, so drop the
	# marker first or the refresh below would still count the card
	if is_instance_valid(energy) and energy.has_meta(META_HOST):
		energy.remove_meta(META_HOST)
	var host = details.get("host")
	if is_instance_valid(host) and game != null:
		game.stats.refresh(host)


# --- stats ------------------------------------------------------------------------------------------------

# +Strike and +Guard equal to the mana value of the card beneath the creature
func stat_bonus(card: Card, _stat: String) -> int:
	if card.attachments.is_empty() or not has_ability(card):
		return 0
	var embodied := embodied_card(card)
	return (embodied as FateCardTemplate).mana_value() if embodied is FateCardTemplate else 0


# --- the hover button ------------------------------------------------------------------------------------

# Offered only when it is legal now (the buttons are rebuilt whenever they appear)
func actions(card: Card) -> Array:
	if not has_ability(card) or not can_embody(card):
		return []
	var x := cost_of(card)
	return [{
		"id": ACTION_ID,
		"label": "Embody (pay %d)" % x,
		"tooltip": ("Pay %d: move an energy card beneath this creature. It gains Strike and Guard "
				+ "equal to that card's mana value; a card already there goes to the discard pile") % x,
		"enabled": true,
		"run": _run_embody,
	}]


func _run_embody(card: Card) -> bool:
	var options := candidates(card)
	var picked = null
	if chooser.is_valid():
		picked = await chooser.call(card, options)
	else:
		picked = default_chooser(card, options)
	if not picked is Card or not picked in options:
		return false
	return embody(card, picked)
