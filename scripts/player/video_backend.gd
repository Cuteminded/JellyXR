class_name VideoBackend
extends Node

signal failed(message: String)
signal prepared
signal ended
signal size_changed(width: int, height: int)

var bridge: Object
var paused := false
var material: ShaderMaterial

func available() -> bool:
	return false

func unavailable_message() -> String:
	return "Video playback is unavailable on this platform."

func has_android_services() -> bool:
	return false

func open(_url: String, _authorization: String, _start_ms: int) -> void:
	failed.emit(unavailable_message())

func toggle_pause() -> void:
	pass

func seek(_milliseconds: int) -> void:
	pass

func position_ms() -> int:
	return 0

func duration_ms() -> int:
	return 0

func is_buffering() -> bool:
	return bridge != null and bridge.has_method("is_buffering") and bridge.is_buffering()

func stop() -> void:
	pass
