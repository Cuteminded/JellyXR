extends SceneTree

var decoder: Node
var ready_count := 0
var ended_count := 0
var errors: Array[String] = []
var texture: Texture2D
var screen: SubViewport
var dimensions := Vector2i.ZERO
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func wait_until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func run_checks() -> void:
	if not ClassDB.class_exists("JellyXRMpv"):
		push_error("Build the PC video plugin before running this test.")
		quit(1)
		return
	var backend := PcVideo.new()
	root.add_child(backend)
	check(not backend.available(), "Desktop preview must not enable playback")
	check(not backend.has_android_services(), "PC playback must not call Android session services")
	backend.queue_free()
	decoder = ClassDB.instantiate("JellyXRMpv")
	root.add_child(decoder)
	if DisplayServer.get_name() != "headless":
		screen = preload("res://tests/pc_video_test_screen.gd").new(decoder, Vector2i(1920, 1080))
		root.add_child(screen)
	decoder.prepared.connect(func(): ready_count += 1)
	decoder.ended.connect(func(): ended_count += 1)
	decoder.failed.connect(func(message: String): errors.append(message))
	decoder.size_changed.connect(func(w: int, h: int): dimensions = Vector2i(w, h))
	decoder.texture_changed.connect(func(value: Texture2D): texture = value)
	var url := ProjectSettings.globalize_path("res://tests/fixtures/stereo_test.mp4")
	var authorization := ""
	var expected_renderer := "software" if DisplayServer.get_name() == "headless" or OS.get_environment("JELLYXR_PC_RENDERER") == "software" else "opengl"
	if expected_renderer != "software" and RenderingServer.get_current_rendering_driver_name() == "vulkan":
		expected_renderer = "vulkan"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video="): url = argument.trim_prefix("--video=")
		if argument.begins_with("--auth="): authorization = argument.trim_prefix("--auth=")
		if argument.begins_with("--expect-renderer="): expected_renderer = argument.trim_prefix("--expect-renderer=")
	var open_error: String = decoder.open_video(url, authorization, 1000)
	check(open_error.is_empty(), "The decoder opens a video: " + open_error)
	if not open_error.is_empty():
		decoder.queue_free()
		quit(1)
		return
	var received_frame := await wait_until(func(): return (ready_count == 1 and texture != null) or not errors.is_empty())
	check(received_frame and texture != null, "A decoded frame reaches Godot: %s, prepared=%d" % [str(errors), ready_count])
	if texture == null:
		decoder.stop_video()
		decoder.queue_free()
		quit(1)
		return
	check(dimensions == Vector2i(1920, 1080), "Decoded video dimensions reach the screen")
	check(decoder.rendering_backend() == expected_renderer, "The expected rendering backend is active")
	check(await wait_until(func(): return decoder.position_ms() > 1400), "Playback resumes and advances")
	check(decoder.duration_ms() > 2000, "Duration is available for seeking")
	if texture != null and DisplayServer.get_name() != "headless":
		var image: Image = screen.image()
		check(not image.is_empty(), "The decoder uploads a readable texture")
		if not image.is_empty():
			check(image.get_pixel(240, 300).get_luminance() > 0.7, "The left stereo frame reaches the texture")
			check(image.get_pixel(1200, 300).get_luminance() > 0.7, "The right stereo frame reaches the texture")
			check(image.get_pixel(380, 500).get_luminance() > 0.7, "The video keeps its source orientation")
	decoder.set_paused(true)
	await create_timer(0.4).timeout
	var paused_at: int = decoder.position_ms()
	await create_timer(0.4).timeout
	check(absi(decoder.position_ms() - paused_at) < 100, "Pause stops the clock")
	decoder.seek_to(3000)
	check(decoder.is_buffering(), "Native seeking shows buffering while playback restarts")
	check(await wait_until(func(): return absi(decoder.position_ms() - 3000) < 250), "Seeking works while paused")
	check(await wait_until(func(): return not decoder.is_buffering()), "Seek completion clears the loading state")
	decoder.set_paused(false)
	check(await wait_until(func(): return decoder.position_ms() > 3400), "Playback continues after seeking")
	decoder.seek_to(decoder.duration_ms() - 500)
	check(await wait_until(func(): return ended_count == 1), "Natural completion emits ended")
	check(errors.is_empty(), "Valid playback has no errors: " + str(errors))
	check(decoder.open_video(url, authorization, 0).is_empty(), "The decoder can reopen after completion")
	check(await wait_until(func(): return ready_count == 2), "Reopened playback prepares")
	decoder.stop_video()
	check(decoder.rendering_backend() == "none", "Stopping releases the rendering backend")
	check(not decoder.is_buffering(), "Stopping clears native buffering and seeking state")
	await create_timer(0.2).timeout
	check(ended_count == 1, "Stopping does not trigger episode autoplay")
	check(decoder.open_video(ProjectSettings.globalize_path("res://build/desktop/missing.mp4"), "", 0).is_empty(), "Invalid files report asynchronous errors")
	check(await wait_until(func(): return not errors.is_empty()), "Decoder errors reach the transcode fallback")
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	print("PC video checks: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
