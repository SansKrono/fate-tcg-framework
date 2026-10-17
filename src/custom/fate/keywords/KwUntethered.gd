# Untethered (spec Section 4): when the creature dies it is removed from the game, into its
# OWNER's removed pile, instead of the discard pile.
#
# Everything else about a death (freeing the slot, clearing damage/modifiers/grants, firing
# on_destroyed and creature_destroyed once) is done by FateEffects.destroy for every card, so this
# keyword only answers where the card goes. "Dies" is any destruction from the table, whatever
# the cause, so the hook ignores `cause`.
#
# Priority: -100, so Untethered is asked before any other keyword and wins the "first non-empty
# answer" rule of death_destination. Reason: it is a replacement of the discard pile that the card
# text promises unconditionally ("removed from the game"), and leaving the game is the most final
# destination: a keyword that wants the card back ("deck", "hand") must not undo it. A rule that
# should override Untethered has to use a lower priority than -100 on purpose.
extends FateKeyword


func _init() -> void:
	keyword_name = "Untethered"
	priority = -100


func death_destination(_card: Card, _cause: String) -> String:
	return "removed"
