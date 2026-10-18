# Builds the decks. Design document: Section 11.2 (deck building).
class_name FateDecks
extends RefCounted

# Deck rules: exactly DECK_SIZE cards, at most MAX_COPIES copies of any card, and a single copy
# of a legendary card (a unique card, which includes every God)
const DECK_SIZE := 40
const MAX_COPIES := 3
const MAX_LEGENDARY_COPIES := 1

# The mono-domain decks: card name -> copies. Each is 40 cards with a curve that lets a player who
# makes an energy drop every turn spend nearly all of their mana from turn 2 on. Mana value is
# the generic cost plus the pips, and every energy card is 1 mana of its own domain, so a mono
# deck never has colour problems and the curve alone decides how smooth the early turns are.
#
# Order (an aggressive human army, the pool has nothing at 1 and little above 4):
#   mana value  1   2   3   4   5   6   7
#   cards       0  18  16   5   0   0   1      25 creatures, 15 spells, 1 God
# Primal (a ramping beast deck with a top end of Treespirits, board wipes and Teshra):
#   mana value  1   2   3   4   5   6   7
#   cards       5  11  11   8   2   2   1      26 creatures, 9 spells, 5 relics, 1 God
const DECKLISTS := {
	"Order": {
		# 2
		"Righteous Guard": 3,
		"Streetside Recruiter": 3,
		"Insightful Investigator": 2,
		"Holy Healer": 2,
		"Sigil Mage": 2,
		"Faithful Worshiper": 2,
		"Hold the Line": 2,
		"Smite": 2,
		# 3
		"Moral Captain": 3,
		"Tactical Combatant": 3,
		"Wave of Fear": 3,
		"Reinforcements": 3,
		"Battle Ready": 2,
		"Recovering Resources": 1,
		"War of Attrition": 1,
		# 4
		"Devote Paladin": 3,
		"Zelith, Mage Justiciar": 1,
		"Equal Footing": 1,
		# 7
		"Lucran, Divine Saviour": 1,
	},
	"Primal": {
		# 1
		"Meek Minion": 3,
		"Return to Nature": 2,
		# 2
		"Beetle Brawler": 3,
		"Goblin Scout Leader": 3,
		"Dragon's Tooth": 3,
		"Forests Protection": 2,
		# 3
		"Elder Spirit": 3,
		"Battering Ram": 3,
		"Spirit Wielder": 2,
		"Primal Wraith": 2,
		"Ancient Tree": 1,
		# 4
		"Feracious Beast": 3,
		"Ironside Beetle": 3,
		"Guardian Spirits": 1,
		"Teshra's War Gauntlets": 1,
		# 5
		"Wraithful Treespirits": 2,
		# 6
		"Toll of War": 1,
		"No Where to Hide": 1,
		# 7
		"Teshra, Primal Mother": 1,
	},
}


# The most copies of a card a deck may hold: MAX_COPIES, or one for a legendary card
static func copy_limit(card_name: String) -> int:
	var props: Dictionary = cfc.card_definitions[card_name]
	var limit := MAX_LEGENDARY_COPIES if is_legendary(props) else MAX_COPIES
	return mini(limit, props.get("_max_allowed", MAX_COPIES))


# A legendary card is a unique card; the Gods are the legendary creatures
static func is_legendary(props: Dictionary) -> bool:
	return props.get("_unique", false) or "God" in props.get("Tags", [])


# Mana value: the generic cost plus one mana per pip
static func mana_value(card_name: String) -> int:
	var props: Dictionary = cfc.card_definitions[card_name]
	return int(props.get("Cost", 0)) + str(props.get("Pips", "")).length()


# The mono deck list for the domains ({} if there is none, then `build` generates a deck)
static func decklist(domains: Array) -> Dictionary:
	if domains.size() == 1 and DECKLISTS.has(domains[0]):
		return DECKLISTS[domains[0]]
	return {}


# The mana curve of a deck list: mana value -> number of cards
static func mana_curve(list: Dictionary) -> Dictionary:
	var curve := {}
	for card_name in list:
		var mv := mana_value(card_name)
		curve[mv] = curve.get(mv, 0) + list[card_name]
	return curve


# The ways a deck list breaks the deck rules, empty if it is legal. `domains` are the domains
# the cards must belong to.
static func problems(list: Dictionary, domains: Array) -> Array:
	var found := []
	var total := 0
	for card_name in list:
		if not cfc.card_definitions.has(card_name):
			found.append("%s is not a card" % card_name)
			continue
		var props: Dictionary = cfc.card_definitions[card_name]
		total += list[card_name]
		if list[card_name] > copy_limit(card_name):
			found.append("%s: %d copies, the limit is %d" % [card_name, list[card_name], copy_limit(card_name)])
		if props.get("_token", false) or props.get("Type") == "Doctrine":
			found.append("%s cannot be in a deck" % card_name)
		if not props.get("_domains", []).any(func(d): return d in domains):
			found.append("%s is not of the domains %s" % [card_name, domains])
	if total != DECK_SIZE:
		found.append("%d cards, a deck has %d" % [total, DECK_SIZE])
	return found


