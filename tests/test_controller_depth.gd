extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Controller depth checks require a rendering window.")
		quit(1)
		return
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	var view := SubViewport.new()
	view.size = Vector2i(64, 64)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(Camera3D.new())
	var room := MeshInstance3D.new()
	room.mesh = QuadMesh.new()
	room.position.z = -0.4
	var blue := StandardMaterial3D.new()
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blue.albedo_color = Color.BLUE
	room.material_override = blue
	view.add_child(room)
	var panel := MeshInstance3D.new()
	panel.mesh = QuadMesh.new()
	panel.position.z = -2.0
	view.add_child(panel)
	var controller := MeshInstance3D.new()
	controller.mesh = BoxMesh.new()
	controller.scale = Vector3.ONE * 0.2
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	controller.mesh.material = red
	app.world._prepare_controller_model(controller)
	view.add_child(controller)
	var panels := [app.world.panel, app.world.player_loading, app.player_overlay]
	for source in panels:
		var material: StandardMaterial3D = source.material_override.duplicate()
		material.albedo_texture = null
		material.albedo_color = Color.GREEN
		panel.material_override = material
		for room_visible in [false, true]:
			room.visible = room_visible
			for depth in [-1.0, -3.0]:
				controller.position.z = depth
				await process_frame
				await RenderingServer.frame_post_draw
				var pixels := view.get_texture().get_image()
				var center := pixels.get_pixel(32, 32)
				var expected := Color.RED if depth == -1.0 else Color.GREEN
				check(center.is_equal_approx(expected), "Controller depth is preserved with room visibility %s at %s: %s" % [room_visible, depth, center])
				check(pixels.get_pixel(23, 32).is_equal_approx(Color.GREEN), "The menu draws over closer room geometry")
				if room_visible:
					check(pixels.get_pixel(1, 1).is_equal_approx(Color.BLUE), "Room geometry outside the menu remains visible")
	app.queue_free()
	view.queue_free()
	await process_frame
	print("Rendered controller depth checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
