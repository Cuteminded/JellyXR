class_name SessionStore
extends RefCounted

const PATH := "user://session.cfg"
var path := PATH

func load_session() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK: return {}
	var data := {}
	for key in ["server", "token", "user_id"]:
		var value: Variant = config.get_value("session", key, "")
		if not value is String or value.is_empty(): return {}
		data[key] = value
	return data

func save_session(data: Dictionary) -> Error:
	var config := ConfigFile.new()
	for key in ["server", "token", "user_id"]:
		config.set_value("session", key, data[key])
	return config.save(path)

func clear_session() -> Error:
	if not FileAccess.file_exists(path): return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
