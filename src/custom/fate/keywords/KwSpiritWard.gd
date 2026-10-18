# Spirit Ward: given by the doctrine Channel the Spirit's Will (cards/FxChanneltheSpiritsWill.gd) to its owner's
# creatures. A creature that would be destroyed by combat damage stays, and its controller takes 3 damage instead.
extends FateKeyword

const DAMAGE := 3
const DOCTRINE := "Channel the Spirit's Will"


func _init() -> void:
	keyword_name = "Spirit Ward"


func would_be_destroyed(card: Card, cause: String, _source) -> bool:
	if cause != FateEffects.CAUSE_COMBAT or game.doctrines == null:
		return true
	var doctrine = game.doctrines.active_card(DOCTRINE, card.controller_id)
	if doctrine == null:
		return true
	game.effects.deal_damage(game.player(card.controller_id), DAMAGE, doctrine, FateEffects.CAUSE_EFFECT)
	return false
