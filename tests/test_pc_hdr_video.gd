extends SceneTree

var decoder: Node
var texture: Texture2D
var errors: Array[String] = []

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

func make_screen() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 192)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position.z = 1.0
	viewport.add_child(camera)
	camera.current = true
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(10, 3)
	mesh.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/pc_video.gdshader")
	material.set_shader_parameter("video_texture", texture)
	mesh.material_override = material
	viewport.add_child(mesh)
	return viewport

func run_check() -> void:
	var args := OS.get_cmdline_user_args()
	if not require(args.size() == 3, "Pass a video, reference PNG, and expected transfer"):
		return
	var reference := Image.load_from_file(args[1])
	if not require(reference != null and not reference.is_empty(), "Read the FFmpeg tone-mapping reference"):
		return
	decoder = ClassDB.instantiate("JellyframeMpv")
	root.add_child(decoder)
	decoder.texture_changed.connect(func(value: Texture2D): texture = value)
	decoder.failed.connect(func(value: String): errors.append(value))
	if not require(decoder.open_video(args[0], "", 0).is_empty(), "Open the HDR fixture"):
		return
	var deadline := Time.get_ticks_msec() + 10000
	while texture == null and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not require(texture != null and errors.is_empty(), "Vulkan produces HDR output: " + str(errors)):
		return
	decoder.set_paused(true)
	var diagnostics: Dictionary = decoder.playback_diagnostics()
	if not require(diagnostics.get("renderer") == "vulkan" and diagnostics.get("transfer") == args[2], "The decoder preserves transfer metadata: " + str(diagnostics)):
		return
	var screen := make_screen()
	await create_timer(0.2).timeout
	var raw := texture.get_image()
	var rendered := screen.get_texture().get_image()
	for index in range(10):
		var point := Vector2i(index * 64 + 32, 96)
		var expected := reference.get_pixelv(point)
		var direct := raw.get_pixelv(point)
		var visible := rendered.get_pixelv(point)
		for channel in range(3):
			if not require(absf(direct[channel] - expected[channel]) < 0.016, "HDR patch %d matches FFmpeg: expected %s, got %s" % [index, str(expected), str(direct)]):
				return
			if not require(absf(visible[channel] - expected[channel]) < 0.02, "The 3D video screen preserves patch %d brightness: expected %s, got %s" % [index, str(expected), str(visible)]):
				return
	decoder.stop_video()
	decoder.queue_free()
	screen.queue_free()
	await process_frame
	print("Vulkan HDR texture and 3D screen checks: PASS")
	quit()
