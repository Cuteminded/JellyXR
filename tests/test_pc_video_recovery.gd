extends SceneTree

var decoder: Node
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run_check")

func run_check() -> void:
	var url := ""
	var expect_buffer_free := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video="): url = argument.trim_prefix("--video=")
		if argument == "--expect-buffer-free": expect_buffer_free = true
	OS.low_processor_usage_mode = false
	Engine.max_fps = 120
	decoder = ClassDB.instantiate("JellyframeMpv")
	root.add_child(decoder)
	decoder.failed.connect(func(value: String): errors.append(value))
	var error: String = decoder.open_video(url, "", 0)
	if not error.is_empty(): errors.append(error)
	if expect_buffer_free:
		await check_read_ahead()
		return
	var deadline := Time.get_ticks_msec() + 24000
	var held_position := -1
	var held_since := 0
	var audio_held := false
	var recovered := false
	var paused_during_buffering := false
	while errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
		var stats: Dictionary = decoder.playback_diagnostics()
		if stats.get("renderer") != "vulkan":
			errors.append("Vulkan playback fell back")
			break
		var position: int = decoder.position_ms()
		if stats.get("video_buffering", false) and position > 1500:
			if held_position < 0:
				held_position = position
				held_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - held_since > 500:
				audio_held = position - held_position < 200
				if not paused_during_buffering:
					decoder.set_paused(true)
					paused_during_buffering = true
		elif audio_held and paused_during_buffering:
			var paused_at: int = decoder.position_ms()
			await create_timer(0.3).timeout
			if abs(decoder.position_ms() - paused_at) > 100:
				errors.append("Recovery overrode the user's pause")
			decoder.set_paused(false)
			await create_timer(1.0).timeout
			stats = decoder.playback_diagnostics()
			recovered = decoder.position_ms() > paused_at + 500 and abs(int(stats.get("video_position_ms", -10000)) - decoder.position_ms()) < 200
			break
	var final_stats: Dictionary = decoder.playback_diagnostics()
	print("Video recovery: ", JSON.stringify(final_stats), " audio_held=", audio_held, " recovered=", recovered)
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	if not errors.is_empty(): push_error(str(errors))
	quit(0 if audio_held and recovered and errors.is_empty() else 1)

func check_read_ahead() -> void:
	var deadline := Time.get_ticks_msec() + 24000
	var buffer_count := -1
	var previous_count := 0
	var previous_frame := Time.get_ticks_msec()
	var maximum_gap := 0
	while errors.is_empty() and decoder.position_ms() < 12000 and Time.get_ticks_msec() < deadline:
		await process_frame
		var stats: Dictionary = decoder.playback_diagnostics()
		if stats.get("renderer") != "vulkan":
			errors.append("Vulkan playback fell back")
			break
		if decoder.position_ms() < 2000:
			previous_frame = Time.get_ticks_msec()
			continue
		if buffer_count < 0: buffer_count = stats.get("video_buffer_count", 0)
		if stats.get("video_buffer_count", 0) > buffer_count:
			errors.append("Read-ahead did not absorb the delivery interruption")
			break
		var count: int = stats.get("presented_frames", 0)
		if count != previous_count:
			maximum_gap = maxi(maximum_gap, Time.get_ticks_msec() - previous_frame)
			previous_frame = Time.get_ticks_msec()
			previous_count = count
	var passed: bool = errors.is_empty() and decoder.position_ms() >= 12000 and maximum_gap < 300
	print("Video read-ahead: ", JSON.stringify(decoder.playback_diagnostics()), " maximum_gap_ms=", maximum_gap, " errors=", errors)
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	quit(0 if passed else 1)
