extends SceneTree

class FixtureSettings extends JellyXRSettings:
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
	var cinema := CinemaEnvironment.new()
	root.add_child(cinema)
	cinema.build()
	var batches := 0
	var instances := 0
	for child in cinema.interior.get_children():
		if child is MeshInstance3D:
			batches += 1
			instances += child.mesh.surface_get_array_index_len(0) / 3
	check(instances > 390000 and batches <= 8, "The imported cinema retains its geometry in at most eight material batches.")
	check(cinema.interior.get_child(0).mesh.get_aabb().size.x < 6.0, "The cinema must be converted from millimetres to metres.")
	check_projection_visibility(cinema)
	check_seated_height(cinema)
	var viewer := Transform3D(Basis.from_euler(Vector3(0.2, 0.6, 0.1)), Vector3(0.5, 1.6, 0.3))
	cinema.recenter(viewer)
	check(cinema.global_position.is_equal_approx(viewer.origin), "Recenter anchors the cinema at the viewer.")
	check(cinema.global_basis.y.is_equal_approx(Vector3.UP), "The cinema stays upright when the viewer tilts their head.")
	var screen := MeshInstance3D.new()
	root.add_child(screen)
	for aspect_ratio in [16.0 / 9.0, 2.39, 4.0 / 3.0]:
		var dimensions := cinema.video_size(aspect_ratio)
		screen.mesh = Stereo.mesh(dimensions.x, aspect_ratio, 0.0)
		screen.global_transform = cinema.projection_transform()
		check(dimensions.x <= CinemaEnvironment.SCREEN_SIZE.x and dimensions.y <= CinemaEnvironment.SCREEN_SIZE.y, "Every video format must fit inside the physical cinema screen.")
		check(is_equal_approx(dimensions.x / dimensions.y, aspect_ratio), "Video proportions must be preserved.")
		check(cinema.screen_frame.mesh.get_aabb().size.y > screen.mesh.get_aabb().size.y, "The frame surrounds the movie screen.")
		check(cinema.screen_frame.global_basis.is_equal_approx(screen.global_basis), "The screen frame follows the screen orientation.")
		var bounds := screen.mesh.get_aabb()
		for index in range(8):
			var point := cinema.to_local(screen.to_global(bounds.get_endpoint(index)))
			check(CinemaEnvironment.FLOOR < point.y, "The front floor must stay below every screen corner.")
	screen.hide()
	check(cinema.screen_frame.visible, "The physical cinema screen remains visible between videos.")
	await check_environment_switching()
	if "--capture" in OS.get_cmdline_user_args():
		await capture(cinema, screen)
	print("Cinema failures: ", failures, "; batches: ", batches, "; instances: ", instances)
	quit(1 if failures else 0)

func check_seated_height(cinema: CinemaEnvironment) -> void:
	var cushion: MeshInstance3D = cinema.interior.get_node("color_brown")
	var arrays := cushion.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cushion_distance := INF
	for triangle in range(0, indices.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3.ZERO, Vector3(0, -2.0, 0),
			vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]])
		if hit != null: cushion_distance = minf(cushion_distance, -hit.y)
	check(cushion_distance > 0.65 and cushion_distance < 0.85, "The viewer must sit above a real seat cushion at seated eye height.")

func check_projection_visibility(cinema: CinemaEnvironment) -> void:
	for child: MeshInstance3D in cinema.interior.get_children():
		var arrays := child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0, indices.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3.ZERO, CinemaEnvironment.SCREEN_POSITION,
				vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]])
			if hit != null:
				check(false, "Cinema geometry must not cover the projection from the viewing position.")
				return

