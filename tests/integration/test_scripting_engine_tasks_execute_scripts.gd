extends "res://tests/UTcommon.gd"

class TestExecuteScripts:
	extends "res://tests/ScEng_common.gd"

	func test_execute_scripts():
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",
				"require_exec_state": "hand"}]}}
		target.scripts = {"manual": {"hand": [
				{"name": "move_card_to_board",
				"subject": "self",
				"board_position":  Vector2(100,100)}]}}
		card.execute_scripts()
		await target_card(card,target)
		await wait_for_signal(card._tween.tween_all_completed, 1)
		assert_eq(target.get_parent(),cfc.NMAP.board,
				"Card should have moved to board")
		target.scripts = {"manual": {"board": [
				{"name": "mod_tokens",
				"subject": "self",
				"modification": 1,
				"token_name":  "industry"}]}}
		card.execute_scripts()
		await target_card(card,target)
		var industry_token: Token = target.tokens.get_token("industry")
		assert_null(industry_token,
				"scripts not executed because exec state does not match")
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",}]}}
		card.execute_scripts()
		await target_card(card,target)
		await wait_seconds(0.1)
		industry_token = target.tokens.get_token("industry")
		assert_not_null(industry_token,
				"scripts executed because exec state not defined")
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "false",}]}}
		card.execute_scripts()
		await target_card(card,target)
		await wait_seconds(0.1)
		industry_token = target.tokens.get_token("industry")
		assert_not_null(industry_token)
		if industry_token:
			assert_eq(industry_token.count, 1,
					"scripts not executed because exec_trigger does not match")

class TestExecuteScriptsWithTempModProp:
	extends "res://tests/ScEng_common.gd"

	func test_execute_scripts_with_temp_mod_property():
		# warning-ignore:return_value_discarded
		target.modify_property("Cost", 1)
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",
				"temp_mod_properties": {"Cost": 1},
				"require_exec_state": "hand"}]}}
		target.scripts = {"manual": {
			"hand": [
				{"name": "move_card_to_container",
				"subject": "index",
				"subject_count": "per_property",
				"src_container": "deck",
				"dest_container": "hand",
				"subject_index": "top",
				"per_property": {
					"subject": "self",
					"property_name": "Cost"}
				},
			]}
		}
		card.execute_scripts()
		await target_card(card,target, "slow")
		await wait_seconds(0.5)
		assert_eq(hand.get_card_count(), 7,
			"Draw the temp modified amount of cards")
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",
				"temp_mod_properties": {"Cost": -5},
				"require_exec_state": "hand"}]}}
		card.execute_scripts()
		await target_card(card,target, "slow")
		await wait_seconds(0.5)
		assert_eq(hand.get_card_count(), 7,
			"Ensure the property does not go negative")
		target.execute_scripts()
		await wait_seconds(0.1)
		assert_eq(hand.get_card_count(), 8,
			"Ensure temp property modifiers don't remain")

class TestExecuteScriptsWithTempModCounter:
	extends "res://tests/ScEng_common.gd"

	func test_execute_scripts_with_temp_mod_counter():
		cfc.NMAP.board.counters.mod_counter("research", 1)
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",
				"temp_mod_counters": {"research": 1},
				"require_exec_state": "hand"}]}}
		target.scripts = {"manual": {
			"hand": [
				{"name": "move_card_to_container",
				"subject": "index",
				"subject_count": "per_counter",
				"src_container": "deck",
				"dest_container": "hand",
				"subject_index": "top",
				"per_counter": {
					"counter_name": "research"}
				},
			]}
		}
		card.execute_scripts()
		await target_card(card,target, "slow")
		await wait_seconds(0.5)
		assert_eq(hand.get_card_count(), 7,
			"Draw the temp modified amount of cards")
		card.scripts = {"manual": {"hand": [
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger":  "manual",
				"temp_mod_counters": {"research": -5},
				"require_exec_state": "hand"}]}}
		card.execute_scripts()
		await target_card(card,target, "slow")
		await wait_seconds(0.5)
		assert_eq(hand.get_card_count(), 7,
			"Ensure the counter does not go negative")
		target.execute_scripts()
		await wait_seconds(0.1)
		assert_eq(hand.get_card_count(), 8,
			"Ensure temp property modifiers don't remain")

	func _setup_unpayable_target_costs() -> void:
		board.counters.mod_counter("credits", 10, true)
		board.counters.mod_counter("research", 0, true)
		# The target has a cost which cannot be paid, as there's no research
		target.scripts = {"manual": {
			"hand": [
				{"name": "mod_counter",
				"is_cost": true,
				"modification": -5,
				"counter_name": "research"},
				{"name": "mod_counter",
				"modification": 3,
				"counter_name": "credits"}],
			"board": [
				{"name": "mod_counter",
				"is_cost": true,
				"modification": -5,
				"counter_name": "research"},
				{"name": "mod_counter",
				"modification": 3,
				"counter_name": "credits"}]}}

	func test_no_costs_are_paid_when_target_costs_cannot_be_paid():
		_setup_unpayable_target_costs()
		card.scripts = {"manual": {"hand": [
				{"name": "mod_counter",
				"is_cost": true,
				"modification": -2,
				"counter_name": "credits"},
				{"name": "execute_scripts",
				"is_cost": true,
				"subject": "target",
				"exec_trigger": "manual"}]}}
		await execute_with_target(card, target)
		assert_eq(board.counters.get_counter("credits"), 10,
				"No costs were paid because the target card could not pay its costs")
		assert_eq(board.counters.get_counter("research"), 0,
				"Target's task was not executed")

	func test_costs_are_paid_when_execute_scripts_is_not_a_cost():
		_setup_unpayable_target_costs()
		card.scripts = {"manual": {"hand": [
				{"name": "mod_counter",
				"is_cost": true,
				"modification": -2,
				"counter_name": "credits"},
				{"name": "execute_scripts",
				"subject": "target",
				"exec_trigger": "manual"}]}}
		await execute_with_target(card, target)
		assert_eq(board.counters.get_counter("credits"), 8,
				"Costs were paid because executing the target's scripts is not a cost")
		assert_eq(board.counters.get_counter("research"), 0,
				"Target's task was not executed as it could not pay its costs")

	func test_costs_are_paid_when_target_costs_cannot_be_paid_with_boardseek():
		_setup_unpayable_target_costs()
		await table_move(target, Vector2(500,200))
		card.scripts = {"manual": {"hand": [
				{"name": "mod_counter",
				"is_cost": true,
				"modification": -2,
				"counter_name": "credits"},
				{"name": "execute_scripts",
				"is_cost": true,
				"subject": "boardseek",
				"subject_count": "all",
				"exec_trigger": "manual"}]}}
		await execute_with_yield(card)
		assert_eq(board.counters.get_counter("credits"), 8,
				"Costs were paid because a boardseek subject can't fail the cost check")
		assert_eq(board.counters.get_counter("research"), 0,
				"Target's task was not executed as it could not pay its costs")
