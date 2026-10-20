class_name JellyframeSettings
extends RefCounted

const PATH := "user://settings.cfg"
const SCREEN_KEYS := ["width", "distance", "height", "curvature"]
const PLAYBACK_MODES := ["auto", "original", "transcoded"]
const TRANSCODE_PRESETS := {
	720: {"label": "720p", "width": 1280, "height": 720, "bitrate": 6000000},
	1080: {"label": "1080p", "width": 1920, "height": 1080, "bitrate": 12000000},
	2160: {"label": "4K", "width": 3840, "height": 2160, "bitrate": 40000000}
}
const LIBRARY_SORT_OPTIONS := [
	["Name", "SortName"], ["Random", "Random"],
	["Community rating", "CommunityRating"], ["Critics rating", "CriticRating"],
	["Date added", "DateCreated"], ["Date played", "DatePlayed"],
	["Parental rating", "OfficialRating"], ["Play count", "PlayCount"],
	["Release date", "PremiereDate"], ["Runtime", "Runtime"]
]
var width := 3.6
var distance := 3.0
var height := 0.0
var curvature := 0.0
var environment := "Void"
var server := ""
var device_id := ""
var library_sort_by := "SortName"
var library_sort_order := "Ascending"
var playback_mode := "auto"
var transcode_resolution := 1080

func load_settings(path: String = PATH) -> void:
	var config := ConfigFile.new()
	config.load(path)
	width = clampf(config.get_value("screen", "width", width), 1.5, 7.0)
	distance = clampf(config.get_value("screen", "distance", distance), 1.5, 8.0)
	height = clampf(config.get_value("screen", "height", height), -2.0, 2.0)
	curvature = clampf(config.get_value("screen", "curvature", curvature), 0.0, 1.2)
	environment = config.get_value("screen", "environment", "Void")
	if int(config.get_value("screen", "environment_version", 1)) < 2:
		if environment == "Theatre": environment = "Cinema"
		elif environment == "Theatre LowRes": environment = "Theatre"
	if environment not in ["Void", "Cinema", "Theatre", "Passthrough"]: environment = "Void"
	server = config.get_value("connection", "server", "")
	device_id = config.get_value("connection", "device_id", "")
	library_sort_by = str(config.get_value("library", "sort_by", "SortName"))
	if not LIBRARY_SORT_OPTIONS.any(func(option: Array): return option[1] == library_sort_by):
		library_sort_by = "SortName"
	library_sort_order = str(config.get_value("library", "sort_order", "Ascending"))
	if library_sort_order not in ["Ascending", "Descending"]:
		library_sort_order = "Ascending"
	playback_mode = str(config.get_value("playback", "mode", "auto"))
	if playback_mode not in PLAYBACK_MODES: playback_mode = "auto"
	transcode_resolution = int(config.get_value("playback", "transcode_resolution", 1080))
	if not TRANSCODE_PRESETS.has(transcode_resolution): transcode_resolution = 1080
	if device_id.is_empty():
		device_id = Crypto.new().generate_random_bytes(16).hex_encode()
		save(path)

func is_theatre() -> bool:
	return environment in ["Cinema", "Theatre"]

func reset_screen() -> void:
	var defaults := JellyframeSettings.new()
	for key in SCREEN_KEYS:
		set(key, defaults.get(key))

func save(path: String = PATH) -> Error:
	var config := ConfigFile.new()
	for key in SCREEN_KEYS:
		config.set_value("screen", key, get(key))
	config.set_value("screen", "environment", environment)
	config.set_value("screen", "environment_version", 2)
	config.set_value("connection", "server", server)
	config.set_value("connection", "device_id", device_id)
	config.set_value("library", "sort_by", library_sort_by)
	config.set_value("library", "sort_order", library_sort_order)
	config.set_value("playback", "mode", playback_mode)
	config.set_value("playback", "transcode_resolution", transcode_resolution)
	return config.save(path)

