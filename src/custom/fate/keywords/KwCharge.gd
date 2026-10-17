# Charge: may attack the turn it enters play (docs/FATE_RULES_SPEC.md, Section 4).
# Without Charge a creature cannot attack on the turn it entered. The rule applies to creatures
# that do NOT have the keyword, which get no hook calls of their own, so the keyword is
# universal and checks has() itself. Granted Charge (game.stats.grant_keyword) is seen by has()
# like an innate one, and its expiry is handled by the stats layer.
extends FateKeyword


func _init() -> void:
	keyword_name = "Charge"
	universal = true


func can_attack(card: Card) -> bool:
	return not is_summoning_sick(card) or has(card)


# Did this card enter play this turn? entered_turn is 0 for cards that were not played from the
# hand (tokens, test helpers), and turn numbers start at 1, so those are never restricted.
func is_summoning_sick(card: Card) -> bool:
	return card is FateCardTemplate and card.entered_turn > 0 \
			and card.entered_turn == game.turn_number