# Returns an array of card names forming a legal deck for the given domains: `custom_list` (card name ->
# copies, not checked here, see `problems`) if given, else the mono deck list if there is one, else
# DECK_SIZE cards taken evenly from the domains' cards (up to their copy limit) cheapest first.
# Shuffled with the game RNG so that seeded games are repeatable.
static func build(domains: Array, rng: RandomNumberGenerator, custom_list := {}) -> Array:
	var deck := []
	var list: Dictionary = custom_list if not custom_list.is_empty() else decklist(domains)
	if list.is_empty():
		deck = _generated(domains)
	else:
		for card_name in list:
			for _i in range(list[card_name]):
				deck.append(card_name)
	# Fisher-Yates shuffle with the game RNG so that seeded games are repeatable
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck


# A deck for domains without a deck list: the cards of the domains by mana value, then name,
# a copy of each in turn until the deck is full
static func _generated(domains: Array) -> Array:
	var pool := []
	for card_name in cfc.card_definitions:
		var props: Dictionary = cfc.card_definitions[card_name]
		if props.get("_token", false) or props.get("Type") == "Doctrine":
			continue
		if props.get("_domains", []).any(func(d): return d in domains):
			pool.append(card_name)
	pool.sort_custom(func(a, b): return [mana_value(a), a] < [mana_value(b), b])
	var deck := []
	var copies := {}
	var progress := true
	while deck.size() < DECK_SIZE and progress:
		progress = false
		for card_name in pool:
			if deck.size() >= DECK_SIZE:
				break
			if copies.get(card_name, 0) < copy_limit(card_name):
				copies[card_name] = copies.get(card_name, 0) + 1
				deck.append(card_name)
				progress = true
	return deck


# The doctrine card names for a player: all three tiers of the first domain's branch.
static func doctrines_for(domains: Array) -> Array:
	var found := []
	for card_name in cfc.card_definitions:
		var props: Dictionary = cfc.card_definitions[card_name]
		if props.get("Type") == "Doctrine" and props.get("Domain") == domains[0]:
			found.append(card_name)
	found.sort_custom(func(a, b): return cfc.card_definitions[a]["Cost"] < cfc.card_definitions[b]["Cost"])
	return found


# --- the deck catalogue ---------------------------------------------------------------------------------------
#
# What a player can pick on the deck selection screen (FateDeckSelect): per domain an OPTIMISED deck, tuned with
# the data of the AI simulation lab (src/custom/fate/sim/), and a STARTER deck (the default list of the domain,
# or the generated deck for a domain without a list). A preset is
#   {"id": "order_optimised", "name": ..., "domain": "Order", "tier": "Optimised" | "Starter", "blurb": ..., "list": {card: copies}}

const DOMAIN_ORDER := ["Order", "Primal", "Chaos", "Innovation"]
const TIER_OPTIMISED := "Optimised"
const TIER_STARTER := "Starter"

