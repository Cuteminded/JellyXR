extends SceneTree

var screen: SubViewport
var material: ShaderMaterial
var failures := 0
const COLORS = [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE]

func _initialize() -> void:
	call_deferred("run_checks")

func make_planes(interleaved: bool) -> void:
	var y_plane := Image.create(12, 8, false, Image.FORMAT_R8)
	var u_plane := Image.create(6, 4, false, Image.FORMAT_RG8 if interleaved else Image.FORMAT_R8)
	var v_plane := Image.create(6, 4, false, Image.FORMAT_R8)
	y_plane.fill(Color.WHITE)
	u_plane.fill(Color.BLACK)
	v_plane.fill(Color.BLACK)
	for y in range(4):
		for x in range(8):
			var color: Color = COLORS[(y / 2) * 2 + x / 4]
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			var u := (color.b - luma) / (2.0 * (1.0 - 0.0722))
			var v := (color.r - luma) / (2.0 * (1.0 - 0.2126))
			y_plane.set_pixel(x, y, Color((16.0 + 219.0 * luma) / 255.0, 0, 0))
			u_plane.set_pixel(x / 2, y / 2, Color((128.0 + 224.0 * u) / 255.0, (128.0 + 224.0 * v) / 255.0, 0))
			v_plane.set_pixel(x / 2, y / 2, Color((128.0 + 224.0 * v) / 255.0, 0, 0))
	material.set_shader_parameter("y_plane", ImageTexture.create_from_image(y_plane))
	material.set_shader_parameter("u_plane", ImageTexture.create_from_image(u_plane))
	material.set_shader_parameter("v_plane", ImageTexture.create_from_image(v_plane))
	material.set_shader_parameter("source_size", Vector2(8, 4))
	material.set_shader_parameter("direct_yuv", true)
	material.set_shader_parameter("interleaved_chroma", interleaved)

func check_corners(expected: Array, label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = screen.image()
	var points := [Vector2i(8, 8), Vector2i(55, 8), Vector2i(8, 55), Vector2i(55, 55)]
	for index in range(points.size()):
		var actual := image.get_pixelv(points[index])
		var color: Color = expected[index]
		if absf(actual.r - color.r) > 0.04 or absf(actual.g - color.g) > 0.04 or absf(actual.b - color.b) > 0.04:
			failures += 1
			push_error("%s corner %d: expected %s, got %s" % [label, index, color, actual])

func run_checks() -> void:
	var decoder := ClassDB.instantiate("JellyXRMpv") as Node
	root.add_child(decoder)
	screen = preload("res://tests/pc_video_test_screen.gd").new(decoder, Vector2i(64, 64))
	root.add_child(screen)
	material = screen.material
	for interleaved in [false, true]:
		make_planes(interleaved)
		material.set_shader_parameter("stereo", false)
		for rotation in range(4):
			material.set_shader_parameter("video_rotation", rotation)
			var order: Array = [[0, 1, 2, 3], [2, 0, 3, 1], [3, 2, 1, 0], [1, 3, 0, 2]][rotation]
			await check_corners(order.map(func(index: int): return COLORS[index]), "Padded YUV rotation %d, interleaved %s" % [rotation, interleaved])
		material.set_shader_parameter("video_rotation", 0)
		material.set_shader_parameter("stereo", true)
		for top_bottom in [false, true]:
			material.set_shader_parameter("top_bottom", top_bottom)
			for swap in [false, true]:
				material.set_shader_parameter("swap_eyes", swap)
				var order: Array = ([2, 3, 2, 3] if swap else [0, 1, 0, 1]) if top_bottom else ([1, 1, 3, 3] if swap else [0, 0, 2, 2])
				await check_corners(order.map(func(index: int): return COLORS[index]), "Stereo top-bottom %s, swap %s" % [top_bottom, swap])
	screen.queue_free()
	decoder.queue_free()
	await process_frame
	print("Direct YUV padded planes, rotation, and stereo checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
