class_name ControllerBindings
extends RefCounted

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

var overrides: Dictionary = {}

func action_for(button: String) -> String:
	if not BUTTONS.has(button): return DEFAULTS.get(button, "none")
	return overrides.get(button, DEFAULTS.get(button, "none"))

func assign(button: String, action: String) -> void:
	if not BUTTONS.has(button) or not ACTIONS.has(action): return
	if action == DEFAULTS.get(button, "none"):
		overrides.erase(button)
	else:
		overrides[button] = action

func load_config(config: ConfigFile) -> void:
	overrides.clear()
	for button in BUTTONS:
		var action: Variant = config.get_value("controls", button, DEFAULTS.get(button, "none"))
		if action is String: assign(button, action)

func save_config(config: ConfigFile) -> void:
	for button in overrides:
		config.set_value("controls", button, overrides[button])
