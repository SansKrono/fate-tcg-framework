# Productive: may occupy the turn it enters play (docs/FATE_RULES_SPEC.md, Section 4).
# Without Productive a creature cannot occupy the turn it entered. Same shape as Charge: the rule
# is for creatures that lack the keyword, so it is universal and checks has() itself.
extends FateKeyword


func _init() -> void:
	keyword_name = "Productive"
	universal = true


func can_occupy(card: Card) -> bool:
	return not entered_this_turn(card) or has(card)


# entered_turn is 0 for cards not played from the hand (tokens, test helpers), and turn numbers
# start at 1, so those are never restricted.
func entered_this_turn(card: Card) -> bool:
	return card is FateCardTemplate and card.entered_turn > 0 \
			and card.entered_turn == game.turn_number
