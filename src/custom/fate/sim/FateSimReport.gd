# Turns the game records of a simulation run (FateSimRecorder) into the numbers that matter for balancing:
# win rates with their error bars, how long games last, how each deck wins and loses, and for every card
# how much it moves the result. Pure data in, pure data and text out: no scene needed, it can be fed
# while the run is going on (add_record) and asked for a report at any time.
#
# Win rates leave out games nobody won (turn cap, stall). Win rates are shown as "52.0% (+-9.8)": the
# half-width of the 95% Wilson interval, so a reader sees at once how much the number can be trusted.
#
# Card numbers (per deck label, over the games the deck played):
#   seen%       games where the card left the deck (drawn or searched)
#   wr seen     win rate of the deck in those games      wr unseen  in the games where it stayed in the deck
#   delta       wr seen - wr unseen. Only flagged when both samples are big enough and the gap is bigger than
#               noise (|z| >= Z_FLAG); the flag is a hint to look at the card, not a verdict
#   plays/seen  casts per game the card was seen in      energy%    copies seen that were played as energy
#   unused%     games it was seen but neither cast nor played as energy
#   turn        average turn it was cast on          dmg c/p   damage to creatures / players per game seen
#   kills, deaths   creatures destroyed with it as the source, times it was destroyed (per game seen)
#
# No class_name (see FateAIEval.gd).
extends RefCounted

# Fewer decided games than this on either side of a card comparison and the card is not flagged
const MIN_SAMPLE := 30
const Z_FLAG := 2.0
# A card mostly played as energy is probably "dead": its script does nothing yet, so the AI uses it as fodder
const ENERGY_FLAG := 0.5
const UNUSED_FLAG := 0.4
const TURN_BUCKETS := [[1, 8, "1-8"], [9, 12, "9-12"], [13, 16, "13-16"], [17, 20, "17-20"], [21, 999, "21+"]]
const LIFE_CURVE_TURNS := 12

var games := 0
var reasons := {}
var turns_list: Array = []
var wins_by_seat := {1: 0, 2: 0}
var decided := 0
var frames_total := 0
var ms_total := 0
var problems: Array = []
var turn_buckets := {}
# deck label -> aggregate (see _new_deck)
var decks := {}
# "A vs B" -> {"a", "b", "games", "a_wins", "b_wins", "draws", "turns"} in the order the matchup was configured
var matchups := {}
# "file.gd:12  text" -> {"count", "games"}: script errors printed while the games were played
var errors := {}
# workers that stopped before their share was played: [{"worker", "text"}]
var failures: Array = []


# --- feeding ---------------------------------------------------------------------------------------------

func add_record(record: Dictionary) -> void:
	if record.get("type", "") != "game":
		return
	games += 1
	var reason: String = record.get("reason", "")
	reasons[reason] = reasons.get(reason, 0) + 1
	var turns := int(record.get("turns", 0))
	turns_list.append(turns)
	frames_total += int(record.get("frames", 0))
	ms_total += int(record.get("ms", 0))
	for key in record.get("errors", {}):
		var e: Dictionary = errors.get(key, {"count": 0, "games": 0})
		e.count += int(record.errors[key])
		e.games += 1
		errors[key] = e
	for p in record.get("problems", []):
		if problems.size() < 20:
			problems.append(str(p))
	var winner := int(record.get("winner_seat", 0))
	var seats: Dictionary = record.seats
	if winner != 0:
		decided += 1
		wins_by_seat[winner] += 1
		for bucket in TURN_BUCKETS:
			if turns >= bucket[0] and turns <= bucket[1]:
				turn_buckets[bucket[2]] = turn_buckets.get(bucket[2], 0) + 1
	var label1: String = seats["1"].label
	var label2: String = seats["2"].label
	var mirror := label1 == label2
	for key in seats:
		_add_deck_game(seats[key], int(key), winner, mirror, turns)
	_add_matchup(record, seats, winner, turns)


func add_failure(worker: int, text: String) -> void:
	failures.append({"worker": worker, "text": text})


