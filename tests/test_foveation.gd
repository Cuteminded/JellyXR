extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	check(ProjectSettings.get_setting("xr/openxr/extensions/eye_gaze_interaction", false), "Request optional eye gaze support before OpenXR initializes")
	check(ProjectSettings.get_setting("xr/openxr/foveation_eye_tracked", false), "Prefer native eye-tracked foveation when available")
	check(ProjectSettings.get_setting("xr/openxr/foveation_level", 0) == 1, "Use low native foveation")
	check_eye_binding()
	var world := ViewingWorld.new()
	world.settings = JellyXRSettings.new()
	root.add_child(world)
	world.setup()
	check(not root.use_xr, "Run this check with --xr-mode off")
	check(root.vrs_mode == Viewport.VRS_DISABLED, "Desktop preview must keep full shading quality")
	check(world.viewport.vrs_mode == Viewport.VRS_DISABLED, "The UI texture must keep full shading quality")
	world.free()
	if failures == 0: print("Foveation settings, eye gaze binding and desktop fallback passed.")
	quit(1 if failures else 0)

func check_eye_binding() -> void:
	var action_map := load("res://openxr_action_map.tres") as OpenXRActionMap
	var eye_action: OpenXRAction
	for action_set in action_map.get_action_sets():
		for action in action_set.get_actions():
			if action.resource_name == "eye_gaze_pose": eye_action = action
	check(eye_action != null, "Godot's VRS implementation requires an action named eye_gaze_pose")
	if eye_action == null: return
	check(eye_action.action_type == OpenXRAction.OPENXR_ACTION_POSE, "Eye gaze must provide a pose")
	check(eye_action.toplevel_paths == PackedStringArray(["/user/eyes_ext"]), "Eye gaze must use the eye tracker")
	var bound := false
	for profile in action_map.get_interaction_profiles():
		if profile.interaction_profile_path != "/interaction_profiles/ext/eye_gaze_interaction": continue
		for binding in profile.get_bindings():
			if binding.action == eye_action and binding.binding_path == "/user/eyes_ext/input/gaze_ext/pose": bound = true
	check(bound, "Bind the eye gaze action so VRS can follow gaze instead of silently using the center")
