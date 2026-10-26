extends SceneTree

class FixtureVideo extends VideoBackend:
	func available() -> bool: return true
	func open(_url: String, _authorization: String, _start_ms: int) -> void: pass
	func stop() -> void: pass

class FixtureSession extends PlaybackSession:
	func open(selected: Dictionary, _transcode: bool = false) -> void: item = selected
	func report(_event: String, _paused: bool = false) -> void: pass

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
	await check_playback_placement(app)
	check_screen_follow(app)
	app.playing = false
	root.use_xr = false
	if added_interface: XRServer.remove_interface(xr)
	print("Startup recenter checks: PASS")
	quit()

func check_screen_follow(app: Node) -> void:
	app.settings.follow_screen = true
	app.settings.distance = 4.0
	app.settings.height = 0.4
	app.projection_mode = VideoProjection.Mode.SCREEN
	var menu_transform: Transform3D = app.panel.global_transform
	for environment in ["Void", "Passthrough"]:
		app.settings.environment = environment
		app.camera.position += Vector3(0.5, 0.2, -0.3)
		app.camera.rotation = Vector3(0.3, 0.7, 0.2)
		app._update_screen_follow()
		assert(app.screen.global_basis.is_equal_approx(app.camera.global_basis), "Following tracks head rotation in adjustable environments")
		var expected: Vector3 = app.camera.global_position - app.camera.global_basis.z * 4.0 + app.camera.global_basis.y * 0.4
		assert(app.screen.global_position.is_equal_approx(expected), "Following tracks translation and preserves distance and height")
		assert(app.panel.global_transform.is_equal_approx(menu_transform), "Following the movie does not move the settings window")
	app.settings.follow_screen = false
	var stationary: Transform3D = app.screen.global_transform
	app.camera.position += Vector3.ONE
	app.camera.rotate_y(0.4)
	app._update_screen_follow()
	assert(app.screen.global_transform.is_equal_approx(stationary), "Disabling following leaves the screen at its last position")
	app.settings.follow_screen = true
	for environment in ["Cinema", "Theatre"]:
		app.settings.environment = environment
		app._change_environment()
		var fixed_screen: Transform3D = app.screen.global_transform
		app.camera.position += Vector3.ONE
		app.camera.rotate_y(0.4)
		app._update_screen_follow()
		assert(app.screen.global_transform.is_equal_approx(fixed_screen), "Cinema and Theatre screens never follow head movement")
	app.settings.environment = "Void"
	for projection in [VideoProjection.Mode.EQUIRECTANGULAR_180, VideoProjection.Mode.EQUIRECTANGULAR]:
		app.projection_mode = projection
		var before: Transform3D = app.screen.global_transform
		var panorama: Basis = app.world.panorama.global_basis
		app.camera.rotate_y(0.4)
		app._update_screen_follow()
		assert(app.screen.global_transform.is_equal_approx(before) and app.world.panorama.global_basis.is_equal_approx(panorama), "Following does not rotate immersive video with the head")
	app.settings.follow_screen = false
	app.projection_mode = VideoProjection.Mode.SCREEN

func check_playback_placement(app: Node) -> void:
	app.video.queue_free()
	app.session.queue_free()
	app.video = FixtureVideo.new()
	app.session = FixtureSession.new()
	app.add_child(app.video)
	app.add_child(app.session)
	for environment in ["Void", "Cinema", "Theatre"]:
		app.settings.environment = environment
		app._change_environment()
		app._recenter()
		var screen_transform: Transform3D = app.screen.global_transform
		var theatre_transform: Transform3D = app.theatre.global_transform
		var panorama_basis: Basis = app.world.panorama.global_basis
		app.camera.position += Vector3(0.4, 0.2, 0.3)
		app.camera.rotate_y(0.5)
		await app._start({"Id": environment})
		assert(app.screen.global_transform.is_equal_approx(screen_transform), "Starting an item preserves screen placement")
		for path in ["Normal.mp4", "Beach.VR180.mp4", "Beach.360.mp4", "Normal.mp4"]:
			await app._play_stream("", {"Path": path}, 0)
			assert(app.screen.global_transform.is_equal_approx(screen_transform), "Starting a stream preserves screen placement")
			assert(app.theatre.global_transform.is_equal_approx(theatre_transform), "Starting a stream preserves theatre placement")
			assert(app.world.panorama.global_basis.is_equal_approx(panorama_basis), "Starting a stream preserves panorama direction")
			app.camera.rotate_y(0.2)

func check_menu_placement(app: Node) -> void:
	for environment in ["Theatre", "Cinema", "Void"]:
		app.settings.environment = environment
		app._change_environment()
		for pitch in [-70.0, -30.0, 0.0]:
			app.camera.rotation = Vector3(deg_to_rad(pitch), 0.4, 0.3)
			app._recenter()
			assert(app.panel.global_basis.is_equal_approx(app.camera.global_basis), "Menu recenter preserves the viewing direction")
			assert(app.panel.global_position.is_equal_approx(app.camera.global_position - app.camera.global_basis.z * 2.7), "Room geometry does not shift the menu position")
