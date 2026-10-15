extends SceneTree

var decoder: Node
var preview: TextureRect
var video_texture: Texture2D
var errors: Array[String] = []
var frame_times: Array[float] = []

func _initialize() -> void:
	call_deferred("run_check")

func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	if decoder != null:
		decoder.stop_video()
	quit(1)
	return false

func check_controls_and_reopen(url: String) -> bool:
	decoder.set_paused(true)
	await create_timer(0.2).timeout
	var paused_at: int = decoder.position_ms()
	await create_timer(0.2).timeout
	if not require(absi(decoder.position_ms() - paused_at) < 100, "Pause stops high-resolution playback"):
		return false
	decoder.seek_to(1000)
	var deadline := Time.get_ticks_msec() + 5000
	while decoder.is_buffering() and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not require(absi(decoder.position_ms() - 1000) < 250, "Seek works while high-resolution playback is paused"):
		return false
	decoder.set_paused(false)
	await create_timer(0.5).timeout
	if not require(decoder.position_ms() > 1200, "High-resolution playback resumes after seeking"):
		return false
	decoder.stop_video()
	video_texture = null
	if not require(decoder.open_video(url, "", 0).is_empty(), "Reopen with a different resolution"):
		return false
	deadline = Time.get_ticks_msec() + 10000
	while video_texture == null and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return require(video_texture != null and video_texture.get_size() == Vector2(1920, 1080) and errors.is_empty(), "Reopening replaces high-resolution GPU buffers")

func run_check() -> void:
	var url := ProjectSettings.globalize_path("res://native/android/src/main/res/raw/stereo_test.mp4")
	var reopen_url := url
	var expected_size := Vector2i(1920, 1080)
	var minimum_fps := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video="):
			url = argument.trim_prefix("--video=")
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			expected_size = Vector2i(int(parts[0]), int(parts[1]))
		if argument.begins_with("--min-fps="):
			minimum_fps = float(argument.trim_prefix("--min-fps="))
		if argument.begins_with("--reopen-video="):
			reopen_url = argument.trim_prefix("--reopen-video=")
	if not require(DisplayServer.get_name() != "headless", "GPU checks require a graphics context"):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	decoder = ClassDB.instantiate("JellyframeMpv")
	root.add_child(decoder)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(640, 360)
	root.add_child(preview)
	decoder.texture_changed.connect(func(value: Texture2D): video_texture = value; preview.texture = value)
	decoder.failed.connect(func(message: String): errors.append(message))
	if not require(decoder.open_video(url, "", 0).is_empty(), "Open the GPU test video"):
		return
	var deadline := Time.get_ticks_msec() + 15000
	while video_texture == null and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not require(video_texture != null and errors.is_empty(), "GPU produces a frame: " + str(errors)):
		return
	if not require(video_texture.get_size() == Vector2(expected_size), "GPU rendering preserves the source resolution"):
		return
	await create_timer(0.5).timeout
	var before: Dictionary = decoder.playback_diagnostics()
	var last_frame := Time.get_ticks_usec()
	var started := last_frame
	while Time.get_ticks_usec() - started < 3000000 and errors.is_empty():
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last_frame) / 1000.0)
		last_frame = now
	var statistics: Dictionary = decoder.playback_diagnostics()
	statistics["sample_uploaded_fps"] = float(statistics.uploaded_frames - before.uploaded_frames) * 1000000.0 / float(last_frame - started)
	for counter in ["frame-drop-count", "decoder-frame-drop-count"]:
		if before.get(counter) != null and statistics.get(counter) != null:
			statistics["sample_" + counter] = statistics[counter] - before[counter]
	frame_times.sort()
	statistics["godot_frame_p95_ms"] = frame_times[mini(frame_times.size() - 1, int(frame_times.size() * 0.95))]
	print("GPU playback statistics: ", JSON.stringify(statistics))
	if not require(errors.is_empty() and statistics.render_backend == "opengl", "The GPU backend stays active during playback"):
		return
	if not require(statistics.cpu_rgba_bytes == 0 and statistics.upload_cpu_ms == 0, "GPU playback avoids CPU RGBA staging and image uploads"):
		return
	var image := video_texture.get_image()
	if not require(image != null and image.get_size() == expected_size, "Read the full-resolution GPU result"):
		return
	if not require(statistics.uploaded_frames > before.uploaded_frames, "Video frames continue reaching Godot"):
		return
	if not require(float(statistics.sample_uploaded_fps) >= minimum_fps, "Video meets the requested delivered frame rate"):
		return
	var screen_image := root.get_texture().get_image()
	var brightest := 0.0
	for y in range(1, 16):
		for x in range(1, 16):
			var sample := screen_image.get_pixel(screen_image.get_width() * x / 16, screen_image.get_height() * y / 16)
			brightest = maxf(brightest, sample.get_luminance())
	if not require(brightest > 0.5, "Godot draws the video after GPU presentation"):
		return
	if not await check_controls_and_reopen(reopen_url):
		return
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	print("PC GPU video checks: PASS")
	quit()
