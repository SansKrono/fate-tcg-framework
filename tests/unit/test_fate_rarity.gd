extends GutTest
# FateRarity (derived from the card definitions) and the geometry of FateCardFx. Data only: no table.


func test_rarity_follows_mana_value():
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 0, "Pips": "I"}), FateRarity.COMMON)
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 1, "Pips": "I"}), FateRarity.COMMON)
	assert_eq(FateRarity.of("A", {"Type": "Spell", "Cost": 1, "Pips": "II"}), FateRarity.UNCOMMON)
	assert_eq(FateRarity.of("A", {"Type": "Relic", "Cost": 2, "Pips": "II"}), FateRarity.RARE)
	assert_eq(FateRarity.of("A", {"Type": "Spell", "Cost": 4, "Pips": "II"}), FateRarity.EPIC)


func test_unique_cards_are_legendary():
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 1, "Pips": "I", "_unique": true}),
			FateRarity.LEGENDARY)


func test_tokens_are_common():
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 5, "Pips": "", "_token": true}),
			FateRarity.COMMON)
	assert_eq(FateRarity.of("A", {"Type": "Relic", "Tags": ["Token"], "Cost": 4}), FateRarity.COMMON)


func test_doctrines_follow_their_tier():
	for tier in [1, 2, 3]:
		var props := {"Type": "Doctrine", "Cost": tier, "_unique": true}
		assert_eq(FateRarity.of("A", props), FateRarity.RARE + tier - 1)


func test_rarity_property_overrides_the_derived_one():
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 0, "_rarity": "epic"}), FateRarity.EPIC)
	assert_eq(FateRarity.of("A", {"Type": "Creature", "Cost": 0, "_rarity": "nonsense"}),
			FateRarity.COMMON)


func test_every_fate_card_has_a_rarity_with_effects():
	for table in [FateData.CARDS, FateData.TOKENS, FateData.DOCTRINES]:
		for card_name in table:
			var rarity := FateRarity.of(card_name, table[card_name])
			assert_between(rarity, FateRarity.COMMON, FateRarity.LEGENDARY, card_name)
			assert_true(FateRarity.fx_of(rarity).has("holo_amount"), card_name)


func test_a_flat_card_needs_no_fit():
	assert_eq(FateCardFx.fit_scale(Vector2.ZERO, CFConst.CARD_SIZE, 500.0), 1.0)


func test_a_tilted_card_grows_just_enough_to_cover_the_flat_card():
	var size := CFConst.CARD_SIZE
	var max_tilt := FateCardFx.MAX_TILT
	for tilt in [Vector2(max_tilt, 0), Vector2(0, -max_tilt), Vector2(max_tilt, max_tilt).limit_length(max_tilt)]:
		var fit := FateCardFx.fit_scale(tilt, size, size.y * FateCardFx.CAM_DIST)
		assert_gt(fit, 1.0, str(tilt))
		assert_lt(fit, 1.15, str(tilt))
