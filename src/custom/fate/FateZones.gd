# Naming and layout of the Fate zones.
#
# The framework looks containers up by node name (lowercased) in cfc.NMAP and
# grids by their label text, so every zone has a deterministic name per player.
# Design document: Section 6 (Zones and piles).
class_name FateZones
extends RefCounted

# Zones implemented as card piles, one per player
const PILES := ["deck", "discard", "removed"]
# Zones implemented as board placement grids, one per player
const GRIDS := ["creatures", "occupied", "relics", "energy", "field", "doctrines"]
# The one grid shared by both players
const WORLD_GRID := "World"

const PLAYER_COUNT := 2
# The zones where a creature is in play: ready to fight in the creature zone, or tilted and
# working in the occupied zone
const CREATURE_ZONES := ["creatures", "occupied"]


# The node name of a pile or hand ("Deck_P1", "Hand_P2")
static func node_name(zone: String, player_id: int) -> String:
	return "%s_P%d" % [zone.capitalize(), player_id]


# The key under which the pile or hand is stored in cfc.NMAP
static func nmap_key(zone: String, player_id: int) -> String:
	return node_name(zone, player_id).to_lower()


# The name (label text) of a placement grid ("Creatures P1")
static func grid_name(zone: String, player_id: int) -> String:
	if zone == "world":
		return WORLD_GRID
	return "%s P%d" % [zone.capitalize(), player_id]


# Returns the pile or hand of a player, or null if the board is not built yet
static func container(zone: String, player_id: int):
	return cfc.NMAP.get(nmap_key(zone, player_id))


# Returns the placement grid of a player (or the world grid)
static func grid(zone: String, player_id: int) -> BoardPlacementGrid:
	if not cfc.NMAP.has("board"):
		return null
	return cfc.NMAP.board.get_grid(grid_name(zone, player_id))


static func opponent_of(player_id: int) -> int:
	return 2 if player_id == 1 else 1


# The zone a card stands in on the table ("creatures", "occupied", "relics", "energy", "field",
# "doctrines", "world"), or "" if it is not in a placement grid (hand, piles, floating).
static func zone_of(card: Card) -> String:
	if not is_instance_valid(card) or not cfc.NMAP.has("board") \
			or card.get_parent() != cfc.NMAP.board:
		return ""
	var slot = card._placement_slot
	if slot == null or not is_instance_valid(slot):
		return ""
	var label: String = slot.get_grid_name()
	if label == WORLD_GRID:
		return "world"
	return label.rsplit(" ", true, 1)[0].to_lower()


# Is the card a creature in play? Creatures in play stand in the creature or the occupied zone
# (of either player).
static func is_creature_in_play(card: Card) -> bool:
	return is_instance_valid(card) and card.properties.get("Type") == "Creature" \
			and zone_of(card) in CREATURE_ZONES
