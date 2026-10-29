extends SceneTree

func _initialize() -> void:
	call_deferred("run_check")

func run_check() -> void:
	if RenderingServer.get_current_rendering_driver_name() != "vulkan":
		push_error("This check requires the Vulkan playback path.")
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Provide a sample with audio at zero and its first video frame after 30 ms.")
		quit(1)
		return
	var decoder: Node = ClassDB.instantiate("JellyXRMpv")
	root.add_child(decoder)
	var failures: Array[String] = []
	var textures: Array[Texture2D] = []
	decoder.failed.connect(func(message: String): failures.append(message))
	decoder.texture_changed.connect(func(value: Texture2D):
		if value != null: textures.append(value))
	var error: String = decoder.open_video(arguments[0], "", 0)
	if not error.is_empty(): failures.append(error)
	var deadline := Time.get_ticks_msec() + 5000
	while textures.is_empty() and failures.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	var stats: Dictionary = decoder.playback_diagnostics()
	var passed: bool = failures.is_empty() and not textures.is_empty() and stats.get("renderer") == "vulkan"
	if passed:
		await create_timer(1.0).timeout
		passed = decoder.position_ms() > 500
		decoder.set_paused(true)
		var before: int = decoder.playback_diagnostics().get("presented_frames", 0)
		decoder.seek_to(0)
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline:
			var after: Dictionary = decoder.playback_diagnostics()
			if int(after.get("presented_frames", 0)) > before and not decoder.is_buffering(): break
			await process_frame
		passed = passed and int(decoder.playback_diagnostics().get("presented_frames", 0)) > before
		passed = passed and not decoder.is_buffering() and failures.is_empty()
	else:
		push_error("First video frame did not reach presentation: " + JSON.stringify(stats) + " " + str(failures))
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	print("Delayed first video frame: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
