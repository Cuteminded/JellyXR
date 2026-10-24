extends SceneTree

var calls := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var startup := StartupRecenter.new()
	root.add_child(startup)
	startup.ready_to_center.connect(func(): calls += 1)
	startup.update_tracking(false, 10.0)
	assert(calls == 0, "Do not center before headset tracking starts")
	startup.update_tracking(true, 0.2)
	startup.update_tracking(false, 0.1)
	startup.update_tracking(true, 0.2)
	assert(calls == 0, "Tracking loss resets the settling period")
	startup.update_tracking(true, 0.2)
	assert(calls == 1, "Stable tracking centers once")
	startup.update_tracking(true, 10.0)
	assert(calls == 1, "Normal head movement does not keep recentering")
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	var added_interface := xr == null
	if added_interface:
		xr = OpenXRInterface.new()
		XRServer.add_interface(xr)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var menu_transform: Transform3D = app.panel.global_transform
	var movie_transform: Transform3D = app.screen.global_transform
	app.camera.position += Vector3(0.4, 0.2, 0.0)
	app.camera.rotate_y(0.5)
	root.use_xr = true
	app.panel.show()
	app._toggle_menu()
	assert(not app.panel.visible, "The controller hides the menu")
	app._toggle_menu()
	assert(app.panel.visible, "The controller shows the menu again")
	assert(app.panel.global_transform == menu_transform, "Menu toggling preserves its world position and orientation")
	assert(app.screen.global_transform == movie_transform, "Menu toggling does not reposition the movie")
	app._recenter()
	assert(app.panel.global_transform != menu_transform, "Explicit recenter still follows the current viewing position")
	app.playing = true
	app.screen.show()
	var screen_transform: Transform3D = app.screen.global_transform
	app._toggle_menu()
	assert(app.player_overlay.is_visible_in_tree() and not app.panel.visible, "Playback toggles the screen overlay instead of the main menu")
	assert(app.player_overlay.get_parent() == app.screen, "The overlay follows the movie screen")
	app._toggle_menu()
	assert(not app.player_overlay.visible and app.screen.global_transform == screen_transform, "Hiding the overlay does not move the movie")
	app.api.token = "fixture"
	app.shell.set_signed_in(true)
	app._screen_settings()
	assert(app.panel.visible and not app.player_overlay.visible, "Settings open in the main window")
	var menu_material: StandardMaterial3D = app.panel.material_override
	assert(not menu_material.no_depth_test, "Main-window pages respect controller depth")
	app._show_playback()
	assert(not app.panel.visible and app.player_overlay.visible, "Returning from settings restores the overlay")
	var before_reset: Transform3D = app.screen.global_transform
	app.camera.position += Vector3(0.5, 0.1, 0.2)
	app.camera.rotate_y(0.4)
	xr.pose_recentered.emit()
	await process_frame
	await process_frame
	assert(app.screen.global_transform != before_reset, "Headset recenter moves the movie to the new viewing position")
	assert(app.screen.global_basis.is_equal_approx(app.camera.global_basis), "Headset recenter uses the current viewing direction")
	assert(app.panel.global_position.is_equal_approx(app.camera.global_position - app.camera.global_basis.z * 2.7), "Headset recenter also moves the library menu")
	assert(not app.panel.visible and app.player_overlay.visible, "Headset recenter preserves menu visibility")
	check_menu_placement(app)
	app.playing = false
	root.use_xr = false
	if added_interface: XRServer.remove_interface(xr)
	print("Startup recenter checks: PASS")
	quit()

func check_menu_placement(app: Node) -> void:
	for environment in ["Theatre", "Cinema", "Void"]:
		app.settings.environment = environment
		app._change_environment()
		for pitch in [-70.0, -30.0, 0.0]:
			app.camera.rotation = Vector3(deg_to_rad(pitch), 0.4, 0.3)
			app._recenter()
			assert(app.panel.global_basis.is_equal_approx(app.camera.global_basis), "Menu recenter preserves the viewing direction")
			assert(app.panel.global_position.is_equal_approx(app.camera.global_position - app.camera.global_basis.z * 2.7), "Room geometry does not shift the menu position")
