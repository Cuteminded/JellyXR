extends SceneTree

class FixtureVideo extends VideoBackend:
	func toggle_pause() -> void: paused = not paused

class FixtureSession extends PlaybackSession:
	func report(_event: String, _paused: bool = false) -> void: pass

var received: Array[String] = []
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String = "Controller binding check failed") -> void:
	if condition: return
	failures += 1
	push_error(message)

func run_checks() -> void:
	var settings := JellyXRSettings.new()
	var bindings := settings.controller_bindings
	check(bindings.action_for("left_hand/by_button") == "settings")
	check(bindings.action_for("right_hand/by_button") == "library")
	check(bindings.action_for("left_hand/ax_button") == "menu")
	check(bindings.action_for("right_hand/menu_button") == "menu")
	check(bindings.action_for("left_hand/menu_button") == "none")
	bindings.assign("right_hand/menu_button", "pause")
	check(bindings.action_for("right_hand/menu_button") == "menu", "The right Menu button keeps its fixed action")
	check(not ControllerBindings.BUTTONS.has("right_hand/menu_button") and not ControllerBindings.BUTTONS.has("left_hand/menu_button"), "Menu buttons are excluded from remapping")
	bindings.assign("left_hand/by_button", "pause")
	bindings.assign("right_hand/by_button", "none")
	bindings.assign("right_hand/grip_click", "recenter")
	var path := "user://controller-bindings-test.cfg"
	settings.device_id = "controller-test-device"
	check(settings.save(path) == OK)
	var restored := JellyXRSettings.new()
	restored.load_settings(path)
	check(restored.controller_bindings.action_for("left_hand/by_button") == "pause", "Remapping survives a restart")
	check(restored.controller_bindings.action_for("right_hand/by_button") == "none", "Disabled shortcuts survive a restart")
	check(restored.controller_bindings.action_for("right_hand/grip_click") == "recenter")
	check(JellyXRSettings.new().controller_bindings.action_for("left_hand/by_button") == "settings", "Settings instances do not share overrides")
	var config := ConfigFile.new()
	check(config.load(path) == OK)
	config.set_value("controls", "left_hand/by_button", "invalid")
	config.set_value("controls", "right_hand/by_button", ["library"])
	config.set_value("controls", "left_hand/menu_button", "pause")
	config.set_value("controls", "right_hand/menu_button", "pause")
	check(config.save(path) == OK)
	restored.load_settings(path)
	check(restored.controller_bindings.action_for("left_hand/by_button") == "settings", "Invalid actions fall back to defaults")
	check(restored.controller_bindings.action_for("right_hand/by_button") == "library", "Invalid value types fall back to defaults")
	check(restored.controller_bindings.action_for("left_hand/menu_button") == "none", "Reserved inputs cannot be remapped through config")
	check(restored.controller_bindings.action_for("right_hand/menu_button") == "menu", "Old Menu button overrides are ignored")
	var world := ViewingWorld.new()
	world.settings = settings
	world.menu_requested.connect(func(): received.append("menu"))
	world.settings_requested.connect(func(): received.append("settings"))
	world.library_requested.connect(func(): received.append("library"))
	world.pause_requested.connect(func(): received.append("pause"))
	world.recenter_requested.connect(func(): received.append("recenter"))
	for action in ControllerBindings.ACTIONS:
		received.clear()
		bindings.assign("left_hand/primary_click", action)
		world._controller_button_pressed("primary_click", &"left_hand")
		check(received == ([] if action == "none" else [action]), "Every assigned action dispatches exactly once")
	received.clear()
	world._controller_button_pressed("by_button", &"right_hand")
	world._controller_button_pressed("menu_button", &"left_hand")
	world._controller_button_pressed("trigger_click", &"left_hand")
	world._controller_button_pressed("ax_touch", &"left_hand")
	check(received.is_empty(), "Disabled, reserved, select and touch inputs do not run shortcuts")
	world._controller_button_pressed("menu_button", &"right_hand")
	check(received == ["menu"], "The right Menu button keeps opening playback controls")
	bindings.overrides.clear()
	check(settings.save(path) == OK)
	restored.load_settings(path)
	check(restored.controller_bindings.overrides.is_empty(), "Reset removes saved overrides")
	check(restored.controller_bindings.action_for("right_hand/by_button") == "library")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	world.free()
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.video.queue_free()
	app.video = FixtureVideo.new()
	app.add_child(app.video)
	app.session.queue_free()
	app.session = FixtureSession.new()
	app.add_child(app.session)
	app.settings.controller_bindings.assign("right_hand/grip_click", "pause")
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(not app.video.paused, "Play/pause does nothing without active playback")
	app.playing = true
	app.decoder_ready = true
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(app.video.paused, "Remapped play/pause reaches the player")
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(not app.video.paused, "The shortcut resumes playback")
	app.seeking = true
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(not app.video.paused, "Seeking blocks the shortcut")
	app.seeking = false
	app.photo_active = true
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(not app.video.paused, "Viewing a photo blocks the shortcut")
	app.photo_active = false
	app.settings.controller_bindings.assign("right_hand/grip_click", "recenter")
	app.camera.position.x += 1.0
	var previous_position: Vector3 = app.panel.global_position
	app.world._controller_button_pressed("grip_click", &"right_hand")
	check(not app.panel.global_position.is_equal_approx(previous_position), "Remapped recenter moves the menu with the viewer")
	app.viewport.get_parent().stretch = false
	app.viewport.size = Vector2i(1536, 960)
	app.api.token = "fixture"
	app.shell.set_signed_in(true)
	app._screen_settings()
	var settings_view: SettingsView
	for child in app.page.get_children():
		if child is SettingsView: settings_view = child
	settings_view._show_section(5)
	for frame in range(4): await process_frame
	var controls := settings_view.controller_controls
	controls.binding_buttons["left_hand/by_button"].pressed.emit()
	for frame in range(2): await process_frame
	var popup_rect := controls.editor.panel.get_rect()
	check(Rect2(Vector2.ZERO, Vector2(1536, 960)).encloses(popup_rect), "The first popup opening fits inside the VR viewport")
	check(popup_rect.size.y < 600, "The first popup opening fits its contents without excess height")
	app.queue_free()
	await process_frame
	await check_diagram_models()
	print("Controller binding checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func check_diagram_models() -> void:
	var generic: ControllerDiagramModel = load("res://assets/controllers/generic.tres")
	var alternate := ControllerDiagramModel.new()
	alternate.texture = GradientTexture2D.new()
	alternate.canvas_size = Vector2(240, 400)
	alternate.mirror_right = false
	alternate.button_positions = {"by_button": Vector2(180, 90)}
	alternate.button_labels = {"by_button": "Alternate face button"}
	var controls := ControllerSettings.new()
	controls.bindings = ControllerBindings.new()
	controls.right_model = alternate
	controls.size = Vector2(1000, 900)
	root.add_child(controls)
	await process_frame
	await process_frame
	var left := controls.hand_views[0]
	var right := controls.hand_views[1]
	check(left.model == generic and right.model == alternate, "Each hand loads its own diagram resource")
	check(right.hotspots.size() == 1 and right.hotspots.has("right_hand/by_button"), "The diagram resource supplies its remappable buttons")
	var hotspot: Button = right.hotspots["right_hand/by_button"]
	var expected := right.diagram_rect.position + Vector2(180, 90) * right.diagram_rect.size / alternate.canvas_size
	check((hotspot.position + hotspot.size / 2).is_equal_approx(expected), "Alternate artwork coordinates place the interactive target")
	check(hotspot.accessibility_name.contains("Alternate face button"), "The diagram resource supplies accessible button names")
	hotspot.pressed.emit()
	check(controls.selected_key == "right_hand/by_button", "A replacement diagram opens the same mapping editor")
	controls.action_buttons["recenter"].pressed.emit()
	check(controls.bindings.action_for("right_hand/by_button") == "library", "A replacement diagram keeps pending mappings separate")
	controls.apply_button.pressed.emit()
	check(controls.bindings.action_for("right_hand/by_button") == "recenter", "A replacement diagram uses the existing remapping behavior")
	for key in left.hotspots:
		var target: Button = left.hotspots[key]
		check(Rect2(Vector2.ZERO, left.size).encloses(target.get_rect()), "Generic diagram targets stay within the hand view")
		for other_key in left.hotspots:
			if key == other_key: continue
			check(not target.get_rect().intersects(left.hotspots[other_key].get_rect()), "Generic diagram targets do not overlap")
	controls.queue_free()
	await process_frame
