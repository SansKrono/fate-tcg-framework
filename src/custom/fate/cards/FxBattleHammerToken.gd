# Battle Hammer token (relic token): "Attached creature gains +2 Strike."
extends "res://src/custom/fate/cards/FateCardEffect.gd"


func _init() -> void:
	card_name = "Battle Hammer Token"


func static_stat_bonus(host: Card, target: Card, stat: String) -> int:
	if stat != "Strike" or not host.has_meta("fate_equipped_to"):
		return 0
	return 2 if host.get_meta("fate_equipped_to") == target and host.current_host_card == target else 0
