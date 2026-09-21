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
	app._update_timeline()
	assert(indicator.visible, "Buffering shows loading with controls hidden")
	backend.buffering = false
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
	app.queue_free()
	await process_frame
	print("Player loading checks: PASS")
	quit()