func check_environment_switching() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	app.settings = FixtureSettings.new()
	root.add_child(app)
	check(not app.cinema.visible, "Void starts without cinema geometry.")
	app.api.token = "fixture"
	app.shell.set_signed_in(true)
	app._screen_settings()
	var view: SettingsView = app.page.get_child(0)
	var cinema_choice: CheckBox = view.environment_buttons["Cinema"]
	cinema_choice.button_pressed = true
	cinema_choice.pressed.emit()
	check(app.cinema.visible and app.settings.environment == "Cinema", "Selecting Cinema shows the cinema immediately.")
	var projection: Transform3D = app.cinema.projection_transform()
	check(app.screen.global_transform.is_equal_approx(projection), "The video must be mounted on the cinema's front screen.")
	check(app.screen.global_basis.y.is_equal_approx(Vector3.UP), "The mounted screen stays upright.")
	var movie_size: Vector3 = app.screen.mesh.get_aabb().size
	app.settings.width = 7.0
	app.settings.distance = 1.5
	app.settings.height = -2.0
	app.settings.curvature = 1.2
	app._position_screen()
	app._resize_screen()
	check(app.screen.global_transform.is_equal_approx(projection) and app.screen.mesh.get_aabb().size.is_equal_approx(movie_size), "Void screen adjustments must not move or resize the Cinema projection.")
	app.camera.position += Vector3(0.3, 0.1, 0.2)
	app.camera.rotation = Vector3(0.25, 0.4, 0.1)
	app._position_screen()
	check(app.screen.global_transform.is_equal_approx(projection), "Head movement must not move the mounted movie screen.")
	app._recenter()
	check(app.screen.global_transform.is_equal_approx(app.cinema.projection_transform()) and app.screen.global_basis.y.is_equal_approx(Vector3.UP), "Recenter keeps the movie attached to an upright cinema screen.")
	var slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(not slider.editable, "Void position controls are disabled in Cinema.")
	var low_res_choice: CheckBox = view.environment_buttons["Theatre"]
	low_res_choice.button_pressed = true
	low_res_choice.pressed.emit()
	check(app.cinema.low_res and app.cinema.low_resolution != null and app.cinema.interior == null, "Theatre shows the original cinema without instantiating the detailed interior.")
	check(app.screen.global_transform.is_equal_approx(app.cinema.projection_transform()), "Theatre mounts the video on its own screen.")
	check(app.cinema.global_basis.y.is_equal_approx(Vector3.UP), "Switching cinema quality preserves upright recentering.")
	check(app.cinema.video_size(16.0 / 9.0).x > CinemaEnvironment.SCREEN_SIZE.x, "Theatre preserves the original larger screen dimensions.")
	var part_count := 0
	var batch_count := 0
	for child in app.cinema.low_resolution.get_children():
		if child is MultiMeshInstance3D:
			part_count += child.multimesh.instance_count
			batch_count += 1
	check(part_count > 400 and batch_count < 40, "The original Theatre geometry retains its instanced seats and architecture.")
	app._recenter()
	check(app.screen.global_transform.is_equal_approx(app.cinema.projection_transform()), "Theatre recenter keeps the screen mounted.")
	slider = view.screen_dimensions.get_child(0).get_child(1)
	check(not slider.editable, "Theatre also disables floating screen adjustments.")
	cinema_choice.button_pressed = true
	cinema_choice.pressed.emit()
	check(not app.cinema.low_res and app.cinema.low_resolution == null and app.cinema.interior != null, "Switching back restores the detailed cinema and releases Theatre geometry.")
	var reset: Button = view.reset_screen_button
	reset.pressed.emit()
	check(app.cinema.visible and app.settings.environment == "Cinema", "Screen reset preserves the separate environment choice.")
	var void_choice: CheckBox = view.environment_buttons["Void"]
	void_choice.button_pressed = true
	void_choice.pressed.emit()
	check(not app.cinema.visible and app.settings.environment == "Void", "The Environment page can return to Void.")
	var floating_position: Vector3 = app.camera.global_position - app.screen.global_basis.z * 3.0 - app.screen.global_basis.y * 0.2
	check(app.screen.global_position.is_equal_approx(floating_position), "Void restores the default floating screen distance and lowered height reference.")
	app.queue_free()
	await process_frame
	await process_frame
	var low_res_app: Node = load("res://scenes/main.tscn").instantiate()
	low_res_app.settings = FixtureSettings.new()
	low_res_app.settings.environment = "Theatre"
	root.add_child(low_res_app)
	check(low_res_app.cinema.visible and low_res_app.cinema.low_res and low_res_app.cinema.interior == null, "Starting with saved Theatre uses only the original cinema geometry.")
	check(low_res_app.screen.global_transform.is_equal_approx(low_res_app.cinema.projection_transform()), "A saved Theatre selection starts with the video correctly mounted.")
	low_res_app.queue_free()
	await process_frame

func capture(cinema: CinemaEnvironment, screen: MeshInstance3D) -> void:
	root.size = Vector2i(1440, 900)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	root.add_child(camera)
	camera.current = true
	cinema.recenter(camera.global_transform)
	var dimensions := cinema.video_size(16.0 / 9.0)
	screen.mesh = Stereo.mesh(dimensions.x, 16.0 / 9.0, 0.0)
	screen.global_transform = cinema.projection_transform()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load("res://assets/logo/jellyxr-wordmark.png")
	material.albedo_color = Color("d5e1ef")
	screen.material_override = material
	screen.show()
	await snapshot("cinema-forward")
	camera.rotate_y(-0.9)
	await snapshot("cinema-side")
	camera.rotation.y = PI
	camera.rotation.x = -0.2
	await snapshot("cinema-seating")

func snapshot(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/" + filename + ".png")
