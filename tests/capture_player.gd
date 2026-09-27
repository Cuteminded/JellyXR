extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.viewport.get_parent().hide()
	app.session.item = {"Name": "The long way home"}
	app._show_playback()
	app.screen.show()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("16334b"), Color("bf9874")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	material.albedo_texture = texture
	app.screen.material_override = material
	app.player_overlay.update_time(1425000, 6780000, true, true)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/player-preview.png")
	app.player_overlay._show_tooltip(app.player_overlay.pause_button)
	await RenderingServer.frame_post_draw
	app.player_overlay.viewport.get_texture().get_image().save_png("res://dist/player-controls-preview.png")
	quit()
