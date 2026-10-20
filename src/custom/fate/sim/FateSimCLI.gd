# Runs a simulation from the command line, without a window, and prints the report:
#
#   godot --headless --path . res://src/custom/fate/sim/FateSimCLI.tscn -- --decks=Order,Primal --games=40
#
# Arguments (after `--`):
#   --decks=A,B            two decks: a domain, a deck of the catalogue (order_optimised, primal_starter ...) or the
#                          path of a deck file (see FateSimConfig.deck_from_file)
#   --decks=A,B,C,..       three or more decks: every deck against every other (round robin)
#   --decks=all            the four domains' default decks, round robin
#   --decks=optimised      the four optimised decks of the catalogue, round robin (also: starters)
#   --against=X,Y,..       a gauntlet: every deck of --decks plays every deck of this list (and no other pairs)
#   --games=<n>            games per matchup (default 20)
#   --workers=<n>          processes playing at the same time (default: cores - 1)
#   --levels=normal,hard   AI profile of the first and the second deck: a grade (novice, easy, normal, hard, expert),
#                          a skill 0..1, a style ("hard+aggro") and parameters ("hard;aggression=1.4;caution=0.3"),
#                          or a profile file (res://ai_profiles/<name>.json). --list-params prints every parameter
#   --seed=<text>          same seed, same games (default "fate sim")
#   --turn-cap=<n>         a game still going on this turn is a draw (default 60)
#   --no-swap              the first deck always goes first (default: the seats alternate)
#   --no-doctrines         start without the doctrine cards
#   --discover=<domain>    deck discovery: every matchup is a new random legal deck of this domain against
#                          the next of --versus (see README); --games is then the games per random deck
#   --versus=A,B,..        the decks to play against in a discovery run (default: all four domains)
#   --samples=<n>          random decks in a discovery run (default 100)
#   --quiet                print the final report only, not the progress
#
# Exits with 0 when all games were played, 1 otherwise (a worker died, bad arguments).
#
# No class_name (see FateAIEval.gd).
extends Node

const Config := preload("res://src/custom/fate/sim/FateSimConfig.gd")
const Coordinator := preload("res://src/custom/fate/sim/FateSimCoordinator.gd")

var _run
var _quiet := false
var _last_printed := -1


func _ready() -> void:
	FateGame.register_cards()
	var args := _args()
	if args.has("list-params"):
		print(load("res://src/custom/fate/ai/FateAIProfile.gd").describe())
		get_tree().quit(0)
		return
	var config := _config(args)
	if config.has("error"):
		printerr("fate sim: %s" % config.error)
		get_tree().quit(1)
		return
	_quiet = args.has("quiet")
	_run = Coordinator.new()
	add_child(_run)
	_run.progress.connect(_on_progress)
	_run.finished.connect(_on_finished)
	var problem: String = _run.start(config)
	if problem != "":
		printerr("fate sim: %s" % problem)
		get_tree().quit(1)
		return
	print("fate sim: %d games (%d matchups x %d), %d processes, results in %s" % [
			Config.total_games(config), config.matchups.size(), config.games, _run.config.workers,
			_run.global_run_dir()])


func _on_progress(done: int, total: int) -> void:
	if _quiet:
		return
	var step := maxi(1, total / 20)
	if done / step != _last_printed:
		_last_printed = done / step
		print("fate sim: %d / %d games (%.0f s)" % [done, total, _run.elapsed()])


func _on_finished(report) -> void:
	print("")
	print(report.format_text(8))
	print("")
	print("fate sim: %d games in %.0f s, files in %s" % [report.games, _run.elapsed(), _run.global_run_dir()])
	var complete: bool = report.games == _run.games_total() and report.failures.is_empty()
	get_tree().quit(0 if complete else 1)


# `--name=value` / `--flag` user arguments as {name: value or ""}
func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if not text.begins_with("--"):
			continue
		var at := text.find("=")
		if at < 0:
			found[text.substr(2)] = ""
		else:
			found[text.substr(2, at - 2)] = text.substr(at + 1)
	return found


func _config(args: Dictionary) -> Dictionary:
	var decks_text: String = args.get("decks", "Order,Primal")
	var matchups: Array = []
	if args.has("against"):
		var challengers: Array = _decks_of(decks_text)
		var field: Array = _decks_of(str(args.against))
		if challengers.is_empty() or field.is_empty():
			return {"error": "--decks and --against need decks (a domain, a catalogue id or a .json file)"}
		for challenger in challengers:
			for opponent in field:
				matchups.append(Config.matchup(challenger, opponent))
	elif args.has("discover"):
		var opponents: Array = []
		for part in str(args.get("versus", ",".join(Config.DOMAINS))).split(","):
			var found := _deck(part.strip_edges())
			if found.has("error"):
				return found
			opponents.append(found)
		var domain := ""
		for d in Config.DOMAINS:
			if d.to_lower() == str(args.discover).to_lower():
				domain = d
		if domain == "":
			return {"error": "--discover wants a domain: %s" % ", ".join(Config.DOMAINS)}
		matchups = Config.discovery_matchups(domain, opponents, int(args.get("samples", "100")),
				str(args.get("seed", "fate sim")))
	elif decks_text == "all":
		matchups = Config.round_robin(Config.DOMAINS.map(func(d): return Config.domain_deck(d)))
	elif decks_text == "optimised":
		matchups = Config.round_robin(Config.tier_decks(FateDecks.TIER_OPTIMISED))
	elif decks_text == "starters":
		matchups = Config.round_robin(Config.tier_decks(FateDecks.TIER_STARTER))
	else:
		var parts := decks_text.split(",")
		if parts.size() < 2:
			return {"error": "--decks wants two or more decks (A,B) or all / optimised / starters"}
		var decks: Array = []
		for part in parts:
			var found := _deck(part.strip_edges())
			if found.has("error"):
				return found
			decks.append(found)
		matchups = [Config.matchup(decks[0], decks[1])] if decks.size() == 2 else Config.round_robin(decks)
	var default_games := "2" if args.has("discover") else "20"
	var config := Config.new_config(matchups, int(args.get("games", default_games)), int(args.get("workers", "0")))
	config.seed = args.get("seed", config.seed)
	config.turn_cap = int(args.get("turn-cap", "60"))
	config.swap_seats = not args.has("no-swap")
	config.doctrines = not args.has("no-doctrines")
	var levels: PackedStringArray = str(args.get("levels", "normal,normal")).split(",")
	config.levels = [_level(levels[0]), _level(levels[levels.size() - 1])]
	return config


# The decks of a comma separated list; [] if one of them cannot be used (the error is printed)
func _decks_of(text: String) -> Array:
	var found: Array = []
	for part in text.split(","):
		var one := _deck(part.strip_edges())
		if one.has("error"):
			printerr("fate sim: %s" % one.error)
			return []
		found.append(one)
	return found


func _deck(text: String) -> Dictionary:
	if not FateDecks.preset(text.to_lower()).is_empty():
		return Config.preset_deck(text.to_lower())
	if text.ends_with(".json"):
		return Config.deck_from_file(text)
	for domain in Config.DOMAINS:
		if domain.to_lower() == text.to_lower():
			return Config.domain_deck(domain)
	return {"error": "unknown deck '%s' (a domain: %s, or a .json deck file)" % [text, ", ".join(Config.DOMAINS)]}


# A grade name becomes its Level number; anything else (a style, parameters, a profile file) stays text for
# FateAIProfile.resolve
func _level(text: String):
	var at: int = Config.LEVEL_NAMES.find(text.strip_edges().to_lower())
	return at if at >= 0 else text.strip_edges()