func _new_deck() -> Dictionary:
	return {
		"games": 0, "wins": 0, "losses": 0, "draws": 0, "wins_nm": 0, "losses_nm": 0,
		"play_wins": 0, "play_games": 0, "draw_wins": 0, "draw_games": 0,
		"life_end": 0, "creatures_lost": 0, "attacks": 0, "player_hits": 0, "blocked_attacks": 0,
		"mana_spent": 0, "mana_available": 0, "board_sum": 0, "board_turns": 0, "energy_plays": 0,
		"draw_choices": 0, "cards_played": 0, "turns": 0, "dmg_taken": {},
		"life_sum": [], "life_n": [], "cards": {},
	}


func _new_card() -> Dictionary:
	return {
		"copies": 0, "games": 0, "seen_games": 0, "seen_wins": 0, "unseen_games": 0, "unseen_wins": 0,
		"seen_copies": 0, "played": 0, "energy": 0, "unused": 0, "turn_sum": 0, "dmg_c": 0, "dmg_p": 0,
		"kills": 0, "deaths": 0, "attacks": 0, "hits": 0,
	}


func _add_deck_game(seat: Dictionary, seat_id: int, winner: int, mirror: bool, _turns: int) -> void:
	var label: String = seat.label
	if not decks.has(label):
		decks[label] = _new_deck()
	var d: Dictionary = decks[label]
	d.games += 1
	var won: bool = winner == seat_id
	var lost: bool = winner != 0 and not won
	if won:
		d.wins += 1
	elif lost:
		d.losses += 1
	else:
		d.draws += 1
	if not mirror:
		if won:
			d.wins_nm += 1
		elif lost:
			d.losses_nm += 1
	if winner != 0:
		if seat_id == 1:
			d.play_games += 1
			d.play_wins += 1 if won else 0
		else:
			d.draw_games += 1
			d.draw_wins += 1 if won else 0
	for key in ["life_end", "creatures_lost", "attacks", "player_hits", "blocked_attacks", "mana_spent",
			"mana_available", "board_sum", "board_turns", "energy_plays", "draw_choices", "cards_played", "turns"]:
		d[key] += int(seat.get(key, 0))
	for cause in seat.get("dmg_taken", {}):
		d.dmg_taken[cause] = d.dmg_taken.get(cause, 0) + int(seat.dmg_taken[cause])
	var curve: Array = seat.get("life_by_turn", [])
	for i in mini(curve.size(), LIFE_CURVE_TURNS):
		while d.life_sum.size() <= i:
			d.life_sum.append(0)
			d.life_n.append(0)
		d.life_sum[i] += int(curve[i])
		d.life_n[i] += 1
	for card_name in seat.get("cards", {}):
		var data: Dictionary = seat.cards[card_name]
		if int(data.copies) <= 0:
			continue
		if not d.cards.has(card_name):
			d.cards[card_name] = _new_card()
		var c: Dictionary = d.cards[card_name]
		c.copies = maxi(c.copies, int(data.copies))
		c.games += 1
		var seen := int(data.seen) > 0
		if winner != 0:
			if seen:
				c.seen_games += 1
				c.seen_wins += 1 if won else 0
			else:
				c.unseen_games += 1
				c.unseen_wins += 1 if won else 0
		c.seen_copies += int(data.seen)
		c.played += int(data.played)
		c.energy += int(data.energy)
		if seen and int(data.played) + int(data.energy) == 0:
			c.unused += 1
		for key in ["turn_sum", "dmg_c", "dmg_p", "kills", "deaths", "attacks", "hits"]:
			c[key] += int(data[key])


func _add_matchup(record: Dictionary, seats: Dictionary, winner: int, turns: int) -> void:
	# Keyed by the matchup number, so the same labels in two matchups (two custom decks) stay apart
	var key := str(int(record.get("matchup", 0)))
	var deck_a := ""
	var deck_b := ""
	for seat_key in seats:
		if int(seats[seat_key].deck) == 0:
			deck_a = seats[seat_key].label
		else:
			deck_b = seats[seat_key].label
	if not matchups.has(key):
		matchups[key] = {"a": deck_a, "b": deck_b, "games": 0, "a_wins": 0, "b_wins": 0, "draws": 0, "turns": 0}
	var m: Dictionary = matchups[key]
	m.games += 1
	m.turns += turns
	if winner == 0:
		m.draws += 1
	elif int(seats[str(winner)].deck) == 0:
		m.a_wins += 1
	else:
		m.b_wins += 1


# --- numbers -------------------------------------------------------------------------------------------

