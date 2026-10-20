extends SceneTree

var decoder: Node
var texture: Texture2D
var errors: Array[String] = []
var ended := false

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

func wait_for_frame() -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while (texture == null or decoder.is_buffering()) and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.15).timeout
	return require(texture != null and errors.is_empty(), "Vulkan produces a frame: " + str(errors))

func check_color(expected: Color) -> bool:
	var image := texture.get_image()
	var actual := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	return require(absf(actual.r - expected.r) < 0.04 and absf(actual.g - expected.g) < 0.04 and absf(actual.b - expected.b) < 0.04 and actual.a > 0.99,
		"The Vulkan shader converts the expected color: %s, got %s" % [str(expected), str(actual)])

func run_check() -> void:
	if not require(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_driver_name() == "vulkan", "This test requires Vulkan"):
		return
	var url := "res://build/desktop/vulkan-colors.mkv"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video="):
			url = argument.trim_prefix("--video=")
	decoder = ClassDB.instantiate("JellyframeMpv")
	root.add_child(decoder)
	decoder.texture_changed.connect(func(value: Texture2D): texture = value)
	decoder.failed.connect(func(message: String): errors.append(message))
	decoder.ended.connect(func(): ended = true)
	if not require(decoder.open_video(ProjectSettings.globalize_path(url), "", 0).is_empty(), "Open the ten-bit color fixture"):
		return
	if not await wait_for_frame():
		return
	decoder.set_paused(true)
	if not require(decoder.rendering_backend() == "vulkan", "Color conversion stays on Vulkan") or not check_color(Color.RED):
		return
	for sample in [[2250, Color.GREEN], [4250, Color.BLUE], [250, Color.RED]]:
		decoder.seek_to(sample[0])
		if not await wait_for_frame() or not check_color(sample[1]):
			return
	decoder.seek_to(5500)
	if not await wait_for_frame():
		return
	decoder.set_paused(false)
	var deadline := Time.get_ticks_msec() + 3000
	while not ended and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not require(ended and errors.is_empty(), "Silent video completes after seeking"):
		return
	decoder.stop_video()
	decoder.queue_free()
	await process_frame
	print("Vulkan ten-bit color and seek checks: PASS")
	quit()
