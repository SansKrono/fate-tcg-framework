# Counts the script errors the engine prints while games are played, so a run can say which card scripts
# are broken instead of leaving it to the console of a process nobody reads. Installed with
# OS.add_logger() by FateSimRunner; the engine may call it from any thread, hence the mutex.
#
# Warnings are ignored (the table builds a lot of harmless layout warnings). An error is identified by the
# script file, the line and the start of its text; repeats just count.
#
# No class_name (see FateAIEval.gd).
extends Logger

const TEXT_LENGTH := 90
const MAX_KEYS := 40

var _mutex := Mutex.new()
var _counts := {}


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	var text := rationale if rationale != "" else code
	var key := "%s:%d  %s" % [file.get_file(), line, text.replace("\n", " ").left(TEXT_LENGTH)]
	_mutex.lock()
	if _counts.has(key) or _counts.size() < MAX_KEYS:
		_counts[key] = _counts.get(key, 0) + 1
	_mutex.unlock()


# The errors since the last call, {"file.gd:12  text": count}, and starts counting again
func take() -> Dictionary:
	_mutex.lock()
	var found := _counts
	_counts = {}
	_mutex.unlock()
	return found
