extends "res://tests/UTcommon.gd"

class TestManipulationButtons:
	extends "res://tests/Basic_common.gd"


	func test_manipulation_buttons_not_messing_hand_focus():
		var card = cards[0]
		await move_mouse(card.global_position)
		await move_mouse(card.global_position - Vector2(0,100))
		await wait_seconds(0.2)
		await move_mouse(card.global_position)
		await move_mouse(card.global_position - Vector2(0,100))
		await wait_seconds(0.2)
		await move_mouse(card.global_position)
		await wait_for_signal(cards[0].get_node('Tween').tween_all_completed, 1)
		assert_almost_eq(Vector2(103, -240.5),cards[0].position,Vector2(2,2),
				"Card focused and in correct global position")
		assert_almost_eq(Vector2(1.5, 1.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
