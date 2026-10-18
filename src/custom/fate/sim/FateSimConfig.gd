# The description of one AI simulation run and the helpers around it. Everything is plain data (Dictionary,
# Array, String, numbers), so a run can be written to a JSON file for the worker processes to read.
#
#   config = {
#     "run_id":      folder name under user://fate_sim/
#     "matchups":    [{"a": deck, "b": deck}, ...]   every matchup plays `games` games
#     "games":       games per matchup
#     "workers":     how many Godot processes play in parallel
#     "levels":      [level of deck a, level of deck b]  (FateAIProfile.Level: 0 easy, 1 normal, 2 hard)
#     "seed":        text; the same seed and config give the same games
#     "swap_seats":  deck a is seat 1 (goes first) in even games and seat 2 in odd games
#     "turn_cap":    a game still going on this turn is a draw (reason "turn_cap")
#     "game_seconds": wall-clock seconds one game may take before it is stopped (reason "stall")
#     "doctrines":   the doctrine cards both players start with are in play (as in a real game)
#   }
#   deck = {"label": "Order", "domains": ["Order"], "list": {card name: copies}}  (list optional: without
#          it the deck of the domains is used, see FateDecks)
#
# Game numbers: game g of a run (0 .. matchups * games - 1) belongs to matchup g % matchups, and is the
# game g / matchups of that matchup. Interleaving keeps a half-finished run balanced across the matchups.
#
# No class_name (see FateAIEval.gd).
extends RefCounted

const DOMAINS := ["Order", "Primal", "Chaos", "Innovation"]
const ROOT_DIR := "user://fate_sim"
const LEVEL_NAMES := ["easy", "normal", "hard"]


static func deck(domains: Array, label := "", list := {}) -> Dictionary:
	return {"label": label if label != "" else "+".join(domains), "domains": domains.duplicate(), "list": list.duplicate()}


# A deck of a single domain, from its deck list (or the generated one)
static func domain_deck(domain: String) -> Dictionary:
	return deck([domain], domain)


# A deck read from a JSON file: {"label": "...", "domains": [...], "cards": {name: copies}} or just
# {name: copies} (the label is then the file name and the domain is taken from the cards). Returns
# {"error": text} when the file cannot be used or the deck breaks the deck rules (FateDecks.problems).
static func deck_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "no such file: %s" % path}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"error": "not a JSON object: %s" % path}
	var list: Dictionary = parsed.get("cards", parsed) if parsed.has("cards") else parsed
	var label: String = str(parsed.get("label", path.get_file().get_basename())) if parsed.has("cards") \
			else path.get_file().get_basename()
	var domains: Array = parsed.get("domains", []) if parsed.has("cards") else []
	var clean := {}
	for card_name in list:
		clean[str(card_name)] = int(list[card_name])
	if domains.is_empty():
		domains = domains_of_list(clean)
	var found := deck(domains, label, clean)
	var problems := FateDecks.problems(clean, domains)
	if not problems.is_empty():
		return {"error": "; ".join(problems)}
	return found


# The domains the cards of a list belong to, most common first
static func domains_of_list(list: Dictionary) -> Array:
	var counts := {}
	for card_name in list:
		for d in cfc.card_definitions.get(card_name, {}).get("_domains", []):
			counts[d] = counts.get(d, 0) + int(list[card_name])
	var found: Array = counts.keys()
	found.sort_custom(func(a, b): return counts[a] > counts[b])
	return found.slice(0, 1) if not found.is_empty() else ["Order"]


static func matchup(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"a": a, "b": b}


# Every pair of the given decks, each deck against each other deck once (and against itself when
# `with_mirrors`): the round robin that shows how the domains stand against each other
static func round_robin(decks: Array, with_mirrors := false) -> Array:
	var found: Array = []
	for i in decks.size():
		for j in range(i if with_mirrors else i + 1, decks.size()):
			found.append(matchup(decks[i], decks[j]))
	return found


static func new_config(matchups: Array, games := 20, workers := 0) -> Dictionary:
	if workers <= 0:
		workers = default_workers()
	return {
		"run_id": new_run_id(), "matchups": matchups, "games": games, "workers": workers,
		"levels": [1, 1], "seed": "fate sim", "swap_seats": true, "turn_cap": 60,
		"game_seconds": 120, "doctrines": true,
	}


# Leave a core for the program that watches the run
static func default_workers() -> int:
	return clampi(OS.get_processor_count() - 1, 1, 8)


static func new_run_id() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%04d" % [t.year, t.month, t.day, t.hour, t.minute, t.second, randi() % 10000]


static func total_games(config: Dictionary) -> int:
	return config.matchups.size() * int(config.games)


static func matchup_of_game(config: Dictionary, g: int) -> int:
	return g % config.matchups.size()


static func game_in_matchup(config: Dictionary, g: int) -> int:
	return g / config.matchups.size()


# The deck (0 = a, 1 = b) that sits in seat 1 in the game
static func deck_in_seat_1(config: Dictionary, g: int) -> int:
	if not config.get("swap_seats", true):
		return 0
	return game_in_matchup(config, g) % 2


static func game_seed(config: Dictionary, g: int) -> String:
	return "%s|%d|%d" % [config.seed, matchup_of_game(config, g), game_in_matchup(config, g)]


static func run_dir(config: Dictionary) -> String:
	return "%s/%s" % [ROOT_DIR, config.run_id]


# Problems with a config that would make the run useless, as text; empty when it can run
static func problems(config: Dictionary) -> Array:
	var found: Array = []
	if config.get("matchups", []).is_empty():
		found.append("no matchups")
	if int(config.get("games", 0)) < 1:
		found.append("games must be at least 1")
	for m in config.get("matchups", []):
		for side in ["a", "b"]:
			var d: Dictionary = m[side]
			if d.get("domains", []).is_empty():
				found.append("deck %s has no domains" % d.get("label", "?"))
			if not d.get("list", {}).is_empty():
				found.append_array(FateDecks.problems(d.list, d.domains).map(
						func(p): return "%s: %s" % [d.label, p]))
	return found


static func level_name(level: int) -> String:
	return LEVEL_NAMES[clampi(level, 0, LEVEL_NAMES.size() - 1)]