# The optimised decks, by domain: {"name", "blurb", "list"}. Built with the AI simulation lab (docs/FATE_DECKS.md).
const OPTIMISED := {
	"Order": {
		"name": "Iron Vanguard",
		"blurb": "A fast human army. Cheap soldiers and Reinforcements go wide, Moral Captain and Battle Ready send the whole line in with extra Strike, Devote Paladin adds Savage, Smite removes the blocker that matters and Lucran closes the game.",
		"list": {
			# 2
			"Faithful Worshiper": 3,
			"Hold the Line": 3,
			"Holy Healer": 3,
			"Sigil Mage": 3,
			"Smite": 3,
			"Streetside Recruiter": 3,
			# 3
			"Battle Ready": 3,
			"Moral Captain": 3,
			"Recovering Resources": 3,
			"Reinforcements": 3,
			"Tactical Combatant": 3,
			"War of Attrition": 2,
			# 4
			"Devote Paladin": 3,
			"Zelith, Mage Justiciar": 1,
			# 7
			"Lucran, Divine Saviour": 1,
		},
	},
	"Primal": {
		"name": "Wild Stampede",
		"blurb": "Big, efficient beasts on a smooth curve. Battering Ram, Beetle Brawler, Feracious Beast and Ironside Beetle hit hard with Savage, Elder Spirit and Cycle of Life ramp your energy, and Wraithful Treespirits and Teshra finish the game.",
		"list": {
			# 1
			"Meek Minion": 3,
			"Return to Nature": 2,
			# 2
			"Beetle Brawler": 3,
			"Dragon's Tooth": 3,
			"Goblin Scout Leader": 3,
			# 3
			"Ancient Tree": 1,
			"Battering Ram": 3,
			"Cycle of Life": 3,
			"Elder Spirit": 3,
			"Spirit Wielder": 2,
			# 4
			"Feracious Beast": 3,
			"Guardian Spirits": 2,
			"Ironside Beetle": 3,
			"Teshra's War Gauntlets": 1,
			# 5
			"Wraithful Treespirits": 2,
			# 6
			"No Where to Hide": 1,
			"Toll of War": 1,
			# 7
			"Teshra, Primal Mother": 1,
		},
	},
	"Chaos": {
		"name": "Abyssal Usurpers",
		"blurb": "Steals the other player's army. Unseen Manipulator and Harbinger of Krelgar take their creatures, Claimed by the Abyss and Double Agent turn their attackers against them, and unblockable Specters keep the pressure on until Krelga ends it.",
		"list": {
			# 1
			"Enthralled Civilian": 3,
			# 2
			"Double Agent": 3,
			"Murkmist Gemstone": 3,
			"Repurpose": 2,
			"Specter of Hate": 3,
			"Unending Echo": 3,
			"Unseen Reach": 3,
			# 3
			"Cultist Fanatic": 3,
			"Dockside Alter": 3,
			"Harbinger of Krelgar": 3,
			# 4
			"Claimed by the Abyss": 3,
			"Dockside Ambusher": 3,
			"Ikthar, The Great Summoner": 1,
			"Unseen Manipulator": 3,
			# 7
			"Krelga, Abyssal Nightmare": 1,
		},
	},
	"Innovation": {
		"name": "Goblin Foundry",
		"blurb": "A scrap and ingot engine. Cheap goblins make scrap, Acquisition Fabricator and Factory Crafter turn it into ingots and 3/3 automatons, Battle Smith arms the army with hammers and Thrang is the 6/6 finisher. Slow to start, hard to break.",
		"list": {
			# 1
			"Goblin Ledgerkeeper": 3,
			# 2
			"Factory Shutdown": 3,
			"Garbage Heap": 3,
			"Safety Measure": 3,
			"Scrap Recycler": 3,
			"Skulking Goblin": 3,
			# 3
			"Acquisition Fabricator": 3,
			"Battle Smith": 3,
			"Factory Crafter": 3,
			"Rarink, Crafty Opportunist": 1,
			"Rustmarket Tinkerer": 3,
			"Scrap Cannon": 3,
			# 4
			"Brogir, Master Artificer": 1,
			"Steelwork Salvager": 3,
			# 5
			"Thrang's Crafting Table": 1,
			# 7
			"Thrang, Perpetual Innovation": 1,
		},
	},
}


# The catalogue: the optimised deck of every domain, then the starter decks
static func presets() -> Array:
	var found: Array = []
	for tier in [TIER_OPTIMISED, TIER_STARTER]:
		for domain in DOMAIN_ORDER:
			found.append(_preset(domain, tier))
	return found


# One preset by id ("order_optimised"), {} if there is none
static func preset(preset_id: String) -> Dictionary:
	for domain in DOMAIN_ORDER:
		for tier in [TIER_OPTIMISED, TIER_STARTER]:
			if preset_id == preset_id_of(domain, tier):
				return _preset(domain, tier)
	return {}


static func preset_id_of(domain: String, tier: String) -> String:
	return "%s_%s" % [domain.to_lower(), tier.to_lower()]


static func _preset(domain: String, tier: String) -> Dictionary:
	if tier == TIER_OPTIMISED:
		var data: Dictionary = OPTIMISED[domain]
		return {"id": preset_id_of(domain, tier), "name": data.name, "domain": domain, "tier": tier,
				"blurb": data.blurb, "list": data.list.duplicate()}
	var list := decklist([domain])
	if list.is_empty():
		list = counts_of(_generated([domain]))
	return {"id": preset_id_of(domain, tier), "name": "%s Starter" % domain, "domain": domain, "tier": tier,
			"blurb": "The basic %s deck: a plain selection of the domain's cards." % domain, "list": list.duplicate()}


# {card: copies} of a list of card names
static func counts_of(names: Array) -> Dictionary:
	var counts := {}
	for card_name in names:
		counts[card_name] = counts.get(card_name, 0) + 1
	return counts


# How many cards of each type a deck list has: {"Creature": 25, "Spell": 15, ...}
static func type_counts(list: Dictionary) -> Dictionary:
	var counts := {}
	for card_name in list:
		var card_type: String = str(cfc.card_definitions[card_name].get("Type", "?"))
		counts[card_type] = counts.get(card_type, 0) + int(list[card_name])
	return counts


# Makes `preset_id` the deck of a player for the table that opens next (FateGame.domain_override and
# decklist_override, which every new table reads). Returns false for an unknown id.
static func select(player_id: int, preset_id: String) -> bool:
	var chosen := preset(preset_id)
	if chosen.is_empty():
		return false
	FateGame.domain_override[player_id] = [chosen.domain]
	FateGame.decklist_override[player_id] = chosen.list.duplicate()
	return true


# Forgets the choices: the next table plays the default decks again
static func clear_selection() -> void:
	FateGame.domain_override = {}
	FateGame.decklist_override = {}