# Half-width of the 95% Wilson interval of `wins` out of `n`, as a share (0.05 = 5 points)
static func wilson_half_width(wins: int, n: int) -> float:
	if n <= 0:
		return 0.5
	var z := 1.96
	var p := float(wins) / n
	var denom := 1.0 + z * z / n
	return z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / denom


# z score of a share compared with a fixed expectation
static func z_vs(wins: int, n: int, expected := 0.5) -> float:
	if n <= 0:
		return 0.0
	var se := sqrt(expected * (1.0 - expected) / n)
	return (float(wins) / n - expected) / se


# z score of the difference of two shares
static func z_diff(w1: int, n1: int, w2: int, n2: int) -> float:
	if n1 <= 0 or n2 <= 0:
		return 0.0
	var p := float(w1 + w2) / (n1 + n2)
	if p <= 0.0 or p >= 1.0:
		return 0.0
	var se := sqrt(p * (1.0 - p) * (1.0 / n1 + 1.0 / n2))
	return (float(w1) / n1 - float(w2) / n2) / se


static func _share(a: int, b: int) -> float:
	return float(a) / b if b > 0 else 0.0


static func pct(x: float) -> String:
	return "%.1f%%" % (x * 100.0)


# "52.0% (+-9.8)"
static func rate_text(wins: int, n: int) -> String:
	if n <= 0:
		return "   n/a"
	return "%s (+-%.1f)" % [pct(float(wins) / n), wilson_half_width(wins, n) * 100.0]


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	return float(sorted[mid]) if sorted.size() % 2 == 1 else (sorted[mid - 1] + sorted[mid]) / 2.0


func average_turns() -> float:
	if turns_list.is_empty():
		return 0.0
	var total := 0
	for t in turns_list:
		total += t
	return float(total) / turns_list.size()


# --- derived tables ------------------------------------------------------------------------------------

# One row per deck label for the deck table, sorted by win rate. Mirror games are left out of the win
# rate (they are 50% by construction) unless the deck only played mirrors.
func deck_rows() -> Array:
	var rows: Array = []
	for label in decks:
		var d: Dictionary = decks[label]
		var wins: int = d.wins_nm
		var losses: int = d.losses_nm
		if wins + losses == 0:
			wins = d.wins
			losses = d.losses
		var n := wins + losses
		var own_turns: int = maxi(1, d.turns)
		var flag := ""
		var z := z_vs(wins, n)
		if n >= MIN_SAMPLE and absf(z) >= Z_FLAG:
			flag = "FAVOURED" if z > 0 else "DISFAVOURED"
		var total_taken := 0
		for cause in d.dmg_taken:
			total_taken += d.dmg_taken[cause]
		rows.append({
			"label": label, "games": d.games, "wins": wins, "losses": losses, "draws": d.draws, "n": n,
			"wr": _share(wins, n), "wr_ci": wilson_half_width(wins, n), "flag": flag,
			"wr_on_play": _share(d.play_wins, d.play_games), "wr_on_draw": _share(d.draw_wins, d.draw_games),
			"life_end": _share(d.life_end, d.games), "creatures_lost": _share(d.creatures_lost, d.games),
			"attacks_per_turn": _share(d.attacks, own_turns), "unblocked": _share(d.player_hits, d.attacks),
			"mana_eff": _share(d.mana_spent, d.mana_available), "board": _share(d.board_sum, d.board_turns),
			"energy_rate": _share(d.energy_plays, own_turns), "draw_rate": _share(d.draw_choices, own_turns),
			"casts_per_turn": _share(d.cards_played, own_turns), "dmg_taken": d.dmg_taken.duplicate(),
			"dmg_taken_per_game": _share(total_taken, d.games),
		})
	rows.sort_custom(func(a, b): return a.wr > b.wr)
	return rows


