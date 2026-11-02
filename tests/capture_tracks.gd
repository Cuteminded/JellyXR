extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.playing = true
	app.decoder_ready = true
	app.session.item = {"Id": "fixture", "Name": "Example movie"}
	app.session.source = {"DefaultAudioStreamIndex": 1, "MediaStreams": [
		{"Type": "Audio", "Index": 1, "DisplayTitle": "English - AAC - Stereo"},
		{"Type": "Audio", "Index": 2, "DisplayTitle": "Dutch - AC3 - 5.1"},
		{"Type": "Subtitle", "Index": 3, "DisplayTitle": "English - SDH - SRT", "Codec": "srt"},
		{"Type": "Subtitle", "Index": 4, "DisplayTitle": "Dutch - PGS", "Codec": "pgssub"}
	]}
	app._show_tracks()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	app.player_overlay.viewport.get_texture().get_image().save_png("res://dist/quick-subtitles-preview.png")
	app.player_overlay.show_menu("audio")
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	app.player_overlay.viewport.get_texture().get_image().save_png("res://dist/quick-audio-preview.png")
	app.api.token = "preview-only"
	app.shell.signed_in = true
	app._screen_settings()
	var view: SettingsView = app.page.get_child(0)
	view._show_section(4)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	app.viewport.get_texture().get_image().save_png("res://dist/subtitle-settings-preview.png")
	app.panel.hide()
	app.viewport.get_parent().hide()
	app.screen.show()
	app.subtitle_overlay.text = "English subtitles in VR\nSize, color and timing can be adjusted."
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/subtitle-overlay-preview.png")
	var preferred_y: float = app.subtitle_overlay.position.y
	app.player_overlay.show()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var subtitle_bottom: float = app.subtitle_overlay.position.y + app.subtitle_overlay.get_aabb().position.y
	var controls_top: float = app.player_overlay.position.y + app.player_overlay.panel_size.y / 2.0
	assert(subtitle_bottom > controls_top, "Multiline subtitles stay above the visible player controls")
	root.get_texture().get_image().save_png("res://dist/subtitle-controls-preview.png")
	var controls_y: float = app.subtitle_overlay.position.y
	app.player_overlay.show_menu("subtitles")
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	assert(is_equal_approx(app.subtitle_overlay.position.y, controls_y), "Opening a submenu does not move subtitles above the panel")
	var player_material := app.player_overlay.material_override as StandardMaterial3D
	assert(app.subtitle_overlay.render_priority < player_material.render_priority, "Subtitles draw behind player menus")
	root.get_texture().get_image().save_png("res://dist/subtitle-menu-overlay-preview.png")
	app.player_overlay.close_menu()

	app.settings.subtitle_size = 80
	app.settings.curvature = 1.2
	app._resize_screen()
	app.subtitle_overlay.text = "Large subtitles\nwith three lines\nstay above the controls."
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	subtitle_bottom = app.subtitle_overlay.position.y + app.subtitle_overlay.get_aabb().position.y
	controls_top = app.player_overlay.position.y + app.player_overlay.panel_size.y / 2.0
	assert(subtitle_bottom > controls_top, "Large multiline subtitles also clear controls on a curved screen")
	app.player_overlay.hide()
	await process_frame
	await process_frame
	assert(is_equal_approx(app.subtitle_overlay.position.y, preferred_y), "Hiding controls restores the chosen subtitle position")
	print("Subtitle controls layout checks: PASS")
	app.playing = false
	app.queue_free()
	await process_frame
	quit()
