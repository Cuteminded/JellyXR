extends SceneTree

var decoder: Node
var texture: Texture2D
var preview: TextureRect
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run_check")

func run_check() -> void:
	var url := "res://build/gpu-worker/8k-av1-test.mp4"
	var seconds := 5.0
	var minimum_fps := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video="): url = argument.trim_prefix("--video=")
		if argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		if argument.begins_with("--minimum-fps="): minimum_fps = float(argument.trim_prefix("--minimum-fps="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 120
	decoder = ClassDB.instantiate("JellyframeMpv")
	root.add_child(decoder)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(640, 360)
	root.add_child(preview)
	decoder.texture_changed.connect(func(value: Texture2D): texture = value; preview.texture = value)
	decoder.failed.connect(func(value: String): errors.append(value))
	var error: String = decoder.open_video(ProjectSettings.globalize_path(url), "", 0)
	if not error.is_empty(): errors.append(error)
	var deadline := Time.get_ticks_msec() + 15000
	while texture == null and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if texture == null or not errors.is_empty():
		push_error("Video did not start: " + str(errors))
		decoder.stop_video()
		quit(1)
		return
	var before: Dictionary = decoder.playback_diagnostics()
	await create_timer(1.0).timeout
	before = decoder.playback_diagnostics()
	var started := Time.get_ticks_usec()
	var intervals: Array[float] = []
	var video_intervals: Array[float] = []
	var previous_video := started
	var previous_count: int = before.get("presented_frames", 0)
	var previous := started
	while Time.get_ticks_usec() - started < seconds * 1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		var count: int = decoder.playback_diagnostics().get("presented_frames", 0)
		if count != previous_count:
			video_intervals.append(float(now - previous_video) / 1000.0)
			previous_video = now
			previous_count = count
		previous = now
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var stats: Dictionary = decoder.playback_diagnostics()
	stats["presented_fps"] = float(int(stats.get("presented_frames", 0)) - int(before.get("presented_frames", 0))) / elapsed
	stats["dropped_during_sample"] = int(stats.get("dropped_frames", 0)) - int(before.get("dropped_frames", 0))
	intervals.sort()
	stats["frame_p95_ms"] = intervals[int(intervals.size() * 0.95)]
	stats["frame_max_ms"] = intervals.back()
	video_intervals.sort()
	stats["video_gap_p95_ms"] = video_intervals[int(video_intervals.size() * 0.95)] if not video_intervals.is_empty() else 0
	stats["window_focused"] = DisplayServer.window_is_focused()
	print("Video performance: ", JSON.stringify(stats))
	var passed: bool = errors.is_empty() and stats.get("renderer") == "vulkan" and float(stats["presented_fps"]) >= minimum_fps
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	quit(0 if passed else 1)