# One row per card of every deck, for the cards table (unsorted)
func card_rows() -> Array:
	var rows: Array = []
	for label in decks:
		var cards: Dictionary = decks[label].cards
		for card_name in cards:
			var c: Dictionary = cards[card_name]
			var seen_games: int = c.seen_games
			var wr_seen := _share(c.seen_wins, seen_games)
			var wr_unseen := _share(c.unseen_wins, c.unseen_games)
			var z := z_diff(c.seen_wins, seen_games, c.unseen_wins, c.unseen_games)
			var flags: Array = []
			if seen_games >= MIN_SAMPLE and c.unseen_games >= MIN_SAMPLE and absf(z) >= Z_FLAG:
				flags.append("STRONG" if z > 0 else "WEAK")
			var seen_all: int = maxi(1, c.seen_copies)
			var energy_rate := _share(c.energy, seen_all)
			var unused_rate := _share(c.unused, seen_games)
			if c.seen_copies >= MIN_SAMPLE and energy_rate >= ENERGY_FLAG:
				flags.append("MOSTLY-ENERGY")
			if seen_games >= MIN_SAMPLE and unused_rate >= UNUSED_FLAG and energy_rate < ENERGY_FLAG:
				flags.append("RARELY-PLAYED")
			var info := _card_info(card_name)
			rows.append({
				"label": label, "card": card_name, "type": info.type, "mv": info.mv, "copies": c.copies,
				"games": c.games, "seen_games": seen_games, "seen_pct": _share(seen_games, c.games),
				"wr_seen": wr_seen, "wr_unseen": wr_unseen, "delta": wr_seen - wr_unseen, "z": z,
				"plays_per_seen": _share(c.played, maxi(1, seen_games)), "energy_pct": energy_rate,
				"unused_pct": unused_rate, "avg_turn": _share(c.turn_sum, c.played),
				"dmg_c": _share(c.dmg_c, maxi(1, seen_games)), "dmg_p": _share(c.dmg_p, maxi(1, seen_games)),
				"kills": _share(c.kills, maxi(1, seen_games)), "deaths": _share(c.deaths, maxi(1, seen_games)),
				"flags": ",".join(flags),
			})
	return rows


func _card_info(card_name: String) -> Dictionary:
	var props: Dictionary = cfc.card_definitions.get(card_name, {})
	var mv := 0
	if not props.is_empty():
		mv = int(props.get("Cost", 0)) + str(props.get("Pips", "")).length()
	return {"type": str(props.get("Type", "?")), "mv": mv}


# Matchup rows in the order they were configured
func matchup_rows() -> Array:
	var rows: Array = []
	var keys := matchups.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var m: Dictionary = matchups[key]
		var n: int = m.a_wins + m.b_wins
		rows.append({
			"a": m.a, "b": m.b, "games": m.games, "a_wins": m.a_wins, "b_wins": m.b_wins, "draws": m.draws,
			"wr_a": _share(m.a_wins, n), "wr_ci": wilson_half_width(m.a_wins, n),
			"avg_turns": _share(m.turns, m.games),
		})
	return rows


# Everything the report says as data (for the JSON file)
func to_dict() -> Dictionary:
	return {
		"games": games, "decided": decided, "reasons": reasons, "avg_turns": average_turns(),
		"median_turns": median(turns_list), "wins_by_seat": wins_by_seat, "turn_buckets": turn_buckets,
		"decks": deck_rows(), "cards": card_rows(), "matchups": matchup_rows(), "problems": problems,
		"failures": failures, "errors": errors,
	}


# --- text ------------------------------------------------------------------------------------------------

