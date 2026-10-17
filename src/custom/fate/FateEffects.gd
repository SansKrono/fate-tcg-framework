# The effects pipeline: destroying creatures and dealing damage to creatures and players.
# Design document: Section 8 (SYS-COMBAT) and Section 9 (SYS-MOD).
#
# Owned by FateGame (`game.effects`). Combat, card effects and keywords all go through here, so
# keyword hooks (modify_damage_taken, would_be_destroyed, death_destination, on_destroyed) apply
# to every source of damage and destruction the same way.
#
# `cause` says why: CAUSE_COMBAT, CAUSE_EFFECT (a card or ability), CAUSE_STATS (both stats
# reached 0). Keywords see it, so Indomitable can limit itself to combat damage.
class_name FateEffects
extends RefCounted

const CAUSE_COMBAT := "combat"
const CAUSE_EFFECT := "effect"
const CAUSE_STATS := "stats"
# Damage with these causes destroys a creature whose USED stat reached 0 (spec, Section 3: "the
# creature whose used stat reaches 0 is destroyed"). Damage from other causes only destroys a
# creature through the both-stats-zero rule.
const ZERO_KILLS_CAUSES := [CAUSE_COMBAT]

var game: FateGame
# Instance ids of the cards being destroyed right now, so that nothing destroys them twice
var _dying := {}


func _init(owner_game: FateGame) -> void:
	game = owner_game


# --- destruction --------------------------------------------------------------------------------

# Destroys a card on the table (any grid): asks would_be_destroyed of its keywords, moves it to
# its OWNER's zone from death_destination (default "discard") with the "Scripted" tag, frees its
# slot, runs on_destroyed, forgets its stats and emits game.creature_destroyed(card, cause).
# `source` is the Card or effect that caused it (or null). Returns whether the card was destroyed.
func destroy(card: Card, source = null, cause := CAUSE_EFFECT) -> bool:
	if not _on_table(card) or _dying.has(card.get_instance_id()):
		return false
	if not game.keywords.would_be_destroyed(card, cause, source):
		return false
	var id := card.get_instance_id()
	_dying[id] = true
	var zone: String = game.keywords.death_destination(card, cause)
	var owner_id: int = card.owner_id if card is FateCardTemplate else game.active_id
	var destination = FateZones.container(zone, owner_id)
	if destination == null:
		push_warning("FateEffects: no zone '%s' for %s, using the discard pile" % [zone, card.canonical_name])
		destination = FateZones.container("discard", owner_id)
	# Free the slot right now. The framework frees it too, but only after the card finished
	# moving into a pile, and the next card may want the slot before that.
	var slot: BoardPlacementSlot = card._placement_slot
	if slot != null and is_instance_valid(slot) and slot.occupying_card == card:
		slot.occupying_card = null
	card._placement_slot = null
	card.set_card_rotation(0)
	card.move_to(destination, -1, null, ["Scripted"])
	game.keywords.destroyed(card, cause, source)
	game.stats.clear_card(card)
	_dying.erase(id)
	game.creature_destroyed.emit(card, cause)
	return true


# --- damage ---------------------------------------------------------------------------------------------

# Deals `amount` damage to a creature Card or a FatePlayer. Returns the damage really dealt.
#
# Creature: lowers the stat the creature is using, which is its Strike if it is upright in the
# creature zone and its Guard if it is guarding or occupied (`stat` overrides that). The amount
# first goes through the modify_damage_taken hooks, then FateStats.apply_damage() (never below 0),
# then the keywords of `source` hear on_damage_dealt. For ZERO_KILLS_CAUSES the creature is
# destroyed if the stat reached 0 (`defer_death` leaves that to destroy_if_depleted(), which lets
# combat finish all its damage before anybody dies). The both-zero check of the stats layer runs
# on its own.
#
# Player: lowers `life`; at 0 or less the player is defeated (game.player_defeated).
func deal_damage(target, amount: int, source = null, cause := CAUSE_EFFECT, stat := "",
		defer_death := false) -> int:
	if target is FatePlayer:
		return _damage_player(target, amount, source, cause)
	if not target is Card or not FateZones.is_creature_in_play(target):
		return 0
	var used := stat if stat != "" else used_stat(target)
	var lowered := game.keywords.modify_damage_taken(target, used, maxi(0, amount), cause, source)
	var dealt := game.stats.apply_damage(target, used, lowered)
	if dealt > 0:
		game.keywords.damage_dealt(source, target, dealt, cause)
		game.damage_dealt.emit(source, target, dealt, cause)
	if not defer_death:
		destroy_if_depleted(target, used, source, cause)
	return dealt


# Destroys the creature if `cause` kills at 0 and its stat is 0. Returns whether it was destroyed.
func destroy_if_depleted(card: Card, stat: String, source = null, cause := CAUSE_EFFECT) -> bool:
	if cause in ZERO_KILLS_CAUSES and _on_table(card) and game.stats.current(card, stat) == 0:
		return destroy(card, source, cause)
	return false


# The stat a creature uses when it is damaged outside of an attack's own roles: Strike when it is
# upright in the creature zone, Guard when it guards (tilted) or is occupied.
func used_stat(card: Card) -> String:
	if FateZones.zone_of(card) == "creatures" and card.card_rotation == 0:
		return "Strike"
	return "Guard"


# Lowers a player's life. Returns how much (never more than their remaining life matters:
# life may go below 0, the player is defeated the moment it is 0 or less).
func _damage_player(player: FatePlayer, amount: int, source, cause: String) -> int:
	if amount <= 0 or game.is_over:
		return 0
	player.life -= amount
	game.keywords.damage_dealt(source, player, amount, cause)
	game.damage_dealt.emit(source, player, amount, cause)
	if player.life <= 0:
		game.defeat_player(player.id)
	return amount


func _on_table(card) -> bool:
	return card is Card and is_instance_valid(card) and cfc.NMAP.has("board") \
			and card.get_parent() == cfc.NMAP.board
