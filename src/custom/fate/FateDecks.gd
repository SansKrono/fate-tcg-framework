# Builds the decks. Design document: Section 11.2 (deck building).
class_name FateDecks
extends RefCounted

const DECK_SIZE := 60


# Returns an array of card names forming a legal deck for the given domains:
# at least DECK_SIZE cards if the pool allows it, no more copies of a card than
# its _max_allowed (4, or 1 for unique cards). Deterministic apart from the
# order, which is shuffled with the game RNG.
static func build(domains: Array, rng: RandomNumberGenerator) -> Array:
	var pool := []
	for card_name in cfc.card_definitions:
		var props: Dictionary = cfc.card_definitions[card_name]
		if props.get("_token", false) or props.get("Type") == "Doctrine":
			continue
		for d in props.get("_domains", []):
			if d in domains:
				pool.append(card_name)
				break
	pool.sort()
	var deck := []
	var copies := {}
	var progress := true
	while deck.size() < DECK_SIZE and progress:
		progress = false
		for card_name in pool:
			if deck.size() >= DECK_SIZE:
				break
			var limit: int = cfc.card_definitions[card_name].get("_max_allowed", 4)
			if copies.get(card_name, 0) < limit:
				copies[card_name] = copies.get(card_name, 0) + 1
				deck.append(card_name)
				progress = true
	# Fisher-Yates shuffle with the game RNG so that seeded games are repeatable
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
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