# The report as monospaced text. `top_cards` limits how many cards are listed per deck (the strongest and
# weakest by delta); 0 lists them all.
func format_text(top_cards := 8) -> String:
	var out: Array = []
	out.append("GAMES  %d played, %d decided   avg %.1f turns (median %.0f)" % [
			games, decided, average_turns(), median(turns_list)])
	var ends: Array = []
	for r in reasons:
		ends.append("%s %d" % [r if r != "" else "life", reasons[r]])
	if not ends.is_empty():
		out.append("ENDED  " + ", ".join(ends))
	var seat_z := z_vs(wins_by_seat[1], decided)
	out.append("SEATS  first player wins %s%s" % [rate_text(wins_by_seat[1], decided),
			"   <-- first-player advantage" if decided >= MIN_SAMPLE and seat_z >= Z_FLAG else
			("   <-- second-player advantage" if decided >= MIN_SAMPLE and seat_z <= -Z_FLAG else "")])
	var buckets: Array = []
	for bucket in TURN_BUCKETS:
		buckets.append("%s: %d" % [bucket[2], turn_buckets.get(bucket[2], 0)])
	out.append("WON ON TURN  " + "   ".join(buckets))
	if not failures.is_empty():
		for f in failures:
			out.append("!! worker %d: %s" % [f.worker, f.text])
	if not problems.is_empty():
		out.append("!! the AI asked for illegal moves (%d shown):" % problems.size())
		for p in problems.slice(0, 5):
			out.append("     " + p)
	if not errors.is_empty():
		var keys := errors.keys()
		keys.sort_custom(func(a, b): return errors[a].count > errors[b].count)
		out.append("!! script errors in %d kinds (most frequent first; a card script that fails is a card that does nothing):" % keys.size())
		for key in keys.slice(0, 8):
			out.append("     %5dx in %3d games  %s" % [errors[key].count, errors[key].games, key])
	out.append("")
	out.append("DECKS")
	out.append("  %-12s %5s %-16s %6s %6s %5s %5s %5s %5s %5s  %s" % [
			"deck", "games", "win rate", "onplay", "ondraw", "life", "lost", "mana", "board", "cast", "flag"])
	for r in deck_rows():
		out.append("  %-12s %5d %-16s %6s %6s %5.1f %5.1f %5s %5.1f %5.2f  %s" % [
				r.label, r.games, rate_text(r.wins, r.n), pct(r.wr_on_play), pct(r.wr_on_draw), r.life_end,
				r.creatures_lost, pct(r.mana_eff), r.board, r.casts_per_turn, r.flag])
	out.append("  (life = life at the end, lost = creatures lost per game, mana = share of energy spent, board = creatures")
	out.append("   in play at the start of own turns, cast = cards cast per own turn)")
	var m_rows := matchup_rows()
	if m_rows.size() > 1:
		out.append("")
		out.append("MATCHUPS  (win rate of the first deck)")
		for r in m_rows:
			out.append("  %-12s vs %-12s %4d games   %s   draws %d   %.1f turns" % [
					r.a, r.b, r.games, rate_text(r.a_wins, r.a_wins + r.b_wins), r.draws, r.avg_turns])
	elif m_rows.size() == 1:
		var r: Dictionary = m_rows[0]
		out.append("")
		out.append("MATCHUP  %s vs %s: %d - %d, %d draws" % [r.a, r.b, r.a_wins, r.b_wins, r.draws])
	var all_cards := card_rows()
	for label in decks:
		out.append("")
		out.append("CARDS  %s" % label)
		var rows: Array = all_cards.filter(func(r): return r.label == label)
		rows.sort_custom(func(a, b): return a.delta > b.delta)
		var shown: Array = rows
		if top_cards > 0 and rows.size() > top_cards * 2:
			shown = rows.slice(0, top_cards) + rows.slice(rows.size() - top_cards)
		out.append("  %-26s %2s %3s %5s %6s %6s %7s %6s %6s %6s %5s  %s" % [
				"card", "mv", "x", "seen", "wrSeen", "wrUnsn", "delta", "plays", "energy", "unused", "turn", "flags"])
		for r in shown:
			out.append("  %-26s %2d %3d %5s %6s %6s %+6.1f%% %6.2f %6s %6s %5.1f  %s" % [
					r.card.left(26), r.mv, r.copies, pct(r.seen_pct), pct(r.wr_seen), pct(r.wr_unseen),
					r.delta * 100.0, r.plays_per_seen, pct(r.energy_pct), pct(r.unused_pct), r.avg_turn, r.flags])
		if shown.size() < rows.size():
			out.append("  (%d cards in the middle left out; the CSV has all of them)" % (rows.size() - shown.size()))
	return "\n".join(out)


func cards_csv() -> String:
	var lines: Array = ["deck,card,type,mana_value,copies,games,seen_games,seen_pct,wr_seen,wr_unseen,delta,z,"
			+ "plays_per_seen,energy_pct,unused_pct,avg_turn,dmg_creatures,dmg_players,kills,deaths,flags"]
	for r in card_rows():
		lines.append("%s,\"%s\",%s,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.2f,%.3f,%.4f,%.4f,%.2f,%.3f,%.3f,%.3f,%.3f,%s" % [
				r.label, r.card, r.type, r.mv, r.copies, r.games, r.seen_games, r.seen_pct, r.wr_seen, r.wr_unseen,
				r.delta, r.z, r.plays_per_seen, r.energy_pct, r.unused_pct, r.avg_turn, r.dmg_c, r.dmg_p, r.kills,
				r.deaths, r.flags])
	return "\n".join(lines) + "\n"
