extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var desktop_container: Node = app.viewport.get_parent()
	app.viewport.reparent(app)
	desktop_container.hide()
	app.settings.distance = 1.5
	app.settings.curvature = 1.2
	app._position_screen()
	app._resize_screen()
	app.screen.show()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("876143")
	app.screen.material_override = material
	app._screen_settings()
	app.panel.show()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/menu-depth-preview.png")
	quit()
