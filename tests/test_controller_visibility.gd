extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	var world: ViewingWorld = app.world
	check_controller_materials(world)
	var origin := world.camera.get_parent()
	var pointer := LaserPointer.new()
	pointer.panel = world.panel
	pointer.viewport = world.viewport
	origin.add_child(pointer)
	world.pointers.append(pointer)
	assert(ProjectSettings.get_setting("xr/openxr/extensions/render_model"), "OpenXR render models are enabled")
	world._process(0.0)
	assert(pointer.visible, "Controllers are visible in the library")
	app.playing = true
	app.screen.show()
	app._show_playback()
	app._video_prepared()
	app._player_action("hide")
	world._process(0.0)
	assert(not pointer.visible, "Video without menus hides the laser pointer")
	assert(pointer.is_processing(), "Hidden controllers keep processing input")
	app._show_playback()
	world._process(0.0)
	assert(pointer.visible, "Opening playback controls restores controllers")
	app._screen_settings()
	world.panel.show()
	world._process(0.0)
	assert(pointer.visible, "Settings keep controllers visible during playback")
	app._show_playback()
	app._player_action("hide")
	world.player_loading.show_buffering()
	world._process(0.0)
	assert(not pointer.visible, "Buffering without buttons keeps controllers hidden")
	world.player_loading.show_countdown("Next episode", 5)
	world._process(0.0)
	assert(pointer.visible, "Autoplay cancellation keeps controllers visible")
	world.player_loading.hide()
	world.set_panoramic(true)
	world._process(0.0)
	assert(not pointer.visible, "Panoramic playback also hides controllers")
	app.playing = false
	app.screen.hide()
	world._process(0.0)
	assert(pointer.visible, "Stopping playback restores controllers")
	app.queue_free()
	await process_frame
	print("Controller visibility checks: PASS")
	quit()

func check_controller_materials(world: ViewingWorld) -> void:
	var model := Node3D.new()
	var component := Node3D.new()
	model.add_child(component)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var source := StandardMaterial3D.new()
	source.albedo_color = Color("b7c4d6")
	source.albedo_texture = GradientTexture2D.new()
	source.metallic = 0.5
	mesh.mesh.material = source
	component.add_child(mesh)
	world._prepare_controller_model(model)
	var result := mesh.get_active_material(0) as BaseMaterial3D
	assert(result.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Nested controller meshes do not require scene lighting")
	assert(result.albedo_color == source.albedo_color and result.albedo_texture == source.albedo_texture, "Controller colors and textures are preserved")
	assert(result.metallic == source.metallic, "Other controller material properties are preserved")
	assert(result.use_z_clip_scale and is_equal_approx(result.z_clip_scale, VrOverlayMaterial.DEPTH_SCALE), "Controllers share the menu depth range")
	assert(source.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Shared source materials remain unchanged")
	model.free()
