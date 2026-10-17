# Compatibility node which reproduces the Godot 3 "Tween" node API
# on top of Godot 4 [Tween] objects.
#
# Godot 4 removed the Tween node. The framework relies heavily on its
# queue-then-start workflow (interpolate_property() + start()),
# as well as on is_active(), remove() and the tween_all_completed signal,
# so this class provides those on a plain Node.
#
# Each interpolation is backed by its own Godot 4 Tween, which allows
# remove() to stop a single object/property pair, the same way it worked
# in Godot 3.
class_name TweenNode
extends Node

signal tween_started(object, key)
signal tween_step(object, key, elapsed, value)
signal tween_completed(object, key)
signal tween_all_completed

# Interpolations queued with interpolate_property() which have not been
# started yet.
var _pending := []
# Interpolations which are currently running.
# Each entry is a dictionary with "object", "key", "tween" and "duration".
var _running := []


# Queues an interpolation of an object's property.
# Mirrors Godot 3 Tween.interpolate_property()
func interpolate_property(object: Object, property, initial_val, final_val,
		duration: float, trans_type := Tween.TRANS_LINEAR,
		ease_type := Tween.EASE_IN_OUT, delay := 0.0) -> bool:
	if not is_instance_valid(object):
		return false
	_pending.append({
		"object": object,
		"key": NodePath(str(property)),
		"initial": initial_val,
		"final": final_val,
		"duration": max(duration, 0.0),
		"trans": trans_type,
		"ease": ease_type,
		"delay": max(delay, 0.0),
	})
	return true


# Queues a call to a method with a value interpolated between
# initial_val and final_val.
# Mirrors Godot 3 Tween.interpolate_method()
func interpolate_method(object: Object, method: String, initial_val, final_val,
		duration: float, trans_type := Tween.TRANS_LINEAR,
		ease_type := Tween.EASE_IN_OUT, delay := 0.0) -> bool:
	if not is_instance_valid(object):
		return false
	_pending.append({
		"object": object,
		"key": NodePath(method),
		"method": method,
		"initial": initial_val,
		"final": final_val,
		"duration": max(duration, 0.0),
		"trans": trans_type,
		"ease": ease_type,
		"delay": max(delay, 0.0),
	})
	return true


# Queues a method call after a delay.
# Mirrors Godot 3 Tween.interpolate_callback()
func interpolate_callback(object: Object, duration: float,
		callback: String, arg1 = null, arg2 = null, arg3 = null) -> bool:
	if not is_instance_valid(object):
		return false
	var args := []
	for arg in [arg1, arg2, arg3]:
		if arg != null:
			args.append(arg)
	_pending.append({
		"object": object,
		"key": NodePath(callback),
		"callback": callback,
		"args": args,
		"duration": 0.0,
		"delay": max(duration, 0.0),
	})
	return true


# Starts all queued interpolations.
func start() -> bool:
	var to_start := _pending
	_pending = []
	for spec in to_start:
		if not is_instance_valid(spec.object):
			continue
		_start_interpolation(spec)
	return true


# Returns true while any interpolation started by this node is running.
func is_active() -> bool:
	_prune()
	return not _running.is_empty()


# Stops and forgets all queued and running interpolations.
func remove_all() -> bool:
	_pending.clear()
	for entry in _running:
		if entry.tween and entry.tween.is_valid():
			entry.tween.kill()
	_running.clear()
	return true


# Stops and forgets the interpolations of a specific object.
# If key is provided, only that property's interpolations are removed.
func remove(object: Object, key = "") -> bool:
	var key_path := NodePath(str(key))
	var keep_pending := []
	for spec in _pending:
		if not _matches(spec, object, key_path):
			keep_pending.append(spec)
	_pending = keep_pending
	var keep_running := []
	for entry in _running:
		if _matches(entry, object, key_path):
			if entry.tween and entry.tween.is_valid():
				entry.tween.kill()
		else:
			keep_running.append(entry)
	_running = keep_running
	return true


# Same as remove_all(). Kept for API compatibility.
func stop_all() -> bool:
	return remove_all()


func stop(object: Object, key = "") -> bool:
	return remove(object, key)


# Returns the time in seconds until the longest running
# interpolation finishes.
func get_runtime() -> float:
	var runtime := 0.0
	for entry in _running:
		runtime = max(runtime, entry.duration)
	return runtime


func _start_interpolation(spec: Dictionary) -> void:
	var tween := create_tween()
	var entry := {
		"object": spec.object,
		"key": spec.key,
		"tween": tween,
		"duration": spec.duration + spec.delay,
	}
	_running.append(entry)
	if spec.delay > 0.0:
		tween.tween_interval(spec.delay)
	tween.tween_callback(_on_interpolation_started.bind(spec.object, spec.key))
	if spec.has("callback"):
		tween.tween_callback(Callable(spec.object, spec.callback).bindv(spec.args))
	elif spec.has("method"):
		tween.tween_method(Callable(spec.object, spec.method),
				spec.initial, spec.final, spec.duration)\
				.set_trans(spec.trans).set_ease(spec.ease)
	else:
		tween.tween_property(spec.object, spec.key, spec.final, spec.duration)\
				.from(spec.initial).set_trans(spec.trans).set_ease(spec.ease)
	tween.finished.connect(_on_interpolation_finished.bind(entry))


func _on_interpolation_started(object: Object, key: NodePath) -> void:
	tween_started.emit(object, key)


func _on_interpolation_finished(entry: Dictionary) -> void:
	_running.erase(entry)
	tween_completed.emit(entry.object, entry.key)
	_prune()
	if _running.is_empty():
		tween_all_completed.emit()


# Discards running entries whose tween was killed externally,
# or whose target object has been freed.
func _prune() -> void:
	var keep := []
	for entry in _running:
		if entry.tween and entry.tween.is_valid() \
				and is_instance_valid(entry.object):
			keep.append(entry)
		elif entry.tween and entry.tween.is_valid():
			entry.tween.kill()
	_running = keep


func _matches(spec: Dictionary, object: Object, key: NodePath) -> bool:
	if spec.object != object:
		return false
	return key.is_empty() or spec.key == key
