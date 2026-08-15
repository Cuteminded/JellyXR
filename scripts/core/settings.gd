class_name JellyframeSettings
extends RefCounted

const PATH := "user://settings.cfg"
var width := 3.6
var distance := 3.0
var height := 0.0
var curvature := 0.0
var environment := "Void"
var server := ""
var device_id := ""

func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	width = clampf(config.get_value("screen", "width", width), 1.5, 7.0)
	distance = clampf(config.get_value("screen", "distance", distance), 1.5, 8.0)
	height = clampf(config.get_value("screen", "height", height), -2.0, 2.0)
	curvature = clampf(config.get_value("screen", "curvature", curvature), 0.0, 1.2)
	environment = config.get_value("screen", "environment", "Void")
	server = config.get_value("connection", "server", "")
	device_id = config.get_value("connection", "device_id", "")
	if device_id.is_empty():
		device_id = Crypto.new().generate_random_bytes(16).hex_encode()
		save()

func save() -> Error:
	var config := ConfigFile.new()
	for key in ["width", "distance", "height", "curvature", "environment"]:
		config.set_value("screen", key, get(key))
	config.set_value("connection", "server", server)
	config.set_value("connection", "device_id", device_id)
	return config.save(PATH)

