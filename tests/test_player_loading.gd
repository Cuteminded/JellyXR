extends SceneTree

class BufferingVideo extends VideoBackend:
	var buffering := false

	func is_buffering() -> bool:
		return buffering

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.video.queue_free()
	var backend := BufferingVideo.new()
	app.add_child(backend)
	app.video = backend
	var indicator: PlayerLoading = app.world.player_loading
	assert(not indicator.visible, "Loading is hidden before playback")
	app.playing = true
	app.screen.show()
	app._show_playback()
	assert(indicator.is_visible_in_tree(), "Loading appears while the decoder prepares")
	app.player_overlay.hide()
	assert(indicator.is_visible_in_tree(), "Hiding controls keeps loading visible")
	app._video_prepared()
	assert(not indicator.visible, "Prepared playback hides loading")
	backend.buffering = true
	app._process(0.01)
	assert(indicator.visible, "Buffering shows loading with controls hidden")
	assert(indicator.label.text == "Buffering video...", "Buffering identifies why playback is waiting")
	assert(indicator.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "The visible popup renders independently of video frames")
	var popup_material: StandardMaterial3D = indicator.material_override
	assert(popup_material.no_depth_test and popup_material.render_priority > 0, "The loading popup draws over video and playback controls")
	app.screen.hide()
	assert(indicator.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hiding the video also stops popup rendering")
	app.screen.show()
	assert(indicator.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Showing the video restores popup rendering")
	backend.buffering = false
	app._process(0.01)
	assert(not indicator.visible, "Playback resuming hides the popup before the next timeline update")
	assert(indicator.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden loading popups stop rendering")
	backend.paused = true
	app._update_timeline()
	assert(not indicator.visible, "Pausing alone does not show loading")
	app.seeking = true
	app._update_timeline()
	assert(indicator.visible, "Transcoded seeks show loading")
	app._error("Test playback error")
	assert(not indicator.visible, "Errors clear loading")
	app.playing = true
	app.screen.show()
	app._update_timeline()
	await app._stop(false)
	assert(not indicator.visible, "Stopping clears loading")
	if "--capture" in OS.get_cmdline_user_args():
		app.screen.show()
		indicator.show()
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		indicator.viewport.get_texture().get_image().save_png("res://dist/player-loading-preview.png")
		indicator.show_buffering()
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		indicator.viewport.get_texture().get_image().save_png("res://dist/player-buffering-preview.png")
		indicator.show_countdown("S02 E03 The next episode", 5)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		indicator.viewport.get_texture().get_image().save_png("res://dist/episode-countdown-preview.png")
	app.queue_free()
	await process_frame
	print("Player loading checks: PASS")
	quit()
