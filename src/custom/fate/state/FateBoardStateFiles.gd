# Reading, writing and listing board state files (FateBoardState as JSON).
#
# Two folders:
#   res://boards/       shared positions, checked into the repo, hand-editable. Only writable
#                       when the game runs from the editor.
#   user://boards/      personal positions of whoever plays (the user data folder of the game).
# A state is addressed by its file name without ".json" ("two_goblins"), or by a full path.
# When both folders have the same name the personal one wins.
class_name FateBoardStateFiles
extends RefCounted

const SHARED_DIR := "res://boards"
const USER_DIR := "user://boards"
const EXTENSION := "json"
# The schema file sits next to the shared states but is not a state
const SKIP_FILES := ["board_state.schema.json"]
const SOURCE_SHARED := "repo"
const SOURCE_USER := "personal"


# Every state file: Array of {name, path, source}, shared first, each folder sorted by name
static func list() -> Array:
	var found := []
	for entry in [[SHARED_DIR, SOURCE_SHARED], [USER_DIR, SOURCE_USER]]:
		var names := []
		var dir := DirAccess.open(entry[0])
		if dir == null:
			continue
		for file_name in dir.get_files():
			# Exported projects list resources as "<name>.remap" or ".import"; plain json files keep their name
			if file_name.get_extension() == EXTENSION and not file_name in SKIP_FILES:
				names.append(file_name)
		names.sort()
		for file_name in names:
			found.append({
				"name": file_name.get_basename(),
				"path": "%s/%s" % [entry[0], file_name],
				"source": entry[1],
			})
	return found


# The path a name or path stands for, or "" if there is no such file
static func resolve(name_or_path: String) -> String:
	var wanted := name_or_path.strip_edges()
	if wanted == "":
		return ""
	if wanted.begins_with("res://") or wanted.begins_with("user://") or wanted.is_absolute_path():
		return wanted if FileAccess.file_exists(wanted) else ""
	var file_name := wanted if wanted.get_extension() == EXTENSION else "%s.%s" % [wanted, EXTENSION]
	for dir in [USER_DIR, SHARED_DIR]:
		var path := "%s/%s" % [dir, file_name]
		if FileAccess.file_exists(path):
			return path
	return ""


# Reads a state. Never null: a missing or unreadable file comes back as a state whose
# `load_errors` says what is wrong (validate() reports them with everything else).
static func load_state(name_or_path: String) -> FateBoardState:
	var path := resolve(name_or_path)
	if path == "":
		var state := FateBoardState.new()
		state.load_errors.append("No board state called \"%s\" in %s or %s" % [name_or_path, SHARED_DIR, USER_DIR])
		return state
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var state := FateBoardState.new()
		state.load_errors.append("Cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return state
	var state := FateBoardState.from_json(file.get_as_text())
	if state.data["name"] == "":
		state.set_state_name(path.get_file().get_basename())
	return state


# Writes a state as `name`.json into the personal folder, or into res://boards when `to_repo`.
# Returns {ok: bool, path: String, error: String}.
static func save_state(state: FateBoardState, name: String, to_repo := false) -> Dictionary:
	var file_name := sanitize(name)
	if file_name == "":
		return {"ok": false, "path": "", "error": "Give the board state a name first"}
	var dir := SHARED_DIR if to_repo else USER_DIR
	if to_repo and not OS.has_feature("editor"):
		return {"ok": false, "path": "", "error": "The repo folder can only be written when the game runs from the editor; save it as a personal state instead"}
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK and made != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": "", "error": "Cannot create the folder %s (error %d)" % [dir, made]}
	var path := "%s/%s.%s" % [dir, file_name, EXTENSION]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path, "error": "Cannot write %s (error %d)" % [path, FileAccess.get_open_error()]}
	if state.data["name"] == "":
		state.set_state_name(name.strip_edges())
	file.store_string(state.to_json(true) + "\n")
	file.close()
	return {"ok": true, "path": path, "error": ""}


# Deletes a personal state (the shared ones are managed in the repo). Returns "" or an error.
static func delete_state(name: String) -> String:
	var path := "%s/%s.%s" % [USER_DIR, sanitize(name), EXTENSION]
	if not FileAccess.file_exists(path):
		return "There is no personal board state called \"%s\"" % name
	var err := DirAccess.remove_absolute(path)
	return "" if err == OK else "Cannot delete %s (error %d)" % [path, err]


# A name safe for a file: letters, digits, spaces, "-" and "_"; spaces become "_"
static func sanitize(name: String) -> String:
	var out := ""
	for ch in name.strip_edges():
		if ch.unicode_at(0) < 128 and (ch.is_valid_identifier() or ch.is_valid_int() or ch in [" ", "-", "_"]):
			out += "_" if ch == " " else ch
	return out.lstrip("_-.")


# --- the clipboard: paste a state from a chat or an editor, copy one out ------------------------

static func copy_to_clipboard(state: FateBoardState) -> void:
	DisplayServer.clipboard_set(state.to_json(true))


static func from_clipboard() -> FateBoardState:
	return FateBoardState.from_json(DisplayServer.clipboard_get())
