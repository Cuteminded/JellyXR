extends SceneTree

class FixtureSettings extends JellyframeSettings:
	func load_settings(_path: String = PATH) -> void:
		pass
	func save(_path: String = PATH) -> Error:
		return OK

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var theatre := TheatreEnvironment.new()
	root.add_child(theatre)
	theatre.build()
	var batches := 0
	var instances := 0
	for child in theatre.get_children():
		if child is MultiMeshInstance3D:
			batches += 1
			instances += child.multimesh.instance_count
	check(instances > 400 and batches < 40, "Seats and architecture must be batched instead of using a draw call per part.")
	var viewer := Transform3D(Basis.from_euler(Vector3(0.2, 0.6, 0.1)), Vector3(0.5, 1.6, 0.3))
	theatre.recenter(viewer)
	check(theatre.global_position.is_equal_approx(viewer.origin), "Recenter anchors the theatre at the viewer.")
	check(theatre.global_basis.y.is_equal_approx(Vector3.UP), "The theatre stays upright when the viewer tilts their head.")
	var screen := MeshInstance3D.new()
	root.add_child(screen)
	for aspect_ratio in [16.0 / 9.0, 2.39, 4.0 / 3.0]:
		var dimensions := theatre.video_size(aspect_ratio)
		screen.mesh = Stereo.mesh(dimensions.x, aspect_ratio, 0.0)
		screen.global_transform = theatre.projection_transform()
		check(dimensions.x <= TheatreEnvironment.SCREEN_SIZE.x and dimensions.y <= TheatreEnvironment.SCREEN_SIZE.y, "Every video format must fit inside the physical cinema screen.")
		check(is_equal_approx(dimensions.x / dimensions.y, aspect_ratio), "Video proportions must be preserved.")
		check(theatre.screen_frame.mesh.get_aabb().size.y > screen.mesh.get_aabb().size.y, "The frame surrounds the movie screen.")
		check(theatre.screen_frame.global_basis.is_equal_approx(screen.global_basis), "The screen frame follows the screen orientation.")
		var bounds := screen.mesh.get_aabb()
		for index in range(8):
			var point := theatre.to_local(screen.to_global(bounds.get_endpoint(index)))
			check(theatre.front_floor.position.y + 0.1 < point.y, "The front floor must stay below every screen corner.")
	screen.hide()
	check(theatre.screen_frame.visible, "The physical cinema screen remains visible between videos.")
	await check_environment_switching()
	if "--capture" in OS.get_cmdline_user_args():
		await capture(theatre, screen)
	print("Theatre failures: ", failures, "; batches: ", batches, "; instances: ", instances)
	quit(1 if failures else 0)

func check_environment_switching() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	app.settings = FixtureSettings.new()
	root.add_child(app)
	check(not app.theatre.visible, "Void starts without theatre geometry.")
	app._screen_settings()
	var view: SettingsView = app.page.get_child(0)
	var theatre_choice: CheckBox = view.sections[2].get_child(2).get_child(1)
	theatre_choice.button_pressed = true
	theatre_choice.pressed.emit()
	check(app.theatre.visible and app.settings.environment == "Theatre", "Selecting Theatre shows the cinema immediately.")
	var projection: Transform3D = app.theatre.projection_transform()
	check(app.screen.global_transform.is_equal_approx(projection), "The video must be mounted on the theatre's front screen.")
	check(app.screen.global_basis.y.is_equal_approx(Vector3.UP), "The mounted screen stays upright.")
	var movie_size: Vector3 = app.screen.mesh.get_aabb().size
	app.settings.width = 7.0
	app.settings.distance = 1.5
	app.settings.height = -2.0
	app.settings.curvature = 1.2
	app._position_screen()
	app._resize_screen()
	check(app.screen.global_transform.is_equal_approx(projection) and app.screen.mesh.get_aabb().size.is_equal_approx(movie_size), "Void screen adjustments must not move or resize the Theatre projection.")
	app.camera.position += Vector3(0.3, 0.1, 0.2)
	app.camera.rotation = Vector3(0.25, 0.4, 0.1)
	app._position_screen()
	check(app.screen.global_transform.is_equal_approx(projection), "Head movement must not move the mounted movie screen.")
	app._recenter()
	check(app.screen.global_transform.is_equal_approx(app.theatre.projection_transform()) and app.screen.global_basis.y.is_equal_approx(Vector3.UP), "Recenter keeps the movie attached to an upright cinema screen.")
	var slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(not slider.editable, "Void position controls are disabled in Theatre.")
	var reset: Button = view.sections[1].get_child(0).get_child(1)
	reset.pressed.emit()
	check(app.theatre.visible and app.settings.environment == "Theatre", "Screen reset preserves the separate environment choice.")
	var void_choice: CheckBox = view.sections[2].get_child(2).get_child(0)
	void_choice.button_pressed = true
	void_choice.pressed.emit()
	check(not app.theatre.visible and app.settings.environment == "Void", "The Environment page can return to Void.")
	check(is_equal_approx(app.screen.global_position.distance_to(app.camera.global_position), 3.0), "Void restores the saved floating screen distance.")
	app.queue_free()
	await process_frame
	await process_frame

func capture(theatre: TheatreEnvironment, screen: MeshInstance3D) -> void:
	root.size = Vector2i(1440, 900)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	root.add_child(camera)
	camera.current = true
	theatre.recenter(camera.global_transform)
	var dimensions := theatre.video_size(16.0 / 9.0)
	screen.mesh = Stereo.mesh(dimensions.x, 16.0 / 9.0, 0.0)
	screen.global_transform = theatre.projection_transform()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load("res://assets/logo/jellyframe-wordmark.png")
	material.albedo_color = Color("d5e1ef")
	screen.material_override = material
	screen.show()
	await snapshot("theatre-forward")
	camera.rotate_y(-0.9)
	await snapshot("theatre-side")
	camera.rotation.y = PI
	camera.rotation.x = -0.2
	await snapshot("theatre-seating")

func snapshot(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/" + filename + ".png")
