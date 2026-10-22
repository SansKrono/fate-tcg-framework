# The mana curve of a deck as a small ink bar chart on the parchment: one column per mana value
# (0 to 6, then 7 and more), the bar's height relative to the tallest one, the count above it.
class_name FateManaCurve
extends VBoxContainer

const COLUMNS := 8
const MIN_BAR := 2.0

var _counts: Array[int] = []


func set_curve(curve: Dictionary, color: Color) -> void:
	_counts.clear()
	for mv in COLUMNS:
		_counts.append(0)
	for mv in curve:
		_counts[mini(int(mv), COLUMNS - 1)] += int(curve[mv])
	for mv in COLUMNS:
		var column := $Columns.get_child(mv)
		column.get_node("Count").text = str(_counts[mv]) if _counts[mv] > 0 else ""
		column.get_node("Well/Bar").color = color
	_layout_bars()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_bars.call_deferred()


# The wells only have their height once the containers laid them out
func _layout_bars() -> void:
	if _counts.is_empty():
		return
	var tallest := maxi(1, _counts.max())
	for mv in COLUMNS:
		var well: Control = $Columns.get_child(mv).get_node("Well")
		var bar: ColorRect = well.get_node("Bar")
		bar.offset_top = -maxf(MIN_BAR, well.size.y * _counts[mv] / tallest)
