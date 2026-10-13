extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.viewport.get_parent().hide()
	var image := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := Color.from_hsv(float(x) / 1024.0, 0.65, 0.9 - float(y) / 1024.0)
			if x % 128 < 3 or y % 128 < 3: color = Color.WHITE
			image.set_pixel(x, y, color)
	var grid_texture := ImageTexture.create_from_image(image)
	app.material.set_shader_parameter("video_texture", grid_texture)
	app.screen.show()
	app._select_projection(VideoProjection.Mode.EQUIRECTANGULAR)
	app._show_playback()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/360-preview.png")
	app.player_overlay.hide()
	image.fill_rect(Rect2i(0, 0, 1024, 256), Color.RED)
	image.fill_rect(Rect2i(0, 256, 1024, 256), Color.GREEN)
	app.material.set_shader_parameter("video_texture", ImageTexture.create_from_image(image))
	app._select_stereo(Stereo.Mode.TOP_BOTTOM)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var pixel := frame.get_pixel(frame.get_width() / 2, frame.get_height() / 2)
	if pixel.r < 0.8 or pixel.g > 0.2:
		push_error("Top-bottom left-eye rendering must sample the upper half")
		quit(1)
		return
	app.material.set_shader_parameter("swap_eyes", true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	frame = root.get_texture().get_image()
	pixel = frame.get_pixel(frame.get_width() / 2, frame.get_height() / 2)
	if pixel.g < 0.8 or pixel.r > 0.2:
		push_error("Swapped top-bottom rendering must sample the lower half")
		quit(1)
		return
	if not await check_180_rendering(app, grid_texture): return
	app._screen_settings()
	app.viewport.get_parent().show()
	var settings: SettingsView = app.page.get_child(0)
	var screen_tab: Button = settings.get_child(0).get_child(1)
	screen_tab.button_pressed = true
	screen_tab.pressed.emit()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	app.viewport.get_texture().get_image().save_png("res://dist/180-settings-preview.png")
	print("180 and 360 rendering checks: PASS")
	app.queue_free()
	await process_frame
	quit()

func check_180_rendering(app: Node, texture: Texture2D) -> bool:
	app._select_stereo(Stereo.Mode.MONO)
	app.material.set_shader_parameter("swap_eyes", false)
	app.material.set_shader_parameter("video_texture", texture)
	app._select_projection(VideoProjection.Mode.EQUIRECTANGULAR_180)
	app._show_playback()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/180-preview.png")
	app.player_overlay.hide()
	app.camera.rotate_y(PI)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var pixel := frame.get_pixel(frame.get_width() / 2, frame.get_height() / 2)
	if pixel.r > 0.05 or pixel.g > 0.05 or pixel.b > 0.05:
		push_error("The view behind a 180 video must stay dark")
		quit(1)
		return false
	app.camera.rotate_y(-PI)
	return true
