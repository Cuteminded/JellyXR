class_name ControllerBindings
extends RefCounted

const STEAM_FRAME_PROFILE := "/interaction_profiles/valve/frame_controller_valve"

const ACTIONS := {
	"none": "No action",
	"menu": "Playback controls",
	"settings": "Settings",
	"library": "Library",
	"pause": "Play / pause",
	"recenter": "Recenter"
}
const BUTTONS := {
	"left_hand/ax_button": "X button",
	"left_hand/by_button": "Y button",
	"left_hand/grip_click": "Grip",
	"left_hand/primary_click": "Thumbstick click",
	"right_hand/ax_button": "A button",
	"right_hand/by_button": "B button",
	"right_hand/grip_click": "Grip",
	"right_hand/primary_click": "Thumbstick click"
}
const DEFAULTS := {
	"left_hand/ax_button": "menu",
	"left_hand/by_button": "settings",
	"right_hand/ax_button": "menu",
	"right_hand/by_button": "library",
	"right_hand/menu_button": "menu"
}
const STEAM_FRAME_BUTTONS := {
	"left_hand/dpad_up": "D-pad up",
	"left_hand/dpad_down": "D-pad down",
	"left_hand/dpad_left": "D-pad left",
	"left_hand/dpad_right": "D-pad right",
	"left_hand/view_button": "View button",
	"left_hand/grip_click": "Grip",
	"left_hand/primary_click": "Thumbstick click",
	"right_hand/ax_button": "A button",
	"right_hand/by_button": "B button",
	"right_hand/x_button": "X button",
	"right_hand/y_button": "Y button",
	"right_hand/grip_click": "Grip",
	"right_hand/primary_click": "Thumbstick click"
}
const STEAM_FRAME_DEFAULTS := {
	"left_hand/dpad_down": "menu",
	"left_hand/dpad_up": "settings",
	"right_hand/ax_button": "menu",
	"right_hand/by_button": "library",
	"right_hand/menu_button": "menu"
}

const PROFILES := {
	STEAM_FRAME_PROFILE: {
		"name": "Steam Frame",
		"config_section": "controls_steam_frame",
		"buttons": STEAM_FRAME_BUTTONS,
		"defaults": STEAM_FRAME_DEFAULTS,
		"left_model": preload("res://assets/controllers/steam_frame_left.tres"),
		"right_model": preload("res://assets/controllers/steam_frame_right.tres")
	}
}

var profile := ""
var overrides: Dictionary = {}

func _init(controller_profile: String = "") -> void:
	profile = controller_profile

static func active_profile(hand: StringName) -> String:
	var tracker := XRServer.get_tracker(hand) as XRPositionalTracker
	return tracker.get_tracker_profile().strip_edges() if tracker != null else ""

func buttons() -> Dictionary:
	return PROFILES.get(profile, {}).get("buttons", BUTTONS)

func _defaults() -> Dictionary:
	return PROFILES.get(profile, {}).get("defaults", DEFAULTS)

func _config_section() -> String:
	return PROFILES.get(profile, {}).get("config_section", "controls")

func action_for(button: String) -> String:
	if not buttons().has(button): return _defaults().get(button, "none")
	return overrides.get(button, _defaults().get(button, "none"))

func assign(button: String, action: String) -> void:
	if not buttons().has(button) or not ACTIONS.has(action): return
	if action == _defaults().get(button, "none"):
		overrides.erase(button)
	else:
		overrides[button] = action

func load_config(config: ConfigFile) -> void:
	overrides.clear()
	var section := _config_section()
	for button in buttons():
		var action: Variant = config.get_value(section, button, _defaults().get(button, "none"))
		if action is String: assign(button, action)

func save_config(config: ConfigFile) -> void:
	var section := _config_section()
	for button in overrides:
		config.set_value(section, button, overrides[button])
