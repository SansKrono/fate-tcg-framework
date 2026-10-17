extends "res://tests/UTcommon.gd"

class TestNestedTasks:
	extends "res://tests/ScEng_common.gd"

	func test_nested_tasks_are_executed():
		board.counters.mod_counter("credits", 10, true)
		card.scripts = {"manual": {"hand": [
				{"name": "nested_script",
				"nested_tasks": [
					{"name": "mod_counter",
					"is_cost": true,
					"modification": -2,
					"counter_name": "credits"},
					{"name": "mod_counter",
					"modification": 3,
					"counter_name": "research"}]}]}}
		await execute_with_yield(card)
		assert_eq(board.counters.get_counter("credits"), 8,
				"Nested cost task was paid")
		assert_eq(board.counters.get_counter("research"), 3,
				"Nested non-cost task was executed")

	func test_failing_nested_cost_aborts_parent_script():
		board.counters.mod_counter("credits", 1, true)
		card.scripts = {"manual": {"hand": [
				{"name": "nested_script",
				"is_cost": true,
				"nested_tasks": [
					{"name": "mod_counter",
					"is_cost": true,
					"modification": -2,
					"counter_name": "credits"},
					{"name": "mod_counter",
					"modification": 3,
					"counter_name": "research"}]},
				{"name": "mod_counter",
				"modification": 5,
				"counter_name": "research"}]}}
		await execute_with_yield(card)
		assert_eq(board.counters.get_counter("credits"), 1,
				"Nested cost could not be paid, so credits are unchanged")
		assert_eq(board.counters.get_counter("research"), 0,
				"Neither the nested task nor the parent script task were executed")
