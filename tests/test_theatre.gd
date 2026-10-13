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
	for child in theatre.interior.get_children():
		if child is MeshInstance3D:
			batches += 1
			instances += child.mesh.surface_get_array_index_len(0) / 3
	check(instances > 390000 and batches <= 8, "The imported cinema retains its geometry in at most eight material batches.")
	check(theatre.interior.get_child(0).mesh.get_aabb().size.x < 6.0, "The cinema must be converted from millimetres to metres.")
	check_projection_visibility(theatre)
	check_seated_height(theatre)
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
			check(TheatreEnvironment.FLOOR < point.y, "The front floor must stay below every screen corner.")
	screen.hide()
	check(theatre.screen_frame.visible, "The physical cinema screen remains visible between videos.")
	await check_environment_switching()
	if "--capture" in OS.get_cmdline_user_args():
		await capture(theatre, screen)
	print("Theatre failures: ", failures, "; batches: ", batches, "; instances: ", instances)
	quit(1 if failures else 0)

func check_seated_height(theatre: TheatreEnvironment) -> void:
	var cushion: MeshInstance3D = theatre.interior.get_node("color_brown")
	var arrays := cushion.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cushion_distance := INF
	for triangle in range(0, indices.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3.ZERO, Vector3(0, -2.0, 0),
			vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]])
		if hit != null: cushion_distance = minf(cushion_distance, -hit.y)
	check(cushion_distance > 0.65 and cushion_distance < 0.85, "The viewer must sit above a real seat cushion at seated eye height.")

func check_projection_visibility(theatre: TheatreEnvironment) -> void:
	for child: MeshInstance3D in theatre.interior.get_children():
		var arrays := child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0, indices.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3.ZERO, TheatreEnvironment.SCREEN_POSITION,
				vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]])
			if hit != null:
				check(false, "Cinema geometry must not cover the projection from the viewing position.")
				return

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
	check(app.theatre.visible and app.settings.environment == "Cinema", "Selecting Theatre shows the cinema immediately.")
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
	var low_res_choice: CheckBox = view.sections[2].get_child(2).get_child(2)
	low_res_choice.button_pressed = true
	low_res_choice.pressed.emit()
	check(app.theatre.low_res and app.theatre.low_resolution != null and app.theatre.interior == null, "LowRes shows the original theatre without instantiating the detailed interior.")
	check(app.screen.global_transform.is_equal_approx(app.theatre.projection_transform()), "LowRes mounts the video on its own screen.")
	check(app.theatre.global_basis.y.is_equal_approx(Vector3.UP), "Switching theatre quality preserves upright recentering.")
	check(app.theatre.video_size(16.0 / 9.0).x > TheatreEnvironment.SCREEN_SIZE.x, "LowRes preserves the original larger screen dimensions.")
	var part_count := 0
	var batch_count := 0
	for child in app.theatre.low_resolution.get_children():
		if child is MultiMeshInstance3D:
			part_count += child.multimesh.instance_count
			batch_count += 1
	check(part_count > 400 and batch_count < 40, "The original LowRes geometry retains its instanced seats and architecture.")
	app._recenter()
	check(app.screen.global_transform.is_equal_approx(app.theatre.projection_transform()), "LowRes recenter keeps the screen mounted.")
	slider = view.screen_dimensions.get_child(0).get_child(1)
	check(not slider.editable, "LowRes also disables floating screen adjustments.")
	theatre_choice.button_pressed = true
	theatre_choice.pressed.emit()
	check(not app.theatre.low_res and app.theatre.low_resolution == null and app.theatre.interior != null, "Switching back restores the detailed theatre and releases LowRes geometry.")
	var reset: Button = view.reset_screen_button
	reset.pressed.emit()
	check(app.theatre.visible and app.settings.environment == "Cinema", "Screen reset preserves the separate environment choice.")
	var void_choice: CheckBox = view.sections[2].get_child(2).get_child(0)
	void_choice.button_pressed = true
	void_choice.pressed.emit()
	check(not app.theatre.visible and app.settings.environment == "Void", "The Environment page can return to Void.")
	check(is_equal_approx(app.screen.global_position.distance_to(app.camera.global_position), 3.0), "Void restores the saved floating screen distance.")
	app.queue_free()
	await process_frame
	await process_frame
	var low_res_app: Node = load("res://scenes/main.tscn").instantiate()
	low_res_app.settings = FixtureSettings.new()
	low_res_app.settings.environment = "Theatre"
	root.add_child(low_res_app)
	check(low_res_app.theatre.visible and low_res_app.theatre.low_res and low_res_app.theatre.interior == null, "Starting with saved LowRes uses only the original theatre geometry.")
	check(low_res_app.screen.global_transform.is_equal_approx(low_res_app.theatre.projection_transform()), "A saved LowRes selection starts with the video correctly mounted.")
	low_res_app.queue_free()
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
