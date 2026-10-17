extends FateKeyword
# A configurable keyword for tests (NOT in src/custom/fate/keywords/, so the registry never finds it
# and it does not ship). Register it per test: `game.keywords.register(kw)`.
# Every hook call is recorded in `calls` as [hook_name, args...], and each hook's answer can be
# set through the variables below.

var calls := []
var allow_attack := true
var allow_occupy := true
var allow_block := true
var allow_blocked_by := true
var allow_attacked := true
var allow_destroy := true
var destination := ""
# damage_taken = max(0, amount * damage_factor - damage_reduction), or capped at damage_cap if >= 0
var damage_reduction := 0
var damage_cap := -1
var bonus := {}
var action_list := []
# Holds the used stat at 1 instead of letting combat damage reduce it to 0 (Indomitable)
var hold_at_one := false
# Called by on_blocked(card, attack, blockers), for keywords that do something when blocked
var on_blocked_cb := Callable()
# When set, every hook call also appends "<keyword_name>:<hook>" here, to check the order
var shared_log: Array = []
var use_shared_log := false


static func make(kw_name: String, kw_priority := 0, is_universal := false) -> FateKeyword:
	var kw = load("res://tests/FateTestKeyword.gd").new()
	kw.keyword_name = kw_name
	kw.priority = kw_priority
	kw.universal = is_universal
	return kw


func _rec(entry: Array) -> void:
	calls.append(entry)
	if use_shared_log:
		shared_log.append("%s:%s" % [keyword_name, entry[0]])


func hooks_called(hook_name: String) -> Array:
	return calls.filter(func(c): return c[0] == hook_name)


func can_attack(card: Card) -> bool:
	_rec(["can_attack", card])
	return allow_attack


func can_occupy(card: Card) -> bool:
	_rec(["can_occupy", card])
	return allow_occupy


func can_block(blocker: Card, attack: FateAttack) -> bool:
	_rec(["can_block", blocker, attack])
	return allow_block


func can_be_blocked_by(attacker: Card, blocker: Card, attack: FateAttack) -> bool:
	_rec(["can_be_blocked_by", attacker, blocker, attack])
	return allow_blocked_by


func can_be_attacked(target: Card, attacker: Card) -> bool:
	_rec(["can_be_attacked", target, attacker])
	return allow_attacked


func on_attack_declared(card: Card, attack: FateAttack) -> void:
	_rec(["on_attack_declared", card, attack])


func on_blocked(card: Card, attack: FateAttack, blockers: Array) -> void:
	_rec(["on_blocked", card, attack, blockers])
	if on_blocked_cb.is_valid():
		on_blocked_cb.call(card, attack, blockers)


func on_blocking(card: Card, attack: FateAttack) -> void:
	_rec(["on_blocking", card, attack])


func before_combat_damage(card: Card, attack: FateAttack) -> void:
	_rec(["before_combat_damage", card, attack])


func on_damage_dealt(card: Card, target, amount: int, cause: String) -> void:
	_rec(["on_damage_dealt", card, target, amount, cause])


func modify_damage_taken(card: Card, stat: String, amount: int, cause: String, source) -> int:
	_rec(["modify_damage_taken", card, stat, amount, cause, source])
	var result := maxi(0, amount - damage_reduction)
	if damage_cap >= 0:
		result = mini(result, damage_cap)
	if hold_at_one and cause == "combat":
		result = mini(result, maxi(0, game.stats.current(card, stat) - 1))
	return result


func would_be_destroyed(card: Card, cause: String, source) -> bool:
	_rec(["would_be_destroyed", card, cause, source])
	return allow_destroy


func death_destination(card: Card, cause: String) -> String:
	_rec(["death_destination", card, cause])
	return destination


func on_destroyed(card: Card, cause: String, source) -> void:
	_rec(["on_destroyed", card, cause, source])


func stat_bonus(_card: Card, stat: String) -> int:
	return int(bonus.get(stat, 0))


func on_turn_end(card: Card) -> void:
	_rec(["on_turn_end", card])


func on_maintenance(card: Card) -> void:
	_rec(["on_maintenance", card])


func actions(card: Card) -> Array:
	return action_list
