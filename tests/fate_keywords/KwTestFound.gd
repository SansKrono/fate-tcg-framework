extends FateKeyword
# A keyword script for the discovery test (tests/integration/test_fate_keyword_registry.gd). It
# lives under tests/ so that it does not ship with the game.


func _init() -> void:
	keyword_name = "Test found"
	priority = 7


func can_attack(card: Card) -> bool:
	# Cannot attack with a creature that has Strike 0
	return game.stats.current(card, "Strike") > 0
